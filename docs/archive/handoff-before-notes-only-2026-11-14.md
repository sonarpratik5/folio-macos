# Current handoff

## Adaptive translucent Insights popup — 2026-11-14

- Request/status: shrink short selection insights, allow scrolling for long replies, make backdrop slightly transparent. Done in native app; web unchanged.
- SelectionInsightView.swift: removed fixed overall height; InsightScrollBody measures natural content and caps the response viewport at 260pt. Width remains 380pt; header/quote stay outside the response scroller. Native thin material replaces solid fill, with solid Reduce Transparency/Increase Contrast fallback. PDFCanvas.swift enables NSHostingController preferred-content sizing so native popover follows loading/result/error changes.
- Fresh checks: local-cache Swift build passes; existing SelectionInsightTests pass 3/3 with macOS graphics access; debug bundle build passes with host packaging access; context and whitespace checks pass. CUA isolated dynamicpreview/generated sample/local synthetic Codex fixture: short popup about 200pt; long popup about 394pt with overflow scrollbar; native AX scrollbar to end shows final paragraph and actions. Thin material visible in dark mode. Wheel/drag automation did not advance scroll; AX value did. No new layout-mirroring tests.
- Limits: no fresh light/older-OS/accessibility-toggle or live provider check. No changes to AI context, cache, requests or credentials. Updated build .build/Folio.app; no installation/publication.
- Preserved concurrent footer removal, icon/copy/credential/theme work and dirty web repo. [Previous footer checkpoint](handoff-before-dynamic-insight-popup-2026-11-14.md) retains earlier selection-popup/context work and archives. Next action: human feedback; no new features queued.
