# Changelog

## 0.3.0 — Beta candidate

- Add Zotero PDF reader toolbar (`✦ ChatGPT`, prompt editor `⚙`).
- Support the current PDF and local same-parent SI attachment selection.
- Stage symbolic links instead of copying PDF bytes.
- Launch Safari UI automation in a best-effort hidden Terminal session.
- Remove plugin confirmation dialogs; never automatically click Send.

Known limitations: only macOS + Safari has been tested; Safari DOM and Accessibility automation are brittle; cannot reliably identify Chat versus Work; only one user device has verified the core upload path.
