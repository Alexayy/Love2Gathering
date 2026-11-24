"""Real isolated Git-object/index guards; local bare remotes only."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / 'scripts/check-submodule-pin.py'
PUSH = ROOT / 'scripts/push-development.sh'
PIN = '2a96b0ac129dfd77946eaad536184d3b35fb5e64'
OTHER = '1234567890abcdef1234567890abcdef12345678'
MODULES = '[submodule "engine/mage"]\n\tpath = engine/mage\n\turl = https://github.com/magefree/mage.git\n'


class SubmodulePublishGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='love2gathering-git-guard-')
        self.root = Path(self.temp.name)
        self.repo = self.root / 'parent'; self.repo.mkdir()
        self.git('init', '-q', '-b', 'development')
        self.git('config', 'user.name', 'Isolated Test')
        self.git('config', 'user.email', 'test@example.invalid')
        (self.repo / '.gitmodules').write_text(MODULES)
        (self.repo / 'app.txt').write_text('base\n')
        self.git('add', '.gitmodules', 'app.txt')
        self.git('update-index', '--add', '--cacheinfo', '160000,' + PIN + ',engine/mage')
        self.git('commit', '-qm', 'base pinned engine')
        self.base = self.git('rev-parse', 'HEAD').stdout.strip()

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args, cwd=None, check=True):
        return subprocess.run(['git', *args], cwd=cwd or self.repo, check=check, capture_output=True, text=True)

    def guard(self, *args):
        return subprocess.run(['python3', str(CHECK), '--base', self.base, '--index', *args], cwd=self.repo, capture_output=True, text=True)

    def commit(self, content):
        (self.repo / 'app.txt').write_text(content)
        self.git('add', 'app.txt'); self.git('commit', '-qm', 'parent change')

    def test_clean_parent_commits_are_checked(self):
        self.commit('first\n'); self.commit('second\n')
        result = self.guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('"outgoingCommits": 2', result.stdout)

    def test_staged_gitlink_change_is_rejected_without_resetting_it(self):
        self.git('update-index', '--cacheinfo', '160000,' + OTHER + ',engine/mage')
        self.assertNotEqual(self.guard().returncode, 0)
        self.assertIn(OTHER, self.git('ls-files', '--stage', 'engine/mage').stdout)

    def test_changed_then_restored_pin_in_outgoing_history_is_rejected(self):
        self.git('update-index', '--cacheinfo', '160000,' + OTHER + ',engine/mage')
        self.git('commit', '-qm', 'unwanted engine advance')
        self.git('update-index', '--cacheinfo', '160000,' + PIN + ',engine/mage')
        self.git('commit', '-qm', 'restore engine')
        self.assertNotEqual(self.guard().returncode, 0)

    def test_submodule_url_change_is_rejected(self):
        (self.repo / '.gitmodules').write_text(MODULES.replace('magefree/mage', 'someone/other'))
        self.git('add', '.gitmodules')
        self.assertNotEqual(self.guard().returncode, 0)

    def test_extra_gitlink_is_rejected(self):
        self.git('update-index', '--add', '--cacheinfo', '160000,' + OTHER + ',engine/extra')
        self.assertNotEqual(self.guard().returncode, 0)

    def test_wrong_baseline_pin_is_not_trusted(self):
        self.git('update-index', '--cacheinfo', '160000,' + OTHER + ',engine/mage')
        self.git('commit', '-qm', 'bad baseline')
        self.base = self.git('rev-parse', 'HEAD').stdout.strip()
        self.assertNotEqual(self.guard().returncode, 0)

    def upgrade_guard(self, *args):
        # Substitute only the exact allowlisted base SHA with this fixture's
        # independently created old base; production has no override switch.
        check = self.root / 'upgrade-check.py'
        check.write_text(CHECK.read_text().replace('0c797b1db53540c99a8739230818646f195544c5', self.base))
        return subprocess.run(['python3', str(check), '--base', self.base, '--index', *args],
                              cwd=self.repo, capture_output=True, text=True)

    def old_upgrade_base(self):
        old = 'd9b266fc981024873ac7ec5f90ee7121a060725e'
        self.git('update-index', '--cacheinfo', '160000,' + old + ',engine/mage')
        self.git('commit', '-qm', 'exact published old snapshot fixture')
        self.base = self.git('rev-parse', 'HEAD').stdout.strip()

    def test_reviewed_upgrade_from_exact_published_base_is_allowed(self):
        self.old_upgrade_base()
        self.git('update-index', '--cacheinfo', '160000,' + PIN + ',engine/mage')
        self.git('commit', '-qm', 'reviewed engine update')
        self.commit('subsequent packaging changes\n')
        result = self.upgrade_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        # The same old pin at an unrecognized base remains rejected.
        self.assertNotEqual(self.guard().returncode, 0)

    def test_upgrade_allowlist_does_not_allow_an_old_or_intermediate_outgoing_pin(self):
        self.old_upgrade_base()
        self.commit('old-pin intermediate commit\n')
        self.git('update-index', '--cacheinfo', '160000,' + PIN + ',engine/mage')
        self.git('commit', '-qm', 'eventual reviewed pin')
        self.assertNotEqual(self.upgrade_guard().returncode, 0)

    def test_upgrade_allowlist_cannot_publish_old_head(self):
        self.old_upgrade_base()
        self.assertNotEqual(self.upgrade_guard().returncode, 0)

    def test_upgrade_still_checks_official_url_and_index(self):
        self.old_upgrade_base()
        self.git('update-index', '--cacheinfo', '160000,' + PIN + ',engine/mage')
        self.git('commit', '-qm', 'reviewed engine update')
        (self.repo / '.gitmodules').write_text(MODULES.replace('magefree/mage', 'someone/other'))
        self.git('add', '.gitmodules')
        self.assertNotEqual(self.upgrade_guard().returncode, 0)

    def test_parent_publish_ignores_dirty_nested_repo_and_never_pushes_it(self):
        parent_remote = self.root / 'parent.git'; child_remote = self.root / 'engine.git'
        self.git('init', '--bare', '-q', str(parent_remote))
        self.git('init', '--bare', '-q', str(child_remote))
        child = self.repo / 'engine/mage'; child.mkdir(parents=True)
        self.git('init', '-q', cwd=child)
        self.git('config', 'user.name', 'Engine Test', cwd=child)
        self.git('config', 'user.email', 'engine@example.invalid', cwd=child)
        self.git('remote', 'add', 'origin', str(child_remote), cwd=child)
        (child / 'keep.txt').write_text('engine commit\n')
        self.git('add', 'keep.txt', cwd=child); self.git('commit', '-qm', 'local engine commit', cwd=child)
        (child / 'keep.txt').write_text('uncommitted engine work\n')
        engine_head = self.git('rev-parse', 'HEAD', cwd=child).stdout
        self.commit('parent release\n')
        self.git('remote', 'add', 'origin', str(parent_remote))
        self.git('config', 'push.recurseSubmodules', 'on-demand')
        result = self.guard(); self.assertEqual(result.returncode, 0, result.stderr)
        self.git('-c', 'push.recurseSubmodules=no', 'push', '--recurse-submodules=no', '--no-follow-tags', 'origin', 'HEAD:refs/heads/development')
        self.assertEqual(self.git('--git-dir=' + str(parent_remote), 'rev-parse', 'development').stdout, self.git('rev-parse', 'HEAD').stdout)
        self.assertEqual(self.git('--git-dir=' + str(child_remote), 'show-ref', check=False).stdout, '')
        self.assertEqual(self.git('rev-parse', 'HEAD', cwd=child).stdout, engine_head)
        self.assertEqual((child / 'keep.txt').read_text(), 'uncommitted engine work\n')

    def test_push_wrapper_rejects_other_remote_before_fetch(self):
        self.git('remote', 'add', 'origin', str(self.root / 'wrong.git'))
        # The wrapper runs from the temporary parent, but reads no nested repo.
        result = subprocess.run(['bash', str(PUSH), '--check-only'], cwd=self.repo, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Alexayy/Love2Gathering', result.stderr)

    def test_push_wrapper_rejects_second_push_destination_before_fetch(self):
        self.git('remote', 'add', 'origin', 'https://github.com/Alexayy/Love2Gathering.git')
        self.git('config', '--add', 'remote.origin.pushurl', 'https://github.com/Alexayy/Love2Gathering.git')
        self.git('config', '--add', 'remote.origin.pushurl', 'https://github.com/magefree/mage.git')
        result = subprocess.run(['bash', str(PUSH), '--check-only'], cwd=self.repo, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('multiple push destinations', result.stderr)

    def test_replace_ref_cannot_hide_changed_head_tree(self):
        self.git('update-index', '--cacheinfo', '160000,' + OTHER + ',engine/mage')
        self.git('commit', '-qm', 'unwanted raw engine change')
        bad = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('replace', bad, self.base)
        result = subprocess.run(['python3', str(CHECK), '--head', bad], cwd=self.repo, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('XMage gitlink', result.stderr)


if __name__ == '__main__':
    unittest.main()
