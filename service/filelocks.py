"""The same shared/exclusive storage locks on POSIX and Windows."""
import errno
import os

LOCK_SH, LOCK_EX, LOCK_NB, LOCK_UN = 1, 2, 4, 8

if os.name != 'nt':
    from fcntl import flock, LOCK_SH, LOCK_EX, LOCK_NB, LOCK_UN
else:
    import ctypes
    from ctypes import wintypes
    import msvcrt

    class _Overlapped(ctypes.Structure):
        _fields_ = [('Internal', ctypes.c_size_t), ('InternalHigh', ctypes.c_size_t),
                    ('Offset', wintypes.DWORD), ('OffsetHigh', wintypes.DWORD), ('hEvent', wintypes.HANDLE)]

    _kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    _kernel.LockFileEx.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD,
                                   wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(_Overlapped)]
    _kernel.LockFileEx.restype = wintypes.BOOL
    _kernel.UnlockFileEx.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD,
                                     wintypes.DWORD, ctypes.POINTER(_Overlapped)]
    _kernel.UnlockFileEx.restype = wintypes.BOOL

    def flock(file, operation):
        """Lock byte zero, beyond EOF if necessary; closing the handle releases it.

        All application writers use this helper. Shared readers remain shared,
        rather than turning every ordinary SQL read into an exclusive lock.
        """
        fd = file if isinstance(file, int) else file.fileno()
        handle = wintypes.HANDLE(msvcrt.get_osfhandle(fd))
        overlapped = _Overlapped()
        if operation & LOCK_UN:
            ok = _kernel.UnlockFileEx(handle, 0, 1, 0, ctypes.byref(overlapped))
        else:
            flags = (2 if operation & LOCK_EX else 0) | (1 if operation & LOCK_NB else 0)
            ok = _kernel.LockFileEx(handle, flags, 0, 1, 0, ctypes.byref(overlapped))
        if not ok:
            code = ctypes.get_last_error()
            if code in (33, 997):
                raise BlockingIOError(errno.EAGAIN, 'Storage lock is held by another process')
            raise ctypes.WinError(code)
