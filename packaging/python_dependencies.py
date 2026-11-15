"""Checksum-pinned private wheels for shipped interpreters; never run pip."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
import uuid
import zipfile

HERE = Path(__file__).resolve().parent
MAX_WHEEL = 32 * 1024**2
MAX_UNPACKED = 128 * 1024**2


def bundle_pillow(platform, destination, cache, *, spec=None, opener=urlopen):
    """Unpack a verified ABI-specific wheel into an owned packaging stage.

    Wheel licenses and bundled JPEG/native libraries remain alongside PIL.
    The destination is private to the package, never the host site-packages.
    """
    if platform not in ('windows-cp313', 'flatpak-cp313'):
        raise ValueError('Unsupported packaged Python wheel platform')
    spec = dict(spec or json.loads((HERE/'python-wheels.lock.json').read_text())[platform])
    filename = spec.get('filename', '')
    if not re.fullmatch(r'pillow-[0-9.]+-cp313-cp313-[A-Za-z0-9_.]+\.whl', filename) or not re.fullmatch(r'[a-f0-9]{64}', spec.get('sha256', '')):
        raise ValueError('Pillow wheel lock is incomplete')
    if platform=='windows-cp313' and not filename.endswith('-win_amd64.whl') or platform=='flatpak-cp313' and 'manylinux_2_28_x86_64' not in filename:
        raise ValueError('Pillow wheel platform does not match the packaged interpreter')
    parsed = urlsplit(spec.get('url', ''))
    if parsed.scheme != 'https' or parsed.hostname != 'files.pythonhosted.org' or parsed.username or parsed.password or parsed.port not in (None, 443):
        raise ValueError('Pillow wheels must come from the pinned official PyPI file host')
    destination, cache = Path(destination), Path(cache)
    if destination.is_symlink() or destination.exists() and any(destination.iterdir()):
        raise ValueError('Pillow destination must be a new or empty private package directory')
    cache.mkdir(parents=True, exist_ok=True)
    wheel = cache/filename
    if wheel.is_symlink(): raise ValueError('Cached Pillow wheel must not be a symbolic link')
    if not wheel.exists():
        temporary = wheel.with_name('.'+wheel.name+'.'+uuid.uuid4().hex+'.part')
        try:
            request = Request(spec['url'], headers={'User-Agent':'Love2Gathering-packager/1.0'})
            with opener(request, timeout=60) as source, temporary.open('xb') as target:
                final = urlsplit(source.geturl())
                if final.scheme != 'https' or final.hostname != 'files.pythonhosted.org':
                    raise ValueError('Pillow wheel redirected outside its official file host')
                written = 0
                while True:
                    block = source.read(1024**2)
                    if not block: break
                    written += len(block)
                    if written > MAX_WHEEL: raise ValueError('Pillow wheel exceeds the packaging download limit')
                    target.write(block)
            if hashlib.sha256(temporary.read_bytes()).hexdigest() != spec['sha256']:
                raise ValueError('Pillow wheel checksum mismatch')
            os.replace(temporary, wheel)
        finally: temporary.unlink(missing_ok=True)
    if not wheel.is_file() or wheel.stat().st_size > MAX_WHEEL or hashlib.sha256(wheel.read_bytes()).hexdigest() != spec['sha256']:
        raise ValueError('Cached Pillow wheel checksum mismatch')
    with zipfile.ZipFile(wheel) as archive:
        infos = archive.infolist()
        if len(infos)>2048 or sum(info.file_size for info in infos)>MAX_UNPACKED:
            raise ValueError('Pillow wheel exceeds its extraction limits')
        names = set()
        for info in infos:
            member = PurePosixPath(info.filename)
            if info.filename in names or '\\' in info.filename or '\x00' in info.filename or member.is_absolute() or '..' in member.parts or any(':' in part for part in member.parts) or stat.S_ISLNK(info.external_attr>>16):
                raise ValueError('Pillow wheel contains an unsafe archive member')
            names.add(info.filename)
        native = any(name.startswith('PIL/_imaging.') and name.endswith('.pyd' if platform=='windows-cp313' else '.so') for name in names)
        licenses = any('.dist-info/licenses/' in name and not name.endswith('/') for name in names)
        if not {'PIL/__init__.py','PIL/Image.py'}<=names or not native or not licenses:
            raise ValueError('Pillow wheel is missing its image core or redistribution notices')
        destination.mkdir(parents=True, exist_ok=True)
        for info in infos:
            target = destination/Path(*PurePosixPath(info.filename).parts)
            if info.is_dir(): target.mkdir(parents=True, exist_ok=True);continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as source, target.open('xb') as output:
                shutil.copyfileobj(source, output, 1024**2)
    return {**spec, 'platform':platform, 'privateDirectory':str(destination.name), 'includesNativeCode':True, 'includesLicenses':True}
