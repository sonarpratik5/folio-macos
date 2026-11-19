# Current handoff

## Menu bar pull launcher — 2026-11-15

- Request/status: adapt the Productivity pull interaction into native Folio with open-app and recent-PDF actions. Implemented a book status icon; click or pull down/release opens the launcher, return toward menu bar cancels. Shows Open Folio, five recent PDFs with saved page, empty state and Quit. Closing the last workspace window now keeps the menu bar available. Existing window is raised/restored; closed workspace uses SwiftUI openWindow resolved inside the scene.
- Changed: Sources/FolioMac/MenuBarController.swift (status item, capture/action/global fallback, pointer polling, transient popover, elastic screen-local overlay and gesture state), FolioApp.swift (lifecycle/window bridge), Tests/FolioMacTests/MenuBarTests.swift; docs STATE/ARCHITECTURE/DECISIONS/PORTING/QUALITY/TESTING and context routes. Preserved all pre-existing dirty work; Productivity and web source unchanged.
- Checks: final MenuBarTests passed, 3 tests, 0 failures (/tmp/folio-menubar-tests-final.log); context check and git diff --check passed. Debug app packaging/signature verification passed using host macOS services; sandbox iconutil failed. Bundle: .build/Folio.app. Host launch accepted an isolated /tmp/folio-menubar-qa-20261115 library. Desktop tool timed out while binding the app, so no visual click/pull/reopen or recent-PDF GUI evidence. No installed app replacement, real-paper automation, commit or publication.
- Limits/next: manually check click, downward pull, return-to-cancel, recent PDF page restoration and close/reopen on supported macOS. No timer or launch-at-login added.
- Preserved prior checkpoint: [prior checkpoint](handoff-before-menu-bar-2026-11-15.md).
