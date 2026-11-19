# Current handoff

## Native Claude and OpenReview dotenv — 2026-11-14

- Request/status: use ANTHROPIC_API_KEY plus OPENREVIEW_TOKEN / OPENREVIEW_USERNAME / OPENREVIEW_PASSWORD from the existing native `.env`. Implemented; all four names found without exposing values. Web unchanged; no credential-file edits.
- LocalDotEnv.swift shares single-line dotenv parsing and working-directory / `.build/Folio.app` project discovery. Launch environment wins. Claude then falls back to existing non-interactive Keychain; header readiness includes dotenv. No credential controls added.
- NativeReviews.swift: token first, lazy api2 login with username/password if missing, one login/retry on 401/403, client-memory token reuse, redacted errors, same-host redirects. Codex child environment strips OpenReview credentials too. Test environments disable OpenReview file discovery.
- Checks: 27 targeted CredentialSessionTests / ClaudeDotEnvTests / AssistantTests / NativeReviewTests passed with macOS service access; includes synthetic login/refresh/redaction and dotenv discovery. Initial restricted LAContext check failed; outside restriction passed. Debug bundle rebuilt with host icon-packaging access after restricted Invalid Iconset. Context and whitespace checks passed. No GUI/live provider or account verification; no install/commit/publication.
- Bundle: `.build/Folio.app`. Moved bundles require native-project working directory or launch environment; secrets are never bundled. Prior UI/icon/credential/context dirty work preserved.
- [Previous paper-entry checkpoint](handoff-before-dotenv-provider-configuration-2026-11-14.md) preserves the concurrent paper-entry/full Insights work, adaptive selection popup work and earlier checkpoints. Next authorized action: human uses rebuilt app; no new features queued.
