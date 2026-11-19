# Current handoff

## Preview highlight palette — 2026-11-15

- Request/status: match Apple's Preview highlight colors; human explicitly wants only yellow/green/blue/pink, no purple. Implemented: #FACD5A / #7CC868 / #69B0F1 / #FB5C89 opaque sRGB, no extra web fading. Values verified from installed Apple AnnotationKit helper/theme; app ships constants with public APIs only.
- Changed: AnnotationPalette, reader/sidebar/Notes swatch callers, WebStyleRenderTests, docs STATE/ARCHITECTURE/PORTING/DECISIONS/TESTING. Existing saved marks retain their colors and legacy palette recognition. Underline/text inks preserved. Preserved pre-existing dirty native/web work.
- Checks: 4 focused tests passed, 0 failures, /tmp/folio-preview-palette-tests.log; exact RGB and PDF save/reopen, preferences, Workspace replacement/Undo/Redo. Context validator and whitespace checks passed. Preview menu inspected on a generated sample; CUA then failed, so no side-by-side visual match claimed.
- Previous active responsive Ask/install checkpoint preserved in [previous handoff](handoff-before-preview-colors-2026-11-15.md). No commit/publication.
- Packaging: release build and deep/strict signing passed with host services, /tmp/folio-preview-palette-package-host.log. Sandbox attempt blocked dsymutil.
- Installed verified release at ~/Applications/Folio.app; backup ~/Applications/.folio-preview-colors-goaw2jac/Previous-Folio.app. Running app left open; quit/reopen to activate.
- Next authorized action: assess human feedback on the four-color palette.
