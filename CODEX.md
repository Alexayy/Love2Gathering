# Codex development notes

Start future Codex work from this project's root. `AGENTS.md` is its instructions entry point. This document records how Codex was used to build and validate Love: 2 Gathering, and provides context for later Codex work. It is referenced explicitly from `AGENTS.md`; the filename `CODEX.md` is not automatically discovered by default. Codex's documented project instruction discovery uses `AGENTS.md`/`AGENTS.override.md` and configured fallback filenames. [Official instruction discovery documentation](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

## Features used in this project

The implementation used parallel subagents with bounded ownership, coordinated by a main integration agent. Parallel subagents are a documented Codex workflow; each performs its own work and reports results to the parent. Shared file edits need deliberate ownership to avoid conflicts. [Official subagent documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents).

| Workstream | Delegated work | Integration boundary |
| --- | --- | --- |
| Engine | Inspect XMage, compile the required modules, implement the Java transport and native prompt projection, exercise real rules and AI | JSON state/prompt contract and engine fixtures |
| Catalog and builder | Stream the JSONL into SQLite, implement search/storage/construction validation, extend builder controls and model contracts | Catalog endpoints, persisted deck shape and shared builder layout |
| Decks and assets/input | Prepare/validate the twenty lists, run engine load/game checks, inspect supplied font/image/audio metadata, curate assets and repair Slab editing | Validated deck files, asset API, text-input tests and provenance |
| Main agent | Coordinate requirements, review contracts, integrate the table, scaling, modals/settings and artwork, run the actual desktop client and inspect screenshots | Final application behavior and acceptance |

The work used shell commands for focused source discovery, builds and local runs; patches for reviewable edits; primary documentation and the supplied rules PDF for targeted checks; local image/asset inspection; real HTTP/service tests; deterministic engine fixtures; and actual LÖVE rendering with screenshots. The frontend uses LÖVE, Slab, a local Python service and XMage. Codex is a development tool, and the running client requires no OpenAI API key or OpenAI runtime API.

## Continuing work

1. Read `AGENTS.md`, then inspect the files for the requested behavior. Use the architecture table there to assign ownership.
2. Trace gameplay decisions into XMage before changing the frontend. Extend the existing prompt contract when information is missing; keep presentation separate from rules.
3. For parallel work, agree on JSON fields and file ownership before writes. Send concise findings and dependencies back to the integration owner.
4. Use temporary user-data directories and an isolated engine port for destructive test sessions. Preserve the current user's collection and running match.
5. Run the checks appropriate to the change. Review real screenshots for UI changes, and rebuild/restart an owned test engine when source/jar changes.
6. Report the tested outcome, the evidence source and the remaining limits. A rendering fixture, successful compile or button click does not establish a completed real game.

## Evidence and its scope

| Evidence | What it establishes |
| --- | --- |
| `service/tests/` and `tests/frontend_model.lua` | Service/storage/validation behavior and frontend model contracts |
| `tests/assets-input.sh` | Actual LÖVE/Slab text editing, loaded glyphs, texture/icon metadata and sound decoding |
| `tests/frontend_run.sh` | Real frontend/catalog persistence and card dragging; injected game states cover presentation only |
| `decks/validation-report.json`, `decks/engine-load-report.json` | The twenty list definitions and actual native-engine startup/hidden-hand checks |
| `bridge/tests/trigger-report.json` | Real automatic/manual simultaneous triggers, their resolution and nested counters from an initial fixture state |
| `bridge/tests/actionability-report.json` | Native costs, land limits, timing/priority, mana-option prompts and paid/free mulligan behavior |
| `bridge/tests/gameplay-actionability-report.json` | A complete real Modern bot game: eight turns, 65 prompt answers, lands/casts/resolutions/life changes and normal completion |
| `bridge/tests/input-bound-report.json` | Native Modern validation/loading of 250 Plains for each player and rejection of 251 copies at the application's input bound; no running match touched |
| `bridge/tests/replay-recording-report.json` | A separate completed native game, authoritative SQLite recording, structured actors/actions, stack source cards/rules, hidden hands, in-game flush, reopen and crash/outage recovery |
| `tests/replay_model.lua` | Frame pagination, stale-response guards, timeline controls, read-only playback and live-state restoration; mocked transport only |
| `tests/richtext.sh` | Real LÖVE glyph/layout/raster checks, alpha correction, bounded caches and display-mode invalidation |
| `tests/table_replay_ui.sh`, `tests/table-replay-ui-report.json` | 106 actual UI checks plus SQLite flush on quit: floating-panel drag/resize/persistence, responsive land-row fixtures and playback controls against a real 413-frame native recording |
| `tests/quit_storage.sh`, `tests/json_codec.lua` | Callback-chained SQLite writes during immediate closure and large numeric JSON decoding without repeated suffix copies |

The full-game proof covers its tested mono-red game. It does not establish every card interaction or optimal Phoenix/Lotus Field strategy. Check report contents and current code before quoting older acceptance results. User-facing startup and controls belong in `README.md`; low-level bridge protocol details belong in `bridge/README.md`.

The storage update used separate ownership for SQLite migration/API tests, engine recording/outbox tests, icons/rich-text and main-agent presentation/playback integration. The shared replay event contract was agreed before implementation. User data and production matches were excluded from destructive fixtures. Keep the same separation when extending this work: the frontend playback tests cannot prove native recording durability, and a completed engine recording cannot prove floating-window usability without actual UI inspection.
