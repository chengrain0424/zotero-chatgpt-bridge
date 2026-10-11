# Release checklist (owner action required)

Target: public repository `chengrain0424/zotero-chatgpt-bridge` with MIT license. The repository must exist and both `dist/*.xpi` and `updates.json` must be committed on `main` for update downloads to work; Releases are optional.

1. Review code and docs, verify there are no private PDFs or logs.
2. Build using: `python3 scripts/build_release.py --owner chengrain0424 --repo zotero-chatgpt-bridge`.
3. Smoke test the generated `.xpi` on **Zotero 10 + macOS + Safari**. Compare the PDF/SI list and ensure the normal Chat mode is selected. Do **not** click Send when testing with confidential documents.
4. Commit the generated `dist/updates.json` as repository-root `updates.json` AND commit `dist/*.xpi`, since the update feed links directly to the raw XPI in `main`.
5. Optionally create a GitHub Release tagged `v0.3.0`, mark **Pre-release**, and upload the XPI asset named `Zotero_to_ChatGPT_Direct_v0.3.0_Zotero10.xpi`.
6. Ensure update feed, release file link and SHA-256 match exactly; test installation from GitHub Release, then test updates on a later version.
7. State unambiguously: Mac Safari Beta, not Windows/Chrome/Edge compatible yet; third-party, no official ChatGPT/Zotero affiliation.
