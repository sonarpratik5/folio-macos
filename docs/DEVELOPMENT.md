# Development and verification

## Build and run

macOS 14+, Xcode 15.3+; `xcode-select -p` should point to Xcode. The Swift package has no external Swift package dependencies. Offline KaTeX 0.18.10 (MIT) is vendored under Sources/FolioMac/Resources/Math with WOFF2-only fonts; SwiftPM and build-app.sh include its resource bundle. Open `Package.swift` in Xcode and run FolioMac, or use:

```sh
swift build
swift test
scripts/build-app.sh
open .build/Folio.app
```

`scripts/build-app.sh release` makes an optimized local bundle. The bundle has a stable `dev.folio.mac` identifier, plist, app icon and local ad-hoc signature; no Apple account required. The generated plist records the original native `.env` path (never its contents), allowing copied bundles to keep using the local credentials. Rebuild after moving the project. Copying the bundle elsewhere on the same machine is possible, but distribution signing/notarization is separate future work. `swift run FolioMac` is useful during development; the .app is the independent desktop deliverable. No `.xcodeproj` generation step is required.

Packaging assembles a fresh bundle under `.build/package.*`, signs it and verifies the deep/strict signature before replacing `.build/Folio.app`. Do not overwrite or re-sign an already launched executable in place: macOS can retain stale signature state even when on-disk verification passes. For a local installed copy, stage fresh files, verify, then replace the bundle; do not patch its executable or icon in place. The build script does not install automatically.

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

Pick a unique path, not a real library. Import a disposable generated PDF (or use the opt-in QA harness `open-sample` command), add a note, highlight/underline synthetic text, star a page, run Find, return to library, inspect grid and Notes, quit/reopen the same isolated root, and export only to another disposable PDF. Verify that standard comments persist and the source is untouched. Inspect dark mode and narrow layouts. Do not use real papers or the normal Application Support library for automated tests. UserDefaults appearance preferences remain shared by bundle identifier even with an isolated library root.

## Agent QA harness

`scripts/qa.sh start` launches `.build/Folio.app` with `FOLIO_QA_DIR=/tmp/folio-qa` and a disposable `--library-path`. `Sources/FolioMac/QAHarness.swift` is inert unless that variable is set; when set it runs commands posted as the `object` of the distributed notification `dev.folio.mac.qa` (for example `scripts/qa.sh open-sample`, `scripts/qa.sh snapshot t1`), writes `ack.txt`, and saves window PNGs without Screen Recording permission. The command list is in the `scripts/qa.sh` header. Snapshots use the app's own window image, falling back to `cacheDisplay` plus manual PDF page drawing. `appearance` writes the app's `appearance` default (restored on `quit`).

## Agent checks

```sh
python3 scripts/context.py "annotations"
python3 scripts/context.py --check
git diff --check
```

CI runs the harness checker, core tests and release app build on macos-15. A configured workflow is not evidence of a hosted run; record actual results in [TESTING](TESTING.md). No screenshot testing or UI automation framework is installed.

## QA harness and live tests (2026-11-14)

- Panel sections: `assistant`, `reviews`, `concept-map` open reader panels; `overview` opens the dedicated Insights page. `section <all|opened|notes|starred|insights>`, `read-inspected` and `library-layout <list|grid>` cover library navigation. New commands: `select-line <page> <line>`, `ask-selection` (prefill only), `overview`. `selection-insights` toggles the I/V mode; `explain-selection` explicitly dispatches the selected passage (can make a real provider call). `provider <codex|claude>` temporarily changes the provider, restored on QA quit. `keychain-check` attempts a non-interactive read and records only available/unavailable, never the secret. Snapshots also save `<name>-sheet.png` when a sheet is attached.
- Use a unique `FOLIO_QA_DIR` per session; a second app instance on the default `/tmp/folio-qa` channel interfered with another session's run.
- Opt-in live provider tests (skipped unless `FOLIO_LIVE_AI=1`): `FOLIO_LIVE_AI=1 FOLIO_PAPER_TOOLS_CLI=$PWD/.build/debug/FolioPaperTools swift test --filter LiveProviderTests`. Add `FOLIO_LIVE_PROVIDER=claude` for Claude (needs ANTHROPIC_API_KEY).

## Claude API key import

`~/Applications/Folio.app/Contents/MacOS/FolioMac --import-claude-key-from <path/to/.env>` reads `ANTHROPIC_API_KEY` from a dotenv file, saves it to the login Keychain item Folio uses (`dev.folio.mac.claude-api`), prints only success/failure and exits without opening a window. AI panel header menus offer provider/model selection; Settings has no AI section or credential controls, per the human’s request. All credential operations prohibit authentication UI. After an ad-hoc rebuild, blocked access appears as an inline error; the existing explicit import command can create a fresh app-owned slot. A locked login Keychain can be unlocked separately in macOS Keychain Access.
