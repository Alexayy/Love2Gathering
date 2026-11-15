#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-navigation-builder.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme runtime;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/navigation_builder_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)
 t.identity='love2gathering-navigation-builder-tests';t.window.title='Love: 2 Gathering — navigation and split acceptance'
 t.window.width=1120;t.window.height=720;t.window.vsync=0;t.window.resizable=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
CONF
LOVE2GATHERING_CATALOG_PORT=17499 LOVE2GATHERING_ENGINE_PORT=17498 LOVE2GATHERING_ROOM_PORT=17497 love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import hashlib,json,pathlib,sys
run,root=map(pathlib.Path,sys.argv[1:]);report=json.loads(pathlib.Path('/tmp/love2gathering-navigation-builder-report.json').read_text())
names=['app/navigation.lua','app/renderer.lua','app/view.lua','app/builder.lua','app/builder_simplified.lua','app/collection_ui.lua','app/lobby_ui.lua','app/replay_ui.lua','app/multiplayer_table.lua','tests/navigation_builder_ui.lua']
report['sourceSha256']={p:hashlib.sha256((run/('main.lua'if p=='tests/navigation_builder_ui.lua'else p)).read_bytes()).hexdigest()for p in names}
(root/'tests/navigation-builder-ui-report.json').write_text(json.dumps(report,indent=2)+'\n')
PY
