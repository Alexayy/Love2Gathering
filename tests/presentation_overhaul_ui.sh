#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
RUN=$(mktemp -d /tmp/love2gathering-presentation-overhaul.XXXXXX)
cp -R "$ROOT/app" "$ROOT/lib" "$RUN/"
mkdir -p "$RUN/assets/kenney" "$RUN/assets/fonts" "$ROOT/build/presentation-overhaul"
cp -R "$ROOT/assets/keyrune" "$ROOT/assets/icons" "$ROOT/assets/card-backs" "$RUN/assets/"
for part in runtime ui particles sounds theme;do cp -R "$ROOT/assets/kenney/$part" "$RUN/assets/kenney/";done
cp "$ROOT/assets/fonts/"*.ttf "$RUN/assets/fonts/"
if [[ -f "$ROOT/build/presentation-overhaul/Plains-normal.jpg" ]];then cp "$ROOT/build/presentation-overhaul/Plains-normal.jpg" "$RUN/land.jpg";fi
cp "$ROOT/tests/presentation_overhaul_ui.lua" "$RUN/main.lua"
cat > "$RUN/conf.lua" <<'EOF'
function love.conf(t)
 t.identity='love2gathering-isolated-presentation-overhaul';t.window.width=1366;t.window.height=768;t.window.vsync=0;t.window.resizable=true;t.console=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false
end
EOF
LOVE2GATHERING_PRESENTATION_OUTPUT="$ROOT/build/presentation-overhaul" love "$RUN"
printf 'Isolated graphical fixture: %s\n' "$RUN"
