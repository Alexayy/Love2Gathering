# Complete application updates

Settings → About → **Check for updates** checks the installed release channel.
Nothing checks or downloads releases at startup. **Download complete update**
fetches the matching Windows setup, Linux folder installer, DEB, RPM or Flatpak
bundle, and verifies its exact published SHA-256 and size. Client Lua, bridge,
engine dependencies, runtimes and packaged resources move together.

For a private repository, save a GitHub fine-grained access token in the same
About section, selecting this repository with **Contents: read**. This permission
allows reading [private release assets](https://docs.github.com/en/rest/releases/assets).
The field is masked and cleared after submission. **Forget GitHub access** removes
the saved credential. Windows protects stored bytes with current-user DPAPI;
Linux uses a private configuration directory/file outside the application and
SQLite databases. The app never imports Codex, browser or GitHub CLI credentials.
Authorization goes only to the pinned GitHub API and is removed before every
download redirect. Status responses, logs, captures and release reports contain
no token. Saving access does not itself contact GitHub.

**Close, install and restart** is available only after a verified download and
outside a live practice game or room, including a game retained behind replay.
The pending installation owns input until acknowledgement. A lost acknowledgement
is reconciled through an idempotent status read; the client never retries the
installation mutation blindly. Normal queued saves finish before the app exits.

| Installation | Apply behavior |
| --- | --- |
| Windows setup | A private copy of Python/helper outside the installed folder waits for the exact supervisor process, rehashes the setup, installs into the same folder and verifies the selected release before restarting. |
| Linux folder `.run` | The independent helper runs the existing staged installer with the original prefix, then verifies the installed release and restarts. |
| DEB | The system package manager applies the verified package, using the normal desktop authentication prompt. |
| RPM | The system package manager upgrades the verified package with its original relocatable prefix, using desktop authentication. |
| Flatpak installed with the supplied helper | The host launcher waits for its owned Flatpak process, imports the verified bundle into the same selected installation, verifies the actual new commit/release and restarts with a fresh context. |
| Direct/older Flatpak launcher | **Close and open system installer** opens the verified bundle through the desktop. This is a handoff, not a claim that installation completed. For a custom location, run the supplied `install-flatpak.py` with its original `--prefix`. |

Keep both `install-flatpak.py` and `update-host.py` beside the bundle for initial
Flatpak installation or migration from an older host launcher. New bundles carry
both helpers under `host-tools`, so an accepted update refreshes their owned
copies. Edited helpers and unrelated files are preserved. The coordinator adds
no host-execution permission to the Flatpak app. Direct desktop handoff uses the
[file-opening portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.OpenURI.html).

Windows includes **Uninstall.exe**, a Start menu entry and Windows Apps
registration, including quiet uninstall. Upgrade/removal refuses active installed
runtimes or locked files. Installation stages the entire payload and restores the
prior payload and registration on failure. Obsolete owned JAR/DLL files are
removed during upgrade. Uninstall removes only unchanged owned files; modified
or user-created files remain. Saves and image databases are separate and are
never purged by update/uninstall.

Source checkouts retain the repository workflow. They cannot point the updater
at arbitrary directories, releases, commands or download URLs. Packaged update
authorization comes from the supervisor's private per-launch context; public API
calls contain only the current candidate ID. GitHub responses are restricted to
the project's repository and matching stable/development identity. The release
checksum binds a precise filename, not a name prefix. Helpers recheck the artifact
and current installed identity after shutdown. A successful installer exit alone
does not establish replacement.

Implementation: `app/updates.lua`, `service/updates.py`,
`packaging/runtime/update_handoff.py`, the platform installers and
`packaging/flatpak/update-host.py`. Background service work does not execute
installers. Stage/download files stay outside the application payload and user
databases.

Focused verification:

```sh
python3 -m unittest service.tests.test_updates service.tests.test_updates_http -v
python3 packaging/runtime/test_update_handoff.py
python3 packaging/windows/test_transaction.py
python3 packaging/flatpak/test_update_host.py
python3 packaging/flatpak/test_host_native.py
lua tests/updates_model.lua
tests/updates_ui.sh
```

These cover distinct scopes: real local HTTP faults; actual deferred Linux
replacement; actual NSIS/Win32 transactions under Wine; real offline Flatpak
bundles, custom prefix, update and restart; controlled UI transport; and real
LÖVE/Slab clicks. Wine does not establish native Windows hardware/gameplay, and
unit command construction does not establish a particular desktop's privilege
dialog. Native desktop authentication remains owned by the operating system.
