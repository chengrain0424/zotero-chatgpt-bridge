# Zotero → ChatGPT Chat (unofficial)

[中文说明](README.zh-CN.md) · [Roadmap](docs/ROADMAP.md) · [Changelog](CHANGELOG.md)

**Beta v0.3.9 · Zotero 10 · macOS + Safari only.** A reader-toolbar plugin that collects the currently open article's **local main PDF and other supported sibling attachments**, opens a fresh ChatGPT browser conversation, and attempts to attach the files. It supports an editable Chinese literature-review prompt.

The plugin uses your **existing signed-in ChatGPT browser session**, **not** the OpenAI API, Codex, or a separate API key. **You must check that the page is regular Chat rather than Work**; the plugin cannot verify or switch modes reliably. Usage limits are whatever your ChatGPT plan permits.

## What it does

- `✦ ChatGPT` in Zotero's PDF reader toolbar (with a context-menu fallback).
- Gets the original attachment locations from Zotero; **no second PDF copy** is created. The diagnostic `links_only` directory contains symbolic links; the actual chooser uses regular hardlinks (no copied bytes) when possible, or symlinks across volumes.
- By default, collects **all supported local sibling attachments from the SAME Zotero parent item** (PDF, DOC, DOCX, XLS, XLSX, CSV, TXT, PPT/PPTX, MD), even if SI filenames are generic such as `data_1.docx`. The `⚙` prompt panel also includes an **SI-only** checkbox option to restrict non-PDF uploads to files named as supplementary/supporting information. It cannot fetch missing SI from publisher websites.
- Opens Safari and adds files one at a time using the faster native keyboard picker flow validated on macOS. **Does not automatically click Send**. Always review attachments and conversation mode before sending.
- `⚙` opens an editable prompt template **and attachment inclusion option**, saved in Zotero's local preferences.

## Compatibility

| Platform | Browser | Status |
| --- | --- | --- |
| Zotero 10 / macOS | Safari | **Beta, tested in one user environment** |
| Zotero 10 / macOS | Chrome / Edge / custom Chromium path | Planned, not implemented |
| Zotero 10 / Windows | Chrome / Edge | Planned, not implemented |
| Zotero 7–9 | Any | Not verified |

> This is an **unofficial, community-built project**, not affiliated with Zotero or OpenAI. ChatGPT's website markup may change at any time. The current uploader depends on Safari JavaScript-from-Apple-Events permission, macOS Accessibility/Automation permissions, and a Terminal-launched AppleScript. The Terminal window is hidden only on a best-effort basis.

## Install

1. Download the `.xpi` from the local [`dist/`](dist/) folder for this test build (select the file and use **Download raw file**), or from [Releases](../../releases) once a release is published.
2. In Zotero 10: **Tools → Plugins → gear icon → Install Plugin From File**.
3. Restart Zotero and reopen a PDF. Use `✦ ChatGPT` and `⚙` in the reader toolbar.
4. In Safari: enable developer features and **Develop → Allow JavaScript from Apple Events**. Grant only necessary macOS Accessibility/Automation permissions when asked.
5. Open a normal ChatGPT session and log in using the normal official login page. Review the upload list and **manually submit** the prompt.

**Do not test with unpublished/confidential papers until you have reviewed the privacy behavior and the destination account.** Diagnostic logs and generated prompts may contain publication titles and local paths: do not upload those logs to public GitHub issues without redacting them.

## Build from source

Requires Python 3.10+ (standard library only). For the project repository:

```bash
python3 scripts/build_release.py --owner chengrain0424 --repo zotero-chatgpt-bridge
```

The command generates `dist/*.xpi`, `dist/updates.json`, and `dist/SHA256SUMS`. The builder replaces the placeholder `update_url` in the packaged manifest with the real GitHub raw-file URL. Commit both `dist/*.xpi` and the generated `updates.json` at the repository root. Optionally create a `v0.3.9-beta` GitHub **pre-release** with the XPI attached. See [release instructions](docs/RELEASING.md).

## Limitations and troubleshooting

The file picker is UI automation, not an official ChatGPT upload API. It may break when the site changes, when macOS permissions change, or if a dialog steals focus. A generated upload folder contains symlinks, but **the uploaded data are the contents of the original documents**. Review attachments before clicking Send. The tool currently cannot confirm normal Chat vs Work, uploaded-file count, or successful attachment ingestion reliably. Since the default includes all supported files under one Zotero parent, **check unrelated attachments and your account before sending**; choose SI-only mode in `⚙` when needed.

If no action occurs, inspect Zotero **Tools → Developer → Error Console** and the most recent `~/Library/Caches/ZoteroChatGPTBridge/run-*/status.log`. Redact local paths and titles before sharing bug reports.

## Source and licensing

This repository package contains no user PDFs, accounts, tokens or personal logs. Source code is released under the [MIT License](LICENSE).


### Local v0.3.7 diagnostic build

This local test build identifies the actual loaded bridge and Safari script separately in `status.log`; see [diagnostic guide](UPGRADE_v0.3.7.md). It is **not** a published GitHub release.


### v0.3.8 quick-confirm test

See [v0.3.8 test guide](UPGRADE_v0.3.8.md). This is a local testing build, not a stable release.
