# Architecture

## Ownership

| Owner | Responsibility / entry points |
| --- | --- |
| [FolioApp](../Sources/FolioMac/FolioApp.swift) | App/window lifecycle, shared Workspace, native menus and Settings |
| [Workspace](../Sources/FolioMac/Workspace.swift) | Main-actor open/import/go/changedPage, active identity, marks/notes, annotation Undo, export, synthetic sample |
| [WorkspaceView](../Sources/FolioMac/WorkspaceView.swift) | Native NavigationSplitView and persistent library sidebar |
| [LibraryView](../Sources/FolioMac/LibraryView.swift) | Library filtering/sorting, continue reading, table/grid, page-one thumbnails, all-paper written notes |
| [PDFCanvas](../Sources/FolioMac/PDFCanvas.swift) | NSViewRepresentable PDFView bridge, PDFViewPageChanged coordinator, restore-event suppression |
| [ReaderView](../Sources/FolioMac/ReaderView.swift) | Compact annotation/page toolbar, page list/outline, Find, notes sheet, Notes/Overview/Ask inspector |
| [Theme](../Sources/FolioMac/Theme.swift), [Settings](../Sources/FolioMac/SettingsView.swift) | Adaptive native colors, serif headings, UserDefaults appearance/accent/layout preferences |
| [PaperRecord](../Sources/FolioCore/PaperRecord.swift) | Codable schema-v1 library records; one-based pages and stars |
| [LibraryRepository](../Sources/FolioCore/LibraryRepository.swift) | Managed-copy paths/import, manifest validation, atomic persistence |
| [PDFNotes](../Sources/FolioCore/PDFNotes.swift) | Standard Text comment extraction; bare marks excluded |

## Data flow and invariants

App → shared Workspace → repository load → library. NSOpenPanel → temporary security-scope access → validated PDF → UUID managed copy → atomic manifest → Workspace.open → PDFCanvas. Each import is independent; there is no source-identity deduplication. UUID filenames avoid path traversal from untrusted PDF titles. Titles are display text.

Views call Workspace. PDFKit page notifications defer main-actor publication and check active document identity. PDFCanvas suppresses page-change notifications while assigning/restoring documents. Records/UI are one-based; PDFKit uses zero-based indices. No global PDFView singleton.

Selection → per-line/per-page PDFKit bounds → grouped annotations → managed PDF atomic save → Undo registration → revision refresh. On a failed write, the in-memory change is rolled back. Reverse transactions save the PDF again. Undo resets when opening a paper; text editor undo belongs to AppKit, while annotation Undo uses explicit buttons. Star/position changes write metadata separately and do not export as PDF comments. PDF content is authoritative for notes and marks, avoiding a second sidecar annotation format.

## Extension boundaries

FolioCore is the storage/model seam; FolioMac owns native UI and orchestration. No AI service protocol is included before requirements exist. Add a main-actor observable assistant model plus a Sendable service protocol for provider work when authorized, keeping credentials in Keychain and implementing bounded, user-triggered paper context with cancellation. The [porting map](PORTING.md) identifies source behavior to inspect first. Swift Package Manager opens directly in Xcode; no generated Xcode project, Node toolchain or third-party package is required.
