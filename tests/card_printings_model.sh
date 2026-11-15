#!/bin/sh
# Headless LÖVE supplies LuaJIT when no separate Lua executable is installed.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/love2gathering-printings-model.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT INT TERM
cat > "$test_dir/conf.lua" <<'CONF'
function love.conf(t)t.window=false;t.modules.graphics=false;t.modules.audio=false;t.modules.joystick=false;t.modules.physics=false;t.console=true end
CONF
cat > "$test_dir/main.lua" <<'LUA'
local runtime=love
function love.load()
 local root=assert(os.getenv('LOVE2GATHERING_MODEL_TEST_ROOT'));package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
 local ok,err=xpcall(function()dofile(root..'/tests/card_printings_model.lua')end,debug.traceback)
 love=runtime;if not ok then io.stderr:write(err..'\n')end;love.event.quit(ok and 0 or 1)
end
LUA
LOVE2GATHERING_MODEL_TEST_ROOT="$project_dir" love "$test_dir"
