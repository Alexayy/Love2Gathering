#!/usr/bin/env python3
"""Actual LÖVE workers keep foreground SQL/catalog/JPEG reads responsive during downloads."""
import argparse
from contextlib import contextmanager
import hashlib
from http.server import ThreadingHTTPServer
import base64
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
from urllib.parse import parse_qs,urlsplit
import uuid

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'service'));sys.path.insert(0,str(ROOT/'scripts'))
from catalog import Catalog
from storage import Storage
from server import make_handler
from mechanics.runtime import OwnedProcess,isolated_env,write_json,sha

PRINTING='22222222-2222-4222-8222-222222222222'
ORACLE='11111111-1111-4111-8111-111111111111'
# Generated solid32×32 RGB(104,143,117) JPEG; no card art or test dependency.
JPEG=base64.b64decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAAgACADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwAooorzz5IKKKKACiiigAooooA//9k=')


def card(printing,oracle,name):
    return {'object':'card','id':printing,'oracle_id':oracle,'name':name,'lang':'en','type_line':'Basic Land — Plains'if name=='Plains'else'Instant','oracle_text':'','mana_cost':'','colors':[],'color_identity':['W'],'set':'tst','set_name':'Fixture','artist':'Generated fixture pixels','released_at':'2020-01-01','legalities':{'modern':'legal'},'image_uris':{kind:f'https://cards.scryfall.io/{kind}/{printing}.jpg'for kind in('normal','large','art_crop')}}


@contextmanager
def service(directory):
    directory.mkdir(parents=True)
    jpeg=JPEG
    records=[card(PRINTING,ORACLE,'Plains')]
    for i in range(80):records.append(card(str(uuid.uuid5(uuid.NAMESPACE_DNS,'loading-printing-'+str(i))),str(uuid.uuid5(uuid.NAMESPACE_DNS,'loading-oracle-'+str(i))),'Background '+str(i)))
    source=directory/'metadata.jsonl';source.write_text('\n'.join(json.dumps(v)for v in records)+'\n')
    catalog=Catalog(source,directory/'catalog.sqlite');catalog.ensure()
    if not catalog.status().get('state')=='ready':raise AssertionError(catalog.status())
    store=Storage(directory/'data',directory/'bundled')
    store.save_settings({'theme':'Ember','accentColor':'#d67b52'})
    store.save_profile({'name':'Loading Fixture','avatar':{'oracleId':ORACLE,'printingId':PRINTING,'face':0},'playmat':None},catalog)
    store.save_deck({'id':'loading-deck','name':'Cached deck','format':'Modern','main':[{'name':'Plains','count':60}],'coverCard':'Plains'})
    store.save_art(PRINTING+'-0-large.jpg',jpeg,{'oracleId':ORACLE,'printingId':PRINTING,'face':0,'kind':'large'})
    base=make_handler(catalog,store);guard=threading.Lock();counts={'retryGets':0,'mutationPosts':0,'coalescedGets':0,'settingsPuts':0,'settingsRefreshGets':0,'settingsReadSnapshots':[]};fetched=[]
    class Fetcher:
        def image(self,url):
            with guard:fetched.append(url)
            time.sleep(.04);return jpeg
    base.downloads.fetcher_factory=Fetcher;base.downloads.disk_usage=lambda _:SimpleNamespace(free=20*1024**3)
    class Handler(base):
        def route(self,method):
            parts=urlsplit(self.path);query=parse_qs(parts.query)
            if method=='PUT'and parts.path=='/settings':
                with guard:counts['settingsPuts']+=1;number=counts['settingsPuts']
                # The second real SQLite save remains queued while the first
                # callback requests its refresh. Reads on another lane would
                # capture A, then wrongly share that snapshot with B's callback.
                if number==2:time.sleep(.3)
            if method=='GET'and parts.path=='/settings':
                with guard:refresh=counts['settingsPuts']>0
                if refresh:
                    snapshot=store.settings()
                    with guard:
                        counts['settingsRefreshGets']+=1;counts['settingsReadSnapshots'].append(snapshot['theme'])
                    time.sleep(.45);self.respond(200,snapshot);return
            if parts.path=='/probe/state':
                with guard:value=dict(counts,cachedDeckFetches=sum(PRINTING in url for url in fetched))
                value['download']=self.downloads.status();self.respond(200,value);return
            if parts.path=='/probe/retry':
                with guard:counts['retryGets']+=1;attempt=counts['retryGets']
                self.respond(503 if attempt==1 else 200,{'attempt':attempt,'retryable':attempt==1},retry_after=.1 if attempt==1 else None);return
            if parts.path=='/probe/mutation':
                self.read_json()
                with guard:counts['mutationPosts']+=1
                self.respond(503,{'retryable':True},retry_after=.1);return
            if query.get('probe')==['coalesced']:
                with guard:counts['coalescedGets']+=1
                time.sleep(.08)
            if query.get('probe')==['slow']:
                time.sleep(1.4)
                if parts.path=='/storage/status':self.respond(200,{'fixtureSlowMaintenance':True});return
            return super().route(method)
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.daemon_threads=True
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:
        state=base.downloads.scan({'fullSize':'large','kinds':['large'],'mirrors':False})
        deadline=time.monotonic()+8
        while state['state']!='ready'and time.monotonic()<deadline:
            time.sleep(.01);state=base.downloads.status()
        if state['state']!='ready':raise AssertionError(state)
        base.downloads.control('start')
        yield {'port':server.server_port,'storage':store,'catalog':catalog,'handler':Handler,'fetched':fetched,'counts':counts,'jpegSha256':hashlib.sha256(jpeg).hexdigest(),'directory':str(directory)}
    finally:
        Handler.close_managers();server.shutdown();server.server_close();thread.join(2)
        write_json(directory/'closed.json',{'serverThreadTerminated':not thread.is_alive(),'downloadWorkerTerminated':not(base.downloads.thread and base.downloads.thread.is_alive()),'state':base.downloads.status(),'fetchedImages':len(fetched),'cachedDeckFetches':sum(PRINTING in url for url in fetched)})


def variant(output,name,baseline=None,disable_mutation_barrier=False):
    directory=output/name;work=directory/'runtime';work.mkdir(parents=True)
    (work/'app').mkdir();(work/'lib').mkdir()
    files=['app/api.lua','app/http_worker.lua','app/image_decode.lua','lib/json.lua']
    for relative in files:
        content=subprocess.check_output(['git','show',baseline+':'+relative],cwd=ROOT)if baseline and relative in ('app/api.lua','app/http_worker.lua')else(ROOT/relative).read_bytes()
        if relative=='app/api.lua'and disable_mutation_barrier:
            barrier=b"if detail.orderedWrite and detail.group==group then lane='catalog';break end"
            if content.count(barrier)!=1:raise AssertionError('Expected one explicit mutation-read ordering barrier')
            content=content.replace(barrier,b"if false then lane='catalog';break end")
        (work/relative).write_bytes(content)
    shutil.copy2(ROOT/'tests/loading_http.lua',work/'main.lua')
    (work/'conf.lua').write_text("function love.conf(t)t.identity='loading-http-fixture';t.console=true;t.window=false;t.modules.graphics=false;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false end\n")
    env=isolated_env(work);env.update(SDL_VIDEODRIVER='dummy',L2G_LOADING_HTTP_OUTPUT=str(directory),L2G_LOADING_HTTP_ORACLE=ORACLE,L2G_LOADING_HTTP_PRINTING=PRINTING)
    with service(directory/'service')as active:
        env['L2G_LOADING_HTTP_PORT']=str(active['port'])
        process=OwnedProcess(['love',str(work)],directory/'runner',env=env)
        watch=process.wait({'wallSeconds':20,'cpuSeconds':20,'rssBytes':512*1024**2,'diskBytes':64*1024**2})
        result_path=directory/'result.json'
        result=json.loads(result_path.read_text())if result_path.exists()else{'status':'fail','error':'No fresh LÖVE result'}
        result.update(variant=name,baselineRevision=baseline,disabledMutationReadBarrier=disable_mutation_barrier,sourceHashes={relative:sha(work/relative)for relative in files},backendSourceHashes={name:sha(ROOT/name)for name in('service/storage.py','service/artwork.py','service/catalog.py','service/server.py','service/downloads.py')},watchdog=watch,jpegSha256=active['jpegSha256'],evidenceDirectory=str(directory))
        result['cachedDeckFetchesVerified']=not any(PRINTING in url for url in active['fetched'])
        result['savedSettingsPreserved']=active['storage'].settings()['theme']=='Ember'
    result['cleanup']=json.loads((directory/'service/closed.json').read_text())
    write_json(directory/'combined-result.json',result)
    print(name+': '+result['status'],flush=True);return result


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path);parser.add_argument('--current-only',action='store_true',help='Verify the current pipeline without historical backend comparisons');parser.add_argument('--baseline',default='81da081');parser.add_argument('--report-file',type=Path,default=ROOT/'tests/loading-http-report.json');args=parser.parse_args(argv)
    output=args.output.resolve()if args.output else Path(tempfile.mkdtemp(prefix='love2gathering-mechanics-loading-http-'))
    if not str(output).startswith('/tmp/love2gathering-mechanics-')or output.is_symlink():parser.error('Use a fresh owned mechanics /tmp directory')
    output.mkdir(parents=True,exist_ok=True)
    if any(output.iterdir()):parser.error('Output directory must be empty')
    if args.current_only:
        current=variant(output,'current');results=[current];baseline_failed_latency=stale_refresh_reproduced=None
    else:
        old=variant(output,'baseline',args.baseline);unordered=variant(output,'without-mutation-read-barrier',disable_mutation_barrier=True);current=variant(output,'current');results=[old,unordered,current]
        baseline_failed_latency=old['status']=='fail'and any('not queued behind'in text for text in old.get('failures',[]))
        stale_refresh_reproduced=unordered['status']=='fail'and any('refresh observes final B theme'in text for text in unordered.get('failures',[]))
    passed=(args.current_only or baseline_failed_latency and stale_refresh_reproduced)and current['status']=='pass'and current['watchdog']['status']=='pass'and all(value['watchdog']['ownedProcessTerminated']and value['cleanup']['serverThreadTerminated']and value['cleanup']['downloadWorkerTerminated']for value in results)
    report={'schema':1,'status':'pass'if passed else'fail','runId':output.name,'sourceRevision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'scope':'Actual headless LÖVE HTTP workers + actual isolated SQLite/catalog/background image job; generated JPEGs and explicit synthetic HTTP delay/status routes; baseline replaces API/worker only, another copy disables only the mutation-read barrier, backend is shared current code; no native game, external downloads or user data','fixtureSourceHashes':{str(p.relative_to(ROOT)):sha(p)for p in(ROOT/'tests/loading_http.py',ROOT/'tests/loading_http.lua')},'baselineLatencyReproduced':baseline_failed_latency,'staleCallbackRefreshReproduced':stale_refresh_reproduced,'output':str(output),'results':results,'currentOnly':args.current_only}
    write_json(output/'report.json',report);write_json(args.report_file,report)
    print('Report: '+str(output/'report.json'),flush=True);return 0 if passed else 1


if __name__=='__main__':raise SystemExit(main())
