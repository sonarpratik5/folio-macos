# Native reading assistant setup

[README setup walkthrough](../README.md#configure-codex-cli) · [Local data and privacy](../README.md#privacy-and-local-data)

Folio's AI features use **your** configured provider. There is no shared developer account, bundled key or silent provider fallback. Reading, annotations and PDF export work without AI. Provider and Claude model menus are in AI panel headers; Settings has no credential-entry controls.

## Codex CLI

Install the official CLI using `brew install --cask codex`, or `npm install -g @openai/codex` if you already use Node. Then run:

```sh
codex --version
codex login
codex login status
```

Complete the sign-in with your own account. See [official installation](https://github.com/openai/codex#installing-and-running-codex-cli) and [authentication](https://developers.openai.com/codex/auth/). Folio's default requests **GPT-6.1 Terra / medium reasoning**. Access depends on the installed CLI version and your account's model access and limits. Folio supplies its own restricted configuration and ignores user/project instructions for these requests.

Folio searches `~/.local/bin`, standard Apple Silicon/Intel Homebrew locations, supported Codex/ChatGPT application locations and its launch `PATH`. For a custom installation, quit Folio and launch it directly:

```sh
FOLIO_CODEX_CLI="$(command -v codex)" .build/Folio.app/Contents/MacOS/FolioMac
```

Replace the executable path if Folio is installed elsewhere. `FOLIO_CODEX_CLI` is read from the **launch environment**, not `.env`. Finder does not necessarily inherit Terminal's shell variables. Keep `FolioPaperTools` beside `FolioMac` inside the bundle. Codex requests expose bounded paper tools and optional web search; no shell or arbitrary-file tools are exposed to the model. Answers display when the request completes.

## Claude API

Create your own API key in the [Claude Console](https://platform.claude.com/settings/keys) and configure the API access/billing your account requires. A chat-app subscription does not by itself configure Folio's API requests. [Anthropic's API overview](https://platform.claude.com/docs/en/api/overview) describes account and authentication requirements.

The recommended location works for Finder and Applications launches:

```sh
mkdir -p "$HOME/Library/Application Support/FolioMac"
touch "$HOME/Library/Application Support/FolioMac/.env"
chmod 600 "$HOME/Library/Application Support/FolioMac/.env"
open -e "$HOME/Library/Application Support/FolioMac/.env"
```

Add this line, replacing the placeholder **only in your private local file**:

```dotenv
ANTHROPIC_API_KEY=paste-your-own-key-here
```

Save, quit and reopen Folio, choose **Claude API** in an AI panel header, then Send a question. The model menu offers Claude Sonnet 5.5 (default) and Claude Opus 5.5. `FOLIO_ASSISTANT_MODEL` in the launch environment overrides the menu/default. Claude answers support streaming. Opening a panel or selecting a provider alone never sends a request.

### Configuration precedence

Credential variables resolve independently, in this order:

1. Folio's launch environment.
2. `~/Library/Application Support/FolioMac/.env`, resolved on the Mac running the app.
3. `.env` in the process's working directory (development fallback).
4. The native project `.env` above `.build/Folio.app` (local build fallback).
5. For Claude keys only, an existing explicitly imported login-Keychain key.

No sibling web `.env` is searched. Dotenv supports single-line quoted/unquoted values, `export` and comments, without shell expansion. For launch variables, use the executable directly rather than assuming `open` forwards your shell environment. File configuration stays outside the app and is never copied into the bundle. Builds no longer store the builder's absolute dotenv path; existing Applications copies must be rebuilt to adopt this behavior. If you previously relied on that path, create the user-local file above or supply launch variables. The native project `.env` remains usable when running locally from this repository.

Keychain queries remain non-interactive; blocked access produces an inline error. Folio does not unlock or weaken your Keychain. Existing explicit `--import-claude-key-from <path/to/.env>` support is documented in [development](DEVELOPMENT.md#claude-api-key-import). New users can use the file method without importing a key. Restart after changing credentials because successful Keychain access can be cached until exit.

## Optional OpenReview authentication

Public review lookup works without credentials where the service allows it. For restricted content, put your own values in the same user-local file:

```dotenv
# Optional: use a current token, or configure your own login below.
OPENREVIEW_TOKEN=
OPENREVIEW_USERNAME=
OPENREVIEW_PASSWORD=
```

A token is preferred. Without one, username/password sign-in happens only during an explicit review search/load. A rejected token can trigger one sign-in/retry if both login fields are configured. Refreshed tokens remain in memory and are never written back to your file or library. Environment values take priority per variable. Keep this file private and out of Git.

## How to use AI safely

Open a paper and the **Ask** panel, type a question and press Send. A page citation opens the source in the reader. Explain Selection, overview generation, review analysis and concept-map generation are explicit requests. **Selection Insights is an active explanation mode:** once enabled, finishing a text selection sends a request; ordinary Select mode never does. Stop or navigation cancels active work. Opening saved conversations or overviews does not regenerate them.

AI requests share bounded extracted paper text and recent conversation with the selected provider. Chat starts with a compact map (at most 12K characters), up to two ranked local excerpts and recent complete exchanges within 32K UTF-8 bytes. Explicit “here/this page” questions add a short page excerpt. Paper tools can fetch relevant pages and search the paper; provider web search may be used when needed or requested. The local lookup corpus is capped at 1.6 MB, and tool calls, excerpts and duration are bounded. This is not a guarantee of full-paper coverage.

Paper at a glance uses distributed passages within a 40K-byte context budget and validates cited sources. Saved AI results and per-paper conversation threads remain under `Assistant/` in the selected library; they are separate from PDF annotations. Math uses bundled offline KaTeX. Corrupt/incompatible saved files are kept rather than silently replaced. Scanned PDFs require OCR, which Folio does not implement. Provider retention, costs and account controls follow the provider's policies. Check answers against source citations.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Codex cannot be found | Run `command -v codex`; use the explicit launch command above if its location is not searched. |
| Codex asks for sign-in | Run `codex login status`, then `codex login` using the same macOS account that runs Folio. Never copy another person's auth cache. |
| Unsupported CLI flag or model | Update the CLI with your chosen installation method; verify your account supports Folio's requested model. Folio does not silently substitute another model/provider. |
| Missing Claude key | Check the user-local file name is exactly `.env`, replace the placeholder, save and restart. Do not paste the key into a support report. |
| Claude rejects the request | Check key validity, API billing/limits and selected model access in your Console. |
| Finder launch differs from Terminal | Use the user-local file for Claude, a standard CLI installation for Codex, or launch the executable with explicit variables. |
| Keychain access is blocked | Use the user-local `.env` or explicitly repair/import your own key. Folio will not show a Keychain password prompt. |
| Paper tools are missing | Rebuild/reinstall the complete bundle with `FolioPaperTools`; do not copy just the main executable. |
| No text or weak citations | The PDF may be scanned or extraction may be incomplete; check the original document and Folio's bounded-context limits. |

Automated tests use synthetic credentials and fake providers. They do not verify your live account, quota or model access. See [verification evidence](TESTING.md).
