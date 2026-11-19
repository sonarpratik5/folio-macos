# Current handoff

## Continuous window toolbar — 2026-11-15

- Request/status: resolve visual mismatch between native traffic-light region and All PDFs title/divider. FolioApp now explicitly uses unified window toolbar; WorkspaceView applies one adaptive panelLeft toolbar background to the whole split view. Native controls/title/split resizing remain system-owned. All earlier dirty work preserved.
- Release `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh release` passed with host services, signed and deep/strict verified. Log `/tmp/folio-titlebar-build.log`. Context and whitespace checks passed.
- Disposable unique preview app/library: own QA snapshot `/tmp/folio-titlebar-held-20261115/final.png` visually confirms continuous light/inactive top bar at 1380×880 and sidebar boundary starting beneath it; zero-paper empty state. QA quit acknowledged. CUA targeting resolved to regular app (read-only inspection); relied on isolated QA capture for final evidence.
- Limits: no fresh dark/active/reader/accessibility matrix or unit suite for chrome-only changes; no installed-copy replacement, real-library writes, commit or publication. Next authorized action follows the human request.
- [Preserved sample-cleanup checkpoint](handoff-before-continuous-toolbar-2026-11-15.md) retains previous changes and concurrent history.
