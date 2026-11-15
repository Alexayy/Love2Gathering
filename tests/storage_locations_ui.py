#!/usr/bin/env python3
"""Own every service, SQLite file and LÖVE harness used by the Locations UI."""
import hashlib
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'service'))
from catalog import Catalog
from storage import Storage
from storage_locations import StorageLocations,read_config
from server import make_handler
import storage_locations


def main():
    with tempfile.TemporaryDirectory(prefix='love2gathering-locations-ui-')as temporary:
        base=Path(temporary);run=base/'harness';run.mkdir()
        source=base/'cards.jsonl';source.write_text(json.dumps({'object':'card','id':'location-printing','oracle_id':'location-oracle','name':'Locations Card','lang':'en','type_line':'Creature','set':'tst','set_name':'Test','legalities':{'modern':'legal'},'colors':['W'],'color_identity':['W'],'image_uris':{'normal':'https://cards.scryfall.io/normal.jpg','art_crop':'https://cards.scryfall.io/art.jpg'}})+'\n')
        catalog=Catalog(source,base/'catalog.sqlite');catalog.ensure();assert catalog.status()['state']=='ready'
        storage=Storage(base/'saves',ROOT/'decks');storage.save_settings({'sfxVolume':.45,'musicEnabled':False,'sfxEnabled':False})
        image=b'\xff\xd8temporary-exact-image'+b'x'*600000+b'\xff\xd9';storage.save_art('location-printing-0-normal.jpg',image,{'printingId':'location-printing','oracleId':'location-oracle','face':0,'kind':'normal'})
        foreign=base/'foreign';foreign.mkdir();(foreign/'app.sqlite').write_bytes(b'foreign-database-must-survive')
        location_env={'LOVE2GATHERING_CONFIG_DIR':str(base/'config')};locations=StorageLocations(storage,environ=location_env)
        original_backup=storage_locations._backup
        def delayed_backup(source,destination,check=None,update=None):
            if Path(source).name=='app.sqlite':
                until=time.monotonic()+1.2
                while time.monotonic()<until:
                    if check:check()
                    time.sleep(.02)
            return original_backup(source,destination,check,update)
        storage_locations._backup=delayed_backup
        handler=make_handler(catalog,storage,location_manager=locations);server=ThreadingHTTPServer(('127.0.0.1',0),handler);server.daemon_threads=True
        worker=threading.Thread(target=server.serve_forever,daemon=True);worker.start()
        for folder in('app','lib'):shutil.copytree(ROOT/folder,run/folder)
        for folder in('keyrune','icons'):shutil.copytree(ROOT/'assets'/folder,run/'assets'/folder)
        for folder in('ui','particles','sounds','theme','runtime'):shutil.copytree(ROOT/'assets/kenney'/folder,run/'assets/kenney'/folder)
        (run/'assets/fonts').mkdir(parents=True,exist_ok=True)
        for name in('DejaVuSans.ttf','DejaVuSans-Bold.ttf','Beleren2016-Bold.ttf'):shutil.copy2(ROOT/'assets/fonts'/name,run/'assets/fonts'/name)
        shutil.copy2(ROOT/'tests/storage_locations_ui.lua',run/'main.lua')
        (run/'conf.lua').write_text("function love.conf(t)t.identity='love2gathering-locations-ui-tests';t.window.title='Love2Gathering — isolated storage locations';t.window.width=2560;t.window.height=1080;t.window.resizable=true;t.window.vsync=0;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true end\n")
        env=dict(os.environ,LOVE2GATHERING_CATALOG_PORT=str(server.server_port),LOVE2GATHERING_ENGINE_PORT='65401',LOVE2GATHERING_ROOM_PORT='65402',LOVE2GATHERING_LOCATIONS_FIXTURE=str(base))
        try:
            process=subprocess.run(['love',str(run)],cwd=ROOT,env=env,timeout=160)
            if process.returncode:return process.returncode
            report=json.loads(Path('/tmp/love2gathering-storage-locations-ui-report.json').read_text())
            report['sourceSha256']={('tests/storage_locations_ui.lua'if file==run/'main.lua'else str(file.relative_to(run))):hashlib.sha256(file.read_bytes()).hexdigest()for file in list((run/'app').glob('*.lua'))+list((run/'lib/Slab').rglob('*.lua'))+[run/'main.lua']}
            assert not storage.relocation_active.is_set();assert not read_config(location_env).get('pending')
            assert storage.get_art('location-printing-0-normal.jpg')==image
            assert(foreign/'app.sqlite').read_bytes()==b'foreign-database-must-survive'
            assert not(base/'new database with padding/app.sqlite').exists();assert not(base/'separate image cache/images.sqlite').exists()
            report['backendVerification']={'sourceImagePreserved':True,'foreignDatabasePreserved':True,'pendingLocationCleared':True,'noUnconfirmedActivation':True,'temporaryStorageOnly':True}
            (ROOT/'tests/storage-locations-ui-report.json').write_text(json.dumps(report,indent=2)+'\n')
            return 0
        finally:
            server.shutdown();server.server_close();handler.close_managers();worker.join();storage_locations._backup=original_backup

if __name__=='__main__':raise SystemExit(main())
