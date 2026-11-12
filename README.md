# Love: 2 Gathering

A LÖVE desktop client with Slab controls, a 2D Magic table and a fanned hand. **XMage runs the game**: legal actions, mana, combat, targets, stack resolution, triggers and the computer opponent. The client displays that state and sends your choices back to the engine.

## Start

XMage is a Git submodule pinned to the engine revision used by this client. Clone this repository with `git clone --recurse-submodules https://github.com/Alexayy/Love2Gathering.git`. For an existing clone, initialize it from the project root:

```sh
git submodule update --init --recursive
```

Install **Java 21, Python 3 and LÖVE 11.5**, then run:

```sh
./run.sh
```

The launcher starts the local card catalog, XMage and the desktop window. The first build downloads Java dependencies; if Maven is unavailable, the script downloads a local copy using `curl` and `tar`. The supplied large `assets/all-cards-20260922091740.jsonl` is indexed locally into `service/data/catalog.sqlite`. Indexing progress appears in the client.

Build and service logs are in `.runtime/engine-build.log`, `.runtime/engine.log` and `.runtime/catalog.log`. The launcher reuses a compatible catalog and starts a separate engine for each desktop instance, so opening another client preserves an existing match. It selects available local ports and stops only services it started.

`./run.sh --services-only` keeps the services running in a terminal and prints the exact command for connecting a client. `love .` opens only the frontend; use the printed port settings when those services are on nondefault ports.

## Decks and builder

The [included library](decks/README.md) contains five decks each for **Modern, Standard, Pioneer and Commander**. Pioneer includes **Izzet Phoenix** and **Lotus Field Combo**. Constructed starters contain 60 main-deck and 15 sideboard cards; Commander starters contain one commander and 99 other cards.

Use the deck manager to edit, duplicate, delete or choose lists for the lobby. Select a preview card as the deck's cover. The builder supports name/rules/type search, format/color/type/set filters, and name/color/set sorting. Double-click a search result or drag it into the list to add it; use `−` / `+` to change quantities. Choose the main deck, sideboard or commander zone before adding cards.

Saving checks format legality, copy limits across the deck and sideboard, Commander color identity and eligible commanders/pairs. Basic lands and cards with printed copy-count exceptions are handled separately. Errors identify the cards that need changes. An otherwise valid unfinished list can be saved as an explicit **draft**; it must meet the format's full construction requirements before play. XMage performs final validation when the match starts.

The application accepts up to 250 copies per card entry as an input resource bound; the format's game-rule copy limits still apply.

The catalog uses the supplied **September 22, 2026 snapshot**. Format changes are not fetched automatically, and the installed engine can reject a list even when the snapshot labels its cards legal.

## Lobby and table

Choose your deck and the bot's deck in the lobby; both use the same format. Commander practice uses normal Commander legality, **40 starting life and one free mulligan**, with a single opponent. Games are single-game practice sessions; between-game sideboarding and tournament scoring are not included.

The table uses larger cards and controls, with configurable UI scale. Your hand fans across the bottom. Hover to inspect a card and right-click for its full view. Click a highlighted card or drag it onto the table to choose a legal action. Card highlights come from XMage's current playable actions, including costs, available mana, timing, priority and the land limit.

During a match the application name and main navigation header are hidden. The field fills the window. Small mana-source rows sit centered lower in your field; crowded rows move left and overlap within their bounds. The icon toolbar opens the lobby, settings, log, stack and recordings. Hover over an icon for its label.

The log and stack are floating windows: drag their title bars or resize their edges. Their placement is saved. The log marks your actions in mint and the opponent's in purple, with separate colors and icons for casting, combat, damage, triggers and other actions. The stack shows source-card images and rules text, with the next object to resolve labeled first.

The opening-hand decision appears in the center with **Keep** and **Mulligan**, including the engine's resulting hand size. XMage asks for any required cards to put on the bottom of the library. When a mana source offers choices, its mana wheel shows the abilities or colors actually offered by the engine. Other prompts cover targets, modes, amounts, divided amounts and confirmations. Graveyard, exile and revealed-card views let you inspect relevant cards.

Use the compact action controls or **Space** to pass when the engine offers Pass / Done. Trigger ordering is automatic by default. Enable manual trigger ordering for a new match to drag simultaneous triggers left to right; **the leftmost resolves first**. Confirm the order to continue.

The phase buttons can cycle **WAIT / SKIP** labels. These are **placeholder markers only**: they do not skip a phase or automatically pass priority.

## Settings and artwork

Settings cover display mode/resolution, VSync, antialiasing, render scale, texture filtering, frame limit and UI scale; animations/particles; music, sound effects and volume; and accessibility options such as reduced motion, contrast, color-friendly palettes and tooltips. Use **Apply and save** for presentation changes. Trigger-order and automatic pool-payment settings apply when starting a match.

Automatic mana payment spends mana already in your pool. XMage still prompts you to activate mana sources when needed. Card details, rules and costs render inline Mana symbols, including hybrid costs and tap symbols. Card artwork downloads on demand and is cached locally; a first uncached image needs a connection. The supplied Mana/Keyrune glyphs, Kenney effects/UI/sounds and music are described with their licenses in [the asset guide](assets/ASSET_GUIDE.md).

## Recordings

New games are recorded automatically by the engine, including game-state frames, accepted actions and structured logs. The **Save replay** icon flushes the current recording without ending the game. Open **Replays** from the main navigation or the table's replay icon to browse and open recordings, including recordings from earlier launches. Playback provides pause/play, a timeline, previous/next frame and speeds from 0.5× to 8×. **Space** toggles playback; **Left / Right** step frames.

A replay is a read-only view of the recorded game; it does not resume a playable XMage session. The bot's hidden hand remains hidden. A recording interrupted by a process shutdown can retain its saved frames with an interrupted status. If the catalog is temporarily unavailable, the engine keeps events in a durable SQLite outbox and reports pending synchronization rather than reporting a successful save.

## Saved data

The application's user storage is **`app.sqlite`** in `${XDG_DATA_HOME:-$HOME/.local/share}/love2gathering`: decks and covers, preferences, hidden bundled lists, floating-window layouts, artwork image blobs and recordings. Set `LOVE2GATHERING_DATA_DIR` before launching to choose another directory. Existing JSON preferences/decks and JPEG caches are imported automatically; their original files remain as backups and are not used for new writes. SQLite uses WAL transactions; use SQLite's backup facility or close the application before copying its database.

`replay-outbox.sqlite` in that directory provides durable engine recording delivery during service interruptions. The generated card catalog is separately stored in `service/data/catalog.sqlite`. Bundled source lists remain in `decks/`; deleting one from your collection hides it without deleting that source. XMage's working files are in `data/engine`.

The catalog and engine bind only to loopback. Their preferred ports are **17370** and **17371**; the launcher selects another available port when needed. `LOVE2GATHERING_CATALOG_PORT` and `LOVE2GATHERING_ENGINE_PORT` also support explicitly configured services. This lobby is for local play against the bot. The bot is XMage's existing AI; its strength varies by deck, and complex Phoenix/Lotus Field decisions may be weaker than straightforward combat play.

## Verification and development

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

Verified engine evidence includes **20/20 deck startups**, automatic/manual simultaneous triggers with nested Pridemate counters, legal-action/mana-wheel/mulligan fixtures, and a complete **Modern bot game: eight turns and 65 actual engine prompt answers**. Both sides played lands, cast and resolved spells, life totals changed, and the game ended normally. See [the engine reports](bridge/README.md#acceptance-checks). This does not establish exhaustive card/combo coverage or optimal bot strategy.

The separate [recording report](bridge/tests/replay-recording-report.json) verifies a complete native game with **63 answers, 413 recorded frames and 220 log events**, reopening SQLite, spell/ability source artwork/text, hidden bot hands, saving during play and recovery after a catalog outage and recorder-process crash. Recording happens in the engine; it does not depend on frontend polling.

Actual LÖVE/Slab input checks cover UTF-8 editing, selection, clipboard shortcuts, caret placement and asset loading. Frontend tests that inject a game state verify their own rendering/interactions; real-engine acceptance is recorded separately.

With an isolated catalog running, `tests/builder_integration.sh` checks real saves, copy exceptions, rapid fifth-copy rejection and format changes. `tests/ux-run.sh` checks responsive rendering, centered mulligan dispatch, mana-wheel choices, trigger dragging, scaled popup movement and visible settings controls. Set `LOVE2GATHERING_CATALOG_PORT` to that test service; these tests must not use an active user's collection. UI captures distinguish the requested display size from the actual window size supplied by the desktop.

`tests/table_replay_ui.sh` additionally checks full-width table layout, centered/crowded mana rows, movable/resizable SQLite-backed panels and playback of an actual completed native recording. Use a temporary catalog containing the recorded engine acceptance game. Synthetic table fixtures establish layout, while the native recording establishes the content actually saved by XMage.

Technical architecture, safe test setup and contributor instructions are in [AGENTS.md](AGENTS.md). [CODEX.md](CODEX.md) records the Codex workflow used for implementation and verification.
