#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-about-ui-XXXXXX)
cp -R "$project_dir/app" "$project_dir/lib" "$project_dir/licenses" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney" "$test_dir/assets/audio/music-loop-bundle-2026-q2" "$test_dir/decks/preconstructed" "$test_dir/assets/card-backs"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$project_dir/assets/fonts/LICENSE-DejaVu.txt" "$test_dir/assets/fonts/"
cp "$project_dir/assets/audio/music-loop-bundle-2026-q2/_LICENSE.txt" "$test_dir/assets/audio/music-loop-bundle-2026-q2/"
cp "$project_dir/decks/preconstructed/LICENSE-MTGJSON.txt" "$test_dir/decks/preconstructed/"
cp "$project_dir/assets/card-backs/provenance.json" "$test_dir/assets/card-backs/"
cp "$project_dir/LICENSE" "$project_dir/CREDITS.md" "$project_dir/THIRD_PARTY_NOTICES.md" "$test_dir/"
cp "$project_dir/tests/about_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-about-tests';t.window.title='Isolated About page and in-game settings popup'
 t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
python3 - "$test_dir" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1])
(root/'build-info.json').write_text(json.dumps({'version':'2026.11.16.42','channel':'development','branch':'development','revision':'a'*40,'tag':'DEV-2026.11.16.42-1-aaaaaaaaaaaa','builtAtUTC':'2026-11-16T09:12:34Z','repository':'https://github.com/Alexayy/Love2Gathering','engineRevision':'d9b266fc981024873ac7ec5f90ee7121a060725e'}))
(root/'startup-status.json').write_text(json.dumps({'version':'724032c'}))
PY
printf '%s\n' "$test_dir"
LOVE2GATHERING_ABOUT_OUTPUT="$test_dir" LOVE2GATHERING_STARTUP_STATUS="$test_dir/startup-status.json" love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import hashlib,json,pathlib,sys
run,root=map(pathlib.Path,sys.argv[1:]);path=run/'report.json';report=json.loads(path.read_text())
files=['app/about.lua','app/build_info.lua','app/credits.lua','app/settings.lua','LICENSE','CREDITS.md','THIRD_PARTY_NOTICES.md']
report['sourceSha256']={name:hashlib.sha256((run/name).read_bytes()).hexdigest()for name in files}
report['sourceSha256']['tests/about_ui.lua']=hashlib.sha256((run/'main.lua').read_bytes()).hexdigest()
path.write_text(json.dumps(report,indent=2)+'\n');(root/'tests/about-ui-report.json').write_text(path.read_text());print('Report:',path)
PY
