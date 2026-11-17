"""CI metadata transfer and dynamic package-version contracts without user writes."""
import argparse
import gzip
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec);spec.loader.exec_module(value)
    return value


metadata = module('ci_metadata', ROOT / 'scripts/ci/prepare-metadata.py')
packager = module('ci_packager', ROOT / 'packaging/build.py')


class Response(io.BytesIO):
    pass


CARD = {'object': 'card', 'id': 'first-printing', 'name': 'Card Name',
        'image_uris': {'normal': 'https://cards.scryfall.io/not-fetched.jpg'}}


class Fetcher:
    def __init__(self, records, *, array=False, descriptor=None):
        self.urls=[]
        self.descriptor=descriptor or {'object':'bulk_data','type':'default_cards','id':'provider',
            'updated_at':'2026-11-15T00:00:00Z',
            ('download_uri'if array else'jsonl_download_uri'):'https://data.scryfall.io/default-cards.jsonl.gz'}
        self.data=json.dumps(records).encode()if array else gzip.compress(('\n'.join(json.dumps(x)for x in records)+'\n').encode())
    def open(self,url,*args,**kwargs):
        self.urls.append(url)
        return Response(json.dumps(self.descriptor).encode()if len(self.urls)==1 else self.data)
    def image(self,*args):
        raise AssertionError('A metadata build must never request card images')


class MetadataTests(unittest.TestCase):
    def test_gzip_jsonl_provenance_and_verified_cache_use_no_image_or_store(self):
        with tempfile.TemporaryDirectory()as tmp:
            target=Path(tmp)/'cards.jsonl';fetcher=Fetcher([CARD])
            with patch.object(metadata.DOWNLOADER,'Storage',side_effect=AssertionError('No application storage in CI')):
                report=metadata.prepare(target,min_cards=1,fetcher=fetcher)
                self.assertEqual(report['cards'],1);self.assertTrue(report['metadataOnly'])
                self.assertEqual(report['sha256'],metadata.file_digest(target))
                again=metadata.prepare(target,min_cards=1,fetcher=fetcher)
                self.assertTrue(again['reused']);self.assertEqual(len(fetcher.urls),2)
            self.assertEqual(json.loads(target.read_text()),CARD)
            self.assertFalse(list(Path(tmp).rglob('*.sqlite')))

    def test_older_json_array_is_streamed_into_jsonl(self):
        with tempfile.TemporaryDirectory()as tmp:
            target=Path(tmp)/'cards.jsonl'
            result=metadata.prepare(target,min_cards=2,fetcher=Fetcher([CARD,dict(CARD,id='second')],array=True))
            self.assertEqual(result['cards'],2);self.assertEqual(len(target.read_text().splitlines()),2)

    def test_bad_cache_and_existing_original_are_not_overwritten(self):
        with tempfile.TemporaryDirectory()as tmp:
            target=Path(tmp)/'cards.jsonl';target.write_text('original source')
            with self.assertRaises(ValueError):metadata.prepare(target,min_cards=1,fetcher=Fetcher([CARD]))
            self.assertEqual(target.read_text(),'original source')
            target.unlink();metadata.prepare(target,min_cards=1,fetcher=Fetcher([CARD]))
            target.write_text('changed source')
            with self.assertRaises(ValueError):metadata.prepare(target,min_cards=1,fetcher=Fetcher([CARD]))
            self.assertEqual(target.read_text(),'changed source')

    def test_small_invalid_and_over_bound_sources_never_commit_partial_output(self):
        for values,options in [([CARD],{'min_cards':2}),([dict(CARD,object='ruling')],{'min_cards':1}),
                               ([CARD],{'min_cards':1,'max_bytes':8}),
                               ([CARD,dict(CARD,id='second')],{'min_cards':1,'max_cards':1})]:
            with self.subTest(options=options),tempfile.TemporaryDirectory()as tmp:
                target=Path(tmp)/'cards.jsonl'
                with self.assertRaises(ValueError):metadata.prepare(target,fetcher=Fetcher(values),**options)
                self.assertFalse(target.exists());self.assertFalse(list(Path(tmp).glob('*.part')))

    def test_foreign_download_url_and_wrong_descriptor_are_rejected(self):
        for descriptor in [{'type':'default_cards','download_uri':'https://untrusted.example/cards.json'},
                           {'type':'rulings','download_uri':'https://data.scryfall.io/cards.json'}]:
            with tempfile.TemporaryDirectory()as tmp:
                target=Path(tmp)/'cards.jsonl';fetcher=Fetcher([CARD],descriptor=descriptor)
                with self.assertRaises(ValueError):metadata.prepare(target,min_cards=1,fetcher=fetcher)
                self.assertFalse(target.exists());self.assertEqual(len(fetcher.urls),1)

    def test_report_cannot_replace_metadata_itself(self):
        with tempfile.TemporaryDirectory()as tmp:
            target=Path(tmp)/'cards.jsonl'
            with self.assertRaises(ValueError):metadata.prepare(target,target,min_cards=1,fetcher=Fetcher([CARD]))
            self.assertFalse(target.exists())


class VersionTests(unittest.TestCase):
    def test_common_version_is_valid_for_all_targets_and_rejects_spec_injection(self):
        for value in ['2026.11.15','2026.11.15.42']:
            self.assertEqual(packager.release_version(value),value)
        for value in ['2026.13.01','2026.02.31','v1','2026.11.15\n%post','2026.11.15;cmd','../../release']:
            with self.assertRaises(argparse.ArgumentTypeError):packager.release_version(value)

    def test_reused_payloads_cannot_be_relabelled_as_a_different_version(self):
        with tempfile.TemporaryDirectory()as tmp:
            root=Path(tmp);common=root/'stage/common/Love2Gathering';common.mkdir(parents=True)
            (common/'release.json').write_text(json.dumps({'version':'2026.11.15.1'}))
            result=subprocess.run([sys.executable,str(ROOT/'packaging/build.py'),'--format','common','--reuse-common',
                                   '--output',str(root),'--version','2026.11.15.2'],capture_output=True,text=True)
            self.assertEqual(result.returncode,2);self.assertIn('payload version differs',result.stderr)
            self.assertEqual(json.loads((common/'release.json').read_text())['version'],'2026.11.15.1')

    def test_reused_linux_identity_must_match_common_even_when_version_matches(self):
        from contextlib import redirect_stdout,redirect_stderr
        with tempfile.TemporaryDirectory()as tmp:
            root=Path(tmp);output=root/'dist';version='2026.11.15.42'
            common=output/'stage/common/Love2Gathering';linux=output/'stage/linux/Love2Gathering'
            for path in (common,linux):path.mkdir(parents=True)
            identity={'version':version,'sourceRevision':'a'*40,'engineRevision':'b'*40,
                      'channel':'stable','branch':'master','tag':'v'+version}
            (common/'release.json').write_text(json.dumps(identity))
            args=['build.py','--format','deb','--output',str(output),'--reuse-common','--reuse-linux',
                  '--version',version,'--channel','stable','--branch','master','--tag','v'+version]
            for key,wrong in [('channel','development'),('sourceRevision','c'*40),('tag','DEV-'+version+'-1-'+'a'*12),
                              ('engineRevision','c'*40),('branch','development'),('version','2026.11.15.41')]:
                with self.subTest(key=key):
                    (linux/'release.json').write_text(json.dumps(identity|{key:wrong}))
                    with patch.object(packager,'ROOT',root),patch.object(packager,'VERSION',packager.VERSION), \
                         patch.object(sys,'argv',args),patch.object(packager,'build_deb')as build, \
                         redirect_stdout(io.StringIO()),redirect_stderr(io.StringIO())as error,self.assertRaises(SystemExit):
                        packager.main()
                    self.assertIn('Linux payload release identity differs',error.getvalue());build.assert_not_called()
            (linux/'release.json').write_text(json.dumps(identity))
            with patch.object(packager,'ROOT',root),patch.object(packager,'VERSION',packager.VERSION), \
                 patch.object(sys,'argv',args),patch.object(packager,'build_deb',return_value=output/'fixture.deb')as build, \
                 redirect_stdout(io.StringIO()):packager.main()
            build.assert_called_once_with(output,linux)
            self.assertEqual(json.loads((linux/'release.json').read_text()),identity)

    def test_explicit_java21_precedes_another_system_jlink(self):
        with tempfile.TemporaryDirectory()as tmp:
            root=Path(tmp);wanted=root/'jdk21';other=root/'jdk17'
            for folder,version in [(wanted,'21.0.13'),(other,'17.0.1')]:
                (folder/'bin').mkdir(parents=True);(folder/'bin/jlink').write_text('fixture')
                (folder/'release').write_text('JAVA_VERSION="'+version+'"\n')
            with patch.dict(os.environ,{'JAVA_HOME':str(wanted)}),patch.object(packager.shutil,'which',return_value=str(other/'bin/jlink')):
                self.assertEqual(packager.java_home(),wanted)

    @unittest.skipUnless(shutil.which('dpkg-deb'), 'DEB builder is not available on this test platform')
    def test_selected_ci_version_reaches_real_deb_metadata_and_filename(self):
        # Minimal synthetic payload: this checks the real package header and
        # version contract, not an installed application or native gameplay.
        from contextlib import redirect_stdout
        with tempfile.TemporaryDirectory()as tmp:
            root=Path(tmp);output=root/'dist';version='2026.11.15.42'
            common=output/'stage/common/Love2Gathering';payload=output/'stage/linux/Love2Gathering'
            for folder in (common,payload):
                folder.mkdir(parents=True);(folder/'release.json').write_text(json.dumps({'version':version}))
            (payload/'share/icons').mkdir(parents=True);(payload/'share/icons/love2gathering.png').write_bytes(b'header-only fixture icon')
            (payload/'love2gathering').write_text('#!/bin/sh\nexit 0\n');(payload/'love2gathering').chmod(0o755)
            args=['build.py','--format','deb','--output',str(output),'--reuse-common','--reuse-linux','--version',version]
            with patch.object(packager,'ROOT',root),patch.object(packager,'VERSION',packager.VERSION),patch.object(sys,'argv',args),redirect_stdout(io.StringIO()):
                packager.main()
            package=output/('Love2Gathering-'+version+'-linux-amd64.deb')
            self.assertTrue(package.is_file())
            actual=subprocess.check_output(['dpkg-deb','--field',str(package),'Version'],text=True).strip()
            self.assertEqual(actual,version+'-1')


class PayloadTests(unittest.TestCase):
    def test_common_payload_includes_exact_product_catalog_and_seals_it(self):
        # Build the real common payload from an isolated minimal source tree,
        # rather than testing only the suffix predicate that previously lost it.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'source'; root.mkdir()
            for name in ('main.lua', 'conf.lua', 'app/model.lua', 'service/precons.py',
                         'decks/starter.json', 'decks/preconstructed/README.md',
                         'decks/preconstructed/LICENSE-MTGJSON.txt', 'decks/preconstructed/manifest.json',
                         'bridge/target/xmage-bridge-1.0.0.jar', 'bridge/card-map.json',
                         'scripts/download-card-images.py', 'scripts/starter-image-pack.py', 'service/image_packs.py', 'assets/card-art/full-art-basics.json',
                         'assets/icons/thb.png', 'engine/mage/LICENSE.txt', 'README.md',
                         'LICENSE', 'CREDITS.md', 'THIRD_PARTY_NOTICES.md',
                         'licenses/Roboto-Apache-2.0.txt',
                         'assets/fonts/Beleren2016-Bold.ttf', 'assets/fonts/LICENSE-DejaVu.txt',
                         'assets/card-backs/classic-magic.jpg', 'assets/card-backs/mystic-eye.png',
                         'assets/ASSET_GUIDE.md', 'assets/card-backs/README.md', 'packaging/runtime/launcher.py'):
                path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('fixture')
            catalog = root / 'decks/preconstructed/catalog.jsonl.gz'
            catalog.write_bytes(gzip.compress(b'{"_meta":{"version":1}}\n{"id":"precon:fixture"}\n'))
            for name in ('decks/preconstructed/unrelated.jsonl.gz', 'decks/backup.tar.gz',
                         'decks/app.sqlite', 'decks/user.log', 'decks/build_library.py'):
                (root / name).write_bytes(b'must not ship')
            source = root / 'cards.jsonl'; source.write_text(json.dumps(CARD) + '\n')
            with zipfile.ZipFile(root / 'bridge/target/xmage-bridge-1.0.0.jar', 'w') as archive:
                archive.writestr('love2gathering/EngineBridge.class', b'fixture bytecode')
            slab=root/'lib/Slab/init.lua';slab.parent.mkdir(parents=True);slab.write_text('--[[\nMIT License\nRetained fixture copyright\n--]]\nreturn{}')
            jar=root/'bridge/target/lib/fixture.jar';jar.parent.mkdir(parents=True)
            with zipfile.ZipFile(jar,'w')as archive:
                archive.writestr('META-INF/jsoup/LICENSE','nested MIT fixture')
                archive.writestr('com/j256/ormlite/core/LICENSE.txt','nested ISC fixture')
                archive.writestr('META-INF/maven/org.xerial/sqlite-jdbc/LICENSE.zentus','native dependency fixture')
            selected=[root/name for name in ('assets/fonts/Beleren2016-Bold.ttf','assets/fonts/LICENSE-DejaVu.txt','assets/card-backs/classic-magic.jpg','assets/card-backs/mystic-eye.png')]
            from contextlib import redirect_stdout
            with patch.object(packager, 'ROOT', root), patch.object(packager, 'asset_paths', return_value=selected), \
                    patch.object(packager.subprocess, 'check_output', return_value='a' * 40), redirect_stdout(io.StringIO()):
                payload = packager.common_payload(Path(tmp) / 'dist', source,channel='stable',branch='master',tag='v'+packager.VERSION)
            self.assertTrue((payload / 'scripts/starter-image-pack.py').is_file())
            self.assertTrue((payload / 'service/image_packs.py').is_file())
            copied = payload / 'decks/preconstructed/catalog.jsonl.gz'
            self.assertEqual(copied.read_bytes(), catalog.read_bytes())
            manifest = json.loads((payload / 'payload-manifest.json').read_text())
            # seal() includes all delivered runtime sources in its integrity map.
            import hashlib
            self.assertEqual(manifest['files']['decks/preconstructed/catalog.jsonl.gz'],
                             hashlib.sha256(catalog.read_bytes()).hexdigest())
            for name in ('starter.json', 'preconstructed/README.md',
                         'preconstructed/LICENSE-MTGJSON.txt', 'preconstructed/manifest.json'):
                self.assertTrue((payload / 'decks' / name).is_file())
            for name in ('preconstructed/unrelated.jsonl.gz', 'backup.tar.gz', 'app.sqlite', 'user.log', 'build_library.py'):
                self.assertFalse((payload / 'decks' / name).exists())
            with zipfile.ZipFile(payload/'app.love')as archive:
                info=json.loads(archive.read('build-info.json'))
                self.assertEqual(info['version'],packager.VERSION);self.assertEqual(info['channel'],'stable')
                self.assertEqual(info['revision'],'a'*40);self.assertEqual(info['tag'],'v'+packager.VERSION)
                self.assertEqual(info['branch'],'master');self.assertTrue(info['builtAtUTC'].endswith('Z'))
                for name in packager.PROJECT_NOTICES:
                    self.assertEqual(archive.read(name),(root/name).read_bytes())
                    self.assertEqual((payload/'licenses'/name).read_bytes(),(root/name).read_bytes())
                self.assertEqual(archive.read('licenses/Roboto-Apache-2.0.txt'),b'fixture')
                self.assertEqual((payload/'licenses/Roboto-Apache-2.0.txt').read_bytes(),b'fixture')
                # User explicitly retained these local assets in installer copies.
                for path in selected:self.assertEqual(archive.read(path.relative_to(root).as_posix()),path.read_bytes())
            self.assertIn('Retained fixture copyright',(payload/'licenses/Slab-MIT.txt').read_text())
            self.assertEqual((payload/'licenses/assets/fonts/LICENSE-DejaVu.txt').read_text(),'fixture')
            notices='\n'.join(path.read_text()for path in(payload/'licenses').glob('fixture-*'))
            self.assertIn('nested MIT fixture',notices);self.assertIn('nested ISC fixture',notices)
            self.assertIn('native dependency fixture',(payload/'licenses/fixture-META-INF-maven-org.xerial-sqlite-jdbc-LICENSE.zentus').read_text())

    def test_release_payload_cannot_claim_a_foreign_branch_or_tag(self):
        with tempfile.TemporaryDirectory()as tmp,patch.object(packager.subprocess,'check_output',return_value='a'*40):
            for channel,branch,tag in [('stable','development','v'+packager.VERSION),('development','master','DEV-'+packager.VERSION+'-1-'+'a'*12),('source','development','v'+packager.VERSION)]:
                with self.subTest(channel=channel),self.assertRaises(SystemExit):
                    packager.common_payload(Path(tmp),Path(tmp)/'unused.jsonl',channel=channel,branch=branch,tag=tag)
            self.assertFalse((Path(tmp)/'stage').exists())

    def test_missing_corrupt_or_symlinked_product_source_fails_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'decks'; source.mkdir()
            catalog = source / 'preconstructed/catalog.jsonl.gz'; catalog.parent.mkdir()
            target = Path(tmp) / 'payload'
            with self.assertRaisesRegex(SystemExit, 'Required bundled'):
                packager.copy_deck_payload(source, target)
            for value in (b'', b'not gzip', gzip.compress(b'contents')[:-4], gzip.compress(b'')):
                with self.subTest(value=value):
                    catalog.write_bytes(value)
                    with self.assertRaises(SystemExit):
                        packager.copy_deck_payload(source, target)
                    self.assertFalse(target.exists())
            external = Path(tmp) / 'external.gz'; external.write_bytes(gzip.compress(b'contents'))
            catalog.unlink(); catalog.symlink_to(external)
            with self.assertRaisesRegex(SystemExit, 'Required bundled'):
                packager.copy_deck_payload(source, target)


if __name__=='__main__':unittest.main()
