#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-startup-art-XXXXXX)
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/card-backs"
cp "$project_dir/assets/card-backs/classic-magic.jpg" "$test_dir/assets/card-backs/"
cp "$project_dir/tests/startup_art.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-startup-art-tests';t.window.title='Isolated cached artwork warmup'
 t.window.width=720;t.window.height=360;t.window.vsync=0
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
printf '%s\n' "$test_dir"
LOVE2GATHERING_STARTUP_ART_OUTPUT="$test_dir" love "$test_dir"
python3 - "$test_dir" <<'PY'
import hashlib,json,pathlib,sys
run=pathlib.Path(sys.argv[1]);path=run/'report.json';report=json.loads(path.read_text())
files=['app/startup_art.lua','app/artwork.lua','app/profile.lua','app/model.lua','app/card_printings.lua','app/library.lua']
report['sourceSha256']={name:hashlib.sha256((run/name).read_bytes()).hexdigest()for name in files}
report['sourceSha256']['tests/startup_art.lua']=hashlib.sha256((run/'main.lua').read_bytes()).hexdigest()
path.write_text(json.dumps(report,indent=2)+'\n');print('Report:',path)
PY
