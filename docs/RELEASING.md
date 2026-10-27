# Release and CI maintenance

## The two maintained GitHub Actions workflows

1. **CI** (`.github/workflows/ci.yml`) runs on pushes to `main`, on pull requests targeting `main`, and when manually dispatched. Feature-branch pushes no longer cause a redundant second CI run; superseded CI runs are cancelled. Documentation-only edits are excluded. The Windows version of the CI includes PowerShell parsing and staged-attachment tests.
2. **Release (manual)** (`.github/workflows/release.yml`) is only launched through **Actions → Release (manual) → Run workflow**. Ordinary pushes never publish GitHub Releases.

All one-off beta, historical-pruning, and version-specific publishing workflows have been removed.

## Publishing a future stable version

1. Finish and review changes, preferably merging a tested feature branch into `main`. The Windows feature PR is currently a draft; review it before merging.
2. Set `src/manifest.json` to the desired stable version, for example `0.4.1`, and ensure the source passes CI. **The `main` source branch may lag behind the published v0.4.0 tag until feature integration is completed.**
3. Start **Release (manual)**. Set `version` to `0.4.1` (no leading `v`) and `source_ref` to the reviewed source branch or commit (prefer `main` after merging).
4. The workflow checks the manifest matches the requested version, refuses to replace existing tags/Releases, runs JavaScript/smoke/Windows parser checks, builds a single XPI, validates its manifest and SHA256SUMS, and publishes the Release.
5. Confirm the new XPI downloads correctly before announcing it. If a fix is required, bump the patch version; do not silently rewrite a published tag.

The Releases page intentionally retains exactly three entries: historical `v0.3.0` and `v0.3.9` (their original Git tags include `-beta` to preserve provenance), and current stable `v0.4.0`.

## Reducing GitHub notification noise

- Do not create a new workflow YAML for every beta or release.
- Avoid pushing partly edited code on every individual step; CI can still report genuine errors for commits that contain incomplete work.
- [GitHub notification settings](https://github.com/settings/notifications) → **System → Actions** allows switching from **Email** to **On GitHub**, or retaining email but selecting **Only notify for failed workflows**.
- Old failed Actions runs and already-sent notification emails remain historical records. Removing obsolete workflows prevents future triggers, not past emails. New genuine failures may still generate email if GitHub Actions email notifications remain enabled.
