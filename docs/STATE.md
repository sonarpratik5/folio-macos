# Current state

Native macOS starter, created 2026-11-14. SwiftUI window/navigation/settings and AppKit panels wrap PDFKit directly. No browser wrapper, authentication or server.

- Library: import one PDF into a managed copy, table/grid views, title search, last-opened/title sort, continue reading, All documents/Opened/Notes/Starred pages. Every import opens the paper, so Opened currently contains all imports. Starred pages filters papers with stars; page-level stars appear in reader navigation.
- Reader: continuous vector PDF rendering, native selectable text, page list, embedded outline, page-number input/previous/next, auto-fit and manual zoom, explicit whole-PDF Find with match navigation. Initial resume position and subsequent page changes save locally.
- Annotations: selection highlights/underlines in four Folio colors, grouped annotation Undo/Redo buttons, standard written PDF Text comments and note deletion. Notes lists exclude bare highlights/underlines. Note placement uses the current-page selection or a default margin point. Notes are added/deleted; in-app note editing is not implemented.
- Storage: atomic manifest/PDF writes under Application Support, managed copies independent of source file permissions, metadata schema check, load errors preserve existing files and block imports. Explicit export copy. Settings uses native UserDefaults. No source-file handles, web-data import, library removal or cloud sync.
- Design: Classic forest-green accent and serif headings, quiet paper/canvas surfaces; optional Studio blue accent. Native resizable sidebar, split document navigation and notes inspector, toolbar/menu shortcuts; Light/Dark/System chrome. Studio's full web surface/font treatment is not ported.
- Overview: title/page count and bounded first-page excerpt only. Ask explicitly reports that AI is not connected. No AI calls or fabricated summaries. Generated sample contains only synthetic instructional text.

See [porting map](PORTING.md) for incomplete functionality and [evidence](TESTING.md) for what was actually tested.
