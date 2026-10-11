#!/usr/bin/env python3
"""Generate a release package from vetted plugin sources."""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src"
OUTPUT = ROOT / "dist"
OUTPUT.mkdir(exist_ok=True)
with zipfile.ZipFile(OUTPUT / "Zotero_to_ChatGPT_Direct_v0.3.0_Zotero10.xpi", "w", zipfile.ZIP_DEFLATED) as archive:
    for name in ("manifest.json", "bootstrap.js", "bridge.js"):
        archive.write(SOURCE / name, name)
print("Package created; add generated Safari source before release.")
