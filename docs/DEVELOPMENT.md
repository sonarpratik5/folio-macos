# Development and verification

## Build and run

macOS 14+, Xcode 15.3+; `xcode-select -p` should point to Xcode. The Swift package has no external dependencies. Open `Package.swift` in Xcode and run FolioMac, or use:

```sh
swift build
swift test
scripts/build-app.sh
open .build/Folio.app
```

`scripts/build-app.sh release` makes an optimized local bundle. The bundle has a stable `dev.folio.mac` identifier, plist, app icon and local ad-hoc signature; no Apple account required. Copying the bundle elsewhere on the same machine is possible, but distribution signing/notarization is separate future work. `swift run FolioMac` is useful during development; the .app is the independent desktop deliverable. No `.xcodeproj` generation step is required.

In managed environments where default compiler caches are read-only, keep caches inside this checkout:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
```

`--disable-sandbox` applies to SwiftPM's build sandbox, not the app. Use it only when a managed environment prevents SwiftPM from launching its manifest sandbox. No dependency plugins are installed in this package. Build script caches are local by default.

The equivalent bundle command in that environment is `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh` (optionally `release`).

## Safe interactive check

Build the bundle, then launch with a disposable data root:

```sh
open -n .build/Folio.app --args --library-path /tmp/folio-native-check-UNIQUE
```

Pick a unique path, not a real library. Use Sample paper, add a note, highlight/underline synthetic text, star a page, run Find, return to library, inspect grid and Notes, quit/reopen the same isolated root, and export only to another disposable PDF. Verify that standard comments persist and the source is untouched. Inspect dark mode and narrow layouts. Do not use real papers or the normal Application Support library for automated tests. UserDefaults appearance preferences remain shared by bundle identifier even with an isolated library root.

## Agent checks

```sh
python3 scripts/context.py "annotations"
python3 scripts/context.py --check
git diff --check
```

CI runs the harness checker, core tests and release app build on macos-15. A configured workflow is not evidence of a hosted run; record actual results in [TESTING](TESTING.md). No screenshot testing or UI automation framework is installed.
