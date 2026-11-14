#!/bin/sh
set -eu
install_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$install_dir/.installer/installer.py" --uninstall --prefix "$install_dir" "$@"
