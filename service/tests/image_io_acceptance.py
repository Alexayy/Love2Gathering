#!/usr/bin/env python3
"""Actual HTTP/SQLite with bounded simulated cold-disk latency; no Internet."""
from concurrent.futures import ThreadPoolExecutor
from http.server import ThreadingHTTPServer
from io import BytesIO
import hashlib
import json
from pathlib import Path
import random
import sys
import tempfile
import threading
import time
from urllib.error import HTTPError
from urllib.request import urlopen

ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'service'))
from catalog import Catalog
from image_io import ImageIO
from server import make_handler
from storage import Storage
from PIL import Image


class FIFO(ImageIO):
    """Isolate the missing priority policy, retaining the identical disk bound."""
    def foreground(self,selected=False):return super().foreground(False)
    def background(self,cancel=None):return self._priority(1,cancel)


def run(directory,priority):
    directory.mkdir();source=directory/'cards.jsonl';oracle='22222222-2222-4222-8222-222222222222'
    printings=['11111111-1111-4111-8111-'+format(index,'012d')for index in range(8)]
    source.write_text(''.join(json.dumps(dict(object='card',id=p,oracle_id=oracle,name='Performance Fixture',lang='en',set='tst',type_line='Instant',legalities={'modern':'legal'},image_uris={'normal':'https://cards.scryfall.io/normal/'+p+'.jpg','art_crop':'https://cards.scryfall.io/art_crop/'+p+'.jpg'}))+'\n'for p in printings))
    catalog=Catalog(source,directory/'catalog.sqlite');catalog.ensure();store=Storage(directory/'data',directory/'bundled');store.enable_thumbnails()
    image=Image.frombytes('RGB',(672,936),random.Random(123).randbytes(672*936*3));buffer=BytesIO();image.save(buffer,'JPEG',quality=85);data=buffer.getvalue()
    for p in printings[:-1]:store.save_art(p+'-0-normal.jpg',data,dict(printingId=p,oracleId=oracle,face=0,kind='normal'))
    assert store.flush_thumbnails(10);generation=store.image_io.status();store.image_io=ImageIO()if priority else FIFO()
    handler=make_handler(catalog,store);network=[]
    def fetch(_self,url):network.append(url);time.sleep(.04);return data
    handler.download_art=fetch;server=ThreadingHTTPServer(('127.0.0.1',0),handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start();base='http://127.0.0.1:'+str(server.server_port)
    selected=printings[-2];order=[];original=store._art_row;order_lock=threading.Lock()
    def bounded_disk(connection,key,variant):
        with order_lock:order.append('selected'if key==selected+'-0-normal.jpg'else'visible')
        time.sleep(.035)
        return original(connection,key,variant)
    store._art_row=bounded_disk
    def get(path):
        started=time.monotonic()
        with urlopen(base+path,timeout=5)as response:body=response.read();headers=dict(response.headers)
        return dict(seconds=time.monotonic()-started,bytes=len(body),headers=headers)
    def image_path(p):return '/gallery/art/'+p+'?kind=normal&variant=thumb&exact=1&network=0'
    def await_waiters(count):
        deadline=time.monotonic()+2
        while store.image_io.status()['waiting']<count and time.monotonic()<deadline:time.sleep(.002)
        assert store.image_io.status()['waiting']>=count,'Actual HTTP requests did not reach the disk queue'
    def bulk():
        with store.image_io.background():
            store.image_io.checkpoint()
            with store.connection(image=True)as c:
                order.append('bulk');c.execute('SELECT cache_key FROM art_cache LIMIT 1').fetchone();time.sleep(.035)
    try:
        with ThreadPoolExecutor(max_workers=8)as pool:
            with store.image_io.operation():
                background=pool.submit(bulk);await_waiters(1)
                ordinary=[pool.submit(get,image_path(p))for p in printings[:5]];await_waiters(6)
                selected_future=pool.submit(get,image_path(selected)+'&priority=selected');await_waiters(7)
                metadata=get('/settings')
            chosen=selected_future.result(5);visible=[future.result(5)for future in ordinary];background.result(5)
        store._art_row=original
        missing='/gallery/art/'+printings[-1]+'?kind=normal&network=0'
        try:get(missing);raise AssertionError('Expected an exact cache-only miss')
        except HTTPError as error:assert error.code==404;error.close()
        acquired=get('/gallery/art/'+printings[-1]+'?kind=normal&network=1&priority=selected')
        cached=get('/gallery/art/'+printings[-1]+'?kind=normal&network=0')
        assert len(network)==1 and acquired['bytes']==len(data)and cached['bytes']==len(data)
        assert metadata['seconds']<.25,'Metadata WAL reads must not wait behind a simulated image operation'
        assert store.flush_thumbnails(10)
        info=store.artwork_summary();timings=store.image_io.status()
        return dict(priorityEnabled=priority,selectedFirst=order[0]=='selected',diskOrder=order,
                    selected=chosen,visible=visible,metadata=metadata,forcedNetwork=acquired,reopenedCached=cached,
                    networkFetchCount=len(network),io=timings,thumbnailGenerationTimings=generation,
                    originals=dict(count=8,bytes=8*len(data)),thumbnailExtra=dict(count=info['thumbnailImages'],bytes=info['thumbnailBytes'],bytesPerImage=info['thumbnailBytes']/info['thumbnailImages']),
                    thumbnailStats=store.thumbnails.status(),exportMirrorBytes=0)
    finally:
        server.shutdown();server.server_close();thread.join(3);handler.close_managers()
        assert not thread.is_alive()and not store.thumbnails.status()['workerAlive']


def main():
    out=Path(tempfile.mkdtemp(prefix='love2gathering-image-io-acceptance-'))
    baseline=run(out/'fifo-baseline',False);current=run(out/'priority',True)
    passed=not baseline['selectedFirst']and current['selectedFirst']and current['diskOrder'][-1]=='bulk'
    report=dict(status='pass'if passed else'fail',baseline=baseline,current=current,output=str(out),
                baselinePriorityAssertionExpectedFailure=not baseline['selectedFirst'],
                sourceHashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in [ROOT/'service'/name for name in('server.py','storage.py','artwork.py','image_io.py','thumbnails.py')]},
                scope='Owned real ThreadingHTTPServer/Catalog/SQLite and generated JPEGs. The exact same bounded 35ms fake cold-disk step runs in FIFO and priority cases; this measures scheduling, not physical HDD throughput or Internet speed. Originals remain untouched; derived JPEG bytes are additional to originals, independent of optional export mirrors.')
    text=json.dumps(report,indent=2,sort_keys=True)+'\n';(out/'report.json').write_text(text);(ROOT/'service/tests/image-io-performance-report.json').write_text(text)
    print(report['status'],out/'report.json');print('selected seconds FIFO/current',baseline['selected']['seconds'],current['selected']['seconds']);print('thumbnail extra bytes',current['thumbnailExtra'])
    return 0 if passed else 1


if __name__=='__main__':raise SystemExit(main())
