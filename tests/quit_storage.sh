#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec python3 - "$project_dir" <<'PY'
import os
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer
project=Path(sys.argv[1]);sys.path.insert(0,str(project/'service'))
from catalog import Catalog
from server import make_handler
from storage import Storage
with tempfile.TemporaryDirectory(prefix='l2g-quit-storage-') as temporary:
    root=Path(temporary);source=root/'client';source.mkdir();data=root/'user'
    # Only construction validation is needed here. Never rebuild the index used
    # by a running user's catalog for this shutdown/persistence test.
    metadata=root/'cards.jsonl';metadata.write_text(json.dumps({'object':'card','id':'11111111-1111-4111-8111-111111111111','oracle_id':'22222222-2222-4222-8222-222222222222','name':'Lightning Bolt','lang':'en','mana_cost':'{R}','cmc':1,'type_line':'Instant','oracle_text':'Lightning Bolt deals 3 damage to any target.','colors':['R'],'color_identity':['R'],'legalities':{'modern':'legal'},'set':'tst'})+'\n')
    catalog=Catalog(metadata,root/'catalog.sqlite');catalog.ensure()
    assert catalog.status()['state']=='ready'
    for directory in ('app','lib'):shutil.copytree(project/directory,source/directory)
    for name in ('main.lua','conf.lua'):shutil.copy2(project/'tests/quit_storage'/name,source/name)
    storage=Storage(data,project/'decks')
    server=ThreadingHTTPServer(('127.0.0.1',0),make_handler(catalog,storage));server.daemon_threads=True
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:
        environment=dict(os.environ,LOVE2GATHERING_CATALOG_PORT=str(server.server_port),XDG_DATA_HOME=str(root/'love-data'))
        result=subprocess.run(['love',str(source)],env=environment,timeout=20)
        assert result.returncode==0,f'Love quit check exited {result.returncode}'
        reopened=Storage(data,project/'decks')
        assert reopened.ui_layout()['quitTest']=='callback-chain-committed'
        assert all(path.name.startswith('app.sqlite')or path.name=='.maintenance.lock' for path in data.iterdir()),'Unexpected save outside the SQLite store or its coordination lock'
        print('QUIT STORAGE PASS: reopened SQLite contains the chained write; no new JSON files')
    finally:server.shutdown();server.server_close();thread.join()
PY
