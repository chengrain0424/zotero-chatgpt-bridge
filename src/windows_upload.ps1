# Windows ChatGPT upload assistant for Zotero 10
# WIN_SCRIPT_BUILD v0.4.0 uia-20261027
# Experimental: Windows PowerShell 5.1 + Edge/Chrome + native Windows file dialog.
# Never clicks Send or calls the OpenAI API.
param(
    [Parameter(Mandatory=$true)][ValidateSet('edge','chrome')][string]$Browser,
    [Parameter(Mandatory=$true)][string]$PromptPath,
    [Parameter(Mandatory=$true)][string]$UploadListPath,
    [Parameter(Mandatory=$true)][string]$StatusPath,
    [switch]$SelfTestStaging
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
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("kernel32.dll", EntryPoint = "CreateHardLinkW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CreateHardLink(string newFileName, string existingFileName, IntPtr securityAttributes);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hWnd);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr SendMessageTimeoutGet(IntPtr hWnd, uint msg, UIntPtr wParam,
        StringBuilder text, uint flags, uint timeout, out UIntPtr result);

    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO info);
    [StructLayout(LayoutKind.Sequential)] public struct RECT {
        public int Left, Top, Right, Bottom;
    }
    [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
        public uint cbSize;
        public uint flags;
        public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder className, int maxCount);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT pt);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);

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

function Prepare-UploadStaging([string[]]$SourcePaths, [string]$LogPath) {
    # Each picker sees ONE vetted attachment, never Zotero reader state files.
    # Staging is task-local; prefer a hard link (no duplicate PDF data).
    $taskRoot=[System.IO.Path]::GetDirectoryName($LogPath)
    $stageRoot=[System.IO.Path]::Combine($taskRoot,'picker_staging')
    [System.IO.Directory]::CreateDirectory($stageRoot) | Out-Null
    $allowed=@('.pdf','.doc','.docx','.xls','.xlsx','.csv','.txt','.ppt','.pptx','.md')
    for($i=0; $i -lt $SourcePaths.Count; $i++) {
        $src=$SourcePaths[$i]
        if(-not [System.IO.File]::Exists($src)) { throw 'Zotero 附件路径不存在；未打开 ChatGPT。' }
        $filename=[System.IO.Path]::GetFileName($src)
        $ext=[System.IO.Path]::GetExtension($filename).ToLowerInvariant()
        if($filename.StartsWith('.') -or $allowed -notcontains $ext) {
            throw '附件扩展名不是受支持的文档类型，已阻止非论文文件上传。'
        }
        if($i -eq 0 -and $ext -ne '.pdf') {
            throw '第一份正文附件不是 PDF，已停止上传。'
        }
        $size=([System.IO.FileInfo]::new($src)).Length
        if($size -lt 1 -or $size -gt 104857600) {
            throw '附件大小无效或超过 100 MB，已停止上传。'
        }
        if($ext -eq '.pdf') {
            $stream=[System.IO.File]::OpenRead($src)
            try {
                $bytes=New-Object byte[] 5
                if($stream.Read($bytes,0,5) -ne 5 -or
                    [System.Text.Encoding]::ASCII.GetString($bytes) -cne '%PDF-') {
                    throw '待上传文件不具有 PDF 文件头；已停止上传。'
                }
            } finally { $stream.Dispose() }
        }
        $single=[System.IO.Path]::Combine($stageRoot,('{0:D2}' -f ($i+1)))
        [System.IO.Directory]::CreateDirectory($single) | Out-Null
        $target=[System.IO.Path]::Combine($single,$filename)
        if([System.IO.File]::Exists($target)) {
            throw '附件暂存目录已存在相同文件；为避免误上传已停止。'
        }
        $mode='hardlink'
        if(-not [ZcgWin32]::CreateHardLink($target,$src,[IntPtr]::Zero)) {
            $mode='copy'
            [System.IO.File]::Copy($src,$target,$false)
        }
        if(-not [System.IO.File]::Exists($target) -or
           ([System.IO.FileInfo]::new($target)).Length -ne $size) {
            throw '暂存附件大小验证失败；停止上传。'
        }
        $entries=@([System.IO.Directory]::GetFileSystemEntries($single))
        if($entries.Count -ne 1 -or $entries[0] -ne $target) {
            throw '文件选择目录不止一份附件；拒绝自动上传。'
        }
        Log ('STAGED_SINGLE_FILE index=' + ($i+1) + ' extension=' + $ext +
             ' bytes=' + $size + ' method=' + $mode)
        Write-Output $target
    }
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

function Test-UIATarget([System.Windows.Automation.AutomationElement]$Expected,
                        [System.Windows.Automation.AutomationElement]$AtPoint) {
    if($null -eq $Expected -or $null -eq $AtPoint) { return $false }
    # Chromium's DOM can expose child icons only in RawView, not ControlView.
    # Either walker must lead from the hit-tested point to the exact control.
    foreach($walker in @([System.Windows.Automation.TreeWalker]::ControlViewWalker,
                         [System.Windows.Automation.TreeWalker]::RawViewWalker)) {
        $node=$AtPoint
        for($depth=0; $depth -lt 16 -and $null -ne $node; $depth++) {
            try {
                if($node.Equals($Expected)) { return $true }
                $parent=$walker.GetParent($node)
                if($null -ne $parent -and $parent.Equals($node)) { break }
                $node=$parent
            } catch { break }
        }
    }
    return $false
}

function Invoke-UIA([System.Windows.Automation.AutomationElement]$Element) {
    if ($null -eq $Element) { return $false }
    try {
        if (-not $Element.Current.IsEnabled -or $Element.Current.IsOffscreen) { return $false }
        $p = $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $p.Invoke()
        Log 'UIA_ACTIVATED via=InvokePattern'
        return $true
    } catch {
        Log ('UIA_INVOKE_UNAVAILABLE ' + $_.Exception.GetType().Name)
    }
    try {
        $p = $Element.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
        $p.DoDefaultAction()
        Log 'UIA_ACTIVATED via=LegacyAccessible'
        return $true
    } catch {
        Log ('UIA_LEGACY_UNAVAILABLE ' + $_.Exception.GetType().Name)
    }

    # Keyboard fallback: only send Space if keyboard focus can be verified.
    try {
        $Element.SetFocus()
        Start-Sleep -Milliseconds 100
        $focus = [System.Windows.Automation.AutomationElement]::FocusedElement
        if ($null -ne $focus -and $focus.Equals($Element)) {
            [System.Windows.Forms.SendKeys]::SendWait('{SPACE}')
            Log 'UIA_ACTIVATED via=KeyboardSpace'
            return $true
        }
    } catch {
        Log ('UIA_KEYBOARD_UNAVAILABLE ' + $_.Exception.GetType().Name)
    }

    return (Click-UIA-Verified $Element)
}


function Click-UIA-Verified([System.Windows.Automation.AutomationElement]$Element) {
    # Attachment chips can shift the composer and cover its + button's centre
    # during an animation. Check multiple INTERNAL points. A physical click is
    # permitted only where UIA confirms this exact element/its descendant.
    try {
        if($null -eq $Element -or -not $Element.Current.IsEnabled -or
           $Element.Current.IsOffscreen) { return $false }
        $r=$Element.Current.BoundingRectangle
        if($r.Width -lt 8 -or $r.Height -lt 8) { return $false }
        $offsets=@(@(0.5,0.5),@(0.3,0.5),@(0.7,0.5),
                   @(0.5,0.3),@(0.5,0.7),@(0.3,0.3),@(0.7,0.3),
                   @(0.3,0.7),@(0.7,0.7))
        $hitPoint=$null
        $sample=0
        foreach($fraction in $offsets) {
            $x=[int]($r.Left + $r.Width*$fraction[0])
            $y=[int]($r.Top + $r.Height*$fraction[1])
            try {
                $hit=[System.Windows.Automation.AutomationElement]::FromPoint(
                    [System.Windows.Point]::new($x,$y))
                if(Test-UIATarget $Element $hit) {
                    $hitPoint=[pscustomobject]@{X=$x;Y=$y}
                    break
                }
            } catch {}
            $sample++
        }
        if($null -eq $hitPoint) {
            Log 'UIA_MOUSE_TARGET_MISMATCH no-verified-point'
            return $false
        }
        $previous=New-Object ZcgWin32+POINT
        $hasPrevious=[ZcgWin32]::GetCursorPos([ref]$previous)
        try {
            [void][ZcgWin32]::SetCursorPos($hitPoint.X,$hitPoint.Y)
            Start-Sleep -Milliseconds 110
            $hitAgain=[System.Windows.Automation.AutomationElement]::FromPoint(
                [System.Windows.Point]::new($hitPoint.X,$hitPoint.Y))
            if(-not (Test-UIATarget $Element $hitAgain)) {
                Log 'UIA_MOUSE_TARGET_CHANGED stopped'
                return $false
            }
            [ZcgWin32]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
            [ZcgWin32]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
            Log ('UIA_ACTIVATED via=VerifiedMouseClick sample=' + $sample)
            return $true
        } finally {
            if($hasPrevious) {
                [void][ZcgWin32]::SetCursorPos($previous.X,$previous.Y)
            }
        }
    } catch {
        Log ('UIA_MOUSE_UNAVAILABLE ' + $_.Exception.GetType().Name)
    }
    return $false
}

function Log-UploadCandidates([System.Windows.Automation.AutomationElement]$Window) {
    # Only record toolbar/button labels relevant to uploading. Do not dump chat
    # content, document text, URLs, or clipboard/prompt contents.
    try {
        foreach ($type in @([System.Windows.Automation.ControlType]::Button,
                            [System.Windows.Automation.ControlType]::MenuItem,
                            [System.Windows.Automation.ControlType]::Edit,
                            [System.Windows.Automation.ControlType]::Document)) {
            $filter = [System.Windows.Automation.PropertyCondition]::new(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,$type)
            $items = $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants,$filter)
            Log ('UIA_COUNT type=' + $type.ProgrammaticName + ' count=' + $items.Count)
            $logged=0
            foreach ($item in $items) {
                if ($logged -ge 15) { break }
                try {
                    if ($item.Current.IsOffscreen) { continue }
                    $label=[string]$item.Current.Name
                    $id=[string]$item.Current.AutomationId
                    if (($label + ' ' + $id) -notmatch '(?i)(add|upload|file|attach|composer|photo|plus|message|prompt|ask|文件|上传|添加|附件|照片|消息|提问)') { continue }
                    $label=($label -replace '[\r\n]',' ')
                    $id=($id -replace '[\r\n]',' ')
                    Log ('UIA_CANDIDATE type=' + $type.ProgrammaticName + ' label=' +
                        $label.Substring(0,[Math]::Min(70,$label.Length)) + '; id=' +
                        $id.Substring(0,[Math]::Min(60,$id.Length)))
                    $logged++
                } catch {}
            }
        }
    } catch {
        Log ('UIA_CANDIDATES_ERROR ' + $_.Exception.GetType().Name)
    }
}

function Get-WindowInfo([IntPtr]$Handle) {
    if ($Handle -eq [IntPtr]::Zero) { return $null }
    $classBuffer = New-Object System.Text.StringBuilder 256
    [void][ZcgWin32]::GetClassName($Handle,$classBuffer,$classBuffer.Capacity)
    [uint32]$processId = 0
    [void][ZcgWin32]::GetWindowThreadProcessId($Handle,[ref]$processId)
    $procName = 'unknown'
    try { $procName = (Get-Process -Id ([int]$processId) -ErrorAction Stop).ProcessName } catch {}
    return [pscustomobject]@{
        Handle=$Handle; Class=$classBuffer.ToString(); ProcessName=$procName
        Owner=[ZcgWin32]::GetWindow($Handle,4)
    }
}

function Test-OwnedByChat([IntPtr]$Handle) {
    # Only interact with modal pickers owned by the ChatGPT Edge window that
    # this helper opened. Never type paths into unrelated system dialogs.
    if ($script:ChatWindowHandle -eq [IntPtr]::Zero) { return $false }
    $owner = [ZcgWin32]::GetWindow($Handle,4)
    for ($depth=0; $depth -lt 8 -and $owner -ne [IntPtr]::Zero; $depth++) {
        if ($owner -eq $script:ChatWindowHandle) { return $true }
        $next = [ZcgWin32]::GetWindow($owner,4)
        if ($next -eq $owner) { break }
        $owner=$next
    }
    return $false
}

function Log-ForegroundState([string]$Stage) {
    try {
        $info = Get-WindowInfo ([ZcgWin32]::GetForegroundWindow())
        if ($null -eq $info) { Log ('WINDOW_STATE ' + $Stage + ' none'); return }
        $owned = Test-OwnedByChat $info.Handle
        $same = $info.Handle -eq $script:ChatWindowHandle
        # Do not log window titles, document names, or file paths.
        Log ('WINDOW_STATE ' + $Stage + ' class=' + $info.Class +
            ' process=' + $info.ProcessName + ' ownedByChat=' + $owned +
            ' sameChatWindow=' + $same)
    } catch { Log ('WINDOW_STATE_ERROR ' + $_.Exception.GetType().Name) }
}

function Get-FileDialog {
    # The native picker is not guaranteed to have Edge as its foreground
    # process; verify window ownership instead of requiring Get-ForegroundBrowser.
    $handle = [ZcgWin32]::GetForegroundWindow()
    $info = Get-WindowInfo $handle
    if ($null -eq $info -or -not (Test-OwnedByChat $handle)) { return $null }
    if ($info.Class -ne '#32770') { return $null }
    try {
        $element=[System.Windows.Automation.AutomationElement]::FromHandle($handle)
        if ($null -eq $element) { return $null }
        # Confirm the native filename widget belongs to this picker; resolve
        # its real editable child later, once, to avoid noisy repeated scans.
        $filenameWidget = $element.FindFirst(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.PropertyCondition]::new(
                [System.Windows.Automation.AutomationElement]::AutomationIdProperty, '1148'))
        if ($null -eq $filenameWidget) { return $null }
        return $element
    } catch { return $null }
}

function Wait-FileDialog([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    $elapsed=0
    do {
        $dialog=Get-FileDialog
        if ($null -ne $dialog) {
            Log 'PICKER_CONFIRMED ownership-and-filename-field'
            return $dialog
        }
        Start-Sleep -Milliseconds 250
        $elapsed++
        if ($elapsed % 12 -eq 0) { Log-ForegroundState 'waiting-for-picker' }
    } while ((Get-Date) -lt $deadline)
    Log-ForegroundState 'picker-timeout'
    return $null
}

function Log-PlusButtonState([System.Windows.Automation.AutomationElement]$Window) {
    # This is diagnostic only. Read state even if disabled/offscreen, since
    # Find-UIA deliberately excludes those controls from interaction.
    try {
        $filter = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button)
        $buttons = $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $filter)
        $found = 0
        foreach ($button in $buttons) {
            try {
                $name = [string]$button.Current.Name
                if ($name -notmatch '(?i)^(Add files and more|Attach files|添加文件|添加附件|添加照片|Add photos and files|Add photos & files)$') { continue }
                $found++
                $enabled=$button.Current.IsEnabled
                $offscreen=$button.Current.IsOffscreen
                $r=$button.Current.BoundingRectangle
                Log ('UPLOAD_PLUS_STATE enabled=' + $enabled + ' offscreen=' +
                    $offscreen + ' width=' + [Math]::Round($r.Width) +
                    ' height=' + [Math]::Round($r.Height))
            } catch { Log ('UPLOAD_PLUS_STATE_READ_ERROR ' + $_.Exception.GetType().Name) }
        }
        if ($found -eq 0) { Log 'UPLOAD_PLUS_STATE no-matching-button' }
    } catch { Log ('UPLOAD_PLUS_STATE_ERROR ' + $_.Exception.GetType().Name) }
}

function Wait-ComposerPlus([int]$ItemIndex,[int]$Total) {
    # After the first file, ChatGPT can rerender the composer and temporarily
    # disable Add files while it prepares the attachment. Resolve a NEW UIA
    # root on every poll; never reuse an element from before a previous picker.
    $types=@([System.Windows.Automation.ControlType]::Button,
             [System.Windows.Automation.ControlType]::MenuItem)
    $plusLabels='(?i)(composer-plus-btn|Add files and more|Add photos and files|Add photos & files|Attach files|添加文件|添加照片|添加附件|附件|Add photos|Upload files)'
    $limit=if($ItemIndex -gt 1) { 50 } else { 20 }
    $deadline=(Get-Date).AddSeconds($limit)
    $poll=0
    do {
        $fg=Get-ForegroundBrowser
        if($null -eq $fg -or $fg.Handle -ne $script:ChatWindowHandle) {
            Log ('MULTI_WAIT_WRONG_WINDOW item=' + $ItemIndex)
            return $null
        }
        try {
            if($fg.Element.Current.Name -notmatch '(?i)ChatGPT') {
                Log ('MULTI_WAIT_NOT_CHAT item=' + $ItemIndex)
                return $null
            }
            $plus=Find-UIA $fg.Element $types $plusLabels
            if($null -ne $plus) {
                Log ('MULTI_PLUS_READY item=' + $ItemIndex + '/' + $Total +
                    ' polls=' + $poll)
                return [pscustomobject]@{Root=$fg.Element; Button=$plus}
            }
            if($poll -eq 0 -or $poll % 10 -eq 0) {
                Log ('MULTI_PLUS_WAIT item=' + $ItemIndex + '/' + $Total +
                    ' polls=' + $poll)
                Log-PlusButtonState $fg.Element
            }
        } catch {
            Log ('MULTI_PLUS_POLL_RETRY ' + $_.Exception.GetType().Name)
        }
        $poll++
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    Log ('MULTI_PLUS_TIMEOUT item=' + $ItemIndex + '/' + $Total)
    return $null
}

function Open-FileDialog([int]$ItemIndex,[int]$Total) {
    $types=@([System.Windows.Automation.ControlType]::Button,
             [System.Windows.Automation.ControlType]::MenuItem)
    $uploadLabels='(?i)(Upload files|Upload from computer|Add photos.{0,8}files|从电脑上传|上传文件|添加照片和文件)'
    # Do NOT InvokePattern a second time; actual Edge works with trusted
    # physical clicks. After an attachment chip changes the layout, requery
    # the plus button and retry only if NO physical click was dispatched.
    $clicked=$false
    for($clickAttempt=1; $clickAttempt -le 12; $clickAttempt++) {
        $ready=Wait-ComposerPlus $ItemIndex $Total
        if($null -eq $ready) {
            Log ('UPLOAD_PLUS_NOT_READY item=' + $ItemIndex)
            return $null
        }
        $plus=$ready.Button
        Log ('UPLOAD_PLUS_FOUND item=' + $ItemIndex +
             ' attempt=' + $clickAttempt + ' name=' + [string]$plus.Current.Name)
        if(Click-UIA-Verified $plus) {
            $clicked=$true
            break
        }
        Log ('UPLOAD_PLUS_HIT_RETRY item=' + $ItemIndex +
             ' attempt=' + $clickAttempt)
        Start-Sleep -Milliseconds 550
    }
    if(-not $clicked) {
        Log ('UPLOAD_PLUS_HIT_TIMEOUT item=' + $ItemIndex)
        Log-UploadCandidates ([System.Windows.Automation.AutomationElement]::FromHandle($script:ChatWindowHandle))
        return $null
    }
    Log ('UPLOAD_PLUS_CLICKED item=' + $ItemIndex)
    $dialog=Wait-FileDialog 2
    if($null -ne $dialog) { Log 'PICKER_OPEN_DIRECT'; return $dialog }

    # Requery the browser tree after the menu opens. The stale composer root
    # can no longer be trusted after selecting the previous attachment.
    $window=Get-ForegroundBrowser
    if($null -eq $window -or $window.Handle -ne $script:ChatWindowHandle) {
        Log ('UPLOAD_MENU_WRONG_WINDOW item=' + $ItemIndex)
        return $null
    }
    $menu=$null
    for($attempt=0; $attempt -lt 10; $attempt++) {
        $root=[System.Windows.Automation.AutomationElement]::FromHandle($script:ChatWindowHandle)
        $menu=Find-UIA $root $types $uploadLabels
        if($null -ne $menu) { break }
        Start-Sleep -Milliseconds 200
    }
    if($null -eq $menu) {
        Log ('UPLOAD_MENU_NOT_FOUND item=' + $ItemIndex)
        Log-UploadCandidates $root
        return $null
    }
    Log ('UPLOAD_MENU_FOUND item=' + $ItemIndex + ' name=' + [string]$menu.Current.Name)
    Log ('UPLOAD_MENU_TARGET type=' + $menu.Current.ControlType.ProgrammaticName +
         ' enabled=' + $menu.Current.IsEnabled +
         ' offscreen=' + $menu.Current.IsOffscreen)
    # Retain the verified physical click that worked on real Edge. InvokePattern
    # closed the menu without opening the native picker on this user's system.
    if(-not (Click-UIA-Verified $menu)) {
        Log ('UPLOAD_MENU_MOUSE_NOT_VERIFIED item=' + $ItemIndex)
        return $null
    }
    Log ('UPLOAD_MENU_PHYSICAL_CLICK item=' + $ItemIndex)
    $dialog=Wait-FileDialog 8
    if($null -ne $dialog) { return $dialog }
    Log ('PICKER_NOT_DETECTED_AFTER_PHYSICAL_MENU_CLICK item=' + $ItemIndex)
    Log-ForegroundState 'picker-final'
    return $null
}

function Get-VerifiedDialogFocus([System.Windows.Automation.AutomationElement]$Dialog) {
    $active=Get-FileDialog
    if ($null -eq $active -or -not $active.Equals($Dialog)) { return $null }
    $dlg=[ZcgWin32]::GetForegroundWindow()
    [uint32]$processId=0
    [uint32]$threadId=[ZcgWin32]::GetWindowThreadProcessId($dlg,[ref]$processId)
    if ($threadId -eq 0) { return $null }
    $info=New-Object ZcgWin32+GUITHREADINFO
    $info.cbSize=[uint32][System.Runtime.InteropServices.Marshal]::SizeOf(
        [type][ZcgWin32+GUITHREADINFO])
    if (-not [ZcgWin32]::GetGUIThreadInfo($threadId,[ref]$info)) { return $null }
    if ($info.hwndFocus -eq [IntPtr]::Zero) { return $null }
    $node=$info.hwndFocus
    $belongs=$false
    $filenameAncestor=$false
    $classes=New-Object 'System.Collections.Generic.List[string]'
    for($depth=0; $depth -lt 20 -and $node -ne [IntPtr]::Zero; $depth++) {
        if($node -eq $dlg) { $belongs=$true; break }
        $classBuffer=New-Object System.Text.StringBuilder 128
        [void][ZcgWin32]::GetClassName($node,$classBuffer,$classBuffer.Capacity)
        $id=[ZcgWin32]::GetDlgCtrlID($node)
        if($id -eq 1148) { $filenameAncestor=$true }
        if($classes.Count -lt 12) { $classes.Add(($classBuffer.ToString()+'#'+$id)) }
        $parent=[ZcgWin32]::GetParent($node)
        if($parent -eq $node) { break }
        $node=$parent
    }
    $focusClass=if($classes.Count -gt 0) { $classes[0].Split('#')[0] } else { '' }
    return [pscustomobject]@{
        InPicker=$belongs; Has1148=$filenameAncestor;
        IsEdit=($focusClass -eq 'Edit'); FocusHandle=$info.hwndFocus;
        Classes=[string]::Join('>', $classes.ToArray())
    }
}

function Get-NativeFileNameFocus([System.Windows.Automation.AutomationElement]$Dialog) {
    $info=Get-VerifiedDialogFocus $Dialog
    if($null -eq $info) { return $null }
    $verified=$info.InPicker -and $info.Has1148 -and $info.IsEdit
    Log ('FILENAME_WIN32_FOCUS inPicker=' + $info.InPicker +
        ' has1148=' + $info.Has1148 + ' edit=' + $info.IsEdit +
        ' classes=' + $info.Classes)
    return [pscustomobject]@{
        Verified=$verified; FocusHandle=$info.FocusHandle
    }
}

function Read-NativeEditText([IntPtr]$Handle) {
    # Real WM_GETTEXT against the native Edit HWND, NOT clipboard readback.
    # On timeout/UIPI failure return null and fail closed.
    if($Handle -eq [IntPtr]::Zero) { return $null }
    $buffer=New-Object System.Text.StringBuilder 32768
    $messageResult=[UIntPtr]::Zero
    try {
        $ok=[ZcgWin32]::SendMessageTimeoutGet($Handle,0x000D,
            [UIntPtr]([uint32]$buffer.Capacity),$buffer,0x0002,1200,
            [ref]$messageResult)
        if($ok -eq [IntPtr]::Zero) { return $null }
        return $buffer.ToString()
    } catch { return $null }
}

function Test-NativePathEqual([string]$Actual,[string]$Expected) {
    if([string]::IsNullOrWhiteSpace($Actual) -or
       [string]::IsNullOrWhiteSpace($Expected)) { return $false }
    try {
        $a=[System.IO.Path]::GetFullPath($Actual.Trim('"')).TrimEnd('\')
        $b=[System.IO.Path]::GetFullPath($Expected.Trim('"')).TrimEnd('\')
        return [string]::Equals($a,$b,[System.StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Get-AddressBarFocus([System.Windows.Automation.AutomationElement]$Dialog) {
    $info=Get-VerifiedDialogFocus $Dialog
    if($null -eq $info) { return $null }
    # Address location must be an Edit in the *verified native chooser*, not
    # the filename control (1148), search box, or any browser field.
    $addressShape=$info.Classes -match '(?i)(ComboBox|Address Band Root|Breadcrumb|ToolbarWindow32)'
    $verified=$info.InPicker -and $info.IsEdit -and -not $info.Has1148 -and $addressShape
    Log ('ADDRESS_FOCUS inPicker=' + $info.InPicker + ' edit=' +
        $info.IsEdit + ' has1148=' + $info.Has1148 +
        ' addressShape=' + $addressShape + ' classes=' + $info.Classes)
    return [pscustomobject]@{
        Verified=$verified; FocusHandle=$info.FocusHandle
    }
}

function Focus-AddressBar([System.Windows.Automation.AutomationElement]$Dialog) {
    if($null -eq (Get-FileDialog)) { return $null }
    # Ctrl+L and Alt+D are Explorer's standard location-bar shortcuts.
    foreach($shortcut in @('^l','%d')) {
        try { [System.Windows.Forms.SendKeys]::SendWait($shortcut) } catch { continue }
        Start-Sleep -Milliseconds 170
        $focus=Get-AddressBarFocus $Dialog
        if($null -ne $focus -and $focus.Verified) {
            Log ('ADDRESS_FOCUSED shortcut=' + $shortcut)
            return $focus
        }
    }
    Log 'ADDRESS_FOCUS_UNVERIFIED stopped'
    return $null
}

function Navigate-ToExactFolder([System.Windows.Automation.AutomationElement]$Dialog,
                                [string]$FolderPath) {
    if(-not [System.IO.Directory]::Exists($FolderPath)) {
        throw 'PDF 所在目录已不存在，停止选择文件。'
    }
    Log 'ADDRESS_NAVIGATION_BEGIN'
    $focus=Focus-AddressBar $Dialog
    if($null -eq $focus) { throw '无法验证文件选择窗口的地址栏焦点；未输入目录。' }
    $check=Get-AddressBarFocus $Dialog
    if($null -eq $check -or -not $check.Verified -or
       $check.FocusHandle -ne $focus.FocusHandle) {
        throw '地址栏焦点发生变化，未输入目录。'
    }
    try {
        [System.Windows.Forms.Clipboard]::SetText($FolderPath)
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 220
        $text=Read-NativeEditText $focus.FocusHandle
        if(-not (Test-NativePathEqual $text $FolderPath)) {
            Log 'ADDRESS_PASTE_READBACK_FAILED'
            throw '无法直接读取并确认地址栏内的目标目录；未执行导航。'
        }
        Log 'ADDRESS_PASTE_VERIFIED'
        if($null -eq (Get-FileDialog)) {
            throw '文件对话框焦点已丢失，未执行目录导航。'
        }
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        Start-Sleep -Milliseconds 650
        if($null -eq (Get-FileDialog)) {
            throw '目录导航后文件对话框消失，停止上传。'
        }
        # Re-open location bar: it should expose the ACTIVE directory, not
        # merely the path we entered before pressing Enter.
        $after=Focus-AddressBar $Dialog
        if($null -eq $after) { throw '目录导航后无法读取地址栏。' }
        $actual=Read-NativeEditText $after.FocusHandle
        if(-not (Test-NativePathEqual $actual $FolderPath)) {
            Log 'ADDRESS_NAVIGATION_NOT_VERIFIED'
            throw '文件选择器未确认进入目标 PDF 文件夹，停止上传。'
        }
        Log 'FOLDER_NAVIGATED_VERIFIED'
    } finally {
        # Restore the prepared Prompt on the clipboard for manual fallback.
        try {
            if(-not [string]::IsNullOrEmpty($script:PromptValue)) {
                [System.Windows.Forms.Clipboard]::SetText($script:PromptValue)
            }
        } catch {}
    }
}

function Write-FilenameUsingNativeFocus([System.Windows.Automation.AutomationElement]$Dialog,
                                        [string]$FileName) {
    # After verifying the directory, only type the basename in the native
    # 'File name' Edit#1148 and inspect real HWND text via WM_GETTEXT.
    if($null -eq (Get-FileDialog)) { return $false }
    Log 'FILENAME_NATIVE_ALT_N_ATTEMPT'
    try { [System.Windows.Forms.SendKeys]::SendWait('%n') }
    catch { Log ('FILENAME_NATIVE_ALT_N_ERROR '+$_.Exception.GetType().Name); return $false }
    Start-Sleep -Milliseconds 160
    $focus=Get-NativeFileNameFocus $Dialog
    if($null -eq $focus -or -not $focus.Verified) {
        Log 'FILENAME_NATIVE_FOCUS_UNVERIFIED stopped'
        return $false
    }
    Log 'FILENAME_NATIVE_FOCUS_VERIFIED'
    try {
        [System.Windows.Forms.Clipboard]::SetText($FileName)
        $check=Get-NativeFileNameFocus $Dialog
        if($null -eq $check -or -not $check.Verified -or
            $check.FocusHandle -ne $focus.FocusHandle) {
            Log 'FILENAME_NATIVE_FOCUS_CHANGED_BEFORE_PASTE stopped'; return $false
        }
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 250
        $check=Get-NativeFileNameFocus $Dialog
        if($null -eq $check -or -not $check.Verified -or
            $check.FocusHandle -ne $focus.FocusHandle) {
            Log 'FILENAME_NATIVE_FOCUS_CHANGED_AFTER_PASTE stopped'; return $false
        }
        $readback=Read-NativeEditText $focus.FocusHandle
        if(-not [string]::Equals($readback,$FileName,
            [System.StringComparison]::Ordinal)) {
            Log 'FILENAME_NATIVE_TEXT_READBACK_MISMATCH stopped'
            return $false
        }
        Log 'FILENAME_NATIVE_TEXT_VERIFIED'
        return $true
    } catch {
        Log ('FILENAME_NATIVE_KEYBOARD_ERROR '+$_.Exception.GetType().Name)
        return $false
    } finally {
        try {
            if(-not [string]::IsNullOrEmpty($script:PromptValue)) {
                [System.Windows.Forms.Clipboard]::SetText($script:PromptValue)
            }
        } catch {}
    }
}

function Select-ExactFile([System.Windows.Automation.AutomationElement]$Dialog, [string]$FullPath) {
    if(-not [System.IO.File]::Exists($FullPath)) {
        throw '当前附件路径不存在，停止上传。'
    }
    $directory=[System.IO.Path]::GetDirectoryName($FullPath)
    $filename=[System.IO.Path]::GetFileName($FullPath)
    if([string]::IsNullOrWhiteSpace($directory) -or
       [string]::IsNullOrWhiteSpace($filename) -or
       -not [System.IO.Directory]::Exists($directory)) {
        throw 'PDF 所在文件夹无效，停止上传。'
    }
    if($null -eq (Get-FileDialog)) { throw '文件选择器不是当前前台窗口，停止上传。' }

    # Step 1: go to the exact source folder through the address bar.
    Navigate-ToExactFolder $Dialog $directory

    # Step 2: write ONLY the filename, not a guessed path in an old folder.
    # Never rely on clipboard-copy readback (can produce false positives).
    if(-not (Write-FilenameUsingNativeFocus $Dialog $filename)) {
        throw '无法通过原生文件名框读取并验证目标附件文件名；未点击“打开”。'
    }

    # The common dialog's UIA Open.InvokePattern may submit its highlighted
    # item instead of the verified typed name. Use Enter in Edit#1148, which
    # was just verified by WM_GETTEXT, within the unique staging directory.
    $focus=Get-NativeFileNameFocus $Dialog
    if($null -eq $focus -or -not $focus.Verified) {
        throw '提交前文件名输入框失去焦点；已停止上传。'
    }
    $actual=Read-NativeEditText $focus.FocusHandle
    if(-not [string]::Equals($actual,$filename,[System.StringComparison]::Ordinal)) {
        throw '提交前文件名内容改变；已停止上传。'
    }
    $entries=@([System.IO.Directory]::GetFileSystemEntries($directory))
    if($entries.Count -ne 1 -or $entries[0] -ne $FullPath) {
        throw '待选择的临时目录包含不止目标文件，停止上传。'
    }
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Log 'FILENAME_ENTER_SUBMITTED'
    Start-Sleep -Milliseconds 900
    if($null -ne (Get-FileDialog)) {
        throw '文件选择器仍未关闭，请检查文件选择或权限。'
    }
    Log 'FILENAME_PICKER_CLOSED'
}

function Read-EditorText([System.Windows.Automation.AutomationElement]$Editor) {
    try {
        $p=$Editor.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        return [string]$p.Current.Value
    } catch {}
    try {
        $p=$Editor.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        return [string]$p.DocumentRange.GetText(-1)
    } catch {}
    return $null
}

function Find-ChatComposer([System.Windows.Automation.AutomationElement]$Window) {
    # Do not accept a generic Document named "Ask ChatGPT": after uploading
    # files it may represent the entire ChatGPT page including attachment chips.
    $editFilter=[System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Edit)
    $edits=$Window.FindAll([System.Windows.Automation.TreeScope]::Descendants,$editFilter)
    $best=$null
    $bestScore=0
    foreach($editor in $edits) {
        try {
            if(-not $editor.Current.IsEnabled -or $editor.Current.IsOffscreen) { continue }
            $name=[string]$editor.Current.Name
            $id=[string]$editor.Current.AutomationId
            $score=0
            if($id -match '(?i)(^prompt-textarea$|^pending-home-input$|composer-input|message-input)') {
                $score=100
            } elseif($name -match '(?i)^(Ask ChatGPT|Ask anything|Message ChatGPT|Write a message|向 ChatGPT 提问|询问 ChatGPT|问任何问题)$') {
                $score=50
            }
            if($score -gt $bestScore) { $best=$editor; $bestScore=$score }
        } catch {}
    }
    if($null -ne $best) {
        Log ('PROMPT_EDITOR_FOUND type=Edit score=' + $bestScore +
            ' id=' + [string]$best.Current.AutomationId)
        return $best
    }
    # Some Chromium builds expose the contenteditable as Document. Only
    # accept explicit composer automation IDs, never the page's document.
    $docFilter=[System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Document)
    $docs=$Window.FindAll([System.Windows.Automation.TreeScope]::Descendants,$docFilter)
    foreach($doc in $docs) {
        try {
            if(-not $doc.Current.IsEnabled -or $doc.Current.IsOffscreen) { continue }
            $id=[string]$doc.Current.AutomationId
            if($id -match '(?i)^(prompt-textarea|pending-home-input|composer-input)$') {
                Log ('PROMPT_EDITOR_FOUND type=Document id=' + $id)
                return $doc
            }
        } catch {}
    }
    return $null
}

function Test-ComposerHasOnlyAttachments([string]$Text,[string[]]$AttachmentPaths) {
    # The Edit's accessibility value can contain the uploaded attachment chip
    # labels despite its editable text being empty. Allow insertion ONLY when
    # all non-whitespace content can be accounted for by known attachment
    # filenames. This never overwrites the content; paste only appends.
    if([string]::IsNullOrWhiteSpace($Text)) { return $true }
    $remainder=$Text.Trim()
    if($remainder -match '^(?i)(Ask ChatGPT|Ask anything|Message ChatGPT|Write a message)$') {
        return $true
    }
    $found=0
    foreach($path in $AttachmentPaths) {
        if([string]::IsNullOrWhiteSpace($path)) { continue }
        $name=[System.IO.Path]::GetFileName($path)
        if([string]::IsNullOrWhiteSpace($name)) { continue }
        $pattern=[regex]::Escape($name)
        if([regex]::IsMatch($remainder,$pattern,
           [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $remainder=[regex]::Replace($remainder,$pattern,'',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $found++
        }
    }
    if($found -eq 0) { return $false }
    # Only harmless chip separators may remain. Any other text may be a
    # user's draft and must never be replaced or appended to automatically.
    return ($remainder -match '^[\s,;|·•\[\]\(\)]+$' -or
            [string]::IsNullOrWhiteSpace($remainder))
}

function Place-Prompt([System.Windows.Automation.AutomationElement]$Window,
                     [string]$Prompt,[string[]]$AttachmentPaths) {
    [System.Windows.Forms.Clipboard]::SetText($Prompt)
    $editor=$null
    for($attempt=0; $attempt -lt 12; $attempt++) {
        try {
            $root=[System.Windows.Automation.AutomationElement]::FromHandle(
                $script:ChatWindowHandle)
            $editor=Find-ChatComposer $root
            if($null -ne $editor) { break }
        } catch {
            Log ('PROMPT_EDITOR_POLL_ERROR ' + $_.Exception.GetType().Name)
        }
        Start-Sleep -Milliseconds 400
    }
    if($null -eq $editor) {
        Log 'PROMPT_CLIPBOARD_READY composer not identified; Ctrl+V manually'
        return
    }
    try {
        $existing=Read-EditorText $editor
        if($null -eq $existing) {
            Log 'PROMPT_CLIPBOARD_READY editor text unreadable; not typing'
            return
        }
        Log ('PROMPT_EDITOR_STATE type=' + $editor.Current.ControlType.ProgrammaticName +
             ' length=' + $existing.Length + ' expectedFiles=' + $AttachmentPaths.Count)
        $prefix=$Prompt.Substring(0,[Math]::Min(30,$Prompt.Length))
        if($existing.Contains($prefix)) {
            Log 'PROMPT_ALREADY_PRESENT not duplicating'
            return
        }
        $chipOnly=Test-ComposerHasOnlyAttachments $existing $AttachmentPaths
        if(-not $chipOnly) {
            Log 'PROMPT_CLIPBOARD_READY editor contains non-attachment text; not modifying'
            return
        }
        if(-not [string]::IsNullOrWhiteSpace($existing)) {
            Log 'PROMPT_CHIP_ONLY_TEXT ignoring known attachment labels'
        }
        try {
            $editor.SetFocus()
            Start-Sleep -Milliseconds 150
        } catch { Log 'PROMPT_SETFOCUS_UNAVAILABLE' }
        $focused=[System.Windows.Automation.AutomationElement]::FocusedElement
        $focusOK=Test-UIATarget $editor $focused
        if(-not $focusOK) {
            Log 'PROMPT_MOUSE_FOCUS_ATTEMPT'
            if(Click-UIA-Verified $editor) {
                Start-Sleep -Milliseconds 220
                $focused=[System.Windows.Automation.AutomationElement]::FocusedElement
                $focusOK=Test-UIATarget $editor $focused
            }
        }
        if(-not $focusOK) {
            Log 'PROMPT_CLIPBOARD_READY composer focus unverified'
            return
        }
        Log 'PROMPT_FOCUS_VERIFIED'
        $before=Read-EditorText $editor
        if($null -eq $before -or
           -not (Test-ComposerHasOnlyAttachments $before $AttachmentPaths)) {
            Log 'PROMPT_CLIPBOARD_READY editor changed before paste'
            return
        }
        # Do not Ctrl+A or delete. Insert only into the verified composer.
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 650
        $readback=Read-EditorText $editor
        if($null -ne $readback -and $readback.Contains($Prompt)) {
            Log ('PROMPT_PASTE_VERIFIED_FULL expected_length=' + $Prompt.Length)
        } else {
            $observed=if($null -eq $readback) { -1 } else { $readback.Length }
            Log ('PROMPT_PASTE_UNVERIFIED_FULL expected_length=' + $Prompt.Length +
                 ' observed_length=' + $observed +
                 ' check composer; Ctrl+V manually if incomplete')
        }
    } catch {
        Log ('PROMPT_CLIPBOARD_READY paste skipped: ' + $_.Exception.GetType().Name)
    }
}

try {
    Log 'WIN_SCRIPT_BUILD v0.4.0 uia-20261027'
    $paths = @([System.IO.File]::ReadAllLines($UploadListPath, [System.Text.Encoding]::UTF8) |
        Where-Object { $_.Length -gt 0 })
    if ($paths.Count -lt 1 -or $paths.Count -gt 10) { throw '附件清单必须包含 1–10 个文件。' }
    foreach ($p in $paths) {
        if ($p -match '[\r\n]' -or -not [System.IO.Path]::IsPathRooted($p) -or
            -not [System.IO.File]::Exists($p)) {
            throw '待上传附件路径无效或已经删除。'
        }
    }
    # Never let a chooser select unrelated Zotero metadata in a shared folder.
    $paths = @(Prepare-UploadStaging $paths $StatusPath)
    if($paths.Count -lt 1 -or $paths.Count -gt 10) {
        throw '暂存文件数量与要求不一致；已停止上传。'
    }
    # CI exercises actual Windows hardlink/copy staging without opening a browser.
    if($SelfTestStaging) { Log 'STAGING_SELFTEST_PASS'; exit 0 }
    $prompt = [System.IO.File]::ReadAllText($PromptPath, [System.Text.Encoding]::UTF8)
    $script:PromptValue=$prompt
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
    $script:ChatWindowHandle = $browserWindow.Handle
    Log 'CHAT_WINDOW_VERIFIED title contains ChatGPT'
    Log-UploadCandidates $browserWindow.Element
    # Upload first: pasting a long Prompt may disable/re-render the attach button.
    # Keep Prompt on clipboard now, and paste when picker operations finish.
    Log 'UPLOAD_FIRST_PROMPT_CLIPBOARD_READY'
    Log ('MULTI_UPLOAD_PLAN count=' + $paths.Count + ' first=PDF')
    for ($i=0; $i -lt $paths.Count; $i++) {
        $itemIndex=$i+1
        if ($null -ne (Get-FileDialog)) {
            throw ('第 ' + $itemIndex + ' 份文件：之前的文件选择器仍然打开。')
        }
        [void][ZcgWin32]::SetForegroundWindow($browserWindow.Handle)
        Start-Sleep -Milliseconds 350
        $foreground=Wait-ChatWindow 3
        if($null -eq $foreground -or $foreground.Handle -ne $script:ChatWindowHandle) {
            throw ('第 ' + $itemIndex + ' 份文件：ChatGPT 不是预期前台窗口。')
        }
        $extension=[System.IO.Path]::GetExtension($paths[$i]).ToLowerInvariant()
        Log ('FILE_START ' + $itemIndex + '/' + $paths.Count + ' extension=' + $extension)
        $dialog=Open-FileDialog $itemIndex $paths.Count
        if($null -eq $dialog) {
            throw ('第 ' + $itemIndex + '/' + $paths.Count + ' 份附件：未能打开文件选择器。')
        }
        Select-ExactFile $dialog $paths[$i]
        Log ('FILE_PICKER_CLOSED ' + $itemIndex + '/' + $paths.Count + ' extension=' + $extension)
        # Closing the Windows picker is NOT proof that ChatGPT has ingested
        # the attachment. Leave time for the browser's async upload/rerender.
        if($itemIndex -lt $paths.Count) {
            Log ('MULTI_NEXT_WAIT after=' + $itemIndex)
            Start-Sleep -Milliseconds 2200
        } else {
            Start-Sleep -Milliseconds 1800
        }
    }
    Log ('ALL_PICKERS_CLOSED ' + $paths.Count)
    Log 'ATTACHMENTS_REQUIRE_VISUAL_VERIFICATION web upload status not guaranteed'
    [void][ZcgWin32]::SetForegroundWindow($browserWindow.Handle)
    $foreground=Wait-ChatWindow 2
    if ($null -ne $foreground -and $foreground.Handle -eq $script:ChatWindowHandle) {
        Place-Prompt $foreground.Element $prompt $paths
    } else {
        Log 'PROMPT_CLIPBOARD_READY chat not foreground after uploads; paste manually'
    }
    Log 'NO_AUTO_SEND verify files and normal Chat mode before submitting'
} catch {
    try {
        $p = [System.IO.File]::ReadAllText($PromptPath, [System.Text.Encoding]::UTF8)
        if (-not [string]::IsNullOrWhiteSpace($p)) {
            [System.Windows.Forms.Clipboard]::SetText($p)
        }
    } catch {}
    Log ('ERROR ' + $_.Exception.Message)
    # An attachment error must not suppress the prompt. Only attempt auto-paste
    # if the foreground is still the verified ChatGPT browser, not a native dialog.
    try {
        $fg=Get-ForegroundBrowser
        if ($null -ne $fg -and $fg.Handle -eq $script:ChatWindowHandle) {
            Place-Prompt $fg.Element $prompt $paths
        } else {
            Log 'PROMPT_CLIPBOARD_READY upload error; browser not foreground'
        }
    } catch {
        Log ('PROMPT_FALLBACK_FAILED ' + $_.Exception.GetType().Name)
    }
    exit 1
}
