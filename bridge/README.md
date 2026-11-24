# XMage transport adapter

## Native view metadata

`NativeProjection` preserves current permanent P/T/counters independently of original printing metadata. Tokens retain their original template for image matching even when effects change live stats/colors. It exports attachment/player-Aura links, entitled linked exile, native combat groups/legal blockers and stack target IDs. `PromptContext` describes offered card interactions for image-based scry/surveil/order/pile/board choices; IDs, selected toggles and response types remain native. Cancellation is offered only where the unfinished native action supports it, before committed costs.

Projections include priority/decision timestamps and a 128-entry `animationEvents` ring. Stable event IDs, source/target IDs, actual damage amounts, `combat` and native step distinguish damage from presentation. The frontend must not infer first/double-strike participation or blocker retaliation from card keywords or phase names. Native `zone` events carry `fromZone`/`toZone`; only an actual battlefield-to-graveyard transition is a death presentation. Hidden information remains redacted. Elapsed rope time is not a game deadline.

`NativeViewFixture` has 68 checks. Final priority HTTP and test-facade HTTP each have 17 checks; actual LÖVE/main/API acceptance has 29, recorded in `tests/native-choices-ui-report.json`. The facade and deterministic scenes are test-only. Room rematch/history acceptance completes two real human-seat games through the gateway (`tests/room-rematch-live-report.json`). Whole-board automatic land tapping is not exposed by this pinned engine; existing automatic pool payment remains available.

## Runtime

This process embeds the supplied XMage `1.4.63V2` Java engine, pinned to `2a96b0ac129dfd77946eaad536184d3b35fb5e64` (reviewed November 24, 2026). `/health.engineRevision` and the installed-card registry identify that exact revision. Each real participant has a `HumanPlayer` with its own response queue; `ComputerPlayer7` (MAD) controls AI seats. `TwoPlayerDuel`, `CommanderDuel`, `CommanderFreeForAll` and the native free-for-all execution configured for Limited own game execution. Every participant has a real XMage `MatchPlayer` record, required by the bots' game simulations and by sideboard effects.

The adapter translates stock engine events to JSON; it does not calculate damage, costs, card effects, targets, state-based actions, combat legality, commander tax, or triggered effects. The built-in XMage format validators check submitted decks. Commander uses 40 starting life, one free London mulligan and the standard Commander validator. Multiplayer uses native free-for-all attack/target/turn handling, with no range restriction; its starting player draws on the first turn. Existing two-player Commander practice retains its duel opening draw behavior.

Build once with `scripts/build-engine.sh`; run with `scripts/run-engine.sh [port]` (default `17371`). The build fetches Maven if necessary, cleans and compiles the required XMage reactor modules, regenerates the implemented-card map, then copies runtime dependencies to `bridge/target/lib`, including the SQLite JDBC driver. Cleaning prevents unchanged card classes from retaining old native method signatures after an upstream API change. Published JARs are readable by installed application users. XMage's working directory is `data/engine-<port>`; separate desktop engines therefore do not share the native H2 card repository lock. Launcher logs are in `.runtime`. Replay storage uses the configured user-data directory described below. The service binds only to `127.0.0.1`: `/session/*` serves the existing local practice game, while authenticated room endpoints maintain independent concurrent game and draft registries.

## Protocol

- `GET /health`: engine/version/implemented card count and any pending recording error.
- `POST /session/start`: `{format,playerName,deck,bots:[{name,deck},...],settings:{manualTriggers,autoMana},recordingPort}`. `bots` is authoritative when present and accepts 1–5 bots (2–6 total players); multiple bots require Commander. The lobby offers Commander duel and 4/5/6-player tables. Without `bots`, the original `botName`/`botDeck` single-opponent request remains supported. Every submitted bot deck is validated separately by XMage, with the seat named in any error. `recordingPort` is the actual catalog API v3 port, defaulting to 17370. Decks use `{main:[{name,count}],sideboard:[],commander:[]}`. Commander cards are passed to XMage as its commander sideboard. The recording is created before game execution starts; a replay-creation failure does not silently start an unrecorded game or replace an existing match. Deterministic test fixtures explicitly use `recordingPort:0`.
- `GET /session/state`: authoritative cached snapshot with players, human hand, hidden hand counts for every bot, stable zero-based player `seat`, `format`, `playerCount`, life, mana pool, battlefield, graveyards, command zone, exile, counters, stack, public revealed cards, the human's looked-at cards, turn/phase/step, log, and outstanding prompt. `prompt.actionable` contains the card IDs currently eligible for clicking/highlighting; an empty array explicitly means none.
- `POST /session/action`: `{promptId,type,value}`. Types include `uuid`, `boolean`, `integer`, `string`, `mana`, `mana_source`, `multi_amount`, `order`, and `concede`. Generic choices contain `id`, `label`, `responseType` and an optional explicit `value`; absent an explicit value, send the ID. Mana pool values use names such as `WHITE` or `COLORLESS`. A `mana_source` value is the exact offered choice ID for that payment prompt. Distributed amounts use an integer array matching `prompt.amountMessages` and its per-entry/total limits.
- `POST /session/settings`: `{manualTriggers:boolean}`.
- `POST /session/priority`: `{command:"configure",autoPass:boolean,stops:{own:["PRECOMBAT_MAIN",...],opponent:["END_TURN",...]}}`, `{command:"end_turn",promptId}`, or `{command:"cancel"}`. Configuration changes and cancellation safely re-query an outstanding priority prompt; they never answer a different dialog. End Turn requires the current genuine priority prompt ID. Initial `POST /session/start` accepts the same configuration under `priority`, applied before the GAME thread starts.
- `POST /session/replay/save`: explicitly flush the current recording without ending the game. Returns `{replayId,replayStatus,savedSequence,saved,recordingError,...}`. If the catalog is unavailable, events stay in the SQLite outbox and the response identifies the pending save.
- `POST /session/stop`: stop the current local practice game and await a bounded recording flush/finalization. Unsent events remain durable for recovery.

Each submitted card entry accepts 1–250 copies, matching the storage input bound. This is an application resource limit; native format copy-count rules and printed exceptions are checked separately. A targeted native-engine check loaded 250 Plains for each Modern player and rejected 251 at this input boundary; see `bridge/tests/input-bound-report.json`.

An `order` answer lists every trigger ID once, left to right in desired **resolution** order. The adapter reverses that list for XMage's bottom-first stack insertion. Auto mode deterministically places pending triggers without a dialog. Nested triggers and resolution remain entirely inside XMage.

Priority prompts derive their actionable IDs from XMage's `getPlayableObjects(Zone.ALL)` and the actual priority owner. Mana-payment prompts use `HumanPlayer.getUseableManaAbilities`; attacker/blocker prompts use the engine's possible-attacker/blocker lists. Visible cards that fail timing, mana, costs or land-limit checks do not become selectable simply by being visible. XMage validates each activation/cast and requests its targets/costs/choices as needed. Exiled Adventure/foretold/suspended cards, command-zone cards, playable top-library objects, and stock special actions (including delve/convoke) are accessible through the same prompt mechanism. Automatic mana payment is XMage's payment from the pool; the player selects mana sources through the engine's payment prompt.

During `play_mana`, pool choices carry `manaSymbol` and `manaCount` from the native pool view. A `mana_source` choice identifies the source and native ability, its previewed `manaColors`, and an inline `manaColor` where the native effect has a fixed color menu. XMage checks the activation and continues with any further choices. A plain source UUID also opens the existing native selection path. When that path offers multiple mana abilities or a mana-color choice, `prompt.manaWheel` contains `{sourceId,sourceName,kind:'ability'|'color'}` and responses use the offered UUIDs or strings. Spell choices in `choose_ability` carry a display label and `manaCost` separately from the source object's `prompt.objectName`.

Actual opening-hand decisions have `prompt.mulligan:{keepChoice,mulliganChoice,downTo,currentHandSize,free}`. Both choice fields contain complete normal response objects. The engine's own mulligan options identify this prompt; the bridge does not infer it from displayed prose. Regular games use paid London mulligans and Commander practice uses one free mulligan. XMage also requests any required bottom-of-library card selections.

## Structured log and stack views

`snapshot.log` and `snapshot.logEntries` contain ordered objects with `{id,sequence,actorId,actorName,actor,category,text,sourceId,sourceName,origin,timestamp}`. Actor roles are `human`, `bot` or `system`. Categories include cast, resolve, attack, damage, draw, land, trigger, zone, turn, mana and system. Native XMage game events supply controller/player identity and action categories. General TableEvent text is retained; name-prefix fallback is performed only in the bridge when that event lacks an actor ID. `logText` supplies legacy text strings. The live snapshot retains its last 160 entries; replay storage retains the full event stream.

Stack entries include `sourceCard`, `sourceName`, `artName`, `controllerId`, `kind` (`spell` or `ability`), actual targets, `stackIndex` and `isTop`. The first entry has index 0 and is the next object to resolve. The source card provides artwork metadata and printed rules; ability-specific rules are used when available, with source-card text/type as the creature/vanilla-spell fallback. The frontend can render both card art and readable ability text without guessing the source from an ability's name.

## Live characteristics and native decisions

Battlefield `power`/`toughness` now use XMage's final `MageInt.getValue()`. Its `toString()` describes the current base value and misses continuous boosts/counters. The separate `printing:{name,power,toughness,set,number,colors,type,type_line,subtypes}` preserves printing information, while `permanent:{power,toughness,damage,counters,tapped}` describes the live object. Native tokens use their original token template (or its current transformed face), so counters and color-changing effects do not alter their artwork identity. Angel of Vitality at 25 life with a +1/+1 counter therefore displays **5/5**, with printed **2/2** retained independently. Existing top-level counters/tapped/damage remain supported.

Cards also expose `ownerId`, `controllerId`, `colors`, `subtypes`, `attachedToId`, `attachedToPlayerId`, `attachmentIds`, and `linkedExile`. Source-linked exile reads existing native incarnation-specific exile zones and imprints; projection never creates an exile zone or changes a card's destination. Face-down linked cards stay anonymous unless this perspective has explicit native entitlement. Native tokens carry `token`/`isToken`; their observed native source uses `tokenSourceId`/`tokenSourceName` when known. Artwork selection remains separate from these live characteristics.

`combat:{step,attackerIds,blockerIds,groups}` projects native attack groups, including `attackerId`, `attackerIds` (banding), `defenderId`, `defendingPlayerId`, `blockerIds`, `blocked`, `minBlockers`, and `maxBlockers`. A native maximum of zero means no maximum. Stack objects add `targetIds` alongside `targets:[{id,name}]` and their existing `sourceId`/controller. These relationships are engine identities rather than text-derived targeting.

During blocker selection, `prompt.combat` provides `{role:"blockers",blockers:[{blockerId,legalAttackerIds,unavailable:[{attackerId,reason,rules}],preview:true}]}`. The preview invokes native blocker legality on XMage's isolated playable-calculation simulation, so restrictions cannot open a live dialog or mutate the match while projecting. Rule explanations come from native restriction effects. A selected blocker uses `{role:"block_target",blockerId,legalAttackerIds}` from the actual engine-offered target event. Complex restrictions can conservatively retain an unavailable preview when a decision is required; the live native offer remains authoritative. Menace's minimum blocker count is separate from pairwise eligibility and the engine validates the completed declaration.

Native scry/surveil and top/bottom ordering add `prompt.cardPanel`:

```text
{interactionId,kind,stage,cards,sourceId,zone,
 selectionDestination,remainingDestination,orderDestination,orderDirection,doneChoice}
```

`kind` identifies `scry`, `surveil`, generic `select`, or `piles`; `stage` is `select` or `order`. Each card carries its actual `choiceId`, `responseType`, `value`, `selected`, and `selectable`. Native `possibleTargets` and chosen-target metadata control actionability, including an explicitly empty eligible set; visible but ineligible cards remain inspectable. The transport still answers one native response per prompt. For scry, choose a subset for `bottom`, then the offered Done response leaves the remainder for `top`; surveil uses `graveyard` instead. Native top ordering is `last_chosen_topmost`, bottom ordering is `last_chosen_bottommost`, and the last remaining card is automatically placed. `interactionId` persists across these separate native prompts. Pile responses retain their native booleans and existing `pile1`/`pile2` card lists.

`prompt.cancelChoice` is an actual offered response, with `cancelScope:"pending_action"` and `pendingAction:{kind,sourceId,canCancel}` only while a cast/activation is incomplete. Woe Strider offers a false response before choosing its sacrifice; XMage rejects the incomplete activation and restores its bookmark. Once the sacrifice is selected and activation completes, its subsequent scry cannot restore that creature. There is no generic undo command, turn rollback, or cancellation of an already resolved effect. Unknown native prompts retain ordinary choices/amount/mana/order fallbacks.

Look-at callbacks are transient in XMage: its update event clears them immediately. The bridge retains up to eight immutable, entitled `lookedAt` groups per perspective, each with a fresh `id`, so polling can present and locally dismiss the popup. Remembered groups do not grant access to subsequent hidden changes. Other humans and host-only recordings retain their existing privacy boundaries.

`animationEvents` is a bounded ring of 128 native events with stable `id`/`sequence`, `type`, `nativeType`, `sourceId`, `sourceName`, `targetId`, `playerId`, `amount`, `combat`, `step`, and `timestamp`; zone events also carry `fromZone`/`toZone`. Types include cast, ability, resolve, damage, life_gain, life_loss, attack, block, counter, attachment, zone and step. Hidden source/target identities are masked. Native first/double-strike damage has its actual step and separate event identity. Log entries add entitled `sourceCard` and `stackEvent` for compact presentation.

The global `decisionPlayerId`/`decisionStartedAt` and `priorityStartedAt` allow every perspective to show the actual human holding a decision/priority; own prompts also carry `playerId`/`startedAt`. These are elapsed-time indicators. Current matches expose `clock.enabled:false` and no timeout penalty. `capabilities.automaticManaPoolPayment:true` describes the existing native pool payment; `automaticSourceTapping:false` is deliberate. The pinned HumanPlayer simplifies abilities/colors after the user chooses a mana source but has no whole-board automatic source-selection loop.

Recording participant metadata now includes a deck summary `{id,name,format}` without adding opponent composition to room recordings. Terminal native results include `completed`, perspective-relative `outcome`, `perspectivePlayerId`, native `winnerIds`/`winnerSeatIds`, and each player's actual `won`/`lost`. Only an ended, error-free, non-aborted native game is classified win/loss/draw.

`NativeViewFixture` (included in `scripts/test-engine-fixtures.sh`) verifies boosted Angel P/T/counters, real scry/surveil placement and order, precommit Woe Strider cancellation, committed-sacrifice preservation, flying/reach/landwalk/unblockable/menace, attachments, entitled linked exile, native tokens, stack targeting and structured damage/life events. Its initial zones are deterministic native fixtures; these are not frontend results. `bridge/tests/native-view-report.json` records this scope.

[Combat timing and confirmation](../docs/COMBAT_TIMING.md) documents the native before-damage stop, provisional versus confirmed blockers, sacrifice/trample/first-strike cases, current keyword metadata and elapsed-priority lane. `CombatTimingFixture`, included in the native fixture gate, uses production bridge responses with deterministic native zones; `tests/combat_timing_ui.sh` separately exercises actual UI input against a test-only Ayara scene. Current cards expose `currentRules`, recognized native `keywords` and native `abilityIcons`; original `printing.keywords` remains separate so temporary trample is visible.

For actual UI answers against those native positions, the test-only facade is separate from the production bridge:

```sh
bash bridge/tests/run_native_view_server.sh 17464
python3 bridge/tests/test_native_views.py --url http://127.0.0.1:17464
```

Use Java 21 on `PATH` and an isolated test port. This facade is compiled only into test classes, binds loopback, and has `POST /fixture/{angel,scry,surveil,cancel,combat,look}` to replace its own fixture. Gameplay reads `/session/state`; input invokes the production `Session.action`. `GET /fixture/result` exposes the actual native resulting zones/activation/combat plus accepted-input receipts. It never registers fixture routes in the production JAR, starts a user match, or writes to user storage. HTTP fixture checks, actual GUI input checks, and full production-deck games remain separate evidence.

## Durable SQLite replay recording

Every authoritative published frame, input action, structured log entry and engine error is serialized by the bridge, including transitions that occur between frontend polls. Simulations/playability calculations are excluded. Frames contain the projected human perspective: the bot's hand stays hidden, and unentitled face-down/hidden-card names are redacted. Replay playback uses saved projected frames; it is not a resumable engine save or a replacement rules engine.

The catalog API stores the authoritative replay metadata/events in `app.sqlite`. The bridge first commits outgoing events to `replay-outbox.sqlite` in the same configured user-data directory (`LOVE2GATHERING_DATA_DIR`, otherwise `${XDG_DATA_HOME:-$HOME/.local/share}/love2gathering`). The outbox uses SQLite WAL and FULL synchronous commits. There is no JSON/JSONL user-data spool.

A serialized worker sends idempotent sequence-numbered batches to `/replays/<id>/events`. Failed delivery retains every unsent event, retries with bounded backoff and surfaces `recordingError` through health/state. Completed/failed/aborted recordings are finalized only after queued events have been delivered. `state.replayId`, `replayStatus`, `replayPendingEvents` and `replaySavedSequence` expose progress; `saving` means final delivery is pending. Startup recovery reclaims orphaned outbox rows, retargets the current catalog port from `LOVE2GATHERING_CATALOG_PORT`, preserves already delivered events through idempotent retries, and leaves recordings owned by a live engine process alone.

Catalog replay endpoints are `/replays`, `/replays/<id>`, `/replays/<id>/events`, `/replays/<id>/frames` and `/replays/<id>/finish`. Frames/events have a global recording sequence and timestamp. This sequence is separate from each structured log entry's own log sequence.

## Acceptance checks

The November 17 upstream upgrade is recorded in `bridge/tests/upstream-integration-report.json`. A clean build at the exact pin passes the eleven existing native suites, the 51-check upstream fixture, 20 bundled deck startups, a completed eight-turn game with 37 interactive answers and 69 automatic native priority passes, durable replay recovery (496 frames), 17 priority HTTP checks, 30 multiplayer/privacy checks and 58 draft HTTP checks. Separate native library-top, recovery and gameplay-presentation runs pass 37, 38 and 52 checks. The summary records source/payload hashes and each evidence scope; it does not claim GUI or installer acceptance.

`UpstreamCompatibilityFixture` verifies all 34 new concrete card classes, the new NAU/NAC/PW27 map entries, unchanged cards linking against changed native target filters, mana activation events without a stack object, Loot's native exhaust-mana color response and Sanctum Lurker's zero-loyalty exception. The adapter continues to project the engine's decisions; no engine source or frontend legality rules changed.

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

## Multiplayer acceptance

Run `python3 bridge/tests/test_multiplayer.py --url http://127.0.0.1:17402` against an isolated bridge. It starts real bundled Commander decks for 4, 5 and 6 players, checks 40 life, free mulligan metadata, every commander/library/hand, hidden bot hands and target IDs for every seat, then drives native priority through a complete turn cycle at each table size with actual MAD bot land plays. It also checks bot-count limits and native validation of the third bot's deck. `--recording-port <isolated catalog port>` additionally flushes each live recording, checks every saved frame for hand privacy and every metadata participant, and verifies stopping cancels all bots and finalizes the recording. This is startup/turn-cycle coverage, not a completed Commander-game proof. Results are saved to `bridge/tests/multiplayer-report.json`.

`bridge/tests/love2gathering/MultiplayerFixture.java` separately verifies native Lightning Bolt targeting/payment/resolution against each of three opponents. Its initial cards/mana are deterministic test resources; it does not establish production deck startup or frontend interaction. Compile it together with the existing trigger/actionability fixtures and run `love2gathering.MultiplayerFixture <repository root>` using the bridge runtime classpath. Results are saved to `bridge/tests/multiplayer-targeting-report.json`.

Local-practice recording metadata preserves `playerCount`, all bot names/decks in `bots`, and every participant ID/seat in `metadata.players`, while retaining the legacy first `botName`/`botDeck` fields for existing recording browsers. Room recordings use the narrower host-only policy below and omit opponents' deck lists. Saved frames preserve the complete multiplayer projection and human-only hand perspective. Projections are published atomically after construction so concurrent HTTP readers never observe a partially filled map. Stopping a table sends cancellation to every native player, including surviving bots.

The current multiplayer report, with automatic priority enabled, passed all three full turn cycles (13 human prompt answers total), inspected 653 recorded frames and completed 5,702 concurrent snapshot reads without a read error. The deterministic fixture separately resolved three Lightning Bolts, one against each opponent, and checked hidden choice labels plus entitled revealed/looked-at cards. Regression checks passed all 20 existing duel deck starts and the trigger/actionability fixtures. With the final priority controller, a complete Modern bot game finished on turn 7 after 35 human answers; see `bridge/tests/priority-gameplay-report.json`. These are separate scopes: this report does not claim a complete multiplayer Commander game.

## Automatic priority and real stops

Automatic priority defaults to enabled with empty own/opponent stop lists. `BridgeHuman.priority` asks XMage for native playable abilities, excludes only abilities classified by XMage as mana abilities, and checks native special actions. When no meaningful action remains, it calls the stock HumanPlayer pass/mana-pool-check path on the GAME thread. Mana sources alone do not keep empty priority open and are never activated by this policy. Legal spells (including instant/flash), land plays and non-mana activations retain an interactive prompt. XMage's playable calculation is conservative about targets, so a spell with no valid target can retain an extra prompt; the bridge does not invent legality or infer costs from card text.

All stock native phase windows are enabled and stock cast/activation skip preferences are disabled for this transport, so they cannot silently bypass an explicit stop. Native step names are the `PhaseStep` enum names (`UPKEEP`, `DRAW`, `PRECOMBAT_MAIN`, `BEGIN_COMBAT`, `DECLARE_ATTACKERS`, `DECLARE_BLOCKERS`, `FIRST_COMBAT_DAMAGE`, `COMBAT_DAMAGE`, `END_COMBAT`, `POSTCOMBAT_MAIN`, `END_TURN`, `CLEANUP`). Untap has no priority window and is rejected. A configured stop holds once per native step occurrence, including a distinct extra phase, even with no legal action: it can be used to bluff. Passing or choosing an action acknowledges that stop. A disabled automatic-priority setting is full control and holds otherwise empty windows too.

End Turn explicitly yields the currently offered priority and subsequent ordinary priority in that same turn. It intentionally yields available own-turn actions such as another land or sorcery. It cancels on a newly added stack object or a new turn. After cancellation, normal automatic priority continues: it holds for a meaningful native reaction or full control and passes an empty window. A selected stop always holds, including an empty bluff window. The original existing stack is remembered so explicitly yielding a current response does not immediately re-open that same response. Every target, payment, attacker/blocker selection, mulligan, trigger order, mode, amount and other engine question remains an actual native choice and cancels an armed yield. No native broad skip flag is used. Cancel removes the yield; full control also removes it.

`snapshot.priority` contains `autoPass`, canonical `stops`, `yielding`, `pending`, `paused`, `reason`, readable `status`, current canonical `step`, `turn`, `activePlayerId`, `stopStep`, `stopPlayerId`, `meaningfulActionCount`, `autoPassCount` and `canEndTurn`. Genuine priority prompts contain `priority:true` and `priorityReason`. Reasons are `action`, `stop`, `manual`, `new_stack`, `new_turn`, `choice`, `auto_pass`, `yield` and `waiting`. The stop actor/step are explicit acknowledgement from XMage, rather than a frontend prediction. Initial configuration is saved in recording metadata; automatic accepted passes and explicit commands are recorded, and every frame retains the applied priority view. Playback does not submit these commands. HTTP responses expose a prompt only while the published projection's prompt is still the same current pending prompt. An answered prompt disappears immediately; a new prompt waits for its complete GAME-thread projection, rather than accompanying an older board. `canEndTurn` also requires an acknowledged, paused, non-pending priority window. Stale or malformed transport actions fail validation before entering accepted replay history.

`scripts/test-engine-fixtures.sh` includes `PriorityFixture`: real native empty/mana-only passes, payable Lightning Bolt and Ambush Viper flash holds, empty opponent end-step bluffing and acknowledgement, repeated phase stops, full-control updates, cancellation, End Turn interruption by a real bot Shock/new stack, selected stop and new turn, interactive native attackers/targets/mana payment, and gated GAME publication proving that new prompts wait for their full projection and consumed prompts cannot reappear. Only initial resources and turn positions are fixtures. `bridge/tests/priority-report.json` records the results.

`python3 bridge/tests/test_priority.py --url http://127.0.0.1:17402 --recording-port 17400` separately starts an ordinary validated all-Plains game and exercises the real HTTP controls, initial persisted stops, automatic upkeep priority, End Turn/new-turn cancellation without an empty extra question, empty opponent end-step pause, full control, cancellation and malformed/stale request rejection. With the isolated catalog it also checks that automatic passes and commands were recorded while rejected stale/malformed attempts were not. Three concurrent readers verify response coherence during automatic advancement and command refreshes. Results: `bridge/tests/priority-http-report.json`. These establish native and transport behavior; actual frontend button/layout evidence is separate.

The engine build packages the bridge in a temporary directory and publishes JARs by atomic rename. An already running desktop engine can continue reading its previous open JAR while a new client uses the rebuilt version.

## Private room coordinator protocol

`service/rooms.py` owns invitation codes, membership tokens and remote client authorization. It brokers the following native endpoints; clients never receive the coordinator bearer secret. `/multiplayer/*` and `/draft/*` require loopback transport plus `Authorization: Bearer ...` matching `LOVE2GATHERING_COORDINATOR_TOKEN` (at least 24 characters). Existing `/session/*` remains compatible and independent: starting a room match does not replace a local practice game.

- `GET /multiplayer/capabilities`: actual native game bounds, installed draft procedures/sets/cubes/timing choices and deck profiles. Commander and Limited free-for-all support 2–10 total seats; ordinary Modern/Standard/Pioneer games use two. The existing local Commander bot lobby retains its 2/4/5/6 choices. Native drafts support their own 4–16-seat procedures, then create independent paired Limited duels.
- `POST /multiplayer/start`: `{format,seats:[{seatId,name,type:"human"|"bot",deck,settings?,priority?},...],recordingPort?,recordingSeatId?,idempotencyKey?}`. Returns `{gameId,seats:[{seatId,playerId,name,human,seat},...],running}`. Every submitted deck passes its native format validator. The stable coordinator `seatId` is distinct from each game's native `playerId`.
- `GET /multiplayer/state?gameId=...&playerId=...`: that real human's private projection only. `players[].human` and `isLocal` identify the requesting perspective; `isHuman` distinguishes every actual human from AI seats. Only the local hand and its entitled looked-at cards are inspectable. Opponent hands contain counts and empty card lists. Private logs, prompts, mana choices, trigger ordering and priority controls belong to that same perspective.
- `POST /multiplayer/action` and `POST /multiplayer/priority`: include `gameId`, `playerId` and the existing action/priority fields. Human views share a prompt ID source so another seat's question cannot accidentally match a local outstanding ID. Unknown players, bot perspectives, foreign/stale prompt IDs and malformed values fail before accepted-action recording. The gateway binds identities from its authenticated member mapping, overriding client-supplied identities.
- `GET /multiplayer/result?gameId=...`: cached public `running`, `error`, `players` with IDs/seat IDs/life/win/loss, and `winnerSeatIds`. It contains no hands, choices or private card lists. This also serves bot-versus-bot pairings: the observer projector is not inserted as a fake human participant or `MatchPlayer`.
- `POST /multiplayer/replay/save`: `gameId` and the designated recording owner's `playerId`; flushes that recording without ending the match. Guests receive an explicit host-recording rejection.
- `POST /multiplayer/stop`: `gameId` or the original start's `idempotencyKey`; ends only that stored native game, returns its public result, and releases its registry/card graph. Repeated cleanup succeeds. Conceding through `/multiplayer/action` instead surrenders only that human seat.

A room owns one native `Game`, one real `Match` and one `GAME ...` execution thread. Each participating human owns a separate projection/session view, `BridgeHuman` response queue, prompt, priority controller and trigger queue. Game callbacks publish the complete projections and record them; HTTP threads only deliver responses or native asynchronous signals. Concession uses native `setConcedingPlayer` plus a wake signal so a nonactive player can concede while another human is choosing. XMage processes the queued departure on its GAME thread and either ends the game or resumes the unanswered dialog. Global stop cancels every real human and AI in that one game.

## Native drafting and paired results

[Native drafting details](DRAFT.md) describe the supplied booster/random/cube procedures, private pack/pool state, native deadlines/autopicks, offered basics, Limited construction, explicit departure and tournament pairing. Native routes are `GET /draft/options`, `POST /draft/start` (`config`, `seats`), `GET /draft/state`, `POST /draft/pick`, `POST /draft/deck`, `POST /draft/forfeit`, `GET /draft/deck-source`, `GET /draft/pairings`, `POST /draft/next-round`, `POST /draft/result` and `POST /draft/stop`. A draft operation carries `draftId`; private operations additionally carry the stable `seatId`.

Paired game creation includes `draftId` and `pairingId`. It accepts exactly that native pairing's seats and replaces supplied decks with their stored, native-valid draft deck sources. `/draft/result` accepts only a completed, unstopped, error-free native `gameId` bound to that draft/pairing. It derives the winner from the engine instead of accepting a client winner, then invokes native tournament scoring. A repeated result from the same bound game succeeds; a different game cannot replace an accepted result. Elimination draws require a new native rematch. Sixteen draft participants produce eight independent two-player games, including fully native AI-versus-AI games where required.

The host catalog records only the explicitly designated `recordingSeatId` perspective, and only when that host participates. Other human hands and private answer values are absent from its frames and metadata; other participants' accepted inputs are represented by a redacted remote-action marker. Room snapshots expose `replayAvailable` only to that owner and explain that the host saves the room replay to other participants. Paired games without the host use `recordingPort:0`. This version does not store guests' personal private recordings on the host or promise remote personal replay delivery.

## Lost responses and cleanup

Room game starts and draft starts accept an optional `idempotencyKey`. The coordinator keeps the exact original request body when retrying: canonically equivalent object-key order returns the same native identity, and a different body conflicts. Stopped starts retain a tombstone and cannot be recreated under their old key. Key-only stop can reclaim a successful start whose HTTP response was lost; closing an as-yet unknown start key tombstones it too, so a late request cannot create a match after the room closes.

`POST /draft/next-round` also accepts an `idempotencyKey`. A same-body retry returns the originally accepted round snapshot instead of generating another round. Native result retries are bound to the same draft/pairing/game identity. `/multiplayer/stop` and `/draft/stop` accept repeated cleanup; draft stop also removes its linked games. Coordinators retain completed game contexts for result display and replay saving, then explicitly stop them before advancing or closing the room.

Start receipts are bounded at 4,096 game keys and 4,096 draft keys per coordinator process; round receipts have a separate 4,096-entry bound and are reclaimed with their draft. New keys fail explicitly at the application resource bound; existing accepted retries remain valid. These bounds do not change native format player counts or Magic deck rules. Room/game/draft execution remains in-memory and is not a resumable engine save after process shutdown.

`RoomMultiplayerFixture` and `DraftFixture` are included in `scripts/test-engine-fixtures.sh` alongside the original four fixtures. The room fixture proves four real human MatchPlayers, genuine targeting/damage, private hand/look entitlement, public reveals and isolated stops/yield using deterministic initial resources. The draft fixture exercises complete native procedures and tournament adapters; fixture-supplied result cases are labeled separately from real games. `test_room_multiplayer.py` uses normal production deck loading for actual 2-human, 4-human and mixed tables, private host recording, independent simultaneous games, nonactive concession, bot-only completion and start/cleanup retry fences. `test_draft.py` performs the separate 180-human-pick draft-to-real-games/result/next-round HTTP flow and retry checks. These are native/transport checks; invitation authorization, gateway lifecycle, actual LÖVE interaction and off-machine connectivity have separate evidence.

## Isolated authenticated HTTP checks

After building with Java 21 available, this repository-root example creates a mode-0600 token without printing it, starts only owned test processes, passes the same token through the engine environment and each test's `--token-file`, and stops those processes afterward. It refuses occupied test ports. The temporary catalog is used for replay storage; its intentionally missing bulk source is not used by these native card/draft checks.

```sh
python3 - <<'PY'
import os, pathlib, secrets, socket, subprocess, sys, tempfile, time, urllib.request
root = pathlib.Path.cwd()
engine_port, catalog_port = 17431, 17430
for port in (engine_port, catalog_port):
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', port))
with tempfile.TemporaryDirectory(prefix='love2gathering-native-rooms-') as folder:
    data = pathlib.Path(folder)
    token = data / 'coordinator.token'
    with os.fdopen(os.open(token, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
        output.write(secrets.token_urlsafe(32))
    env = dict(os.environ, LOVE2GATHERING_COORDINATOR_TOKEN=token.read_text(),
               LOVE2GATHERING_DATA_DIR=str(data / 'saves'),
               LOVE2GATHERING_CATALOG_PORT=str(catalog_port))
    children = []
    try:
        children.append(subprocess.Popen([sys.executable, 'service/server.py', '--port', str(catalog_port),
            '--data-dir', str(data / 'saves'), '--database', str(data / 'catalog.sqlite'),
            '--source', str(data / 'missing-test-bulk.jsonl')], env=env))
        children.append(subprocess.Popen(['scripts/run-engine.sh', str(engine_port)], env=env))
        for port in (catalog_port, engine_port):
            deadline = time.monotonic() + 30
            while True:
                if any(child.poll() is not None for child in children):
                    raise RuntimeError('An owned test service exited before acceptance')
                try:
                    with urllib.request.urlopen(f'http://127.0.0.1:{port}/health', timeout=2): break
                except OSError:
                    if time.monotonic() >= deadline: raise
                    time.sleep(.1)
        common = ['--url', f'http://127.0.0.1:{engine_port}', '--token-file', str(token)]
        subprocess.run([sys.executable, 'bridge/tests/test_room_multiplayer.py', *common,
                        '--recording-port', str(catalog_port)], check=True, env=env)
        subprocess.run([sys.executable, 'bridge/tests/test_draft.py', *common], check=True, env=env)
    finally:
        for child in reversed(children):
            if child.poll() is None: child.terminate()
            child.wait(timeout=20)
PY
```

## Starting order and presentation events

`StartingOrder` rolls two server-owned d6 for each seat and rerolls only tied highest players. The winner becomes XMage's native starting player. Local practice can submit an actual `startingSeatId` (`local`, `bot-1`, etc.); omission or `dice` uses 2d6. Authenticated room and draft games always roll, ignoring a preferred starting seat. Public `openingRoll` snapshots retain every round's actual dice and the winner; Lua only animates those values.

`PresentationGames` wraps the native concrete game types solely to observe a completed native `resolve()` call. It emits `animationEvents.type=impact` for an actual non-countered resolved commander or a spell whose native stack mana value is greater than five. The captured value includes announced X. Simulation copies omit these callbacks. Battlefield impulses and distinct target/combat arrow colors remain presentation; neither changes native legality or resolution.

Replay relocation uses protocol 1, advertised by `/health.storageRelocationProtocol`. Native outbox construction and orphan claims use `BEGIN IMMEDIATE`, refuse a `replay_outbox_control` retirement marker and register `owner_protocol:<pid>=1` plus `owner_started:<pid>` process-birth milliseconds. This lets storage migration distinguish cooperative live engines from older idle clients and detect PID reuse. A retired source cannot receive a new guarded recorder; the client must restart into the prepared directory. Existing active/pending rows prevent migration. `ReplayRelocationFixture` checks actual writer contention; separate-JVM crash/recovery acceptance verifies durable delivery still works.
