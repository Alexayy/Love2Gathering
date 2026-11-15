"""Shipping-runtime preflight and nightly release metadata; no system mutation."""
from pathlib import Path
import importlib.util
import json
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('flatpak_build',HERE/'build.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)


class FlatpakBuildTests(unittest.TestCase):
    def test_preflight_runs_platform_rather_than_sdk(self):
        replies=['LOVE 11.5 (Mysterious Mysteries)',json.dumps({'python':'3.13.11','sqlite':'3.50.4','ssl':'OpenSSL 3','pillow':'13.0.0','jpeg':True}),'openjdk 21.0.13 LTS\nOpenJDK Runtime','a'*64,'b'*64]
        with patch.object(builder.subprocess,'check_output',side_effect=replies)as capture:
            info=builder.runtime_preflight(Path('/tmp/build'))
        calls=[call.args[0]for call in capture.call_args_list]
        for command in calls[:3]:self.assertEqual(command[:3],['flatpak','build','--runtime'])
        self.assertIn('import ctypes,json,sqlite3,ssl,sys',calls[1][-1])
        self.assertEqual(info['commits'],{'platform':'a'*64,'sdk':'b'*64})
        self.assertEqual(info['python'],'3.13.11')
        self.assertEqual(info['pillow'],'13.0.0');self.assertTrue(info['jpeg'])
        self.assertIn('features.check_codec("jpg")',calls[1][-1])
        self.assertIn('--env=PYTHONPATH=/app/share/Love2Gathering/runtime/python-packages',calls[1])

    def test_pillow_import_without_a_verified_jpeg_codec_is_not_a_runtime_pass(self):
        for result in ({'pillow':'13.0.0'},{'pillow':'13.0.0','jpeg':False},{}):
            with self.subTest(result=result),patch.object(builder.subprocess,'check_output',side_effect=['LOVE 11.5',json.dumps(result)]):
                with self.assertRaisesRegex(ValueError,'Pillow JPEG'):builder.runtime_preflight(Path('/tmp/build'))

    def test_missing_platform_dependency_aborts_before_publication(self):
        failure=subprocess.CalledProcessError(1,['flatpak','build','--runtime'])
        with patch.object(builder.subprocess,'check_output',side_effect=failure):
            with self.assertRaises(subprocess.CalledProcessError):builder.runtime_preflight(Path('/tmp/build'))

    def test_unexpected_java_or_runtime_commit_is_not_accepted(self):
        for java,commit in [('openjdk 17.0.9','a'*64),('openjdk 21.0.13','not-a-commit')]:
            with self.subTest(java=java,commit=commit):
                with patch.object(builder.subprocess,'check_output',side_effect=['LOVE 11.5','{}',java,commit,'b'*64]):
                    with self.assertRaises(ValueError):builder.runtime_preflight(Path('/tmp/build'))

    def test_nightly_version_updates_metainfo_without_rewriting_history(self):
        with tempfile.TemporaryDirectory()as temp:
            path=Path(temp)/'app.xml';builder.write_metainfo(HERE/(builder.APP_ID+'.metainfo.xml'),path,'2026.11.15.42')
            releases=ET.parse(path).getroot().find('releases')
            self.assertEqual(releases[0].attrib,{'version':'2026.11.15.42','date':'2026-11-15'})
            self.assertTrue(any(item.get('version')=='2026.11.14'for item in releases))
            builder.write_metainfo(path,Path(temp)/'again.xml','2026.11.15.42')
            self.assertEqual(len(ET.parse(Path(temp)/'again.xml').getroot().find('releases')),len(releases))

    def test_setup_plan_is_read_only_and_regular_desktop_execution_is_refused(self):
        setup=HERE.parents[1]/'scripts/ci/flatpak-setup.sh'
        plan=subprocess.run(['bash',str(setup),'--dry-run'],capture_output=True,text=True,check=True)
        self.assertIn('org.freedesktop.Platform//25.08',plan.stdout)
        self.assertIn('FLATPAK_USER_DIR=',plan.stdout)
        refused=subprocess.run(['bash',str(setup)],env={'PATH':'/usr/bin:/bin'},capture_output=True,text=True)
        self.assertEqual(refused.returncode,2)
        self.assertIn('restricted to an ephemeral',refused.stderr)


if __name__=='__main__':unittest.main()
