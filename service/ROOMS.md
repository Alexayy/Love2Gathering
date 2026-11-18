# Private room gateway

`rooms.py` is a standard-library HTTP gateway and in-memory room coordinator. XMage remains authoritative for decks, gameplay, draft packs/picks/deadlines, Limited deck building, pairings and tournament results. The engine submodule is unchanged. Native protocol details are in [the bridge guide](../bridge/README.md) and [draft adapter guide](../bridge/DRAFT.md).

## Hosting

`./run.sh` starts a dedicated engine and gateway for each desktop, reusing only a compatible catalog. Preferred ports are catalog 17370, engine 17371 and room gateway 17380. `LOVE2GATHERING_ROOM_PORT` selects the client's local gateway. The gateway alone binds to the network; engine and catalog bind to loopback. Every instance generates a private coordinator token, shared only between its gateway and engine through their environment.

On a LAN, the invitation advertises the host's detected outbound IPv4 address and gateway port. That address/port must be reachable from the other computers. `LOVE2GATHERING_ROOM_PUBLIC_URL` overrides the invitation origin. No discovery list, account service, public relay or NAT traversal is supplied.

For an Internet host, install Java 21 and Python 3, initialize the pinned submodule, and expose the gateway through an HTTPS reverse proxy:

```sh
git submodule update --init --recursive
LOVE2GATHERING_DATA_DIR=/path/to/server-data scripts/run-room-server.sh \
  --port 17380 --bind 127.0.0.1 --public-url https://rooms.example.com
```

The script starts and owns a catalog/engine, builds when needed, and stops only its own processes. It needs no LÖVE installation or graphical display. Logs are `.runtime/room-server-*.log`. Its public-host mode disables `/client/*` entirely, including requests coming from a loopback reverse proxy. Route the public hostname to the room gateway only; do not expose the catalog or native engine ports.

Desktops that create rooms on the shared host use:

```sh
LOVE2GATHERING_ROOM_SERVER_URL=https://rooms.example.com ./run.sh
```

Joining always uses the invitation code. A joining desktop's own upstream setting does not override the origin carried by that code. HTTPS uses normal certificate verification; credentialed redirects are rejected. A desktop gateway behind a reverse proxy should also disable `/client/*` at that proxy; the dedicated host script already disables those endpoints in the application.

Live room/session credentials are memory-only. Restarting a gateway or engine ends its live rooms; there is no claim of resumable game saves. Recorded host projections remain in the hosting catalog's `app.sqlite`, delivered through the durable native replay outbox. A remote host's recordings are stored on the server and are not automatically imported into that desktop's local replay browser. Guest perspectives cannot export host recordings.

## Invitation and seat boundary

An invitation is `L2G1-` plus URL-safe base64 JSON containing a protocol version, server origin, random room ID and join secret. It is a shareable invitation, not a short room listing identifier; keep the full value intact. There is no `GET /rooms` listing. A wrong secret cannot join, and joining is locked once play/drafting begins.

Joining creates a new random seat credential, distinct from the invitation. Each local gateway keeps that credential internally behind a random `connectionId`; the frontend receives the connection ID, public room, and only its seat's private projection. A seat cannot claim a game/player by supplying their IDs. The coordinator binds native identities from its assignment and rejects actions tagged with a previous game's `expectedGameId`.

The host alone adds/removes bots, starts and advances rounds, or closes the entire room. Any human can request a constructed rematch, with consent from every other human before replacement. Humans submit only their own deck, readiness, offered pick IDs and pool instance IDs. Deck names/readiness and draft pick counts are public; opponent deck compositions, packs, pools and hidden game cards are not. Initial trigger/mana/priority preferences are private per-seat settings. The server derives winners from completed games bound to the native pairing; no public winner/result-submission route exists.

All POST commands require JSON, requests are bounded to 8 MiB, and browser-origin requests are rejected. Client-only routes additionally require a direct loopback source and are disabled on the dedicated host. Invite codes/seat credentials are omitted from access logs. Room capacity is 32 by default (`--max-rooms`, at most 64), a hosting resource bound. Closed rooms expire after a minute; idle setup rooms expire after an hour.

## Desktop API

`GET /client/capabilities` returns native game/draft options from the configured creation host. Draft `modes` are native booster/random/cube procedures; `profiles` are deck rules (currently Limited). Limits are read from installed tournament/game types rather than a frontend constant.

| Method/path | Payload or result |
| --- | --- |
| `POST /client/rooms` | `{name,playerName,kind,format,maxPlayers,draft?,settings?,priority?}` creates a room |
| `POST /client/join` | `{code,name,settings?,priority?}` joins by invitation |
| `GET /client/rooms/:connection` | Public room and own `draft`/`game` projections |
| `POST .../deck` | `{deck}` selects own saved constructed deck |
| `POST .../ready` | `{ready:boolean}` |
| `POST .../bots` | Host `{count}` |
| `POST .../start` | Host starts setup, or first round after native-valid draft decks |
| `POST .../rematch` | Human `{}` requests a new native constructed game after completion; all original seats must be ready and present |
| `POST .../rematch-response` | Other human `{requestId,accept:boolean}` accepts or declines the current offer |
| `POST .../rematch-cancel` | Requester `{requestId}` cancels their current offer |
| `POST .../draft/pick` | `{pickToken,cardId}` from own current native pack |
| `POST .../draft/deck` | `{main:[ownedPoolUUID],basics:{name:count}}`; a rejected deck returns 422 |
| `GET .../game/state` | Own native projection |
| `POST .../game/action`, `.../game/priority` | Native action/control with assigned perspective |
| `POST .../game/replay/save` | Native host-perspective flush; guests are denied |
| `POST .../next-round` | Host advances after all native results are recorded |
| `POST .../leave` | Guest leaves/concedes only own seat; host closes room |

The public counterpart is `/rooms/:roomId` with an independent bearer seat token, plus `POST /rooms`, `POST /rooms/:id/join`, `/capabilities` and `/health`. Desktop credentials never authenticate native coordinator routes. There is no public stop-game, choose-winner or arbitrary native-forwarding endpoint.

Room phases are `lobby`, `starting`, `drafting`, `building`, `playing`, `completed`, `failed`, and `closed`. `room.canStart` and `canNextRound` reflect host authority. A constructed room remains `playing` after its native game ends; `game.running:false` and `canRematch:true` enable any authenticated human to request a rematch. Running/errored games, departed/unready seats and draft rooms cannot use this constructed rematch route.

`room.rematchRequest` exposes only the offer ID, assigned native game ID, requester ID/name, approved human seat IDs and remaining seconds. Offers expire after 90 seconds. A second requester cannot overwrite an active offer; repeated requests by its owner are idempotent. Responses must match the exact current offer and server-assigned game. All non-departed humans must accept; bots need no consent. A decline, cancellation, expiry or departure leaves the finished native game intact. One-human rooms with bots can rematch directly. No route accepts a client-selected game, player or winner identity.

A rematch retains the same room, human connections, external seat identities and submitted decks/settings, while creating a new native game and player instances. The gateway reclaims the prior native game, replaces assignments and uses a new stable start key. Old `expectedGameId` actions cannot affect the replacement. Each game records a distinct host-perspective recording and native outcome; a rematch does not overwrite its predecessor. Draft rounds and drawn elimination-pairing repeats continue through their separate native tournament flow.

`draft.tournament` contains native pairings, byes and standings. Pick requests use native tokens, and deck selection restores from native `draft.selection` after a transient reconnect. Leaving deliberately invokes native seat forfeiture: XMage completes picks and builds that seat's deck without losing already chosen instances. Subsequent paired games use a bot for that seat. A transient disconnect does not forfeit it.

Draft procedure, card pool and tournament pairing are independent choices. Traditional `draft.sets` contains its three pack slots; Random uses only `draft.randomSets`, an optional array of eligible native booster-set codes. An omitted or empty array means all supported booster sets. The gateway validates the offered choices, removes duplicate codes, and ignores inactive Traditional slots in a Random request. The UI retains each procedure's selections separately and provides a searchable eligible-set list. Both Swiss and elimination work with either pool choice. Cube uses the chosen native `cubeId`; deck construction remains native Limited.

The UI fences responses by connection opening, mutation sequence, room revision and native game ID. Entering a live room game closes read-only replay first. A bye/eliminated player receives no playable assignment; no stale prior-round game is polled. The existing local Lobby/game routes remain independent.

## Verification scope

Room reads and native choices have separate transport lanes. Capability and
room-envelope reads cannot queue an action behind a slow metadata scan. Native
reads have a 2.5-second per-hop limit and a shared five-second envelope budget;
the public hop is limited to six seconds, below the desktop worker's eight
seconds. A failed read may retry once, then polls back off up to eight seconds.
Waiting/reconnecting status retains the existing seat, game and unanswered
choice. A lost mutation acknowledgement triggers a fresh read, never a replay
of that action/pick. Definite validation failures remain validation failures.

Create/join intents carry a stable desktop request identity. New room hosts
advertise `membershipIdempotency` and receive a separate random private key.
Only the exact same operation and canonical payload may reuse that key; a
duplicate in flight is fenced. Both hops retain at most 1,024 small identity
records for one hour. A retry resumes the same authenticated seat/room and does
not allocate another member. Closed/departed memberships cannot be resurrected.
When a legacy host gives an unknown, malformed or failed reply after a possible
allocation, another POST is blocked because that host cannot confirm safe reuse.

Table priority is a per-player policy. New players default to manual control;
saved `autoPass` values remain intact. `passWithOnlyMana` is a separate opt-in
and considers only XMage's native legal abilities across every zone and native
special actions. Stops and Full Control take precedence. Targets, payments,
combat and other mandatory decisions are never automatically answered. A
failed or noncurrent native legality inventory holds priority conservatively.
The policy never taps a source or generates mana on the player's behalf.

- `service/tests/test_room_transport.py`: real delayed HTTP responses, bounded
  composed reads, lost membership replies, same-seat recovery, operation/payload
  conflicts, in-flight fencing, capacity/expiry and legacy uncertainty.
- `tests/api_read_lanes.py`: actual LÖVE/LuaSocket workers prove that held room
  metadata does not delay a native action, one busy read retries, and the action
  reaches HTTP exactly once. Payloads are controlled transport fixtures.
- `PriorityFixture`: native mana-only opt-in, manual defaults, explicit stops,
  unavailable legality, legal instant/flash responses and mandatory choices.
- `tests/table_options_ui.sh`: actual Slab checkbox clicks verify complete
  native policy requests, per-player preference saves, delayed acknowledgements
  and disabled controls during reconnect. Its synthetic duel also checks compact
  exile/library targets, native-offered mana undo and completion while options
  are open. It uses isolated VFS and controlled replies, not a native game.
- `lua5.4 tests/stack_presentation.lua`: exact docked stack-row identities,
  clipping, modal/scroll hover retirement and rematch/seat resets. Actual dock
  rendering and hover are covered separately by `presentation_overhaul_ui.sh`.
- `python3 tests/table_production.py`: a fresh bridge-only build and owned real
  catalog run a complete native duel, then 4/5/6-player Commander openings and
  full turn rounds with native MAD bots. It checks server-owned 2d6 starting
  order, all seats and bot land plays, private hands, native deck validation and
  actual recordings. `tests/table-production-report.json` records exact build
  hashes and cleanup; these are HTTP games, separate from graphical fixtures.

- `python3 -m unittest discover -s service/tests -p test_rooms.py -v`: real HTTP gateways with a synthetic native adapter. Checks authorization, private projections, native capability mapping, rejected decks, host/guest scope, stale-round actions, explicit forfeiture, start/close races, byes and draw-rematch orchestration. This is not rules evidence.
- `lua tests/api_rooms.lua` and `lua tests/rooms_model.lua`: deterministic transport fencing and room/draft editing contracts.
- `tests/draft_ui.sh`: actual LÖVE/Slab presentation/input with controlled projections.
- `python3 tests/rooms_live.py --host-url http://127.0.0.1:17420 --guest-url http://127.0.0.1:17421`: two explicitly isolated gateways backed by a fresh native engine. The report records real code-only joins, two-human constructed gameplay, four-human 180-pick draft, native Limited deck checks, paired gameplay/concession, authoritative Swiss scoring/next round and deliberate departure. It closes only rooms it creates.
- `python3 tests/rooms_random_live.py --url http://127.0.0.1:17451`: an explicitly isolated real gateway checks that selected Random booster pools reach XMage independently of inactive Traditional pack slots, plus unrestricted native pools, both pairing configurations and native deck submission. It closes only rooms it creates.
- `tests/room-rematch-live-report.json`: **18 passed checks** through a real desktop gateway and native Modern games. Two human seats complete opposite native concessions; the rematch request reaches the other human and waits for acceptance, the same connections/decks load into a new native game, stale-game actions fail, and separate genuine host win/loss history entries retain both names and exact deck summaries. It uses isolated storage and closes all created connections; no native coordinator credentials appear in the report.
- `tests/bot_draft_live.py` and `tests/bot-draft-live-report.json`: actual one-human/seven-bot native draft through the gateway. All eight seats complete 45 picks; native bots produce valid decks, the human submits their own Limited pool selection, and real paired games preserve hidden bot hands. The separate `tests/bot_draft_ui.sh` drives Lobby controls with synthetic replies.
- Native fixture/HTTP evidence lives in `bridge/tests/*draft*report.json` and `*room-multiplayer*report.json`. Fixture pairing outcomes and actual completed games are distinguished there.

Development acceptance uses temporary storage, loopback hosts and real native games. LAN/WAN routers, third-party HTTPS infrastructure, packet loss and real geographically separated Internet clients have not been acceptance-tested. The standalone host was started without LÖVE, queried for native capacities, used for code-only room creation and stopped with all owned services reclaimed. The original full JSONL/catalog is not needed for native draft rules; full artwork coverage still requires the card catalog/cache described in [the catalog guide](README.md). Catalog API 5 defaults to local artwork only; [LIBRARY.md](LIBRARY.md) documents offline image identity, explicit import previews, per-deck token preferences and read-only native match history.
