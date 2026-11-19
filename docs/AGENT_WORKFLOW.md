# Context harness workflow

This is a repository-local, offline harness for coding agents. It supplements source inspection; it cannot guarantee mistake-free changes. It installs no global instructions, hooks, background agents or paid model calls.

## Load context progressively

1. Read [root rules](../AGENTS.md), the short [handoff](../handoff.md), and `git status --short`. Identify existing dirty work before editing. Do not read archived sessions by default.
2. Run `python3 scripts/context.py` for feature IDs, then `python3 scripts/context.py "task or path"`. One focused card includes entry symbols, data flow, scoped rules, tests and sensitive contracts. Use `--limit 3` only when the task crosses features. An exact feature ID or entry path takes priority over word matches.
3. Read returned scoped AGENTS, then locate entry symbols with `rg -n`. Read bounded sections and trace callers, persistence and callbacks. The feature index is a starting set, not a dependency graph. Shared Workspace changes often cross features.
4. Read the relevant sections of authoritative docs from the [map](README.md). Load only the matching records in [sensitive memory](context/sensitive.json). Keep papers, credentials, user libraries and generated/vendor assets out of agent context unless specifically needed and authorized.

Examples, from the native repository:

```sh
python3 scripts/context.py annotations
python3 scripts/context.py "selection explanation popup"
python3 scripts/context.py Sources/FolioCore/ClaudeKeyStore.swift
python3 scripts/context.py --changed
rg -n 'savePageStructure|finishEditorIfNeeded' Sources/FolioMac
```

`--changed` reads staged/unstaged names relative to HEAD and untracked names using Git; it never opens file contents. It includes pre-existing dirty work and broad area neighbors, so it is not an attribution tool. Renames/deletions can require manual routing. Task text is data and is never executed. Unknown tasks fall back to the map. Suggested checks are instructions to evaluate, never automatically executed by the router.

## Change protocol

Before editing, establish the feature owner, actual caller/data flow, invariant and observable success/failure target. For persisted or async changes, trace failure, retry, cancellation, stale identity and fresh reload, not only the happy path. Read applicable sensitive records before changing their owners; they identify prior regressions, checks and verification limits. These records are cautionary memory, not proof that an area is perfect or permission requirements. Current human instructions remain authoritative.

Make the smallest coherent change. Use injected providers and disposable generated PDFs. Run checks appropriate to the changed behavior; add failure/recovery tests when they protect a real contract. A build or source inspection does not establish GUI geometry, accessibility or arbitrary PDF export fidelity. Do not run live-provider tests or touch a normal library as routine harness verification.

Before checkpointing, review the scoped diff and run:

```sh
python3 scripts/context.py --check
# Required when changing harness code or indexes:
python3 scripts/test_context.py
git diff --check
```

## Keep memory useful

Each fact has one authoritative home in the [map](README.md). Product behavior belongs in STATE; mechanisms in ARCHITECTURE; requirements in DECISIONS; risks in QUALITY; dated evidence in TESTING. A harness-only change does not require rewriting application behavior docs.

- [Area routes](context/routes.json) cover executable/config/asset paths and broader documentation. Route added/moved/deleted files here.
- [Features](context/features.json) own concise entry symbols, data flows, test pointers and sensitive IDs. Add a feature when an independent user task needs a distinct starting point, rather than repeating the entire area inventory. Keep paths/symbols aligned when moving code.
- [Sensitive memory](context/sensitive.json) owns change hazards: protected contract, owners, regression mechanism, authoritative references, checks and limits. Update a record when its mechanism changes or evidence contradicts it; avoid speculative warnings and "never touch" claims. Do not store secrets or personal data. L5/L6 in the logic audit remain decisions, not implementation authorization.
- Replace handoff with a dated checkpoint, preserving another active checkpoint by link. Include request/status, changed paths/decisions, exact checks and limits, next authorized action. After compaction, recover from that checkpoint and the scoped diff; do not replay every archive or infer new backlog work.

## Validation boundaries

`--check` validates area coverage, paths, feature/guard IDs, entry-symbol substrings, local Markdown file links, document reachability, CLAUDE imports and byte budgets. It does not validate heading fragments, semantic truth, complete dependencies, executable test commands or model adherence. Missing/malformed JSON fails the check; an existing but inaccurate description still needs human/source review. Symbol checks detect missing text, not unique declarations.

Budgets: root AGENTS ≤6,000 bytes; handoff ≤3,500; map ≤5,000; scoped AGENTS ≤2,000; feature index ≤24,000; sensitive index ≤16,000. The full indexes are on-demand, not mandatory boot reads. Offline regressions check representative routing, exact IDs/paths, unknown fallback, task-text safety, Git filename handling, stale pointers and default output ≤12,000 bytes per feature. These checks run in macOS CI; a configured workflow is not evidence of a hosted pass.

CLAUDE wrappers import only sibling AGENTS; provider-specific policy copies must not drift. Navigation uses repository-relative links and works without the sibling web repository.
