#!/usr/bin/env python3
"""Offline, bounded owner discovery and structural context validation."""
import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
ROUTES = json.loads((ROOT / 'docs/context/routes.json').read_text())
LINK = re.compile(r'\[[^\]]*\]\(([^)]+)\)')


def local_links(path):
    for match in LINK.finditer(path.read_text()):
        target = match.group(1).strip('<>').split('#')[0]
        if not target or re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*:', target):
            continue
        yield (path.parent / unquote(target)).resolve()


def check():
    errors = []
    covered = set()
    for route in ROUTES:
        for key in ['rules', 'files', 'docs']:
            for value in route[key]:
                if not (ROOT / value).is_file():
                    errors.append(f'{route["id"]}: missing {key} path {value}')
        covered.update(route['files'])
        covered.update(route['rules'])
    executable = {p.relative_to(ROOT).as_posix()
                  for directory in ['Sources', 'Tests', 'scripts', '.github/workflows', 'Resources', 'Assets']
                  for p in (ROOT / directory).rglob('*')
                  if p.is_file() and p.suffix in {'.swift', '.sh', '.py', '.yml', '.yaml', '.plist', '.png'}}
    executable.add('Package.swift')
    for missing in sorted(executable - covered):
        errors.append(f'unrouted executable/config/asset: {missing}')
    documents = [ROOT / 'README.md', ROOT / 'AGENTS.md', ROOT / 'handoff.md', *(ROOT / 'docs').rglob('*.md')]
    for path in documents:
        if not path.is_file():
            errors.append(f'missing document: {path.relative_to(ROOT)}')
            continue
        for target in local_links(path):
            if not target.is_relative_to(ROOT) or not target.exists():
                errors.append(f'broken or nonportable link: {path.relative_to(ROOT)} -> {target.name}')
    reached, queue = set(), [ROOT / 'docs/README.md', ROOT / 'AGENTS.md', ROOT / 'README.md']
    while queue:
        path = queue.pop()
        if path in reached or not path.is_file() or path.suffix != '.md':
            continue
        reached.add(path)
        queue.extend(local_links(path))
    for path in (ROOT / 'docs').rglob('*.md'):
        if path.name not in {'AGENTS.md', 'CLAUDE.md'} and path not in reached:
            errors.append(f'unreachable doc: {path.relative_to(ROOT)}')
    budgets = {'AGENTS.md': 6000, 'handoff.md': 3500, 'docs/README.md': 5000}
    for directory in ['Sources', 'Tests', 'scripts', 'docs']:
        budgets[f'{directory}/AGENTS.md'] = 2000
    for name, budget in budgets.items():
        path = ROOT / name
        if not path.is_file() or path.stat().st_size > budget:
            errors.append(f'missing or over {budget}-byte budget: {name}')
        wrapper = path.with_name('CLAUDE.md') if path.name == 'AGENTS.md' else None
        if wrapper and (not wrapper.is_file() or wrapper.read_text().strip() != '@AGENTS.md'):
            errors.append(f'CLAUDE wrapper must import only sibling AGENTS: {wrapper.relative_to(ROOT)}')
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print(f'Context OK: {len(ROUTES)} routes; {len(executable)} executable/config/asset paths; local links and boot budgets valid.')
    return 0


def route(query):
    tokens = set(re.findall(r'[a-z0-9]+', query.lower()))
    matches = []
    for item in ROUTES:
        haystack = ' '.join([item['id'], item['title'], *item['keywords'], *item['files']]).lower()
        score = sum(1 for token in tokens if token in haystack)
        if score:
            matches.append((score, item))
    if not matches:
        print('Start at docs/README.md; no confident route. Use rg to find the owner.')
        return
    for _, item in sorted(matches, key=lambda pair: -pair[0])[:3]:
        print(f'\n{item["id"]}: {item["title"]}')
        for label, key in [('Rules', 'rules'), ('Start', 'files'), ('Read', 'docs'), ('Locate', 'symbols'), ('Checks', 'checks')]:
            print(f'{label}: ' + ', '.join(item[key]))


if __name__ == '__main__':
    if sys.argv[1:] == ['--check']:
        raise SystemExit(check())
    if not sys.argv[1:]:
        print('\n'.join(f'{r["id"]}: {r["title"]}' for r in ROUTES))
    else:
        route(' '.join(sys.argv[1:]))
