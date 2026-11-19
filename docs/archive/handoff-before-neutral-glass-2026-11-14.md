# Current handoff

## GitHub sync — 2026-11-14

- Request: sync native macOS only; preserve sibling web changes. Existing native source/tests/docs will be committed and pushed to `origin/main`; fetch confirmed no upstream divergence.
- Fresh checks: full Swift tests with local caches and macOS graphics access pass (88 tests, 2 live-provider skips); release bundle passes. Context/whitespace checks pass. Sandboxed PDFKit crashed; host graphics rerun passed. No new GUI/provider/real-Keychain checks.
- Source/docs only; ignored builds, PDFs, libraries and credentials excluded. Prior checkpoint below retained. Next authorized action: commit/push and confirm remote equality; no new features.

## Selected-text Insights + legacy Keychain dialogs — 2026-11-14

- Human clarified missing Insights means explanations for selected text. Implemented I/V mode, toolbar/rail/menu access, transient reader explanation panel, page citations, Stop/retry/Continue in Ask. Only completed gestures in enabled mode send; plain selection/enabling alone never sends. Bound selections to 12K, deduplicate, cancel on new selection/tool/provider/navigation changes. Paper at a glance stays on the overview page.
- Keychain screenshot persisted after query-only flags. Final fix disables legacy Security.framework interaction process-wide at launch (SecKeychainSetUserInteractionAllowed(false)), guards its success, and also sets LAContext.interactionNotAllowed + kSecUseAuthenticationUIFail for every operation. Blocked access fails inline, never asks for a password. Save creates a new app-owned UUID slot; defaults contain only the slot identifier. Existing Keychain protections remain.
- Owners: ClaudeKeyStore/FolioApp/AssistantSurface/Workspace/PDFCanvas/ReaderView/ReaderPanel; new SelectionInsightView and SelectionInsightTests; CredentialSessionTests/AssistantTests. QA selection/provider/key availability hooks; routes and authoritative docs updated. Preserve concurrent theme/sync work; no commit or push from this chat.
- Checks: final full swift test with local caches/macOS graphics: 93 total (26 Mac + 67 core), 0 failures, 2 live-provider skips. Release build/signature, context and whitespace pass. Local synthetic provider GUI showed selected explanation/citations in light/dark; final credential check returned unavailable without a dialog. Earlier synthetic live-Claude attempt was stopped still loading: no successful live explanation claim.
- Installed latest to ~/Applications/Folio.app with old bundle retained in temp. Human authorized closing older copies after initial automatic approval rejection. CUA reopened installed app, resumed existing sample and enabled Selection insights; toolbar + panel visible without credential dialog. An older separate preview also ran during development; always verify the installed build.
- Required human setup: macOS blocks the old saved Claude key under strict no-dialog access. Re-save it in Settings → AI assistant to create a fresh app-owned item; unlock the login Keychain separately if it is locked. No password/secret logged, no real paper sent. Next: human uses selection Insights and provides feedback; live Claude verification after re-save.
