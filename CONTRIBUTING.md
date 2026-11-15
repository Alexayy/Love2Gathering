# Contributing to Love: 2 Gathering

Use issues for a reproducible bug or a proposed change, and open focused pull
requests against `development`. A private repository requires maintainer
access; receiving an installer does not grant repository access or rights to
its third-party content.

## Before changing code

Read [README.md](README.md), [CODEX.md](CODEX.md) and [AGENTS.md](AGENTS.md).
For graphics or sound, also read [the asset guide](assets/ASSET_GUIDE.md) and
[credits and usage rights](THIRD_PARTY_NOTICES.md).

Requirements are LÖVE 11.5, Java 21, Python 3.10 or newer and Pillow 9.1 or
newer for small image variants. Standalone model checks also need Lua 5.4. The launcher can use the retained local JDK
and Maven, or acquire its build dependencies as documented in README.

```sh
git clone --recurse-submodules https://github.com/Alexayy/Love2Gathering.git
cd Love2Gathering
./run.sh
```

Card metadata is a separate configured source. Do not commit generated
catalogs, user databases, image caches, downloaded card scans or installers.

## Preserve the engine boundary

XMage owns game rules, timing, priority, costs, payment, targets and outcomes.
Frontend work renders entitled state and sends offered choices; it must not
invent legality from card text or names. Preserve each human perspective's
hidden information and keep replay playback read-only.

`engine/mage` is pinned. Routine frontend/service/bridge contributions must
leave its gitlink, working tree and `.gitmodules` unchanged. Put integration
work in `bridge/`. Discuss an intentional engine change separately, make its
source available in the engine repository first, and verify it independently
before proposing a parent gitlink change.

## Work with isolated saves

Run acceptance and destructive storage checks only against temporary data.
For a separate development client, choose new directories:

```sh
task_data=$(mktemp -d /tmp/love2gathering-contrib.XXXXXX)
LOVE2GATHERING_DATA_DIR="$task_data/data" \
LOVE2GATHERING_CACHE_DIR="$task_data/cache" \
LOVE2GATHERING_CONFIG_DIR="$task_data/config" ./run.sh
```

Do not test game replacement, concession, purge, relocation or bulk downloads
against another person's running services. Use explicit isolated engine and
catalog ports for native tests. Stop only processes created by your test.

## Validate the changed behavior

Choose checks relevant to the change; the complete list and fixture scopes
are in AGENTS.md. Typical entry points are:

```sh
python3 -m unittest discover -s service/tests -v
lua tests/frontend_model.lua
lua tests/builder_model.lua
lua tests/replay_model.lua
lua tests/priority_model.lua
python3 decks/validate_library.py
git diff --check
python3 scripts/check-submodule-pin.py --index
```

UI changes need actual LÖVE input and inspected captures at a small window
and a scaled layout. A model test or crash-free frame does not prove that a
control can be reached or clicked. Preserve UTF-8 input, tooltips, modal
locks, UI scaling and current artwork identities.

Bridge changes require a fresh bridge build, not an old running JAR. Native
fixtures, real HTTP/service tests, synthetic UI scenes and completed games
prove different things; label them accurately. For example,
`python3 bridge/tests/test_library_top.py` owns its native fixture build and
storage. Never point a test at an active user's match to make it pass.

## Pull request information

Describe the concrete problem and the resulting behavior. Include:

- Reproduction steps, expected behavior and actual behavior.
- Relevant version/channel/revision from Settings → About.
- Tests run and their scope; note failed or unverified checks.
- Captures for layout changes and any data/protocol migration impact.

Redact private room codes, seat credentials, coordinator tokens, personal
paths and identifying replay details. Keep useful sanitized failure evidence;
do not include a user's saves or image BLOBs. Use small deterministic fixtures.

## Releases and submodule safety

Pushes on `development` produce `DEV-…` prereleases. Pushes on `master`
produce normal `v…` releases. The workflow builds the shared payload and
Windows EXE, DEB, RPM, Flatpak and Linux folder packages. Publication is
commit-bound and preserves already published assets; a retry may verify and
reuse a complete existing release.

The CI pin guard checks the parent commit range and index. Maintainers should
use `scripts/push-development.sh` for an authorized development push: it
disables recursive submodule pushes. Do not bypass a failed guard by resetting
someone's engine changes or silently changing the pin. An issue or PR alone
does not authorize a release or external message.

## Contribution license and asset provenance

By intentionally submitting project-authored code or documentation for
inclusion, you license that contribution under the project's [MIT](LICENSE)
terms. You keep your copyright. This does not transfer ownership of your
unrelated work, require a separate copyright assignment, or relicense vendor
components. Submit only work you can license on those terms.

For third-party code, fonts, images or sound, retain the actual license,
author, source URL, version and provenance. Discuss incompatible terms first.
Keep each component's notices and applicable source/replacement obligations.
Do not assume that free downloading, private sharing, attribution or a
removal promise supplies missing redistribution rights. Existing unresolved
material is identified in THIRD_PARTY_NOTICES.md; do not copy that exception
to new contributions or describe it as cleared.

Neither this project nor its MIT license grants rights to Wizards content,
third-party illustrations, trademarks or owner-supplied assets. The maintainer
will review substantiated rights-holder requests using the
[contact/removal process](CREDITS.md#owner-supplied-material-and-removal-requests).
