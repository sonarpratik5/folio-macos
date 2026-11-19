# Current handoff

## Subtle library conveniences — 2026-11-16

- Request/status: implement very easy, subtle next-step features. Complete in the native Mac app, selected from the latest active repository context.
- Changed: `Sources/FolioMac/LibraryView.swift` adds Copy Title to the shared paper context menu; empty results offer search/filter reset; Notes and Starred pages distinguish searches with no matches. Reset preserves folder/section/sort/layout. No persistence or provider changes. Updated STATE, ARCHITECTURE and TESTING.
- Checks: local-cache `swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security` passed (CLANG_MODULE_CACHE_PATH=$PWD/.build/ModuleCache); matching `swift test ... --filter ReaderParityTests` passed 7/7. Plain swift build initially failed on unwritable global Clang cache. `python3 scripts/context.py --check`, `python3 scripts/test_context.py`, `git diff --check` passed.
- Limits: no fresh interactive GUI/clipboard test or real-library operation. Existing tests cover regressions, not these SwiftUI button actions. No installation/publication/commit. Broad pre-existing dirty native work and all sibling web work preserved.
- Previous active checkpoint: [native harness audit](handoff-before-library-conveniences-2026-11-16.md), including links to earlier product checkpoints.
- Next authorized action: follow the next human request; no further feature queued.
