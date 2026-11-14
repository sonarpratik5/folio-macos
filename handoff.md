# Current handoff

## GitHub sync — 2026-11-14

- Request: sync native macOS only; preserve sibling web changes. Existing native source/tests/docs will be committed and pushed to `origin/main`; fetch confirmed no upstream divergence.
- Fresh checks: full Swift tests with local caches and macOS graphics access pass (88 tests, 2 live-provider skips); release bundle passes. Context/whitespace checks pass. Sandboxed PDFKit crashed; host graphics rerun passed. No new GUI/provider/real-Keychain checks.
- Source/docs only; ignored builds, PDFs, libraries and credentials excluded. Prior checkpoint below retained. Next authorized action: commit/push and confirm remote equality; no new features.

## Native Insights + credential prompts — 2026-11-14

- Request: review web Folio, fix native missing Insights and repeated passkey prompts; keep Paper at a glance only in Insights, with minimal functional UI. Implemented. Existing broad dirty native/web work preserved; nothing committed.
- Insights is a library destination with picker, explicit Read paper and source-page actions. Library row/card/hero/context menu and ⌥⌘G route there. Reader rail now only Notes/Ask/Reviews/Map. Inspection preserves the active PDF and position; departure cancels overview generation. `Workspace.navigate` commits editors before navigation. Fixed hidden All-documents filters leaking into Opened. Abstract extraction preserves section boundaries before cleaning, avoiding body text in abstracts.
- Credential readiness now uses attributes-only Keychain queries with LAContext.interactionNotAllowed. Only explicit Claude requests retrieve secrets; successful unlocks cache in memory. Save/remove update cache on success, and failed removal no longer falsely reports success. Existing key never read/changed during verification.
- Owners: new `Sources/FolioMac/InsightsView.swift`; Workspace/View, LibrarySidebar/View, AssistantSurface, ReaderPanel/View, PaperGlancePanel, ClaudeKeyStore, AISettingsView, InsightAnalysis. Added CredentialSessionTests; expanded PaperAssistantTests/AssistantThreadsTests; QA section/layout commands and context routes/docs updated.
- Checks: final full swift test with local caches and macOS graphics access: 88 total (23 Mac + 65 core), 0 failures, 2 live-provider skips. Release bundle build passes. Initial sandbox-only PDFKit rendering and dsymutil failures resolved by macOS tool access. Context/whitespace checks pass. QA: synthetic-only isolated library, light/dark/narrow Insights and reader, annotations, undo/redo, Find, Ask, notes, list/grid and library destinations. See docs/TESTING.md.
- Limits: no live provider request or real Keychain authorization test; rebuilt ad-hoc app may require authorization on first explicit Claude request. No arbitrary-PDF fidelity claim. No real library/source writes, migration, commit, push or deployment. Installed app requires relaunch to load the new build; preserve any current reader session.
- Prior checkpoints retained as current evidence in docs/TESTING.md and docs/STATE.md. Next action follows human feedback; no new backlog selected.
