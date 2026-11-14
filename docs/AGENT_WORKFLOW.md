# Context harness workflow

Boot: [root rules](../AGENTS.md) → short [handoff](../handoff.md) → Git status → `python3 scripts/context.py "task or path"`. The router ranks curated routes, prints at most three, and points to scoped rules, source symbols, docs and checks. Unknown input returns the context map. It does not read papers, call AI, fetch the web or execute task text. Use `rg -n` plus bounded reads to follow actual callers before editing.

Each fact has one home in the [map](README.md). After changing behavior, update the corresponding authoritative statement. Route new/moved/deleted executable sources/config/tests/scripts/workflows in [routes](context/routes.json). Replace the current handoff rather than accumulating a session diary; preserve another active task's checkpoint. Record exact fresh commands and explicit unverified boundaries. Future parity rows do not authorize implementation.

`python3 scripts/context.py --check` validates route paths, scoped rules, source/config/tool coverage, local Markdown links (file targets), reachable docs, exact CLAUDE imports and boot byte budgets. It does not prove semantic truth, heading fragments, runtime behavior or model adherence. Root AGENTS ≤6,000 bytes; handoff ≤3,500; map ≤5,000; scoped AGENTS ≤2,000. Keep historical detail out of mandatory boot context. No global instructions, Git hooks, background agent, automatic publication or paid model call is installed.

CLAUDE wrappers import only their sibling AGENTS. The repo's AGENTS is the shared policy; provider-specific copies must not drift. The checker is run in macOS CI and manually at checkpoint time. Standalone clone navigation uses only repository-relative links; the sibling web folder is not required.
