# Native reading assistant

From home, use the sparkle button on Continue reading, or open a paper's details and choose **Ask Folio**. The sheet restores the saved conversation and Paper at a glance. Opening it never starts a provider request. Send, Explain selection and Generate/Regenerate are explicit actions; Cancel and Done stop active work. A page citation opens the source in the reader. Asking from home preserves the current reader until you choose a source or Resume.

## Providers

The default is **Codex CLI, GPT-6.1 Terra, medium reasoning**, matching the web app. Install Codex CLI and run `codex login` yourself in Terminal. Folio searches the standard Homebrew/local/Codex app locations and PATH; set `FOLIO_CODEX_CLI` in the app's launch environment for another executable path. The packaged `FolioPaperTools` helper must remain beside FolioMac. No shell or arbitrary-file tools are exposed to the model.

**Claude API** is an explicit choice in Settings or the assistant's provider button. Supply `ANTHROPIC_API_KEY` in Folio's launch environment; optionally set `FOLIO_ASSISTANT_MODEL` (default `claude-sonnet-5-5`). Alternatively save a key in Settings → AI assistant; it is stored only in this Mac's login Keychain. Folio does not automatically read the sibling web app's `.env`. Navigation uses non-interactive presence checks and never retrieves the secret. An explicit Claude request may ask macOS to authorize Keychain access once; a successful unlock is reused until the app exits or the key changes. Ad-hoc rebuilds can require renewed macOS authorization. To inherit variables set in a terminal, launch the executable directly from that terminal: `.build/Folio.app/Contents/MacOS/FolioMac`. Finder launches may have a different environment. No provider switches automatically when setup, sign-in, model access or quota fails.

## Context and local storage

Requests share extracted paper text with the selected provider. Chat starts from a compact map of at most 12K characters, reuses bounded conversation history, and can retrieve relevant pages/search the paper or web when needed. The local extracted lookup corpus is capped at 1.6 MB; individual results, total tool calls and request duration are bounded. Truncated excerpts are explicitly marked. Web queries should remain minimal and relevant.

Paper at a glance uses up to 800 distributed passages / 120K characters and validates every cited source against that extraction. An unsupported card is omitted rather than fabricated. Results persist atomically at `Assistant/<paper UUID>.json` inside the selected library. They are separate from PDF bytes and library metadata. Corrupt/incompatible history or changed paper text disables reuse and leaves the file untouched.

Current boundaries: answers display after completion with basic Markdown and source/page buttons. Rendered LaTeX, streaming, multiple conversation threads, OpenReview analysis and concept-graph refinement are not implemented. Scanned PDFs require OCR, which is absent. Fake-provider and generated-PDF checks do not establish live account/model access; see [testing](TESTING.md).
