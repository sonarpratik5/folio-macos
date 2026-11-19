# Current handoff

## Startup crash repair — 2026-11-14

- Request: investigate FolioMac unexpectedly quitting and prevent recurrence. Latest three crash reports show pre-main `Taskgated Invalid Signature` / SIGKILL, not Swift app frames. On-disk signatures nevertheless verified; in-place mutation and cached signature state are the suspected trigger.
- `scripts/build-app.sh` now packages fresh files and a unique iconset under `.build/package.*`, signs/deep-strict verifies before replacing `.build/Folio.app`, retaining the old valid bundle until packaging succeeds. Prior dotenv path metadata preserved. Updated STATE, ARCHITECTURE, DEVELOPMENT, QUALITY, TESTING. No web edits.
- Rebuilt debug with host packaging access. Replaced `~/Applications/Folio.app` through fresh staged copy and signature verification; prior installed app retained at `.build/.folio-repair-km1rxx6s-previous.app`. No real library/credential changes.
- Verification: installed Launch Services launch with disposable library; sample reader/page/rotation/highlight/Undo/Redo/library actions and inspected window snapshot passed. Three additional ordinary quit/relaunch cycles passed. No new crash reports (latest remained 22:32:07 CET). Temporary QA instances quit; separate normal-library process left alone.
- Full host-service local-cache Swift suite: 107 tests (32 Mac, 75 core), zero failures, two live-provider skips. See TESTING for exact command and evidence. Shell syntax, context and whitespace checks pass. No live AI/account checks; bounded tests cannot certify every runtime path.
- Prior audit and concurrent installed-dotenv checkpoints preserved in [previous handoff](handoff-before-startup-crash-repair-2026-11-14.md). Existing dirty work preserved. Next authorized action: human uses repaired installed app; no new feature work queued.
