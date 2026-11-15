#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-choice-panels-ui-XXXXXX)
native_dir=${1:-}
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney" "$test_dir/assets/card-backs"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/assets/card-backs/classic-magic.jpg" "$test_dir/assets/card-backs/"
cp "$project_dir/main.lua" "$test_dir/application-main.lua";cp "$project_dir/tests/choice_panels_ui.lua" "$test_dir/main.lua"
if [ -n "$native_dir" ];then
 cp "$native_dir/individual-attacker.json" "$test_dir/native-attackers.json";cp "$native_dir/combat-damage.json" "$test_dir/native-damage.json"
 if [ -f "$native_dir/land-search.json" ];then cp "$native_dir/land-search.json" "$test_dir/native-land-search.json";fi
fi
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-choice-panels-tests';t.window.title='Isolated native-choice presentation and zone grids'
 t.window.width=1120;t.window.height=720;t.window.vsync=0;t.window.resizable=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
printf '%s\n' "$test_dir"
L2G_CHOICE_PANELS_OUTPUT="$test_dir" love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import hashlib,json,pathlib,sys
run,root=map(pathlib.Path,sys.argv[1:]);path=run/'report.json';report=json.loads(path.read_text())
files=['app/card_choices.lua','app/combat_choices.lua','app/zone_ui.lua','app/view.lua','app/match_ui.lua','app/card_presentation.lua','app/renderer.lua']
report['sourceSha256']={name:hashlib.sha256((run/name).read_bytes()).hexdigest()for name in files}
report['sourceSha256']['main.lua']=hashlib.sha256((run/'application-main.lua').read_bytes()).hexdigest();report['sourceSha256']['tests/choice_panels_ui.lua']=hashlib.sha256((run/'main.lua').read_bytes()).hexdigest()
report['nativeFrameSha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in run.glob('native-*.json')}
path.write_text(json.dumps(report,indent=2)+'\n');(root/'tests/choice-panels-ui-report.json').write_text(path.read_text());print('Report:',path)
PY
