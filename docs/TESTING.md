# Verification evidence

## Native starter — 2026-11-14

Local environment: Apple Silicon Mac, Xcode selected at `/Applications/Xcode.app`, Apple Swift 6.4.2, macOS 27.2 SDK; package deployment minimum macOS 14. Compatibility was compiled, not interactively tested on older OS versions.

| Check | Fresh result |
| --- | --- |
| `CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security` | Passed native executable build |
| Same cache flags with `swift test` | 8 XCTest tests passed, 0 failures |
| `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh` | Passed debug .app packaging and local ad-hoc signature (macOS packaging tools needed host access in the managed workspace) |
| `scripts/build-app.sh release` with host tooling access | Passed optimized app bundle, icon/plist and ad-hoc signing |
| `python3 scripts/context.py annotations` | Routed to reader owners, scoped rules, symbols, docs and checks |
| `python3 scripts/context.py --check` | Passed routed-file coverage, local links, reachability, wrappers and byte budgets |
| `git diff --check` / staged diff whitespace check | Passed before initial publication |

Core tests cover: empty library; validated import and byte-for-byte original preservation; metadata/stars round trip; PDF comment/highlight serialization with page-size preservation; invalid input rejection; corrupt and future-schema manifest preservation; invalid reading-position rejection; and rollback of a copied import after manifest-save failure. Fixtures are generated in isolated temporary directories. Invalid-PDF testing emits an expected CoreGraphics diagnostic.

Native UI checks used only generated sample papers in an isolated `/tmp/folio-native-check-20261114-01a1daa9` library, launched with `--library-path`. Observed independent .app launch without browser/server; sample import; note composition/save and visibility after quit/reopen; star state; table/grid switching; all-library written Notes; selectable text highlight; annotation Undo/Redo; explicit Find results; page 2/3 navigation; embedded outline; return to library and resume on page 2; and an exported PDF via NSSavePanel to `/tmp/folio-native-export-01a1daa9.pdf`. A screenshot after reopening showed the page-2 highlight and star, with Notes remaining empty for a bare highlight. The initial sample's duplicate text extraction was corrected by generating its replacement through CoreText/CoreGraphics; the updated synthetic sample has three pages and an outline.

A temporary read-only Swift/PDFKit verification (`swift -module-cache-path .build/ModuleCache .build/verify-export.swift`) checked those disposable artifacts: saved written comment, current page 2 and star 2 in metadata, three exported pages, Highlight annotation, matching managed/exported page bounds and extracted text. Temporary libraries, inspection code, exports and build logs are ignored/untracked and are not shipped or committed.

Hosted workflow configuration: [verify.yml](../.github/workflows/verify.yml); current remote results are available in [GitHub Actions](https://github.com/sonarpratik5/folio-macos/actions). Local results above are independent of hosted status.

Limits: no full web parity, AI/provider calls, real-paper tests, original-file overwrite, external PDF-reader fidelity matrix, dark-mode interaction audit, accessibility audit, notarization/distribution signing, Intel build, older-macOS runtime test, large-library performance test or browser-data migration. The working sample and fixture results do not establish arbitrary-PDF fidelity. See [QUALITY](QUALITY.md).
