#!/usr/bin/env python3
"""Offline, bounded owner discovery and structural context validation."""
import json
import argparse
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
ROUTES = json.loads((ROOT / 'docs/context/routes.json').read_text())
FEATURES = json.loads((ROOT / 'docs/context/features.json').read_text())
SENSITIVE = json.loads((ROOT / 'docs/context/sensitive.json').read_text())
LINK = re.compile(r'\[[^\]]*\]\(([^)]+)\)')


def local_links(path):
    for match in LINK.finditer(path.read_text()):
        target = match.group(1).strip('<>').split('#')[0]
        if not target or re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*:', target):
            continue
        yield (path.parent / unquote(target)).resolve()


def check():
    errors = []
    errors.extend(validate_index())
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
    print(f'Context OK: {len(ROUTES)} areas; {len(FEATURES)} features; {len(SENSITIVE)} sensitive contracts; {len(executable)} executable/config/asset paths; local links and boot budgets valid.')
    return 0


def validate_index():
    """Validate curated pointers, not semantic correctness of prose or symbols."""
    errors = []
    areas = {r['id']: r for r in ROUTES}
    guards = {g['id']: g for g in SENSITIVE}
    for name, items in [('area', ROUTES), ('feature', FEATURES), ('sensitive', SENSITIVE)]:
        ids = [item['id'] for item in items]
        if len(ids) != len(set(ids)):
            errors.append(f'duplicate {name} IDs')
    def path_exists(value):
        path = ROOT / value
        if not path.resolve().is_relative_to(ROOT) or not path.is_file():
            errors.append(f'missing or nonportable index path: {value}')
            return False
        return True
    for item in FEATURES:
        if item['area'] not in areas:
            errors.append(f'{item["id"]}: unknown area {item["area"]}')
        if not item['entry'] or not item['tests'] or not item['flow']:
            errors.append(f'{item["id"]}: empty entry/tests/flow')
        for entry in item['entry']:
            if path_exists(entry['path']) and entry['symbol'] not in (ROOT / entry['path']).read_text():
                errors.append(f'{item["id"]}: stale symbol {entry["symbol"]} in {entry["path"]}')
        for value in item['tests']:
            path_exists(value)
        for guard in item['guards']:
            if guard not in guards:
                errors.append(f'{item["id"]}: unknown sensitive contract {guard}')
    for item in SENSITIVE:
        for field in ['contract', 'regression', 'limits', 'checks', 'files', 'docs']:
            if not item[field]:
                errors.append(f'{item["id"]}: empty {field}')
        for value in item['files'] + item['docs']:
            path_exists(value)
    for name, budget in [('features.json', 24000), ('sensitive.json', 16000)]:
        if (ROOT / 'docs/context' / name).stat().st_size > budget:
            errors.append(f'index exceeds {budget}-byte budget: {name}')
    return errors


def words(value):
    return set(re.findall(r'[a-z0-9]+', value.lower()))


def rank(query):
    tokens = words(query)
    exact_areas = {a['id'] for a in ROUTES if query in a['files']}
    matches = []
    for item in FEATURES:
        paths = [e['path'] for e in item['entry']] + item['tests']
        # Exact words avoid matching `ai` inside `failure` or `page` inside `homepage`.
        score = 4 * len(tokens & words(item['id'] + ' ' + item['title']))
        score += 2 * len(tokens & set(item['keywords']))
        score += len(tokens & words(' '.join(paths)))
        score += len(tokens & words(item['area']))
        if item['area'] in exact_areas:
            score += 20
        if query == item['id'] or query in paths:
            score += 100
        if score:
            matches.append((score, item))
    return [item for _, item in sorted(matches, key=lambda pair: -pair[0])]


def changed_paths():
    """Include staged, unstaged and untracked paths; never load their contents."""
    paths = set()
    for args in [('diff', '--name-only', '-z', 'HEAD'), ('ls-files', '--others', '--exclude-standard', '-z')]:
        result = subprocess.run(['git', '-C', str(ROOT), *args], check=True, capture_output=True)
        paths.update(result.stdout.decode('utf-8', errors='replace').split('\0'))
    return paths - {''}


def route(query, limit=1, changed=None):
    if changed is None:
        matches = rank(query)
        touched = {query} if (ROOT / query).is_file() else set()
    else:
        touched = changed
        matches = [f for f in FEATURES if touched & ({e['path'] for e in f['entry']} | set(f['tests']))]
        # Broad area coverage catches secondary owners not repeated in feature entry lists.
        areas = {a['id'] for a in ROUTES if touched & set(a['files'])}
        matches += [f for f in FEATURES if f['area'] in areas and f not in matches]
        print(f'Working-tree impact hints: {len(touched)} changed paths (all existing dirty work included).')
    guards = {g for item in matches[:limit] for g in item['guards']}
    guards.update(g['id'] for g in SENSITIVE if touched & set(g['files']))
    if changed is not None:
        guards.update(g for item in matches for g in item['guards'])
    if not matches:
        print('Start at docs/README.md; no confident route. Use rg to find the owner.')
    areas = {a['id']: a for a in ROUTES}
    for item in matches[:limit]:
        area = areas[item['area']]
        print(f'\n{item["id"]}: {item["title"]}\nRules: ' + ', '.join(area['rules']))
        print('Flow: ' + item['flow'])
        for entry in item['entry']:
            print(f'Locate: {entry["path"]} :: {entry["symbol"]}')
        print('Tests: ' + ', '.join(item['tests']))
        print('Area detail (read relevant sections): ' + ', '.join(area['docs'][:3]))
    if len(matches) > limit:
        print('\nOther candidate IDs (rerun an ID to focus): ' + ', '.join(f['id'] for f in matches[limit:]))
    for guard in SENSITIVE:
        if guard['id'] in guards:
            print(f'\nSensitive [{guard["id"]}]: {guard["contract"]}')
            print('Regression: ' + guard['regression'])
            print('Read: ' + ', '.join(guard['docs']))
            print('Verify: ' + '; '.join(guard['checks']))
            print('Limits: ' + guard['limits'])
    print('\nHints only: follow actual callers with rg; read sensitive.json for regression history and authoritative references. Do not run all suggested checks blindly.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('query', nargs='*', help='task, feature ID or repository-relative path')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='validate structure and curated pointers')
    mode.add_argument('--changed', action='store_true', help='read-only working-tree impact hints')
    parser.add_argument('--limit', type=int, choices=[1, 2, 3], default=1, help='feature cards to print (default: 1)')
    args = parser.parse_args()
    if args.check:
        raise SystemExit(check())
    if args.changed:
        route('', args.limit, changed_paths())
    elif not args.query:
        print('\n'.join(f'{f["id"]}: {f["title"]}' for f in FEATURES))
    else:
        route(' '.join(args.query), args.limit)
