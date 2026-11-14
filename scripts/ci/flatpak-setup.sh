#!/usr/bin/env bash
# Prepare only an ephemeral GitHub-hosted Ubuntu job, never a desktop install.
set -euo pipefail

if [[ "${1:-}" == --dry-run ]]; then
  cat <<'PLAN'
GitHub-hosted Ubuntu 24.04 only:
  sudo apt-get update
  sudo apt-get install --yes --no-install-recommends flatpak love libmodplug1 libluajit2-5.1-2 libtheora0 desktop-file-utils dbus-daemon
  sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0  # only if the kernel exposes it
  export FLATPAK_USER_DIR="$RUNNER_TEMP/love2gathering-flatpak"
  # If absent, create a private XDG_RUNTIME_DIR under RUNNER_TEMP for D-Bus/Flatpak.
  flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak --user install --assumeyes --noninteractive --no-related flathub org.freedesktop.Platform//25.08 org.freedesktop.Sdk//25.08
  flatpak --user info --show-commit org.freedesktop.Platform//25.08
  flatpak --user info --show-commit org.freedesktop.Sdk//25.08
PLAN
  exit 0
fi

if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "${RUNNER_OS:-}" != Linux ]]; then
  printf '%s\n' 'This setup is restricted to an ephemeral GitHub-hosted Linux runner. Use --dry-run to inspect it.' >&2
  exit 2
fi
if [[ -z "${RUNNER_TEMP:-}" || -z "${GITHUB_ENV:-}" ]]; then
  printf '%s\n' 'GitHub runner temporary directory/environment file is missing.' >&2
  exit 2
fi
# The workflow selects ubuntu-24.04; do not silently use a different ABI.
source /etc/os-release
if [[ "$ID" != ubuntu || "$VERSION_ID" != 24.04 || "$(uname -m)" != x86_64 ]]; then
  printf '%s\n' 'Flatpak native payload builds require the Ubuntu 24.04 package ABI.' >&2
  exit 2
fi
sudo apt-get update
sudo apt-get install --yes --no-install-recommends flatpak love libmodplug1 libluajit2-5.1-2 libtheora0 desktop-file-utils dbus-daemon
# Ubuntu and Flatpak's own CI document this exception for disposable 24.04 VMs.
# It is never installed as a persistent desktop setting or applied outside CI.
if [[ -e /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]]; then
  sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
fi
export FLATPAK_USER_DIR="$RUNNER_TEMP/love2gathering-flatpak"
mkdir -p -- "$FLATPAK_USER_DIR"
printf 'FLATPAK_USER_DIR=%s\n' "$FLATPAK_USER_DIR" >> "$GITHUB_ENV"
if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" ]]; then
  export XDG_RUNTIME_DIR="$RUNNER_TEMP/love2gathering-runtime"
  mkdir -p -- "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
  printf 'XDG_RUNTIME_DIR=%s\n' "$XDG_RUNTIME_DIR" >> "$GITHUB_ENV"
fi
flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak --user install --assumeyes --noninteractive --no-related flathub org.freedesktop.Platform//25.08 org.freedesktop.Sdk//25.08
flatpak --user info --show-commit org.freedesktop.Platform//25.08
flatpak --user info --show-commit org.freedesktop.Sdk//25.08
