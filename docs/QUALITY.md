# Quality and limits

- Q1: PDFKit serialization is not a full-fidelity guarantee for arbitrary PDFs, signatures, forms, embedded fonts or existing third-party annotations. Tests cover only generated fixtures and preserve the source. Add a synthetic fidelity matrix before broad export claims.
- Q2: Multi-column/rotated/cropped/non-Latin and cross-page selection geometry needs interaction testing. Scanned PDFs need OCR, which is absent. Highlights/underlines cannot yet be selected, edited or individually erased in-app; Undo is session-only.
- Q3: Manifest and PDF writes are individually atomic, not a cross-file transaction. Import rollback handles manifest failure; a crash between copy and manifest can leave an orphan. No recovery UI, version history, migration beyond schema rejection or multi-process coordination. Do not run concurrent app instances against the same library.
- Q4: PDF loading, explicit Find, thumbnail generation and all-library note scanning run on the main actor. Large libraries/papers may pause the UI. No bounded async repository or thumbnail cache yet. Metadata is saved on page changes without coalescing.
- Q5: Minimum window size is 960×640; toolbar scrolls if space is tight. VoiceOver, full keyboard focus, split-pane restoration and all display-scale combinations need a broader audit. Dark mode affects chrome, not PDF contents. Settings presets are not full visual parity.
- Q6: Local app is ad-hoc signed, unsandboxed and unnotarized. No App Store entitlements, security-scoped bookmark persistence, automatic updates, universal binary or Finder file associations configured. Packaging is for development on the build machine.
- Q7: No web-data migration. Export browser annotations to PDFs first where supported; browser-local stars/chats/drafts will not appear automatically. Reimports create separate copies. There is no native delete-library-entry action yet.
- Q8: Overview is a first-page excerpt, not an abstract detector or AI summary. Ask is a placeholder. No backend/provider integration, review discovery, graph, arXiv import, attachments or writing extensions. [PORTING](PORTING.md) is authoritative for parity.

Verification belongs in [TESTING](TESTING.md). Open quality items are context, not automatic authorization to work on them.
