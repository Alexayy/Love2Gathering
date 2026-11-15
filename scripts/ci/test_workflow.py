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
from unittest.mock import patch
from contextlib import redirect_stdout
import io

import yaml

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('build_identifiers', Path(__file__).with_name('build-identifiers.py'))
IDS = importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(IDS)


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.load((ROOT/'.github/workflows/development-release.yml').read_text(), Loader=yaml.BaseLoader)
        self.job = self.workflow['jobs']['build-and-release'];self.steps = self.job['steps']

    def test_only_development_and_master_pushes_publish_installers(self):
        self.assertEqual(self.workflow['on']['push']['branches'], ['development', 'master'])
        self.assertIn("github.ref == 'refs/heads/development'", self.job['if'])
        self.assertIn("github.ref == 'refs/heads/master'", self.job['if'])
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
        self.assertEqual(len(exposed),2)
        preflight,publisher = exposed
        self.assertIn('--check-published',preflight['run']);self.assertIn('scripts/ci/publish-release.py',publisher['run'])
        self.assertEqual(publisher['if'],"steps.published.outputs.already_published != 'true'")
        self.assertNotIn('always()',publisher['if'])
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
        self.assertEqual(first['tag'],'DEV-2026.11.15.42-1-'+'a'*12)
        self.assertNotEqual(first['tag'],second['tag'])
        for args in [(0,1,'a'*40),(65536,1,'a'*40),(1,0,'a'*40),(1,1,'bad\ninjected=value')]:
            with self.assertRaises(ValueError):IDS.identifiers(*args)

    def test_master_tag_keeps_its_identity_across_retry_attempts(self):
        first=IDS.identifiers(42,1,'a'*40,date(2026,11,15),branch='master')
        retry=IDS.identifiers(42,2,'a'*40,date(2026,11,15),branch='master')
        self.assertEqual(first,retry)
        self.assertEqual(first['tag'],'v2026.11.15.42');self.assertEqual(first['channel'],'stable')
        with self.assertRaises(ValueError):IDS.identifiers(42,1,'a'*40,branch='feature')

    def test_cli_version_uses_commit_date_in_belgrade_instead_of_retry_clock(self):
        with patch.object(IDS.subprocess,'check_output',return_value='2026-11-14T23:30:00+00:00'), \
             patch.object(sys,'argv',['build-identifiers.py','--number','42','--attempt','2','--commit','a'*40,'--branch','master']), \
             patch.dict(os.environ,{},clear=True),redirect_stdout(io.StringIO())as output:
            IDS.main()
        import json
        self.assertEqual(json.loads(output.getvalue())['tag'],'v2026.11.15.42')

    def test_invalid_sha_is_rejected_before_git_can_interpret_it_as_an_option(self):
        with patch.object(IDS.subprocess,'check_output',side_effect=AssertionError('InvalidSHA reached git')), \
             patch.object(sys,'argv',['build-identifiers.py','--number','42','--commit=--output=/tmp/unwanted','--branch','master']), \
             patch.dict(os.environ,{},clear=True),patch.object(sys,'stderr',io.StringIO()),self.assertRaises(SystemExit):IDS.main()

    def test_retry_skip_is_after_pin_guard_and_wraps_every_mutating_or_expensive_step(self):
        probe=next(i for i,s in enumerate(self.steps)if '--check-published'in s.get('run',''))
        guard=next(i for i,s in enumerate(self.steps)if 'check-submodule-pin.py'in s.get('run',''))
        self.assertLess(guard,probe)
        for step in self.steps[probe+1:-1]:self.assertEqual(step['if'],"steps.published.outputs.already_published != 'true'")
        common=next(s for s in self.steps if 'python3 packaging/build.py'in s.get('run',''))
        for flag in ('--channel "$RELEASE_CHANNEL"','--branch "$RELEASE_BRANCH"','--tag "$RELEASE_TAG"'):self.assertIn(flag,common['run'])

    def test_latest_promotion_alone_is_serialized_and_runs_after_successful_master_release(self):
        self.assertNotIn('concurrency',self.job)
        job=self.workflow['jobs']['promote-stable-latest']
        self.assertEqual(job['needs'],'build-and-release')
        self.assertIn("github.ref == 'refs/heads/master'",job['if'])
        self.assertIn("needs.build-and-release.result == 'success'",job['if'])
        self.assertEqual(job['concurrency'],{'group':'stable-latest','cancel-in-progress':'false'})
        steps=job['steps'];self.assertEqual(steps[0]['with']['submodules'],'false');self.assertEqual(steps[0]['with']['persist-credentials'],'false')
        self.assertIn('check-submodule-pin.py',steps[1]['run']);self.assertIn('promote-latest.py',steps[2]['run'])
        self.assertEqual(len(steps),3)
        for step in steps:self.assertNotRegex(step.get('run',''),r'git\s+.*\b(push|commit|add)\b')

    def test_optional_release_token_is_confined_to_three_release_endpoints(self):
        allowed=('--check-published','--dist dist','scripts/ci/promote-latest.py')
        exposed=[]
        for job in self.workflow['jobs'].values():
            self.assertNotIn('GH_TOKEN',job.get('env',{}));self.assertNotIn('RELEASE_TOKEN',job.get('env',{}))
            for step in job['steps']:
                value=step.get('env',{}).get('GH_TOKEN')
                if value is not None:
                    exposed.append(step)
                    self.assertEqual(value,'${{ secrets.RELEASE_TOKEN || github.token }}')
                    self.assertTrue(any(flag in step.get('run','')for flag in allowed))
                if 'uses'in step and'checkout'in step['uses']:
                    self.assertNotIn('token',step['with']);self.assertEqual(step['with']['persist-credentials'],'false')
        self.assertEqual(len(exposed),3)
        text=(ROOT/'.github/workflows/development-release.yml').read_text()
        self.assertEqual(text.count('secrets.RELEASE_TOKEN'),3)

    def test_output_file_contains_only_the_validated_fields(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)/'output'
            result = subprocess.run([sys.executable,str(ROOT/'scripts/ci/build-identifiers.py'),'--number','42','--attempt','2','--commit','b'*40,'--date','2026-11-15','--branch','development'],env=dict(os.environ,GITHUB_OUTPUT=str(output)),capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            values=dict(line.split('=',1)for line in output.read_text().splitlines())
            self.assertEqual(set(values),{'version','tag','channel','branch'});self.assertEqual(values['tag'],'DEV-2026.11.15.42-2-'+'b'*12)


if __name__=='__main__':unittest.main()
