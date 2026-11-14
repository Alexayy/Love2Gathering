"""Resolve one data directory for the launcher, catalog and offline utilities."""
from pathlib import Path
import os

PROJECT = Path(__file__).resolve().parents[1]


def default_data_dir(project=None, environ=None, home=None):
    env = os.environ if environ is None else environ
    user_home = Path.home() if home is None else Path(home)
    if env.get('LOVE2GATHERING_DATA_DIR'):
        return Path(env['LOVE2GATHERING_DATA_DIR']).expanduser().resolve()
    if env.get('XDG_DATA_HOME'):
        return (Path(env['XDG_DATA_HOME']).expanduser() / 'love2gathering').resolve()
    # A copied project can live on the same mounted drive as its copied saves.
    # Adopt only an existing application DB, never create a new empty store or
    # migrate/delete the old home directory as a startup side effect.
    root = Path(project or PROJECT).resolve()
    for parent in root.parents:
        if parent == Path(parent.anchor):
            break
        candidate = parent / '.local/share/love2gathering'
        if parent.is_mount() and (candidate / 'app.sqlite').is_file():
            return candidate.resolve()
    return (user_home / '.local/share/love2gathering').resolve()


if __name__ == '__main__':
    print(default_data_dir())
