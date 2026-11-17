# Windows x64 package

`build.py --payload dist/stage/common/Love2Gathering` produces the offline
`dist/Love2Gathering-VERSION-windows-x64-setup.exe`. It includes LÖVE 11.5,
CPython 3.13.11 embeddable, Pillow 13 with JPEG support, Temurin JRE 21.0.13+9,
Mesa LLVMpipe 26.3.0 and the compiled bridge.
`runtimes.lock.json` pins upstream URLs and SHA256 checksums. LÖVE/Python/Java
come from their official distributions; the private software OpenGL DLL comes
from the reproducible [mmozeiko/build-mesa](https://github.com/mmozeiko/build-mesa/releases/tag/26.3.0)
x64 static build, with LLVM 23.1.5. Runtime archives
retain their original licenses/notices. No user decks, image cache or replay
database enters the payload. `../python-wheels.lock.json` pins the official
CPython3.13 Windows Pillow wheel and SHA256. Its PIL/native DLLs and license
notices are unpacked under the private interpreter's `Lib/site-packages` and
explicitly enabled in `python313._pth`; no host Python or pip install is used.

The per-user NSIS installer offers a directory page and an optional desktop
shortcut; Start Menu entries and an uninstaller are always registered. The
default is `%LOCALAPPDATA%\Programs\Love2Gathering`; a writable folder on
another drive can be selected. Silent installation accepts `/S /D=PATH`, with
`/D` last. Installation refuses a nonempty unrelated directory and verifies its
ownership marker when reusing an existing installation. The uninstaller removes
the generated exact file list instead of recursively removing the chosen folder;
saved data and unrecognized extra files remain.

`Love2Gathering.exe` starts the bundled Python supervisor without a console.
It starts owned catalog/XMage/room processes and the desktop splash. The card
index, logs, engine work and saves are outside the installation; Windows defaults
use Local AppData, with location preferences under Roaming AppData. Settings can
choose other data/cache folders. No build tool or separately installed Python,
Java or LÖVE is required on the target machine.

Dedicated graphics are not required. Before opening the desktop, the supervisor
checks an actual hidden SDL2 OpenGL context in a separate, bounded process.
Supported integrated/virtual/hardware drivers stay in use. Missing OpenGL 2.1,
missing framebuffer support, driver crashes and probe timeouts select bundled
CPU rendering automatically. Mesa is loaded only for this application through
SDL's `SDL_OPENGL_LIBRARY`; no system DLL, driver or registry entry is replaced.
The selected renderer and the native failure reason are retained in the session's
`graphics.json`. CPU rendering can be slower on large displays.

`Love2Gathering.exe --graphics software` forces CPU rendering;
`--graphics native` forces the existing Windows driver. The environment setting
`LOVE2GATHERING_GRAPHICS=software` provides the same persistent launcher choice.
`runtime\python\python.exe launcher.py --check-graphics --graphics software`
checks the real bundled context without opening saved data. `--check` continues
to check runtime versions and package readability without requiring a display.
The Mesa/LLVM/dependency license texts, original Mesa copyright headers and exact
source/archive provenance are retained under `runtime\mesa\licenses`.

The SDL2 loader's source accepts the private library path on Windows:
[SDL2 Windows OpenGL implementation](https://github.com/libsdl-org/SDL/blob/SDL2/src/video/windows/SDL_windowsopengl.c).
[Mesa's LLVMpipe documentation](https://docs.mesa3d.org/drivers/llvmpipe.html)
describes CPU rendering and Windows application-local OpenGL libraries.

Build NSIS on Linux with `makensis` (the build can use an extracted local NSIS
installation under `.tools/packaging-platform/nsis`). Official background:
[NSIS directory pages](https://nsis.sourceforge.io/Docs/Chapter4.html),
[Python embedded distribution](https://docs.python.org/3/using/windows.html#the-embeddable-package),
[LÖVE Windows distribution](https://love2d.org/wiki/Game_Distribution),
[Adoptium download API](https://adoptium.net/installation/ci-scripts).

Acceptance distinguishes a native Windows machine from Wine. The installed
package was checked under Wine 11.22 Staging: NSIS install/uninstall in a chosen
folder, automatic fallback from a real failed DLL load, Mesa context creation,
LÖVE shader/Canvas pixel readback and SQLite-save preservation. See
`graphics-runtime-report.json` and `installer-test-report.json`. The older
`runtime-test-report.json` records separate Wine 9 runtime/Win32 checks and its
Java NetworkInterface limitation. Neither establishes native Windows 10/11 VM
execution or a complete Windows game.

To repeat the installed graphics acceptance with a fresh work directory:

```sh
python3 packaging/windows/test_installer.py --installer PATH/setup.exe --wine-prefix .runtime/isolated-wine --work .runtime/windows-install-test --check-graphics
```
