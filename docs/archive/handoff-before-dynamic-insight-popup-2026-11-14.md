# Current handoff

## Remove reader footer — 2026-11-14

- Request/status: remove repeated PDF title and Saved on this Mac bottom bar; keep page number in the interface. Done in ReaderView only. Previous/next, editable current page and total are pinned to the top toolbar outside its existing overflow scroller. PDF gets the former footer height. Error-only Edit not saved warning retained beside pagination; existing save-failure alert unchanged.
- Verification: local-cache Swift build and `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh debug` with macOS host tooling pass. CUA in isolated pagination-preview/disposable sample confirms no footer, toolbar pagination, Previous disabled on page 1 and Next navigating to page 2. Direct-entry attempt interrupted by preview changing to Insights with generation visible; no direct-entry/final-boundary/provider-success claim. Preview terminated. No real PDF or credential edits. Narrow width, light mode and save-failure rendering not freshly checked; no new unit tests for layout-only move. Context/whitespace pass; evidence in TESTING.
- Updated STATE, ARCHITECTURE, DECISIONS and TESTING. Built app `.build/Folio.app`. Preserved concurrent native changes and dirty web repository. [Prior selection-Insights checkpoint](handoff-before-reader-footer-removal-2026-11-14.md) preserves popup/context/icon/copy/credential evidence and archives. No publication or install.
- Next action follows human feedback; no new feature backlog.
