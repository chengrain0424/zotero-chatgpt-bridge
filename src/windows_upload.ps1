# Windows ChatGPT upload assistant for Zotero 10
# WIN_SCRIPT_BUILD v0.4.0beta12 uia-20261027
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
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
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

function Test-UIATarget([System.Windows.Automation.AutomationElement]$Expected, [System.Windows.Automation.AutomationElement]$AtPoint) {
    # Prevent an accidental click on an overlay or another control after layout changes.
    $node = $AtPoint
    for ($depth=0; $depth -lt 8 -and $null -ne $node; $depth++) {
        try {
            if ($node.Equals($Expected)) { return $true }
            $node = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($node)
        } catch { return $false }
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
    # Guard the target with a UI Automation hit test immediately before click.
    try {
        $r = $Element.Current.BoundingRectangle
        if ($r.Width -lt 8 -or $r.Height -lt 8) { return $false }
        $x = [int]($r.Left + $r.Width/2)
        $y = [int]($r.Top + $r.Height/2)
        $hit = [System.Windows.Automation.AutomationElement]::FromPoint(
            [System.Windows.Point]::new($x,$y))
        if (-not (Test-UIATarget $Element $hit)) {
            Log 'UIA_MOUSE_TARGET_MISMATCH stopped'
            return $false
        }
        $previous = New-Object ZcgWin32+POINT
        $hasPrevious = [ZcgWin32]::GetCursorPos([ref]$previous)
        try {
            [void][ZcgWin32]::SetCursorPos($x,$y)
            Start-Sleep -Milliseconds 80
            $hitAgain = [System.Windows.Automation.AutomationElement]::FromPoint(
                [System.Windows.Point]::new($x,$y))
            if (-not (Test-UIATarget $Element $hitAgain)) {
                Log 'UIA_MOUSE_TARGET_CHANGED stopped'
                return $false
            }
            [ZcgWin32]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
            [ZcgWin32]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
            Log 'UIA_ACTIVATED via=VerifiedMouseClick'
            return $true
        } finally {
            if ($hasPrevious) { [void][ZcgWin32]::SetCursorPos($previous.X,$previous.Y) }
        }
    } catch {
        Log ('UIA_MOUSE_UNAVAILABLE ' + $_.Exception.Message)
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

function Open-FileDialog([System.Windows.Automation.AutomationElement]$ChatWindow) {
    $buttons = @([System.Windows.Automation.ControlType]::Button,
                 [System.Windows.Automation.ControlType]::MenuItem)
    $plusLabels = '(?i)(composer-plus-btn|Add files and more|Add photos and files|Add photos & files|Attach files|添加文件|添加照片|添加附件|附件|Add photos|Upload files)'
    $uploadLabels = '(?i)(Upload files|Upload from computer|Add photos.{0,8}files|从电脑上传|上传文件|添加照片和文件)'
    # A freshly loaded composer may briefly disable its attach button.
    # Never click disabled elements: wait for an interactive one, with diagnostics.
    $plus = $null
    for ($attempt=0; $attempt -lt 12; $attempt++) {
        $plus = Find-UIA $ChatWindow $buttons $plusLabels
        if ($null -ne $plus) { break }
        if ($attempt -eq 0 -or $attempt -eq 5) { Log-PlusButtonState $ChatWindow }
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $plus) {
        Log 'UPLOAD_PLUS_UNAVAILABLE_AFTER_RETRIES'
        Log-PlusButtonState $ChatWindow
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
    $dialog = Wait-FileDialog 2
    if ($null -ne $dialog) { Log 'PICKER_OPEN_DIRECT'; return $dialog }

    $menu=Find-UIA $ChatWindow $buttons $uploadLabels
    if ($null -eq $menu) {
        Log 'UPLOAD_MENU_NOT_FOUND'
        Log-UploadCandidates $ChatWindow
        return $null
    }
    Log ('UPLOAD_MENU_FOUND name=' + [string]$menu.Current.Name)
    # An InvokePattern action on Chromium's HTML file-input menu entry can
    # dismiss the menu without providing the browser a trusted user gesture.
    # Use one hit-tested physical mouse click, rather than invoking the
    # accessibility action and then retrying after the menu closes.
    Log ('UPLOAD_MENU_TARGET type=' + $menu.Current.ControlType.ProgrammaticName +
         ' enabled=' + $menu.Current.IsEnabled +
         ' offscreen=' + $menu.Current.IsOffscreen)
    if (-not (Click-UIA-Verified $menu)) {
        Log 'UPLOAD_MENU_MOUSE_NOT_VERIFIED'
        Log-UploadCandidates $ChatWindow
        return $null
    }
    Log 'UPLOAD_MENU_PHYSICAL_CLICK'
    $dialog=Wait-FileDialog 8
    if ($null -ne $dialog) { return $dialog }
    # Never toggle the + button a second time after a failed native picker:
    # the menu may have closed, and a retry can accidentally reopen it.
    Log 'PICKER_NOT_DETECTED_AFTER_PHYSICAL_MENU_CLICK'
    Log-ForegroundState 'picker-final'
    Log-UploadCandidates $ChatWindow
    return $null
}

function Log-FilenameCandidates([System.Windows.Automation.AutomationElement]$Dialog) {
    # Log only control types/IDs under the filename widget; no displayed
    # text, titles, document names, contents, or local attachment paths.
    try {
        $idFilter=[System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1148')
        $roots=$Dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants,$idFilter)
        Log ('FILENAME_1148_MATCHES ' + $roots.Count)
        $index=0
        foreach ($root in $roots) {
            if ($index -ge 8) { break }
            try {
                Log ('FILENAME_1148_NODE type=' + $root.Current.ControlType.ProgrammaticName +
                    ' enabled=' + $root.Current.IsEnabled +
                    ' offscreen=' + $root.Current.IsOffscreen)
                $children=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                    [System.Windows.Automation.Condition]::TrueCondition)
                $j=0
                foreach ($child in $children) {
                    if ($j -ge 16) { break }
                    Log ('FILENAME_CHILD type=' + $child.Current.ControlType.ProgrammaticName +
                        ' id=' + [string]$child.Current.AutomationId)
                    $j++
                }
            } catch { Log ('FILENAME_CANDIDATE_ERROR ' + $_.Exception.GetType().Name) }
            $index++
        }
    } catch {
        Log ('FILENAME_ENUM_ERROR ' + $_.Exception.GetType().Name)
    }
}

function Find-FilenameControl([System.Windows.Automation.AutomationElement]$Dialog) {
    # Win11 file pickers may expose AutomationId 1148 as Pane, ComboBox and
    # Edit at different depths. NEVER return a Pane: it cannot accept focus.
    $idFilter=[System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1148')
    $editFilter=[System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Edit)
    $roots=$Dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants,$idFilter)
    $candidates=New-Object 'System.Collections.Generic.List[System.Windows.Automation.AutomationElement]'

    # Prefer the actual 1148 Edit, rather than the first 1148 Pane.
    foreach ($root in $roots) {
        try {
            if ($root.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit -and
                $root.Current.IsEnabled -and -not $root.Current.IsOffscreen) {
                $candidates.Add($root)
            }
        } catch {}
    }
    if ($candidates.Count -eq 1) {
        Log 'FILENAME_EDIT_FOUND via=1148-direct'
        return $candidates[0]
    }
    if ($candidates.Count -gt 1) {
        Log 'FILENAME_EDIT_AMBIGUOUS multiple-direct-1148-edits'
        Log-FilenameCandidates $Dialog
        return $null
    }

    # Traverse the Pane/ComboBox with ID 1148 and select exactly one Edit.
    foreach ($root in $roots) {
        try {
            $edits=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$editFilter)
            foreach ($edit in $edits) {
                if (-not $edit.Current.IsEnabled -or $edit.Current.IsOffscreen) { continue }
                $seen=$false
                foreach ($prev in $candidates) { if ($prev.Equals($edit)) { $seen=$true; break } }
                if (-not $seen) { $candidates.Add($edit) }
            }
        } catch {}
    }
    if ($candidates.Count -eq 1) {
        Log 'FILENAME_EDIT_FOUND via=1148-descendant'
        return $candidates[0]
    }
    if ($candidates.Count -gt 1) {
        Log 'FILENAME_EDIT_AMBIGUOUS multiple-descendant-edits'
        Log-FilenameCandidates $Dialog
        return $null
    }
    # Do not guess between an address bar, search field or file name. A
    # focused click on the wrong input could expose private document paths.
    Log 'FILENAME_EDIT_NOT_FOUND'
    Log-FilenameCandidates $Dialog
    return $null
}

function Test-VerifiedFileNameFocus([System.Windows.Automation.AutomationElement]$Dialog,
                                    [System.Windows.Automation.AutomationElement]$Field) {
    # CRITICAL: Ctrl+A must never reach the file list, address bar, or chat box.
    $active=Get-FileDialog
    if ($null -eq $active -or -not $active.Equals($Dialog)) { return $false }
    $focused=[System.Windows.Automation.AutomationElement]::FocusedElement
    if ($null -eq $focused) { return $false }
    return (Test-UIATarget $Field $focused)
}

function Write-FilenameWithKeyboard([System.Windows.Automation.AutomationElement]$Dialog,
                                    [System.Windows.Automation.AutomationElement]$Field,
                                    [string]$FullPath) {
    # Fallback when this Windows Common File Dialog field has no ValuePattern.
    # Only use Ctrl+A after focus and dialog ownership are verified.
    # Reject outer Pane/ComboBox explicitly, even if upstream selection regresses.
    if ($Field.Current.ControlType -ne [System.Windows.Automation.ControlType]::Edit) {
        Log 'FILENAME_NOT_EDIT stopped'
        return $false
    }
    try { $Field.SetFocus() } catch {
        Log ('FILENAME_SETFOCUS_UNAVAILABLE ' + $_.Exception.GetType().Name)
    }
    Start-Sleep -Milliseconds 150
    if (-not (Test-VerifiedFileNameFocus $Dialog $Field)) {
        Log 'FILENAME_FOCUS_RETRY_VERIFIED_MOUSE'
        if (-not (Click-UIA-Verified $Field)) {
            Log 'FILENAME_FOCUS_MOUSE_NOT_VERIFIED stopped'
            return $false
        }
        Start-Sleep -Milliseconds 180
    }
    if (-not (Test-VerifiedFileNameFocus $Dialog $Field)) {
        Log 'FILENAME_FOCUS_NOT_VERIFIED stopped'
        return $false
    }
    Log 'FILENAME_FOCUS_VERIFIED'
    try {
        [System.Windows.Forms.Clipboard]::SetText($FullPath)
        if (-not (Test-VerifiedFileNameFocus $Dialog $Field)) {
            Log 'FILENAME_FOCUS_CHANGED_BEFORE_PASTE stopped'
            return $false
        }
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 350
        if (-not (Test-VerifiedFileNameFocus $Dialog $Field)) {
            Log 'FILENAME_FOCUS_CHANGED_AFTER_PASTE stopped'
            return $false
        }
        # Read back what was actually pasted using Ctrl+A / Ctrl+C INSIDE the
        # verified file name control. Without a match, never click "Open".
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        [System.Windows.Forms.SendKeys]::SendWait('^c')
        Start-Sleep -Milliseconds 180
        $copied=[System.Windows.Forms.Clipboard]::GetText()
        if (-not [string]::Equals($copied,$FullPath,[System.StringComparison]::Ordinal)) {
            Log 'FILENAME_PASTE_READBACK_MISMATCH stopped'
            return $false
        }
        Log 'FILENAME_KEYBOARD_READBACK_VERIFIED'
        return $true
    } catch {
        Log ('FILENAME_KEYBOARD_ERROR ' + $_.Exception.GetType().Name)
        return $false
    } finally {
        # The clipboard was previously holding the Zotero-generated Prompt.
        # Restore that fallback rather than leaving the PDF path copied.
        try {
            if (-not [string]::IsNullOrEmpty($script:PromptValue)) {
                [System.Windows.Forms.Clipboard]::SetText($script:PromptValue)
            }
        } catch {}
    }
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
        throw 'PDF 附件路径不存在，停止上传。'
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
        throw '无法通过原生文件名框读取并验证目标 PDF 文件名；未点击“打开”。'
    }

    # Revalidate actual file selection context immediately before opening.
    # Don't send Enter here; the verified Open button is safer.
    if($null -eq (Get-FileDialog)) {
        throw '文件选择器在确认 PDF 名称后已失去焦点。'
    }
    $ok=$Dialog.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1'))
    if($null -eq $ok) {
        $ok=Find-UIA $Dialog @([System.Windows.Automation.ControlType]::Button) '^(Open|打开)(\s|$)'
    }
    if($null -eq $ok -or -not (Invoke-UIA $ok)) {
        throw '路径已验证，但无法点击文件选择器的“打开”按钮。'
    }
    Log 'FILENAME_OPEN_CLICKED'
    Start-Sleep -Milliseconds 900
    if($null -ne (Get-FileDialog)) {
        throw '文件选择器仍未关闭，请检查文件选择或权限。'
    }
    Log 'FILENAME_PICKER_CLOSED'
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
        # Chromium may expose a contenteditable composer as Document instead of Edit.
        $editor = Find-UIA $Window @([System.Windows.Automation.ControlType]::Edit,
          [System.Windows.Automation.ControlType]::Document) $pattern
        if ($null -ne $editor) { break }
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $editor) {
        Log 'PROMPT_CLIPBOARD_READY composer not identified in Edit/Document controls; Ctrl+V manually'
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
    Log 'WIN_SCRIPT_BUILD v0.4.0beta12 uia-20261027'
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
    [void][ZcgWin32]::SetForegroundWindow($browserWindow.Handle)
    $foreground=Wait-ChatWindow 2
    if ($null -ne $foreground -and $foreground.Handle -eq $script:ChatWindowHandle) {
        Place-Prompt $foreground.Element $prompt
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
            Place-Prompt $fg.Element $prompt
        } else {
            Log 'PROMPT_CLIPBOARD_READY upload error; browser not foreground'
        }
    } catch {
        Log ('PROMPT_FALLBACK_FAILED ' + $_.Exception.GetType().Name)
    }
    exit 1
}
