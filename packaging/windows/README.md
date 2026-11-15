# Windows x64 package

`build.py --payload dist/stage/common/Love2Gathering` produces the offline
`dist/Love2Gathering-VERSION-windows-x64-setup.exe`. It includes LÖVE 11.5,
CPython 3.13.11 embeddable, Pillow 13 with JPEG support, Temurin JRE 21.0.13+9 and the compiled bridge.
`runtimes.lock.json` pins official URLs and SHA256 checksums. Runtime archives
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

Build NSIS on Linux with `makensis` (the build can use an extracted local NSIS
installation under `.tools/packaging-platform/nsis`). Official background:
[NSIS directory pages](https://nsis.sourceforge.io/Docs/Chapter4.html),
[Python embedded distribution](https://docs.python.org/3/using/windows.html#the-embeddable-package),
[LÖVE Windows distribution](https://love2d.org/wiki/Game_Distribution),
[Adoptium download API](https://adoptium.net/installation/ci-scripts).

Acceptance distinguishes an actual native Windows machine from Wine. The local
Wine 9 environment runs the bundled Python/SQLite/SSL/LÖVE/Java version checks
and Win32 lock/PID tests. Its Java NetworkInterface implementation crashes while
initializing the native server; that emulator limitation is not a successful
Windows gameplay test. Native Windows 10/11 execution still needs validation.
