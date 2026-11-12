# XMage transport adapter

This process embeds the supplied XMage `1.4.63` Java engine. `HumanPlayer` receives user answers, `ComputerPlayer7` (MAD) controls the opponent, and `TwoPlayerDuel` / `CommanderDuel` own game execution. Both participants have real XMage `MatchPlayer` records, required by the bot's game simulations and by sideboard effects.

The adapter translates stock engine events to JSON; it does not calculate damage, costs, card effects, targets, state-based actions, combat legality, commander tax, or triggered effects. The built-in XMage format validators check submitted decks. Commander uses 40 starting life and the standard Commander validator, rather than the separate Duel Commander ban list.

Build once with `scripts/build-engine.sh`; run with `scripts/run-engine.sh [port]` (default `17371`). The build fetches Maven if necessary, compiles only the required XMage modules, then copies runtime dependencies to `bridge/target/lib`, including the SQLite JDBC driver. XMage's working directory is `data/engine`; launcher logs are in `.runtime`. Replay storage uses the configured user-data directory described below. The service binds only to `127.0.0.1` and serves one local practice game.

## Protocol

- `GET /health`: engine/version/implemented card count and any pending recording error.
- `POST /session/start`: `{format,playerName,botName,deck,botDeck,settings:{manualTriggers,autoMana},recordingPort}`. `recordingPort` is the actual catalog API v3 port, defaulting to 17370. Decks use `{main:[{name,count}],sideboard:[],commander:[]}`. Commander cards are passed to XMage as its commander sideboard. The recording is created before game execution starts; a replay-creation failure does not silently start an unrecorded game or replace an existing match. Deterministic test fixtures explicitly use `recordingPort:0`.
- `GET /session/state`: authoritative cached snapshot with players, human hand, hidden bot hand count, life, mana pool, battlefield, graveyards, command zone, exile, counters, stack, public revealed cards, the human's looked-at cards, turn/phase/step, log, and outstanding prompt. `prompt.actionable` contains the card IDs currently eligible for clicking/highlighting; an empty array explicitly means none.
- `POST /session/action`: `{promptId,type,value}`. Types are `uuid`, `boolean`, `integer`, `string`, `mana`, `multi_amount`, `order`, and `concede`. Generic choices contain `id`, `label`, `responseType` and an optional explicit `value`; absent an explicit value, send the ID. Mana values use names such as `WHITE` or `COLORLESS`. Distributed amounts use an integer array matching `prompt.amountMessages` and its per-entry/total limits.
- `POST /session/settings`: `{manualTriggers:boolean}`.
- `POST /session/replay/save`: explicitly flush the current recording without ending the game. Returns `{replayId,replayStatus,savedSequence,saved,recordingError,...}`. If the catalog is unavailable, events stay in the SQLite outbox and the response identifies the pending save.
- `POST /session/stop`: stop the current local practice game and await a bounded recording flush/finalization. Unsent events remain durable for recovery.

Each submitted card entry accepts 1–250 copies, matching the storage input bound. This is an application resource limit; native format copy-count rules and printed exceptions are checked separately. A targeted native-engine check loaded 250 Plains for each Modern player and rejected 251 at this input boundary; see `bridge/tests/input-bound-report.json`.

An `order` answer lists every trigger ID once, left to right in desired **resolution** order. The adapter reverses that list for XMage's bottom-first stack insertion. Auto mode deterministically places pending triggers without a dialog. Nested triggers and resolution remain entirely inside XMage.

Priority prompts derive their actionable IDs from XMage's `getPlayableObjects(Zone.ALL)` and the actual priority owner. Mana-payment prompts use `HumanPlayer.getUseableManaAbilities`; attacker/blocker prompts use the engine's possible-attacker/blocker lists. Visible cards that fail timing, mana, costs or land-limit checks do not become selectable simply by being visible. XMage validates each activation/cast and requests its targets/costs/choices as needed. Exiled Adventure/foretold/suspended cards, command-zone cards, playable top-library objects, and stock special actions (including delve/convoke) are accessible through the same prompt mechanism. Automatic mana payment is XMage's payment from the pool; the player selects mana sources through the engine's payment prompt.

When the engine offers multiple mana abilities or a mana-color choice, `prompt.manaWheel` contains `{sourceId,sourceName,kind:'ability'|'color'}`. Relevant choices have `manaColors` using `W/U/B/R/G/C`, obtained from native mana production or the actual engine color choices. Responses retain their ordinary UUID/string types. Generic ability prompts carry their source display name in `prompt.objectName`; that name is not an answer choice.

Actual opening-hand decisions have `prompt.mulligan:{keepChoice,mulliganChoice,downTo,currentHandSize,free}`. Both choice fields contain complete normal response objects. The engine's own mulligan options identify this prompt; the bridge does not infer it from displayed prose. Regular games use paid London mulligans and Commander practice uses one free mulligan. XMage also requests any required bottom-of-library card selections.

## Structured log and stack views

`snapshot.log` and `snapshot.logEntries` contain ordered objects with `{id,sequence,actorId,actorName,actor,category,text,sourceId,sourceName,origin,timestamp}`. Actor roles are `human`, `bot` or `system`. Categories include cast, resolve, attack, damage, draw, land, trigger, zone, turn, mana and system. Native XMage game events supply controller/player identity and action categories. General TableEvent text is retained; name-prefix fallback is performed only in the bridge when that event lacks an actor ID. `logText` supplies legacy text strings. The live snapshot retains its last 160 entries; replay storage retains the full event stream.

Stack entries include `sourceCard`, `sourceName`, `artName`, `controllerId`, `kind` (`spell` or `ability`), actual targets, `stackIndex` and `isTop`. The first entry has index 0 and is the next object to resolve. The source card provides artwork metadata and printed rules; ability-specific rules are used when available, with source-card text/type as the creature/vanilla-spell fallback. The frontend can render both card art and readable ability text without guessing the source from an ability's name.

## Durable SQLite replay recording

Every authoritative published frame, input action, structured log entry and engine error is serialized by the bridge, including transitions that occur between frontend polls. Simulations/playability calculations are excluded. Frames contain the projected human perspective: the bot's hand stays hidden, and unentitled face-down/hidden-card names are redacted. Replay playback uses saved projected frames; it is not a resumable engine save or a replacement rules engine.

The catalog API stores the authoritative replay metadata/events in `app.sqlite`. The bridge first commits outgoing events to `replay-outbox.sqlite` in the same configured user-data directory (`LOVE2GATHERING_DATA_DIR`, otherwise `${XDG_DATA_HOME:-$HOME/.local/share}/love2gathering`). The outbox uses SQLite WAL and FULL synchronous commits. There is no JSON/JSONL user-data spool.

A serialized worker sends idempotent sequence-numbered batches to `/replays/<id>/events`. Failed delivery retains every unsent event, retries with bounded backoff and surfaces `recordingError` through health/state. Completed/failed/aborted recordings are finalized only after queued events have been delivered. `state.replayId`, `replayStatus`, `replayPendingEvents` and `replaySavedSequence` expose progress; `saving` means final delivery is pending. Startup recovery reclaims orphaned outbox rows, retargets the current catalog port from `LOVE2GATHERING_CATALOG_PORT`, preserves already delivered events through idempotent retries, and leaves recordings owned by a live engine process alone.

Catalog replay endpoints are `/replays`, `/replays/<id>`, `/replays/<id>/events`, `/replays/<id>/frames` and `/replays/<id>/finish`. Frames/events have a global recording sequence and timestamp. This sequence is separate from each structured log entry's own log sequence.

## Acceptance checks

`scripts/test-engine-fixtures.sh` runs deterministic real-engine simultaneous trigger tests. Initial permanent zones are injected using XMage's own test setup helper; Grizzly Bears then really enters the battlefield. The tests assert automatic ordering, both manual left-to-right orders, two life-gain resolutions, and the two resulting nested Ajani's Pridemate counters. Results: `bridge/tests/trigger-report.json`.

The same command verifies native playability on empty and developed boards, the land limit, tapped/untapped mana sources, paid casting, stack/turn/priority restrictions, Shivan Reef's precise mana options, a real City of Brass color choice, and ordinary/Commander London mulligans. These tests inject initial zones but use actual engine actions and prompts for the assertions. Results: `bridge/tests/actionability-report.json`.

`python3 decks/test_engine_library.py --url http://127.0.0.1:17372` loads all 20 decks into an isolated running bridge, validates both decks, checks initial libraries/hands/commanders, and verifies that the bot's hand stays hidden. This replaces any current game on the chosen service.

`python3 bridge/tests/test_gameplay.py --url http://127.0.0.1:17372` drives an actual game against the bot, answering the same prompts as the frontend. It checks both players' lands, casts, resolution, damage/life changes, and a normal completed game; critical engine errors fail acceptance.

For recording acceptance, start isolated catalog/engine services with a temporary data directory, then run:

```sh
python3 bridge/tests/test_gameplay.py --url http://127.0.0.1:17372 --recording-port 17374 --output bridge/tests/replay-gameplay-report.json
python3 bridge/tests/test_replay_recording.py --engine-url http://127.0.0.1:17372 --catalog-url http://127.0.0.1:17374 --data-dir /path/to/temporary-data
```

The recorded real Modern game finished on turn 8 after 63 input actions. SQLite retained **413 authoritative frames**, although the test frontend observed only **138** revisions, plus 220 structured log entries: 696 contiguous recorded events. This establishes capture independent of frontend polling. `bridge/tests/replay-recording-report.json` verifies native actor/action categories, spell/ability source art/text and stack order, hidden bot hands in every frame, and reopening the persisted SQLite recording. It also verifies that explicit Save keeps a game running, then simulates an unavailable catalog and an owned recorder process crash: all three pending fixture events remain in SQLite, are recovered by a new process, and finalize as an aborted recording with no pending events. These durability fixtures are separate from the real-game proof.
