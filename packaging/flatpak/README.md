# Local Flatpak bundle

`build.py --payload dist/stage/linux/Love2Gathering` creates
`dist/Love2Gathering-VERSION-x86_64.flatpak` using the installed Freedesktop
25.08 Platform/SDK. The app includes its compiled XMage bridge, JRE 21, native
LÖVE 11.5 and the three additional native SONAMEs absent from that Platform;
their original notices and exact native hashes are retained. Python/SQLite/SSL
come from the actual Platform, independently of the SDK. This is a local binary
bundle, not a Flathub submission manifest.

Install through the distribution's software manager, or use the supplied folder
chooser/CLI helper:

```sh
python3 install-flatpak.py Love2Gathering-VERSION-x86_64.flatpak --prefix /mnt/Games/Flatpak
```

The helper uses the documented `FLATPAK_USER_DIR` to keep this per-user
installation at the selected location without requiring a system configuration
change. It registers an owned command and menu shortcut that retain that exact
location. Flathub supplies the standard runtime if it is not already installed;
runtime size is additional to the application bundle. Internet/IPC/display/audio
and host filesystem access support private network games and Settings folder
selection. Application saves and image-cache paths remain independently
configurable.

To remove the app through the helper:

```sh
python3 /mnt/Games/Flatpak/install-flatpak.py --uninstall --prefix /mnt/Games/Flatpak
```

Uninstall retains saves/cache and the repository/runtime. It does not use
`--delete-data`. See the focused registration tests and the real isolated sandbox
health report for distinct evidence.

The folder picker can be cancelled before any Flatpak command runs. Existing
Flatpak repositories are supported, but their unrelated launchers/helpers and
shortcuts are never overwritten. Installer ownership includes the selected root
and hashes of its two helper files; modified files stop an update and remain
after uninstall. Dangling/symbolic shortcut conflicts are treated as existing
files. Registration restores earlier owned helpers if a later write fails;
Flatpak's repository and downloaded runtimes remain available for retry.
The helper imports and verifies the bundle first, checks its application ID, then
updates an existing application to that exact local commit without uninstalling
it. It verifies the deployed commit before registering shortcuts. A damaged or
wrong-application bundle leaves the working deployment and helpers in place.
Only the auto-created `love2gathering-origin`, used exclusively by this app and
still pointing to an empty or installer-owned local URL, can be directed to the
verified local repository. Shared sources such as Flathub are never rewritten.
An already-current application only needs its helpers/shortcuts repaired. This
also avoids older Flatpak versions' local-bundle reinstall and `--no-pull`
limitations; native deployment checks determine success.

`python3 packaging/flatpak/test_installer.py` checks these guards with temporary
homes/repositories and a fake Flatpak command ledger. It additionally validates
the generated `.desktop` and runs it through real `gio launch`, including spaces,
quotes, dollar signs, percent signs, backticks, equals signs and a backslash in
the selected path. Those tests verify helper behavior; the separate native
Flatpak sandbox report establishes actual app installation/runtime readiness.
See `packaging/flatpak/installer-test-report.json`.

## GitHub-hosted build

`scripts/ci/flatpak-setup.sh` prepares only an ephemeral GitHub-hosted
Ubuntu 24.04 x86_64 job. It installs the native LÖVE 11.5 package/dependencies,
Flatpak and D-Bus, then installs Freedesktop Platform and SDK 25.08 in a private
`RUNNER_TEMP` user installation. The selected branch is stable while exact
Platform/SDK commits and native binary hashes are recorded per build. It does
not install anything when run on an ordinary desktop; `--dry-run` prints the
plan without changing the machine.

The setup applies Ubuntu's user-namespace exception only inside that disposable
runner. This is needed for Bubblewrap on affected 24.04 images; it is not a
persistent end-user setting. See [Ubuntu's release notes](https://documentation.ubuntu.com/release-notes/24.04/)
and [Flatpak's own CI](https://github.com/flatpak/flatpak/blob/main/.github/workflows/check.yml).

After downloading the compiled Linux payload from the preceding job, build via:

```sh
dbus-run-session -- python3 packaging/flatpak/build.py \
  --payload dist/stage/linux/Love2Gathering \
  --output dist --work build/flatpak/application --version 2026.11.15.42
```

Preflight explicitly uses `flatpak build --runtime` to exercise the shipping
Platform rather than the SDK: native LÖVE, Python with SQLite/SSL/ctypes and the
bundled Java 21 must run before an export is created. The metainfo's newest
release receives the same nightly version/date as the artifact. Existing
release history remains present. `test_build.py` checks the command boundary,
failure behavior and metainfo update without modifying installed runtimes.

References: [Flatpak environment and FLATPAK_USER_DIR](https://docs.flatpak.org/en/latest/flatpak-command-reference.html#environment),
[system-wide custom installations](https://docs.flatpak.org/en/latest/tips-and-tricks.html#adding-a-custom-installation),
[Flatpak bundles](https://docs.flatpak.org/en/latest/single-file-bundles.html).
