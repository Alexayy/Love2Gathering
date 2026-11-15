#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
native_scene=${1:?Supply the exported native Courser playable-top JSON projection}
test_dir=$(mktemp -d /tmp/love2gathering-library-top-ui-XXXXXX)
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$native_scene" "$test_dir/native-scene.json"
cp "$project_dir/tests/library_top_ui.lua" "$test_dir/main.lua";cp "$project_dir/main.lua" "$test_dir/application-main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-library-top-tests';t.window.title='Isolated native library-top presentation'
 t.window.width=1120;t.window.height=720;t.window.vsync=0;t.window.resizable=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
printf '%s\n' "$test_dir"
L2G_LIBRARY_TOP_OUTPUT="$test_dir" love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import hashlib,json,pathlib,sys
run,root=map(pathlib.Path,sys.argv[1:]);path=run/'report.json';report=json.loads(path.read_text())
files=['app/table.lua','app/multiplayer_table.lua','app/renderer.lua','app/model.lua','app/view.lua','app/layout.lua','app/match_ui.lua']
report['sourceSha256']={name:hashlib.sha256((run/name).read_bytes()).hexdigest()for name in files}
report['sourceSha256']['tests/library_top_ui.lua']=hashlib.sha256((run/'main.lua').read_bytes()).hexdigest();report['sourceSha256']['main.lua']=hashlib.sha256((run/'application-main.lua').read_bytes()).hexdigest()
report['nativeSceneSha256']=hashlib.sha256((run/'native-scene.json').read_bytes()).hexdigest()
path.write_text(json.dumps(report,indent=2)+'\n');(root/'tests/library-top-ui-report.json').write_text(path.read_text());print('Report:',path)
PY
