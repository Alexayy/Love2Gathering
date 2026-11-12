# Love: 2 Gathering — agent instructions

This is a LÖVE 11.5 desktop frontend for the supplied XMage engine. Read `README.md` for the user flow and `CODEX.md` for the Codex development workflow. Inspect the current files before relying on a previous report.

## Architecture and ownership

| Area | Responsibility |
| --- | --- |
| `main.lua`, `conf.lua` | LÖVE lifecycle, callback routing, application identity and window defaults |
| `app/model.lua`, `app/api.lua`, `app/http_worker.lua` | Frontend state, asynchronous loopback requests and persisted preferences |
| `app/renderer.lua`, `app/table.lua`, `app/layout.lua`, `app/match_ui.lua`, `app/log.lua` | Full-width table, hand fan, floating log/stack/actions, typed log presentation, hit regions and logical coordinates |
| `app/replays.lua`, `app/replay_ui.lua` | Recording browser, asynchronous frame loading, read-only playback and saved UI layouts |
| `app/view.lua`, `app/builder.lua`, `app/settings.lua`, `lib/Slab/` | Slab controls, shared builder layout, modal choices, settings panels and text input |
| `app/assets.lua`, `app/richtext.lua`, `app/preferences.lua` | Curated glyphs/icons, inline mana text, effects, audio and applied presentation settings |
| `service/` | Streaming JSONL index, search/printings/art, deck construction checks and user storage; default port 17370 |
| `bridge/` | Loopback JSON transport, real human/AI players and prompt/state projection; default port 17371 |
| `engine/mage/` | Pinned XMage Git submodule: rules, card implementations, format validators and MAD bot |
| `decks/` | Twenty bundled lists, catalog references and deck validation tools |

The source JSONL is large. Stream it through `service/catalog.py`; do not load the entire file into a frontend table. The SQLite catalog is generated under `service/data/`. Maven downloads live under `.tools/`; Java build output lives under each module's `target/`.

Initialize XMage with `git submodule update --init --recursive` before building a fresh clone. The parent repository records the exact engine commit in its gitlink; keep `.gitmodules` and that gitlink together. Do not update the submodule to a newer upstream revision or discard engine changes as part of an unrelated task. Project integration code belongs in `bridge/`; any intentional engine source changes must be committed in the engine repository and made available before advancing the parent gitlink.

## Rules and engine boundary

- XMage owns runtime legality, timing, priority, mana production/payment, targets, costs, combat, stack resolution, state-based actions and triggers. Do not implement replacement Magic rules or mana-cost heuristics in Lua to decide what can be played.
- Highlight and select cards from `prompt.actionable`. A present empty array means no card is actionable. Target selection uses the engine's target IDs; ability/color selections use their actual choice IDs and response types. Visibility alone does not grant playability.
- Preserve generic prompt coverage: booleans, UUIDs, strings, amounts, distributed amounts, modes, piles, targets, mana and simultaneous-trigger order. A source display name in a native ability event is metadata, not an answer choice.
- `prompt.manaWheel` and `choice.manaColors` describe options offered by XMage. Render them without inventing extra colors, abilities or mana.
- Use native mulligan metadata and responses. Regular games use paid London mulligans; Commander practice uses one free mulligan. The engine chooses the kept-hand size and requests bottom-card selections.
- Manual trigger order is left-to-right **resolution** order. The bridge reverses placement for the stack. Nested trigger processing remains in XMage. Do not request user ordering during simulation or playable-action calculation.
- Keep game execution on a thread whose name begins `GAME`, as required by the supplied HumanPlayer. Input threads deliver answers/signals; snapshots are prepared from game callbacks. Preserve real MatchPlayer records for AI simulation and sideboard access.
- Production game setup uses concrete engine cards, `loadCards`, player initialization and native format validation for both decks. XMage's test-zone helper belongs only in deterministic tests.
- Hide the bot's hand and unentitled face-down information in card views **and** choice labels. Public revealed cards and the human's looked-at cards must remain inspectable.
- Phase WAIT/SKIP buttons are explicitly labeled placeholder markers. They do not skip engine phases or automatically pass priority. Keep this distinction visible until a real engine command and its acceptance tests are implemented.

## Builder and storage

The catalog service performs deck construction checks against the supplied snapshot, including combined main/sideboard copy limits, basic-land and printed copy-count exceptions, Commander identity/eligibility/pairs, and sideboard limits. The native engine performs final validation when a game starts. Never present a successful snapshot check as proof that the installed XMage accepts the deck.

An otherwise valid unfinished list may be saved with `draft:true` and `playable:false`. Illegal cards, excess copies, invalid commanders and identity conflicts are save errors with named cards; do not silently strip them. Preserve Commander partner/background and printed copy-count exceptions. Persist `coverCard`; sorting the displayed list must not alter card quantities or deck composition.

Storage and bridge input support up to 250 copies in a card entry as an application resource bound. This is separate from Magic's deck construction rules. Keep the transport/storage bounds aligned and do not describe that resource bound as a game-rule copy limit.

User decks, settings, hidden bundled-deck selections and artwork caches live in the configured data directory, normally `${XDG_DATA_HOME:-$HOME/.local/share}/love2gathering`; `LOVE2GATHERING_DATA_DIR` overrides it for the launcher. Use temporary directories for storage tests. Preserve existing user data, the original JSONL, bundled lists and supplied engine source. Do not reset collections to make a test pass. Deleting a bundled deck from a collection hides it rather than deleting its source file.

`app.sqlite` is authoritative for all application saves, including artwork BLOBs, UI layouts and replay metadata/events. Preserve transactional, restartable legacy migration and its markers; originals remain backups, never overwrite newer SQL data from old files. Keep WAL/busy-timeout/full-synchronous behavior and input bounds. Recordings use contiguous idempotent event sequences; conflicting retries must fail instead of silently replacing history.

The engine records authoritative projections and accepted actions into `replay-outbox.sqlite` before asynchronous delivery to the catalog. Keep recovery, explicit pending/error status and manual flush without ending a match. Playback renders saved projections, never reimplements the engine or exposes hidden information. Disable live action submission during playback. Protect frame and metadata loads with per-opening identity, including reopening the same recording ID; guard list refresh order and live revision order, and restore live prompt choices on close. A replay is not a resumable engine save.

## UI, input and assets

- Initialize Slab with `Slab.Initialize(args, true)` and forward callbacks explicitly. Retain the unsupported-system-cursor fallback.
- `app/layout.lua` defines the logical coordinate system. Apply the same UI scale to drawing, mouse input, card hit regions, Slab and scissor rectangles. Render scale is a separate canvas scale. Test drag/drop and modals after changing either scale.
- Use `app/builder.lua`'s shared layout for drawing, panel positions, search page size and the drop target. Do not add independent hardcoded builder drop bounds.
- Keep text input UTF-8 safe. Verify caret placement, selection, Ctrl+A/C/X/V, word navigation/deletion, Home/End, held Shift and mouse drag selection when modifying Slab input. Preserve the user's clipboard around tests.
- Settings must affect the corresponding rendering, audio or accessibility behavior; adding a stored toggle alone is insufficient. Engine settings may apply at the next match; make their timing explicit.
- Use the curated Mana/Keyrune/Kenney/audio assets through `app/assets.lua`. Read `assets/ASSET_GUIDE.md` before changing glyphs, icon orientation, transparent textures, nine-slice geometry or sound decoding. Keep source licenses and provenance alongside the assets. Do not replace a supplied font glyph with a guessed Unicode symbol or commit unused asset distributions.
- Use `app/richtext.lua` for inline mana symbols in rules, costs and engine text. Keep logical metrics independent of render scale, premultiplied-alpha correction and bounded raster caches. Call `Assets.invalidateRasterCaches()` after successful native display-mode changes: LÖVE can clear Canvas pixels even when dimensions do not change.
- Slab `GetWindowPosition` already reports the outer title-bar position; `GetWindowSize` includes the configured border. Convert measured geometry back to requested geometry before saving or resetting it. Test idle stability, dragging, resizing and reopening persisted floating windows; do not let measurement feedback grow or drift panels every frame.
- Apply Slab size resets before calculating window dimensions. Clearing resize deltas after constructing the region produces a transient oversized frame that can corrupt saved geometry. Keep stack text indented for its whole column; `SetCursorPos` alone does not change subsequent text anchors. Replay stack geometry is stored separately so it leaves room for playback controls.
- Avoid copying the remaining input for every JSON number. Replay responses can be large; match at the decoder cursor and load bounded frame pages. Keep the real large-recording UI acceptance and codec regression.

## Verification

Run commands from the repository root. Choose checks that exercise the changed behavior; distinguish real-engine, real-service and synthetic-UI results.

```sh
python3 -m unittest discover -s service/tests -v
lua tests/frontend_model.lua
lua tests/builder_model.lua
lua tests/builder_layout.lua
lua tests/replay_model.lua
lua tests/json_codec.lua
python3 decks/validate_library.py
tests/assets-input.sh
tests/richtext.sh
tests/quit_storage.sh
scripts/test-engine-fixtures.sh
```

`tests/frontend_run.sh` requires a running catalog and checks real frontend/service saves and drag operations; its injected table/amount/trigger states are rendering fixtures. It is not a full engine game. LÖVE checks require a graphical environment and, for audio checks, the relevant audio module.

Use `tests/builder_integration.sh` and `tests/ux-run.sh` against an isolated catalog for construction/save behavior and responsive presentation. UX fixtures check real input dispatch, scaled popup deltas, visible settings pixels and applied native display/filter options; their game states are synthetic. Respect the actual window dimensions returned by LÖVE, since a desktop can clamp a requested mode.

`tests/table_replay_ui.sh` checks centered/crowded land rows, floating geometry and actual playback controls. It requires a catalog in a temporary data directory containing the completed 413-frame native acceptance recording; it rejects user-data directories. Its synthetic table checks are separate from opening the real native recording. `tests/quit_storage.sh` creates its own isolated catalog to prove callback-chained SQLite writes survive immediate client closure.

Vendored Slab fixes include UTF-8 selection/caret behavior, scaled mouse deltas, distinct internal component layout IDs, ignored-layout newline handling and ancestor scissor restoration. Nested input/combo controls inside scrolling forms must remain visible and clickable. A crash-free frame alone does not verify this; inspect captures and retain pixel/interaction regression checks.

After engine or prompt changes, use an isolated bridge:

```sh
scripts/run-engine.sh 17372
# In another terminal:
python3 decks/test_engine_library.py --url http://127.0.0.1:17372
python3 bridge/tests/test_gameplay.py --url http://127.0.0.1:17372 --output bridge/tests/gameplay-actionability-report.json
```

Those tests replace the game on the selected service. Do not run them against an active user match. `LOVE2GATHERING_ENGINE_PORT=17372 love .` points a test frontend at that bridge; `LOVE2GATHERING_CATALOG_PORT` also supports a separate catalog. The launcher selects available ports from these preferences/defaults and starts an owned engine for every desktop instance; it may reuse a compatible catalog. Stop only the processes started by the current test.

Use `scripts/build-engine.sh` after engine/bridge changes; for bridge-only iteration, the existing local Maven installation can package `bridge/pom.xml` using `.tools/m2`. Do not claim a new source change is accepted while testing an older running jar. Visually inspect real LÖVE screenshots for layout changes and record failed or unverified gates separately.

When delegating, give agents disjoint file ownership, communicate protocol changes early and leave final integration to one owner. Shared-directory agents see each other's writes immediately. Update user and technical documentation to match the tested final behavior.
