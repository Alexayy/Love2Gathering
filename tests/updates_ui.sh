#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-updates-ui-XXXXXX)
output="$project_dir/build/updates-ui"
mkdir -p "$output" "$test_dir/assets/fonts" "$test_dir/assets/kenney" "$test_dir/assets/card-backs"
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/assets/card-backs/provenance.json" "$test_dir/assets/card-backs/"
cp "$project_dir/tests/updates_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-isolated-updates';t.window.title='Isolated About updater acceptance';t.window.width=1440;t.window.height=900;t.window.vsync=0
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
python3 - "$test_dir" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]);(root/'build-info.json').write_text(json.dumps(dict(version='2026.11.18.1',channel='development',branch='development',revision='a'*40,repository='https://github.com/Alexayy/Love2Gathering',engineRevision='b'*40)))
PY
LOVE2GATHERING_UPDATES_FIXTURE="$test_dir" LOVE2GATHERING_UPDATES_OUTPUT="$output" love "$test_dir"
python3 - "$project_dir" "$test_dir" "$output" <<'PY'
import hashlib,json,pathlib,sys
root,run,output=map(pathlib.Path,sys.argv[1:]);report=json.loads((output/'report.json').read_text())
files=['app/updates.lua','app/about.lua','app/model.lua','app/renderer.lua','app/view.lua','app/settings.lua','app/build_info.lua','lib/Slab/Internal/UI/Input.lua']
report['sourceSha256']={name:hashlib.sha256((run/name).read_bytes()).hexdigest()for name in files}
report['sourceSha256']['tests/updates_ui.lua']=hashlib.sha256((run/'main.lua').read_bytes()).hexdigest()
report['sourceStillMatches']=all((root/name).read_bytes()==(run/name).read_bytes()for name in files)and(root/'tests/updates_ui.lua').read_bytes()==(run/'main.lua').read_bytes()
report['fixtureDirectory']=str(run)
assert report['passed']and report['sourceStillMatches'],'Updater product sources changed during graphical acceptance'
(root/'tests/updates-ui-report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
print('Updater GUI acceptance:',len(report['checks']),'checks;',output)
PY
