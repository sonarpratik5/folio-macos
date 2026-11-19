# Current handoff

## Sidebar simplification — 2026-11-15

- Request/status: subfolders always active with no checkbox; remove Sample paper sidebar action and “A guide to reading research” from Quick access. Done. Existing library records, notes and the empty-library sample entry are preserved; sidebar filtering is presentation-only.
- Changed: LibrarySidebar removes the toggle/footer sample button and filters the named guide before taking five recent shortcuts. Workspace removes includeSubfolders state and always includes descendant folder papers; badge counts always aggregate descendants. Existing ReaderParityTests/WorkspaceEditingTests assert nested counts across refresh/relaunch. STATE, ARCHITECTURE, DECISIONS and TESTING updated. No new executable paths.
- Fresh verification: host-service `CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --filter 'ReaderParityTests|WorkspaceEditingTests'`: 18 tests, zero failures. Initial restricted run hit an AppKit process signal; host rerun passed. Host-service `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh release` passed; `.build/Folio.app` optimized, ad-hoc signed and deep/strict verified. Context (6 routes/94 paths), scoped review and whitespace passed. [Evidence](../TESTING.md#sidebar-simplification--2026-11-15).
- Limits: no fresh GUI pass or installed-app replacement. No real user-library writes/deletions, provider calls, commit/push/publication. Broad pre-existing dirty work and compact notes feature preserved.
- Next action follows the human request. Prior compact notes, parity and concurrent Skim checkpoints remain linked in [archive](handoff-before-sidebar-simplification-2026-11-15.md).
