#!/usr/bin/env python3
"""Build a local Flatpak bundle from the compiled Linux payload and installed SDK."""
import argparse
from datetime import date, datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

PROJECT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(PROJECT/'packaging'))
from python_dependencies import bundle_pillow
APP_ID='io.github.Alexayy.Love2Gathering'
RUNTIME_BRANCH='25.08'
PERMISSIONS=['--share=network','--share=ipc','--socket=x11','--socket=wayland','--socket=pulseaudio','--device=dri','--filesystem=host']


def run(*args):
    subprocess.run([str(arg)for arg in args],check=True)


def runtime_preflight(work):
    """Check the shipping Platform, not the more complete SDK used to build."""
    command=['flatpak','build','--runtime','--env=LD_LIBRARY_PATH=/app/lib/love','--env=PYTHONPATH=/app/share/Love2Gathering/runtime/python-packages',str(work)]
    love=subprocess.check_output(command+['/app/share/Love2Gathering/runtime/love/bin/love','--version'],text=True).strip()
    if not love.startswith('LOVE 11.5'):
        raise ValueError('Packaged LÖVE 11.5 could not run in the Platform runtime')
    python=json.loads(subprocess.check_output(command+['python3','-c',
        'import ctypes,json,sqlite3,ssl,sys;from PIL import Image,features,__version__ as pillow;assert features.check_codec("jpg");print(json.dumps({"python":sys.version.split()[0],"sqlite":sqlite3.sqlite_version,"ssl":ssl.OPENSSL_VERSION,"pillow":pillow,"jpeg":True}))'],text=True))
    if not python.get('pillow') or python.get('jpeg') is not True:
        raise ValueError('Packaged Pillow JPEG support is unavailable in the shipping Platform')
    java=subprocess.check_output(command+['/app/share/Love2Gathering/runtime/java/bin/java','--version'],text=True).strip()
    if not re.match(r'(?:openjdk|java) 21(?:[.\s]|$)',java):
        raise ValueError('Packaged Java 21 could not run in the Platform runtime')
    commits={}
    for kind in ('Platform','Sdk'):
        ref='org.freedesktop.'+kind+'//'+RUNTIME_BRANCH
        value=subprocess.check_output(['flatpak','info','--arch=x86_64','--show-commit',ref],text=True).strip()
        if not re.fullmatch('[0-9a-f]{64}',value):
            raise ValueError('Cannot identify the installed Flatpak '+kind+' commit')
        commits[kind.lower()]=value
    return {'branch':RUNTIME_BRANCH,'commits':commits,'love':love,'java':java.splitlines()[0],**python}


def write_metainfo(source,destination,version):
    tree=ET.parse(source);releases=tree.getroot().find('releases')
    if releases is None:releases=ET.SubElement(tree.getroot(),'releases')
    match=re.match(r'^(\d{4})\.(\d{1,2})\.(\d{1,2})(?:\.|$)',version)
    release_date=date(*(int(part)for part in match.groups()))if match else datetime.now(timezone.utc).date()
    existing=next((node for node in releases if node.get('version')==version),None)
    if existing is None:releases.insert(0,ET.Element('release',{'version':version,'date':release_date.isoformat()}))
    tree.write(destination,encoding='UTF-8',xml_declaration=True)


def build(payload,output,work,version):
    if not(payload/'runtime/java/bin/java').is_file():
        raise ValueError('The Linux payload must include runtime/java/bin/java')
    if work.exists():shutil.rmtree(work)
    work.parent.mkdir(parents=True,exist_ok=True);output.mkdir(parents=True,exist_ok=True)
    run('flatpak','build-init','--arch=x86_64',work,APP_ID,'org.freedesktop.Sdk','org.freedesktop.Platform',RUNTIME_BRANCH)
    files=work/'files';installed=files/'share/Love2Gathering'
    shutil.copytree(payload,installed)
    shutil.copy2(PROJECT/'packaging/runtime/launcher.py',installed/'launcher.py')
    (files/'bin').mkdir(parents=True,exist_ok=True)
    wrapper=files/'bin/love2gathering'
    wrapper.write_text('#!/bin/sh\nexport LD_LIBRARY_PATH="/app/lib/love${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\nexport PYTHONPATH="/app/share/Love2Gathering/runtime/python-packages${PYTHONPATH:+:$PYTHONPATH}"\nexec python3 /app/share/Love2Gathering/launcher.py "$@"\n');wrapper.chmod(0o755)
    pillow=bundle_pillow('flatpak-cp313',installed/'runtime/python-packages',PROJECT/'.tools/packaging-platform/downloads')
    binary=Path(shutil.which('love')or'/usr/bin/love')
    result=subprocess.run([str(binary),'--version'],check=True,capture_output=True,text=True)
    if not result.stdout.startswith('LOVE 11.5'):
        raise ValueError('Build requires the tested native LÖVE 11.5')
    target=installed/'runtime/love/bin/love';target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(binary,target)
    # Freedesktop25.08 supplies SDL2/OpenAL/FreeType/etc. These three SONAMEs
    # are absent or changed there and remain alongside their original notices.
    names=['libmodplug.so.1','libluajit-5.1.so.2','libtheoradec.so.1']
    ldd=subprocess.check_output(['ldd',str(binary)],text=True);provenance={'love':{'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'version':result.stdout.strip()},'libraries':{},'pillow':pillow}
    library_dir=files/'lib/love';library_dir.mkdir(parents=True)
    for name in names:
        source=next((Path(line.split('=>',1)[1].strip().split()[0])for line in ldd.splitlines()if line.strip().startswith(name+' =>')),None)
        if not source or not source.is_file():raise ValueError('Missing native library '+name)
        shutil.copy2(source,library_dir/name)
        provenance['libraries'][name]={'source':str(source),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
    notices=installed/'licenses/flatpak-native';notices.mkdir(parents=True,exist_ok=True)
    luajit_package='libluajit2-5.1-2'if(Path('/usr/share/doc/libluajit2-5.1-2/copyright').is_file())else'libluajit-5.1-2'
    for package in('love','libmodplug1',luajit_package,'libtheora0'):
        source=Path('/usr/share/doc')/package/'copyright'
        if not source.is_file():raise ValueError('Missing redistribution notice for '+package)
        shutil.copy2(source,notices/(package+'.copyright'))
    desktop=files/'share/applications';desktop.mkdir(parents=True,exist_ok=True)
    shutil.copy2(HERE/(APP_ID+'.desktop'),desktop/(APP_ID+'.desktop'))
    meta=files/'share/metainfo';meta.mkdir(parents=True,exist_ok=True)
    write_metainfo(HERE/(APP_ID+'.metainfo.xml'),meta/(APP_ID+'.metainfo.xml'),version)
    icons=files/'share/icons/hicolor/256x256/apps';icons.mkdir(parents=True,exist_ok=True)
    shutil.copy2(installed/'share/icons/love2gathering.png',icons/(APP_ID+'.png'))
    (installed/'host-tools').mkdir(exist_ok=True)
    for name in('install-flatpak.py','update-host.py'):shutil.copy2(HERE/name,installed/'host-tools'/name)
    manifest={'version':1,'files':{str(path.relative_to(installed)):hashlib.sha256(path.read_bytes()).hexdigest()for path in sorted(installed.rglob('*'))if path.is_file()and path.name!='payload-manifest.json'}}
    (installed/'payload-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    provenance['runtime']=runtime_preflight(work)
    run('flatpak','build-finish','--command=love2gathering',*PERMISSIONS,work)
    repo=work.parent/'repo'
    run('flatpak','build-export','--arch=x86_64',repo,work,'stable')
    artifact=output/('Love2Gathering-'+version+'-x86_64.flatpak')
    run('flatpak','build-bundle','--arch=x86_64','--runtime-repo=https://flathub.org/repo/flathub.flatpakrepo',repo,artifact,APP_ID,'stable')
    (output/'flatpak-native-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
    shutil.copy2(HERE/'install-flatpak.py',output/'install-flatpak.py')
    shutil.copy2(HERE/'update-host.py',output/'update-host.py')
    print(artifact)
    return artifact


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--payload',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=PROJECT/'dist')
    parser.add_argument('--work',type=Path,default=PROJECT/'.runtime/flatpak-build/application')
    parser.add_argument('--version',default='2026.11.14')
    args=parser.parse_args();build(args.payload.resolve(),args.output.resolve(),args.work.resolve(),args.version)
