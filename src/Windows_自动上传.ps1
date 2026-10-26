# Windows ChatGPT upload assistant for Zotero 10
# WIN_SCRIPT_BUILD v0.4.0beta1 uia-20261026
# Experimental: Windows PowerShell 5.1 + Edge/Chrome + native Windows file dialog.
# Never clicks Send or calls the OpenAI API.
param(
    [Parameter(Mandatory=$true)][ValidateSet('edge','chrome')][string]$Browser,
    [Parameter(Mandatory=$true)][string]$PromptPath,
    [Parameter(Mandatory=$true)][string]$UploadListPath,
    [Parameter(Mandatory=$true)][string]$StatusPath
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ZcgWin32 {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder className, int maxCount);
}
'@

function Log([string]$Message) {
    $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) + [Environment]::NewLine
    [System.IO.File]::AppendAllText($StatusPath, $line, [System.Text.Encoding]::UTF8)
}

function Resolve-Browser {
    $name = if ($Browser -eq 'edge') { 'msedge.exe' } else { 'chrome.exe' }
    $locations = New-Object System.Collections.Generic.List[string]
    foreach ($hive in @('HKCU:', 'HKLM:')) {
        $key = $hive + '\Software\Microsoft\Windows\CurrentVersion\App Paths\' + $name
        try {
            $entry = Get-Item -LiteralPath $key -ErrorAction Stop
            $value = [string]$entry.GetValue('')
            if ($value) { [void]$locations.Add($value.Trim('"')) }
        } catch {}
    }
    foreach ($base in @($env:ProgramFiles, [Environment]::GetEnvironmentVariable('ProgramFiles(x86)'), $env:LOCALAPPDATA)) {
        if (-not $base) { continue }
        if ($Browser -eq 'edge') {
            [void]$locations.Add((Join-Path $base 'Microsoft\Edge\Application\msedge.exe'))
        } else {
            [void]$locations.Add((Join-Path $base 'Google\Chrome\Application\chrome.exe'))
        }
    }
    foreach ($p in $locations) {
        if ([System.IO.File]::Exists($p)) { return $p }
    }
    throw "找不到 $name。请安装 Edge/Chrome，或检查注册表 App Paths 和默认安装目录。"
}

function Get-ForegroundBrowser {
    $hwnd = [ZcgWin32]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { return $null }
    [uint32]$pidValue = 0
    [void][ZcgWin32]::GetWindowThreadProcessId($hwnd, [ref]$pidValue)
    try { $process = Get-Process -Id ([int]$pidValue) -ErrorAction Stop } catch { return $null }
    $expected = if ($Browser -eq 'edge') { 'msedge' } else { 'chrome' }
    if ($process.ProcessName -ne $expected) { return $null }
    $element = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
    if ($null -eq $element) { return $null }
    return [pscustomobject]@{ Handle = $hwnd; Element = $element; ProcessId = $pidValue }
}

function Wait-ChatWindow([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $candidate = Get-ForegroundBrowser
        if ($null -ne $candidate) {
            try {
                # Do not automate an arbitrary browser tab or a login window.
                if ($candidate.Element.Current.Name -match '(?i)ChatGPT') { return $candidate }
            } catch {}
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Find-UIA([System.Windows.Automation.AutomationElement]$Root,
                  [System.Windows.Automation.ControlType[]]$Types, [string]$NameRegex) {
    $conditions = New-Object 'System.Collections.Generic.List[System.Windows.Automation.Condition]'
    foreach ($type in $Types) {
        $conditions.Add([System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $type))
    }
    if ($conditions.Count -eq 1) {
        $filter = $conditions[0]
    } else {
        $filter = [System.Windows.Automation.OrCondition]::new($conditions.ToArray())
    }
    $matches = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $filter)
    foreach ($candidate in $matches) {
        try {
            if (-not $candidate.Current.IsEnabled -or $candidate.Current.IsOffscreen) { continue }
            $label = ([string]$candidate.Current.Name) + ' ' + ([string]$candidate.Current.AutomationId)
            if ($label -match $NameRegex) { return $candidate }
        } catch {}
    }
    return $null
}

function Invoke-UIA([System.Windows.Automation.AutomationElement]$Element) {
    if ($null -eq $Element) { return $false }
    try {
        $p = $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $p.Invoke()
        return $true
    } catch {}
    try {
        $p = $Element.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
        $p.DoDefaultAction()
        return $true
    } catch {}
    return $false
}

function Get-FileDialog {
    # Only trust the actual foreground native chooser from the requested browser.
    $fg = Get-ForegroundBrowser
    if ($null -eq $fg) { return $null }
    $name = [string]$fg.Element.Current.Name
    $classBuffer = New-Object System.Text.StringBuilder 256
    [void][ZcgWin32]::GetClassName($fg.Handle, $classBuffer, $classBuffer.Capacity)
    $class = $classBuffer.ToString()
    if ($class -ne '#32770' -and $name -notmatch '^(Open|打开|选择文件|Choose File|Select File)') {
        return $null
    }
    return $fg.Element
}

function Wait-FileDialog([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $dialog = Get-FileDialog
        if ($null -ne $dialog) { return $dialog }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Open-FileDialog([System.Windows.Automation.AutomationElement]$ChatWindow) {
    # Match known accessible names; stop if ChatGPT's UI has changed.
    $buttons = @([System.Windows.Automation.ControlType]::Button,
                 [System.Windows.Automation.ControlType]::MenuItem)
    $upload = Find-UIA $ChatWindow $buttons '(?i)(Attach files|Add photos.{0,8}files|Upload files|上传文件|添加照片和文件|添加附件)'
    if ($null -ne $upload -and (Invoke-UIA $upload)) {
        $dialog = Wait-FileDialog 3
        if ($null -ne $dialog) { return $dialog }
    }
    $add = Find-UIA $ChatWindow $buttons '(?i)(composer-plus-btn|Add files and more|Add photos and files|Add photos & files|添加文件|添加照片|\bAttach\b)'
    if ($null -eq $add -or -not (Invoke-UIA $add)) { return $null }
    $dialog = Wait-FileDialog 2
    if ($null -ne $dialog) { return $dialog }
    $menu = Find-UIA $ChatWindow $buttons '(?i)(Upload files|Upload from computer|Add photos.{0,8}files|上传文件|从电脑上传|添加照片和文件)'
    if ($null -eq $menu -or -not (Invoke-UIA $menu)) { return $null }
    return Wait-FileDialog 5
}

function Find-FilenameControl([System.Windows.Automation.AutomationElement]$Dialog) {
    # Common Item Dialog usually assigns automation ID 1148 to filename control.
    $idFilter = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, '1148')
    $field = $Dialog.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $idFilter)
    if ($null -eq $field) {
        $field = Find-UIA $Dialog @([System.Windows.Automation.ControlType]::Edit,
            [System.Windows.Automation.ControlType]::ComboBox) '(?i)(File name|文件名)'
    }
    if ($null -eq $field) { return $null }
    if ($field.Current.ControlType -eq [System.Windows.Automation.ControlType]::ComboBox) {
        $child = $field.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.PropertyCondition]::new(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::Edit))
        if ($null -ne $child) { return $child }
    }
    return $field
}

function Select-ExactFile([System.Windows.Automation.AutomationElement]$Dialog, [string]$FullPath) {
    if (-not [System.IO.File]::Exists($FullPath)) { throw "本地文件不存在：$FullPath" }
    $field = Find-FilenameControl $Dialog
    if ($null -eq $field) { throw '未找到原生对话框的文件名输入框；请手动上传。' }
    try {
        # Locale-independent, preserves Chinese paths, no Select All in Zotero folders.
        $value = $field.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $value.SetValue($FullPath)
        if ($value.Current.Value -ne $FullPath) { throw '文件名未正确写入' }
    } catch {
        throw "无法安全设置文件名输入框：$($_.Exception.Message)"
    }
    $ok = $Dialog.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty, '1'))
    if ($null -eq $ok) {
        $ok = Find-UIA $Dialog @([System.Windows.Automation.ControlType]::Button) '^(Open|打开)(\s|$)'
    }
    if ($null -eq $ok -or -not (Invoke-UIA $ok)) {
        throw '文件名已填写，但无法确定“打开”按钮；请手动点击，自动化已停止。'
    }
    Start-Sleep -Milliseconds 800
    if ($null -ne (Get-FileDialog)) {
        throw '文件选择器没有关闭；请检查文件名/权限并手动完成上传。'
    }
}

function Place-Prompt([System.Windows.Automation.AutomationElement]$Window, [string]$Prompt) {
    # Always put prompt on clipboard for manual Ctrl+V fallback.
    [System.Windows.Forms.Clipboard]::SetText($Prompt)
    $editor = Find-UIA $Window @([System.Windows.Automation.ControlType]::Edit) '(?i)(Ask anything|Message ChatGPT|Ask ChatGPT|向 ChatGPT 提问|询问 ChatGPT|发送消息给 ChatGPT|问任何问题|prompt-textarea|composer-input)'
    if ($null -eq $editor) {
        Log 'PROMPT_CLIPBOARD_READY composer not reliably identified; paste manually with Ctrl+V'
        return
    }
    try {
        $editor.SetFocus()
        $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
        if ($null -eq $focused -or -not $focused.Equals($editor)) {
            Log 'PROMPT_CLIPBOARD_READY composer focus unverified'
            return
        }
        # Never overwrite a draft whose text cannot be inspected.
        try {
            $p = $editor.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
            if (-not [string]::IsNullOrWhiteSpace([string]$p.Current.Value)) {
                Log 'PROMPT_CLIPBOARD_READY existing composer text; not overwriting'
                return
            }
        } catch {
            Log 'PROMPT_CLIPBOARD_READY editor content cannot be verified; paste manually'
            return
        }
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Log 'PROMPT_PASTE_ATTEMPTED verify composer on ChatGPT page'
    } catch {
        Log ('PROMPT_CLIPBOARD_READY paste skipped: ' + $_.Exception.Message)
    }
}

try {
    Log 'WIN_SCRIPT_BUILD v0.4.0beta1 uia-20261026'
    $paths = @([System.IO.File]::ReadAllLines($UploadListPath, [System.Text.Encoding]::UTF8) |
        Where-Object { $_.Length -gt 0 })
    if ($paths.Count -lt 1 -or $paths.Count -gt 10) { throw '附件清单必须包含 1–10 个文件。' }
    foreach ($p in $paths) {
        if ($p -match '[\r\n]' -or -not [System.IO.Path]::IsPathRooted($p) -or
            -not [System.IO.File]::Exists($p)) {
            throw "附件路径无效或已经删除：$p"
        }
    }
    $prompt = [System.IO.File]::ReadAllText($PromptPath, [System.Text.Encoding]::UTF8)
    if (-not $prompt.Trim()) { throw 'Prompt 为空，已停止。' }
    [System.Windows.Forms.Clipboard]::SetText($prompt)
    $exe = Resolve-Browser
    Log ('START_BROWSER ' + $Browser + ' UPLOAD_EXPECTED ' + $paths.Count)
    Start-Process -FilePath $exe -ArgumentList @('--new-window', 'https://chatgpt.com/')
    $browserWindow = Wait-ChatWindow 25
    if ($null -eq $browserWindow) {
        throw '没有检测到位于前台的 ChatGPT 浏览器窗口。请先登录 ChatGPT，再手动附加文件。'
    }
    Log 'CHAT_WINDOW_VERIFIED title contains ChatGPT'
    for ($i=0; $i -lt $paths.Count; $i++) {
        if ($null -ne (Get-FileDialog)) { throw '上一个文件选择器仍处于打开状态。' }
        [void][ZcgWin32]::SetForegroundWindow($browserWindow.Handle)
        Start-Sleep -Milliseconds 350
        $foreground = Wait-ChatWindow 2
        if ($null -eq $foreground) { throw 'ChatGPT 不是前台窗口；为防止误操作已停止。' }
        Log ('FILE_START ' + ($i+1) + '/' + $paths.Count)
        $dialog = Open-FileDialog $foreground.Element
        if ($null -eq $dialog) { throw '无法通过 UI Automation 打开 ChatGPT 文件选择器。请手动上传；网页可能已更新。' }
        Select-ExactFile $dialog $paths[$i]
        Log ('FILE_PICKER_CLOSED ' + ($i+1) + '/' + $paths.Count)
        Start-Sleep -Milliseconds 1100
    }
    [void][ZcgWin32]::SetForegroundWindow($browserWindow.Handle)
    $foreground = Wait-ChatWindow 2
    if ($null -ne $foreground) { Place-Prompt $foreground.Element $prompt }
    else { [System.Windows.Forms.Clipboard]::SetText($prompt); Log 'PROMPT_CLIPBOARD_READY chat window not foreground' }
    Log ('ALL_PICKERS_CLOSED ' + $paths.Count)
    Log 'NO_AUTO_SEND verify files and normal Chat mode before submitting'
} catch {
    try {
        $p = [System.IO.File]::ReadAllText($PromptPath, [System.Text.Encoding]::UTF8)
        if (-not [string]::IsNullOrWhiteSpace($p)) {
            [System.Windows.Forms.Clipboard]::SetText($p)
        }
    } catch {}
    Log ('ERROR ' + $_.Exception.Message)
    exit 1
}
