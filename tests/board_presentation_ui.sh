#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-board-presentation.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cp -R "$project_dir/app" "$project_dir/lib" "$test_dir/"
mkdir -p "$test_dir/assets/fonts" "$test_dir/assets/kenney"
cp -R "$project_dir/assets/keyrune" "$project_dir/assets/icons" "$test_dir/assets/"
for name in ui particles sounds theme;do cp -R "$project_dir/assets/kenney/$name" "$test_dir/assets/kenney/";done
cp "$project_dir/assets/fonts/DejaVuSans.ttf" "$project_dir/assets/fonts/DejaVuSans-Bold.ttf" "$test_dir/assets/fonts/"
cp "${LOVE2GATHERING_ANGEL_FRAME:-/tmp/love2gathering-native-angel-frame.json}" "$test_dir/native-angel.json"
python3 - "$test_dir" "$project_dir" <<'PY'
import json,sqlite3,sys,pathlib,os
dest=pathlib.Path(sys.argv[1]);index=pathlib.Path(os.environ.get('LOVE2GATHERING_PRESENTATION_INDEX','/tmp/love2gathering-gameplay-catalog/catalog.sqlite'));database=pathlib.Path(os.environ.get('LOVE2GATHERING_PRESENTATION_STORE','/tmp/love2gathering-gameplay-catalog/saves/app.sqlite'))
assert pathlib.Path('/tmp')in index.resolve().parents and pathlib.Path('/tmp')in database.resolve().parents,'Use isolated fixture storage'
c=sqlite3.connect('file:'+str(index)+'?mode=ro',uri=True);a=sqlite3.connect('file:'+str(database)+'?mode=ro',uri=True);cards={};images={}
for name in ['Angel of Vitality','Krenko, Mob Boss']:
 row=c.execute('SELECT payload FROM cards WHERE name=?',(name,)).fetchone()
 if not row:continue
 card=json.loads(row[0]);cards[name]=card
 images[name]={}
 for kind in ['normal','art_crop']:
  art=a.execute("SELECT content FROM art_cache WHERE json_extract(metadata,'$.oracleId')=? AND json_extract(metadata,'$.kind')=? ORDER BY cache_key LIMIT 1",(card['id'],kind)).fetchone()
  if art:
   file='card-'+str(len(images))+'-'+kind+'.jpg';(dest/file).write_bytes(art[0]);images[name][kind]=file
assert images.get('Angel of Vitality',{}).get('normal'),'Seed one genuine cached Angel JPEG in the isolated store'
(dest/'card-metadata.json').write_text(json.dumps({'cards':cards,'images':images}))
PY
cp "$project_dir/tests/board_presentation_ui.lua" "$test_dir/main.lua"
cat > "$test_dir/conf.lua" <<'EOF'
function love.conf(t)
    t.identity='love2gathering-board-presentation-tests';t.window.title='Love: 2 Gathering — board presentation acceptance';t.window.width=1440;t.window.height=900;t.window.vsync=0;t.window.resizable=true
    t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false;t.console=true
end
EOF
cp -R "$project_dir/assets/kenney/runtime" "$test_dir/assets/kenney/"
cp "$project_dir/assets/fonts/Beleren2016-Bold.ttf" "$test_dir/assets/fonts/"
love "$test_dir"
