#!/usr/bin/env python3
"""Build a Zotero XPI and Github-hosted updates.json for a named repository.
No external packages required; never reads Zotero user data.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.4.0-beta.1"
ASSET_NAME = f"Zotero_to_ChatGPT_Direct_v{VERSION}_Zotero10.xpi"
FILES = ["manifest.json", "bootstrap.js", "bridge.js", "safari_source.js", "windows_source.js"]


def build(owner, repo):
    for label, value in (("owner", owner), ("repo", repo)):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,99}", value):
            raise SystemExit(f"Invalid GitHub {label}: {value!r}")
    source = ROOT / "src"
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    zotero = manifest["applications"]["zotero"]
    zotero["update_url"] = f"https://raw.githubusercontent.com/{owner}/{repo}/main/updates.json"
    # Inline the AppleScript as a JavaScript string, exactly as bootstrap expects.
    apple = (source / "Safari_自动上传.applescript").read_text(encoding="utf-8")
    js_source = "var SAFARI_SOURCE = " + json.dumps(apple, ensure_ascii=False) + ";\n"
    windows = (source / "Windows_自动上传.ps1").read_text(encoding="utf-8")
    js_windows = "var WINDOWS_SOURCE = " + json.dumps(windows, ensure_ascii=False) + ";\n"
    generated = {
        "manifest.json": (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode(),
        "bootstrap.js": (source / "bootstrap.js").read_bytes(),
        "bridge.js": (source / "bridge.js").read_bytes(),
        "safari_source.js": js_source.encode("utf-8"),
        "windows_source.js": js_windows.encode("utf-8"),
    }
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    xpi = dist / ASSET_NAME
    with zipfile.ZipFile(xpi, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for filename in FILES:
            info = zipfile.ZipInfo(filename, (2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o644 & 0xffff) << 16
            z.writestr(info, generated[filename])
    sha = hashlib.sha256(xpi.read_bytes()).hexdigest()
    feed = {
        "addons": {
            zotero["id"]: {
                "updates": [{
                    "version": VERSION,
                    "update_link": f"https://raw.githubusercontent.com/{owner}/{repo}/main/dist/{ASSET_NAME}",
                    "update_hash": f"sha256:{sha}",
                    "applications": {"zotero": {
                        "strict_min_version": zotero["strict_min_version"],
                        "strict_max_version": zotero["strict_max_version"],
                    }},
                }]
            }
        }
    }
    (dist / "updates.json").write_text(json.dumps(feed, indent=2) + "\n", encoding="utf-8")
    (dist / "SHA256SUMS").write_text(f"{sha}  {ASSET_NAME}\n", encoding="utf-8")
    print(f"Built: {xpi}\nFeed:  {dist/'updates.json'}\nSHA-256: {sha}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--owner", required=True)
    parser.add_argument("--repo", required=True)
    a = parser.parse_args()
    build(a.owner, a.repo)
