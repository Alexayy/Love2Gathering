#!/bin/sh
set -eu
: "${LOVE2GATHERING_CATALOG_PORT:?Set a ready isolated catalog with gallery metadata and cached JPEG artwork}"
export LOVE2GATHERING_CATALOG_PORT
python3 - <<'PY'
import json,os,pathlib,urllib.request
with urllib.request.urlopen('http://127.0.0.1:'+os.environ['LOVE2GATHERING_CATALOG_PORT']+'/health',timeout=10)as response:health=json.load(response)
if os.environ.get('LOVE2GATHERING_GALLERY_EXPECT_UNAVAILABLE'):
    assert not health['ready'], 'Unavailable-source acceptance needs a missing-source catalog'
else:
    assert health['ready'], 'Gallery acceptance requires an indexed fixture catalog'
assert pathlib.Path('/tmp') in pathlib.Path(health['storage']['dataDirectory']).resolve().parents, 'Use a temporary user-data directory'
PY
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-gallery-ui.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/gallery_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)
    t.identity='love2gathering-gallery-ui-tests';t.window.title='Love: 2 Gathering — artwork gallery acceptance'
    t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
    t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
EOF
cp -R "$project_dir/assets/kenney/runtime" "$test_dir/assets/kenney/"
cp "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
LOVE2GATHERING_ENGINE_PORT=17495 love "$test_dir"
