# Installers and release builds

The release targets **Linux x86_64** and **Windows x64**. Build products live in
`dist/`, with SHA256 digests in `dist/SHA256SUMS`. They contain the curated client,
precompiled pinned XMage bridge, dependencies, compressed card metadata and a
Java 21 runtime. They do not contain the developer's saves, replays, generated
catalog, downloaded card images or image-cache database. Illustrations download
only through the application's explicit image controls.

## Choose an installation folder

For a normal Linux user, use the **`.run` installer**. With no arguments it opens
a folder chooser when Zenity/KDialog is available, otherwise it asks in the
terminal. For a particular destination:

```sh
chmod +x dist/Love2Gathering-2026.11.14-linux-x86_64.run
./dist/Love2Gathering-2026.11.14-linux-x86_64.run --prefix /mnt/Games/Love2Gathering
```

The selected folder must be writable by the installing user. Install **Python
3.10+, Pillow 9.1+ with JPEG support and LÖVE 11.5** through the distribution
first (`python3-pil` on Debian/Ubuntu, `python3-pillow` on RPM systems); Java is included. No JDK,
Maven, Git checkout or XMage build is needed on the installed machine. The
installer creates `~/.local/bin/love2gathering`, an application-menu `.desktop`
entry and an optional Desktop shortcut (`--desktop-shortcut`). Paths with spaces
and literal `%`, quotes and `$` are supported. Run the installed `uninstall.sh`
to remove owned files/shortcuts; changed and untracked files are retained.

The equivalent **tar.xz** contains `install.sh`, `installer.py`, `uninstall.sh`
and `payload/`. Extract it, then run `./install.sh --prefix CHOSEN_FOLDER`.
See [Linux installation details](linux/README.md).

The **Windows setup `.exe`** has a Directory page for choosing e.g.
`D:\Games\Love2Gathering`. It includes Python, LÖVE and Java, creates a Start-menu
shortcut and offers a Desktop shortcut. Its default is a per-user Programs
folder. Installed Apps / its uninstaller removes application files while saves,
cache and settings remain outside the installation folder.

## System packages

The **DEB** installs the application under `/opt/love2gathering`, plus its command,
icon and application-menu entry. Its package dependencies are Python 3.10+ and
LÖVE 11.5. Install through the distribution's package manager:

```sh
sudo apt install ./dist/Love2Gathering-2026.11.14-linux-amd64.deb
```

DEB package paths are part of the package layout; use the `.run` installer for
a folder picker. This follows the [Debian filesystem policy](https://www.debian.org/doc/debian-policy/ch-opersys.html).

The **RPM** defaults to `/opt/love2gathering` and declares that prefix relocatable.
With its Python/LÖVE dependencies installed, a selected destination is supported:

```sh
sudo rpm -Uvh --prefix=/mnt/Games/Love2Gathering dist/Love2Gathering-2026.11.14-linux-x86_64.rpm
```

The package's registration helper creates menu/command links to the actual
prefix and removes only its matching registration on uninstall. RPM relocation
and scriptlet prefix variables follow the [RPM manual](https://rpm.org/docs/latest/man/rpm.8)
and [scriptlet documentation](https://rpm.org/docs/latest/manual/scriptlet_expansion).
Using DNF normally installs at the default prefix.

## Flatpak in a selected folder

Install Flatpak through the distribution. Keep `install-flatpak.py` beside the
`.flatpak` bundle; the helper opens a chooser or accepts an explicit location:

```sh
python3 dist/install-flatpak.py --prefix /mnt/Games/Love2Gathering-flatpak dist/Love2Gathering-2026.11.14-x86_64.flatpak
```

This uses a separate per-user Flatpak installation through `FLATPAK_USER_DIR`,
with an owned command and menu shortcut. Flatpak downloads the standard
Freedesktop 25.08 runtime if it is absent from that installation. The application
bundle includes LÖVE and Java; Python/SQLite/SSL come from the runtime. Use the
copied helper with the same `--prefix --uninstall` to remove this app while
retaining saved data and the repository. The [Flatpak environment documentation](https://docs.flatpak.org/en/latest/flatpak-command-reference.html)
describes the custom installation variable.

Network access supports the local bridge, room connections and explicit image
downloads. Host filesystem access allows Settings to choose external data/cache
folders. Those permissions are recorded in `flatpak/build.py`.

## Data and updates

The installed launcher keeps generated indexes, engine working files and logs
under writable user storage. It follows configured database/cache directories;
new installations use a separate `images.sqlite`. Windows and Flatpak privately
bundle checksum-pinned Pillow wheels, including their native codecs/licenses;
DEB/RPM declare the distribution dependency. Missing Pillow on a source or
chosen-folder Linux launch leaves original card images available and reports
that small-card image preparation is unavailable. The installed `--check`
requires a working JPEG decoder. Python bytecode generation is
disabled so launching does not populate the application folder. Installers do
not run Purge, relocate saves, or remove user data during uninstall.

Managed bulk downloads and image-pack imports yield to visible/selected image
requests in their catalog process. A separately launched downloader CLI has its
own I/O coordinator; it retains bounded SQL commits, WAL and the cross-process
bulk-job lock, but does not receive another process's foreground priority signals.

On first launch the splash indexes the supplied compressed metadata into the
user's generated catalog. Subsequent starts reuse the index. Existing saved
location checks and missing-drive errors remain active. See
[storage controls](../service/STORAGE.md).

## Build again

Every push to `development` or `master` runs [Installers and releases](../.github/workflows/development-release.yml)
on GitHub-hosted Ubuntu 24.04. It builds the pinned XMage bridge, Linux DEB/RPM,
the chosen-folder Linux installer/archive, Windows setup EXE and Flatpak. A dated
numeric version `YYYY.MM.DD.RUN` uses the commit's date in Europe/Belgrade and the
workflow run number. Retrying on another day preserves that version.
`development` produces `DEV-<version>-<attempt>-<SHA12>` prereleases;
`master` produces ordinary `v<version>` releases without the DEV prefix.
Every installer release initially leaves GitHub's Latest pointer unchanged.
A separate master-only job runs after successful publication, serialized under
`stable-latest`. It verifies the highest published four-part numeric stable
version and promotes only that release. Older builds finishing later therefore
cannot replace a newer Latest. Only these small promotion jobs share a queue;
installer builds and releases still run for every push. Each promotion rescans
published releases, so replacing a pending promotion does not lose a release.

The workflow publishes in
[GitHub Releases](https://github.com/Alexayy/Love2Gathering/releases) only after
all builds and required checks pass. It stages a draft, uploads the complete
asset set, verifies exact names, sizes, SHA256 digests, source commit, channel and
the pinned engine, then publishes. Existing tags must point to the same commit.
Only a matching unpublished draft can receive uploads. A published release is
never replaced: a retry validates its small manifest/checksum files and all
thirteen remote asset descriptors before skipping the build. A foreign,
incomplete or changed published release stops the job. Releases include SHA256SUMS,
installation instructions and source/runtime/metadata provenance. Actions keeps
only compact reports for seven days, avoiding another copy of the large
installers in artifact storage. This uses Releases rather than GitHub's
container/package registries.

The read-only release preflight, final publisher and separate Latest promotion
use the optional repository secret `RELEASE_TOKEN`, falling back to GitHub's
built-in token when that secret is absent. GitHub requires workflow write
authorization when a release's target commit changes `.github/workflows/`
relative to the repository's default branch; the built-in `GITHUB_TOKEN` cannot
be granted that permission. This includes a development release whose workflow
differs from the default master branch. Without the required authorization,
GitHub rejects publication and the workflow fails closed. See the official
[release API authorization notes](https://docs.github.com/en/rest/releases/releases#create-a-release).

For those releases, a repository owner can configure the supported token:

1. In GitHub account settings, open **Developer settings → Personal access tokens → Fine-grained tokens**.
2. Select the `Alexayy/Love2Gathering` repository and grant repository permissions
   **Contents: Read and write** and **Workflows: Read and write**. Choose an
   appropriate expiry; no other repository or administrative permissions are needed by this publisher.
3. In repository **Settings → Secrets and variables → Actions**, add a repository
   secret named **RELEASE_TOKEN** containing that token.

The workflow never writes that secret into checkout, build-tool environments,
files or command arguments. It is supplied only to the three release endpoints
listed above. No token is generated or repository secret created automatically.
Local fake-GitHub tests verify the release contracts; they do not establish that
a live repository permits a particular publication.

CI acquires current Scryfall **bulk metadata only** into an isolated build
directory. It does not download card illustrations or read a developer's SQL
databases. The source digest and upstream update time accompany the release.
Windows setup is cross-built with NSIS; this is not a native Windows gameplay
test. The compiled Linux service check uses temporary one-card metadata, and
the Flatpak builder probes the actual Platform runtime before packaging.

For a protected parent-only push after committing:

```sh
bash scripts/push-development.sh --check-only
bash scripts/push-development.sh
```

The helper accepts only this repository's `development` destination, fetches
without submodule recursion and checks **every outgoing commit** plus the index.
It rejects changes to the canonical `.gitmodules` or XMage gitlink, including a
temporary pin change restored by a later commit. It pushes one explicit parent
ref with submodule recursion and tag following disabled. Uncommitted files
inside `engine/mage` remain untouched and are not pushed. CI repeats the pin
check before initializing the recorded engine and before publishing; it never
updates the pin from upstream.

From the repository root, with an existing JSONL snapshot and already compiled
`bridge/target` + `bridge/card-map.json`:

```sh
python3 packaging/build.py --format all-linux --source assets/all-cards-20261114-scryfall-default.jsonl
python3 packaging/windows/build.py --help
python3 packaging/flatpak/build.py --help
```

Pass `--version YYYY.MM.DD.BUILD` to use the same version across all three
builders. A reused common payload must already carry that version. CI also passes
`--channel development --branch development --tag DEV-<version>-<attempt>-<SHA12>`
or `--channel stable --branch master --tag v<version>` to the common payload builder.
`app.love` contains a bounded `build-info.json` with that version, channel,
branch, tag, complete source/engine revisions and UTC build time for About.
No build-info file is generated into a source checkout. Local packaging uses the
`source` channel unless explicitly supplied a consistent release identity.

The Linux builder requires a Java 21 JDK with `jlink`, `dpkg-deb`, `rpmbuild`, and
Python 3.11+ for the build scripts. It can use the project's local JDK and locally
extracted RPM build tools; these stay outside Git under `.tools/`. Windows
runtime downloads have fixed upstream URLs/SHA256 values in
`windows/runtimes.lock.json`; NSIS produces the actual setup executable. Flatpak
uses the installed Freedesktop SDK/Platform 25.08 and the compiled Linux stage;
it does not require flatpak-builder. No installer compiles the engine at runtime.

The project LICENSE, CREDITS.md, THIRD_PARTY_NOTICES.md and component `licenses/`
are embedded in `app.love`; installed payloads also retain a separate licenses
directory, including asset notices, Slab's MIT header and nested JAR notices.
Windows/Flatpak preserve the bundled runtimes' own complete license trees.
Project and component licenses remain separate. The supplied Classic Magic / Mystic Eye backs are
not described as Kenney or CC0; their unchanged originals and provenance live
in `assets/card-backs/`.

## Verification scope

`linux/installer-test-report.json` covers real temporary-filesystem installation,
updates, archive safety, desktop parsing and special-character paths.
`linux/assembled-test-report.json` separately starts the actual packaged Java,
LÖVE, catalog, XMage and gateway through its installed symlink, then proves
uninstall preserves temporary saves/cache. Its metadata fixture is explicitly
small. Native package metadata/digests and extraction are distinct from running
an OS package-manager transaction. Windows/Wine and Flatpak acceptance reports
record their own runtime scope and limits. No check installs over the user's
existing application or alters the user's card library.
