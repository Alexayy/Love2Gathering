#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-match-controls-ui-XXXXXX)
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime; do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/"; done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/main.lua" "$test_dir/application-main.lua"
cp "$project_dir/tests/match_controls_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-match-controls-tests';t.window.title='Isolated drag cancellation and native match controls'
 t.window.width=1120;t.window.height=720;t.window.vsync=0;t.window.resizable=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
printf '%s\n' "$test_dir"
L2G_MATCH_CONTROLS_OUTPUT="$test_dir" love "$test_dir"
python3 - "$test_dir" <<'PYREPORT'
import hashlib,json,pathlib,sys
run=pathlib.Path(sys.argv[1]);path=run/'report.json';report=json.loads(path.read_text())
sources=['application-main.lua','app/drag_cancel.lua','app/outcome.lua','app/match_ui.lua','app/renderer.lua','app/model.lua','app/rooms.lua','app/view.lua','app/assets.lua','lib/Slab/Internal/UI/Region.lua']
sources.extend(str(path.relative_to(run))for path in sorted((run/'assets/kenney/runtime').glob('*.lua')))
icon=run/'assets/kenney/runtime/icons/arrow_counterclockwise.png'
if icon.exists():sources.append(str(icon.relative_to(run)))
report['sourceSha256']={name:hashlib.sha256((run/name).read_bytes()).hexdigest() for name in sources}
report['sourceSha256']['tests/match_controls_ui.lua']=hashlib.sha256((run/'main.lua').read_bytes()).hexdigest()
path.write_text(json.dumps(report,indent=2)+'\n');print('Report:',path)
PYREPORT
