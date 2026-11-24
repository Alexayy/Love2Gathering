#!/usr/bin/env python3
"""Renderer selection and failure boundaries; real SDL/Wine acceptance is separate."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('windows_graphics', ROOT / 'runtime/windows_graphics.py')
graphics = importlib.util.module_from_spec(spec); spec.loader.exec_module(graphics)


class RendererTests(unittest.TestCase):
    def test_supported_native_driver_is_kept(self):
        original = {'EXISTING': 'keep'}
        result, info = graphics.select_renderer(Path('/missing'), original,
                                                probe=lambda env: {'available': True, 'renderer': 'Intel integrated'})
        self.assertEqual(result, original); self.assertIsNot(result, original)
        self.assertEqual(info['mode'], 'native')

    def test_opengl11_vm_uses_private_software_driver(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); dll = root / 'runtime/mesa/opengl32.dll'
            dll.parent.mkdir(parents=True); dll.write_bytes(b'fixture')
            environments = []
            def probe(env):
                environments.append(env.copy())
                return {'available': False, 'error': 'Microsoft OpenGL 1.1'} if len(environments) == 1 else {'available': True, 'renderer': 'llvmpipe'}
            original = {'PATH': 'unchanged'}
            selected, info = graphics.select_renderer(root, original, probe=probe)
            self.assertEqual(info['mode'], 'software'); self.assertIn('1.1', info['nativeError'])
            self.assertEqual(selected['SDL_OPENGL_LIBRARY'], str(dll)); self.assertEqual(selected['GALLIUM_DRIVER'], 'llvmpipe')
            self.assertEqual(original, {'PATH': 'unchanged'})

    def test_forced_native_does_not_silently_change_renderer(self):
        with self.assertRaisesRegex(RuntimeError, '--graphics software'):
            graphics.select_renderer(Path('/missing'), {}, 'native', probe=lambda env: {'available': False})

    def test_missing_or_broken_fallback_has_actionable_error(self):
        with self.assertRaisesRegex(RuntimeError, 'software OpenGL driver is missing'):
            graphics.select_renderer(Path('/missing'), {}, 'software')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); dll = root / 'runtime/mesa/opengl32.dll'
            dll.parent.mkdir(parents=True); dll.write_bytes(b'fixture')
            with self.assertRaisesRegex(RuntimeError, 'Neither the Windows driver'):
                graphics.select_renderer(root, {}, 'software', probe=lambda env: {'available': False, 'error': 'failed context'})

    def test_faulty_driver_timeout_is_contained(self):
        with patch.object(graphics.subprocess, 'run', side_effect=subprocess.TimeoutExpired('probe', 20)):
            self.assertFalse(graphics.run_probe(Path('/fixture'), {})['available'])
        with patch.object(graphics.subprocess, 'run', return_value=subprocess.CompletedProcess([], 3, '', '')):
            self.assertFalse(graphics.run_probe(Path('/fixture'), {})['available'])


if __name__ == '__main__': unittest.main()
