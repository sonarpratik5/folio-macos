# Current handoff

## Final-app sample cleanup — 2026-11-15

- Request/status: remove the reading-guide and Sample paper entries from the final app; retain internal refinement fixtures. Sidebar already omitted both; removed remaining Open sample button in LibraryView empty state. Workspace.sample is now documented as QA-only; QAHarness is its only caller. Existing managed papers and notes are preserved.
- Changed: Sources/FolioMac/LibraryView.swift, Workspace.swift; docs STATE, ARCHITECTURE, DEVELOPMENT, DECISIONS, TESTING. Preserved all pre-existing dirty work.
- Release bundle build passed with host services: `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh release`; `.build/Folio.app` signed and deep/strict verified. Log `/tmp/folio-sample-cleanup-build-host.log`. Restricted attempt failed at dsymutil (Operation not permitted). Context and whitespace checks passed. Source inspection verified UI removal and sole QA caller.
- Limits: no fresh GUI evidence or unit suite for this button-only change; no installed copy replacement, real-library edit, commit or publication. Next action follows the human request.
- [Preserved compact-page-notes checkpoint](handoff-before-sample-cleanup-2026-11-15.md) retains concurrent work and earlier history.
