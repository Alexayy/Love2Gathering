"""Private ABI-pinned image codecs; no host package installation or network."""
import builtins
from contextlib import redirect_stderr
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from python_dependencies import bundle_pillow

HERE=Path(__file__).resolve().parent


class Response(io.BytesIO):
    def geturl(self):return 'https://files.pythonhosted.org/fixture.whl'


class PythonDependencyTests(unittest.TestCase):
    def wheel(self, root, platform='windows-cp313', extra=None, license=True):
        filename='pillow-13.0.0-cp313-cp313-'+('win_amd64'if platform=='windows-cp313'else'manylinux_2_27_x86_64.manylinux_2_28_x86_64')+'.whl'
        data=io.BytesIO()
        with zipfile.ZipFile(data,'w')as archive:
            archive.writestr('PIL/__init__.py','__version__="13.0.0"')
            archive.writestr('PIL/Image.py','# isolated packaging fixture')
            archive.writestr('PIL/_imaging.cp313-win_amd64.pyd'if platform=='windows-cp313'else'PIL/_imaging.cpython-313-x86_64-linux-gnu.so',b'native-code-fixture')
            if license:archive.writestr('pillow-13.0.0.dist-info/licenses/LICENSE','Fixture redistribution notice')
            if extra:extra(archive)
        body=data.getvalue();spec={'name':'Pillow','version':'13.0.0','filename':filename,'url':'https://files.pythonhosted.org/'+filename,'sha256':hashlib.sha256(body).hexdigest()}
        return spec,body

    def test_both_interpreters_receive_private_core_and_original_notices(self):
        for platform in('windows-cp313','flatpak-cp313'):
            with self.subTest(platform=platform),tempfile.TemporaryDirectory()as temp:
                root=Path(temp);spec,data=self.wheel(root,platform);calls=[]
                def fetch(*args,**kwargs):calls.append(args);return Response(data)
                result=bundle_pillow(platform,root/'private-packages',root/'downloads',spec=spec,opener=fetch)
                self.assertTrue(result['includesNativeCode']and result['includesLicenses'])
                self.assertTrue((root/'private-packages/PIL/Image.py').is_file())
                self.assertTrue((root/'private-packages/pillow-13.0.0.dist-info/licenses/LICENSE').is_file())
                bundle_pillow(platform,root/'second-stage',root/'downloads',spec=spec,opener=fetch)
                self.assertEqual(len(calls),1,'A verified wheel cache must not repeat downloads')

    def test_hash_mismatch_and_foreign_redirect_never_extract(self):
        with tempfile.TemporaryDirectory()as temp:
            root=Path(temp);spec,data=self.wheel(root)
            with self.assertRaisesRegex(ValueError,'checksum'):
                bundle_pillow('windows-cp313',root/'stage',root/'cache',spec=dict(spec,sha256='0'*64),opener=lambda *a,**k:Response(data))
            class Foreign(Response):
                def geturl(self):return 'https://foreign.example/wheel'
            with self.assertRaisesRegex(ValueError,'redirected'):
                bundle_pillow('windows-cp313',root/'stage',root/'cache',spec=spec,opener=lambda *a,**k:Foreign(data))
            self.assertFalse((root/'stage').exists());self.assertEqual(list((root/'cache').glob('*.part')),[])

    def test_unsafe_members_and_missing_licenses_are_rejected_before_extraction(self):
        def symlink(archive):
            item=zipfile.ZipInfo('PIL/escape');item.external_attr=(stat.S_IFLNK|0o777)<<16;archive.writestr(item,'/etc/passwd')
        for extra,license in((lambda a:a.writestr('../escape','no'),True),(symlink,True),(None,False)):
            with self.subTest(extra=extra,license=license),tempfile.TemporaryDirectory()as temp:
                root=Path(temp);spec,data=self.wheel(root,extra=extra,license=license)
                with self.assertRaises(ValueError):bundle_pillow('windows-cp313',root/'stage',root/'cache',spec=spec,opener=lambda *a,**k:Response(data))
                self.assertFalse((root/'stage').exists());self.assertFalse((root/'escape').exists())

    def test_existing_stage_and_wrong_platform_are_not_modified(self):
        with tempfile.TemporaryDirectory()as temp:
            root=Path(temp);spec,data=self.wheel(root);stage=root/'stage';stage.mkdir();(stage/'user.txt').write_text('preserve')
            with self.assertRaises(ValueError):bundle_pillow('windows-cp313',stage,root/'cache',spec=spec)
            with self.assertRaises(ValueError):bundle_pillow('flatpak-cp313',root/'new',root/'cache',spec=spec)
            self.assertEqual((stage/'user.txt').read_text(),'preserve')

    def test_installed_launcher_explains_compatible_original_image_fallback(self):
        spec=importlib.util.spec_from_file_location('private_launcher_dependency_test',HERE/'runtime/launcher.py')
        launcher=importlib.util.module_from_spec(spec);spec.loader.exec_module(launcher)
        original=builtins.__import__
        def absent(name,*args,**kwargs):
            if name=='PIL':raise ImportError('Pillow intentionally absent')
            return original(name,*args,**kwargs)
        output=io.StringIO()
        with patch('builtins.__import__',side_effect=absent),redirect_stderr(output):
            self.assertFalse(launcher.image_dependency()['available'])
            with self.assertRaises(RuntimeError):launcher.image_dependency(required=True)
        self.assertIn('original card images remain available',output.getvalue())

    def test_committed_wheel_locks_keep_the_exact_published_abi_and_hashes(self):
        locks=json.loads((HERE/'python-wheels.lock.json').read_text())
        self.assertEqual(set(locks),{'windows-cp313','flatpak-cp313'})
        for platform,spec in locks.items():
            self.assertEqual(spec['version'],'13.0.0');self.assertEqual(len(spec['sha256']),64)
            self.assertIn('cp313-cp313-',spec['filename']);self.assertTrue(spec['url'].startswith('https://files.pythonhosted.org/'))


if __name__=='__main__':unittest.main()
