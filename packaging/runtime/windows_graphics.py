"""Private Windows renderer selection. Never installs or replaces system drivers."""
from __future__ import annotations
import ctypes
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def software_environment(root, environment):
    result = environment.copy()
    library = root / 'runtime/mesa/opengl32.dll'
    if not library.is_file():
        raise RuntimeError('The bundled software OpenGL driver is missing. Reinstall the complete Windows package.')
    result['SDL_OPENGL_LIBRARY'] = str(library.resolve())
    result['GALLIUM_DRIVER'] = 'llvmpipe'
    result['LIBGL_ALWAYS_SOFTWARE'] = '1'
    return result


def select_renderer(root, environment, mode='auto', probe=None):
    if mode not in ('auto', 'native', 'software'):
        raise ValueError('Graphics mode must be auto, native or software')
    probe = probe or (lambda env: run_probe(root, env))
    native = None
    if mode != 'software':
        native = probe(environment)
        if native.get('available'):
            return environment.copy(), dict(native, mode='native')
        if mode == 'native':
            raise RuntimeError('The Windows OpenGL driver cannot run the client. Start with --graphics software. ' + native.get('error', ''))
    fallback = software_environment(root, environment)
    result = probe(fallback)
    if not result.get('available'):
        raise RuntimeError('Neither the Windows driver nor bundled software OpenGL could start. ' + result.get('error', ''))
    return fallback, dict(result, mode='software', nativeError=(native or {}).get('error', 'Software graphics requested'))


def run_probe(root, environment):
    """A faulty vendor driver can crash; keep its lifetime outside the supervisor."""
    try:
        process = subprocess.run([sys.executable, '-B', str(root / 'windows_graphics.py'), '--probe', str(root)],
                                 env=environment, capture_output=True, text=True, timeout=20,
                                 creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if process.returncode:
            return {'available': False, 'error': 'OpenGL probe exited with code ' + str(process.returncode)}
        result = json.loads(process.stdout)
        if isinstance(result, dict) and isinstance(result.get('available'), bool):
            return result
        raise ValueError('Invalid graphics probe response')
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        return {'available': False, 'error': str(exc)[:600]}


def probe_sdl(root):
    """Create the same SDL2 OpenGL context used by LÖVE without an error dialog."""
    sdl = ctypes.CDLL(str(root / 'runtime/love/SDL2.dll'))
    sdl.SDL_Init.argtypes = [ctypes.c_uint32]; sdl.SDL_Init.restype = ctypes.c_int
    sdl.SDL_GetError.restype = ctypes.c_char_p
    sdl.SDL_GL_SetAttribute.argtypes = [ctypes.c_int, ctypes.c_int]
    sdl.SDL_CreateWindow.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_uint32]
    sdl.SDL_CreateWindow.restype = ctypes.c_void_p
    sdl.SDL_GL_CreateContext.argtypes = [ctypes.c_void_p]; sdl.SDL_GL_CreateContext.restype = ctypes.c_void_p
    sdl.SDL_GL_GetProcAddress.argtypes = [ctypes.c_char_p]; sdl.SDL_GL_GetProcAddress.restype = ctypes.c_void_p
    sdl.SDL_GL_DeleteContext.argtypes = [ctypes.c_void_p]
    sdl.SDL_DestroyWindow.argtypes = [ctypes.c_void_p]
    window = context = None
    def failed():
        error = sdl.SDL_GetError()
        return {'available': False, 'error': (error.decode('utf-8', 'replace') if error else 'No compatible OpenGL context')[:600]}
    try:
        if sdl.SDL_Init(0x20) != 0:
            return failed()
        sdl.SDL_GL_SetAttribute(17, 2)  # SDL_GL_CONTEXT_MAJOR_VERSION
        sdl.SDL_GL_SetAttribute(18, 1)  # SDL_GL_CONTEXT_MINOR_VERSION
        sdl.SDL_GL_SetAttribute(5, 1)   # SDL_GL_DOUBLEBUFFER
        sdl.SDL_GL_SetAttribute(7, 8)   # SDL_GL_STENCIL_SIZE
        window = sdl.SDL_CreateWindow(b'Love2Gathering graphics check', 0, 0, 32, 32, 0xA)  # OPENGL | HIDDEN
        if not window:
            return failed()
        context = sdl.SDL_GL_CreateContext(window)
        if not context:
            return failed()
        address = sdl.SDL_GL_GetProcAddress(b'glGetString')
        if not address:
            return failed()
        get_string = ctypes.WINFUNCTYPE(ctypes.c_char_p, ctypes.c_uint)(address)
        def text(key):
            value = get_string(key)
            return value.decode('utf-8', 'replace') if value else ''
        version = text(0x1F02)
        match = re.match(r'(\d+)\.(\d+)', version)
        extensions = text(0x1F03)
        modern = match and tuple(map(int, match.groups())) >= (3, 0)
        available = bool(match and tuple(map(int, match.groups())) >= (2, 1)
                         and (modern or 'GL_EXT_framebuffer_object' in extensions or 'GL_ARB_framebuffer_object' in extensions))
        return {'available': available, 'version': version, 'renderer': text(0x1F01), 'vendor': text(0x1F00),
                'error': '' if available else 'OpenGL 2.1 and framebuffer objects are required'}
    finally:
        if context: sdl.SDL_GL_DeleteContext(context)
        if window: sdl.SDL_DestroyWindow(window)
        sdl.SDL_Quit()


if __name__ == '__main__':
    try:
        print(json.dumps(probe_sdl(Path(sys.argv[2]).resolve())))
    except Exception as exc:
        print(json.dumps({'available': False, 'error': str(exc)[:600]}))
