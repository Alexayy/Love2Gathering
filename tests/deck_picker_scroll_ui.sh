#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-deck-scroll-ui-XXXXXX)
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
python3 - "$project_dir/build/artifacts/Love2Gathering-Starter-images-2026-11-15.zip" "$test_dir" <<'PY'
import json,pathlib,sys,zipfile
with zipfile.ZipFile(sys.argv[1])as archive:
    manifest=json.loads(archive.read('manifest.json'))
    entry=next(v for v in manifest['images']if v['name']=='Forest'and v['kind']in('normal','large'))
    (pathlib.Path(sys.argv[2])/'land.jpg').write_bytes(archive.read(entry['path']))
PY
cp "$project_dir/tests/deck_picker_scroll_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)t.identity='love2gathering-deck-scroll-tests';t.window.title='Isolated deck scroll';t.window.width=1440;t.window.height=900;t.window.vsync=0;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true end
CONF
printf '%s\n' "$test_dir"
LOVE2GATHERING_DECK_SCROLL_OUTPUT="$test_dir" love "$test_dir"
cp "$test_dir/report.json" "$project_dir/tests/deck-picker-scroll-ui-report.json"
