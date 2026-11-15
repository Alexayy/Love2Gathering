#!/usr/bin/env python3
"""Build and verify a separate optional Starter ZIP in disposable CI storage.

Metadata must already match prepare-metadata.py provenance. Only the explicit
Starter builder acquires images; no user SQL database or cache is accepted.
Nothing is installed, added to an installer, uploaded or published here.
"""
from __future__ import annotations
import argparse
from collections import Counter
from datetime import datetime,timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'service'))
from catalog import Catalog
from image_packs import EmptyImages,MAX_MANIFEST,starter_plan,validate_archive

SPEC=importlib.util.spec_from_file_location('starter_ci_metadata',Path(__file__).with_name('prepare-metadata.py'))
METADATA=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(METADATA)


def starters(directory):
    directory=Path(directory);library=directory/'library.json'
    if library.is_symlink()or not library.is_file()or library.stat().st_size>MAX_MANIFEST:
        raise ValueError('A bounded tracked Starter library is required')
    labels=json.loads(library.read_text(encoding='utf-8'))
    if not isinstance(labels,list)or len(labels)!=20:raise ValueError('The optional pack requires exactly twenty Starter lists')
    seen=set();formats=Counter();result=[]
    for label in labels:
        if not isinstance(label,dict)or not isinstance(label.get('id'),str)or not re.fullmatch(r'[A-Za-z0-9_-]{1,100}',label['id'])or label['id']in seen:
            raise ValueError('Starter IDs must be unique bounded filenames')
        path=directory/(label['id']+'.json')
        if path.is_symlink()or not path.is_file()or path.stat().st_size>MAX_MANIFEST:raise ValueError('A selected Starter list is unavailable')
        deck=json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(deck,dict)or deck.get('id')!=label['id']or deck.get('name')!=label.get('name')or deck.get('format')!=label.get('format')or not isinstance(deck.get('main'),list):
            raise ValueError('Starter source does not match its tracked library label')
        if not isinstance(deck['name'],str)or not 1<=len(deck['name'])<=300:raise ValueError('Starter names must be bounded')
        seen.add(label['id']);formats[deck['format']]+=1;result.append({'id':deck['id'],'name':deck['name']})
    if formats!=Counter({'Modern':5,'Standard':5,'Pioneer':5,'Commander':5}):raise ValueError('Select all five Starters in each of the four supported formats')
    return result


def identity(image):return tuple(image[key]for key in('printingId','oracleId','face','kind','source','name'))


def verify_pack(path,catalog,decks,selected,full_size):
    with Path(path).open('rb')as source:manifest,manifest_sha=validate_archive(source,catalog)
    if manifest['complete']is not True or manifest['missing']or not manifest['images']:
        raise ValueError('Only a complete, nonempty Starter image pack can become a CI artifact')
    expected_labels={item['id']:item['name']for item in selected}
    actual_labels={item['id']:item['name']for item in manifest['decks']}
    if len(manifest['decks'])!=20 or actual_labels!=expected_labels:raise ValueError('The ZIP does not contain the exact twenty selected Starters')
    expected=starter_plan(catalog,EmptyImages(),decks,list(expected_labels),full_size)
    required={identity(item)for item in expected['images']+expected['missing']}
    if {identity(item)for item in manifest['images']}!=required:raise ValueError('The ZIP omits or adds an exact Starter image')
    return manifest,manifest_sha


def publish_new(staged):
    created=[]
    try:
        for source,destination in staged:
            os.link(source,destination)
            info=destination.stat();created.append((destination,(info.st_dev,info.st_ino)))
    except BaseException:
        for path,expected in reversed(created):
            try:
                info=path.stat()
                if (info.st_dev,info.st_ino)==expected:path.unlink()
            except FileNotFoundError:pass
        raise


def prepare(source,metadata_report,work,output,report=None,*,decks=ROOT/'decks',bulk_type='default_cards',full_size='normal',min_cards=10000,runner=subprocess.run):
    source=Path(source).absolute();metadata_report=Path(metadata_report).absolute()
    output=Path(output).absolute();report=Path(report).absolute()if report else output.with_suffix('.provenance.json')
    sums=output.parent/'SHA256SUMS';work=Path(work).absolute()
    if output.suffix!='.zip'or report.parent!=output.parent:raise ValueError('Use a ZIP and separate provenance in one optional-artifact directory')
    destinations=(output,report,sums)
    if len(set(destinations))!=3 or any(path.exists()or path.is_symlink()for path in destinations):raise ValueError('Choose new optional artifact paths; existing files are preserved')
    if any(path.resolve()in(source.resolve(),metadata_report.resolve())for path in destinations):raise ValueError('Artifact outputs must not replace source metadata or provenance')
    selected=starters(decks)
    metadata=METADATA.validate_cache(source,metadata_report,bulk_type,min_cards)
    work.mkdir(parents=True,exist_ok=True);output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='starter-images-',dir=work)as temporary:
        owned=Path(temporary);catalog=Catalog(source,owned/'catalog.sqlite');catalog.ensure()
        if catalog.status()['state']!='ready':raise ValueError('Disposable card index failed: '+str(catalog.status().get('error')))
        target=owned/'starter-images.zip'
        command=[sys.executable,str(ROOT/'scripts/starter-image-pack.py'),'build','--catalog',str(catalog.database),'--decks',str(Path(decks).absolute()),'--full-size',full_size,'--output',str(target)]
        for deck in selected:command+=['--deck',deck['id']]
        # These are child-only paths. The image builder receives no application
        # SQL source, even if the calling workstation has saved location vars.
        env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',HOME=str(owned/'home'),LOVE2GATHERING_DATA_DIR=str(owned/'data'),LOVE2GATHERING_CACHE_DIR=str(owned/'cache'),LOVE2GATHERING_CONFIG_DIR=str(owned/'config'),LOVE2GATHERING_STORAGE_RESOLVED='',XDG_DATA_HOME=str(owned/'xdg/data'),XDG_CACHE_HOME=str(owned/'xdg/cache'),XDG_CONFIG_HOME=str(owned/'xdg/config'))
        runner(command,check=True,cwd=ROOT,env=env,timeout=45*60)
        manifest,manifest_sha=verify_pack(target,catalog,decks,selected,full_size)
        # A long image build must still describe the verified source it used.
        if METADATA.validate_cache(source,metadata_report,bulk_type,min_cards)['sha256']!=metadata['sha256']:
            raise ValueError('Metadata changed while the optional pack was built')
        result={'version':1,'optional':True,'installed':False,'complete':True,'decks':selected,'images':len(manifest['images']),'imageBytes':sum(item['size']for item in manifest['images']),'fullSize':full_size,'archive':output.name,'archiveBytes':target.stat().st_size,'archiveSha256':METADATA.file_digest(target),'manifestSha256':manifest_sha,'sourceCachesOpened':False,'metadata':{key:metadata.get(key)for key in('bulkType','cards','bytes','sha256','providerId','sourceUpdatedAt','sourceUrl')},'preparedAt':datetime.now(timezone.utc).isoformat()}
        with tempfile.TemporaryDirectory(prefix='.starter-images-stage-',dir=output.parent)as stage:
            stage=Path(stage);zip_stage=stage/output.name;report_stage=stage/report.name;sums_stage=stage/sums.name
            shutil.copyfile(target,zip_stage);report_stage.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
            sums_stage.write_text(result['archiveSha256']+'  '+output.name+'\n'+METADATA.file_digest(report_stage)+'  '+report.name+'\n',encoding='utf-8')
            publish_new(((zip_stage,output),(report_stage,report),(sums_stage,sums)))
    return result


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    for flag in('source','metadata-report','work','output'):parser.add_argument('--'+flag,type=Path,required=True)
    parser.add_argument('--report',type=Path);parser.add_argument('--bulk-type',choices=('default_cards','all_cards'),default='default_cards');parser.add_argument('--full-size',choices=('normal','large'),default='normal')
    args=parser.parse_args(argv)
    try:result=prepare(args.source,args.metadata_report,args.work,args.output,args.report,bulk_type=args.bulk_type,full_size=args.full_size)
    except(OSError,ValueError,KeyError,subprocess.SubprocessError)as exc:print(str(exc),file=sys.stderr);return 1
    print(json.dumps(result,indent=2));return 0


if __name__=='__main__':raise SystemExit(main())
