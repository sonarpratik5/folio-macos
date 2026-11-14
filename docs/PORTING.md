# Web → native porting map

This is a continuation guide, not an approved feature backlog. Status describes this native repository only. Web reference details and snapshot limits are in [WEB_REFERENCE](WEB_REFERENCE.md).

| Web behavior / reference owner | Native adaptation | Status |
| --- | --- | --- |
| Home.tsx, recents.ts: library, resume, list/grid | LibraryView + PaperRecord + managed copies; native sidebar | Basic working equivalent; title search only, no document classification/details page |
| App.tsx, Page.tsx: local PDF reader | PDFCanvas/PDFView and ReaderView | Basic working equivalent; native continuous view/selection, page navigation/outline/zoom |
| reader-fit.mjs, search-text.mjs | PDFView auto-fit and PDFDocument.findString | Partial: no separate fit-width toggle, normalization parity, live debounced search or rotation control |
| annotations/state/types, pdf-tools.mjs | Standard PDFKit Highlight/Underline/Text annotations; explicit grouped Undo buttons | Partial: no mark selection/recolor/delete, on-page FreeText, eraser, image paste or cross-page attached passage notes |
| notes-view.mjs, NoteImages.tsx, drafts.ts | Written PDF comments in reader/global Notes | Partial: no note editing/attachments, source quote model, draggable pin UI, recovery drafts or browser migration |
| writing-space.mjs, writing-pdf.mjs | Native layout/export design required | Future: writing below pages and study-copy continuation sheets |
| RightSidebar.tsx | Resizable native inspector with Notes/Overview/Ask tabs | Native adaptation; no hover rail, pinned-preview behavior or Reviews tab |
| ConceptMap.tsx, paper-overview.mjs | Overview shows bounded opening excerpt | Partial: no inferred abstract/keywords, AI at-a-glance or concept graph |
| Assistant.tsx, Insight.tsx, assistant-threads.mjs | Honest Ask placeholder | Future: chat, citations, selection insights, persisted conversations and stream recovery |
| server/assistant.ts, assistant-provider.ts, paper-tools.mjs | Future native provider/context service | Future: Codex CLI / GPT-6.1 Terra medium and explicit Claude API parity; no backend process or hidden network calls now |
| Reviews.tsx, review-context.mjs | Future native service and inspector | Future: review discovery/analysis |
| ArxivImport.tsx, server/openreview.ts | Explicit URLSession import when authorized | Future: arXiv/download flows, cancellation and network validation |
| paper-access.ts, drop-file.mjs | NSOpenPanel, app-managed copy, NSSavePanel export | Intentional difference: source files are not overwritten; no folder scan, drag/drop or Finder document-open handler yet |
| preferences.ts, style.css, theme-studio.css | Adaptive AppKit colors, serif titles, native settings/sidebar | Partial visual translation; Classic/Studio green/blue accents; no full Studio skin or PDF dimming |
| Browser single-user startup | Native window opens immediately | Implemented: no login screens |

For subsequent work, ask the human to select scope. A sensible first slice to discuss is annotation edit/delete plus fixture-based export fidelity, followed by the assistant/provider path. Do not auto-implement either. Match behavior and data safety before promising pixel or feature parity.
