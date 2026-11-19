# Current handoff

## Selection Insights saved-history error — 2026-11-15

- Request/status: fix “The saved assistant data could not be read. Its file was left untouched.” on selecting text in reader Insights mode. Fixed the dependency: popup now reads managed PDF via PaperAssistantModel.readPaper, independently of saved chat/overview state. Shared chat loading keeps its fail-closed behavior. No user data repaired, deleted or overwritten.
- Changed: Sources/FolioMac/PaperAssistantView.swift (shared read-only extraction), SelectionInsightView.swift (independent request loading), Tests/FolioMacTests/SelectionInsightTests.swift (malformed snapshot/thread, stale fingerprint, missing PDF regressions), docs/STATE.md, ARCHITECTURE.md, QUALITY.md, TESTING.md. Existing routes already cover these files; earlier dirty work preserved.
- Checks: focused SelectionInsightTests + PaperAssistantTests, 12 passed with host macOS services; `/tmp/folio-insight-tests-host.log`. Sandboxed test process exited signal 5. Release packaging passed with host services, `.build/Folio.app` signed/deep-strict verified; `/tmp/folio-insight-build-host.log` (sandbox dsymutil denied). Context and whitespace checks passed.
- Follow-up screenshot: old installed executable was still running. Staged/signature-verified workspace fix, gracefully quit, replaced `~/Applications/Folio.app`, reopened. Backup: `~/Applications/.folio-insights-update-ij39ol6m/Previous-Folio.app`.
- Limits: synthetic PDFs/fake provider; no fresh manual selection/live provider run, library repair, commit or publication. Updated installed app is reopened; next authorized action follows human request.
- [Preserved prior checkpoint](handoff-before-insight-history-fix-2026-11-15.md) retains toolbar QA and earlier history.
