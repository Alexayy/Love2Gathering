#!/usr/bin/env python3
"""Bounded real catalog/library smoke; requires explicit temporary catalog storage.

Reads the original JSONL/index, creates/deletes only its own deck, and optionally
downloads exactly two image kinds for one token into the isolated catalog cache.
The offline gate runs its own ephemeral HTTP server and separate temporary DB.
"""
import argparse
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import sys
import tempfile
import threading
import urllib.error
import urllib.parse
import urllib.request
import uuid
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'service'))
from catalog import Catalog
from storage import Storage
from server import make_handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', required=True)
    parser.add_argument('--catalog-database', type=Path, required=True)
    parser.add_argument('--archidekt-url', default='https://archidekt.com/decks/27859380')
    parser.add_argument('--output', type=Path, default=ROOT / 'tests/library-live-report.json')
    args = parser.parse_args();checks=[];identifier='library-acceptance-'+uuid.uuid4().hex
    report={'passed':False,'scope':'Actual full local metadata and HTTP import/token/history APIs, real public Archidekt JSON, two genuine token JPEG kinds, then network-disabled HTTP reads from a separate SQLite cache. Native history consumes completed engine recordings; no synthetic winner submission.'}
    parsed=urllib.parse.urlsplit(args.url)
    assert parsed.hostname in ('127.0.0.1','localhost') and parsed.port and parsed.port>=17400,'Use an explicitly isolated catalog'
    def call(path,body=None,method=None,binary=False,base=None):
        req=urllib.request.Request((base or args.url)+path,data=None if body is None else json.dumps(body).encode(),method=method,headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(req,timeout=25)as response:return response.read()if binary else json.load(response)
    def check(ok,label):
        assert ok,label;checks.append(label);print('LIBRARY LIVE PASS',label,flush=True)
    try:
        health=call('/health');data=Path(health['storage']['dataDirectory']).resolve()
        assert Path('/tmp')in data.parents,'Acceptance must not write existing user storage'
        check(health['ready']and health['apiVersion']>=5,'Full streaming metadata index and new library API are ready in isolated storage')
        previews=call('/imports/preview',{'text':'4 Lightning Bolt (M10) 146\n56 Forest','format':'Modern'})
        check(previews['validation']['playable']and not previews['saved'],'Actual metadata validates a 60-card text preview without saving')
        check(previews['printingSelections'][0]['set']=='m10','Text preview preserves requested set and collector metadata')
        imported=call('/imports/preview',{'url':args.archidekt_url,'format':'Commander'})
        check(imported['source']['provider']=='Archidekt'and sum(e['count']for z in('main','commander')for e in imported['deck'][z])==100,'Official public Archidekt deck JSON imports all 100 cards and commander zones')
        check(bool(imported['printingSelections']),'Actual public export preserves individual set/collector selections')
        original=call('/decks/commander-krenko-goblins');own=dict(original,id=identifier,name='Library acceptance owned deck')
        saved=call('/decks',own)
        check(saved['main']==original['main']and saved['commander']==original['commander'],'Own temporary deck save preserves bundled deck composition')
        items=call('/tokens?deckId='+identifier+'&q=Goblin&limit=60')['items']
        check(bool(items)and all('Token'in i['type_line']for i in items),'Deck all_parts relationships return real local Goblin token printings')
        item=next(i for i in items if i.get('power')=='1'and i.get('toughness')=='1'and i.get('colors')==['R'])
        prefs={'mode':'randomSelected','selected':[item['tokenImageId']]}
        check(call('/decks/'+identifier+'/token-art',prefs,'PUT')==prefs,'Per-deck token selection persists through its own validated preference route')
        resolved=call('/tokens/resolve',{'deckId':identifier,'token':{'name':'Goblin','power':'1','toughness':'1','colors':['R']},'seed':'actual-native-token-instance'})['card']
        check(resolved['printing_id']==item['printing_id']and resolved['requested_face']==item['requested_face'],'Runtime token resolution returns exactly the selected real printing and face')
        blobs={}
        for kind in('normal','art_crop'):
            path='/gallery/art/'+item['printing_id']+'?face='+str(item['requested_face'])+'&kind='+kind+'&network=1'
            blobs[kind]=call(path,binary=True)
            check(blobs[kind].startswith(b'\xff\xd8')and len(blobs[kind])>1000,'Real '+kind+' token JPEG loads through the catalog and authoritative SQLite cache')
        with tempfile.TemporaryDirectory(prefix='love2gathering-library-offline-')as temp:
            store=Storage(Path(temp)/'saves',Path(temp)/'bundled')
            for kind,blob in blobs.items():store.save_art(f"{item['printing_id']}-{item['requested_face']}-{kind}.jpg",blob,{'printingId':item['printing_id'],'oracleId':item['oracle_id'],'face':item['requested_face'],'kind':kind})
            catalog=Catalog(Path(health['catalogSource']),args.catalog_database);catalog.ensure();assert catalog.status()['state']=='ready'
            Handler=make_handler(catalog,store);server=ThreadingHTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            try:
                with patch.object(Handler,'download_art',side_effect=AssertionError('Offline test forbids network'))as network:
                    for kind,blob in blobs.items():
                        path='/art/'+item['printing_id']+'?face='+str(item['requested_face'])+'&kind='+kind+'&exact=1'
                        check(call(path,binary=True,base='http://127.0.0.1:'+str(server.server_port))==blob,'Network-disabled HTTP returns identical cached '+kind+' bytes')
                    network.assert_not_called()
            finally:server.shutdown();server.server_close();thread.join()
        history=call('/history?limit=60')['matches'];completed=[i for i in history if i['completed']and i['outcome']in('win','loss','draw')]
        check(bool(completed),'History derives outcomes from actual completed native recordings')
        check(all(any(p['deck'].get('name')for p in i['players'])for i in completed),'Actual native history retains truthful per-seat deck names')
        report.update(passed=True,metadataLines=health['index']['lines'],metadataOracleCards=health['index']['cards'],tokenPrinting=item['printing_id'],tokenFace=item['requested_face'],imageBytes={k:len(v)for k,v in blobs.items()},nativeHistory=[{'id':i['id'],'outcome':i['outcome'],'format':i['format']}for i in completed],archidekt=imported['source'])
    except Exception as exc:
        report['failure']=str(exc);print('LIBRARY LIVE FAILED',str(exc),flush=True)
    finally:
        try:call('/decks/'+identifier,method='DELETE')
        except Exception:pass
        report['checks']=checks;args.output.write_text(json.dumps(report,indent=2)+'\n')
    print('LIBRARY LIVE COMPLETE',len(checks),'checks; passed =',report['passed'],flush=True)
    return 0 if report['passed']else 1


if __name__=='__main__':raise SystemExit(main())
