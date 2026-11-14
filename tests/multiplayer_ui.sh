#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-multiplayer-ui.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$project_dir/assets/kenney" "$test_dir/assets/"
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/multiplayer_ui.lua" "$test_dir/main.lua"
# Optional actual engine projections captured by native acceptance, kept outside
# the repository. They supplement (and never relabel) the synthetic UI fixtures.
if [ "$#" -ge 1 ]; then cp "$1" "$test_dir/native-four.json"; fi
if [ "$#" -ge 2 ]; then cp "$2" "$test_dir/native-six.json"; fi
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)
    t.identity='love2gathering-multiplayer-ui-tests';t.window.title='Love: 2 Gathering — multiplayer presentation tests'
    t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
    t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
EOF
cp "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
love "$test_dir"
