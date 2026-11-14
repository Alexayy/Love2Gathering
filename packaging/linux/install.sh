#!/bin/sh
set -eu
installer_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' 'Please install Python 3.10 or newer, then run this installer again.' >&2
    exit 1
fi
exec python3 "$installer_dir/installer.py" "$@"
