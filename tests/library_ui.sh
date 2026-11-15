#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-library-ui.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$test_dir/assets/fonts/"
cp "$project_dir/tests/library_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)
    t.identity='love2gathering-library-ui-tests';t.window.title='Love: 2 Gathering — library acceptance';t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
    t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
EOF
cp -R "$project_dir/assets/kenney/runtime" "$test_dir/assets/kenney/"
cp "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
love "$test_dir"
python3 - "$test_dir" "$project_dir" <<'PY'
import hashlib,json,pathlib,sys
run,root=map(pathlib.Path,sys.argv[1:])
report=json.loads(pathlib.Path('/tmp/love2gathering-library-ui-report.json').read_text())
files=['app/library.lua','app/library_ui.lua','app/token_art_ui.lua','app/assets.lua','app/theme.lua','app/fonts.lua','lib/Slab/Internal/UI/Tooltip.lua','lib/Slab/Internal/UI/ComboBox.lua','lib/Slab/Internal/UI/Window.lua','lib/Slab/Internal/Core/Cursor.lua','lib/Slab/Internal/Core/DrawCommands.lua']
report['sourceSha256']={p:hashlib.sha256((run/p).read_bytes()).hexdigest()for p in files}
report['sourceSha256']['tests/library_ui.lua']=hashlib.sha256((run/'main.lua').read_bytes()).hexdigest()
report['captures']=['/tmp/love2gathering-library-'+p+'.png'for p in ['tokens-1440','token-grid-1440','token-random-all','tokens-1120','token-grid-1120']]
(root/'tests/library-ui-report.json').write_text(json.dumps(report,indent=2)+'\n')
PY
