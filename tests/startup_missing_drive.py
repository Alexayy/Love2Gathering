#!/usr/bin/env python3
"""Exercise launcher ordering/errors without touching user storage or services."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'service'))
from storage import Storage


def main():
    results=[]
    with tempfile.TemporaryDirectory(prefix='love2gathering-missing-drive-')as temporary:
        base=Path(temporary);binary=base/'bin';binary.mkdir()
        # This proves early desktop launch/status ordering, not LÖVE pixels.
        executable=binary/'love'
        executable.write_text("""#!/usr/bin/env python3
import json,os,time
from pathlib import Path
status=Path(os.environ['LOVE2GATHERING_STARTUP_STATUS']);deadline=time.monotonic()+12
while time.monotonic()<deadline:
 try:
  value=json.loads(status.read_text())
  if value.get('state')=='error':
   Path(os.environ['LOVE2GATHERING_STARTUP_RECEIPT']).write_text(json.dumps(value));raise SystemExit(0)
 except (OSError,ValueError):pass
 time.sleep(.01)
raise SystemExit(2)
""")
        executable.chmod(0o700)
        for kind in('database','cache'):
            fixture=base/kind;fixture.mkdir();config=fixture/'config';config.mkdir()
            database=fixture/'data';cache=fixture/'unavailable-cache'
            if kind=='cache':
                available_cache=fixture/'temporary-cache'
                store=Storage(database,fixture/'bundled',available_cache)
                store.save_settings({'sfxVolume':.37})
                # The selected saved cache is deliberately absent; no real mount.
            selected={'databaseDirectory':str(database),'cacheDirectory':str(cache)}
            (config/'storage-paths.json').write_text(json.dumps({'version':1,'active':selected}))
            receipt=fixture/'receipt.json'
            env={key:value for key,value in os.environ.items()if not key.startswith('LOVE2GATHERING_')}
            env.update(PATH=str(binary)+os.pathsep+os.environ['PATH'],LOVE2GATHERING_CONFIG_DIR=str(config),LOVE2GATHERING_STARTUP_RECEIPT=str(receipt),LOVE2GATHERING_CATALOG_PORT='17770',LOVE2GATHERING_ENGINE_PORT='17771',LOVE2GATHERING_ROOM_PORT='17772')
            result=subprocess.run(['./run.sh'],cwd=ROOT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=20)
            assert result.returncode==1,(kind,result.returncode,result.stdout)
            progress=json.loads(receipt.read_text())
            assert progress['state']=='error'and progress['stage']=='storage',progress
            assert 'reconnect'in progress['message'].lower()or'unavailable'in progress['message'].lower(),progress
            assert not(cache/'images.sqlite').exists()
            if kind=='database':assert not(database/'app.sqlite').exists()
            else:assert store.settings()['sfxVolume']==.37
            result_cli=subprocess.run(['./run.sh','--services-only'],cwd=ROOT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=20)
            assert result_cli.returncode==1 and progress['message']in result_cli.stdout,(kind,result_cli.returncode,result_cli.stdout)
            results.append({'kind':kind,'earlyDesktopReceivedStorageError':True,'servicesOnlyError':True,'emptyReplacementAvoided':True,'message':progress['message']})
    report={'passed':True,'scope':'Real launcher path resolution/early desktop ordering with an explicit stand-in desktop process that consumes the normal status JSON. No actual LÖVE graphics, user data, engine or network access.','checks':results}
    (ROOT/'tests/startup-missing-drive-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2));return 0

if __name__=='__main__':raise SystemExit(main())
