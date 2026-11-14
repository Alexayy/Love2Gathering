# Love: 2 Gathering — agent instructions

This is a LÖVE 11.5 desktop frontend for the supplied XMage engine. Read `README.md` for the user flow and `CODEX.md` for the Codex development workflow. Inspect the current files before relying on a previous report.

## Architecture and ownership

| Area | Responsibility |
| --- | --- |
| `main.lua`, `conf.lua` | LÖVE lifecycle, callback routing, application identity and window defaults |
| `app/model.lua`, `app/priority.lua`, `app/api.lua`, `app/http_worker.lua` | Frontend state, native priority controls, asynchronous loopback requests and persisted preferences |
| `app/renderer.lua`, `app/table.lua`, `app/multiplayer_table.lua`, `app/table_camera.lua`, `app/layout.lua`, `app/match_ui.lua`, `app/log.lua` | Duel and multiplayer terrain, camera focus/pan, fixed hand, floating log/stack/actions, typed logs and logical hit coordinates |
| `app/board_fx.lua`, `app/card_choices.lua`, `app/deck_picker.lua` | Native-state overlays/animation anchors, staged image choices and card-based lobby selection |
| `app/library.lua`, `app/library_ui.lua`, `service/deck_import.py`, `service/tokens.py`, `service/history.py`, `service/artwork.py` | Import previews, token illustration preferences, recording-derived history and local artwork identity |
| `app/collection.lua`, `app/collection_ui.lua`, `service/precons.py`, `scripts/sync-precons.py` | Owned/Starter/product groups, whole-art square tiles, bounded historical product browsing and immutable-template copying |
| `app/profile.lua`, `app/profile_ui.lua`, `service/profiles.py` | Profile name/exact avatar/playmat identities, persistence and public native/replay presentation |
| `app/replays.lua`, `app/replay_ui.lua` | Recording browser, asynchronous frame loading, read-only playback and saved UI layouts |
| `app/rooms.lua`, `app/room_ui.lua`, `app/draft_ui.lua` | Invite-only multiplayer, private draft packs/pools, native deck submission and tournament presentation |
| `app/artwork.lua`, `app/gallery.lua`, `service/gallery_catalog.py`, `service/artists.py`, `scripts/download-card-images.py` | Bounded image/status cache, paged exact-printing artwork, reviewed illustrator links, resumable full-card/art exports and SQLite cache integration |
| `app/view.lua`, `app/builder.lua`, `app/builder_simplified.lua`, `app/lobby_ui.lua`, `app/deck_picker.lua`, `app/settings.lua`, `lib/Slab/` | Slab controls, shared Classic/Simplified builder layout, grouped lobby selection, modal input locks, settings panels and text input |
| `app/assets.lua`, `app/theme.lua`, `app/richtext.lua`, `app/fonts.lua`, `app/preferences.lua` | Curated glyphs/textures, Kenney skin, inline mana, installed fonts, effects, audio and applied presentation settings |
| `service/` | Streaming JSONL index, search/printings/art, deck construction checks and user storage; default port 17370 |
| `service/rooms.py`, `scripts/run-room-server.sh` | Network-facing room-code registry, desktop-local proxy and headless hosting; preferred port 17380 |
| `bridge/` | Loopback JSON transport, real human/AI players and prompt/state projection; default port 17371 |
| `bridge/src/love2gathering/MultiplayerBridge.java`, `RoomSeat.java`, `DraftSession.java` | Authenticated native coordinator, per-human perspectives, native packs/picks/Limited validation and Swiss/elimination pairing |
| `engine/mage/` | Pinned XMage Git submodule: rules, card implementations, format validators and MAD bot |
| `decks/` | Twenty curated Starter lists, compact prepared preconstructed source/provenance and deck validation tools |

The source JSONL is large. Stream it through `service/catalog.py`; do not load the entire file into a frontend table. The SQLite catalog is generated under `service/data/`. Maven downloads live under `.tools/`; Java build output lives under each module's `target/`.

Initialize XMage with `git submodule update --init --recursive` before building a fresh clone. The parent repository records the exact engine commit in its gitlink; keep `.gitmodules` and that gitlink together. Do not update the submodule to a newer upstream revision or discard engine changes as part of an unrelated task. Project integration code belongs in `bridge/`; any intentional engine source changes must be committed in the engine repository and made available before advancing the parent gitlink.

## Rules and engine boundary

- XMage owns runtime legality, timing, priority, mana production/payment, targets, costs, combat, stack resolution, state-based actions and triggers. Do not implement replacement Magic rules or mana-cost heuristics in Lua to decide what can be played.
- `NativeProjection` exports live permanent values separately from original printing/token identity. Preserve both during catalog enrichment. `PromptContext` describes only native offered choices; image-panel staging sends no answer until confirmation. Cancel only an actual offered native cancellation, before irreversible cost/effect commitment.
- Combat animation consumes unseen positive native damage events with `combat:true`, exact source/target and native damage step. Do not infer first/double-strike participation or retaliation from group membership or keywords. Retained event/step identities handle skipped polling snapshots; missing/redacted anchors never fall back to the screen center. Rope time is elapsed presentation, not a native deadline.
- Highlight and select cards from `prompt.actionable`. A present empty array means no card is actionable. Target selection uses the engine's target IDs; ability/color selections use their actual choice IDs and response types. Visibility alone does not grant playability.
- Preserve generic prompt coverage: booleans, UUIDs, strings, amounts, distributed amounts, modes, piles, targets, mana and simultaneous-trigger order. A source display name in a native ability event is metadata, not an answer choice.
- `prompt.manaWheel` and `choice.manaColors` describe options offered by XMage. Render them without inventing extra colors, abilities or mana.
- Use native mulligan metadata and responses. Regular games use paid London mulligans; Commander practice uses one free mulligan. The engine chooses the kept-hand size and requests bottom-card selections.
- Manual trigger order is left-to-right **resolution** order. The bridge reverses placement for the stack. Nested trigger processing remains in XMage. Do not request user ordering during simulation or playable-action calculation.
- Keep game execution on a thread whose name begins `GAME`, as required by the supplied HumanPlayer. Input threads deliver answers/signals; snapshots are prepared from game callbacks. Preserve real MatchPlayer records for AI simulation and sideboard access.
- Production game setup uses concrete engine cards, `loadCards`, player initialization and native format validation for both decks. XMage's test-zone helper belongs only in deterministic tests.
- Hide the bot's hand and unentitled face-down information in card views **and** choice labels. Public revealed cards and the human's looked-at cards must remain inspectable.
- Priority automation and phase stops live in `bridge/src/love2gathering/PriorityController.java`. Only native priority is auto-passed; target/payment/combat/mulligan/other choices remain interactive. Selected own/opponent steps can hold an empty bluff window. End Turn cancels on changed stack/turn/required choice, then applies ordinary native automatic priority; do not force an empty response after cancellation. The frontend shows acknowledged stop state and must hide an obsolete priority prompt while `priority.pending` is true. Old WAIT intentions migrate to native stops; old SKIP placeholders never execute.
- Draft packs, rotation, deadlines/autopicks, bot ratings/decks and tournament pairing/scoring remain native. Read capacities/options from native tournament types (currently 4–16 draft seats); do not invent Commander Draft or apply constructed deck rules to Limited pools. Submit pool UUIDs and offered basic quantities; failed validation must not mark a seat ready.
- Room codes carry origin/join secrets; seat credentials stay inside the local gateway. Never list public rooms or trust client game/player/winner IDs. Native coordinator routes require a private loopback bearer token. Disable `/client/*` on a headless/reverse-proxy host; a proxy's loopback address is not proof that its caller is local. Do not log or commit live invitation codes, seat tokens or coordinator secrets.
- Each real human has a separate prompt, priority state and entitled projection. Record only the designated host perspective into the hosting catalog; guest replay export must not reveal it. Deliberate draft departure uses native autopick on the existing seat, preserving picked instances; transient disconnect retains human ownership. Use native completed games bound to their draft/pairing to score outcomes.
- Starting order uses native server-owned `StartingOrder` 2d6 with tied-high rerolls; practice alone may choose a seat. Render `openingRoll`, never choose room outcomes in Lua. `PresentationGames` emits impact events only after successful native spell resolution; native mana value includes paid X. Keep impact motion on terrain/per-card poses with matching hit coordinates, honoring reduced motion and fixed hand/HUD.
- Fence frontend gameplay by connection and native game ID across rounds. Reopening a seat must preserve its submitted UUID selection. Close replay before adopting live room state, and clear prior gameplay routing for a bye/eliminated/completed seat. Keep the local practice session independent of room registries.

## Builder and storage

The catalog service performs deck construction checks against the supplied snapshot, including combined main/sideboard copy limits, basic-land and printed copy-count exceptions, Commander identity/eligibility/pairs, and sideboard limits. The native engine performs final validation when a game starts. Never present a successful snapshot check as proof that the installed XMage accepts the deck.

My Decks means `origin:user`. Starter exposes the original twenty bundled templates independently of older owned overrides/hidden selections; preconstructed products live in their own indexed table and bounded API pages. Preserve the legacy `/decks` lobby contract. Editing a template must fork a new user ID, and the client must adopt that returned ID. Invalid archival copies return their complete unsaved repair list and named validation errors; never silently remove cards or overwrite originals. Historical formats are browse labels, not current legality claims. Editable constructed formats remain Modern/Standard/Pioneer/Commander; Limited belongs to native draft pools. Preserve auxiliary planes/schemes in archived details and explain their exclusion before a constructed copy. See `service/PRECONS.md`.

An otherwise valid unfinished list may be saved with `draft:true` and `playable:false`. Illegal cards, excess copies, invalid commanders and identity conflicts are save errors with named cards; do not silently strip them. Preserve Commander partner/background and printed copy-count exceptions. Persist `coverCard`; sorting the displayed list must not alter card quantities or deck composition.

Storage and bridge input support up to 250 copies in a card entry as an application resource bound. This is separate from Magic's deck construction rules. Keep the transport/storage bounds aligned and do not describe that resource bound as a game-rule copy limit.

User saves and artwork caches have independently configurable directories. Resolve them through `service/paths.py`: explicit DATA/CACHE environment settings override saved locations. Fresh installs split images into `DATA/cache/images.sqlite`; existing combined stores stay combined until an explicit Locations preparation/restart. Preserve missing-drive errors, ownership checks, source/outbox fences, cancellation and staged recovery in `service/storage_locations.py`. Never silently create an empty replacement for a missing persisted store. Use temporary directories for storage tests. Preserve existing user data, the original JSONL, bundled lists and supplied engine source. Do not reset collections to make a test pass. Deleting a bundled deck from a collection hides it rather than deleting its source file.

`app.sqlite` is authoritative for saves, UI layouts and replay metadata/events. In a split store, `images.sqlite` is authoritative for artwork BLOBs and is attached as `images`; legacy combined stores still have `main.art_cache`. Use Storage helpers rather than assuming either table's database. JPEG exports are mirrors. Preserve transactional, restartable legacy migration and its markers; originals remain backups, never overwrite newer SQL data from old files. Keep WAL/busy-timeout/full-synchronous behavior and input bounds on both databases. Recordings use contiguous idempotent event sequences; conflicting retries must fail instead of silently replacing history.

Profiles store only bounded names and validated exact catalog printing/Oracle/face references for avatar/playmat art. No arbitrary image URLs or HP settings. Life always comes from XMage. Public identity travels with room/draft/native/replay seats; it grants no hidden-card access. Keep offline name updates possible for unchanged saved art references, and protect profile search/save responses from stale openings/edits. See `docs/PROFILES.md`.

Catalog API 10 is required by the launcher for storage/download/location controls and collection/profile endpoints. Compatible reuse must match configured database/cache storage and an explicit metadata-source override. Never stop an incompatible running user catalog to make room; select another owned port. Product-source refresh is explicit, checksum verified and streamed; it must preserve original metadata, cached images, user SQL data and the previous complete prepared source on failure. Do not run acquisition against an active user's files for acceptance.

The engine records authoritative projections and accepted actions into `replay-outbox.sqlite` before asynchronous delivery to the catalog. Keep recovery, explicit pending/error status and manual flush without ending a match. Playback renders saved projections, never reimplements the engine or exposes hidden information. Disable live action submission during playback. Protect frame and metadata loads with per-opening identity, including reopening the same recording ID; guard list refresh order and live revision order, and restore live prompt choices on close. A replay is not a resumable engine save.

Storage maintenance/download work belongs in `service/maintenance.py`, `service/downloads.py` and `app/storage.lua`. The shared resolver `service/paths.py` honors application/XDG overrides before adopting an existing store at the project mount root. Never silently migrate/delete the original home store. Purge/compact and image downloads share cross-process locks; active/pending replay outboxes must survive. Purged image categories use import barriers and a generation fence so old mirrors/plans cannot silently refill them. Keep completed match history when purging playback. SQL-only is the managed-download default; estimates are sampled/fallback ranges, not exact remote sizes. Test destructive actions only in temporary data directories. See `service/STORAGE.md`.

## UI, input and assets

- Initialize Slab with `Slab.Initialize(args, true)` and forward callbacks explicitly. Retain the unsupported-system-cursor fallback.
- `app/layout.lua` defines the logical coordinate system. Apply the same UI scale to drawing, mouse input, card hit regions, Slab and scissor rectangles. Render scale is a separate canvas scale. Test drag/drop and modals after changing either scale.
- Use `app/builder.lua`'s shared layout for drawing, panel positions, search page size and the drop target. Do not add independent hardcoded builder drop bounds.
- Keep text input UTF-8 safe. Verify caret placement, selection, Ctrl+A/C/X/V, word navigation/deletion, Home/End, held Shift and mouse drag selection when modifying Slab input. Preserve the user's clipboard around tests.
- Settings must affect the corresponding rendering, audio or accessibility behavior; adding a stored toggle alone is insufficient. Engine settings may apply at the next match; make their timing explicit.
- Beleren is the default display face for headings/deck names/card titles; application body fonts remain independently selectable. Keep fallback glyphs and Mana/Keyrune fonts intact. The title-family override must use the chosen application family. Square deck tiles fit the entire illustration into their image area; do not crop it into a strip or derive color identity from names/covers.
- Backgrounds use the supplied aspect-cover panoramas with real brightness and bounded decoded caches. Playmat opacity, Dice/Text exact counters, keyword reminders, cursor choice and existing audio controls must remain applied. Dice never wrap large values; counter names and native live P/T stay visible. Keyword explanations are presentation, never a source of legality. Future ideas in `docs/SETTINGS_IDEAS.md` are not implemented settings.
- Use the curated Mana/Keyrune/Kenney/audio assets through `app/assets.lua`. Read `assets/ASSET_GUIDE.md` before changing glyphs, icon orientation, transparent textures, nine-slice geometry or sound decoding. Keep source licenses and provenance alongside the assets. Do not replace a supplied font glyph with a guessed Unicode symbol or commit unused asset distributions.
- `app/surfaces.lua` owns luminance-to-alpha masks, bounded tiled quads, slider surfaces and card backs. Custom cursor selection goes through Slab's cursor provider to avoid transient system cursors, including text input. Preserve unsupported-platform fallback, hotspot scaling and visible font/caret metrics at both raster qualities.
- `app/startup.lua` warms only curated assets/modules and gates normal Model writes on actual launcher/service readiness. Keep startup failures visible and offline continuation explicit. Local revision display is not a network updater; never silently download full metadata or images during startup.
- Consult `assets/KENNEY_CATALOG.md` and `assets/kenney/inventory.json` for the supplied-pack audit and curated runtime provenance. Preserve user-supplied full packs; distinguish programmatic inventory/representative visual inspection from viewing every asset. Beleren's provenance is separate from Kenney CC0.
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
lua tests/rooms_model.lua
lua tests/api_rooms.lua
lua tests/table_camera.lua
lua tests/priority_model.lua
lua tests/gallery_model.lua
lua tests/artwork_model.lua
lua tests/card_traits.lua
lua tests/deck_picker_model.lua
lua tests/duplicate_model.lua
lua tests/modal_input.lua
lua tests/stack_presentation.lua
lua tests/library_model.lua
lua tests/collection_model.lua
lua tests/profile_model.lua
python3 decks/validate_library.py
tests/assets-input.sh
tests/richtext.sh
tests/quit_storage.sh
scripts/test-engine-fixtures.sh
tests/lobby_ui.sh
tests/multiplayer_ui.sh
tests/fonts.sh
tests/theme.sh
tests/assets_presentation.sh
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

`bridge/tests/test_multiplayer.py --url http://127.0.0.1:17372 --recording-port PORT` exercises real 4/5/6-player Commander starts, every bot's turn, hidden hands, native validation, concurrent projection readers and recording cancellation. Use an isolated catalog for `PORT`. `tests/multiplayer_ui.sh` uses synthetic states for actual input/scale checks; optional arguments supply saved native four/six-player projection JSON files for additional rendering checks. These are separate from completed full-game acceptance.

`LOVE2GATHERING_ENGINE_PORT=17372 LOVE2GATHERING_CATALOG_PORT=PORT tests/commander_live_ui.sh` starts real four/six-player games through actual lobby and opening-choice clicks. It requires explicit ports, an idle engine and catalog storage under `/tmp`; it replaces and stops those test matches.

`tests/priority_live_ui.sh` uses the same explicit isolated-port/idle-engine constraints and checks actual phase-stop, End Turn, Pass and full-control buttons against native production games. Its command ledger must not contain an old priority answer after End Turn or configure. `bridge/tests/test_priority.py` and `PriorityFixture` separately verify native priority policy and rejected-input recording behavior.

`LOVE2GATHERING_CATALOG_PORT=PORT tests/gallery_ui.sh` requires a temporary ready catalog with real image fixtures. Gallery and downloader tests use their own temporary storage; never point bulk-download acceptance at an existing user cache. Full-card and art-crop folders are export mirrors; configured SQL image storage remains authoritative. Artist URLs require reviewed sources and dates; unknown artists have no invented destination. Preserve the user-provided full Kenney packs/ZIPs and use only curated theme/runtime selections in application/test bundles.

`tests/global_controls_ui.sh` checks actual Beleren ink/caret geometry, tooltip pixels, cursor states, opacity/themes, the native ColorPicker and page/popup Settings. `tests/client_layout_ui.sh` and `tests/builder_modes_ui.sh` require an explicitly isolated catalog; the latter creates/removes only its own named test deck. Their reports retain actual clamped display dimensions. Builder geometry tests include Slab's extra 14px outer border. Modal guards must reject background presses, late drag releases and stale picker/duplicate callbacks, including Escape while a search input is focused. Current native keyword metadata is presentation only; preserve original printing keywords and use text when no verified icon exists.

Artwork is local-only by default (current catalog API 10/schema 7). Cache lookup preserves printing/face/kind; Gallery does not alias another illustrator's printing. Bot full-art playmats use the bounded supplied `full_art:true` metadata pool and native identity; no invented full-art labels or foreground download. Token resolution uses the original native token template, not modified current P/T/colors. Imports preview before explicit save and never bypass a provider's refused public access. History derives outcomes only from native recorded results. See `service/LIBRARY.md`.

Additional presentation/storage checks: `tests/presentation_refresh_ui.sh` covers real custom cursor transitions/UTF-8 selection, raster quality, masks, slider input and ancestor-clipped control hits. `tests/startup_ui.sh` checks actual curated decoding/graphics with a synthetic launcher ledger; `tests/startup-main-report.json` records a separate real-launcher smoke. `tests/storage_locations_ui.sh` uses a real isolated catalog for path inputs, folder picker, preparation/cancellation and source preservation. `tests/gameplay_presentation_ui.sh` renders native-contract dice/impact fixtures; `StartingPresentationFixture` and `ReplayRelocationFixture` separately verify native behavior. Keep those evidence scopes distinct.

`service/tests/test_precons.py` covers the actual packaged provider snapshot, bounded historical browsing, source/ownership preservation, unsaved invalid-copy repair and resumable acquisition. `service/tests/precons-live-report.json` records read-only actual service checks. `service/tests/test_profiles.py`, `tests/profile_model.lua`, native `ProfileFixture` and `tests/profile_live.py` cover separate storage/model/native/room-recording scopes. Use explicit owned services and restore isolated profile data. Graphical collection/profile checks need actual input and inspected captures; do not infer them from model/HTTP results. `tests/assets_presentation.sh` exercises real supplied fonts/icons, panorama pixels, exact dice, sound decoders, cursors and Slab settings dispatch without user saves.

`tests/collection_replay_ui.sh` and `tests/profile_ui.sh` require an explicit ready API-6 catalog whose data directory is under `/tmp`, actual prepared precons and real cached JPEG fixtures. They restore isolated layout/profile state and delete only their created deck copies. Collection/replay tests distinguish real catalog/fork operations from synthetic replay rows and profile-bearing table projections. `lua tests/collection_model.lua` covers stale save/fork routing, metadata edits during saves, Starter array tags and the 16-entry full-detail cache; `lua tests/keywords.lua` checks display-only reminders. Never clear dirty state or adopt a saved fork ID into a newer editor opening.

`lua tests/board_fx.lua`, `lua tests/card_choices.lua` and `lua tests/library_model.lua` check presentation/transport contracts. `tests/board_presentation_ui.sh` needs an isolated ready catalog with genuine cached Angel JPEGs and a saved native Angel frame; other added combat/attachment states are labeled presentation fixtures. `tests/native_choices_ui.sh` requires an owned test-only `NativeViewServer` on its explicit isolated port and a temporary catalog; it drives the actual application callbacks against deterministic native scenes. Never run it against a user's engine. `tests/room_rematch_live.py` uses an owned gateway/engine/catalog to complete and rematch two actual human-seat games and verify recorded win/loss history.

Use `scripts/build-engine.sh` after engine/bridge changes; for bridge-only iteration, the existing local Maven installation can package `bridge/pom.xml` using `.tools/m2`. Do not claim a new source change is accepted while testing an older running jar. Visually inspect real LÖVE screenshots for layout changes and record failed or unverified gates separately.

`docs/XMAGE_UPSTREAM_REVIEW.md` is a dated comparison, not permission or evidence for an engine upgrade. The integration remains pinned at `d9b266fc981024873ac7ec5f90ee7121a060725e`; evaluate a candidate in an isolated checkout with native/privacy/draft/profile/UI regressions before advancing its gitlink.

Room/draft protocol and hosting are documented in `service/ROOMS.md` and `bridge/DRAFT.md`. `tests/rooms_live.py` uses two explicitly isolated gateways and creates/closes only its own rooms; `bridge/tests/test_room_multiplayer.py` and `test_draft.py` need owned authenticated engines. Their acceptance data must not include live credentials. GUI tests with synthetic projections and actual native multiplayer/draft HTTP games establish different behavior; keep those scopes separate. WAN reachability/HTTPS hosting needs separate infrastructure verification.

When delegating, give agents disjoint file ownership, communicate protocol changes early and leave final integration to one owner. Shared-directory agents see each other's writes immediately. Update user and technical documentation to match the tested final behavior.


## Packaging

`packaging/README.md` documents release builds. Keep compiled payloads, runtime downloads, package tools and installers under ignored dist/build/.tools paths. Runtime payloads use explicit curated allowlists, not the entire checkout; never include user databases/caches, generated catalogs, secrets, full asset distributions or engine source. Preserve the pinned gitlink and precompiled bridge freshness. Installed supervisors must work from read-only paths, keep generated indexes/logs/engine files in writable user storage and stop only owned processes.

Shared/exclusive locks must retain native POSIX and Win32 behavior. Never use os.kill(pid,0) as a Windows liveness probe: use service/processes.py. Linux/Flatpak installers must quote both desktop-string and Exec layers, reject foreign paths/links, track their owned files/shortcuts and preserve saves on updates/uninstall. Windows setup exposes a directory page and keeps LocalAppData/Roaming saves outside the payload. Distinguish package construction, isolated installer execution, Wine tests, Flatpak runtime and actual native Windows/gameplay evidence.
