#!/usr/bin/env python3
"""Build a local Flatpak bundle from the compiled Linux payload and installed SDK."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

PROJECT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
APP_ID='io.github.Alexayy.Love2Gathering'
PERMISSIONS=['--share=network','--share=ipc','--socket=x11','--socket=wayland','--socket=pulseaudio','--device=dri','--filesystem=host']


def run(*args):
    subprocess.run([str(arg)for arg in args],check=True)


def build(payload,output,work,version):
    if not(payload/'runtime/java/bin/java').is_file():
        raise ValueError('The Linux payload must include runtime/java/bin/java')
    if work.exists():shutil.rmtree(work)
    work.parent.mkdir(parents=True,exist_ok=True);output.mkdir(parents=True,exist_ok=True)
    run('flatpak','build-init','--arch=x86_64',work,APP_ID,'org.freedesktop.Sdk','org.freedesktop.Platform','25.08')
    files=work/'files';installed=files/'share/Love2Gathering'
    shutil.copytree(payload,installed)
    shutil.copy2(PROJECT/'packaging/runtime/launcher.py',installed/'launcher.py')
    (files/'bin').mkdir(parents=True,exist_ok=True)
    wrapper=files/'bin/love2gathering'
    wrapper.write_text('#!/bin/sh\nexport LD_LIBRARY_PATH="/app/lib/love${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\nexec python3 /app/share/Love2Gathering/launcher.py "$@"\n');wrapper.chmod(0o755)
    binary=Path(shutil.which('love')or'/usr/bin/love')
    result=subprocess.run([str(binary),'--version'],check=True,capture_output=True,text=True)
    if not result.stdout.startswith('LOVE 11.5'):
        raise ValueError('Build requires the tested native LÖVE 11.5')
    target=installed/'runtime/love/bin/love';target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(binary,target)
    # Freedesktop25.08 supplies SDL2/OpenAL/FreeType/etc. These three SONAMEs
    # are absent or changed there and remain alongside their original notices.
    names=['libmodplug.so.1','libluajit-5.1.so.2','libtheoradec.so.1']
    ldd=subprocess.check_output(['ldd',str(binary)],text=True);provenance={'love':{'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'version':result.stdout.strip()},'libraries':{}}
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
    shutil.copy2(HERE/(APP_ID+'.metainfo.xml'),meta/(APP_ID+'.metainfo.xml'))
    icons=files/'share/icons/hicolor/256x256/apps';icons.mkdir(parents=True,exist_ok=True)
    shutil.copy2(installed/'share/icons/love2gathering.png',icons/(APP_ID+'.png'))
    manifest={'version':1,'files':{str(path.relative_to(installed)):hashlib.sha256(path.read_bytes()).hexdigest()for path in sorted(installed.rglob('*'))if path.is_file()and path.name!='payload-manifest.json'}}
    (installed/'payload-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    run('flatpak','build','--env=LD_LIBRARY_PATH=/app/lib/love',work,'/app/share/Love2Gathering/runtime/love/bin/love','--version')
    run('flatpak','build-finish','--command=love2gathering',*PERMISSIONS,work)
    repo=work.parent/'repo'
    run('flatpak','build-export','--arch=x86_64',repo,work,'stable')
    artifact=output/('Love2Gathering-'+version+'-x86_64.flatpak')
    run('flatpak','build-bundle','--arch=x86_64','--runtime-repo=https://flathub.org/repo/flathub.flatpakrepo',repo,artifact,APP_ID,'stable')
    (output/'flatpak-native-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
    shutil.copy2(HERE/'install-flatpak.py',output/'install-flatpak.py')
    print(artifact)
    return artifact


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--payload',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=PROJECT/'dist')
    parser.add_argument('--work',type=Path,default=PROJECT/'.runtime/flatpak-build/application')
    parser.add_argument('--version',default='2026.11.14')
    args=parser.parse_args();build(args.payload.resolve(),args.output.resolve(),args.work.resolve(),args.version)
