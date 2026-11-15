#!/usr/bin/env python3
"""Read an already-exported native registry; check actual products in owned storage."""
import argparse,json,pathlib,sys,tempfile,time,hashlib
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'service'))
from storage import Storage
from engine_support import EngineSupport
p=argparse.ArgumentParser();p.add_argument('--registry',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);args=p.parse_args()
registry=json.loads(args.registry.read_text());assert registry['legalityChecked']is False
with tempfile.TemporaryDirectory(prefix='love2gathering-actual-deck-support-')as directory:
 store=Storage(pathlib.Path(directory),ROOT/'decks');manager=EngineSupport(store)
 try:
  started=time.monotonic();manager.register(registry);deadline=started+60
  while manager.status()['state']!='ready':
   assert time.monotonic()<deadline,'Actual product implementation scan exceeded deadline';time.sleep(.02)
  with store.connection()as c:
   rows=list(c.execute("SELECT id,name,payload FROM preconstructed WHERE active=1 AND category IN ('deck','packet') ORDER BY id"))
  available=[];unavailable=[]
  for row in rows:
   result=manager.for_id(row['id']);assert result['state']in('ready','unavailable'),result
   item={'id':row['id'],'name':row['name'],'missingNames':result['missingNames'],'fingerprint':result['fingerprint']}
   (available if result['available']else unavailable).append(item)
  commander=next(row for row in rows if json.loads(row['payload']).get('faceCommander')=='Anikthea, Hand of Erebos')
  anikthea=manager.for_id(commander['id']);assert anikthea['available'],'Actual Anikthea deck unexpectedly unsupported'
  report={'scope':'Actual prepared preconstructed deck/packet source and genuine installed native class-resource registry, scanned asynchronously against temporary SQLite only. Implementation coverage does not prove format legality. No acquisition or user writes.', 'registrySha256':hashlib.sha256(args.registry.read_bytes()).hexdigest(),'engineRevision':registry['engineRevision'],'registryRevision':registry['registryRevision'],'nativeNameCount':len(registry['names']),'productCount':len(rows),'availableCount':len(available),'unavailableCount':len(unavailable),'seconds':round(time.monotonic()-started,3),'anikthea':{'name':commander['name'],'state':anikthea['state']},'unavailable':unavailable,'cachedResults':manager.status()['cached']}
  args.output.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n');print(json.dumps({k:v for k,v in report.items()if k not in('unavailable','scope')},indent=2))
 finally:manager.close();store.close_images()
