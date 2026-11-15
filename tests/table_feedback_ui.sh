#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-table-feedback.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
pack=${1:-"$project_dir/build/artifacts/Love2Gathering-Starter-images-2026-11-15.zip"}
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime; do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
python3 - "$pack" "$test_dir" <<'PY'
import json,sys,zipfile
from pathlib import Path
with zipfile.ZipFile(sys.argv[1])as archive:
    manifest=json.loads(archive.read('manifest.json'))
    for name,target in(('Plains','land.jpg'),('Lightning Bolt','spell.jpg')):
        entry=next(value for value in manifest['images']if value['name']==name and value['kind']in('normal','large'))
        assert entry['size']<=3*1024**2
        (Path(sys.argv[2])/target).write_bytes(archive.read(entry['path']))
PY
cp "$project_dir/tests/table_feedback_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)t.identity='love2gathering-table-feedback-tests';t.window.title='Love2Gathering table feedback presentation';t.window.width=1120;t.window.height=720;t.window.vsync=0;t.console=true;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false end
EOF
love "$test_dir"
