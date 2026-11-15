#!/usr/bin/env python3
"""Real headless LÖVE worker/socket read lanes under held mutation latency."""
import argparse
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json,pathlib,shutil,sys,tempfile,threading,time
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from mechanics.runtime import OwnedProcess,isolated_env,write_json,sha

@contextmanager
def fixture():
 lock=threading.Lock();started=time.monotonic();events=[];order=[];finished=set();counts={'nativeReads':0,'roomReads':0,'healthReads':0,'orderViolations':0}
 starts={name:threading.Event()for name in('native','room')};reads={name:{kind:threading.Event()for kind in('state','health')}for name in starts}
 def mark(name,**data):
  with lock:events.append(dict(event=name,seconds=round(time.monotonic()-started,6),**data))
 class Handler(BaseHTTPRequestHandler):
  def log_message(self,*args):pass
  def respond(self,value):
   data=json.dumps(value,separators=(',',':')).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers()
   try:self.wfile.write(data)
   except(BrokenPipeError,ConnectionResetError):pass
  def do_POST(self):
   body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))));probe=body['probe'];phase=probe.split('-')[0]
   with lock:order.append(probe)
   mark('mutation-start',probe=probe,path=self.path)
   if probe.endswith('-A'):
    starts[phase].set();arrived=all(reads[phase][kind].wait(2)for kind in('state','health'))
    # The reads must arrive while the handler still owns this mutation.
    # Give their actual worker callbacks time to prove that independence.
    time.sleep(.4)
    with lock:finished.add(probe)
    mark('mutation-finish',probe=probe,readsArrived=arrived);self.respond({'readsArrived':arrived,'expectedGameId':body.get('expectedGameId')})
   else:
    with lock:first=phase+'-A'in finished;counts['orderViolations']+=int(not first)
    mark('mutation-finish',probe=probe,firstMutationFinished=first);self.respond({'firstMutationFinished':first,'expectedGameId':body.get('expectedGameId')})
  def do_GET(self):
   path=self.path
   if path=='/probe/summary':
    with lock:value=dict(counts,mutationOrder=list(order),events=list(events))
    self.respond(value);return
   if path=='/health':
    with lock:counts['healthReads']+=1;phase='native'if counts['healthReads']==1 else'room'
    starts[phase].wait(1)
    with lock:held=phase+'-A'not in finished
    reads[phase]['health'].set();mark('health',phase=phase,actionStillHeld=held);self.respond({'ok':True,'actionStillHeld':held});return
   if path=='/session/state':
    with lock:counts['nativeReads']+=1;number=counts['nativeReads']
    if number==1:
     starts['native'].wait(1)
     with lock:held='native-A'not in finished
     reads['native']['state'].set();mark('state',phase='native',actionStillHeld=held);self.respond({'gameId':'native-live','actionStillHeld':held})
    elif number==2:mark('state-delayed',phase='native');time.sleep(.25);self.respond({'gameId':'native-old'})
    else:self.respond({'gameId':'native-new'})
    return
   if path.startswith('/client/rooms/')and path.endswith('/game/state'):
    with lock:counts['roomReads']+=1
    connection=path.split('/')[3]
    if connection=='owned-live':
     starts['room'].wait(1)
     with lock:held='room-A'not in finished
     reads['room']['state'].set();mark('state',phase='room',actionStillHeld=held);self.respond({'gameId':'room-live','actionStillHeld':held})
    elif connection=='owned-old':mark('state-delayed',phase='room');time.sleep(.25);self.respond({'gameId':'room-old'})
    else:self.respond({'gameId':'room-new'})
    return
   raise AssertionError('Unexpected controlled endpoint: '+path)
 server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.daemon_threads=True;thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
 try:yield server
 finally:server.shutdown();server.server_close();thread.join(2)
 assert not thread.is_alive(),'Owned fixture host did not terminate'

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=pathlib.Path);p.add_argument('--report-file',type=pathlib.Path,default=ROOT/'tests/api-read-lanes-report.json');a=p.parse_args()
 out=a.output.resolve()if a.output else pathlib.Path(tempfile.mkdtemp(prefix='love2gathering-mechanics-read-lanes-'))
 if not str(out).startswith('/tmp/love2gathering-mechanics-')or out.is_symlink():p.error('Use a fresh owned temporary mechanics directory')
 out.mkdir(parents=True,exist_ok=True)
 if any(out.iterdir()):p.error('Output directory must be empty')
 work=out/'runtime';(work/'app').mkdir(parents=True);(work/'lib').mkdir()
 sources=['app/api.lua','app/http_worker.lua','app/image_decode.lua','lib/json.lua']
 for source in sources:shutil.copy2(ROOT/source,work/source)
 shutil.copy2(ROOT/'tests/api_read_lanes.lua',work/'main.lua');(work/'conf.lua').write_text("function love.conf(t)t.identity='api-read-lanes-fixture';t.console=true;t.window=false;t.modules.graphics=false;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false end\n")
 env=isolated_env(work,{'SDL_VIDEODRIVER':'dummy','L2G_READ_LANES_OUTPUT':str(out)})
 with fixture()as server:
  env['L2G_READ_LANES_PORT']=str(server.server_port);process=OwnedProcess(['love',str(work)],out/'runner',env=env)
  watch=process.wait({'wallSeconds':20,'cpuSeconds':10,'rssBytes':192*1024**2,'diskBytes':16*1024**2})
 result=json.loads((out/'result.json').read_text())if(out/'result.json').is_file()else{'status':'fail','error':'No fresh LÖVE result'}
 hashes={source:sha(work/source)for source in sources};matches=all(sha(ROOT/source)==digest for source,digest in hashes.items())
 passed=result['status']=='pass'and watch['status']=='pass'and watch['ownedProcessTerminated']and matches
 report={'schema':1,'status':'pass'if passed else'fail','sourceHashes':hashes,'sourceStillMatches':matches,'fixtureSourceHashes':{name:sha(ROOT/name)for name in('tests/api_read_lanes.py','tests/api_read_lanes.lua')},'output':str(out),'serverTerminated':True,'scope':'Actual headless LÖVE app/api and unmodified http_worker threads over real LuaSocket connections to an owned threaded HTTP fault fixture. Ordinary native/room mutations are held until state+health requests arrive; FIFO and generation guards are tested. Synthetic HTTP payloads, no graphics/GPU, native game, external network or user data.','result':result,'watchdog':watch}
 write_json(out/'report.json',report);write_json(a.report_file,report);print('Read lanes '+report['status']+'; report '+str(out/'report.json'));return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())
