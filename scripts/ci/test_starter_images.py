"""Optional CI image packs: local fixtures only, no acquisition or user SQL."""
from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import yaml

ROOT=Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('prepare_starter_images',Path(__file__).with_name('prepare-starter-images.py'))
CI=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(CI)
from image_packs import EmptyImages,build_starter_pack

JPEG=b'\xff\xd8synthetic-complete-CI-image-fixture\xff\xd9'


class StarterImagesTest(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory(prefix='love2gathering-ci-starters-');self.root=Path(self.temporary.name)
        self.source=self.root/'cards.jsonl';self.metadata=self.root/'cards.provenance.json';self.work=self.root/'work';self.output=self.root/'optional/Starters.zip'
        raw={'object':'card','id':'fixture','oracle_id':'oracle','name':'Fixture card','lang':'en','type_line':'Creature','set':'tst','set_name':'Fixture edition','image_uris':{kind:'https://cards.scryfall.io/'+kind+'/fixture.jpg'for kind in('normal','art_crop')}}
        self.source.write_text(json.dumps(raw)+'\n')
        self.metadata.write_text(json.dumps({'version':1,'bulkType':'default_cards','metadataOnly':True,'cards':1,'bytes':self.source.stat().st_size,'sha256':CI.METADATA.file_digest(self.source),'providerId':'fixture','sourceUpdatedAt':'2026-11-15T00:00:00Z','sourceUrl':'https://data.scryfall.io/fixture.jsonl.gz'}))
        self.decks=self.root/'decks';self.decks.mkdir();self.labels=json.loads((ROOT/'decks/library.json').read_text())
        (self.decks/'library.json').write_text(json.dumps(self.labels))
        for item in self.labels:
            (self.decks/(item['id']+'.json')).write_text(json.dumps({**item,'main':[{'name':'Fixture card','count':60}],'commander':[],'sideboard':[]}))
        # A valid looking extra file must never leak into the twenty selections.
        (self.decks/'unlisted.json').write_text(json.dumps({'id':'unlisted','name':'Not a Starter','main':[{'name':'Not in metadata','count':1}]}))
        self.commands=[];self.urls=[];self.mutate=None

    def tearDown(self):self.temporary.cleanup()

    def runner(self,command,**options):
        self.commands.append((command,options));self.assertNotIn('--database',command);self.assertNotIn('--cache',command)
        self.assertTrue(options['check']);self.assertEqual(options['timeout'],45*60)
        for key in('HOME','LOVE2GATHERING_DATA_DIR','LOVE2GATHERING_CACHE_DIR','XDG_DATA_HOME','XDG_CACHE_HOME'):
            self.assertTrue(Path(options['env'][key]).is_relative_to(self.work))
        arg=lambda flag:command[command.index(flag)+1]
        selected=[command[index+1]for index,flag in enumerate(command)if flag=='--deck']
        self.assertEqual(selected,[item['id']for item in self.labels])
        catalog=CI.Catalog(self.source,Path(arg('--catalog')));outer=self
        class Fetcher:
            def image(self,url):outer.urls.append(url);return JPEG
            def close(self):pass
        archive=Path(arg('--output'))
        build_starter_pack(catalog,EmptyImages(),arg('--decks'),archive,selected,arg('--full-size'),fetcher=Fetcher())
        if self.mutate:
            with zipfile.ZipFile(archive)as source:files={item.filename:source.read(item.filename)for item in source.infolist()}
            manifest=json.loads(files['manifest.json']);self.mutate(manifest,files);files['manifest.json']=json.dumps(manifest).encode()
            with zipfile.ZipFile(archive,'w')as target:
                for path,data in files.items():target.writestr(path,data)
        return subprocess.CompletedProcess(command,0)

    def prepare(self,**kwargs):
        return CI.prepare(self.source,self.metadata,self.work,self.output,decks=self.decks,min_cards=1,runner=self.runner,**kwargs)

    def assert_no_output(self):
        self.assertFalse(self.output.exists());self.assertFalse(self.output.with_suffix('.provenance.json').exists());self.assertFalse((self.output.parent/'SHA256SUMS').exists())
        self.assertEqual(list(self.work.iterdir())if self.work.exists()else[],[])

    def test_complete_twenty_starter_pack_checksums_and_no_source_storage(self):
        before={path:path.read_bytes()for path in[self.source,self.metadata,*self.decks.glob('*.json')]}
        with patch.object(CI.METADATA.DOWNLOADER,'Storage',side_effect=AssertionError('CI must not construct user storage')),patch('image_packs.ReadonlyImages',side_effect=AssertionError('CI must not open a source SQL cache')):
            result=self.prepare()
        self.assertTrue(result['complete']);self.assertTrue(result['optional']);self.assertFalse(result['installed']);self.assertFalse(result['sourceCachesOpened'])
        self.assertEqual((len(result['decks']),result['images']),(20,2));self.assertEqual(len(self.urls),2)
        with zipfile.ZipFile(self.output)as archive:
            manifest=json.loads(archive.read('manifest.json'))
            self.assertEqual({item['id']for item in manifest['decks']},{item['id']for item in self.labels})
            self.assertEqual(set(archive.namelist()),{'manifest.json','full-cards/fixture-0-normal.jpg','art-crops/fixture-0-art_crop.jpg'})
            for image in manifest['images']:self.assertEqual(hashlib.sha256(archive.read(image['path'])).hexdigest(),image['sha256'])
        for line in(self.output.parent/'SHA256SUMS').read_text().splitlines():
            digest,name=line.split('  ',1);self.assertEqual(CI.METADATA.file_digest(self.output.parent/name),digest)
        self.assertEqual(CI.METADATA.file_digest(self.output),result['archiveSha256'])
        self.assertEqual(list(self.work.iterdir()),[]);self.assertEqual(list(self.root.rglob('*.sqlite')),[])
        for path,data in before.items():self.assertEqual(path.read_bytes(),data)

    def test_incomplete_or_silently_omitted_images_never_become_artifacts(self):
        def missing(manifest,files):
            image=manifest['images'].pop();files.pop(image['path'])
            item={key:value for key,value in image.items()if key not in('path','size','sha256')};item['reason']='Synthetic missing source'
            manifest.update(complete=False,missing=[item])
        def omitted(manifest,files):files.pop(manifest['images'].pop()['path'])
        for mutator in(missing,omitted):
            with self.subTest(mutator=mutator.__name__):
                self.mutate=mutator
                with self.assertRaisesRegex(ValueError,'complete|omits'):self.prepare()
                self.assert_no_output()

    def test_wrong_or_duplicate_deck_labels_are_rejected_after_build(self):
        for duplicate in(False,True):
            with self.subTest(duplicate=duplicate):
                def mutate(manifest,files):manifest['decks'][0]=deepcopy(manifest['decks'][1])if duplicate else{'id':'wrong','name':'Wrong Starter'}
                self.mutate=mutate
                with self.assertRaisesRegex(ValueError,'twenty'):self.prepare()
                self.assert_no_output()

    def test_checksum_damage_is_rejected_before_artifact_publication(self):
        def damage(manifest,files):files[manifest['images'][0]['path']]=b'\xff\xd8changed\xff\xd9'
        self.mutate=damage
        with self.assertRaisesRegex(ValueError,'size|SHA256'):self.prepare()
        self.assert_no_output()

    def test_existing_outputs_are_preserved_without_running_acquisition(self):
        self.output.parent.mkdir()
        for path in(self.output,self.output.with_suffix('.provenance.json'),self.output.parent/'SHA256SUMS'):
            with self.subTest(path=path.name):
                path.write_bytes(b'preserve existing output')
                with self.assertRaisesRegex(ValueError,'existing'):self.prepare()
                self.assertEqual(path.read_bytes(),b'preserve existing output');path.unlink()
        self.assertEqual(self.commands,[]);self.assertEqual(self.urls,[])

    def test_metadata_digest_and_bulk_type_are_checked_before_any_build(self):
        original=self.source.read_bytes();self.source.write_bytes(original+b'changed')
        with self.assertRaisesRegex(ValueError,'provenance'):self.prepare()
        self.source.write_bytes(original)
        with self.assertRaisesRegex(ValueError,'provenance'):self.prepare(bulk_type='all_cards')
        self.assertEqual(self.commands,[]);self.assert_no_output()

    def test_missing_duplicate_or_wrong_format_library_is_rejected(self):
        for kind in('missing','duplicate','format'):
            labels=deepcopy(self.labels)
            if kind=='missing':labels.pop()
            elif kind=='duplicate':labels[0]=deepcopy(labels[1])
            else:labels[0]['format']='Pioneer'
            (self.decks/'library.json').write_text(json.dumps(labels))
            with self.subTest(kind=kind),self.assertRaises(ValueError):self.prepare()
        self.assertEqual(self.commands,[]);self.assert_no_output()

    def test_child_failure_cleans_owned_index_and_does_not_publish(self):
        with patch.object(CI.subprocess,'run',side_effect=AssertionError('No unexpected subprocess')):
            def refused(*args,**kwargs):raise subprocess.CalledProcessError(1,args[0])
            with self.assertRaises(subprocess.CalledProcessError):
                CI.prepare(self.source,self.metadata,self.work,self.output,decks=self.decks,min_cards=1,runner=refused)
        self.assert_no_output()

    def test_atomic_publish_does_not_overwrite_or_leave_partial_files(self):
        stage=self.root/'stage';stage.mkdir();first=stage/'first';second=stage/'second';first.write_bytes(b'one');second.write_bytes(b'two')
        target=self.root/'first.out';existing=self.root/'second.out';existing.write_bytes(b'original')
        with self.assertRaises(FileExistsError):CI.publish_new(((first,target),(second,existing)))
        self.assertFalse(target.exists());self.assertEqual(existing.read_bytes(),b'original')


class StarterWorkflowTest(unittest.TestCase):
    def setUp(self):
        self.workflow=yaml.load((ROOT/'.github/workflows/starter-images.yml').read_text(),Loader=yaml.BaseLoader)
        self.job=self.workflow['jobs']['build-starter-images'];self.steps=self.job['steps']

    def test_manual_development_repo_only_and_readonly_permissions(self):
        self.assertEqual(set(self.workflow['on']),{'workflow_dispatch'})
        for guard in("github.event_name == 'workflow_dispatch'","github.repository == 'Alexayy/Love2Gathering'","github.ref == 'refs/heads/development'"):self.assertIn(guard,self.job['if'])
        self.assertEqual(self.workflow['permissions'],{'contents':'read'});self.assertNotIn('permissions',self.job)
        self.assertEqual(self.workflow['defaults']['run']['shell'],'bash')

    def test_no_submodule_initialization_publish_token_or_installer_mutation(self):
        checkout=self.steps[0];self.assertEqual(checkout['with']['submodules'],'false');self.assertEqual(checkout['with']['persist-credentials'],'false')
        guards=[index for index,step in enumerate(self.steps)if 'scripts/check-submodule-pin.py'in step.get('run','')]
        acquire=next(index for index,step in enumerate(self.steps)if 'scripts/ci/prepare-metadata.py'in step.get('run',''))
        build=next(index for index,step in enumerate(self.steps)if 'scripts/ci/prepare-starter-images.py'in step.get('run',''))
        self.assertLess(guards[0],acquire);self.assertGreater(guards[-1],build)
        for step in self.steps:
            command=step.get('run','')
            self.assertNotRegex(command,r'git\s+(?:-C\s+engine/mage\s+)?(?:push|commit|add|submodule)\b')
            self.assertNotIn('publish-release',command);self.assertNotIn('packaging/',command)
            self.assertFalse({'GH_TOKEN','GITHUB_TOKEN'}&set(step.get('env',{})))
            if 'uses'in step:self.assertRegex(step['uses'],r'^actions/[a-z-]+@[a-f0-9]{40}$')

    def test_metadata_contract_and_separate_success_gated_optional_artifacts(self):
        acquire=next(step for step in self.steps if 'scripts/ci/prepare-metadata.py'in step.get('run',''))
        self.assertIn('--bulk-type default_cards',acquire['run'])
        pack=next(step for step in self.steps if 'scripts/ci/prepare-starter-images.py'in step.get('run',''))
        self.assertIn('--bulk-type default_cards',pack['run']);self.assertNotIn('--database',pack['run']);self.assertNotIn('--cache',pack['run'])
        uploads=[step for step in self.steps if 'upload-artifact'in step.get('uses','')]
        artifact=uploads[0];self.assertNotIn('if',artifact);self.assertEqual(artifact['with']['if-no-files-found'],'error')
        paths=artifact['with']['path'].splitlines();self.assertEqual(len(paths),4)
        self.assertTrue(all(path.startswith('dist/optional-images/')or path=='build/ci/cards.provenance.json'for path in paths))
        for path in paths:self.assertNotRegex(path,r'\.sqlite|\.exe|\.deb|\.rpm|\.flatpak|cards\.jsonl$')
        self.assertEqual(uploads[1]['if'],'always()');self.assertEqual(uploads[1]['with']['path'],'build/ci/starter-image-reports/')


if __name__=='__main__':unittest.main()
