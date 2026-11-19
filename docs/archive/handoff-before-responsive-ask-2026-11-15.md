# Current handoff

## Ask interface layout — 2026-11-15

- Request/status: fix Ask UI issues shown in native macOS screenshot. Done: taller intrinsic-height composer, readable placeholder, integrated 32pt Send/Stop with focus outline, matched 14pt saved/streamed answer typography and line spacing, labeled Copy below answer, latest-exchange scroll on opening saved chat. Preserved all pre-existing dirty native/web work; no provider or persistence changes.
- Changed: Sources/FolioMac/AskPanel.swift; existing Tests/FolioMacTests/WebStyleRenderTests.swift adds six opt-in synthetic Ask render fixtures; docs STATE/ARCHITECTURE/TESTING/routes. Previous checkpoint: [pull timer and install evidence](handoff-before-ask-layout-2026-11-15.md).
- Checks: focused PaperAssistantTests plus Ask rendering and theme contrast: 9 passed, 0 failures, /tmp/folio-ask-focused.log. Inspected all six /tmp/folio-ask-render/ask-*.png fixtures: conversation, narrow, dark, empty, streaming and selected passage/multi-line prefill. Broader initial render run crashed in unrelated reader/library test after Apple Vision CVPixelBuffer errors; no full-suite pass claimed.
- Release packaging/signing passed with host services: /tmp/folio-ask-package-host.log; sandbox attempt blocked at dsymutil. No live provider, real-paper automation, physical keyboard/mouse or accessibility coverage. No commit/publication.
- Installed verified release at ~/Applications/Folio.app; prior bundle retained at ~/Applications/.folio-ask-update-mg2p9215/Previous-Folio.app. Running session left open. Context validator and whitespace checks passed.
- Next: quit/reopen Folio to activate the rebuilt code; assess further UI feedback from the human.
