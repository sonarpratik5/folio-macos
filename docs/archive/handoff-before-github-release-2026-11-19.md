# Current handoff

## Hosted CI SDK and clean-checkout fixes — 2026-11-19

- Request/status: investigate the failed Mac GitHub Actions screenshot and repair the workflow. Run 44501178919 failed compiling PullTimerGlass.glassEffect against the runner's older SDK, before tests ran. Build was consequently skipped.
- Fix: match Theme's compiler >=6.2 plus macOS 26 runtime guard for timer glass; older SDKs retain regular material. Clean-checkout CI also lacks intentionally untracked Skim weights. Two real-inference tests explicitly skip if absent; all other tests stay enabled. CI alone uses explicit FOLIO_SOURCE_ONLY_BUILD=1 for packaging; normal bundles still require weights. No model substitution or automatic download.
- Follow-up: hosted run 44501775312 passed tests but privacy packaging rejected older SwiftPM’s generated Bundle.module literal build path. MathAnswerView now resolves resources relative to the runtime bundle/test location; packaging dead-strips the unused generated accessor. Native-build-system local reproduction confirmed zero home paths after stripping. Existing math test also checks KaTeX JS discovery.
- Changed: resource lookup, timer modifier, workflow, packaging, two Skim tests and development/model/quality/evidence docs. Prior checkpoint: [privacy/README](handoff-before-ci-sdk-fix-2026-11-19.md).
- Verification: local host-service tests passed 183 cases (181 passed, two live-provider skips; Skim inference ran). Normal release packaging, privacy gate and deep/strict signing passed. Context validator, seven harness tests and whitespace checks passed. Logs `/tmp/folio-ci-fix-local-tests.log` and `/tmp/folio-ci-fix-local-build.log`. Hosted older-SDK verification follows publication. No new live provider requests or user-library writes.
- Limits: source-only CI cannot verify model inference or a fully provisioned Skim bundle. Local tests with supplied weights remain required for that evidence. No new GUI claim.
- Final local resource checks: 183 cases (181 passed, two live-provider skips), normal release packaging/privacy/signing passed; `/tmp/folio-resource-fix-tests.log`, `/tmp/folio-resource-fix-build.log`. XCTest needs a Bundle(for:) resource anchor; both JS and inline-font checks now pass.
- Next authorized action: publish the CI fix and watch the new run through completion, resolving any additional confirmed failures.
