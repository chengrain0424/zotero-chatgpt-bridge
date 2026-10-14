# Release checklist — v0.3.9 Beta

This release **replaces v0.3.0 as the current distribution on `main`**, but does not rewrite or delete the historical `v0.3.0-beta` tag/release. The working Zotero add-on version remains **0.3.9**; changing code while keeping 0.3.0 would cause update detection problems.

1. Review for confidential PDFs, logs, credentials, absolute paths (do not commit those).
2. Run `python3 scripts/build_release.py --owner chengrain0424 --repo zotero-chatgpt-bridge`.
3. Run `python3 tests/smoke.py` and `node --test tests/attachments.test.js` (if Node.js installed).
4. Confirm `dist/Zotero_to_ChatGPT_Direct_v0.3.9_Zotero10.xpi` SHA-256 matches `dist/SHA256SUMS` and the `update_hash` in `updates.json`.
5. Remove obsolete `dist/Zotero_to_ChatGPT_Direct_v0.3.0_Zotero10.xpi` from current `main` files. Keep historical Git history and release unchanged.
6. Commit/push `src/`, `tests/`, `scripts/`, `docs/`, `dist/`, README, CHANGELOG and **root `updates.json`**.
7. After push, verify raw download URLs, GitHub Actions, and install the downloaded XPI on Zotero 10 macOS Safari. Do not assume workflow success validates native file-picker automation.
8. If desired, create **one** new GitHub Release tag `v0.3.9-beta`, marked pre-release. Do not relabel the XPI or modify earlier tags retroactively.

The add-on still requires checking Chat vs Work, attachment list, and manual Send. Browser automation can fail when Safari/macOS/ChatGPT UI changes.
