#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-preview-utf8-XXXXXX)
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
if [ -n "${LOVE2GATHERING_PREVIEW_UTF8_BASELINE:-}" ];then cp "$LOVE2GATHERING_PREVIEW_UTF8_BASELINE/app/renderer.lua" "$LOVE2GATHERING_PREVIEW_UTF8_BASELINE/app/richtext.lua" "$test_dir/app/";fi
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/preview_utf8_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-preview-utf8-tests';t.window.title='Isolated UTF-8 land choice preview'
 t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
printf '%s\n' "$test_dir"
LOVE2GATHERING_PREVIEW_UTF8_OUTPUT="$test_dir" love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import hashlib,json,pathlib,sys
run,root=map(pathlib.Path,sys.argv[1:]);path=run/'report.json';report=json.loads(path.read_text())
files=['app/utf8_text.lua','app/richtext.lua','app/renderer.lua','app/card_choices.lua']
report['sourceSha256']={name:hashlib.sha256((run/name).read_bytes()).hexdigest()for name in files};report['sourceSha256']['tests/preview_utf8_ui.lua']=hashlib.sha256((run/'main.lua').read_bytes()).hexdigest()
path.write_text(json.dumps(report,indent=2)+'\n');(root/'tests/preview-utf8-ui-report.json').write_text(path.read_text());print('Report:',path)
PY
