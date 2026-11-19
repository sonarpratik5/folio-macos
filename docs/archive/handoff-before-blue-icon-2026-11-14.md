# Current handoff

## Concise interface copy — 2026-11-14

- Request/status: remove promotional and unnecessary prose, especially near API-key settings, retaining useful Ask guidance. Done in native Mac app; sibling web repository untouched.
- Changed: AISettingsView/SettingsView shorten setup, Keychain/privacy and library copy; remove theme pitch, migration and framework prose. LibraryView/InsightsView remove taglines and use direct empty-state instructions. PaperGlancePanel/PaperConceptGraphView/PaperReviewsView shorten introductions while keeping provider-sharing notices. Ask unchanged. No credential, persistence or request-flow changes.
- Fresh checks: local-cache `swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security` passes; `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh debug` passes with host macOS tools after sandbox iconutil failure. Context validator and whitespace pass. CUA verified empty Library and both provider Settings in isolated copy-preview bundle/disposable library. No key entry, AI call or user PDF. Full suite not rerun for copy-only edits; overview/map/review layout, light mode and saved-key state not visually checked. See docs/TESTING.md.
- Preserved all pre-existing native theme, credential and selection Insights edits and dirty web work. Previous active theme checkpoint: [archive](handoff-before-copy-cleanup-2026-11-14.md); concurrent credential/selection facts remain in STATE/TESTING. Updated deliverable: `.build/Folio.app`.
- Next action: follow human feedback; no feature expansion or publication authorized.
