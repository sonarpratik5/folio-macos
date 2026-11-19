# Decisions

1. **Independent native repository (2026-11-14).** Human explicitly requested a new folder/repository and Swift Mac template, independent of the browser. SwiftUI + PDFKit, minimum macOS 14; no Electron/WKWebView, web server or login. The web project remains separate.
2. **Working foundation, explicit parity boundary.** Implement basic local reading and saved notes; map sophisticated web behavior instead of claiming to have ported it. No new unrelated product features.
3. **Managed copies.** Import stores a local PDF copy, simplifying permissions and making browser-free reopening reliable. Source files remain untouched. Original-handle overwrite and browser draft migration are not implemented. User-facing import/settings copy explains this intentional difference.
4. **Standard PDF annotations.** PDFKit holds native PDF marks/comments; metadata stores position/stars. Avoid duplicating browser annotation serialization without a tested migration contract. Export is a native save-panel copy.
5. **Explicit native AI authorization (2026-11-14).** The human requested web AI functionality in the Mac app. Home actions may send bounded extracted text to Codex CLI (GPT-6.1 Terra / medium) or explicit Claude API, with cancellation, restricted paper/web tools and no silent fallback. Keys come from the launch environment or native project `.env`, with legacy Keychain support; never forms or saved library data. Opening a sheet or restored overview never starts generation. The starter's earlier no-provider boundary is superseded only for these explicit actions.
6. **Portable development/context.** Dependency-free Swift package, app-bundle script, Python context router/checker and scoped instructions. New repo defaults private; no license, distribution certificate or machine-global agent settings selected.

## Reader editing interaction — 2026-11-14

The requested web-based PDF tool parity uses persistent Select/Highlight/Underline/Text/Note/Eraser in one native row, contextual formatting, click-away save and reversible grouped edits. During reading, application navigation collapses; Pages/Outline and written Notes are optional panels, initially closed. Unconnected Ask/Overview options are removed. The web remains reference-only and its existing dirty work is preserved. Open-source formal-methods research informs bounded independent state-sequence tests and the [case matrix](PDF_EDITING_VERIFICATION.md); this is not a formal proof of PDFKit or arbitrary PDF fidelity.

## Home and shared appearance — 2026-11-14

The human requested one Apple Liquid Glass–inspired theme throughout the Mac app. Adaptive native materials, restrained green, soft depth and opaque accessibility fallbacks replace the Classic/Studio theme choice. Color modes remain System/Light/Dark. Home details and AI use sheets, preserving reader identity and annotation editing ownership. The separate annotation task owns reader tools; home changes do not alter their controls or gestures.

## 2026-11-14 — Earlier web-matched palette (superseded by the default Liquid Glass theme below)

After hands-on testing the human asked for colors and sidebars "inspired by our web app". That iteration used the web light palette (`style.css`) and the web dark neutral charcoal (`theme-dark.css`), with flat backdrops. The later Liquid Glass request supersedes this chrome treatment; the later Preview highlight request below supersedes the web highlight fills. Underlines and text inks retain their earlier web values. Reduce Transparency fallback remains. The left sidebar uses web-style compact page rows with underline tabs, and the right panel uses web-style cards for written notes. The later notes-only requirement removes its Highlights tab.

## 2026-11-14 — AI tools live in the reader right panel, not sheets

The human first asked for the web AI features in the native app with polished UI, then said separate AI windows add friction and to follow the web UI. Ask, Peer reviews and Concept map are sections of the reader's right panel; the later Insights request below moves At a glance into the library. These tools use an always-visible icon rail, mirroring web RightSidebar; the AI sheets are removed. Requirements kept: requests start only from explicit user actions (Send, suggestion, Explain, Generate, Find), no background calls, and Explain Selection (⌥⌘E) sends immediately because it is explicit. Per-paper AI models live in Workspace so switching sections never cancels a request. This supersedes the sheet wording in decisions 5 and "Home and shared appearance".

## 2026-11-14 — Claude API key in the Keychain; one-click provider switch

The latest human instruction removes Claude API key entry from Settings and keeps the existing `.env` credential setup. The subsequent 2026-11-15 request removes the AI provider section from Settings; provider and Claude model selection live in AI panel header menus; there are no key entry, replacement or removal controls, and no “Add key” links. Environment `ANTHROPIC_API_KEY` retains priority over native project `.env`, then previously imported login-Keychain credentials. The native app does not automatically discover the web `.env`; its existing explicit dotenv-import command remains supported. No stored key or dotenv file is deleted or modified. The key is sent only to api.anthropic.com and is never logged or written to the library. Every AI panel header retains the shared provider switch. No automatic fallback between providers. This supersedes the earlier Settings key-entry decision.

## Minimal Insights and credential interaction (2026-11-14)

The human requested a real Insights page and Paper at a glance only there, never in PDF annotation. Insights is a library destination with explicit Read/source actions. The later paper-entry request replaces the selector/compact panel with the supplied reference layout: paper header, full abstract, contents outline, optional generated overview, notes and per-paper recent chats. Paper titles/thumbnails enter Insights first; explicit Read/Resume/source actions enter the PDF. Preserve the current native theme. Ask, Notes, Reviews and Map stay beside the PDF. This supersedes the earlier decision to put At a glance in the reader rail. Ordinary navigation/readiness checks must not request Keychain authorization. Secret retrieval is reserved for explicit Claude requests; a successful retrieval is reused for the process lifetime. The follow-up requires secret reads and writes to prohibit macOS authentication UI too; denied access must fail inline. Existing login Keychain protections remain in force.

## Selected-text clarification (2026-11-14)

The human clarified that missing Insights means explanations for selected PDF text. Keep explicit I/V mode; the later human request replaces the transient explanation sidebar with an anchored popup inspired by web Insight.tsx. Selecting text with the mode enabled is the explicit request; passive selection remains local. Keep Paper at a glance solely on the overview page. No per-selection chat threads or standalone reader windows. The popup uses native NSPopover. Preserve the sidebar state; use bounded selection surroundings, compact map and on-demand paper/web research to limit repeated input. The visible toolbar label is Insights; the separate page shortcut is labelled Paper overview for accessibility.

## Default Liquid Glass theme — 2026-11-14

The human requested an Apple-inspired default theme, informed by Dribbble, Behance and Apple's official guide, with clearly visible components. After rejecting the first green-tinted iteration, the human chose “Apple native: neutral, airy, subtle glass.” One theme now uses neutral light/charcoal surfaces, restrained blue action accents and system typography; System/Light/Dark remain color modes. This supersedes the earlier flat web-matched chrome requirement.

[Apple HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials) directs glass toward controls/navigation and recommends regular glass for legibility. Folio uses regular glass for the compact reader toolbar and panel-rail control group; structural sidebars use standard material on macOS 26+, with a regular-material fallback on 14/15 (older compilers omit the glass API). Reading cards, notes, editors and the PDF remain opaque. Reduce Transparency or Increase Contrast selects solid chrome; backgrounds remain neutral and flat. No decorative movement is introduced.

Visual references: [Iqbal Nurrofiq's Invoezy dashboard on Dribbble](https://dribbble.com/shots/26570052-Invoezy-Liquid-Glass-Dashboard-Design) informed soft depth and rounded functional groupings; [Luke Jones's Liquid Glass UI on Behance](https://www.behance.net/gallery/230705601/Liquid-Glass-UI) informed capsule controls and edge highlights. These are inspiration, not copied assets or a verified ranking of designs. Folio reduces their translucency and saturation for long reading. Main/secondary text and selected states have explicit contrast checks against the opaque palette; live light/dark glass was also checked in an isolated generated-sample app.

## 2026-11-14 — Remove the reader bottom bar

The human requested removing the repeated PDF title and persistent “Saved on this Mac” footer. Pagination moves to the existing top toolbar, remaining visible when annotation tools overflow horizontally. Keep direct page entry, page count, boundary-disabled previous/next buttons and existing page-focus shortcuts. Failed edits still show a conditional toolbar warning and the existing error alert.

Selection popup refinement (2026-11-14): human requested content-dependent height, a scrollbar for long insights, and slight transparency. Use natural content height up to a bounded response viewport and native thin material. Keep solid accessibility fallbacks and legible text.

## Notes and PDF annotations — 2026-11-14

The human requires highlights, underlines and on-page text to remain PDF annotations, without separate entries or a dedicated highlights section in Notes. The right Notes panel tracks only written notes and their attachments for the PDF. Annotation colors, editing, managed-copy persistence and PDF export remain supported.

## 2026-11-14 — Native dotenv provider configuration

The human explicitly supplied ANTHROPIC_API_KEY and OPENREVIEW_TOKEN / OPENREVIEW_USERNAME / OPENREVIEW_PASSWORD in the native `.env`. Read these locally without importing into Keychain or changing the file. OpenReview prefers token authentication and uses username/password sign-in when no token exists or it is rejected. Keep requests user-triggered and refreshed tokens in memory only.

## Folders and Recent — 2026-11-14

The sidebar prioritizes folders, per the human request. Opening a folder shows its PDFs; Recent provides newest-visit-first reader access across folders. Folder imports keep private managed copies, never write originals, and require an explicit reopen/Refresh folder to discover new files. Existing library and saved-work destinations remain secondary.

The 2026-11-19 privacy request supersedes build-recorded dotenv paths. Finder/Applications launches use the running user's `~/Library/Application Support/FolioMac/.env`; launch-environment variables retain priority, with native development dotenv and legacy Keychain fallbacks. Packaging must not embed the builder's personal source/debug paths or configuration path. Existing local credentials/libraries remain untouched.

## Paper at a glance parity — 2026-11-14

The human requested the existing web implementation as-is. Use ConceptMap.tsx, concept-view.mjs and the concept styles as the presentation reference: numbered Problem/Approach/Finding anchors, pastel sketch frames, selection details, source disclosure, Read/Ask, expand and explicit generation. Preserve native system typography, controls and the existing validated local overview format. No web source edits or new provider requests are required.

## Latest highlight wins — 2026-11-15

The human requested that highlighting the same text twice retain the most recent highlight without overlap. New highlights replace covered earlier color, preserve uncovered portions and written comments, and undo as one transaction.

## Adapted MiniLM Skim — 2026-11-15

The human chose adapted MiniLM only after rejecting larger SciBERT/ModernBERT options for size. Reuse the existing scim-adapted full-text pilot, without replacing it with the original web default, BERT-Tiny or a remote provider. Native Skim is explicit, local and view-only; Goal/Method/Result filters must not modify saved highlights, Notes or exported PDFs. FP16 Core ML weights reduce size while keeping the same architecture/checkpoint; conversion checks do not establish classification accuracy.

## Native reader parity — 2026-11-15

The human requested equation typesetting, expandable writing/study continuations, global conversation search, previous-passage return, recursive folder browsing/filtering, portable note images and dark PDF dimming, inspired by the web app. Extend the native app only and preserve concurrent work. Use a local bundled equation renderer without network dependencies; keep PDFKit source pages intact and augment explicit exported copies. Adapt writing to a page-specific expandable editor below the native canvas. Store chat/search data locally, send nothing on browsing, and preserve explicit provider-action boundaries. Keep display dimming reversible and separate from export bytes.

- 2026-11-15 sidebar simplification: folder browsing always includes descendants; no Include subfolders preference. Remove the Sample paper sidebar action and omit “A guide to reading research” from sidebar Quick access. Existing managed papers and notes are preserved.

- 2026-11-15 final-app sample cleanup: no guide shortcut or sample action in the sidebar or empty library. Keep synthetic sample generation reachable only through the opt-in QA harness for refinement; preserve existing managed papers and notes.

2026-11-15 human clarification: the requested Productivity interaction includes its working timer and smooth pull behavior. Supersedes the earlier launcher-only interpretation. Adapt the reference gesture/event/overlay implementation, with actual countdown, pause/resume, stop, presets and completion feedback, while retaining Open Folio and recent PDFs. Preserve native macOS 14+ and accessibility fallbacks; timer state is session-only.

## Skim edge indicators — 2026-11-15

The human requested that edge/corner indications apply to Skim, with explicit Goal, Method or Result roles, rather than saved highlights. Remove annotation edge indicators, including underlines/notes in the same old marker path. Preserve normal PDF annotation rendering and Skim's transient shading and filters.

## Preview highlight colors — 2026-11-15

The human requested exact Apple Preview highlight colors and explicitly limited the palette to four: yellow, green, blue and pink. Use Preview's opaque highlight RGB values without the prior web opacity treatment; preserve existing saved annotations unless explicitly recolored. Purple is excluded.


## Correctness/optimization audit — 2026-11-16

The human requested identifying/checking native application gaps, implementing confirmed corrections and assessing optimizations. Preserve existing product requirements; L5 retention and L6 Unread remain decisions to settle. Resolve the duplicated Option-Command-G shortcut by retaining Go to Page and assigning Shift-Option-Command-G to Paper at a Glance.
