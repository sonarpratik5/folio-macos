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

Hosted workflow configuration: [verify.yml](../.github/workflows/verify.yml); current remote results are available in [GitHub Actions](https://github.com/sonarpratik5/folio-macos/actions). The [initial hosted run](https://github.com/sonarpratik5/folio-macos/actions/runs/43612254278) compiled on macOS 15.8.2 / Xcode 16.4 but exposed PDFKit's OS-dependent companion Popup annotation: the fixture had three total annotations instead of two. The test now asserts exactly one Text comment and one Highlight, allowing PDFKit's companion Popup. The Undo callback also uses a main-actor transaction box and synchronous assumeIsolated to handle older SDK Sendable annotations. The [corrected hosted run](https://github.com/sonarpratik5/folio-macos/actions/runs/43612524040) passed context validation, all eight core tests and release .app packaging on macOS 15 / Xcode 16.4 at source commit `88cd0b8`. Final evidence-only documentation updates are checked locally with the harness and whitespace validator.

Limits: no full web parity, AI/provider calls, real-paper tests, original-file overwrite, external PDF-reader fidelity matrix, dark-mode interaction audit, accessibility audit, notarization/distribution signing, Intel build, older-macOS runtime test, large-library performance test or browser-data migration. The working sample and fixture results do not establish arbitrary-PDF fidelity. See [QUALITY](QUALITY.md).


## PDF editing and focused reader — 2026-11-14

Research/case design: [PDF editing verification](PDF_EDITING_VERIFICATION.md). The requested research subagent supplied primary open-source/formal-methods material and a per-tool matrix; the later UI subagent used Luna. This work executes bounded model-based tests, not a formal proof of PDFKit or arbitrary PDFs.

Fresh checks on macOS 27.2 (26B123), Apple Silicon:

| Command / evidence | Result |
| --- | --- |
| `CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security` | Passed 32/32: 27 core and 5 Mac tests on combined annotation/home/AI source at check time. This includes 7 PDFEditing tests and 3 WorkspaceEditing tests; later independent home/AI additions require their own fresh checks. |
| `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh release` | Passed; ad-hoc-signed `.build/Folio.app`, including the concurrently implemented paper-tool helper. macOS icon generation required execution outside the managed sandbox; the initial sandboxed iconutil attempt failed. |
| Independent history model | Every four-step sequence over add/replace/erase/undo/redo/failed-save/no-op: 2,401 sequences, 9,604 checked transitions. Compares actual PDFKit-backed history with a separate array/stack model. |
| Generated persistence/failure fixtures | Original bytes unchanged; crop/media geometry/source text retained; cross-page groups/quotes, edited FreeText style, no yellow copied-text background, bitmap appearance/reopen/resave, stale/wrong-document/duplicate rejection, failed edit/undo/redo rollback, redo branching, cancel/no-op and document switching pass. |
| Geometry fixtures | Marks and edge placement contained for rotations 0/90/180/270 and both zero/nonzero crop origins. This checks page-space geometry, not every rotated pointer interaction. |
| `git diff --check` | Passed for combined source at check time. Context routing covers all annotation additions; the other active chat owns routing for its ongoing Reviews/Graph additions. |

Actual CUA checks used only generated samples in `/tmp/folio-pdf-final-20261114-1727` and a separate `dev.folio.mac.pdfqa` bundle to avoid disturbing the active normal app. Observed: initial whole-page fit; persistent multiline Highlight and Underline; select existing group and attach a quote/note; nonempty editor saving on outside click; optional Pages/Outline and Notes without the library sidebar; eraser removes a linked group in one stroke, Command-Z restores it; text creation, movement, handle resizing and transparent background; note-pin movement; synthetic PNG copied from Preview then pasted with Command-V; image handle resize; annotations surviving QA app restart; and explicit copy export. Pointer tests caught and fixed premature drag completion when PDFKit returned early from mouseDown, plus initial fit before layout. UI tests exposed/copied-text fill drift; a rendered regression now checks that moving/editing FreeText does not acquire a yellow rectangle.

The final generated export `/tmp/folio-pdf-tools-final-20261114.pdf` was opened in Preview 11.0 (1147.1.10). Preview recognized standard Text Box, Image, Note, Highlight and Underline objects; screenshots showed saved bitmap colors/aspect, moved note, wrapped text with transparent background, and source text. Preview shares the platform PDF renderer, so this is an external-app compatibility check, not an independent-engine fidelity matrix. Temporary read-only `swift -module-cache-path .build/ModuleCache /tmp/folio-pdf-inspect.swift` verified 3 exported pages, exactly 2 Highlight + 1 Underline + 1 Text + 1 FreeText + 1 Stamp, contained bounds, and equal managed/export media/crop boxes, rotation and extracted source text. Cached accessibility trees sometimes retained old annotation nodes after replacements; the current rendered page and reopened exported annotation counts showed one text box and one image.

Limits: generated fixtures only; no real-paper overwrite, provider invocation, broad external-engine matrix, minimum-macOS/Intel run, full accessibility/960px/Light-mode audit, full rotated/cropped pointer matrix, very large-document performance, note-image attachments or below-page writing port. Undo remains session-only; typed drafts are not crash-recovery storage. Relative layering/rich appearance metadata for arbitrary third-party annotations is not certified. No commit, push, publication or distribution signing was performed by the PDF task. Concurrent home/AI work continues separately and its new source is not covered by this checkpoint's earlier build result.

## Native feature expansion — 2026-11-14

- `swift test`: 55/55 pass, 0 failures.
- `scripts/build-app.sh release` built `.build/Folio.app`; launched with `--library-path /tmp/folio-native-check-<ts>`, it stayed running, created its library root and logged no errors.
- Fixes before the run: `AssistantPaper.quoted` made public; NativeReviewTests actor-await fix.
- Limits: no interactive GUI QA (computer-use unavailable, screencapture blocked). Nothing here verifies visual or interaction behavior, margin marks with rotation, drag-drop, arXiv download, streaming or live AI providers. Design saw only offscreen ImageRenderer snapshots.

## AI reader panel and provider fixes — 2026-11-14

| Check | Result |
| --- | --- |
| `swift build` | OK |
| `swift test` | 60 tests, 2 skipped (live, need `FOLIO_LIVE_AI=1`), 0 failures; includes new `CodexFailureTests` in AssistantTests.swift |
| Live Codex run (synthetic paper) | After the TOML slash fix the request reached the model and returned the account's "usage limit reached, try again at 9:13 PM". A successful answer is NOT verified |
| Claude API | Not live-tested (no ANTHROPIC_API_KEY); request shape checked against the API reference only |
| QA-harness window snapshots, light and dark, 1320×840 | Ask (empty and with attached selection), At a glance, Peer reviews, Concept map and collapsed rail rendered correctly |

Not verified: real clicking/typing, streaming display, right-click menu, Finder-level interactions. Native Codex chat/overview/reviews/concept map had never worked before the fix.

- Claude key/switch follow-up: `swift test` 61 tests, 2 skipped (live), 0 failures, including `testClaudeKeyComesFromEnvironmentThenStoredKey` (injected key lookup; real Keychain untouched by tests). QA `settings-shot` (new harness command) captured Settings → AI assistant with Claude selected; Ask/At a glance snapshots show the header switch and missing-key prompt in light and dark. Live Claude verified: key imported from the web repo’s gitignored `.env` into the Keychain with `FolioMac --import-claude-key-from <.env>` (key never printed); `FOLIO_LIVE_AI=1 FOLIO_LIVE_PROVIDER=claude swift test --filter LiveProviderTests` passed both tests (chat answer from the paper; overview with sourced problem/approach/finding cards) on claude-sonnet-5-5. Installed `~/Applications/Folio.app` Settings shows “Key saved. Claude API is ready.” with no Keychain prompt; Ask shows no missing-key warning. `ClaudeDotEnvTests` covers dotenv parsing.

## Insights destination and Keychain prompts — 2026-11-14

- Source review used the web Home.tsx / LibraryOverview.tsx / App.tsx flows as reference; no web files changed. Native owner changes: Workspace/WorkspaceView/LibrarySidebar/LibraryView, AssistantSurface, ReaderPanel/ReaderView, new InsightsView, PaperGlancePanel, ClaudeKeyStore and AISettingsView. Local abstract extraction now detects numbered section boundaries before flattening whitespace.
- Final `CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security`: **88 tests total (23 Mac + 65 core), 0 failures, 2 opt-in live-provider skips**. Run with macOS graphics access. Initial sandboxed test run trapped inside PDFKit's PDFTileSurface/CFRelease after graphics-service failures; rerun outside that restriction passed. New regressions verify Insights preserves active PDF and manifest bytes, inspected-paper source navigation, credential cache reuse/replacement/removal/cancel retry, and abstract/body separation.
- `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh release`: pass with macOS build-tool access; the sandboxed attempt was blocked in dsymutil. Existing provider/reader warnings remain.
- GUI QA used unique channels `/tmp/folio-qa-insights-fix` and `/tmp/folio-qa-insights-final`, generated sample PDFs only, and an isolated library. Commands covered empty Insights, local skim, overview→reader, highlight, inline FreeText commit, undo/redo, Find, Ask, Notes, grid/list, Opened, Starred empty state, and light/dark/narrow layouts. No provider request was sent, no real credential accessed, and no original research PDF opened/written. Screenshots are temporary local artifacts, not repository content. Tests provide persistence/export/failure-path coverage; GUI checks do not establish arbitrary-PDF fidelity.
- `python3 scripts/context.py --check` and `git diff --check`: pass. Live Codex/Claude quota, streaming and OS credential-authorization behavior were not exercised. Non-interactive attributes-only presence query is source-verified; session cache is tested with synthetic credentials. Ad-hoc rebuilds may still require one explicit Claude-request authorization from macOS.

## GitHub sync verification — 2026-11-14

- Fresh full Swift test run with local caches and macOS graphics access: 88 tests (23 Mac + 65 core), 0 failures, 2 opt-in live-provider skips. Command: `CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security`. Initial sandboxed Mac tests crashed after graphics-service errors; host-access rerun passed.
- `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh release`: passed, including local ad-hoc bundle signing. Existing compiler warnings remain.
- Context/whitespace checks pass. No fresh interactive GUI, provider, real credential or arbitrary-PDF verification. Only the native repository is being synced; web changes remain untouched.
