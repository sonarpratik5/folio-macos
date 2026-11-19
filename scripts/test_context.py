#!/usr/bin/env python3
"""Offline harness regressions: routing, preservation boundaries and stale pointers."""
import copy
import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('folio_context', Path(__file__).with_name('context.py'))
context = importlib.util.module_from_spec(spec)
spec.loader.exec_module(context)


class ContextTests(unittest.TestCase):
    def render(self, query='', **kwargs):
        output = io.StringIO()
        with redirect_stdout(output):
            context.route(query, **kwargs)
        return output.getvalue()

    def test_features_are_addressable_by_id_and_exact_entry_path(self):
        for item in context.FEATURES:
            self.assertEqual(context.rank(item['id'])[0]['id'], item['id'])
        self.assertEqual(context.rank('Sources/FolioMac/SelectionInsightView.swift')[0]['id'], 'selection-insight')
        self.assertEqual(context.rank('Sources/FolioMac/ReaderState.swift')[0]['id'], 'reader-search')

    def test_task_routing_and_unknown_fallback(self):
        for query, expected in [('highlight colors', 'annotations'), ('keychain credentials', 'credentials'),
                                ('pull timer', 'menu-timer'), ('selection explanation popup', 'selection-insight'),
                                ('agent harness memory', 'agent-harness')]:
            self.assertEqual(context.rank(query)[0]['id'], expected)
        self.assertIn('no confident route', self.render('zzzzunknown'))
        self.assertEqual(context.rank('failure'), [])

    def test_query_is_data_and_does_not_execute_git_or_shell(self):
        with patch.object(context.subprocess, 'run', side_effect=AssertionError('must stay offline')):
            self.render('$(touch /tmp/folio-must-not-exist); `whoami`')

    def test_secondary_changed_owner_still_surfaces_sensitive_contract(self):
        result = self.render(changed={'Sources/FolioCore/ClaudeKeyStore.swift'})
        self.assertIn('Sensitive [credentials]', result)
        self.assertIn('Sensitive [provider]', result)
        self.assertIn('all existing dirty work included', result)

    def test_changed_paths_handles_spaces_and_includes_untracked_without_reading_content(self):
        class Result:
            def __init__(self, stdout): self.stdout = stdout
        with patch.object(context.subprocess, 'run', side_effect=[Result(b'Sources/space name.swift\0'), Result(b'scripts/new.py\0')]) as run:
            self.assertEqual(context.changed_paths(), {'Sources/space name.swift', 'scripts/new.py'})
            for call in run.call_args_list:
                self.assertNotIn('shell', call.kwargs)
                self.assertIn('-z', call.args[0])

    def test_curated_pointers_validate_and_detect_drift(self):
        self.assertEqual(context.validate_index(), [])
        features = copy.deepcopy(context.FEATURES)
        features[0]['entry'][0]['symbol'] = 'MISSING_SENTINEL_SYMBOL'
        features[0]['guards'].append('missing-contract')
        features[0]['tests'].append('../outside-repository.py')
        features.append(copy.deepcopy(features[0]))
        with patch.object(context, 'FEATURES', features):
            errors = '\n'.join(context.validate_index())
        for expected in ['stale symbol', 'unknown sensitive contract', 'nonportable', 'duplicate feature']:
            self.assertIn(expected, errors)

    def test_default_output_stays_bounded_and_lists_related_ids(self):
        for feature in context.FEATURES:
            output = self.render(feature['id'])
            self.assertLessEqual(len(output.encode()), 12000)
        output = self.render('reader', limit=1)
        self.assertIn('Other candidate IDs', output)
        self.assertEqual(output.count('\nFlow:'), 1)
        self.assertLessEqual(len(self.render(changed=set()).encode()), 12000)
        all_paths = {p for area in context.ROUTES for p in area['files']}
        self.assertLessEqual(len(self.render(changed=all_paths).encode()), 12000)


if __name__ == '__main__':
    unittest.main()
