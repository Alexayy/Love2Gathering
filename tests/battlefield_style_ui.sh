#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
run=$(mktemp -d /tmp/love2gathering-battlefield-style.XXXXXX)
pack=${1:-"$root/build/artifacts/Love2Gathering-Starter-images-2026-11-15.zip"}
out=${2:-"$root/build/table-style"}
test -r "$pack"
mkdir -p "$run/assets/kenney" "$run/xdg/data" "$run/xdg/config" "$out"
cp -R "$root/app" "$root/lib" "$run"
cp -R "$root/assets/fonts" "$root/assets/icons" "$root/assets/keyrune" "$root/assets/card-backs" "$run/assets"
cp -R "$root/assets/battlefield" "$run/assets"
for part in runtime ui particles sounds theme; do cp -R "$root/assets/kenney/$part" "$run/assets/kenney"; done
ln "$pack" "$run/scans.zip" 2>/dev/null || cp "$pack" "$run/scans.zip"
if [ -n "${3:-}" ]; then
    cp "$3/duplicate-islands-before.json" "$3/duplicate-islands-after-tap.json" "$run/"
fi
# Optional read-only image cache for the three cards outside the Starter pack.
if [ -n "${4:-}" ]; then
    python3 - "$4" "$run" <<'PY'
import json
from pathlib import Path
import sqlite3
import sys

cache = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2])
prints = {
    'Sandwurm Convergence': '18c3358a-96d2-4b7c-85e8-e641ef86cedc',
    'Opalescence': '1a2f4972-8987-4349-953d-1e5c71368b08',
    'Invasion of Gobakhan': '11798730-6788-4e0b-a828-b46cab1a4fa7',
}
manifest = []
with sqlite3.connect(cache.as_uri() + '?mode=ro&immutable=1', uri=True) as db:
    for name, printing in prints.items():
        for kind in ('art_crop', 'normal'):
            key = f'{printing}-0-{kind}.jpg'
            row = db.execute('SELECT metadata, content FROM art_cache WHERE cache_key=?',(key,)).fetchone()
            if row is None:
                continue
            meta = json.loads(row[0])
            assert meta['name'] == name and meta['printingId'] == printing and meta['kind'] == kind
            assert 0 < len(row[1]) < 4 * 1024**2
            (out / key).write_bytes(row[1])
            manifest.append(dict(meta, path=key))
(out / 'extra-prints.json').write_text(json.dumps(manifest))
PY
fi
cp "$root/main.lua" "$run/application-main.lua"
cp "$root/tests/battlefield_style_ui.lua" "$run/main.lua"
cat > "$run/conf.lua" <<'LUA'
function love.conf(t)
    t.identity='love2gathering-battlefield-style'
    t.window.title='Battlefield'
    t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
    t.console=true;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false
end
LUA
if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}${SDL_VIDEODRIVER:-}" ]; then
    export SDL_VIDEODRIVER=offscreen EGL_PLATFORM=surfaceless LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null
fi
echo "Battlefield fixture: $run"
XDG_DATA_HOME="$run/xdg/data" XDG_CONFIG_HOME="$run/xdg/config" L2G_STYLE_OUTPUT="$run" love "$run"
cp "$run"/*.png "$run/report.json" "$out/"
echo "Battlefield screenshots and checks: $out"
