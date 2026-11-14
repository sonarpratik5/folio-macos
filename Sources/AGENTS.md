# Native code

Read root rules and route to the owner before editing. `FolioMac/Workspace.swift` owns orchestration and active-document identity; FolioCore owns models, persistence, and PDF note discovery. Views call Workspace rather than writing files. PDFCanvas bridges PDFKit notifications to main-actor state and suppresses initial page events during restoration.

Use one-based pages in records/UI and zero-based indices only at PDFKit boundaries. Keep multi-line highlights grouped into one annotation Undo transaction. Never show bare marks in Notes. Data writes must be atomic; startup decoding failure must not create a replacement manifest. Keep source PDFs unchanged and disclose copy/export semantics.

PDFKit geometry uses PDF page coordinates; test selection on cropped/rotated pages before expanding annotation tools. Do not flatten, rasterize or reconstruct a user's PDF to simplify editing. AppKit/PDFKit UI belongs on the main actor. A build does not prove annotation geometry, accessibility, export compatibility or visual parity.
