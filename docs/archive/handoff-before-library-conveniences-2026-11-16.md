# Current handoff

## Native agent harness — 2026-11-16

- Request/status: audit and strengthen only the macOS application's agent harness. Complete; existing harness extended, no application behavior or sibling web files changed.
- Changed: AGENTS, docs/README and AGENT_WORKFLOW; scripts/context.py and new scripts/test_context.py; docs/context/features.json (13 focused features), sensitive.json (7 contract records), routes.json; CI harness checks and TESTING evidence.
- Decisions: offline, dependency-free discovery; one feature card by default, related IDs, optional --limit 3; exact entry-path/ID priority and read-only --changed impact hints. Sensitive memory records contract/owners/regression/checks/limits with authoritative references; no area is certified perfect or forbidden to change. Existing product decisions remain authoritative.
- Checks: python3 scripts/test_context.py — 7 passed; python3 scripts/context.py --check — 6 areas, 13 features, 7 sensitive contracts, 100 executable/config/asset paths; git diff --check passed. Manually inspected feature query, --changed and --help output. No Swift build/tests, GUI checks or provider calls for this tooling/docs-only task; runtime claims remain in prior evidence.
- Preserved pre-existing dirty native work; no commit/publication. Previous active [palette/install checkpoint](handoff-before-harness-audit-2026-11-16.md) retained with its earlier checkpoint link.
- Next authorized action: use the harness for the next human-requested macOS change; no additional product work inferred.
