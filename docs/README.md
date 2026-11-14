# Context map

[Agent entry](../AGENTS.md) · [Handoff](../handoff.md) · [Project README](../README.md)

Read the handoff, inspect Git status, then run `python3 scripts/context.py "task or path"`. It ranks a small curated index and returns owners, rules and checks. Unknown tasks fall back to this map; routing is a hint, not evidence.

| Question | Authoritative home |
| --- | --- |
| What runs today? | [Current state](STATE.md) |
| Which source owns a behavior? | [Architecture](ARCHITECTURE.md), [route manifest](context/routes.json) |
| What matches the web app and what remains? | [Porting map](PORTING.md), [web reference](WEB_REFERENCE.md) |
| Which choices are settled? | [Decisions](DECISIONS.md) |
| What needs care? | [Quality and limits](QUALITY.md) |
| How do I build, launch and verify? | [Development](DEVELOPMENT.md), [fresh test evidence](TESTING.md) |
| How does agent context stay current? | [Harness workflow](AGENT_WORKFLOW.md) |

Scoped rules: [Sources](../Sources/AGENTS.md), [Tests](../Tests/AGENTS.md), [scripts](../scripts/AGENTS.md), [docs](AGENTS.md). Context is entirely repository-local, with no model calls, background agents or machine-global configuration.
