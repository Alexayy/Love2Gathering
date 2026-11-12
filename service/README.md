# Local data service

Run `python3 service/server.py --port 17370 --data-dir PATH`. The launcher supplies the user's data directory. The service listens on loopback by default and reports **API version 3** at `/health`.

## SQLite storage and migration

The user database is **`PATH/app.sqlite`**. It contains decks, bundled-deck seeds, deletion tombstones, settings, UI layout, artwork JPEG blobs and metadata, replay metadata, and immutable replay events. WAL mode, a 30-second busy timeout and `synchronous=FULL` support concurrent local services. Writes use transactions. The generated card index remains separate in `service/data/catalog.sqlite`; the 2.8 GB source JSONL is an unchanged distribution input.

On first use of a user directory, valid `decks/*.json`, `settings.json` and `hidden-decks.json` are imported in one transaction. Malformed entries are isolated and reported in `health.storage.migrationIssues`. A committed migration marker prevents stale JSON from being imported after a later SQLite edit or deletion. Existing JPG caches are imported eagerly in committed batches of 16, with a completion marker and safe restart behavior. Legacy artwork keys are also resolved from SQLite; old files added later can be imported on first access.

**Original JSON and JPG files remain untouched as migration backups.** New user state and artwork are written to SQLite. Bundled deck JSON remains distribution input: its records are seeded into SQLite, while user overrides and hidden-deck selections survive reseeding. Legacy decks above the current 250-copy transport limit are preserved during import; new editor writes retain that limit independently of printed card copy rules.

`GET /health` includes `storage.dataDirectory`, the resolved absolute data directory, plus the database name, schema version and migration report. The launcher uses this directory to avoid reusing a healthy service belonging to a different user-data directory. `userStore` aliases the same health object for compatibility.

## API

| Endpoint | Behavior |
| --- | --- |
| `GET /cards?q=&format=&color=&type=&set=&sort=&limit=&offset=` | Paginated catalog search; sort is `name`, `color` or `set`. |
| `GET /cards/<oracle-id>` or `/cards/by-name?name=` | Card details; face names resolve to their full oracle card and requested face. |
| `GET /sets?format=` | Set names, codes and distinct-card counts across printings. |
| `GET /art/<oracle-id>?printing=&face=&kind=` | JPEG from SQLite or a validated Scryfall download; kind is `normal` or `art_crop`. |
| `GET /decks`, `POST /decks` | List or save decks. |
| `GET`, `PUT`, `DELETE /decks/<id>` | Read, save or hide/delete a deck. |
| `POST /decks/validate` | Construction checks; returns `saveAllowed`, `playable`, `draft`, named errors, warnings and counts. |
| `GET`, `PUT /settings` | Typed preferences; partial writes update the supplied keys transactionally. |
| `GET`, `PUT /ui-layout` | Read or atomically replace the layout object, including panel positions and replay preferences. |
| `POST /replays` | Create recording metadata; a supplied ID and identical metadata make retries idempotent. |
| `GET /replays?offset=&limit=` | Recording list and total; maximum page size 200. |
| `GET /replays/<id>` | Metadata, status, frame/action/log/error counts and last durable sequence. |
| `POST /replays/<id>/events` | Atomically append `{ "events": [...] }`, up to 2,000 events. |
| `GET /replays/<id>/events?offset=&limit=` | All events ordered by sequence. |
| `GET /replays/<id>/frames?offset=&limit=` | Frame events only; maximum page size 500. |
| `POST /replays/<id>/finish` | Finish as `completed`, `failed` or `aborted`, optionally including result/error details. |
| `DELETE /replays/<id>` | Delete a recording and its events transactionally. |

Request bodies are capped at 8 MiB. Replay metadata is capped at 1 MiB and UI layout at 256 KiB. IDs are constrained identifiers, not filesystem paths.

Replay events have this shape:

```json
{"sequence":0,"type":"frame","timestamp":1770000000000,"data":{"gameId":"...","players":[]}}
```

Types are `frame`, `action`, `log` and `error`. The bridge supplies projected player-visible snapshots; this service does not read raw XMage internals. Recording happens at the engine producer rather than through frontend polling. Events are immutable: an identical sequence/content retry is accepted, while conflicting content returns HTTP 409 and rolls back the whole batch. After finishing, new events are rejected, while exact old-event retries remain safe. Partial and failed recordings retain their frames for reopening.

Frame reads return `{ "frames": [{ "sequence": 0, "type": "frame", "timestamp": 1770000000000, "data": {} }], "total": 1, "limit": 250, "offset": 0 }`. `data` is the playback snapshot. Replay metadata exposes `eventCount`, `frameCount`, `actionCount`, `logCount`, `errorCount` and `lastSequence`.

## Verification

```sh
python3 -m unittest discover -s service/tests -v
lua tests/replay_model.lua
tests/quit_storage.sh
```

The backend suite covers migration preservation and idempotence, concurrent startup/writes, eager and lazy artwork import, deck/settings validation, replay conflict rollback and restart reopening, pagination, and HTTP responses. The quit test starts its own ephemeral-port catalog in a temporary user directory, runs the real LÖVE request workers, and verifies that a callback-generated write survives immediate quit and SQLite reopening. It does not use the running user's catalog or data directory.
