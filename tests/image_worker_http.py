#!/usr/bin/env python3
"""Actual LÖVE worker decoding, channel ownership, bounds and independent lanes."""
import argparse
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import parse_qs,urlsplit
import zlib

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'));sys.path.insert(0,str(ROOT/'tests'))
from mechanics.runtime import OwnedProcess,isolated_env,write_json,sha
from loading_http import JPEG  # Generated 32x32 fixture pixels, never card art.


def chunk(kind,body):return struct.pack('>I',len(body))+kind+body+struct.pack('>I',zlib.crc32(kind+body)&0xffffffff)
def png(width,height,pixels=True):
    header=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))
    return header+(chunk(b'IDAT',zlib.compress((b'\0'+bytes((104,143,117,255))*width)*height))if pixels else b'')+chunk(b'IEND',b'')


@contextmanager
def fixture():
    lock=threading.Lock();counts={};held=[0]
    normal=png(32,32)
    invalid={
        '/art/corrupt-header.png':b'\x89PNG\r\n\x1a\n'+b'\0'*4+b'IHDR'+b'\0'*5,
        '/art/corrupt-header.jpg':b'\xff\xd8\xff\xc0\0\x11\x08\0',
        '/art/corrupt-pixels.png':png(32,32,False),
        '/art/oversized.png':png(100000,100000,False),
        '/art/oversized.jpg':b'\xff\xd8\xff\xc0\0\x11\x08'+struct.pack('>HH',65535,65535)+b'\x03\x01\x11\0\x02\x11\0\x03\x11\0\xff\xd9',
        '/art/oversized-compressed.jpg':JPEG+b'x'*(3*1024**2+1-len(JPEG)),
    }
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def respond(self,data,mime='application/json',headers=None):
            body=data if isinstance(data,bytes)else json.dumps(data,separators=(',',':')).encode()
            self.send_response(200);self.send_header('Content-Type',mime);self.send_header('Content-Length',str(len(body)))
            for name,value in(headers or{}).items():self.send_header(name,value)
            self.end_headers()
            try:self.wfile.write(body)
            except(BrokenPipeError,ConnectionResetError):pass
        def do_GET(self):
            parts=urlsplit(self.path);query=parse_qs(parts.query)
            with lock:counts[self.path]=counts.get(self.path,0)+1
            if parts.path=='/probe/state':
                with lock:value={'requests':dict(counts),'heldSearches':held[0]}
                self.respond(value);return
            if parts.path=='/cards'and query.get('q',[None])[0]in('hold-a','hold-b'):
                with lock:held[0]+=1
                time.sleep(1.2);self.respond({'cards':[],'total':0});return
            if parts.path in('/settings','/profile','/cards/by-name','/printings'):
                with lock:started=held[0]
                self.respond({'name':'Swamp','printing_id':'fixture','items':[{'name':'Swamp','printing_id':'fixture'}],'heldSearches':started});return
            if query.get('coalesced')==['1']:time.sleep(.08)
            if parts.path=='/art/selected-a.jpg':time.sleep(1.2)
            image=invalid.get(parts.path,JPEG if parts.path.endswith('.jpg')else normal)
            self.respond(image,'image/jpeg'if parts.path.endswith('.jpg')else'image/png',{'X-Love2Gathering-Art-Variant':'original'})
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.daemon_threads=True
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:yield server,counts,normal
    finally:server.shutdown();server.server_close();thread.join(2)
    if thread.is_alive():raise AssertionError('Owned fixture server did not stop')


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path);parser.add_argument('--report-file',type=Path,default=ROOT/'tests/image-worker-http-report.json');args=parser.parse_args(argv)
    output=args.output.resolve()if args.output else Path(tempfile.mkdtemp(prefix='love2gathering-mechanics-image-worker-'))
    if not str(output).startswith('/tmp/love2gathering-mechanics-')or output.is_symlink():parser.error('Use a fresh owned mechanics /tmp directory')
    output.mkdir(parents=True,exist_ok=True)
    if any(output.iterdir()):parser.error('Output directory must be empty')
    work=output/'runtime';(work/'app').mkdir(parents=True);(work/'lib').mkdir()
    sources=['app/api.lua','app/http_worker.lua','app/image_decode.lua','lib/json.lua']
    for relative in sources:shutil.copy2(ROOT/relative,work/relative)
    (work/'fixture.jpg').write_bytes(JPEG)
    shutil.copy2(ROOT/'tests/image_worker_http.lua',work/'main.lua')
    (work/'conf.lua').write_text("function love.conf(t)t.identity='image-worker-http-fixture';t.console=true;t.window=false;t.modules.graphics=false;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false end\n")
    env=isolated_env(work,{'SDL_VIDEODRIVER':'dummy','L2G_IMAGE_WORKER_OUTPUT':str(output),'L2G_IMAGE_WORKER_JPEG_BYTES':str(len(JPEG))})
    with fixture()as(server,counts,normal):
        env['L2G_IMAGE_WORKER_PORT']=str(server.server_port)
        process=OwnedProcess(['love',str(work)],output/'runner',env=env)
        watch=process.wait({'wallSeconds':20,'cpuSeconds':15,'rssBytes':192*1024**2,'diskBytes':32*1024**2})
        path=output/'result.json';result=json.loads(path.read_text())if path.is_file()else{'status':'fail','error':'No fresh LÖVE result'}
        result.update(watchdog=watch,httpRequestCounts=dict(counts),jpegSha256=hashlib.sha256(JPEG).hexdigest(),pngSha256=hashlib.sha256(normal).hexdigest())
    hashes={name:sha(work/name)for name in sources}
    current_matches=all(sha(ROOT/name)==value for name,value in hashes.items())
    passed=result['status']=='pass'and watch['status']=='pass'and watch['ownedProcessTerminated']and current_matches
    report={'schema':1,'status':'pass'if passed else'fail','runId':output.name,'sourceRevision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'sourceHashes':hashes,'sourceStillMatches':current_matches,'fixtureSourceHashes':{name:sha(ROOT/name)for name in('tests/image_worker_http.py','tests/image_worker_http.lua','tests/loading_http.py')},'output':str(output),'serverTerminated':True,'scope':'Actual headless LÖVE LuaSocket worker threads, real ImageData transfer/release, generated PNG/JPEG fixtures and a minimal owned HTTP fault fixture. Native allocation auditing wraps the unchanged production worker loader. No GPU rendering, native game, external network or user data.','result':result}
    write_json(output/'report.json',report);write_json(args.report_file,report)
    print('Image worker HTTP '+report['status']+'; report '+str(output/'report.json'));return 0 if passed else 1


if __name__=='__main__':raise SystemExit(main())
