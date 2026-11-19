# Current handoff

## Blue app icon — 2026-11-14

- Request/status: change the logo to blue to suit the theme. Done in native macOS app, following the active Liquid Glass theme; web repository untouched.
- Changed `Assets/Icon-512.png`: blue rounded tile with frosted open-paper/book mark. Generated through connected Copilot image tool after built-in imagegen endpoint returned 404; resized with sips and visually inspected. No source/runtime behavior changes. Updated STATE and TESTING.
- Fresh checks: `FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh debug` passed with host macOS tool access (sandbox iconutil failed). Updated `.build/Folio.app`, including all icon sizes and ad-hoc signing. Asset metadata, signature, context and whitespace checked; see TESTING for evidence. No unit suite or live Dock/Finder inspection for asset-only change.
- Preserved all prior native changes and dirty web work. Prior copy/theme/credential/selection checkpoint: [archive](handoff-before-blue-icon-2026-11-14.md).
- Next action: human feedback; no feature expansion or publication authorized.
