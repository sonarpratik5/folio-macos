# Current handoff

## Settings AI section removal — 2026-11-15

- Request/status: remove AI provider section from Settings because switching is available elsewhere. Done. Settings now has appearance/local-library/about only. ProviderSwitch remains in AI headers; Claude model choices moved into its existing menu, keeping stored selection/environment override. Removed obsolete AI Settings links in Ask/header and stale authentication-error guidance.
- Changed: SettingsView, ReaderPanel, AskPanel, AssistantProvider; deleted unused AISettingsView and its route entry. STATE/ARCHITECTURE/DECISIONS/AI_SETUP/DEVELOPMENT/TESTING updated. Existing broad dirty work, sidebar cleanup and compact notes preserved.
- Fresh verification: host-service `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh release` passed after final error-copy change; optimized `.build/Folio.app`, ad-hoc signed/deep-strict verified. `python3 scripts/context.py --check` (6 routes/93 paths), `git diff --check`, scoped review and source-reference search passed. No new tests for reversible UI removal; no fresh GUI check. [Evidence](../TESTING.md#settings-ai-section-removal--2026-11-15).
- No live AI calls, credential changes, installed replacement, real library writes, commit/push/publication. Next action follows the human request. Earlier sidebar/notes/parity/Skim checkpoints preserved in [archive](handoff-before-settings-ai-removal-2026-11-15.md).
