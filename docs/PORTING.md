# Web → native porting map

This is a continuation guide, not an approved feature backlog. Status describes this native repository only. Web reference details and snapshot limits are in [WEB_REFERENCE](WEB_REFERENCE.md).

| Web behavior / reference owner | Native adaptation | Status |
| --- | --- | --- |
| Home.tsx, recents.ts: library, resume, list/grid | Glass-inspired LibraryView, native sidebar, title/note search, totals, details, direct note/star pages and AI sheet | Working native adaptation; no folder scan or document classification; Opened includes all imports |
| App.tsx, Page.tsx: local PDF reader | PDFCanvas/PDFView and ReaderView | Basic working equivalent; native continuous view/selection, page navigation/outline/zoom |
| reader-fit.mjs, search-text.mjs | PDFView auto-fit and PDFDocument.findString | Partial: no separate fit-width toggle, normalization parity, live debounced search or rotation control |
| annotations/state/types, pdf-tools.mjs | Standard PDFKit Highlight/Underline/Text/FreeText/Stamp, six persistent tools and saved inverse edits | Core tool equivalent: select/recolor/delete, text editing/size/color/move/resize, gesture eraser, image paste/move/resize, cross-page quoted notes; broader fixture/interaction coverage remains |
| notes-view.mjs, NoteImages.tsx, drafts.ts | Editable quoted PDF comments in reader/global Notes | Partial: note text/quotes and on-page pin positioning supported; no note-image attachments, durable recovery drafts or browser migration |
| writing-space.mjs, writing-pdf.mjs | Native layout/export design required | Future: writing below pages and study-copy continuation sheets |
| RightSidebar.tsx | Optional Pages/Outline panel and focused Notes inspector; library sidebar hidden in reader | Native adaptation: both panels collapsed initially; no inactive tabs or hover rail |
| ConceptMap.tsx, paper-overview.mjs | Paper at a glance in the dedicated library Insights page | Source-backed Problem/Approach/Finding cards, saved restore, explicit generate/regenerate; no concept graph/refinement or inferred abstract/keywords |
| Assistant.tsx, Insight.tsx, assistant-threads.mjs | Native PaperAssistantView sheet, per-paper local history | Chat, selected-passage explanation, STE style and clickable citations; completion-only responses, one conversation per paper, no streaming recovery or LaTeX rendering |
| server/assistant.ts, assistant-provider.ts, paper-tools.mjs | Native AssistantService/Client + FolioPaperTools executable | Codex CLI / GPT-6.1 Terra medium default, explicit Claude API, cancellation, compact map and bounded on-demand paper/web tools; no web runtime dependency; live provider access unverified |
| Reviews.tsx, review-context.mjs | Future native service and inspector | Future: review discovery/analysis |
| ArxivImport.tsx, server/openreview.ts | Explicit URLSession import when authorized | Future: arXiv/download flows, cancellation and network validation |
| paper-access.ts, drop-file.mjs | NSOpenPanel, app-managed copy, NSSavePanel export | Intentional difference: source files are not overwritten; no folder scan, drag/drop or Finder document-open handler yet |
| preferences.ts, style.css, theme-studio.css | One adaptive Liquid Glass–inspired green/neutral theme | Intentional native design: material surfaces, serif titles and accessibility fallback; System/Light/Dark color modes, no Classic/Studio switch or PDF dimming |
| Browser single-user startup | Native window opens immediately | Implemented: no login screens |

Remaining parity gaps describe boundaries, not an automatic backlog. Match behavior and data safety before promising pixel or complete feature parity. The home/AI and annotation tasks maintain separate implementation ownership.

## Status update — 2026-11-14 (built and unit-tested; no interactive GUI QA)

| Area | Status |
| --- | --- |
| Fit/search (reader-fit, search-text) | Implemented: Fit Width/Page, zoom, view rotation, layouts, debounced all-match search with normalization |
| Notes (notes-view, NoteImages, drafts) | Implemented natively: grouped inspector, image attachments, draft autosave; no browser migration |
| Writing space | Partial: blank ruled PDF pages after current page/at end; no web writing-space layout parity |
| ConceptMap, Reviews | Native Reviews and Concept Map views exist; live provider/network behavior unverified |
| Assistant threads/streaming | Multiple threads, Claude SSE streaming/Stop/Retry; Codex completion-only; LaTeX not typeset |
| ArxivImport | Implemented: explicit download, cancel, PDF validation, managed copy; unverified against live arXiv in GUI |
| paper-access, drop-file | Drag-drop, Finder Open With, dock drop, multi-select open panel, remove (managed copy only) |
| Margin marks | Native-only addition; rotation refresh unverified by eye |

These rows supersede the older Partial/Future rows above for the same areas.

## Status update — 2026-11-14, inline reader panel (built and unit-tested; partial GUI QA)

The human asked to reduce friction, so web RightSidebar's rail model is followed. These rows supersede the Assistant/ConceptMap/Reviews rows above.

| Area | Status |
| --- | --- |
| RightSidebar (rail) | Native reader panel with a 44pt always-visible icon rail; Notes, Ask, Peer reviews, Concept map sections; click the open section to collapse |
| Assistant.tsx, Insight.tsx | Inline Ask chat (history, new chat, options, suggestions, selection chip, Explain this passage, stop/retry, page citations); no sheet. Web Insights-on-selection auto mode and Skim highlight overlay not ported |
| ConceptMap.tsx, paper-overview.mjs | Insights page: saved source-backed overview plus offline skim, paper picker and direct source navigation; Concept map remains a reader panel |
| Reviews.tsx | Peer reviews panel; live review discovery unverified |
| Codex / Claude providers | Codex CLI config and failure reporting fixed; Claude `pause_turn` continues; live success unverified |
