# Current handoff

## Responsive Ask writing area — 2026-11-15

- Request/status: follow-up screenshot shows writing place squished when Ask opens. Fixed: composer starts at three lines and grows to six; header splits provider/close and title/chat controls into two rows; Ask reader split is min 320pt, ideal 380pt. Previous all-controls row required more width than the old 280pt split minimum. All existing dirty native/web work preserved.
- Changed: Sources/FolioMac/AskPanel.swift, ReaderView.swift; existing WebStyleRenderTests adds 280pt stress case and integrated open/resize/close/reopen reader fixture; docs STATE/ARCHITECTURE/TESTING/routes. Prior checkpoint: [Ask UI and installed-copy evidence](handoff-before-responsive-ask-2026-11-15.md).
- Checks: focused PaperAssistantTests + Ask panel/reader renders, host macOS services: 9 passed, 0 failures, /tmp/folio-ask-responsive-host-final.log. Integrated PDF width stays ≥350pt. Visually checked compact 280pt and passage fixtures; full reader 960×640 opening/resizing/reopening and 1380×880. Composer stays padded and roughly 75pt tall initially. No physical typing, divider drag, VoiceOver or live provider checks.
- Restricted AppKit runner exited signal 5; initial host fixture incorrectly expected NSTextView before editing. Corrected fixture and passing rerun above. Existing ReaderState publish-during-update warning persists.
- Release packaging and deep/strict signing passed (`/tmp/folio-ask-responsive-package.log`). Installed fresh verified bundle at `~/Applications/Folio.app`; backup `~/Applications/.folio-responsive-ask-82_01j0s/Previous-Folio.app`. Running session left open; quit/reopen to activate. Context and whitespace checks passed.
- Next: activate updated app and assess further human feedback. No commit/publication.
