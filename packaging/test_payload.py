#!/usr/bin/env python3
"""Installed-payload readability regressions, including private build outputs."""
import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('payload_builder', ROOT / 'build.py')
builder = importlib.util.module_from_spec(spec); spec.loader.exec_module(builder)


class PayloadTests(unittest.TestCase):
    def test_private_build_jars_become_readable_system_payloads(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); source = base / 'build'; (source / 'lib').mkdir(parents=True)
            for name in ('xmage-bridge-1.0.0.jar', 'lib/native.jar'):
                jar = source / name
                with zipfile.ZipFile(jar, 'w') as archive:
                    archive.writestr('love2gathering/EngineBridge.class', b'fixture')
                jar.chmod(0o600)
            destination = base / 'payload/bridge/target'
            previous = os.umask(0o077)
            try:
                builder.copy_bridge(source, destination)
                command = base / 'payload/launcher'; command.write_text('#!/bin/sh\n'); command.chmod(0o700)
                builder.seal(base / 'payload')
            finally:
                os.umask(previous)
            for item in (base / 'payload').rglob('*'):
                if item.is_dir(): self.assertEqual(stat.S_IMODE(item.stat().st_mode), 0o755)
                elif item == command: self.assertEqual(stat.S_IMODE(item.stat().st_mode), 0o755)
                else: self.assertEqual(stat.S_IMODE(item.stat().st_mode), 0o644)
            self.assertEqual(stat.S_IMODE(source.joinpath('xmage-bridge-1.0.0.jar').stat().st_mode), 0o600)

    def test_missing_entrypoint_and_dependencies_stop_package_construction(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); source = base / 'build'; source.mkdir()
            jar = source / 'xmage-bridge-1.0.0.jar'
            with zipfile.ZipFile(jar, 'w') as archive: archive.writestr('wrong.class', b'fixture')
            with self.assertRaisesRegex(SystemExit, 'lacks EngineBridge'):
                builder.copy_bridge(source, base / 'payload')
            with zipfile.ZipFile(jar, 'w') as archive: archive.writestr('love2gathering/EngineBridge.class', b'fixture')
            with self.assertRaisesRegex(SystemExit, 'dependency directory is empty'):
                builder.copy_bridge(source, base / 'payload')


if __name__ == '__main__': unittest.main()
