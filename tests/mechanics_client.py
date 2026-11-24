#!/usr/bin/env python3
"""Owned-process client fault/render benchmark. No user services or engine files."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]


def dump(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def owned_child(command, cwd, env, output, *, seconds=60, rss_mb=768, cpu_seconds=30, disk_mb=256):
    """External watchdog; only signals the new process group this call owns."""
    output.mkdir(parents=True, exist_ok=True)
    begin = time.monotonic()
    samples, reason = [], None
    static_bytes=sum(p.stat().st_size for p in Path(cwd).rglob('*')if p.is_file())
    disk_bytes=static_bytes;disk_check=begin
    with (output/'process.log').open('w') as log:
        child = subprocess.Popen(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        pid = child.pid
        while child.poll() is None:
            elapsed = time.monotonic()-begin
            try:
                status = dict(line.split(':', 1) for line in Path(f'/proc/{pid}/status').read_text().splitlines() if ':' in line)
                rss = int(status.get('VmRSS', '0 kB').split()[0])*1024
                stat = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
                ticks = os.sysconf('SC_CLK_TCK')
                cpu=(int(stat[11])+int(stat[12]))/ticks
                samples.append({'elapsedSeconds': elapsed, 'rssBytes': rss, 'cpuSeconds': cpu, 'state': stat[0]})
                if rss > rss_mb*1024*1024: reason = 'rss_budget'
                if cpu > cpu_seconds:reason='cpu_budget'
            except (OSError, ValueError, IndexError):
                pass
            if elapsed > seconds: reason = 'wall_time_budget'
            if time.monotonic()-disk_check>.5:
                disk_bytes=static_bytes+sum(p.stat().st_size for p in output.rglob('*')if p.is_file());disk_check=time.monotonic()
                if disk_bytes>disk_mb*1024*1024:reason='disk_budget'
            if reason:
                os.killpg(pid, signal.SIGTERM)
                try: child.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    os.killpg(pid, signal.SIGKILL);child.wait(timeout=2)
                break
            time.sleep(.025)
        code = child.wait()
    result = {'pid': pid, 'ownedProcessGroup': pid, 'returnCode': code, 'durationSeconds': time.monotonic()-begin, 'status': 'budget_exceeded' if reason else 'pass' if code == 0 else 'fail', 'watchdogReason': reason, 'terminationConfirmed': child.poll() is not None, 'peakRssBytes': max((s['rssBytes'] for s in samples), default=0), 'diskBytesObserved':disk_bytes,'budgets':{'wallSeconds':seconds,'cpuSeconds':cpu_seconds,'rssMiB':rss_mb,'diskMiB':disk_mb},'samples': samples}
    dump(output/'process.json', result)
    return result


def prepare_work(work, output, source, *, graphical=False):
    shutil.copytree(ROOT/'app', work/'app');shutil.copytree(ROOT/'lib', work/'lib')
    if graphical:
        shutil.copy2(ROOT/'main.lua', work/'application-main.lua')
        for folder in ['keyrune', 'icons']:
            shutil.copytree(ROOT/'assets'/folder, work/'assets'/folder)
        for folder in ['ui', 'particles', 'sounds', 'theme', 'runtime']:
            shutil.copytree(ROOT/'assets/kenney'/folder, work/'assets/kenney'/folder)
        (work/'assets/fonts').mkdir(parents=True)
        for name in ['DejaVuSans.ttf', 'DejaVuSans-Bold.ttf', 'Beleren2016-Bold.ttf']:
            shutil.copy2(ROOT/'assets/fonts'/name, work/'assets/fonts'/name)
    identity = 'love2gathering-mechanics-client-'+work.name
    (work/'conf.lua').write_text("function love.conf(t)t.identity="+json.dumps(identity)+";t.console=true;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;"+("t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true" if graphical else "t.window=false;t.modules.graphics=false")+" end\n")
    if source == 'model':
        (work/'main.lua').write_text("local runtime=love\nfunction love.load()local ok,err=xpcall(function()dofile("+json.dumps(str(ROOT/'tests/mechanics_client_model.lua'))+")end,debug.traceback);love=runtime;if not ok then io.stderr:write(err..'\\n')end;love.event.quit(ok and 0 or 1)end\n")
    else: shutil.copy2(ROOT/'tests'/source, work/'main.lua')
    env = dict(os.environ)
    for key, suffix in [('LOVE2GATHERING_DATA_DIR','data'),('LOVE2GATHERING_CACHE_DIR','cache'),('LOVE2GATHERING_CONFIG_DIR','config'),('XDG_DATA_HOME','preferences'),('XDG_CONFIG_HOME','xdg-config'),('XDG_CACHE_HOME','xdg-cache')]:
        path = work/suffix;path.mkdir();env[key] = str(path)
    env['L2G_MECHANICS_CLIENT_OUTPUT'] = str(output)
    env['LOVE2GATHERING_CATALOG_PORT'] = '17499';env['LOVE2GATHERING_ENGINE_PORT'] = '17498';env['LOVE2GATHERING_ROOM_PORT'] = '17497'
    return env


class Faults(BaseHTTPRequestHandler):
    accepted = 0
    def log_message(self, *_): pass
    def send(self, value, code=200):
        data = json.dumps(value).encode();self.send_response(code);self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
    def do_GET(self):
        if self.path == '/session/state': time.sleep(1.5);self.send({'gameId':'game-old','running':True})
        elif self.path == '/invalid-json':
            self.send_response(200);self.send_header('Content-Length','8');self.end_headers();self.wfile.write(b'not-json')
        elif self.path == '/accepted-count': self.send({'accepted':self.server.accepted})
        else: self.send({'status':'ok'})
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0')))or b'{}')
        if self.path == '/accepted-then-lost':
            self.server.accepted += 1;self.close_connection=True;return
        if body.get('value')=='slow-action':time.sleep(1.5)
        self.send({**body,'path':self.path})


def run(args):
    output = Path(args.output).resolve() if args.output else Path('/tmp')/('love2gathering-client-evidence-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    if not str(output).startswith('/tmp/') or output.is_symlink(): raise SystemExit('Client tests require an owned output directory under /tmp')
    if output.exists()and any(output.iterdir()):raise SystemExit('Use a fresh empty output directory; older evidence must not be reused as a current result')
    output.mkdir(parents=True, exist_ok=True)
    run_id=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:12]
    results=[]
    with tempfile.TemporaryDirectory(prefix='love2gathering-mechanics-client-') as temp:
        base=Path(temp)
        watchdog=owned_child([sys.executable,'-c','import time;time.sleep(60)'],base,os.environ.copy(),output/'watchdog-selftest',seconds=.2)
        following=owned_child([sys.executable,'-c','print("following scenario continues")'],base,os.environ.copy(),output/'watchdog-following',seconds=2)
        if watchdog['status']!='budget_exceeded'or not watchdog['terminationConfirmed']or following['status']!='pass': raise AssertionError('Watchdog isolation self-test failed')
        results.append({'scenarioId':'client-watchdog-owned-process','evidenceType':'harness_selftest','status':'pass','watchdog':watchdog,'following':following})
        server=ThreadingHTTPServer(('127.0.0.1',0),Faults);server.accepted=0
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        cases=[('model','model',{},False),('transport','mechanics_client_transport.lua',{'L2G_MECHANICS_CLIENT_HTTP_PORT':str(server.server_port)},False),('artwork','mechanics_client_artwork.lua',{'L2G_MECHANICS_CLIENT_NATIVE':str(Path(args.native).resolve())}if args.native else{},True)]
        levels=[1,10] if args.mode=='smoke' else [1,10,100,500,1000]
        if args.levels: levels=list(map(int,args.levels.split(',')))
        for level in levels: cases.append((f'tokens-{level}','mechanics_client_ui.lua',{'L2G_MECHANICS_CLIENT_COUNT':str(level),'L2G_MECHANICS_CLIENT_VARIANT':'equal'},True))
        if args.mode!='smoke': cases += [('tokens-1000-varied','mechanics_client_ui.lua',{'L2G_MECHANICS_CLIENT_COUNT':'1000','L2G_MECHANICS_CLIENT_VARIANT':'varied'},True),('tokens-1000-churn','mechanics_client_ui.lua',{'L2G_MECHANICS_CLIENT_COUNT':'1000','L2G_MECHANICS_CLIENT_VARIANT':'churn'},True),('stack-1000','mechanics_client_ui.lua',{'L2G_MECHANICS_CLIENT_COUNT':'1000','L2G_MECHANICS_CLIENT_VARIANT':'varied','L2G_MECHANICS_CLIENT_STACK':'1000'},True)]
        if args.mode!='smoke':cases.append(('mutate-inspection','mechanics_client_ui.lua',{'L2G_MECHANICS_CLIENT_COUNT':'10','L2G_MECHANICS_CLIENT_VARIANT':'mutate'},True))
        if args.mode=='stress':cases.append(('tokens-5000','mechanics_client_ui.lua',{'L2G_MECHANICS_CLIENT_COUNT':'5000'},True))
        if args.native: cases.append(('native-projection','mechanics_client_ui.lua',{'L2G_MECHANICS_CLIENT_NATIVE':str(Path(args.native).resolve())},True))
        if args.baseline:cases=[case for case in cases if case[0]in('model','transport')]
        if args.only:
            requested=set(args.only.split(','));known={case[0]for case in cases}
            if requested-known:raise SystemExit('Unknown client cases: '+','.join(sorted(requested-known)))
            cases=[case for case in cases if case[0]in requested]
        try:
            for name,source,extra,graphical in cases:
                if name=='tokens-5000':
                    previous=next((r for r in results if r.get('scenarioId')=='client-1000-equal-stack0'),None)
                    if not previous or previous['status']!='pass'or previous['metrics']['frameCpu']['p95Ms']>args.frame_budget_ms or previous['process']['peakRssBytes']>args.rss_mb*1024*1024*.75:
                        results.append({'scenarioId':'client-5000-equal-stack0','status':'not_run','evidenceType':'synthetic_rendering_fixture','reason':'Previous1000-object level did not leave safe frame/RSS headroom'});continue
                work=base/name;work.mkdir();destination=output/name;destination.mkdir()
                env=prepare_work(work,destination,source,graphical=graphical);env.update(extra)
                if args.baseline:
                    for file in ['app/api.lua','app/model.lua']:
                        (work/file).write_bytes(subprocess.check_output(['git','show',args.baseline+':'+file],cwd=ROOT))
                if not graphical: env['SDL_VIDEODRIVER']='dummy'
                process=owned_child(['love',str(work)],work,env,destination,seconds=args.timeout,rss_mb=args.rss_mb,cpu_seconds=args.cpu_seconds,disk_mb=args.disk_mb)
                result_name='model.json'if source=='model'else'transport.json'if name=='transport'else'result.json'
                if (destination/result_name).exists(): case=json.loads((destination/result_name).read_text())
                else: case={'scenarioId':'client-'+name,'status':process['status']if process['status']!='pass'else'fail','evidenceType':'client_transport'if not graphical else'synthetic_rendering_fixture','error':'Child exited without a fresh result'}
                if process['status']!='pass':case['status']=process['status']
                if graphical and case.get('metrics',{}).get('frameCpu',{}).get('p95Ms',0)>args.frame_budget_ms:
                    case['status']='budget_exceeded';case['watchdogReason']='frame_cpu_budget';case['frameCpuBudgetMs']=args.frame_budget_ms
                case['runId']=run_id+':'+name;case['process']=process;case['gameThreadStatus']='not_applicable_client_process';case['recordingOutbox']='not_applicable_client_fixture';results.append(case)
                print(name+': '+case['status'],flush=True)
                if case['status']!='pass': shutil.copytree(work,destination/'failed-runtime')
                if name=='tokens-1000'and process['status']!='pass': break
        finally: server.shutdown();server.server_close();thread.join(timeout=2)
    sources={}
    for path in [ROOT/'main.lua',ROOT/'app/api.lua',ROOT/'app/model.lua',ROOT/'app/library.lua',ROOT/'app/artwork.lua',ROOT/'app/card_printings.lua',ROOT/'app/table.lua',ROOT/'app/view.lua',ROOT/'app/card_details_ui.lua',ROOT/'app/table_inspection.lua',ROOT/'app/match_ui.lua',ROOT/'app/renderer.lua',ROOT/'app/board_fx.lua',ROOT/'tests/mechanics_client_ui.lua',ROOT/'tests/mechanics_client_transport.lua',ROOT/'tests/mechanics_client_model.lua',ROOT/'tests/mechanics_client_artwork.lua',Path(__file__)]:
        relative=str(path.relative_to(ROOT));data=subprocess.check_output(['git','show',args.baseline+':'+relative],cwd=ROOT)if args.baseline and relative in('app/api.lua','app/model.lua')else path.read_bytes();sources[relative]=hashlib.sha256(data).hexdigest()
    failures=[r['status']for r in results if r['status']!='pass']
    overall='pass'if not failures else'budget_exceeded'if all(s in('budget_exceeded','not_run')for s in failures)else'fail'
    report={'runId':run_id,'status':overall,'sourceRevision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'dirty':subprocess.check_output(['git','status','--porcelain=v1'],cwd=ROOT,text=True),'baselineReproduction':bool(args.baseline),'componentOverrides':{'app/api.lua':args.baseline,'app/model.lua':args.baseline}if args.baseline else{},'evidenceScope':'Client/model/transport/synthetic rendering only; native rules require separate native scenario results','cases':results,'sources':sources}
    dump(output/'report.json',report);print(str(output/'report.json'))
    return 0 if report['status']=='pass'else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output');parser.add_argument('--mode',choices=['smoke','full','stress'],default='full');parser.add_argument('--levels');parser.add_argument('--native');parser.add_argument('--only',help='Comma-separated exact case names, e.g. native-projection');parser.add_argument('--baseline',help='Read-only Git revision copied into the isolated client to reproduce a prior failure');parser.add_argument('--timeout',type=float,default=60);parser.add_argument('--rss-mb',type=int,default=768);parser.add_argument('--frame-budget-ms',type=float,default=60);parser.add_argument('--cpu-seconds',type=float,default=30);parser.add_argument('--disk-mb',type=int,default=256)
    raise SystemExit(run(parser.parse_args()))
