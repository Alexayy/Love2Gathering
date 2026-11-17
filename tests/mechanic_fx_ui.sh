#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-mechanic-vfx.XXXXXX)
output=${LOVE2GATHERING_VFX_OUTPUT:-"$project_dir/build/presentation-vfx"}
report_file=${LOVE2GATHERING_VFX_REPORT:-"$project_dir/tests/mechanic-vfx-ui-report.json"}
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney" "$output"
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/mechanic_fx_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-mechanic-vfx-tests';t.window.title='Synthetic mechanic/VFX acceptance';t.window.width=1920;t.window.height=1080;t.window.vsync=0
 t.modules.audio=false;t.modules.joystick=false;t.modules.physics=false;t.console=true
end
CONF
native_before="$project_dir/build/table-overhaul/zone-actions/wipe-before.json"
native_after="$project_dir/build/table-overhaul/zone-actions/wipe-after.json"
if [ -f "$native_before" ] && [ -f "$native_after" ];then
 export LOVE2GATHERING_VFX_NATIVE_BEFORE="$native_before"
 export LOVE2GATHERING_VFX_NATIVE_AFTER="$native_after"
fi
LOVE2GATHERING_VFX_OUTPUT="$output" love "$test_dir"
python3 - "$project_dir" "$output" "$report_file" <<'PY'
import hashlib,json,pathlib,sys
root,output,report_file=map(pathlib.Path,sys.argv[1:]);report=json.loads((output/'report.json').read_text())
assert report['passed']
report['sourceSha256']={name:hashlib.sha256((root/name).read_bytes()).hexdigest()for name in ('app/mechanic_fx.lua','app/board_fx.lua','tests/mechanic_fx_ui.lua')}
report['captures']={name:str(output/(name+'.png'))for name in ('profiles','events','crowded')}
if report.get('nativeWipe'):
 report['captures']['native-wipe']=str(output/'native-wipe.png')
 report['nativeWipe']['sourceSha256']={name:hashlib.sha256(pathlib.Path(report['nativeWipe'][name]).read_bytes()).hexdigest()for name in ('sourceBefore','sourceAfter')}
report_file.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report['performance'],indent=2))
PY
