#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-image-packs-ui-XXXXXX)
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney" "$test_dir/fixtures"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/image_packs_ui.lua" "$test_dir/main.lua"
cp "$project_dir/main.lua" "$test_dir/application-main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-image-packs-ui-tests';t.window.title='Isolated Starter image pack workflow'
 t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
python3 - "$test_dir" <<'PY'
import pathlib,sys,zipfile
root=pathlib.Path(sys.argv[1]);print(root,flush=True)
for name in ('starter.zip','previous.zip','broken.zip'):
 with zipfile.ZipFile(root/'fixtures'/name,'w')as f:f.writestr('fixture.json','{"scope":"File picker only; service validation is mocked"}')
PY
LOVE2GATHERING_IMAGE_PACK_UI_OUTPUT="$test_dir" love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import hashlib,json,pathlib,sys
run,root=map(pathlib.Path,sys.argv[1:]);path=run/'report.json';report=json.loads(path.read_text())
files=['app/image_packs.lua','app/settings.lua','app/model.lua','app/view.lua','app/renderer.lua']
report['sourceSha256']={name:hashlib.sha256((run/name).read_bytes()).hexdigest()for name in files}
report['sourceSha256']['tests/image_packs_ui.lua']=hashlib.sha256((run/'main.lua').read_bytes()).hexdigest()
report['sourceSha256']['main.lua']=hashlib.sha256((run/'application-main.lua').read_bytes()).hexdigest()
path.write_text(json.dumps(report,indent=2)+'\n');(root/'tests/image-packs-ui-report.json').write_text(path.read_text());print('Report:',path)
PY
