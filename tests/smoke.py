"""Static checks only. Real Zotero/macOS/Safari E2E smoke testing required."""
from pathlib import Path
import json, re, tempfile, os
ROOT=Path(__file__).resolve().parents[1]
src=ROOT/'src'
manifest=json.loads((src/'manifest.json').read_text(encoding='utf-8'))
assert manifest['version']=='0.4.0-beta.17'
win=(src/'windows_upload.ps1').read_text(encoding='utf-8')
assert 'NO_AUTO_SEND' in win
assert 'Select-ExactFile' in win
assert '--force-renderer-accessibility' in win
assert 'Log-UploadCandidates' in win
assert 'function Log-UploadCandidates(' in win
assert 'function Prepare-UploadStaging(' in win
assert 'CreateHardLink(' in win
assert 'STAGED_SINGLE_FILE' in win
assert 'STAGING_SELFTEST_PASS' in win
assert 'picker_staging' in win
assert "if($filename.StartsWith('.') -or $allowed -notcontains $ext)" in win
assert "if($i -eq 0 -and $ext -ne '.pdf')" in win
assert 'FILENAME_ENTER_SUBMITTED' in win
assert 'function Get-VerifiedDialogFocus(' in win
assert 'function Get-AddressBarFocus(' in win
assert 'function Focus-AddressBar(' in win
assert 'function Navigate-ToExactFolder(' in win
assert 'function Read-NativeEditText(' in win
assert 'function Test-NativePathEqual(' in win
assert 'function Get-NativeFileNameFocus(' in win
assert 'function Write-FilenameUsingNativeFocus(' in win
assert 'GetGUIThreadInfo' in win
assert 'GetDlgCtrlID' in win
assert 'SendMessageTimeoutW' in win
assert 'WM_GETTEXT' in win
assert 'ADDRESS_PASTE_VERIFIED' in win
assert 'FOLDER_NAVIGATED_VERIFIED' in win
assert 'FILENAME_NATIVE_TEXT_VERIFIED' in win
assert 'FILENAME_PICKER_CLOSED' in win
assert 'FILENAME_NATIVE_FOCUS_UNVERIFIED stopped' in win
assert 'FILENAME_NATIVE_READBACK_VERIFIED' not in win
assert 'FILENAME_KEYBOARD_READBACK_VERIFIED' not in win
assert "SendWait('^c')" not in win
assert win.index('Navigate-ToExactFolder $Dialog $directory') < win.index('Write-FilenameUsingNativeFocus $Dialog $filename')
assert win.index('Write-FilenameUsingNativeFocus $Dialog $filename') < win.index("Log 'FILENAME_ENTER_SUBMITTED'")
assert 'function Log-PlusButtonState(' in win
assert 'UPLOAD_PLUS_STATE enabled=' in win
assert 'UPLOAD_FIRST_PROMPT_CLIPBOARD_READY' in win
assert 'MULTI_PLUS_TIMEOUT item=' in win
assert 'function Wait-ComposerPlus(' in win
assert 'RawViewWalker' in win
assert 'UIA_MOUSE_TARGET_MISMATCH no-verified-point' in win
assert 'UPLOAD_PLUS_HIT_RETRY item=' in win
assert 'UPLOAD_PLUS_HIT_TIMEOUT item=' in win
assert 'PROMPT_MOUSE_FOCUS_ATTEMPT' in win
assert 'PROMPT_FOCUS_VERIFIED' in win
assert 'function Find-ChatComposer(' in win
assert 'function Test-ComposerHasOnlyAttachments(' in win
assert 'PROMPT_EDITOR_STATE type=' in win
assert 'PROMPT_CHIP_ONLY_TEXT' in win
assert 'PROMPT_CLIPBOARD_READY editor contains non-attachment text' in win
assert "if(-not $chipOnly)" in win
assert "if($existing.Contains($prefix))" in win
assert "PLACEHOLDER_INTENTIONAL_DO_NOT_SEND" not in win
assert 'PROMPT_ALREADY_PRESENT not duplicating' in win
assert 'PROMPT_CLIPBOARD_READY composer focus unverified' in win
assert 'Click-UIA-Verified $editor' in win
assert 'if(Click-UIA-Verified $plus)' in win
assert 'if(-not $focusOK)' in win
assert win.index("Log 'PROMPT_FOCUS_VERIFIED'") < win.index("SendWait('^v')", win.index('function Place-Prompt'))
assert 'UPLOAD_PLUS_INVOKE_FAILED item=' not in win

assert 'MULTI_PLUS_READY item=' in win
assert 'MULTI_UPLOAD_PLAN count=' in win
assert 'MULTI_NEXT_WAIT after=' in win
assert 'ATTACHMENTS_REQUIRE_VISUAL_VERIFICATION' in win
assert 'Open-FileDialog $itemIndex $paths.Count' in win
assert 'extension=' in win
assert win.index('UPLOAD_FIRST_PROMPT_CLIPBOARD_READY') < win.index('FILE_START')
assert win.index('FILE_START') < win.index('Place-Prompt $foreground.Element $prompt')
assert 'function Log-ForegroundState(' in win
assert 'function Test-OwnedByChat(' in win
assert 'function Click-UIA-Verified(' in win
assert 'UPLOAD_MENU_PHYSICAL_CLICK' in win
assert 'PICKER_NOT_DETECTED_AFTER_PHYSICAL_MENU_CLICK' in win
assert '(Click-UIA-Verified $menu)' in win
assert '(Invoke-UIA $menu)' not in win
assert 'UPLOAD_MENU_VERIFIED_MOUSE_RETRY' not in win
assert 'PICKER_CONFIRMED ownership-and-filename-field' in win
assert 'KeyboardSpace' in win
assert 'VerifiedMouseClick' in win
assert 'ControlType]::Document' in win
assert 'PROMPT_PASTE_VERIFIED' in win
assert win.index('for ($i=0; $i -lt $paths.Count; $i++)') < win.index('Place-Prompt $foreground.Element $prompt')
assert 'SetForegroundWindow' in win
assert 'WIN_SCRIPT_BUILD v0.4.0beta17 uia-20261027' in win
assert 'prepareWindows(item)' in (src/'bridge.js').read_text(encoding='utf-8')
assert '"Not recorded"' in (src/'bridge.js').read_text(encoding='utf-8')
assert '"None"' in (src/'bridge.js').read_text(encoding='utf-8')
assert 'legacyDefaultTemplate:' in (src/'bridge.js').read_text(encoding='utf-8')
assert manifest['applications']['zotero']['id']=='zotero-chatgpt-safari@local.bridge'
assert manifest['applications']['zotero']['strict_max_version']=='10.0.*'
a=(src/'Safari_自动上传.applescript').read_text(encoding='utf-8')
b=(src/'bridge.js').read_text(encoding='utf-8')
assert 'getFilePathAsync()' in b
assert 'getAttachmentMode()' in b
assert '(!includeAll && ext !== "pdf" && !si)' in b
assert 'registerEventListener("renderToolbar"' in b
assert 'single_file_picker' in b
assert 'createHardlinkIfPossible' in b
assert 'if (!hardLinked) this.createSymlink(f.sourcePath, pickerPath);' in b
assert 'pickerPaths.push(pickerPath)' in b
assert 'upload_paths.txt' in b
assert 'BRIDGE_BUILD v0.3.9 v030-keyboard-20261014' in b
assert 'SCRIPT_BUILD v0.3.9 v030-keyboard-20261014' in a
assert 'FILE_V030_CMD_A_RETURN' in a
assert 'keystroke "g" using {command down, shift down}' in a
assert 'keystroke "a" using {command down}' in a
assert 'set the clipboard to folderPath' in a
assert 'if folderPath does not contain "/single_file_picker/"' in a
assert 'if presence is not "PRESENT" or numberOfFiles is not "1"' in a
assert a.index('set the clipboard to folderPath') < a.index('keystroke "a" using {command down}') < a.index('keystroke return\n    end tell\n    my statusLog(statusPath, "FILE_V030_CMD_A_RETURN')
assert 'entire contents of first sheet' not in a
assert 'FILE_FAST_CLICK' not in a
assert 'FILE_QUICK_START' not in a
assert 'never presses Send' in a or 'Never presses Send' in a
assert 'chooseExactFile(chosenPath, statusPath)' in a
assert not re.search(r'/Users/[^/\s]+',a+b)
# POSIX singleton folders can contain hardlinks and symlinks without copying document bytes.
with tempfile.TemporaryDirectory() as t:
    d=Path(t); main=d/'main.pdf'; main.write_bytes(b'%PDF-\nexample')
    docx=d/'SI.docx'; docx.write_bytes(b'PK\x03\x04example')
    for i,path in enumerate((main,docx),start=1):
        stage=d/'single_file_picker'/f'{i:02d}'
        stage.mkdir(parents=True)
        hardlink=stage/path.name
        os.link(path,hardlink)
        assert os.stat(path).st_ino==os.stat(hardlink).st_ino
        assert len(list(stage.iterdir()))==1
print('PASS v0.3.9: version, singleton staging, restored native keyboard picker; static only')
