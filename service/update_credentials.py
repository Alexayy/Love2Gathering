"""Only explicitly supplied updater credentials; no session/CLI credential import.

Windows protects persisted bytes with current-user DPAPI. Unix stores the token
in a private 0700 configuration subdirectory and a regular 0600 file. Application
databases, installed payloads and other configuration files are never opened.
"""
import ctypes
import os
from pathlib import Path
import re
import stat
import tempfile

from paths import config_file

WINDOWS = os.name == 'nt'
MAX_STORED = 8192
PLAIN = b'Love2Gathering-update-token:1:plain\n'
PROTECTED = b'Love2Gathering-update-token:1:dpapi\n'


def validate_token(token):
    """Return a bounded explicit token, or the empty value used to forget it."""
    if not isinstance(token, str) or token and not re.fullmatch(r'[A-Za-z0-9_-]{20,512}', token):
        raise ValueError('Enter a valid GitHub token without spaces or control characters')
    return token


def _dpapi(value, decrypt=False):
    """Current-user protection without machine scope, prompts or exported keys."""
    if not WINDOWS:
        raise ValueError('Windows credential protection is unavailable')
    from ctypes import wintypes
    class Blob(ctypes.Structure):
        _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_ubyte))]
    buffer = ctypes.create_string_buffer(value, len(value))
    incoming = Blob(len(value), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte)))
    outgoing = Blob()
    crypt = ctypes.WinDLL('crypt32', use_last_error=True)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    kernel.LocalFree.restype = ctypes.c_void_p
    if decrypt:
        function = crypt.CryptUnprotectData
        function.argtypes = [ctypes.POINTER(Blob), ctypes.POINTER(wintypes.LPWSTR), ctypes.POINTER(Blob),
                             ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(Blob)]
        description = None
    else:
        function = crypt.CryptProtectData
        function.argtypes = [ctypes.POINTER(Blob), wintypes.LPCWSTR, ctypes.POINTER(Blob),
                             ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(Blob)]
        description = 'Love2Gathering update credential'
    function.restype = wintypes.BOOL
    try:
        # CRYPTPROTECT_UI_FORBIDDEN; no CRYPTPROTECT_LOCAL_MACHINE flag.
        if not function(ctypes.byref(incoming), description, None, None, None, 1, ctypes.byref(outgoing)):
            raise ValueError('Windows credential protection failed')
        if not 0 < outgoing.size <= MAX_STORED:
            raise ValueError('Windows credential protection returned invalid data')
        return ctypes.string_at(outgoing.data, outgoing.size)
    finally:
        if outgoing.data:
            kernel.LocalFree(ctypes.cast(outgoing.data, ctypes.c_void_p))


class UpdateCredentials:
    def __init__(self, path=None, *, protect=None, unprotect=None):
        if (protect is None) != (unprotect is None):
            raise ValueError('Credential protection requires matching handlers')
        self.path = Path(path).expanduser() if path is not None else config_file().parent / 'updater-credentials/github-token'
        if not self.path.is_absolute() or self.path.name in ('', '.', '..'):
            raise ValueError('Update credential path must be absolute')
        self.protected = WINDOWS or protect is not None
        self._protect = protect or (lambda data: _dpapi(data))
        self._unprotect = unprotect or (lambda data: _dpapi(data, True))

    def _directory(self, create=False):
        directory = self.path.parent
        if directory.is_symlink() or directory.resolve() != directory:
            raise ValueError('Update credential directory cannot use symbolic links')
        try:
            info = directory.lstat()
        except FileNotFoundError:
            if not create:
                return False
            directory.mkdir(mode=0o700, parents=True, exist_ok=True)
            info = directory.lstat()
        if not stat.S_ISDIR(info.st_mode):
            raise ValueError('Update credential directory is not a private folder')
        if not WINDOWS and (info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700):
            raise ValueError('Update credential directory must be owned by this user with mode 0700')
        return True

    def _read(self):
        if not self._directory():
            return None
        flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0)
        try:
            before = self.path.lstat()
            if stat.S_ISLNK(before.st_mode):
                raise ValueError('Update credential cannot be a symbolic link')
            if not stat.S_ISREG(before.st_mode):
                raise ValueError('Update credential must be a regular private file')
            descriptor = os.open(self.path, flags)
        except FileNotFoundError:
            return None
        except OSError:
            raise OSError('Update credential cannot be read') from None
        try:
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_STORED or info.st_nlink != 1:
                raise ValueError('Update credential must be a bounded regular private file')
            if not WINDOWS and (info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600):
                raise ValueError('Update credential file must be owned by this user with mode 0600')
            with os.fdopen(descriptor, 'rb') as source:
                descriptor = None
                data = source.read(MAX_STORED + 1)
            if len(data) > MAX_STORED or not data.startswith((PLAIN, PROTECTED)):
                raise ValueError('Stored update credential format is not recognized')
            return data
        finally:
            if descriptor is not None:
                os.close(descriptor)

    def get(self):
        data = self._read()
        if data is None:
            return ''
        header = PROTECTED if self.protected else PLAIN
        if not data.startswith(header):
            raise ValueError('Stored update credential protection does not match this system')
        raw = data[len(header):]
        if self.protected:
            try:
                raw = self._unprotect(raw)
            except Exception:
                raise ValueError('Stored update credential could not be unlocked') from None
        try:
            if not isinstance(raw, bytes) or len(raw) > 512:
                raise ValueError()
            token = raw.decode('ascii')
            if not token:
                raise ValueError()
            return validate_token(token)
        except (ValueError, UnicodeError):
            raise ValueError('Stored update credential is invalid; enter it again') from None

    def set(self, token):
        token = validate_token(token)
        current = self._read()
        if not token:
            if current is not None:
                self.path.unlink()
            return
        raw = token.encode('ascii')
        if self.protected:
            try:
                raw = self._protect(raw)
                if not isinstance(raw, bytes) or not 0 < len(raw) <= MAX_STORED - len(PROTECTED):
                    raise ValueError()
            except Exception:
                raise ValueError('Update credential could not be protected') from None
        data = (PROTECTED if self.protected else PLAIN) + raw
        self._directory(create=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(prefix='.github-token-', dir=self.path.parent, delete=False) as target:
                temporary = Path(target.name)
                if not WINDOWS:
                    os.fchmod(target.fileno(), 0o600)
                target.write(data)
                target.flush()
                os.fsync(target.fileno())
            # Revalidate after protection/write work so a changed directory or
            # a late foreign file is not silently followed or overwritten.
            self._directory()
            if self._read() != current:
                raise ValueError('Update credential changed while it was being saved')
            temporary.replace(self.path)
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)
