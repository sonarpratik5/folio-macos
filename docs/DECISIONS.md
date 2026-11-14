# Decisions

1. **Independent native repository (2026-11-14).** Human explicitly requested a new folder/repository and Swift Mac template, independent of the browser. SwiftUI + PDFKit, minimum macOS 14; no Electron/WKWebView, web server or login. The web project remains separate.
2. **Working foundation, explicit parity boundary.** Implement basic local reading and saved notes; map sophisticated web behavior instead of claiming to have ported it. No new unrelated product features.
3. **Managed copies.** Import stores a local PDF copy, simplifying permissions and making browser-free reopening reliable. Source files remain untouched. Original-handle overwrite and browser draft migration are not implemented. User-facing import/settings copy explains this intentional difference.
4. **Standard PDF annotations.** PDFKit holds native PDF marks/comments; metadata stores position/stars. Avoid duplicating browser annotation serialization without a tested migration contract. Export is a native save-panel copy.
5. **Explicit native AI authorization (2026-11-14).** The human requested web AI functionality in the Mac app. Home actions may send bounded extracted text to Codex CLI (GPT-6.1 Terra / medium) or explicit Claude API, with cancellation, restricted paper/web tools and no silent fallback. Keys come from the launch environment, never forms or saved library data. Opening a sheet or restored overview never starts generation. The starter's earlier no-provider boundary is superseded only for these explicit actions.
6. **Portable development/context.** Dependency-free Swift package, app-bundle script, Python context router/checker and scoped instructions. New repo defaults private; no license, distribution certificate or machine-global agent settings selected.

## Reader editing interaction — 2026-11-14

The requested web-based PDF tool parity uses persistent Select/Highlight/Underline/Text/Note/Eraser in one native row, contextual formatting, click-away save and reversible grouped edits. During reading, application navigation collapses; Pages/Outline and written Notes are optional panels, initially closed. Unconnected Ask/Overview options are removed. The web remains reference-only and its existing dirty work is preserved. Open-source formal-methods research informs bounded independent state-sequence tests and the [case matrix](PDF_EDITING_VERIFICATION.md); this is not a formal proof of PDFKit or arbitrary PDF fidelity.

## Home and shared appearance — 2026-11-14

The human requested one Apple Liquid Glass–inspired theme throughout the Mac app. Adaptive native materials, restrained green, soft depth and opaque accessibility fallbacks replace the Classic/Studio theme choice. Color modes remain System/Light/Dark. Home details and AI use sheets, preserving reader identity and annotation editing ownership. The separate annotation task owns reader tools; home changes do not alter their controls or gestures.

## 2026-11-14 — Web-matched palette (supersedes green-tinted glass look)

After hands-on testing the human asked for colors and sidebars "inspired by our web app". Theme tokens now use the web light palette (`style.css`) and the web dark neutral charcoal (`theme-dark.css`), and backdrops are flat. Annotation fills, underlines and text inks use the web hex values via `AnnotationPalette`. Highlight fill is stored pre-composited at 0.43 on white, and underlines use full strength. Reduce Transparency fallback remains. The left sidebar uses web-style compact page rows with underline tabs, and the right Notes/Highlights panel uses web annotation cards.

## 2026-11-14 — AI tools live in the reader right panel, not sheets

The human first asked for the web AI features in the native app with polished UI, then said separate AI windows add friction and to follow the web UI. Ask, Peer reviews and Concept map are sections of the reader's right panel; the later Insights request below moves At a glance into the library. These tools use an always-visible icon rail, mirroring web RightSidebar; the AI sheets are removed. Requirements kept: requests start only from explicit user actions (Send, suggestion, Explain, Generate, Find), no background calls, and Explain Selection (⌥⌘E) sends immediately because it is explicit. Per-paper AI models live in Workspace so switching sections never cancels a request. This supersedes the sheet wording in decisions 5 and "Home and shared appearance".

## 2026-11-14 — Claude API key in the Keychain; one-click provider switch

The human said “We have Claude API so implement that for AI features as well, like we can switch between codex and Claude API.” Apps opened from Finder/Dock do not inherit shell variables, so environment-only keys made Claude unreachable. Settings → AI assistant now saves a reader-entered key with `ClaudeKeyStore` (generic-password item `dev.folio.mac.claude-api`, `WhenUnlockedThisDeviceOnly`); `ANTHROPIC_API_KEY` in the launch environment still wins. The key is sent only to api.anthropic.com, never shown again, logged or written to the library. Settings also chooses Claude Sonnet 5.5 (default) or Opus 5.5 (`FOLIO_ASSISTANT_MODEL` overrides). Every AI panel header has a Codex CLI ⇄ Claude API switch that drives all AI features; a missing key shows a warning and an “Add Claude API Key…” link. No automatic fallback between providers.

## Minimal Insights and credential interaction (2026-11-14)

The human requested a real Insights page and Paper at a glance only there, never in PDF annotation. Insights is now a library destination with a paper selector and explicit Read/source actions. Ask, Notes, Reviews and Map stay beside the PDF. This supersedes the earlier decision to put At a glance in the reader rail. Ordinary navigation/readiness checks must not request Keychain authorization. Secret retrieval is reserved for explicit Claude requests; a successful retrieval is reused for the process lifetime. Existing login Keychain protections remain in force.
