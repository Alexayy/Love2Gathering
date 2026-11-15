"""Read-only engine-owner checks. Windows os.kill(pid, 0) is not a probe."""
import os
from pathlib import Path


def _windows_owner(pid):
    import ctypes
    from ctypes import wintypes
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel.WaitForSingleObject.restype = wintypes.DWORD
    kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
    kernel.GetProcessTimes.restype = wintypes.BOOL
    handle = kernel.OpenProcess(0x100000 | 0x1000, False, pid)
    if not handle:
        return ctypes.get_last_error() == 5, None  # An inaccessible owner stays protected.
    try:
        if kernel.WaitForSingleObject(handle, 0) != 258:
            return False, None
        times = [wintypes.FILETIME() for _ in range(4)]
        if not kernel.GetProcessTimes(handle, *(ctypes.byref(value) for value in times)):
            return True, None
        ticks = (times[0].dwHighDateTime << 32) | times[0].dwLowDateTime
        return True, ticks // 10000 - 11644473600000
    finally:
        kernel.CloseHandle(handle)


def process_alive(pid):
    if os.name == 'nt':
        return _windows_owner(pid)[0]
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    return True


def process_started_ms(pid):
    if os.name == 'nt':
        return _windows_owner(pid)[1]
    try:
        fields = Path('/proc/' + str(pid) + '/stat').read_text().rsplit(')', 1)[1].split()
        ticks = int(fields[19])
        boot = next(int(line.split()[1]) for line in Path('/proc/stat').read_text().splitlines() if line.startswith('btime '))
        return round(boot * 1000 + ticks * 1000 / os.sysconf('SC_CLK_TCK'))
    except (OSError, ValueError, IndexError, StopIteration):
        return None
