# Architecture

## Ownership

| Owner | Responsibility / entry points |
| --- | --- |
| [FolioApp](../Sources/FolioMac/FolioApp.swift) | App/window lifecycle, shared Workspace, native menus and Settings |
| [Workspace](../Sources/FolioMac/Workspace.swift) | Main-actor open/import/go/changedPage, active identity, tool/editor state, marks/notes, annotation history, export, synthetic sample |
| [WorkspaceView](../Sources/FolioMac/WorkspaceView.swift) | Native NavigationSplitView; library navigation collapses during reading |
| [LibraryView](../Sources/FolioMac/LibraryView.swift) | Library filtering/sorting, continue reading, table/grid, page-one thumbnails, all-paper written notes |
| [PDFCanvas](../Sources/FolioMac/PDFCanvas.swift) | ToolPDFView gesture/keyboard bridge, selection outline, paste, page notifications, anchored editor popover and restore suppression |
| [ReaderView](../Sources/FolioMac/ReaderView.swift) | Compact persistent-tool/context toolbar, optional Pages/Outline and Notes, footer pagination and Find |
| [Theme](../Sources/FolioMac/Theme.swift), [Settings](../Sources/FolioMac/SettingsView.swift) | One adaptive glass theme, opaque accessibility fallback, serif headings, color-mode/layout preferences |
| [PaperRecord](../Sources/FolioCore/PaperRecord.swift) | Codable schema-v1 library records; one-based pages and stars |
| [LibraryRepository](../Sources/FolioCore/LibraryRepository.swift) | Managed-copy paths/import, manifest validation, atomic persistence |
| [PDFEditing](../Sources/FolioCore/PDFEditing.swift) | PDFTool, finite crop geometry, group/hit/copy rules, FreeText metadata, PDFImageAnnotation, PDFEditHistory ordered snapshots and saved transitions |
| [AnnotationEditor](../Sources/FolioMac/AnnotationEditor.swift) | Captured page/annotation/selection draft, focused text/note popover and formatting |
| [PDFNotes](../Sources/FolioCore/PDFNotes.swift) | Standard Text comment extraction; bare marks excluded |
| [AssistantModels](../Sources/FolioCore/AssistantModels.swift) | Deterministic 12K map / 120K overview passages, byte-bounded lookup corpus, fingerprinted atomic AI persistence and source validation |
| [AssistantService](../Sources/FolioCore/AssistantService.swift), [AssistantProvider](../Sources/FolioCore/AssistantProvider.swift) | User-triggered research/overview prompts; isolated cancellable Codex processes or explicit Claude HTTP/tool loop |
| [PaperLookup](../Sources/FolioCore/PaperLookup.swift), [FolioPaperTools](../Sources/FolioPaperTools/main.swift) | Shared bounded read/search tools; private newline JSON-RPC MCP subprocess exposing only one request's extracted pages |
| [PaperAssistantView](../Sources/FolioMac/PaperAssistantView.swift), [AISettingsView](../Sources/FolioMac/AISettingsView.swift) | Sheet/model lifecycle, per-paper saved history/overview, cancellation, citations and provider setup |

## Data flow and invariants

App → shared Workspace → repository load → library. NSOpenPanel → temporary security-scope access → validated PDF → UUID managed copy → atomic manifest → Workspace.open → PDFCanvas. Each import is independent; there is no source-identity deduplication. UUID filenames avoid path traversal from untrusted PDF titles. Titles are display text.

Views call Workspace. PDFKit page notifications defer main-actor publication and check active document identity. PDFCanvas suppresses page-change notifications while assigning/restoring documents. Records/UI are one-based; PDFKit uses zero-based indices. No global PDFView singleton.

Selection → per-line/per-page finite crop-clipped PDFKit bounds → shared group ID → Workspace page changes → PDFEditHistory → managed PDF atomic save → history/revision refresh. A group is one logical selection, including cross-page marks and at most one written comment. Written quote/group/style/image metadata uses private PDF keys alongside standard editable annotations and appearance streams. PDFImageAnnotation draws a bitmap stamp; base64 PNG data reconstructs its appearance for later movement/resizing. FreeText uses Helvetica and stored size/ink to restore PDFKit's editable style getters after reopening; exported appearance remains standard PDF.

PDFEditHistory takes independent before/after annotation snapshots, validates document/page ownership, rejects duplicate/stale changes and records only successful saves. Replacing PDFAnnotation.copy() with independently constructed supported annotations avoids shared PDF dictionaries dropping edited annotations on subsequent saves. Undo/redo restore fresh annotation objects, preserve supported hit ordering, and retain the same history stack when saving fails. Expected live page arrays detect out-of-band mutation; generated Popup companions are snapshotted with their parent and recreated during encoding. Unrelated link/widget/foreign objects are retained rather than reconstructed; relative layering against such foreign objects is a remaining verification limit. Histories reset on document open. Text-field Undo stays with AppKit; reader Undo uses the annotation history.

Workspace loads a data-backed document independent of later managed-file replacements. AnnotationDraft captures the page, point, quote, original annotation and selection at editor opening. A small anchored popover saves nonempty input on Done, outside click or reader transitions; empty drafts and Cancel create no annotation/history. Quit attempts to finish the current draft and stays open if writing fails. Eraser previews collect hits over interpolated pointer segments, then commit the entire stroke once. Move/resize preview changes geometry without mutating the saved annotation until mouse-up. Stars/position remain separate metadata; source PDF content is not flattened or rebuilt.

## User-triggered AI flow

Library Ask action → assistant sheet → load that managed PDF without changing Workspace.activeID/document → deterministic extracted context and saved assistant snapshot. Only Send/Explain/Generate invokes AssistantService. Chat sends the compact map (12K characters); full extracted pages stay local until a read/search tool requests a bounded excerpt. Lookup JSON is capped at 1.6 MB with per-page truncation reported; read windows are 12K UTF-16 units, search returns at most eight ranked page excerpts. Overview supplies at most 800 passages / 120K characters, validates exact integer source IDs, and stores original extracted passages rather than model quotations. History and overview use `Assistant/<paper UUID>.json`, schema/identity/text-fingerprint validation and atomic writes; malformed or changed-document state fails closed.

Codex uses a private temporary directory, ephemeral/read-only execution, ignored user/project rules, disabled shell/files/plugins/skills and a credential-stripped environment. Its MCP helper receives only the chosen extracted-text JSON path, permits read/search only, and caps calls/input. Claude reads ANTHROPIC_API_KEY from the launch environment only for explicit API requests and supports the same local paper tools plus hosted web search. Both enforce bounded output/time/tool use and cancellation without fallback. The helper is packaged beside FolioMac; no Node/web server is needed. Provider messages and paper/web evidence remain untrusted. Full AI parity limitations are tracked in PORTING/QUALITY.

## Extension boundaries

FolioCore is the storage/model/service seam; FolioMac owns native UI and main-actor orchestration. Injectable HTTP/process transports permit disposable verification without live accounts. Future UI/provider expansion must retain bounded user-triggered context, cancellation and reader identity. The [porting map](PORTING.md) identifies remaining parity gaps. Swift Package Manager opens directly in Xcode; no generated Xcode project, Node toolchain or third-party package is required.

## Ownership additions (2026-11-14)

| Owner | Responsibility |
| --- | --- |
| [ReaderState](../Sources/FolioMac/ReaderState.swift), [ReaderControls](../Sources/FolioMac/ReaderControls.swift), [ReadingPosition](../Sources/FolioCore/ReadingPosition.swift) | Live search, zoom/fit/layout/rotation state and per-paper persistence; keyboard/menu controls; search normalization |
| [MarginMarks](../Sources/FolioMac/MarginMarks.swift), [MarginLayout](../Sources/FolioCore/MarginLayout.swift) | View-only margin bars/note glyphs and merge/stripe layout; never serialized to PDF |
| [LibraryImportViews](../Sources/FolioMac/LibraryImportViews.swift), [ArxivImport](../Sources/FolioCore/ArxivImport.swift), [LibraryOrganizing](../Sources/FolioCore/LibraryOrganizing.swift) | arXiv sheet/download/validation, sort/filter/search rules; LibraryView/LibraryRepository/PaperRecord (optional addedAt/author) and Info.plist document types own drop/open/rename/remove |
| [NotesInspector](../Sources/FolioMac/NotesInspector.swift), [Workspace+Notes](../Sources/FolioMac/Workspace+Notes.swift), [NotesSupport](../Sources/FolioCore/NotesSupport.swift) | Grouped note inspector, image attachments, drafts, ruled writing pages |
| [AssistantThreads](../Sources/FolioCore/AssistantThreads.swift), [AssistantStream](../Sources/FolioCore/AssistantStream.swift), [AssistantRichText](../Sources/FolioCore/AssistantRichText.swift), [InsightAnalysis](../Sources/FolioCore/InsightAnalysis.swift) | Thread persistence/migration, SSE streaming, Markdown/LaTeX-as-Unicode rendering model, offline skim |
| [AssistantRichView](../Sources/FolioMac/AssistantRichView.swift), [AssistantSurface](../Sources/FolioMac/AssistantSurface.swift), [NativeReviews](../Sources/FolioCore/NativeReviews.swift), [ConceptGraph](../Sources/FolioCore/ConceptGraph.swift), [PaperReviewsView](../Sources/FolioMac/PaperReviewsView.swift), [PaperConceptGraphView](../Sources/FolioMac/PaperConceptGraphView.swift) | Rich message UI, shared assistant surface, Reviews and Concept Map |
| [Theme](../Sources/FolioMac/Theme.swift) | FolioSpace/FolioRadius tokens and shared card/header/chip/notice components |

## Reader AI panel (2026-11-14)

Supersedes the sheet entries above (PaperAssistantView and the PaperSurface sheet are removed; their models remain).

| Owner | Responsibility |
| --- | --- |
| [ReaderPanel](../Sources/FolioMac/ReaderPanel.swift) | `ReaderPanel` (notes, ask, reviews, map sections), `ReaderPanelRail` (44pt icon rail, click selects or collapses), `PanelHeader`, `AskRequest`, `PaperAIStore` |
| [AskPanel](../Sources/FolioMac/AskPanel.swift) | Inline chat, history/options menus, suggestions, selection chip, retry/stop, citation navigation |
| [InsightsView](../Sources/FolioMac/InsightsView.swift), [PaperGlancePanel](../Sources/FolioMac/PaperGlancePanel.swift), ReviewsPanel in [PaperReviewsView](../Sources/FolioMac/PaperReviewsView.swift), ConceptMapPanel in [PaperConceptGraphView](../Sources/FolioMac/PaperConceptGraphView.swift) | Dedicated library Insights page (AI ideas + offline skim), plus reader Peer reviews and Concept map panels |

`PaperAIStore` is owned by Workspace and holds the per-paper assistant, reviews and concept models, so switching sections never cancels a request; opening another paper replaces it. `Workspace.present(...)` ([AssistantSurface](../Sources/FolioMac/AssistantSurface.swift)) routes overview to the Insights library destination without replacing the reader; other kinds open the paper if needed and select the panel; the `paperSurface` sheet is gone. Menu commands, PDF context-menu items, the rail and library Ask all route through `present`.

Codex config: `-c` values are serialized as JSON with `.withoutEscapingSlashes` (escaped `/` is invalid TOML and broke every path argument, such as model_instructions_file and the folio_paper MCP args). Codex reports failures as JSON events on stdout (`error`, `turn.failed`); `CodexFailure.message(stdout:stderr:)` extracts the reason (usage limit with reset time, sign-in, model access). Claude API: `pause_turn` from server web search continues the turn; the tool is `web_search_20260209`.

### Credential access and Insights ownership

`ClaudeKeyStore.hasKey` requests Keychain attributes with an `LAContext` whose `interactionNotAllowed` is true; view readiness never reads the secret. `CredentialSession` serializes secret loads and caches successful retrieval in process memory. Save/remove update the cache only after Keychain success; cancelled access can be retried by an explicit request. `InsightsView` owns an assistant model per inspected paper, cancels generation on departure, restores saved overviews, and routes citations through `Workspace.open(paper, at:)`. Workspace's separate `insightsPaperID` preserves reader identity/position during inspection. `Workspace.navigate` commits pending edits before changing library destinations.
