# Current handoff

## Compact page notes — 2026-11-15

- Request/status: refine the native page-extension notes feature to use minimal space and reliable saves. Compact implementation in WritingBelowView/ReaderView: 32-point header, 64-point scrolling editor, collapse, expansion bounded to a third of reader height, retained size choice, contextual Save/retry/checkmark, ⌘Return and focus on opening. No permanent footer.
- Workspace stages input synchronously, flushes before close/navigation/export/quit and annotation Undo/Redo; failed saves retain input and block transitions. Existing ReaderParityTests cover close, deletion/Undo, pending-input Undo/Redo and failure recovery. Existing broader/concurrent work preserved.
- Fresh focused SwiftPM test command with local caches, --disable-sandbox and filter ReaderParityTests|StudyCopyTests: 9 passed, zero failures. Focus-on-open added afterward and compiled in final release. Host-service release build passed; `.build/Folio.app` ad-hoc signed/deep-strict verified. Logs `/tmp/folio-page-notes-{tests,build}.log`. Context (6 routes/93 paths) and whitespace checks passed. [Exact evidence](../TESTING.md#compact-page-notes--2026-11-15).
- Limit: GUI check incomplete; disposable launch reported ready but QA notification timed out before sample/screenshot. No visual, accessibility or arbitrary-PDF guarantee. Pending 650 ms buffer remains non-durable on crash. No real library/paper edits, live AI, installation, commit/push/publication. Next authorized action follows the human request.
- [Previous reader checkpoint](handoff-before-compact-page-notes-2026-11-15.md) preserves concurrent work and earlier checkpoints.

Preserved concurrent history: [Find/performance](handoff-before-search-performance-2026-11-15.md), [sidebar](handoff-before-sidebar-simplification-2026-11-15.md).
