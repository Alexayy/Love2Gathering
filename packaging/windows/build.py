#!/usr/bin/env python3
"""Build an offline Windows x64 installer using checksum-pinned official runtimes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import zipfile

PROJECT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(PROJECT/'packaging'))
from python_dependencies import bundle_pillow


def compile_nsis(tool, arguments):
    env = os.environ.copy()
    adjacent = tool.parent.parent / 'share/nsis'
    if adjacent.is_dir():
        env['NSISDIR'] = str(adjacent)
    subprocess.run([str(tool), '-V2', *arguments], env=env, check=True)


def build(payload, output, cache, makensis, version):
    output.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    stage = output / 'stage/windows/Love2Gathering'
    if stage.exists():
        shutil.rmtree(stage)
    shutil.copytree(payload, stage)
    # The common payload has no platform interpreter. Never ship a Linux JRE in Windows.
    if (stage / 'runtime').exists():
        shutil.rmtree(stage / 'runtime')
    lock = json.loads((HERE / 'runtimes.lock.json').read_text())
    for name, spec in lock.items():
        archive = cache / spec['filename']
        if not archive.exists():
            request = urllib.request.Request(spec['url'], headers={'User-Agent': 'Love2Gathering-packager/1.0'})
            temporary = archive.with_suffix('.part')
            with urllib.request.urlopen(request, timeout=60) as source, temporary.open('wb') as target:
                shutil.copyfileobj(source, target)
            os.replace(temporary, archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != spec['sha256']:
            raise ValueError('Runtime checksum mismatch: ' + str(archive))
        destination = stage / 'runtime' / name
        destination.mkdir(parents=True)
        if name == 'mesa':
            extractor = shutil.which('7z') or shutil.which('7zz') or shutil.which('7za')
            if not extractor:
                raise RuntimeError('7-Zip is required to bundle the Windows software OpenGL runtime')
            subprocess.run([extractor, 'e', '-y', '-o' + str(destination), str(archive), *spec['files']],
                           check=True, stdout=subprocess.DEVNULL)
            if not all((destination / member).is_file() for member in spec['files']):
                raise RuntimeError('The Mesa archive lacks its pinned OpenGL runtime')
            shutil.copytree(HERE / 'licenses', destination / 'licenses')
            continue
        with zipfile.ZipFile(archive) as zipped:
            names = [name for name in zipped.namelist() if name and not name.endswith('/')]
            top = names[0].split('/')[0] + '/' if name != 'python' else ''
            for member in zipped.infolist():
                relative = member.filename[len(top):] if top and member.filename.startswith(top) else member.filename
                target = destination / relative
                if not relative or member.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                if '..' in Path(relative).parts or Path(relative).is_absolute():
                    raise ValueError('Unsafe runtime archive member')
                target.parent.mkdir(parents=True, exist_ok=True)
                with zipped.open(member) as source, target.open('wb') as outgoing:
                    shutil.copyfileobj(source, outgoing)
    if not lock['python']['version'].startswith('3.13.'):
        raise ValueError('Update the pinned Pillow ABI wheel before changing the embedded Python minor version')
    pillow = bundle_pillow('windows-cp313', stage/'runtime/python/Lib/site-packages', cache)
    # CPython's embeddable isolation permits only these fixed installed paths.
    pth = next((stage / 'runtime/python').glob('python*._pth'))
    text = pth.read_text()
    pth.write_text(text + '\nLib/site-packages\n../..\n../../service\n', encoding='utf-8')
    lock['pillow'] = pillow
    shutil.copy2(PROJECT / 'packaging/runtime/launcher.py', stage / 'launcher.py')
    shutil.copy2(PROJECT / 'packaging/runtime/windows_graphics.py', stage / 'windows_graphics.py')
    icon = output / 'love2gathering.ico'
    image = stage / 'share/icons/love2gathering.png'
    if image.exists():
        from PIL import Image
        Image.open(image).convert('RGBA').save(icon, sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    else:
        raise ValueError('Packaged icon is missing')
    launcher = stage / 'Love2Gathering.exe'
    compile_nsis(makensis, ['-DOUTPUT=' + str(launcher), '-DICON=' + str(icon), str(HERE / 'launcher.nsi')])
    manifest={'version':1,'files':{str(path.relative_to(stage)):hashlib.sha256(path.read_bytes()).hexdigest()for path in sorted(stage.rglob('*'))if path.is_file()and path.name!='payload-manifest.json'}}
    (stage/'payload-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    remove = output / 'windows-remove-files.nsh'
    files = sorted(path for path in stage.rglob('*') if path.is_file())
    directories = sorted((path for path in stage.rglob('*') if path.is_dir()), key=lambda path: len(path.parts), reverse=True)
    def escape(path):
        return str(path.relative_to(stage)).replace('/', '\\').replace('$', '$$').replace('"', '$\\"')
    remove.write_text('\n'.join(['Delete "$INSTDIR\\' + escape(path) + '"' for path in files] + ['RMDir "$INSTDIR\\' + escape(path) + '"' for path in directories]) + '\n')
    target = output / ('Love2Gathering-' + version + '-windows-x64-setup.exe')
    compile_nsis(makensis, ['-DPAYLOAD=' + str(stage), '-DOUTPUT=' + str(target), '-DREMOVE_LIST=' + str(remove), '-DICON=' + str(icon), '-DVERSION=' + version, str(HERE / 'installer.nsi')])
    (output / 'windows-runtime-provenance.json').write_text(json.dumps(lock, indent=2) + '\n')
    print(target)
    return target


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--payload', type=Path, required=True)
    p.add_argument('--output', type=Path, default=PROJECT / 'dist')
    p.add_argument('--cache', type=Path, default=PROJECT / '.tools/packaging-platform/downloads')
    p.add_argument('--makensis', type=Path, default=Path(shutil.which('makensis') or PROJECT / '.tools/packaging-platform/nsis/usr/bin/makensis'))
    p.add_argument('--version', default='2026.11.14')
    args = p.parse_args()
    build(args.payload.resolve(), args.output.resolve(), args.cache.resolve(), args.makensis.resolve(), args.version)
