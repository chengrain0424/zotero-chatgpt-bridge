"""Static checks only. A real macOS + Zotero 10 + Safari smoke test is required."""
from pathlib import Path
import json
import re
import sys
ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'src'
manifest = json.loads((source / 'manifest.json').read_text(encoding='utf8'))
assert manifest['applications']['zotero']['strict_max_version'] == '10.0.*'
assert manifest['applications']['zotero']['id'] == 'zotero-chatgpt-safari@local.bridge'
for name in ('bootstrap.js','bridge.js','Safari_自动上传.applescript'):
    assert (source/name).exists(), name
b = (source/'bridge.js').read_text(encoding='utf8')
a = (source/'Safari_自动上传.applescript').read_text(encoding='utf8')
assert 'getFilePathAsync()' in b
assert 'registerEventListener("renderToolbar"' in b
assert 'keystroke return' in a
assert not re.search(r'\/Users\/[^/\s]+', b+a)
print('Smoke checks passed (static only, NOT runtime browser validation).')
