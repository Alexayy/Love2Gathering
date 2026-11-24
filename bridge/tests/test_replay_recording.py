#!/usr/bin/env python3
"""Inspect a real engine replay, explicit Save, and durable SQLite outage recovery.
Run against isolated bridge/catalog services; replaces the selected bridge game.
"""
import argparse,json,os,sqlite3,subprocess,tempfile,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine-url',default='http://127.0.0.1:17372')
    parser.add_argument('--catalog-url',default='http://127.0.0.1:17374')
    parser.add_argument('--data-dir',type=Path,required=True)
    parser.add_argument('--gameplay-report',type=Path,default=ROOT/'bridge/tests/replay-gameplay-report.json')
    args=parser.parse_args()
    def call(base,path,body=None):
        req=urllib.request.Request(base+path,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(req,timeout=30) as response:return json.load(response)
    game=json.loads(args.gameplay_report.read_text());assert game['passed'] and game['replayId']
    identifier=game['replayId'];deadline=time.monotonic()+15
    while True:
        meta=call(args.catalog_url,'/replays/'+identifier)
        if meta['status']=='completed':break
        assert time.monotonic()<deadline, 'Completed native game was not delivered to the catalog'
        time.sleep(.02)
    # The engine also records automatic native priority passes. Submitted
    # interactive answers are checked separately against the immutable events.
    assert meta['actionCount']>=game['actionCount']
    assert meta['frameCount']>game['observedFrameCount'] and meta['eventCount']==meta['lastSequence']+1
    frames=[];offset=0
    while offset<meta['frameCount']:
        page=call(args.catalog_url,f'/replays/{identifier}/frames?offset={offset}&limit=100')
        frames.extend(page['frames']);offset+=len(page['frames'])
    assert len(frames)==meta['frameCount']
    categories=set();actors=set();stack_kinds=set();native=0
    for frame in frames:
        state=frame['data'];assert not state.get('error') and not state.get('projectionError')
        for player in state.get('players',[]):
            if not player['human']:assert player['hand']==[], 'Bot hidden hand leaked into a saved frame'
        for entry in state.get('stack',[]):
            assert entry['sourceCard'] and entry['artName']==entry['sourceCard']['name']
            assert entry.get('rules') or entry['sourceCard'].get('rules') or entry['sourceCard'].get('type')
            assert entry['isTop']==(entry['stackIndex']==0)
            assert entry['controllerId'] and isinstance(entry['targets'],list)
            stack_kinds.add(entry['kind'])
        for entry in state.get('log',[]):
            assert isinstance(entry,dict) and isinstance(entry['sequence'],int)
            categories.add(entry['category']);actors.add(entry['actor']);native+=entry.get('origin')=='game'
    assert {'cast','resolve','attack','damage','draw','land','turn','mana','trigger'}<=categories
    assert {'human','bot','system'}<=actors and native>0 and {'spell','ability'}<=stack_kinds
    assert frames[-1]['data']['running'] is False and frames[-1]['data']['prompt'] is None
    # Open a new SQLite connection: the recording is persistent, not an in-memory response cache.
    with sqlite3.connect(f'file:{args.data_dir / "app.sqlite"}?mode=ro',uri=True) as db:
        rows=db.execute('SELECT count(*),min(sequence),max(sequence) FROM replay_events WHERE replay_id=?',(identifier,)).fetchone()
        assert rows==(meta['eventCount'],0,meta['lastSequence'])
        actions=[json.loads(row[0]) for row in db.execute('SELECT payload FROM replay_events WHERE replay_id=? AND type=?',(identifier,'action'))]
        interactive=sum(action.get('input',{}).get('type')!='auto_priority' for action in actions)
        assert len(actions)==meta['actionCount'] and interactive==game['actionCount'], 'Every submitted answer and automatic native pass must be recorded exactly once'
    deck=json.loads((ROOT/'decks/modern-boros-burn.json').read_text());port=int(args.catalog_url.rsplit(':',1)[1])
    state=call(args.engine_url,'/session/start',{'format':'Modern','recordingPort':port,'deck':deck,'botDeck':deck})
    deadline=time.monotonic()+10
    while not state.get('prompt') and time.monotonic()<deadline:time.sleep(.02);state=call(args.engine_url,'/session/state')
    assert state['running'] and state['replayId']
    saved=call(args.engine_url,'/session/replay/save',{})
    assert saved.get('saved',True) and saved['replayId']==state['replayId'] and saved['replayStatus']=='recording' and saved['savedSequence']>=0
    assert call(args.engine_url,'/session/state')['running'], 'Explicit Save must not end the game'
    call(args.engine_url,'/session/stop',{})
    assert call(args.catalog_url,'/replays/'+state['replayId'])['status']=='aborted'
    classes=ROOT/'bridge/target/test-classes';classes.mkdir(parents=True,exist_ok=True)
    cp=os.pathsep.join([str(ROOT/'bridge/target/xmage-bridge-1.0.0.jar'),str(ROOT/'bridge/target/lib/*')])
    subprocess.run(['javac','-cp',cp,'-d',str(classes),str(ROOT/'bridge/tests/love2gathering/ReplayOutboxFixture.java')],check=True)
    command=['java','-cp',str(classes)+os.pathsep+cp,'love2gathering.ReplayOutboxFixture']
    env={**os.environ,'LOVE2GATHERING_DATA_DIR':str(args.data_dir)}
    with tempfile.TemporaryDirectory(prefix='l2g-replay-test-') as temporary:
        marker=Path(temporary)/'fixture.json'
        subprocess.run(command+['write',str(port),str(marker),'17379'],env=env,check=True)
        crash=json.loads(marker.read_text())
        subprocess.run(command+['recover',str(port),str(marker)],env=env,check=True)
        recovered=call(args.catalog_url,'/replays/'+crash['id'])
        assert recovered['status']=='aborted' and recovered['eventCount']==3 and recovered['lastSequence']==2
    result={'passed':True,'realGame':{'id':identifier,'turns':game['turns'],'actions':game['actionCount'],'persistedFrames':meta['frameCount'],'observedFrames':game['observedFrameCount'],'events':meta['eventCount'],'logs':meta['logCount']},'structuredActors':sorted(actors),'categories':sorted(categories),'stackKinds':sorted(stack_kinds),'botHandHiddenEveryFrame':True,'reopenedSQLite':True,'explicitSaveKeepsGameRunning':True,'outageSurfacedAndRetainedAllEvents':True,'crashedRecorderRecovered':True}
    (ROOT/'bridge/tests/replay-recording-report.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':main()
