# Linux installer

`install.sh` installs the release payload into the folder you choose. It runs as your normal user and does not change application data/cache locations.

```sh
./install.sh --payload ./payload --prefix /mnt/Games/Love2Gathering --desktop-shortcut --yes
```

`--prefix` names the final application directory. Without it, Zenity or KDialog offers a parent-folder chooser when available; the installer adds `Love2Gathering` beneath that folder. A terminal prompt is the fallback. The selected location must be writable by your user. The installer does not request administrator rights or change drive permissions.

`--payload DIR` accepts an extracted release directory. `--archive FILE.tar.gz` / `.tar.xz` accepts a bounded release archive with either a single top-level folder or the payload files at its root. With neither option, the installer looks for its sibling `payload/`, then the repository's `dist/stage/linux/Love2Gathering`. A self-extracting release can invoke the same helper after unpacking its private payload.

The payload has an executable `love2gathering` shell launcher, `runtime/java/bin/java` (Java 21), and `share/icons/love2gathering.png`. The host needs Python 3.10 or newer and LÖVE 11.5. The package launcher owns starting the frontend and local services; this installer only copies/registers it.

Installation adds:

- A command symlink at `~/.local/bin/love2gathering`.
- A menu entry at `${XDG_DATA_HOME:-$HOME/.local/share}/applications/io.github.Alexayy.Love2Gathering.desktop`.
- An optional desktop shortcut with `--desktop-shortcut`.
- `uninstall.sh` and a private manifest/helper inside the selected installation.

The shell launcher must resolve its actual file when invoked through the command symlink. The desktop entry uses an absolute launcher argument with Desktop Entry escaping, including spaces, quotes, dollar signs, backslashes and literal percent characters. No shell command is assembled from the chosen path.

Updates require this installer's ownership marker. Changed or user-created files are never overwritten; conflicting changes stop the update with their filename. An update stages a complete copy beside the existing installation and keeps the old folder until registration succeeds. A single-user installer lock excludes concurrent installs/uninstalls. The old command/menu entries are restored if registration fails. Package links cannot leave the payload; unsafe archive paths/devices are rejected.

Remove the installation with:

```sh
/mnt/Games/Love2Gathering/uninstall.sh --yes
```

Uninstall removes only unchanged files listed in its manifest and still-owned shortcuts. Modified/untracked files remain. Saves, settings, replays, original metadata and image caches are never purged. If a user deliberately placed their own files beneath the install folder, those files keep that folder in place after the app files are removed.

DEB/RPM packages use their package manager's fixed paths. The standalone installer is the Linux route for a custom install folder. Flatpak uses its selected Flatpak installation, as documented by that format's wrapper.

Verification: `python3 packaging/linux/test_installer.py` creates temporary payloads and user homes. It tests selected paths, real symlinks, menu entries, safe updates/rollback, uninstall/data preservation, archive traversal rejection and locking. Where installed, it runs `desktop-file-validate` and an actual `gio launch` using a fixture executable under a path containing spaces, quotes, `%` and `$`. This verifies installation/integration, not gameplay or downloaded runtime authenticity.

Implementation references: [Desktop Entry Exec quoting](https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html), [desktop value escaping](https://specifications.freedesktop.org/desktop-entry/latest/value-types.html), and [XDG user executable/data locations](https://specifications.freedesktop.org/basedir/latest/).
