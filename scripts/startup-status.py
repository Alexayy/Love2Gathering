#!/usr/bin/env python3
"""Write small atomic launcher progress snapshots for the desktop splash."""
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import time


def update(path,stage,progress,message,state='loading'):
    path=Path(path)
    try:previous=json.loads(path.read_text())
    except (OSError,ValueError):previous={}
    checks=previous.get('checks',[])
    for check in checks:
        if check.get('state')=='loading':check['state']='error'if state=='error'else'ready'
    item={'stage':stage,'state':state,'message':message}
    found=next((check for check in checks if check.get('stage')==stage),None)
    if found:found.update(item)
    else:checks.append(item)
    value={'state':state,'stage':stage,'message':message,'progress':max(0,min(1,float(progress))),
           'checks':checks,'updatedAt':int(time.time()*1000)}
    version=previous.get('version')
    if not version:
        result=subprocess.run(['git','rev-parse','--short','HEAD'],cwd=Path(__file__).resolve().parents[1],capture_output=True,text=True)
        version=result.stdout.strip()if result.returncode==0 else'local build'
    value['version']=version
    fd,temporary=tempfile.mkstemp(prefix='.'+path.name,dir=path.parent)
    try:
        with os.fdopen(fd,'w')as stream:json.dump(value,stream);stream.flush()
        os.replace(temporary,path)
    finally:
        if os.path.exists(temporary):os.unlink(temporary)
    return value

if __name__=='__main__':update(*sys.argv[1:])
