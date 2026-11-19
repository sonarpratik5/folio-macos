# Current handoff

## Native health check — 2026-11-18

- Request/status: review the macOS app and make sure it is healthy. Bounded source review and automated verification complete; no new confirmed implementation bug or product source changes. Visual verification remains unavailable.
- Changed only verification/checkpoint docs: `docs/TESTING.md`, this handoff, and `docs/archive/handoff-before-health-check-2026-11-18.md`. Broad pre-existing dirty native work and sibling web work preserved.
- Checks: `CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security` with host services passed 183 cases (181 passed, two live-provider skips, zero failures). Log `/tmp/folio-health-host-tests-20261118.log`. Restricted attempt reproduced the documented LAContext assertion discrepancy; host rerun passed without changes.
- Release: `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh release` with host services passed; `.build/Folio.app` deep/strict signature verified. Log `/tmp/folio-health-host-release-20261118.log`. Restricted dsymutil was blocked. No installation/publication/commit.
- Harness: context validator, seven Python harness tests and whitespace checks passed. Disposable QA launch reported ready, but open-sample acknowledgement timed out and CUA app inspection failed; no fresh GUI evidence. QA PID was absent at cleanup. No real-library writes, live provider calls or credential changes.
- Limits: retained known QUALITY/LOGIC_AUDIT gaps, including arbitrary PDF fidelity, large-document responsiveness and accessibility. L5 conversation retention and L6 Unread semantics still need product decisions before changes.
- Previous active checkpoint: [library conveniences](handoff-before-health-check-2026-11-18.md).
- Next authorized action: follow the next human request; no feature queued.
