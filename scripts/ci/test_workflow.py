"""Release trigger, token boundary, outputs and real version/guard contracts."""
import importlib.util
from datetime import date
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('build_identifiers', Path(__file__).with_name('build-identifiers.py'))
IDS = importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(IDS)


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.load((ROOT/'.github/workflows/development-release.yml').read_text(), Loader=yaml.BaseLoader)
        self.job = self.workflow['jobs']['build-and-release'];self.steps = self.job['steps']

    def test_development_push_is_the_only_push_trigger(self):
        self.assertEqual(self.workflow['on']['push']['branches'], ['development'])
        self.assertIn("github.ref == 'refs/heads/development'", self.job['if'])
        self.assertIn("github.repository == 'Alexayy/Love2Gathering'", self.job['if'])
        self.assertNotIn('pull_request_target', self.workflow['on'])
        self.assertNotIn('concurrency', self.workflow)  # Every push keeps its own build/release.

    def test_checkout_has_no_nested_mutation_or_persisted_push_credentials(self):
        checkout = self.steps[0]
        self.assertEqual(checkout['with']['submodules'], 'false')
        self.assertEqual(checkout['with']['persist-credentials'], 'false')
        guard = next(i for i,s in enumerate(self.steps) if '--base "$BEFORE"' in s.get('run',''))
        initialize = next(i for i,s in enumerate(self.steps) if 'submodule update' in s.get('run',''))
        self.assertLess(guard, initialize)
        self.assertNotIn('--remote', self.steps[initialize]['run'])
        for s in self.steps:
            self.assertNotRegex(s.get('run',''), r'git\s+(?:-C\s+engine/mage\s+)?(?:push|commit|add)\b')

    def test_actions_are_immutable_official_commits(self):
        for step in self.steps:
            if 'uses' in step:self.assertRegex(step['uses'], r'^actions/[a-z-]+@[0-9a-f]{40}$')

    def test_logged_pipeline_failures_stop_the_job(self):
        # Explicit shell:bash selects GitHub's --noprofile --norc -eo pipefail.
        # Its unspecified Linux shell only promises bash -e, which loses a
        # failing builder's status when tee succeeds.
        self.assertEqual(self.workflow['defaults']['run']['shell'], 'bash')
        for step in self.steps:
            if 'run' in step:self.assertNotIn('shell', step)
        result = subprocess.run(['bash', '--noprofile', '--norc', '-eo', 'pipefail', '-c',
                                 'false | tee /dev/null'], capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_release_token_only_reaches_final_publisher(self):
        exposed = [s for s in self.steps if 'GH_TOKEN' in s.get('env',{}) or 'GITHUB_TOKEN' in s.get('env',{})]
        self.assertEqual(len(exposed),1)
        publisher = exposed[0];self.assertIn('scripts/ci/publish-release.py',publisher['run'])
        self.assertNotIn('if',publisher)  # Normal success gating; never always() publish.
        after = self.steps[self.steps.index(publisher)+1:]
        self.assertEqual(len(after),1);self.assertIn('upload-artifact',after[0]['uses'])
        for extension in ('.deb','.rpm','.exe','.flatpak'):
            self.assertNotIn('*'+extension,after[0]['with']['path'])

    def test_all_builders_share_one_validated_version(self):
        builds = [s for s in self.steps if any(p in s.get('run','') for p in ('python3 packaging/build.py','python3 packaging/windows/build.py','python3 packaging/flatpak/build.py'))]
        self.assertEqual(len(builds),3)
        for step in builds:
            self.assertEqual(step['env']['VERSION'],'${{ steps.release.outputs.version }}')
            self.assertIn('--version "$VERSION"',step['run'])

    def test_numeric_version_and_attempt_tags_are_unique(self):
        first = IDS.identifiers(42,1,'a'*40,date(2026,11,15))
        second = IDS.identifiers(42,2,'a'*40,date(2026,11,15))
        self.assertEqual(first['version'],'2026.11.15.42')
        self.assertEqual(first['tag'],'development-42-1-'+'a'*12)
        self.assertNotEqual(first['tag'],second['tag'])
        for args in [(0,1,'a'*40),(65536,1,'a'*40),(1,0,'a'*40),(1,1,'bad\ninjected=value')]:
            with self.assertRaises(ValueError):IDS.identifiers(*args)

    def test_output_file_contains_only_the_validated_fields(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)/'output'
            result = subprocess.run([sys.executable,str(ROOT/'scripts/ci/build-identifiers.py'),'--number','42','--attempt','2','--commit','b'*40],env=dict(os.environ,GITHUB_OUTPUT=str(output)),capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            values=dict(line.split('=',1)for line in output.read_text().splitlines())
            self.assertEqual(set(values),{'version','tag'});self.assertEqual(values['tag'],'development-42-2-'+'b'*12)


if __name__=='__main__':unittest.main()
