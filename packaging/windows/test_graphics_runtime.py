#!/usr/bin/env python3
"""Real packaged Windows SDL/Mesa auto fallback and LÖVE shader/canvas check."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--payload', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--wine-prefix', type=Path)
    args = parser.parse_args(); root = args.payload.resolve()
    project = Path(__file__).resolve().parents[2]
    env = os.environ.copy(); wine = args.wine_prefix is not None
    if wine:
        prefix = args.wine_prefix.resolve()
        if not prefix.is_dir(): parser.error('Initialize an isolated Wine prefix first')
        env.update(WINEPREFIX=str(prefix), WINEDEBUG='-all', WINEDLLOVERRIDES='opengl32=n')
    def windows(path): return 'Z:' + str(path).replace('/', '\\') if wine else str(path)
    def run(command, environment):
        result = subprocess.run((['wine'] if wine else []) + command, env=environment, capture_output=True, text=True, timeout=50)
        if result.returncode: raise RuntimeError('Windows renderer command failed: ' + result.stdout + result.stderr)
        return result.stdout
    python = str(root / 'runtime/python/python.exe')
    forced = json.loads(run([python, '-B', str(root / 'launcher.py'), '--check-graphics', '--graphics', 'software'], env))
    broken = dict(env, SDL_OPENGL_LIBRARY='Z:\\l2g-missing-opengl-for-test.dll' if wine else 'C:\\l2g-missing-opengl-for-test.dll')
    automatic = json.loads(run([python, '-B', str(root / 'launcher.py'), '--check-graphics', '--graphics', 'auto'], broken))
    if forced.get('mode') != 'software' or automatic.get('mode') != 'software' or 'llvmpipe' not in automatic.get('renderer', '').lower():
        raise RuntimeError('The real broken native driver did not fall back to llvmpipe')
    with tempfile.TemporaryDirectory(prefix='l2g-windows-gl-') as temporary:
        fixture = Path(temporary)
        (fixture / 'conf.lua').write_text("function love.conf(t) t.identity='l2g-isolated-renderer-check';t.window.visible=false;t.window.width=128;t.window.height=128;t.window.vsync=0;t.modules.audio=false;t.modules.joystick=false;t.modules.physics=false end\n")
        (fixture / 'main.lua').write_text("""function love.load()
local canvas=love.graphics.newCanvas(128,128,{format='rgba8'})
local shader=love.graphics.newShader([[vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) { return vec4(0.25,0.75,0.5,1.0); }]])
love.graphics.setCanvas(canvas);love.graphics.clear(0,0,0,1);love.graphics.setShader(shader);love.graphics.rectangle('fill',0,0,128,128);love.graphics.setShader();love.graphics.setCanvas()
local r,g,b,a=canvas:newImageData():getPixel(64,64);assert(math.abs(r-.25)<.02 and math.abs(g-.75)<.02 and math.abs(b-.5)<.02 and a==1,'Shader/canvas pixels differ')
local name,version,vendor,device=love.graphics.getRendererInfo();local f=assert(io.open(os.getenv('L2G_GRAPHICS_RESULT'),'w'));f:write(name,'\\n',version,'\\n',vendor,'\\n',device,'\\n',r,',',g,',',b,',',a);f:close();love.event.quit(0)
end
""")
        output = fixture / 'renderer.txt'
        software = dict(env, SDL_OPENGL_LIBRARY=windows(root / 'runtime/mesa/opengl32.dll'), GALLIUM_DRIVER='llvmpipe', L2G_GRAPHICS_RESULT=windows(output))
        run([str(root / 'runtime/love/lovec.exe'), str(fixture)], software)
        renderer = output.read_text().splitlines()
        if 'llvmpipe' not in renderer[3].lower(): raise RuntimeError('LÖVE did not use bundled llvmpipe')
    report = {'passed': True, 'scope': 'Actual packaged Python/SDL2/Mesa and LÖVE shader/canvas pixel readback under ' + ('Wine; not a native Windows VM or game acceptance.' if wine else 'native Windows; not full game acceptance.'),
              'forcedSoftware': forced, 'automaticFallbackFromMissingDriver': automatic, 'loveRenderer': renderer,
              'softwareDllSha256': hashlib.sha256((root / 'runtime/mesa/opengl32.dll').read_bytes()).hexdigest(), 'userStorageUsed': False,
              'wineVersion': subprocess.check_output(['wine', '--version'], text=True).strip() if wine else None,
              'sourceSha256': {relative: hashlib.sha256((project / relative).read_bytes()).hexdigest() for relative in
                               ('packaging/runtime/launcher.py', 'packaging/runtime/windows_graphics.py', 'packaging/windows/build.py',
                                'packaging/windows/runtimes.lock.json', 'packaging/windows/test_graphics_runtime.py')}}
    args.report.parent.mkdir(parents=True, exist_ok=True); args.report.write_text(json.dumps(report, indent=2) + '\n'); print(json.dumps(report))


if __name__ == '__main__': main()
