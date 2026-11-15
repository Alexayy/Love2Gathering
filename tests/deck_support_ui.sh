#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${1:?Provide an already-cached genuine Anikthea normal JPEG; no acquisition is performed}"
test_dir=$(mktemp -d /tmp/love2gathering-deck-support-ui-XXXXXX)
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$1" "$test_dir/anikthea-normal.jpg";cp "$project_dir/tests/deck_support_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)t.identity='love2gathering-deck-support-tests';t.window.title='Isolated collection support';t.window.width=1440;t.window.height=900;t.window.vsync=0;t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true end
CONF
printf '%s\n' "$test_dir"
LOVE2GATHERING_SUPPORT_OUTPUT="$test_dir" love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import pathlib,json,hashlib,sys
run,root=map(pathlib.Path,sys.argv[1:]);report=json.loads((run/'report.json').read_text());files=['app/collection.lua','app/collection_ui.lua','app/deck_picker.lua','app/deck_support.lua','app/deck_support_ui.lua','app/set_icons.lua','assets/keyrune/sets.lua','app/card_printings.lua']
report['sourceSha256']={p:hashlib.sha256((run/p).read_bytes()).hexdigest()for p in files};(run/'report.json').write_text(json.dumps(report,indent=2)+'\n');(root/'tests/deck-support-ui-report.json').write_text((run/'report.json').read_text());print(run/'report.json')
PY
