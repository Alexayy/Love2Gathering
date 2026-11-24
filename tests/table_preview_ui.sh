#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
run=$(mktemp -d /tmp/love2gathering-table-preview.XXXXXX)
pack=${1:-"$root/build/artifacts/Love2Gathering-Starter-images-2026-11-15.zip"}
cp -R "$root/app" "$root/lib" "$run"
mkdir -p "$run/assets/kenney" "$run/xdg/data" "$run/xdg/config"
cp -R "$root/assets/fonts" "$root/assets/icons" "$root/assets/keyrune" "$root/assets/card-backs" "$root/assets/battlefield" "$run/assets"
for part in runtime ui particles sounds theme; do cp -R "$root/assets/kenney/$part" "$run/assets/kenney"; done
python3 - "$pack" "$run" <<'PY'
from pathlib import Path
import json
import sys
import zipfile

out = Path(sys.argv[2])
with zipfile.ZipFile(sys.argv[1]) as archive:
    entries = json.loads(archive.read('manifest.json'))['images']
    prints = {}
    for name, slug in [('Goblin Guide', 'guide'), ('Lightning Bolt', 'bolt'), ('Llanowar Elves', 'elves')]:
        scan = next(entry for entry in entries if entry['name'] == name and entry['kind'] == 'normal')
        printing = scan['printingId']
        prints[name] = printing
        for kind in ('normal', 'art_crop'):
            image = next(entry for entry in entries if entry['name'] == name and entry['kind'] == kind
                         and entry['printingId'] == printing and entry['face'] == scan['face'])
            assert archive.getinfo(image['path']).file_size <= 3 * 1024**2
            (out / (slug + '-' + kind + '.jpg')).write_bytes(archive.read(image['path']))
    (out / 'prints.json').write_text(json.dumps(prints))
PY
cp "$root/main.lua" "$run/application-main.lua"
cp "$root/tests/table_preview_ui.lua" "$run/main.lua"
cat > "$run/conf.lua" <<'LUA'
function love.conf(t)
    t.identity='love2gathering-table-preview-test'
    t.window.title='Table card preview and inspection'
    t.window.width=1120;t.window.height=720;t.window.vsync=0;t.window.resizable=true
    t.console=true;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false
end
LUA
echo "Preview test output: $run"
XDG_DATA_HOME="$run/xdg/data" XDG_CONFIG_HOME="$run/xdg/config" L2G_PREVIEW_TEST="$run" love "$run"
