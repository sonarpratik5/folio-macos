# Web → native porting map

Current source audit: 2026-11-14. The web app is reference material only; no web source changes were made for this audit. Implemented means a native code path exists; the evidence column distinguishes fixture tests from live or interactive verification. This is not a claim of complete web parity.

| Web behavior | Native status | Evidence and remaining limits |
| --- | --- | --- |
| Library, resume, list/grid, sorting and search | Implemented; folder membership and Recent visits are native adaptations | Repository/organizer/workspace tests; folder refresh keeps managed edits; recursive subfolder browsing/filter implemented; no watcher or reconciliation |
| PDF import, drag/drop, Finder open, arXiv | Managed copies; multi-select import, explicit arXiv download/cancel, removal, rename, Reveal in Finder and export | Generated-PDF import/source preservation tested; ID/URL parsing and PDF validation tested; symlinked managed-library export destinations rejected by fixtures; fresh Finder/drop/live arXiv interaction pending |
| Reading, page navigation, outline, thumbnails | Implemented through PDFKit and native controls | Reader rendering/finite-scale tests; Contents needs embedded bookmarks; no OCR |
| Find, fit, zoom, rotation, layouts | Normalized debounced all-match search; Fit Width/Page/Actual; single/two-page continuous layouts; per-paper view state, custom zoom preservation and identity-bound view saves | Search normalization/position tests; view-only rotation across writing-page insert/Undo/Redo and subsequent annotation save now regression-tested |
| Select, highlight, underline, text, note, eraser, image paste | Implemented; four Preview-matched highlight colors replace web fills, including latest-highlight replacement of overlapping color, recolor, edit, movement, resizing and session Undo/Redo | PDF round trips, cross-page groups, crop/rotation geometry, inline-text and failed-save fixtures; arbitrary PDFs and full gesture/accessibility matrix remain unverified |
| Notes, quoted comments, image attachments, drafts | Written/image-only note inspector, page groups, filter/edit/delete, attachment-only edits and new-draft recovery | Note stores and workspace persistence tested; failed note Save rebinds the restored target for retry; attachment-only drafts recover; no browser migration |
| Writing space | Compact, collapsible page notes below the PDF canvas, height-bounded expansion, paginated study-copy continuation sheets; ruled insertion retained | Save/Undo/Redo/failure recovery and repeat export tested; native page-specific editor is an adaptation of the web layout |
| Portable note attachments | Embedded payloads and visible image sheets in exported copies; no-sidecar reimport | Generated-image serialization/reimport/reexport verified; arbitrary third-party viewer interoperability not certified |
| Global conversations and passage returns | Cross-paper full-message search and exact-thread resume; bounded page/point return history | Local/legacy/corrupt chat fixtures, destination test and disposable GUI citation-return/search/resume pass |
| Right sidebar | Native Notes/Ask/Reviews/Concept map rail; selection Insights toggle | Native adaptation without web hover previews; no fresh interactive audit this session |
| Paper entry and overview | Dedicated Insights destination with Read/Resume, web-matched numbered three-card overview with selected details/sources, expand, Read/Ask, abstract/key terms, embedded Contents and recent chats | Exact-paper/thread continuation and overview state tests; generated PDF required for fresh full GUI pass |
| Chat and selected-text insights | Multiple local threads, suggestions/styles, selection context, clickable page citations, Stop/Retry | Fake-provider/process tests and selection gating/persistence tests; Claude streams, Codex completes; offline KaTeX typesetting verified with synthetic equations |
| Skim Goal / Method / Result highlights | Local adapted MiniLM, native Core ML, view-only overlays, per-role filters/counts and cancellation | FP16 compiled model ~46 MB; explicit on-device action, no provider/model fallback; tiny pilot checkpoint and PDF extraction still need representative human evaluation |
| Paper/web research, provider selection | Codex CLI default; explicit Claude API; bounded on-demand tools; native dotenv configuration | Request, cancellation, redaction and bounded-tool tests; live-provider tests skipped in this audit |
| Reviews and concept map | Discovery/analysis and source-linked concept graph/refinement have native implementations | Synthetic transport/graph tests; live OpenReview account and provider behavior not freshly verified |
| Settings and appearance | System/Light/Dark with optional PDF dimming; default Liquid Glass/material fallback; provider/model choice | Palette contrast tests; older OS, VoiceOver and full keyboard audit pending; no credential entry controls by prior human request |
| Local storage and distribution | Atomic individual writes, managed PDFs and local metadata/history | Failure/rollback fixtures; no cross-file transaction, web migration, notarization, updater or universal-distribution certification |

## Audit outcome — 2026-11-14

Core reader/library options have implementations and fixture coverage. Three refinements were made: writing-page saves preserve original page rotations; writing insertion clears abandoned annotation Redo; failed note Save retains the editable draft. A full suite passed before the final note refinement (106 tests, two opt-in live skips); all three focused regressions passed afterward. See [fresh evidence](TESTING.md#functionality-audit-and-writing-page-recovery--2026-11-14).

Completion remains conditional on a fresh interactive pass, live integrations and broader PDF fidelity checks. The disposable app launch was not executed because automatic approval review hit a usage limit. This audit does not certify every option end to end.

## Paper entry and Insights — 2026-11-14

Library paper rows, grid titles and thumbnails now enter a full paper-context destination before reading. The supplied web reference is adapted to native controls and the existing theme: header/Read/Resume, Overview/Notes, optional AI overview matching the web three-card layout and reveal/source/expand interactions (native system typography and controls), full abstract/key terms, embedded contents and recent paper-specific chats with continuation. Explicit reader shortcuts remain direct. Contents depends on embedded PDF bookmarks; no generated section detection or OCR is claimed.

Native credential parity: Claude and OpenReview now read the native local `.env`. OpenReview supports token and username/password login with one refresh/retry on rejection, matching the web authentication flow. No web source changes.

Local Mac app copies retain the original native dotenv path through generated bundle metadata; this is a native launch adaptation and does not embed credentials.

Native menu bar addition (2026-11-15): Productivity-style pull-to-set focus timer, click launcher with Open Folio and five recent PDFs, presets and timer controls. This is a native request independent of web parity.
