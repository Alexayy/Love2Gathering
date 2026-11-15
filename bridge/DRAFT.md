# Native drafting and Limited pairings

`DraftSession` is a transport adapter over the pinned XMage draft and tournament classes. Production uses `BoosterDraft`, `RandomBoosterDraft`, native `DraftCube` implementations, `ComputerPlayer7`'s inherited draft picker/deck builder, and the native `Limited` validator. No cards are inserted into test zones, and no frontend code chooses packs, rotates them, rates picks or validates game rules.

## Capabilities and setup

The authenticated native coordinator exposes `GET /draft/options`. Native `profiles` contain the `booster`, `random` and `cube` procedures, with capacities and pack counts read from their supplied tournament types: **4–16 seats and three packs**. `deckProfiles` currently offers native **Limited, minimum 40 main-deck cards**. Swiss and single-elimination pairings use XMage's tournament classes. The gateway presents native procedures as `draft.modes` and native deck profiles as `draft.profiles`.

Traditional draft accepts `sets: [code, code, code]` in opening order. Random draft accepts `randomSets` as its eligible native booster-set pool, or uses all sets for which XMage advertises boosters when that list is empty. Native `RandomBoosterDraft` selects/generates its packs. Cube draft accepts a discovered `cubeCode`, or `customCube: {main: [{name,count}]}` for native `CubeFromDeck`; the application resource bound is 10,000 cube cards. Native cube generation retains its own exhaustion/refill behavior. The supplied engine has no separate Commander Draft procedure; it is not advertised as one.

`timing` is a native `BEGINNER`, `REGULAR` or `PROFESSIONAL` timing option. Native pick deadlines, timeout autopicks and alternating pack direction remain inside `DraftImpl`. Normal free basic additions come from `DeckValidator.MAIN_BASIC_LAND_NAMES`; snow basics and Wastes are not added as unrestricted draft supplies.

Each participant has a stable external `seatId`, name and human/bot type. `DraftSession` maps those identifiers to separate native draft player UUIDs. The same external seat IDs carry through later paired games; game-native UUIDs may differ.

The first draft initializes native card repositories asynchronously on its draft worker. Its public status is `initializing` while that occurs. Native H2 files are relative to the owned engine process's working directory, which must be isolated per desktop/engine instance. The original card snapshot and the application's authoritative SQLite saves are not modified by native repository generation.

## Private state and picks

`GET /draft/state?draftId=...&seatId=...` projects only that participant's `pack`, picked `pool`, valid submitted `deck` and reconnect `selection`. Other participants expose names, IDs, picking flags, picked-card counts, readiness and forfeiture flags. Authentication and invite/member authorization belong to the room gateway; native coordinator routes additionally require their private bearer token and loopback transport.

State includes `packNumber`, `pickNumber`, `packCount`, `pickToken`, `secondsRemaining`, the engine deadline, `basicLands` and `minDeckSize`. Native snapshots keep pack/pick numbers and cards consistent under the native player lock. A pick submits `{draftId, seatId, pickToken, cardId}`. The generation token must match the current round, and native `addPick` checks the exact card UUID is still offered and the player is still picking. Repeated/outdated requests fail instead of taking another card. Native picks retain their own thread-safe notification order.

## Building and explicit departure

After drafting, human players submit `{main: [pickedInstanceUUID,...], basics: {Forest:17,...}}`; an array of `{name,count}` basic entries is also accepted. Instance membership and duplicate selection are checked against that participant's real pool. Remaining picked cards form its sideboard. The deck then passes native `Limited.validate`; validation failures return `accepted:false` and named `errors`, preserving any earlier valid submission. Quantity/resource bounds remain separate from Magic construction rules.

Native bots build their own decks using XMage's Limited builder and card ratings. Every bot deck is checked against its real pool and native Limited validation before becoming playable. Reconnect state includes `selection.main` (picked instance IDs) and `selection.basics` (added basic quantities), so a human's accepted builder layout can be restored.

An explicit participant leave calls the trusted `forfeit(seatId)` operation. A transient connection loss does not. The original native draft player/pool is retained: XMage's `autoPick` chooses from that seat's actual offered pack, and after drafting the native bot builder constructs its deck. The adapter does not use the pinned engine's incomplete `Draft.leave`, nor its player-replacement path that would discard prior picks. A departed client cannot continue submitting picks or decks. The room gateway marks the departed seat as an AI for later games.

## Real games and tournament results

Once every participant has a valid deck, `/draft/next-round` invokes native Swiss minimum-weight matching or native single-elimination pairing. Results contain `round`, `matches` (pairing IDs and their external `seatIds`), byes, completion flags, round history and native standings. Sixteen draft seats produce eight independent two-player Limited games, rather than a sixteen-player battlefield.

`/multiplayer/start` with `draftId` and `pairingId` accepts only that native pairing's seats and loads their already validated stored deck sources. Client-provided replacement decks are not used. Matches currently use the application's explicit **single-game practice** setting (`winsNeeded=1`); this is not an assertion of best-of-three tournament support. Swiss round count defaults to three and can be configured from 1 to 16. The bound is an application resource setting.

`/draft/result` accepts a stored native `gameId` bound to that draft/pairing. It derives winners from the completed authoritative game and rejects an arbitrary supplied winner, stopped/errored games and unrelated pairings. The accepted outcome is mapped to native draft player IDs, then XMage updates points and elimination state. Swiss draws receive native draw scoring; a drawn elimination game requires a rematch. The next round cannot be generated while current matches remain unfinished. Deck editing is locked after the first pairing round starts.

Coordinator starts optionally accept `idempotencyKey`. The same key and equivalent JSON object content return the original draft/game identity; changed content fails. Object key order does not affect the comparison. Stops accept the native identity or its start key, and repeated stops succeed. A key-only stop received before a start tombstones that key, preventing a delayed request from creating an orphan session. A stopped key cannot create a replacement session. These receipts are bounded, process-local transport recovery records; they are not resumable engine saves.

`/draft/next-round` also accepts a per-command `idempotencyKey`. Retries return the original round snapshot and pairing IDs, even after those games finish; advancing requires a fresh command key. `/draft/result` binds a pairing to its accepted native game identity. A retry for that same game returns current native standings without scoring twice, including after the game has been reclaimed; a conflicting game identity fails. The gateway retains exact request bodies and command keys while recovering a response, so a lost response cannot silently start another game or round.

## Verification

`bridge/tests/love2gathering/DraftFixture.java` exercises complete native traditional/random/bundled-cube/custom-cube drafts, simultaneous human picks, native bots, the minimum/maximum profile capacities, hidden packs/pools, stale picks, offered basic additions, native Limited validation, native Swiss/elimination pairing and explicit-departure pool preservation. Its five-seat Swiss case verifies complete 45-card pools, two played pairings, one native bye and native bye scoring. Its timeout case advances only the native deadline to trigger XMage's own autopick. Pairing result-adapter cases use fixture outcomes and are labeled separately from actual games in `draft-native-report.json`.

`python3 bridge/tests/test_draft.py --url http://127.0.0.1:17412` requires a newly built owned coordinator engine and its private token file. It performs a complete actual HTTP draft, validates private pool decks, starts real paired Limited games, answers native opening prompts, finishes those games by native concession and advances native Swiss pairings using the completed game results. The same pipeline checks equivalent/conflicting start retries, round snapshot recovery, idempotent result scoring, stop retries and close-before-start protection. It stops only the draft/games it creates. Never point acceptance scripts at an active user's engine. Reports distinguish native fixture data, HTTP gameplay and actual frontend UI acceptance.
