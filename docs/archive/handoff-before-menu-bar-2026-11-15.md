# Current handoff

## Skim role margin guides — 2026-11-15

- Request/status: remove corner/edge indications from saved highlights and apply them to PDF Skim with explicit Goal/Method/Result roles. Implemented in Sources/FolioMac/MarginMarks.swift: only active-document/enabled Skim passages feed margin guides, matching role colors, compact stacked labels, merged nearby roles, click-to-passage navigation. Saved highlights/underlines/notes no longer generate guides. Existing transient Skim shading unchanged.
- Regression: Tests/FolioMacTests/SkimWorkspaceTests.swift covers annotation exclusion, all four rotations, labels, filters, foreign documents and clearing. Updated docs/STATE.md, ARCHITECTURE.md, DECISIONS.md, QUALITY.md and TESTING.md. Existing routes cover source/test paths. Broad prior dirty work preserved.
- Checks: focused SkimWorkspaceTests **4/4 passed** with host macOS services (`/tmp/folio-skim-guides-tests-host.log`); sandbox Core ML exited signal 5. Debug app packaged/signature verified with host services (`/tmp/folio-skim-guides-build-host.log`); sandbox iconutil failed. Context/whitespace checks passed.
- Limits: GUI unverified: disposable QA launch ready but command timed out; CUA app inspection timed out. No screenshot, real paper/library edits, live provider request, installed-app replacement, commit or publication. Built bundle: .build/Folio.app. Dense/narrow/arbitrary PDF visual layout remains unverified. Next authorized action follows human request.
- [Preserved prior checkpoint](handoff-before-skim-margin-guides-2026-11-15.md) retains saved-history fix and installed-app state.
