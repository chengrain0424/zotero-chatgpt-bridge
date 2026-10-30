## v0.4.2 development — restore ChatGPT toolbar in reopened PDF tabs

- Fix Zotero 10.0.7 startup ordering: previously reopened PDF readers could miss the one-time renderToolbar event before this plugin registered its listener.
- On plugin startup, scan existing reader sessions for an already-rendered toolbar and insert the **same** ChatGPT/Prompt controls in Zotero's toolbar CustomSections slot, without closing or reloading any PDF.
- Idempotently suppress duplicate widgets; remove recovery-inserted and event-inserted UI at disable/shutdown, and bound the asynchronous restoration retries to roughly six seconds.
- Preserve official `renderToolbar` listener for newly opened/React-rerendered readers; if Zotero changes an internal selector, event handling remains available.
- This is a test build only; leave latest official GitHub Release v0.4.1 unchanged pending user validation on Zotero 10.0.7.

## v0.4.1 — Stable release: ChatGPT ZIP/MD to Zotero child notes

- Promote the tested v0.4.1 import workflow to the current official release. Select a parent paper and drop ZIP/MD onto its detail panel or use the right-click importer.
- Requires Better Notes for Markdown and image import; creates a real Zotero child note. Does not overwrite existing notes.
- ZIP backup defaults off, with optional per-user opt-in; panel shows linked-note counts, recent import shortcut, and only appears on primary paper records.
- Fix native Windows file picker BrowsingContext conversion; retain secure ZIP validation, original PDF/SI uploading, 35,986-char reading prompt and no-auto-send.
- For imported image and formula fidelity, inspect the result in Zotero; source ZIP may be kept outside Zotero as archival backup.

### v0.4.1 development UX refinement — import panel and optional ZIP

- Change ZIP backup default to **OFF**. Users may opt in via the checkbox on the primary reference item pane; existing ZIP attachments are never deleted automatically.
- Add a concise status line displaying the total Zotero child-note count and tagged ChatGPT-import note count, plus a shortcut to the most recently imported note. New imports receive a lightweight `ChatGPT Bridge Import` tag; older notes are not changed.
- Hide the entire custom importer section (including side-navigation entry) when selecting a PDF/SI attachment or child note, using Zotero's documented item-pane `onItemChange({setEnabled})` hook.
- Existing ZIP/MD drop zone, native file picker fix, and Better Notes import flow remain unchanged. CI regression tests cover section visibility, note status and opt-in backup.
- Development build only; no new GitHub Release until Zotero/Better Notes end-to-end verification.

## v0.4.1 (development build) — Import ChatGPT ZIP or Markdown as a Zotero child note

- Add right-click **Import ChatGPT ZIP / Markdown note** and a dedicated item-pane drag/drop target (does not intercept Zotero's native item list drag/drop).
- Validate ZIP entry count, traversal paths, duplicate names, and compressed/uncompressed size budgets before extracting Markdown and supported images to a temporary work directory.
- Use Better Notes' published `api.$import.fromMD(mdPath, {noteId, ignoreVersion: true})` to import into a new Zotero child note, preserving existing notes. Missing or incompatible Better Notes fails visibly without creating an empty note.
- Verify Markdown images exist; preserve the original ZIP as an additional Zotero attachment where the attachment API permits.
- Existing PDF/SI upload, full English research note prompt, 120k editor and no-auto-send unaffected.
- Development CI packaging only; requires Zotero 10 + Better Notes real-device validation before a stable Release.

## v0.4.0 — Consolidated latest release (Windows + macOS)

- Publish **one latest v0.4.0 XPI** for Windows Edge/Chrome and macOS Safari using the tested beta.21 functionality.
- Retain only historical v0.3.0 and v0.3.9 plus latest v0.4.0 in GitHub Releases; older test packages are removed only after the three stable installers are independently checked.
- Preserve the full 35,986-character default English Zotero/Obsidian scientific reading-note Prompt, main/SI contradiction checks, preliminary material and energy balances, interleaved figures, compact tables, MathJax guidance and verification-status labels.
- Preserve Windows PDF + SI PDF/Word attachments, full-Prompt paste verification, 120,000-character editor, existing macOS Safari workflow, and **no auto-send**.
- Remove superseded beta auto-publishing workflows. Older milestone packages are rebuilt from their original versioned files with identical bytes.

## v0.4.0 — Consolidated stable-numbered Release (Windows + macOS)

- Promote the verified beta.21 feature set to the single maintained **v0.4.0** XPI with no automatic sending. Preserve the full 35,986-character evidence-based research note, cross-source consistency checks, preliminary material and energy balances, Obsidian MathJax, figure placement and compact tables.
- Correct Windows stable build-marker matching and retain the PDF/Word SI multi-upload and prompt-paste regression tests.
- Retain only three GitHub Releases: historical original **v0.3.0** and **v0.3.9** XPI binaries, and current **v0.4.0**; remove superseded beta release entries without deleting historical Git tags.
- Prompt editor limit remains 120,000 characters and existing customised templates are preserved.
- Older beta Release entries are deleted only after the current stable XPI and both authentic historical XPI downloads have been verified.
- Release publication is checked separately before the historical Release cleanup, so no binary is deleted until the replacement is available.
- To preserve original source provenance under the available workflow permissions, the two historical Releases retain their original Git tags (`v0.3.0-beta` and `v0.3.9-beta`), but use clean displayed titles (`v0.3.0`, `v0.3.9`). The current stable Release is `v0.4.0`.

## v0.4.0-beta.21 — Refined research-note layout and verification-status default (Windows + macOS)

- Update the shared, complete **35,986-character** research-note Prompt: figures remain integrated in Sections 1–6, with explicit warnings against mixing whole-caption Markdown emphasis and LaTeX or accidentally interpreting adsorbed-site asterisks as Markdown syntax.
- Add measured-vs-calculated quality labels: **[Arithmetic checked]**, **[Partial balance]**, **[Order-of-magnitude estimate]**, **[Not verifiable from available sources]**. These qualify AI calculations; they do not claim primary experimental verification.
- Discourage sprawling multi-page tables and preserve the three-column figure index; PDF pagination belongs to the external Markdown/PDF renderer, which this Zotero upload bridge cannot control.
- Preserve the rigorous main/SI contradiction audit, preliminary material/energy balances, Obsidian MathJax $/$$ instructions and deliberately blank personal reflections.
- Preserve beta.20's corrected Windows PowerShell helper detection and multi-PDF/Word uploads; no automatic Send. Upgrade unchanged saved beta.20 built-in prompts while preserving actual user customisations. Prompt editor limit remains 120,000 characters.
- The GitHub publishing job inspects the completed XPI for the full prompt, supported Windows helper, build signature and regression tests before publishing.

## v0.4.0-beta.20 — Fix false “Windows automation script missing” alert

- Correct the Windows launch guard: beta.19 had a stale hardcoded beta.17 embedded-helper marker, rejecting its own valid PowerShell helper **before** creating a run folder.
- Validate the embedded helper's actual build signature and required entry points instead of comparing to a hardcoded old release; write the detected helper build to status.log.
- Add a regression test that injects the real Windows helper into the Zotero bridge and confirms a new run folder, UTF-8-BOM script, upload list and status file are prepared.
- Verify packaged helper marker matches manifest version at release time.
- The release job also unpacks the generated XPI and checks that bootstrap loads the actual Windows PowerShell source before publishing. Unchanged: 33,105-character English research-note default, 120,000-character editor limit, Obsidian MathJax guidance, cross-source and material/energy balance checks, safe sequential PDF/Word attachment uploads and Prompt paste.

## v0.4.0-beta.19 — Fix prompt input clipping; add material/energy balances and MathJax requirements

- New shared built-in Prompt (**33,105 characters**) extends the beta.18 note with rigorous preliminary elemental/material and power/energy balance checks, balance-completeness labels, and Obsidian-compatible MathJax delimiters.
- Increase the plugin-side Prompt limit **50,000 → 120,000 characters**. Remove native HTML maxlength from both editors to eliminate *silent* clipboard clipping. Intercept PDF-reader editor paste atomically, count characters before insertion and reject over-limit content visibly instead of truncating it.
- Show live editor length and verify the **entire saved preference** equals what the user entered before closing the editor. Preserve genuine customised prompts; automatically migrate the exact built-in beta.18 default.
- Keep Windows PDF/Word SI upload, full-prompt clipboard verification and macOS Safari automation unchanged. No auto-send.
- The built-in default avoids copying extremely long Prompt messages from a chat UI; use **Restore default** and Save. Browser/ChatGPT itself may still impose independent input limits; validate on real devices.
- GitHub Release packaging validates the exact 33,105-character built-in prompt and checks that no native HTML editor length attribute can silently clip pasted text.

## v0.4.0-beta.18 — Full prompt + expanded editor limit (Windows + macOS)

- Install the entire most recent 29,126-character English scientific reading-note Prompt as the shared built-in default. Includes full provenance, main/SI consistency checks, equations, integrated original figures, short Markdown table standards, and the 0–9 section research notebook.
- Increase custom Prompt validation and Zotero inline/Preferences editor length limits from 20,000 to 50,000 characters. Show live character count in the reader toolbar editor. No content truncation.
- Recognise the previously saved beta.17 built-in English default as an upgradeable default; preserve genuinely edited/custom prompts.
- Windows: verify **whole pasted prompt**, not just its first 30 characters; log expected/observed lengths without logging text. Keep Prompt on clipboard if automated verification fails, and never auto-send.
- Preserve the user-validated multi-attachment PDF/Word upload flow on Windows, and existing macOS Safari automation.
- The release bundle is checked for the full 29,126-character default Prompt and both platform scripts before the GitHub prerelease is published.

## v0.4.0-beta.17 — Shared English research note prompt (Windows + macOS)

- Replace the built-in Chinese analysis prompt with the user's full English-language, 0–9 structured critical-reading Markdown note, including source attribution, quantitative evidence, SI navigation, image rules and intentionally blank personal reflections.
- Use the same `ZCGBridge.defaultTemplate` on both Windows (Edge/Chrome) and macOS (Safari); all five metadata placeholders remain supported.
- English metadata fallbacks are `Not recorded` / `None` to avoid Chinese in the requested output.
- Preserve genuine saved custom prompts; automatically recognise the exact old Chinese built-in default even if previously saved in Zotero preferences.
- Retain the user-tested Windows sequential PDF + DOCX SI upload and prompt paste workflow; no automatic Send. No change to Safari GUI automation.
- Distribute one XPI with both Safari and Windows automation; the new long-form English note prompt is the default for either platform.

## v0.3.9 — Restore v0.3.0 keyboard picker for each attachment (macOS Safari user-tested)

- Per-file singleton staging keeps PDF+SI support with a full v0.3.0 `Go to Folder` → `Cmd+A` → `Return` chooser sequence.
- Removes the repeated slow AX `entire contents` selection and Upload button scans.
- No slow fallback: if the picker does not close, stop with a diagnostic log, leave the picker for manual action.
- Use hardlinks where possible and symlinks across volumes; never blindly Cmd+A an original Zotero attachment directory.
- User confirmed normal functionality of v0.3.9 on Zotero 10 + macOS Safari on 2026-10-14. Further environments remain untested.

## v0.3.8 — Quick-confirm test (local beta, not yet released)

- One-file picker: validate staging folder, locate native file list once, click first-row position and use native Return. Confirm picker closes without repeated AX enabled-button scans.
- Fall back to the working v0.3.7 accessibility path on failure, never auto-send ChatGPT.
- Built-in bridge/script version markers and timestamped logs retained.

## v0.3.7 — Diagnostic build identity (local beta, not yet released)

- Bump the addon package version to avoid ambiguity between multiple archives labeled v0.3.6.
- Write `BRIDGE_BUILD v0.3.7` and `EMBEDDED_SCRIPT_MARKER YES/NO` before launching Safari; log `SCRIPT_BUILD v0.3.7` from the running AppleScript.
- Fail safely before starting Safari when v0.3.7 code detects an embedded script that lacks the expected build marker.
- Keep the v0.3.6 fast-first-row selection logic and fallback; no change to PDF/SI selection, upload methods, prompt, or sending behavior.
- **Static checks only**: must be tested in a real Zotero 10/macOS/Safari environment.

## 0.3.6 — Fast file chooser selection (local beta)

- Keep the working 0.3.5 single-file hardlink chooser, with direct row selection tried before expensive filename AX discovery.
- Reduce repeated AX scans in the successful path; old AX discovery and keyboard modes remain fallbacks.
- Add human-readable timestamps to status.log to pinpoint any remaining delay.
- No changes to Zotero attachment filtering or Safari ChatGPT send behavior; no automatic Send.
- **Not yet validated on macOS.** Do not publish as a stable release until a real test succeeds.

## v0.3.5 (macOS Safari test build, 2026-10-14)

- Fix: when macOS file chooser opens the correct folder but fails to select the sole PDF/DOCX, try the native first file row before relying on `AXTextField` label clicks.
- Restrict any coordinate/Select-All fallback to a verified single-file hardlink staging folder. Never blindly select all in the Zotero source directory.
- Add granular log markers `FILE_LIST_GEOMETRY`, `FILE_LIST_CLICK`, `FILE_FIRST_ROW_SELECTED`, and `FILE_ROW_SKIP_UNSAFE` to diagnose inconsistent Accessibility trees.
- Keep v0.3.4 hardlink strategy, attachment discovery, editable prompt and never auto-send.
- **Static-tested only**; macOS/Safari GUI automation remains environment-specific.

## v0.3.4 (macOS Safari test build, 2026-10-14)

- Native upload picker now stages files using **hardlinks** when possible to avoid Finder Alias treatment; otherwise chooses original Zotero file directly. No document bytes are copied.
- More resilient Accessibility filename matching, click and focus fallback; strict enabled Upload/Open check; detailed diagnostics.
- No change to current-article/SI discovery, prompt editor, or manual Send policy.
- **Not tested on real macOS Safari yet.** Do not publish a stable release before end-to-end validation.

## 0.3.3-beta (local test build; not yet on GitHub)

- Fixed macOS file-picker Go-to-Folder misuse: v0.3.2 pasted a **file path** into a directory navigation dialog and could stall.
- Stage a *single symlink per picker directory*; no copies of original PDF or SI.
- Navigate to directory path only; select matching file row by accessibility, then click an enabled Upload/Open button instead of a blind second Return.
- Log `FILE_FOLDER_NAVIGATED`, `FILE_ROW_CLICKED`, `FILE_UPLOAD_BUTTON_CLICKED`, and explicit failures.
- Still requires manual review of attachments and manual Send; not tested yet on macOS.

# Changelog

## 0.3.2 Beta (file chooser reliability test)

- Fix the native macOS chooser stage where navigation into `links_only` succeeded but Cmd+A did not select/submit the files.
- Upload **one staged attachment per chooser** by navigating to its complete POSIX file path, instead of selecting all files in a folder.
- Add an ordered `upload_paths.txt` and progress/error entries in `status.log` (`FILE_START`, `FILE_PICKER_CLOSED`, `FILE_CHOOSER_STUCK`).
- Preserve original Zotero attachments, all-attachments/SI-only option, customizable prompt, no auto-send and Safari browser integration.
- Beta: browser GUI timing differs across macOS versions; requires real-device verification. A closed picker does not prove ChatGPT completed uploading the file.



## 0.3.1 Beta

- Default to **all supported local attachments under the current article’s Zotero parent item**; filenames no longer need SI/Supplementary keywords for DOCX/XLSX.
- Add **all attachments / SI-only** option in the existing `⚙` prompt editor (no extra modal).
- Record unsupported/missing/skipped files in selection metadata; classify unnamed non-PDF attachments as OTHER_ATTACHMENT.
- Add mock tests for generic DOCX/XLSX names, SI-only setting, and cross-parent isolation.
- Make XPI ZIP timestamps deterministic for reproducible SHA-256.


## 0.3.0 — Beta candidate

- Add Zotero PDF reader toolbar (`✦ ChatGPT`, prompt editor `⚙`).
- Support the current PDF and local same-parent SI attachment selection.
- Stage symbolic links instead of copying PDF bytes.
- Launch Safari UI automation in a best-effort hidden Terminal session.
- Remove plugin confirmation dialogs; never automatically click Send.

Known limitations: only macOS + Safari has been tested; Safari DOM and Accessibility automation are brittle; cannot reliably identify Chat versus Work; only one user device has verified the core upload path.
