"""Storage process guards and kernel locks; also runnable by embedded Windows Python."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import time
import unittest

SERVICE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE))
import filelocks
from processes import process_alive, process_started_ms
from storage_locations import _atomic_json


class PlatformStorageTests(unittest.TestCase):
    def test_shared_readers_and_exclusive_writer_are_real_process_locks(self):
        code = "import sys,os;sys.path.insert(0,sys.argv[1]);import filelocks;f=open(sys.argv[2],'a+b');filelocks.flock(f,int(sys.argv[3])|filelocks.LOCK_NB)"
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'lock'
            with path.open('a+b') as stream:
                filelocks.flock(stream, filelocks.LOCK_SH)
                reader = subprocess.run([sys.executable, '-c', code, str(SERVICE), str(path), str(filelocks.LOCK_SH)], capture_output=True)
                writer = subprocess.run([sys.executable, '-c', code, str(SERVICE), str(path), str(filelocks.LOCK_EX)], capture_output=True)
                self.assertEqual(reader.returncode, 0, reader.stderr)
                self.assertNotEqual(writer.returncode, 0)
                self.assertIn(b'BlockingIOError', writer.stderr)
                filelocks.flock(stream, filelocks.LOCK_UN)
                writer = subprocess.run([sys.executable, '-c', code, str(SERVICE), str(path), str(filelocks.LOCK_EX)], capture_output=True)
                self.assertEqual(writer.returncode, 0, writer.stderr)

    def test_owner_probes_do_not_terminate_a_live_process(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(30)'])
        try:
            for _ in range(3):
                self.assertTrue(process_alive(child.pid))
                stamp = process_started_ms(child.pid)
                self.assertIsNotNone(stamp)
                self.assertLess(abs(stamp - time.time() * 1000), 10000)
                self.assertIsNone(child.poll())
        finally:
            child.terminate();child.wait(timeout=5)
        self.assertFalse(process_alive(child.pid))

    def test_atomic_bootstrap_json_survives_replacement(self):
        import json
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'config/paths.json'
            _atomic_json(path, {'name': 'First'})
            _atomic_json(path, {'name': 'Second – saved'})
            self.assertEqual(json.loads(path.read_text(encoding='utf-8')), {'name': 'Second – saved'})
            self.assertEqual(sorted(p.name for p in path.parent.iterdir()), ['paths.json'])


if __name__ == '__main__':
    unittest.main()
