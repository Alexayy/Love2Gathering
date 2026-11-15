#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-startup-readiness-XXXXXX)
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/startup_readiness_ui.lua" "$test_dir/main.lua"
cp "$project_dir/main.lua" "$test_dir/application-main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-startup-readiness-tests';t.window.title='Love: 2 Gathering — isolated saved-data startup gate'
 t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
printf '%s\n' "$test_dir"
LOVE2GATHERING_STARTUP_TEST_OUTPUT="$test_dir" LOVE2GATHERING_STARTUP_STATUS="$test_dir/launcher-status.json" love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import hashlib,json,pathlib,sys
run,root=map(pathlib.Path,sys.argv[1:]);report=json.loads((run/'report.json').read_text())
report['sourceSha256']={name:hashlib.sha256((run/source).read_bytes()).hexdigest()for name,source in {'app/startup.lua':'app/startup.lua','app/preferences.lua':'app/preferences.lua','app/assets.lua':'app/assets.lua','main.lua':'application-main.lua','tests/startup_readiness_ui.lua':'main.lua','assets/kenney/runtime/loading.lua':'assets/kenney/runtime/loading.lua','assets/kenney/runtime/icons/loading_circle.png':'assets/kenney/runtime/icons/loading_circle.png'}.items()}
(root/'tests/startup-readiness-ui-report.json').write_text(json.dumps(report,indent=2)+'\n')
print('Report:',run/'report.json')
PY
