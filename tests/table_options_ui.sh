#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
RUN=$(mktemp -d /tmp/love2gathering-table-options.XXXXXX)
cp -R "$ROOT/app" "$ROOT/lib" "$RUN/"
mkdir -p "$RUN/assets/kenney" "$RUN/assets/fonts" "$ROOT/build/table-options"
cp -R "$ROOT/assets/keyrune" "$ROOT/assets/icons" "$ROOT/assets/card-backs" "$RUN/assets/"
for part in runtime ui particles sounds theme;do cp -R "$ROOT/assets/kenney/$part" "$RUN/assets/kenney/";done
cp "$ROOT/assets/fonts/"*.ttf "$RUN/assets/fonts/"
cp "$ROOT/tests/table_options_ui.lua" "$RUN/main.lua"
cat > "$RUN/conf.lua" <<'EOF'
function love.conf(t)
 t.identity='love2gathering-isolated-table-options';t.window.width=1366;t.window.height=768;t.window.vsync=0;t.console=true
 t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false
end
EOF
LOVE2GATHERING_TABLE_OPTIONS_OUTPUT="$ROOT/build/table-options" love "$RUN"
python3 - "$ROOT" "$RUN" <<'PY'
import hashlib,json,sys
from pathlib import Path
root,run=map(Path,sys.argv[1:])
report=json.loads((root/'build/table-options/ui-report.json').read_text())
files=['app/priority.lua','app/model.lua','app/match_ui.lua','app/view.lua','app/table_panels.lua','app/table.lua','app/table_hud.lua','app/table_presentation.lua','app/renderer.lua','app/layout.lua','tests/table_options_ui.lua','tests/table_options_ui.sh']
report['sourceHashes']={name:hashlib.sha256((root/name).read_bytes()).hexdigest()for name in files}
report['sourceStillMatches']=all((root/name).read_bytes()==(run/name).read_bytes()for name in files if name.startswith('app/'))
report['fixtureDirectory']=str(run)
assert report['passed']and report['sourceStillMatches'],'Graphical test source changed during acceptance'
(root/'tests/table-options-ui-report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
PY
printf 'Isolated graphical fixture: %s\n' "$RUN"
