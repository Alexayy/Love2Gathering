#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-global-controls.XXXXXX)
trap 'python3 -c '\''import pathlib,shutil,sys;p=pathlib.Path(sys.argv[1]);assert p.parent==pathlib.Path("/tmp") and p.name.startswith("love2gathering-global-controls.");shutil.rmtree(p)'\'' "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/global_controls_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-global-controls-tests';t.window.title='Love: 2 Gathering — global typography and controls'
 t.window.width=2560;t.window.height=1080;t.window.vsync=0;t.window.resizable=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
LOVE2GATHERING_CATALOG_PORT=17499 LOVE2GATHERING_ENGINE_PORT=17498 LOVE2GATHERING_ROOM_PORT=17497 love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import json,hashlib,pathlib,sys
run,root=map(pathlib.Path,sys.argv[1:]);r=json.loads(pathlib.Path('/tmp/love2gathering-global-controls-ui-report.json').read_text())
files=list((run/'app').glob('*.lua'))+list((run/'lib/Slab').rglob('*.lua'))+list((run/'assets/kenney/runtime').rglob('*'))+[run/'main.lua']
r['sourceSha256']={('tests/global_controls_ui.lua'if p==run/'main.lua'else str(p.relative_to(run))):hashlib.sha256(p.read_bytes()).hexdigest()for p in files if p.is_file()}
(root/'tests/global-controls-ui-report.json').write_text(json.dumps(r,indent=2)+'\n')
PY
