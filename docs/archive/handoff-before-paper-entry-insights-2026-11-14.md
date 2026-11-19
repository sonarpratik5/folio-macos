# Current handoff

## Written-note-only inspector — 2026-11-14

- Request/status: highlights, underlines and on-page text are PDF annotations, not separate Notes entries. Done in native app. NotesInspector now lists only written notes/attachments; removed Highlights tab, mark cards, mark enumeration and obsolete QA right-tab command. Editing/color/PDF persistence unchanged. Web untouched.
- Changed Sources/FolioMac/NotesInspector.swift, QAHarness.swift, scripts/qa.sh and behavior/mechanism/requirements/parity/evidence docs. Fixed existing build failure by making LibraryView.PaperThumbnail internal for its InsightsView caller.
- Fresh checks: local-cache swift test --disable-sandbox --filter 'LibraryRepositoryTests|WorkspaceEditingTests' (with repository cache/config/security paths) passes 11/11; debug app bundle build passes with host packaging access. Context and whitespace checks pass. Sandboxed packaging failed at iconutil; host retry passed. GUI harness open-sample timed out, so no fresh visual QA claim. No new implementation-mirroring tests, real PDFs, provider calls, installation or publication.
- Prior active checkpoint preserved in [Insights popup handoff](handoff-before-notes-only-2026-11-14.md). All concurrent theme, icon, provider and reader work retained. Next authorized action: human feedback; no new feature queued.
