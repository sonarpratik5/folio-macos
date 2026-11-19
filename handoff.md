# Current handoff

## Git publication checkpoint — 2026-11-19

- Request/status: human authorized committing and pushing both apps; verification complete, preparing publication.
- Scope: commit accumulated native reader/library, assistant/insights, local Skim, writing, menu-bar/timer, theme, harness and audit work on `main`, including the November 18 health-check docs. Removed one trailing blank line from `Sources/FolioMac/MenuBarController.swift`.
- Fresh checks: host-service `CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security` passed 183 cases (181 passed, two opt-in live-provider skips). Restricted attempt reproduced the documented Keychain policy assertion; host rerun passed without behavioral changes. Log: `/tmp/folio-mac-tests-host-20261119.log`.
- Release: `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh release` passed with host services; local `.build/Folio.app` signed and deep/strict verified. Log: `/tmp/folio-mac-release-20261119.log`.
- Harness: `python3 scripts/context.py --check`, `python3 scripts/test_context.py` (7 tests), and `git diff HEAD --check` passed.
- Limits: no fresh GUI or live provider verification. Prior checkpoint and limitations: [native health check](docs/archive/handoff-before-git-push-2026-11-19.md).
- Next authorized action: commit and push this repository to its existing upstream; no new product work.
