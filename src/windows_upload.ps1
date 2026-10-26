# Windows ChatGPT upload assistant for Zotero 10
# WIN_SCRIPT_BUILD v0.4.0beta4 uia-20261026
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
# The first marker is written before UI Automation assemblies are loaded.
# Missing this marker means PowerShell failed before entering the script.
try {
    [System.IO.File]::AppendAllText($StatusPath,
        ("POWERSHELL_ENTERED " + [DateTime]::Now.ToString("s") + [Environment]::NewLine),
        [System.Text.Encoding]::UTF8)
} catch { }
try {
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
} catch {
    try {
        [System.IO.File]::AppendAllText($StatusPath,
            ("INITIALIZATION_ERROR " + $_.Exception.Message + [Environment]::NewLine),
            [System.Text.Encoding]::UTF8)
    } catch {}
    exit 1
}

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
    # ChatGPT typically has a composer "+" button opening an upload menu.
    # Avoid clicking the same toggle twice (previous uploader reopened/closed it).
    $buttons = @([System.Windows.Automation.ControlType]::Button,
                 [System.Windows.Automation.ControlType]::MenuItem)
    $plusLabels = '(?i)(composer-plus-btn|Add files and more|Add photos and files|Add photos & files|Attach files|添加文件|添加照片|添加附件|附件|Add photos|Upload files)'
    $uploadLabels = '(?i)(Upload files|Upload from computer|Add photos.{0,8}files|从电脑上传|上传文件|添加照片和文件)'
    $plus = Find-UIA $ChatWindow $buttons $plusLabels
    if ($null -eq $plus) {
        Log 'UPLOAD_PLUS_NOT_FOUND'
        Log-UploadCandidates $ChatWindow
        return $null
    }
    Log ('UPLOAD_PLUS_FOUND name=' + [string]$plus.Current.Name)
    if (-not (Invoke-UIA $plus)) {
        Log 'UPLOAD_PLUS_INVOKE_FAILED'
        Log-UploadCandidates $ChatWindow
        return $null
    }
    Log 'UPLOAD_PLUS_CLICKED'
    $dialog = Wait-FileDialog 3
    if ($null -ne $dialog) { Log 'PICKER_OPEN_DIRECT'; return $dialog }

    # The first click usually opens a menu. Retry querying the *new* tree.
    $menu = Find-UIA $ChatWindow $buttons $uploadLabels
    if ($null -eq $menu) {
        Log 'UPLOAD_MENU_NOT_FOUND'
        Log-UploadCandidates $ChatWindow
        return $null
    }
    Log ('UPLOAD_MENU_FOUND name=' + [string]$menu.Current.Name)
    if (-not (Invoke-UIA $menu)) {
        Log 'UPLOAD_MENU_INVOKE_FAILED'
        return $null
    }
    Log 'UPLOAD_MENU_CLICKED'
    $dialog = Wait-FileDialog 7
    if ($null -eq $dialog) { Log 'PICKER_NOT_DETECTED_AFTER_UPLOAD_MENU' }
    return $dialog
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

function Read-EditorText([System.Windows.Automation.AutomationElement]$Editor) {
    try {
        $p = $Editor.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        return [string]$p.Current.Value
    } catch {}
    try {
        $p = $Editor.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        return [string]$p.DocumentRange.GetText(-1)
    } catch {}
    return $null
}

function Place-Prompt([System.Windows.Automation.AutomationElement]$Window, [string]$Prompt) {
    # Clipboard fallback ALWAYS works without UI Automation.
    [System.Windows.Forms.Clipboard]::SetText($Prompt)
    $pattern = '(?i)(Ask anything|Message ChatGPT|Ask ChatGPT|向 ChatGPT 提问|询问 ChatGPT|发送消息给 ChatGPT|问任何问题|prompt-textarea|composer-input|message input|Write a message|Ask a question)'
    $editor = $null
    for ($attempt=0; $attempt -lt 8; $attempt++) {
        $editor = Find-UIA $Window @([System.Windows.Automation.ControlType]::Edit) $pattern
        if ($null -ne $editor) { break }
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $editor) {
        Log 'PROMPT_CLIPBOARD_READY composer not identified in Edit controls; Ctrl+V manually'
        return
    }
    try {
        $editor.SetFocus()
        $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
        if ($null -eq $focused -or -not $focused.Equals($editor)) {
            Log 'PROMPT_CLIPBOARD_READY composer focus unverified'
            return
        }
        $oldText = Read-EditorText $editor
        if ($null -eq $oldText) {
            # Uninspectable composer: don't risk overwriting another draft.
            Log 'PROMPT_CLIPBOARD_READY editor text unreadable; paste manually'
            return
        }
        if (-not [string]::IsNullOrWhiteSpace($oldText)) {
            Log 'PROMPT_CLIPBOARD_READY editor not empty; not overwriting'
            return
        }
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 600
        $readback = Read-EditorText $editor
        if ($null -ne $readback -and $readback.Contains($Prompt.Substring(0,[Math]::Min($Prompt.Length,30)))) {
            Log 'PROMPT_PASTE_VERIFIED (first 30 chars)'
        } else {
            Log 'PROMPT_PASTE_UNVERIFIED check ChatGPT composer and paste Ctrl+V manually'
        }
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
    # Chromium accessibility can be disabled until a screen reader is detected.
    # The flag activates the renderer's UIA tree for both Edge and Chrome.
    Start-Process -FilePath $exe -ArgumentList @('--force-renderer-accessibility', '--new-window', 'https://chatgpt.com/')
    $browserWindow = Wait-ChatWindow 25
    if ($null -eq $browserWindow) {
        throw '没有检测到位于前台的 ChatGPT 浏览器窗口。请先登录 ChatGPT，再手动附加文件。'
    }
    Log 'CHAT_WINDOW_VERIFIED title contains ChatGPT'
    # Prompt is independent of uploads; a failed picker must never suppress it.
    Place-Prompt $browserWindow.Element $prompt
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
