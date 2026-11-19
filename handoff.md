# Current handoff

## GitHub v0.1.0 Mac preview — 2026-11-19

- Request/status: publish a GitHub release. Published `v0.1.0` as the initial Apple Silicon preview at application source `26ba2c42f159646a3353e67ab17c3184308989dd`; repository stays private. Release page is linked from README. No web changes, installed-app replacement, real-library writes or credential changes.
- Assets: `Folio-v0.1.0-macos-arm64.zip` (46,238,291 bytes), full local Skim model, helper and offline math; `SHA256SUMS.txt`. SHA-256 `625bf6010b91f0a18cd67573186e7f6ccd82b3878440df36640cca18518d4994`. Build version 0.1.0/1; macOS 14+ declared, Apple Silicon only. Ad-hoc signed, not notarized. Notes cover install, account configuration, features and known limitations.
- Fresh checks: `FOLIO_SWIFTPM_UNSANDBOXED=1 FOLIO_SOURCE_ONLY_BUILD=0 scripts/build-app.sh release` passed full model-required packaging/privacy/signing (`/tmp/folio-v0.1.0-release-build.log`). ZIP integrity/resources/metadata checks and extracted deep/strict signature passed. Uploaded draft assets were downloaded and checksum-verified before publication; final GitHub metadata confirms published prerelease with both assets. Prior hosted source verification: run 44503029752 passed.
- Actual release ZIP smoke test: generated sample opened, local Skim returned two Method marks, offline math fixture rendered; CGWindow screenshot visually inspected. Disposable QA instance quit. No live provider calls; not a macOS-version or Intel compatibility claim.
- Documentation: README download link, TESTING artifact evidence and this checkpoint. Local context/whitespace checks passed. [Previous CI checkpoint](docs/archive/handoff-before-github-release-2026-11-19.md).
- Next action: follow the human request; no new product work queued.
