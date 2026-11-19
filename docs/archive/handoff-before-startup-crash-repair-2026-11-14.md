# Current handoff

## Native functionality audit — 2026-11-14

- Human scope: refine Mac only, refer to web without editing it. Audited option owners and consolidated stale parity claims in PORTING. Existing native/web dirty work, including concurrent folder/Recent and dotenv packaging changes, preserved.
- Fixed: ReaderState tracks intrinsic rotation by PDFPage identity; writing insert/Undo/Redo saves with original angles, reapplies view rotation/fit and refreshes search after structure changes. Successful writing insertion abandons annotation Redo. NotesInspector keeps draft editing open when updateNote persistence fails.
- Changed source: FolioCore/PDFEditing.swift, FolioMac/ReaderState.swift, Workspace+Notes.swift, NotesInspector.swift. Three regression tests in ReaderRenderTests.swift; initial rotation test failed 18 assertions, then passed. STATE/ARCHITECTURE/PORTING/QUALITY/TESTING updated.
- Fresh checks: full local-cache Swift suite with macOS service access before final note refinement: 106 total (31 Mac + 75 core), zero failures, two live-provider skips. After final refinement: three focused recovery/writing tests pass under ordinary restrictions. Full suite not rerun after that small final change. Debug bundle built with host icon services; latest test-built executable copied into bundle, ad-hoc signed and strict/deep signature verification passed. Context check (6 routes/81 paths) and whitespace check passed. Exact commands/limits in TESTING.
- GUI blocker: disposable launch was not executed because automatic approval review hit its usage limit; no fresh interactive verification. Earlier restricted full tests hit macOS service failures; host rerun passed. Live AI/OpenReview/arXiv, Finder/drop/dialog flows, accessibility/older macOS and arbitrary-PDF fidelity remain unverified in this audit. Full web parity absent (LaTeX, Skim overlay, below-page writing layout/migration).
- Deliverable: .build/Folio.app (not installed, committed or published). No real PDF/library changes. Web baseline tests passed 360/360; web source unmodified by this task.
- Next authorized action: when approval review is available, finish a disposable GUI/integration pass per DEVELOPMENT; do not claim every option certified from builds/tests alone. [Prior folder/Recent checkpoint](../archive/handoff-before-functionality-audit-2026-11-14.md) preserves preceding work and links.

## Preserved concurrent installed-dotenv follow-up

The separate credential task added FolioEnvironmentFile path discovery, passed 28 host-service tests and installed/verified its staged build; CUA saw no missing-key warning, without a new provider request. Its [prior checkpoint](../archive/handoff-before-installed-dotenv-fix-2026-11-14.md) and [full evidence](../TESTING.md#installed-dotenv-launch-fix--2026-11-14) remain. This folder task did not install over that app.
