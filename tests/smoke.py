"""Static checks only. Real Zotero/macOS/Safari E2E smoke testing required."""
from pathlib import Path
import json, re, tempfile, os
ROOT=Path(__file__).resolve().parents[1]
src=ROOT/'src'
manifest=json.loads((src/'manifest.json').read_text(encoding='utf-8'))
assert manifest['version']=='0.4.0-beta.5'
win=(src/'windows_upload.ps1').read_text(encoding='utf-8')
assert 'NO_AUTO_SEND' in win
assert 'Select-ExactFile' in win
assert '--force-renderer-accessibility' in win
assert 'Log-UploadCandidates' in win
assert 'function Log-UploadCandidates(' in win
assert 'KeyboardSpace' in win
assert 'VerifiedMouseClick' in win
assert 'ControlType]::Document' in win
assert 'PROMPT_PASTE_VERIFIED' in win
assert win.index('Place-Prompt $browserWindow.Element $prompt') < win.index('for ($i=0; $i -lt $paths.Count; $i++)')
assert 'SetForegroundWindow' in win
assert 'WIN_SCRIPT_BUILD v0.4.0beta5 uia-20261026' in win
assert 'prepareWindows(item)' in (src/'bridge.js').read_text(encoding='utf-8')
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
