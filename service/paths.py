"""Resolve persisted and explicitly overridden database/image-cache locations."""
from pathlib import Path
import json
import os
import sqlite3

PROJECT = Path(__file__).resolve().parents[1]


def explicit_override(environ,key):
    flag=key+'_EXPLICIT'
    if flag in environ:return environ[flag]=='1'and bool(environ.get(key))
    return bool(environ.get(key)and not environ.get('LOVE2GATHERING_STORAGE_RESOLVED'))


def config_file(environ=None, home=None):
    env = os.environ if environ is None else environ
    user_home = Path.home() if home is None else Path(home)
    directory = Path(env.get('LOVE2GATHERING_CONFIG_DIR') or
                     (Path(env['XDG_CONFIG_HOME']) / 'love2gathering' if env.get('XDG_CONFIG_HOME') else user_home / '.config/love2gathering'))
    return directory.expanduser().resolve() / 'storage-paths.json'


def read_config(environ=None, home=None):
    path = config_file(environ, home)
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError) as exc:
        raise ValueError('Storage location configuration cannot be read: ' + str(path)) from exc
    if not isinstance(value, dict) or value.get('version') != 1:
        raise ValueError('Unsupported storage location configuration: ' + str(path))
    return value


def _available_location(directory, filename, label):
    location = Path(directory).expanduser().resolve()
    if not (location / filename).is_file():
        raise ValueError(label + ' is unavailable. Reconnect its drive before starting: ' + str(location))
    return location


def default_data_dir(project=None, environ=None, home=None):
    env = os.environ if environ is None else environ
    user_home = Path.home() if home is None else Path(home)
    if env.get('LOVE2GATHERING_DATA_DIR'):
        return Path(env['LOVE2GATHERING_DATA_DIR']).expanduser().resolve()
    active = read_config(env, user_home).get('active') or {}
    if active.get('databaseDirectory'):
        return _available_location(active['databaseDirectory'], 'app.sqlite', 'Saved database')
    if env.get('XDG_DATA_HOME'):
        return (Path(env['XDG_DATA_HOME']).expanduser() / 'love2gathering').resolve()
    root = Path(project or PROJECT).resolve()
    for parent in root.parents:
        if parent == Path(parent.anchor):
            break
        candidate = parent / '.local/share/love2gathering'
        if parent.is_mount() and (candidate / 'app.sqlite').is_file():
            return candidate.resolve()
    return (user_home / '.local/share/love2gathering').resolve()


def default_cache_dir(data_dir=None, environ=None, home=None, fresh_default=False):
    """None retains an existing combined DB until an explicit split migration."""
    env = os.environ if environ is None else environ
    if env.get('LOVE2GATHERING_CACHE_DIR'):
        return Path(env['LOVE2GATHERING_CACHE_DIR']).expanduser().resolve()
    active = read_config(env, home).get('active') or {}
    actual = Path(data_dir or default_data_dir(environ=env, home=home)).resolve()
    if active.get('databaseDirectory') and actual == Path(active['databaseDirectory']).resolve() and active.get('cacheDirectory'):
        return _available_location(active['cacheDirectory'], 'images.sqlite', 'Image cache')
    database=actual/'app.sqlite'
    if database.is_file():
        try:
            connection=sqlite3.connect(database.as_uri()+'?mode=ro',uri=True,timeout=2)
            try:row=connection.execute("SELECT value FROM meta WHERE key='image_cache_directory'").fetchone()
            finally:connection.close()
            if row:return _available_location(row[0], 'images.sqlite', 'Image cache')
        except sqlite3.Error:pass
    elif fresh_default:
        return actual/'cache'
    return None


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', action='store_true')
    parser.add_argument('--activate-pending', action='store_true')
    parser.add_argument('--next', action='store_true', help='Resolve the prepared next-launch location')
    args = parser.parse_args()
    if args.activate_pending:
        from storage_locations import activate_pending
        activate_pending()
    pending=read_config().get('pending')if args.next else None
    value=Path(pending['cacheDirectory'if args.cache else'databaseDirectory'])if pending else(default_cache_dir(fresh_default=True)if args.cache else default_data_dir())
    print(str(value) if value else '')
