#!/usr/bin/env python3
"""Prepare the complete MTGJSON deck/product snapshot as compact local JSONL.

Explicit network acquisition only. Downloads are resumable and SHA256 checked;
tar members are read one at a time and never extracted to arbitrary paths.
Original user decks, card metadata and application saves are not opened.
"""
import argparse
from collections import Counter
import datetime
import gzip
import hashlib
from http.client import HTTPException
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tarfile
import time
from urllib.request import Request, urlopen
from urllib.error import HTTPError

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'service'))
from precons import normalize_deck

BASE='https://mtgjson.com/api/v5/'
HEADERS={'User-Agent':'Love2Gathering/1.0 (local preconstructed deck catalog)','Accept':'application/json,application/octet-stream,text/plain'}
LICENSE='''MIT License

Copyright (c) 2018 - Present, Zach Halpern

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Source: https://mtgjson.com/license/ (reviewed 2026-11-14).
Magic: The Gathering and its card/game content remain the property of Wizards
of the Coast. This application is not affiliated with Wizards or MTGJSON.
'''


def digest(path):
    value=hashlib.sha256()
    with path.open('rb')as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):value.update(block)
    return value.hexdigest()


def small_file(cache,filename,maximum,offline=False):
    target=cache/filename
    if offline:
        if not target.is_file()or target.stat().st_size>maximum:raise ValueError('Offline metadata is missing or oversized: '+filename)
        return target.read_bytes()
    with urlopen(Request(BASE+filename,headers=HEADERS),timeout=25)as response:
        data=response.read(maximum+1)
    if len(data)>maximum:raise ValueError('Metadata exceeds bound: '+filename)
    part=target.with_name(target.name+'.new');part.write_bytes(data);os.replace(part,target)
    return data


def archive_file(cache,expected,offline=False):
    target=cache/'AllDeckFiles.tar.xz';partial=target.with_name(target.name+'.part')
    if target.is_file()and digest(target)==expected:return target
    if partial.is_file()and digest(partial)==expected:os.replace(partial,target);return target
    if offline:raise ValueError('Offline archive is missing or fails its official SHA256 checksum')
    maximum=512*1024*1024
    for attempt in range(3):
        offset=partial.stat().st_size if partial.exists()else 0
        headers=dict(HEADERS)
        if offset:headers['Range']='bytes='+str(offset)+'-'
        try:
            with urlopen(Request(BASE+'AllDeckFiles.tar.xz',headers=headers),timeout=35)as response:
                resumed=response.status==206 and response.headers.get('Content-Range','').startswith('bytes '+str(offset)+'-')
                if response.status==206 and not resumed:raise ValueError('Invalid resumed archive Content-Range')
                mode='ab'if resumed else'wb';size=offset if resumed else 0
                with partial.open(mode)as output:
                    while True:
                        block=response.read(512*1024)
                        if not block:break
                        size+=len(block)
                        if size>maximum:raise ValueError('Archive exceeds the 512 MiB compressed bound')
                        output.write(block)
            if digest(partial)!=expected:
                partial.unlink()
                if attempt==2:raise ValueError('Downloaded archive failed official SHA256 verification')
                print('Archive checksum changed or partial bytes were stale; retrying a complete transfer',flush=True)
                continue
            os.replace(partial,target);return target
        except (OSError,HTTPException)as exc:
            # A cached partial can belong to an older upstream build. A 416
            # cannot be resumed, so reset only our temporary download bytes.
            if isinstance(exc,HTTPError)and exc.code==416:partial.unlink(missing_ok=True)
            if attempt==2:raise
            print('Archive transfer interrupted; resuming committed bytes:',type(exc).__name__,flush=True);time.sleep(.25*(attempt+1))
    raise ValueError('Could not acquire the archive')


def prepare(archive,deck_list,set_list,output,checksum):
    index={entry['fileName']:entry for entry in deck_list['data']}
    if len(index)!=len(deck_list['data']):raise ValueError('DeckList contains duplicate filenames')
    set_names={entry['code']:entry['name']for entry in set_list['data']}
    output.parent.mkdir(parents=True,exist_ok=True)
    records=output.with_name(output.name+'.records.part');temporary=output.with_name(output.name+'.part')
    seen=set();types=Counter();categories=Counter();formats=Counter();official=0;dates=[];examples={};expanded=0
    try:
        with records.open('w',encoding='utf-8')as destination,tarfile.open(archive,mode='r|xz')as source:
            for member in source:
                if not member.isfile():continue
                if not 0<member.size<=32*1024*1024:raise ValueError('Deck member exceeds 32 MiB: '+member.name)
                expanded+=member.size
                if expanded>2*1024*1024*1024:raise ValueError('Archive exceeds the 2 GiB expanded streaming bound')
                filename=PurePosixPath(member.name).name
                if not filename.endswith('.json'):continue
                stem=filename[:-5]
                if stem not in index:continue
                if stem in seen:raise ValueError('Duplicate archive deck filename: '+stem)
                wrapped=json.loads(source.extractfile(member).read(member.size+1))
                if wrapped.get('meta',{}).get('date')!=deck_list['meta']['date']:raise ValueError('Archive and DeckList snapshot dates differ; rerun to fetch a coherent build')
                deck=normalize_deck(wrapped['data'],stem,set_names,deck_list['meta']);seen.add(stem)
                types[deck['productType']]+=1;categories[deck['category']]+=1;formats[deck['historicalFormat']]+=1
                official+=bool(deck['source']['officialOriginal'])
                if deck.get('releaseDate'):dates.append(deck['releaseDate'])
                if deck['name']in('Feline Ferocity','Calling All Angels'):examples[deck['name']]={key:deck[key]for key in('id','format','historicalFormat','productType','category','set','expansion','faceCommander','counts','source')}
                destination.write(json.dumps(deck,ensure_ascii=False,separators=(',',':'))+'\n')
                if len(seen)%300==0:print('Prepared',len(seen),'/',len(index),'records',flush=True)
        missing=sorted(set(index)-seen)
        if missing:raise ValueError('Archive is incomplete for DeckList: '+str(len(missing))+' missing, first '+missing[0])
        manifest={'schema':1,'provider':'MTGJSON','snapshotDate':deck_list['meta']['date'],'version':deck_list['meta']['version'],
                  'preparedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':'https://mtgjson.com/api/v5/AllDeckFiles.tar.xz',
                  'index':'https://mtgjson.com/api/v5/DeckList.json','sets':'https://mtgjson.com/api/v5/SetList.json','sha256':checksum,
                  'license':'MIT','licenseURL':'https://mtgjson.com/license/','totalSourceRecords':len(seen),'categories':dict(categories),'productTypes':dict(types),
                  'historicalFormats':dict(formats),'earliestRelease':min(dates)if dates else None,'latestRelease':max(dates)if dates else None,
                  'originalWizardsSourceCount':official,'examples':examples,'coverage':'Every record in this MTGJSON DeckList snapshot; not a guarantee that upstream contains every historical Wizards product. Non-deck collections are retained for audit but excluded from default browsing.'}
        with gzip.open(temporary,'wt',encoding='utf-8',compresslevel=9)as destination,records.open('r',encoding='utf-8')as source:
            destination.write(json.dumps({'_meta':manifest},ensure_ascii=False,separators=(',',':'))+'\n')
            shutil.copyfileobj(source,destination,length=512*1024)
        os.replace(temporary,output)
        (output.parent/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
        (output.parent/'LICENSE-MTGJSON.txt').write_text(LICENSE)
        return manifest
    finally:
        records.unlink(missing_ok=True);temporary.unlink(missing_ok=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache',type=Path,default=ROOT/'.runtime/precons')
    parser.add_argument('--output',type=Path,default=ROOT/'decks/preconstructed/catalog.jsonl.gz')
    parser.add_argument('--offline',action='store_true',help='Use previously acquired archive/checksum/index only; no network')
    args=parser.parse_args();args.cache.mkdir(parents=True,exist_ok=True)
    expected=small_file(args.cache,'AllDeckFiles.tar.xz.sha256',256,args.offline).decode().strip()
    if not re.fullmatch('[0-9a-fA-F]{64}',expected):raise ValueError('Invalid official archive checksum')
    deck_list=json.loads(small_file(args.cache,'DeckList.json',8*1024*1024,args.offline))
    set_list=json.loads(small_file(args.cache,'SetList.json',32*1024*1024,args.offline))
    archive=archive_file(args.cache,expected,args.offline)
    result=prepare(archive,deck_list,set_list,args.output,expected)
    print(json.dumps({'output':str(args.output),'records':result['totalSourceRecords'],'categories':result['categories'],'snapshot':result['snapshotDate'],'compressedBytes':args.output.stat().st_size,'examples':result['examples']},ensure_ascii=False),flush=True)
    return 0


if __name__=='__main__':raise SystemExit(main())
