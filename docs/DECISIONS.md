# Decisions

1. **Independent native repository (2026-11-14).** Human explicitly requested a new folder/repository and Swift Mac template, independent of the browser. SwiftUI + PDFKit, minimum macOS 14; no Electron/WKWebView, web server or login. The web project remains separate.
2. **Working foundation, explicit parity boundary.** Implement basic local reading and saved notes; map sophisticated web behavior instead of claiming to have ported it. No new unrelated product features.
3. **Managed copies.** Import stores a local PDF copy, simplifying permissions and making browser-free reopening reliable. Source files remain untouched. Original-handle overwrite and browser draft migration are not implemented. User-facing import/settings copy explains this intentional difference.
4. **Standard PDF annotations.** PDFKit holds native PDF marks/comments; metadata stores position/stars. Avoid duplicating browser annotation serialization without a tested migration contract. Export is a native save-panel copy.
5. **No provider connection in starter.** Chat/AI is visibly unavailable, with no synthetic answers, embedded credentials, automatic subprocesses or uploads. Future work must preserve user-triggered, bounded research context and cancellation.
6. **Portable development/context.** Dependency-free Swift package, app-bundle script, Python context router/checker and scoped instructions. New repo defaults private; no license, distribution certificate or machine-global agent settings selected.
