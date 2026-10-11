# Roadmap

## v0.3.x — macOS Safari hardening

- Independent testing across macOS versions; accessibility permissions, file picker localization.
- Reliable pre-upload validation of title and attachment count; prevent duplicate prompts.
- Keep "do not send automatically" as the safe default.
- Clean up stale task-cache directories and review filename/size constraints.

## v0.4.x — Browser adapters for macOS

- Browser selector: Safari / Chrome / Edge.
- Custom Chromium executable path with validation; **do not** assume that Safari supports Chromium automation APIs.
- Separate file-picker automation for different browser accessibility trees.

## v0.5.x — Windows

- Independent Windows process spawning and file-dialog handling, tested in real Windows/Zotero 10 environments.
- Chrome and Edge only after testing; custom path support later.

## v1.0 — Stable criteria

- CI+manual smoke tests on each **advertised** OS/browser combination.
- Accurate release metadata, update feed, docs, error handling and privacy review.
- Do not claim Zotero versions beyond the tested `strict_max_version`.
