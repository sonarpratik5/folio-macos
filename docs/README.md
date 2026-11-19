# Context map

[Agent entry](../AGENTS.md) · [Handoff](../handoff.md) · [Project README](../README.md)

Read the handoff, inspect Git status, then run `python3 scripts/context.py "task or path"`. It ranks a small curated index and returns owners, rules and checks. Unknown tasks fall back to this map; routing is a hint, not evidence.

Run the router without arguments to list feature IDs; rerun one ID for a focused card. Default output is one card plus related IDs and applicable sensitive contracts. `--limit 3` expands discovery; `--changed` gives read-only impact hints for all current dirty work, including untracked files.

| Question | Authoritative home |
| --- | --- |
| What runs today? | [Current state](STATE.md) |
| Which source owns a behavior? | [Architecture](ARCHITECTURE.md), [route manifest](context/routes.json) |
| What matches the web app and what remains? | [Porting map](PORTING.md), [web reference](WEB_REFERENCE.md) |
| Which choices are settled? | [Decisions](DECISIONS.md) |
| Which logic contracts and gaps were audited? | [Logic audit](LOGIC_AUDIT.md) |
| What needs care? | [Quality and limits](QUALITY.md) |
| How are PDF tools verified? | [PDF editing verification design](PDF_EDITING_VERIFICATION.md) |
| How do I build, launch and verify? | [Development](DEVELOPMENT.md), [fresh test evidence](TESTING.md) |
| How do I use and configure AI? | [Native assistant setup](AI_SETUP.md) |
| How does local Skim work? | [Model provenance and export](../Models/Skim/MODEL.md), [architecture](ARCHITECTURE.md#local-skim-highlights) |
| Which application logic contracts were audited? | [Logic audit](LOGIC_AUDIT.md) |
| How does agent context stay current? | [Harness workflow](AGENT_WORKFLOW.md) |
| How do I jump to a feature and its data flow? | [Feature index](context/features.json), `python3 scripts/context.py <feature-id>` |
| Which fragile contracts must survive a change? | [Sensitive memory](context/sensitive.json): owners, regression mechanism, checks and limits |

Scoped rules: [Sources](../Sources/AGENTS.md), [Tests](../Tests/AGENTS.md), [scripts](../scripts/AGENTS.md), [docs](AGENTS.md). Context is entirely repository-local, with no model calls, background agents or machine-global configuration.

Latest [correctness/performance audit](LOGIC_AUDIT.md#correctness-and-performance-follow-up--2026-11-16) · [preserved previous checkpoint](archive/handoff-before-native-audit-2026-11-16.md).
