"""Explicit credential persistence in owned temporary paths; no real tokens."""
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import update_credentials as credentials

TOKEN = 'ghp_' + 'test_only_credential_1234567890'
SECOND = 'github_pat_' + 'another_test_credential_1234567890'


class CredentialTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.path = self.root / 'updater-credentials/github-token'
        self.store = credentials.UpdateCredentials(self.path)

    def tearDown(self):
        self.tmp.cleanup()

    def test_default_path_uses_existing_config_resolver_without_reading_real_credentials(self):
        with patch.object(credentials, 'config_file', return_value=self.root / 'config/storage-paths.json'):
            store = credentials.UpdateCredentials()
        self.assertEqual(store.path, self.root / 'config/updater-credentials/github-token')
        self.assertEqual(store.get(), '')
        self.assertFalse(store.path.parent.exists())

    def test_missing_read_and_forget_create_no_files(self):
        self.assertEqual(self.store.get(), '')
        self.store.set('')
        self.assertFalse(self.path.parent.exists())

    def test_save_restart_replace_and_forget_preserve_other_config(self):
        other = self.root / 'storage-paths.json'; other.write_text('preserve existing settings')
        self.store.set(TOKEN)
        self.assertEqual(self.store.get(), TOKEN)
        self.assertEqual(credentials.UpdateCredentials(self.path).get(), TOKEN)
        self.store.set(SECOND)
        self.assertEqual(self.store.get(), SECOND)
        self.assertNotIn(TOKEN.encode(), self.path.read_bytes())
        self.store.set('')
        self.assertFalse(self.path.exists()); self.assertEqual(self.store.get(), '')
        self.assertEqual(other.read_text(), 'preserve existing settings')
        self.assertFalse(list(self.root.rglob('*.sqlite')))
        self.assertEqual(list(self.path.parent.iterdir()), [])

    @unittest.skipIf(os.name == 'nt', 'Unix ownership/mode contract')
    def test_private_directory_and_file_modes_ignore_permissive_umask(self):
        old = os.umask(0)
        try: self.store.set(TOKEN)
        finally: os.umask(old)
        self.assertEqual(stat.S_IMODE(self.path.parent.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual(self.path.stat().st_uid, os.getuid())

    def test_validation_is_bounded_and_never_repeats_secret_input(self):
        for value in (None, 1, [], 'short', 'a' * 513, TOKEN + '\n', TOKEN + ' ', TOKEN + '\x00', TOKEN + ':secret'):
            with self.subTest(kind=type(value).__name__):
                with self.assertRaises(ValueError) as caught: self.store.set(value)
                self.assertNotIn(TOKEN, str(caught.exception))
        self.assertFalse(self.path.parent.exists())
        self.assertEqual(credentials.validate_token(TOKEN), TOKEN)
        self.assertEqual(credentials.validate_token(''), '')

    def test_injected_protection_persists_ciphertext_and_can_be_reopened(self):
        def protect(data): return b'fixture-ciphertext:' + bytes(value ^ 0x55 for value in data)
        def unprotect(data):
            self.assertTrue(data.startswith(b'fixture-ciphertext:'))
            return bytes(value ^ 0x55 for value in data[len(b'fixture-ciphertext:'):])
        store = credentials.UpdateCredentials(self.path, protect=protect, unprotect=unprotect)
        store.set(TOKEN)
        self.assertNotIn(TOKEN.encode(), self.path.read_bytes())
        again = credentials.UpdateCredentials(self.path, protect=protect, unprotect=unprotect)
        self.assertEqual(again.get(), TOKEN)
        again.set(''); self.assertFalse(self.path.exists())

    def test_protection_failure_is_redacted_and_preserves_previous_credential(self):
        self.store.set(TOKEN); previous = self.path.read_bytes()
        def fail(_): raise RuntimeError('Backend included ' + SECOND)
        store = credentials.UpdateCredentials(self.path, protect=fail, unprotect=lambda value: value)
        with self.assertRaises(ValueError) as caught: store.set(SECOND)
        self.assertNotIn(SECOND, str(caught.exception))
        self.assertEqual(self.path.read_bytes(), previous)
        self.assertFalse(list(self.path.parent.glob('.github-token-*')))

    def test_unlock_failure_is_redacted(self):
        store = credentials.UpdateCredentials(self.path, protect=lambda data: b'cipher', unprotect=lambda data: (_ for _ in ()).throw(ValueError(TOKEN)))
        store.set(TOKEN)
        with self.assertRaises(ValueError) as caught: store.get()
        self.assertNotIn(TOKEN, str(caught.exception))

    def test_partial_write_failure_keeps_old_bytes_and_removes_temporary(self):
        self.store.set(TOKEN); previous = self.path.read_bytes()
        with patch.object(credentials.os, 'fsync', side_effect=OSError('fixture fsync failure')):
            with self.assertRaises(OSError): self.store.set(SECOND)
        self.assertEqual(self.path.read_bytes(), previous)
        self.assertFalse(list(self.path.parent.glob('.github-token-*')))

    def test_symlinked_directory_and_file_are_never_followed_or_removed(self):
        foreign = self.root / 'foreign'; foreign.mkdir(mode=0o700)
        self.path.parent.symlink_to(foreign, target_is_directory=True)
        for operation in (self.store.get, lambda: self.store.set(TOKEN), lambda: self.store.set('')):
            with self.assertRaises(ValueError): operation()
        self.path.parent.unlink(); self.path.parent.mkdir(mode=0o700)
        target = foreign / 'secret'; target.write_bytes(b'unrelated file'); target.chmod(0o600)
        self.path.symlink_to(target)
        for operation in (self.store.get, lambda: self.store.set(TOKEN), lambda: self.store.set('')):
            with self.assertRaises(ValueError): operation()
        self.assertEqual(target.read_bytes(), b'unrelated file')
        self.assertTrue(self.path.is_symlink())

    def test_directory_nonregular_oversized_and_foreign_file_are_preserved(self):
        self.path.parent.mkdir(mode=0o700); self.path.mkdir()
        with self.assertRaises(ValueError): self.store.get()
        self.path.rmdir(); self.path.write_bytes(b'x' * (credentials.MAX_STORED + 1)); self.path.chmod(0o600)
        with self.assertRaises(ValueError): self.store.set(TOKEN)
        self.assertEqual(self.path.stat().st_size, credentials.MAX_STORED + 1)
        self.path.write_bytes(b'not an updater credential')
        with self.assertRaises(ValueError): self.store.set('')
        self.assertEqual(self.path.read_bytes(), b'not an updater credential')

    @unittest.skipIf(os.name == 'nt', 'Unix special-file contract')
    def test_named_pipe_is_rejected_without_blocking_or_removal(self):
        self.path.parent.mkdir(mode=0o700); os.mkfifo(self.path, mode=0o600)
        with self.assertRaises(ValueError): self.store.get()
        with self.assertRaises(ValueError): self.store.set('')
        self.assertTrue(stat.S_ISFIFO(self.path.lstat().st_mode))

    @unittest.skipIf(os.name == 'nt', 'Unix ownership/mode contract')
    def test_insecure_existing_directory_file_and_hardlinks_are_not_imported(self):
        self.store.set(TOKEN); self.path.chmod(0o644)
        with self.assertRaises(ValueError): self.store.get()
        self.path.chmod(0o600); self.path.parent.chmod(0o755)
        with self.assertRaises(ValueError): self.store.get()
        self.path.parent.chmod(0o700)
        alias = self.root / 'hardlink'; os.link(self.path, alias)
        with self.assertRaises(ValueError): self.store.get()
        self.assertTrue(alias.exists())

    def test_atomic_save_rejects_a_changed_current_credential(self):
        self.store.set(TOKEN)
        original = self.store._directory
        def change(create=False):
            result = original(create)
            if create: self.path.write_bytes(credentials.PLAIN + SECOND.encode())
            return result
        with patch.object(self.store, '_directory', side_effect=change):
            with self.assertRaisesRegex(ValueError, 'changed'): self.store.set('ghp_' + 'third_test_credential_1234567890')
        self.assertEqual(self.store.get(), SECOND)
        self.assertFalse(list(self.path.parent.glob('.github-token-*')))

    @unittest.skipUnless(os.name == 'nt', 'Requires actual Windows current-user DPAPI')
    def test_native_windows_dpapi_round_trip_does_not_persist_plaintext(self):
        self.store.set(TOKEN)
        self.assertTrue(self.path.read_bytes().startswith(credentials.PROTECTED))
        self.assertNotIn(TOKEN.encode(), self.path.read_bytes())
        self.assertEqual(credentials.UpdateCredentials(self.path).get(), TOKEN)


if __name__ == '__main__': unittest.main()
