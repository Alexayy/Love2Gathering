#!/usr/bin/env python3
"""Installed, relocatable supervisor. All generated files live outside the payload."""
from __future__ import annotations
import argparse
import json
import os
import re
from pathlib import Path
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from urllib.request import Request, urlopen

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent
WINDOWS = os.name == 'nt'


def image_dependency(required=False):
    try:
        from PIL import Image, features, __version__
        if not features.check_codec('jpg'): raise ImportError('Pillow was built without JPEG support')
        if tuple(int(part)for part in __version__.split('.')[:2]) < (9,1):
            raise ImportError('Pillow 9.1 or newer is required')
        return {'available':True,'pillow':__version__,'jpeg':True}
    except (ImportError, OSError, ValueError) as exc:
        message='Small card images are unavailable. Install Pillow with JPEG support (python3-pil on Debian/Ubuntu, python3-pillow on RPM systems); original card images remain available.'
        if required: raise RuntimeError(message) from exc
        print(message,file=sys.stderr,flush=True)
        return {'available':False,'jpeg':False}


def runtime(name):
    suffix = '.exe' if WINDOWS else ''
    relative = {'java': 'runtime/java/bin/java' + suffix,
                'love': 'runtime/love/' + ('love.exe' if WINDOWS else 'bin/love')}[name]
    bundled = ROOT / relative
    if bundled.is_file():
        return str(bundled)
    found = shutil.which(name)
    if not found:
        raise RuntimeError('Missing runtime: ' + name + '. Reinstall the complete package.')
    return found


def health(port):
    try:
        with urlopen('http://127.0.0.1:' + str(port) + '/health', timeout=1) as response:
            return json.load(response)
    except (OSError, ValueError):
        return None


def free_port(preferred, excluded):
    if not 1024 <= preferred <= 65400:
        raise ValueError('Service ports must be between 1024 and 65400')
    for port in range(preferred, preferred + 100):
        if port in excluded:
            continue
        with socket.socket() as listener:
            try:
                listener.bind(('127.0.0.1', port))
            except OSError:
                continue
        return port
    raise RuntimeError('No available local service port')


def status(path, stage, progress, message, state='loading'):
    try:
        previous = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        previous = {}
    checks = previous.get('checks', [])
    for check in checks:
        if check.get('state') == 'loading':
            check['state'] = 'ready'
    item = next((item for item in checks if item.get('stage') == stage), None)
    update = {'stage': stage, 'state': state, 'message': message}
    if item:
        item.update(update)
    else:
        checks.append(update)
    try:
        release = json.loads((ROOT / 'release.json').read_text(encoding='utf-8'))
    except (OSError, ValueError):
        release = {}
    value = {'state': state, 'stage': stage, 'message': message, 'progress': progress,
             'checks': checks, 'version': release.get('version', 'installed build')}
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value), encoding='utf-8')
    os.replace(temporary, path)


def main(argv=None):
    def stop_signal(*_):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop_signal)
    parser = argparse.ArgumentParser(description='Love: 2 Gathering — installed desktop launcher')
    parser.add_argument('--services-only', action='store_true', help='Run the owned local services without a desktop')
    parser.add_argument('--check', action='store_true', help='Check packaged files and runtime versions, without opening storage')
    parser.add_argument('--checkhealth', action='store_true', help='Start owned local services, verify readiness, then stop them')
    parser.add_argument('--startup-timeout', type=int, default=180, help=argparse.SUPPRESS)
    args, desktop_args = parser.parse_known_args(argv)
    image_support=image_dependency(required=args.check)
    if WINDOWS:
        os.environ.setdefault('XDG_DATA_HOME', os.environ.get('LOCALAPPDATA', str(Path.home() / 'AppData/Local')))
        os.environ.setdefault('LOVE2GATHERING_CONFIG_DIR', str(Path(os.environ.get('APPDATA', str(Path.home() / 'AppData/Roaming'))) / 'Love2Gathering'))
    sys.path.insert(0, str(ROOT / 'service'))
    from paths import default_data_dir, default_cache_dir
    from storage_locations import activate_pending
    love = runtime('love')
    java = runtime('java')
    source = Path(os.environ.get('LOVE2GATHERING_CATALOG_SOURCE', str(ROOT / 'assets/all-cards.jsonl.gz')))
    jar = ROOT / 'bridge/target/xmage-bridge-1.0.0.jar'
    required = [ROOT / 'app.love', source, jar, ROOT / 'service/server.py', ROOT / 'service/rooms.py', ROOT / 'scripts/download-card-images.py']
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise RuntimeError('The installed package is incomplete: ' + ', '.join(missing))
    flags = subprocess.CREATE_NO_WINDOW if WINDOWS else 0
    if args.check:
        java_version = subprocess.run([java, '-version'], capture_output=True, text=True, creationflags=flags)
        love_console = str(Path(love).with_name('lovec.exe')) if WINDOWS else love
        love_version = subprocess.run([love_console, '--version'], capture_output=True, text=True, creationflags=flags)
        java_text=java_version.stderr+'\n'+java_version.stdout
        java_line=next((line for line in java_text.splitlines()if re.search(r'version "21(?:\.|\")',line)),None)
        if java_version.returncode or love_version.returncode or not java_line or not love_version.stdout.startswith('LOVE 11.5'):
            raise RuntimeError('A packaged runtime could not start')
        print(json.dumps({'passed': True, 'root': str(ROOT), 'java': java_line, 'love': love_version.stdout.strip(), 'python': sys.version.split()[0], 'images':image_support}))
        return 0

    base = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'love2gathering'
    session = base / 'runtime' / ('session-' + str(os.getpid()) + '-' + secrets.token_hex(4))
    session.mkdir(parents=True, exist_ok=False)
    progress_file = session / 'startup.json'
    env = os.environ.copy()
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    ports = {}
    for key, default in [('CATALOG', 17370), ('ENGINE', 17371), ('ROOM', 17380)]:
        ports[key] = free_port(int(env.get('LOVE2GATHERING_' + key + '_PORT', default)), ports.values())
        env['LOVE2GATHERING_' + key + '_PORT'] = str(ports[key])
    env['LOVE2GATHERING_STARTUP_STATUS'] = str(progress_file)
    env['LOVE2GATHERING_CATALOG_SOURCE'] = str(source)
    env['LOVE2GATHERING_COORDINATOR_TOKEN'] = secrets.token_urlsafe(32)
    children = []
    logs = []
    desktop = None
    engine = None
    status(progress_file, 'dependencies', .03, 'Checking installed runtimes')

    def start(command, name, cwd=ROOT):
        stream = (session / (name + '.log')).open('w', encoding='utf-8')
        logs.append(stream)
        child = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT, creationflags=flags)
        children.append(child)
        return child

    def wait_service(key, child, timeout=45, ready=False):
        until = time.monotonic() + timeout
        while time.monotonic() < until:
            if desktop is not None and desktop.poll() is not None:
                raise InterruptedError('Desktop closed')
            if child.poll() is not None:
                raise RuntimeError(key.title() + ' stopped. See ' + str(session / (key.lower() + '.log')))
            result = health(ports[key])
            if result and key=='CATALOG'and result.get('apiVersion',0)<14:
                raise RuntimeError('The catalog runtime is outdated. Reinstall the complete matching client package.')
            if result and (not ready or result.get('ready')):
                return result
            time.sleep(.2)
        raise RuntimeError(key.title() + ' did not become ready. Logs: ' + str(session))

    try:
        if not args.services_only and not args.checkhealth:
            desktop = start([love, str(ROOT / 'app.love'), *desktop_args], 'desktop')
        status(progress_file, 'storage', .12, 'Checking saved database and image-cache locations')
        activate_pending()
        data = default_data_dir()
        cache = default_cache_dir(data, fresh_default=True)
        env['LOVE2GATHERING_DATA_DIR'] = str(data)
        if cache is not None:
            env['LOVE2GATHERING_CACHE_DIR'] = str(cache)
        else:
            env.pop('LOVE2GATHERING_CACHE_DIR', None)
        env['LOVE2GATHERING_DATA_DIR_EXPLICIT'] = '1' if os.environ.get('LOVE2GATHERING_DATA_DIR') else '0'
        env['LOVE2GATHERING_CACHE_DIR_EXPLICIT'] = '1' if os.environ.get('LOVE2GATHERING_CACHE_DIR') else '0'
        env['LOVE2GATHERING_STORAGE_RESOLVED'] = '1'
        data.mkdir(parents=True, exist_ok=True)
        status(progress_file, 'version', .22, 'Checking the installed release and prebuilt bridge')
        status(progress_file, 'assets', .30, 'Preparing curated graphics and local card metadata')
        status(progress_file, 'catalog', .40, 'Starting the local catalog')
        catalog = start([sys.executable, '-B', str(ROOT / 'service/server.py'), '--port', str(ports['CATALOG']), '--source', str(source), '--database', str(data / 'catalog/catalog.sqlite'), '--data-dir', str(data)], 'catalog')
        wait_service('CATALOG', catalog)
        status(progress_file, 'build', .57, 'Verified prebuilt pinned XMage bridge')
        status(progress_file, 'bridge', .66, 'Starting XMage')
        engine_dir = data / 'engine' / str(ports['ENGINE'])
        engine_dir.mkdir(parents=True, exist_ok=True)
        engine = start([java, '-Xms128m', '-Xmx2g', '-Djava.awt.headless=true', '-Djava.net.preferIPv4Stack=true', '-Dlove2gathering.root=' + str(ROOT), '-cp', str(jar) + os.pathsep + str(ROOT / 'bridge/target/lib/*'), 'love2gathering.EngineBridge', str(ports['ENGINE'])], 'engine', engine_dir)
        wait_service('ENGINE', engine)
        status(progress_file, 'rooms', .85, 'Starting private room and draft services')
        room = start([sys.executable, '-B', str(ROOT / 'service/rooms.py'), '--port', str(ports['ROOM']), '--catalog-port', str(ports['CATALOG']), '--engine-port', str(ports['ENGINE'])], 'room')
        wait_service('ROOM', room)
        status(progress_file, 'ready', 1, 'Local services are ready', 'ready')
        if args.checkhealth:
            result = wait_service('CATALOG', catalog, args.startup_timeout, ready=True)
            print(json.dumps({'passed': True, 'ports': ports, 'catalog': result, 'engine': health(ports['ENGINE']), 'room': health(ports['ROOM']), 'logs': str(session)}))
            return 0
        if desktop is not None:
            return desktop.wait()
        print('Local services are ready. Press Ctrl+C to stop this instance.', flush=True)
        print(json.dumps({'ports': ports, 'logs': str(session)}), flush=True)
        while all(child.poll() is None for child in children):
            time.sleep(.5)
        raise RuntimeError('A local service stopped; inspect ' + str(session))
    except InterruptedError:
        return desktop.returncode if desktop is not None else 0
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        status(progress_file, 'storage' if isinstance(exc, ValueError) else 'error', 0, str(exc), 'error')
        print(str(exc), file=sys.stderr, flush=True)
        if desktop is not None and desktop.poll() is None:
            desktop.wait()
        return 1
    finally:
        if engine is not None and engine.poll() is None:
            try:
                request = Request('http://127.0.0.1:' + str(ports['ENGINE']) + '/session/stop', data=b'{}', headers={'Content-Type': 'application/json'})
                with urlopen(request, timeout=9) as response:
                    response.read()
            except OSError:
                pass
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5)
        for stream in logs:
            stream.close()


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as exc:
        if WINDOWS:
            import ctypes
            ctypes.windll.user32.MessageBoxW(None, str(exc), 'Love: 2 Gathering — installation error', 0x10)
        else:
            print(str(exc), file=sys.stderr)
        raise SystemExit(1)
