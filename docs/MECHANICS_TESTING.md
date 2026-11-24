# Mechanics and stability testing

Run the isolated acceptance runner from the repository root:

```sh
python3 scripts/test-mechanics.py --mode smoke
python3 scripts/test-mechanics.py --mode full --jobs 1
python3 scripts/test-mechanics.py --mode stress --jobs 1
```

`smoke` selects a small directed-mechanics subset, one invocation per selected case, lifecycle checks and native token levels 1/10/100. It still normally runs the production, recording-recovery and client scopes. `full` runs all directed cases with their declared repetitions, lifecycle checks, native token levels through 1,000 and the full client suite. `stress` adds the client’s conditional 5,000-object synthetic rendering attempt; it does not bypass the engine’s token-production bound. Native escalation stops after a failed or over-budget level, and later levels remain `not_run`.

Use one or more exact stable IDs to reproduce a narrow native case:

```sh
python3 scripts/test-mechanics.py --mode full --scenario C15
python3 scripts/test-mechanics.py --mode full --scenario adv-mutate-projection-token --scenario adv-copy-retarget
python3 scripts/test-mechanics.py --mode full --scenario tokens-split1000
```

A selected-case run still prepares and validates the isolated dependencies/data and runs the watchdog/outbox preflight. It does not run unrelated lifecycle/escalation, production games or client checks. `--skip-production` and `--skip-client` also make a run explicitly partial. A partial run cannot establish full acceptance. `--jobs` accepts 1–3 independent fixture JVMs; use 1 when memory is limited or comparing performance. See `python3 scripts/test-mechanics.py --help` for current options.

## Prerequisites and preservation

The runner requires Linux process information under `/proc`, Python 3, a Java 21 **JDK** with `java`, `javac`, `jar` and `jcmd`, and the existing pinned dependency JARs under `bridge/target/lib/`. It uses `JAVA_HOME`, a supplied `.tools/jdk-*/` installation or system tools. Client checks additionally require LÖVE 11.5 and a working graphical display for rendering/input captures. The supplied local `assets/*scryfall-default.jsonl`, `bridge/card-map.json`, bundled Commander lists and runtime assets must exist.

This workflow recompiles `bridge/src/` and the test fixtures into a fresh temporary directory using the existing dependency JARs. It does **not** invoke `scripts/build-engine.sh`, Maven dependency acquisition or an engine build. Missing dependencies are a prerequisite failure, not permission to rebuild or modify `engine/` during acceptance. Ordinary fresh-clone preparation is a separate workflow described in [README](../README.md).

The integration is pinned to XMage `2a96b0ac129dfd77946eaad536184d3b35fb5e64` (reviewed November 24, 2026). The entire `engine/` tree, including generated/target files, stays read only. The runner fingerprints file content/modes and existing engine changes before and after execution, and checks `.gitmodules` plus the recorded/index gitlinks. A preservation failure remains a failed run; the runner does not reset or discard existing changes.

All application data, cache, configuration, HOME/XDG directories, replay outboxes and evidence belong to an owned `/tmp/love2gathering-mechanics-*` directory. Catalog, bridge and gateway services use allocated loopback ports with owned-process checks. The runner does not replace an active user match, acquire card images, clear user caches, publish results or change the submodule pin. It stops only processes it started.

## Lists, manifests and evidence scopes

The current manifests define **74 directed native scenarios**: 37 [core](../bridge/tests/mechanics/core.json) and 37 [advanced](../bridge/tests/mechanics/advanced.json). The separate [system manifest](../bridge/tests/mechanics/system.json) has **16 lifecycle/stress scenarios**. These are declared coverage counts, not executed/pass counts. A scenario’s `combined` flag identifies interactions tested together; it does not create an additional invocation. Critical cases declare independent repetitions, normally three outside smoke mode.

The generator writes **20 temporary lists**: 18 purpose-built 60-card lists for mechanics families and two copies of the bundled Krenko/Giada Commander lists. It streams only the required English printing metadata from the local JSONL into a test catalog. `generation.json` retains list/source hashes, missing identities and native validation results. Some purpose-built lists intentionally contain cards unavailable in Modern: native rejection marks them fixture-only, and production games must use accepted lists. Generated lists do not modify a player’s collection or the bundled originals.

| Scope | What it establishes | What it does not establish |
| --- | --- | --- |
| Deterministic native mechanics | XMage executes the declared operations against prepared native zones/resources; assertions inspect native state, offered prompts and projections. | Normal shuffled-game reachability or payment for an injected pre-paid spell. |
| Production HTTP games | Normal Session construction, native deck validation, opening choices, actual offered actions, game/recording lifecycle and entitled state. | Every directed fixture state or exhaustive bot/card correctness. |
| Lifecycle and transport | Stale/concurrent/unoffered-answer rejection, native worker termination and accepted-action recording contracts. | A Magic rules result from a deliberately held worker. |
| Replay/outbox recovery | Durable native recording survives the test child’s abrupt exit and is recovered into the isolated catalog. | Resumable engine saves or recovery of a real multiplayer server. |
| Native projection transport/render | An actual entitled frame preserves exact IDs through JSON/loopback and, when supplied to the client, real drawing/input. | Re-execution of that saved frame’s game mechanics. |
| Synthetic client/model checks | Rendering, interaction, stale-callback fences, responsiveness and presentation-resource behavior. | Native legality, achievable token quantity or a completed match. |

The production runner has six declared policies: burn mirror, burn against land-only control, control deckout, land-only control against burn, and four/six-seat Commander rotation. Completed matches and partial rotation checks are separate results. Meeting an aggregate completion target never hides an individual failure or budget overrun.

## Budgets and watchdog diagnostics

Each manifest declares its wall, heap/RSS, event/action/resolution and relevant projection/storage budgets. The external watchdog also observes CPU, disk and output growth, preserving its applied configuration with each result. These are diagnostic resource bounds, **not Magic rules, maximum legal quantities or deadlines imposed on players**. A budget stop never awards a draw, win, loss or concession. `native_limit_observed` describes a specifically measured native implementation bound, not a successful creation of the requested quantity.

Directed fixtures use their own bounded task waits and event counters in addition to the external watchdog. The core million-counter case has a separate large event allowance; ordinary small scenarios have much lower limits. Advanced results report the applied per-step policy and resolution count separately. Check each invocation’s `scenario.json`, `combined-result.json` and process command rather than assuming every scenario shares the same allowance.

To change a diagnostic allowance, edit that scenario’s `budgets` in its manifest before running it; the saved scenario/configuration hash records the choice. The runner passes `stepSeconds`, `nativeEvents`, `acceptedActions`, `attempts`, `nativeObjects`, `nativeResolutions`, `stackResolutions` and `flushMillis` to the fixture’s corresponding `love2gathering.test.*` properties where supported. Heap/RSS, wall/CPU/disk, projection and log bounds remain external measurements. The stress profile allows a longer step/flush for large boards; original tighter-budget findings remain separate evidence. Task waits, event/action/object/resolution bounds and external limits all affect status. SIGINT/SIGTERM sets a shared cancellation fence so active owned children stop, queued scenarios do not launch, services close and an interrupted report is retained.

The watchdog preflight deliberately creates Python busy/waiting children and Java **busy calculation and monitor-deadlock faults**. The Java deadlock is a real injected monitor deadlock, with diagnostic threads whose names start with `GAME`; it is not a Magic game, a native mandatory loop or a reproduction of a card bug. The harness checks fault initialization, captures repeated thread dumps, terminates the owned child and verifies that a following independent child runs. Its `gameOutcome` stays null.

When a native child exceeds a budget, inspect `resource-samples.json`, `process.log`, `threads-*.txt`, heap/VM diagnostics and the last native prompt/event/projection. A rules assertion that passed before an RSS/CPU/time overrun does not convert the whole invocation into a pass. A stop acknowledgement and confirmed native thread exit are separate observations.

Native fired-event counts come from test watchers attached to registered actual games, excluding simulations/playable-action calculation. They are distinct from structured-log counts, retained animation events and replay sequence numbers. Production polling/recordings observe projected event IDs; they do not claim a complete raw native event stream. Older advanced baseline artifacts used the `nativeEventCount` label for structured logs; their preserved source/hash and the [advanced notes](mechanics/advanced-research.md) explain that historical limitation.

## Native token cap and stress interpretation

At the pinned revision, the engine’s token implementation applies an existing **500-token creation cap per controller**. The single-controller `tokens-1000` case therefore records both requested 1,000 and the native actual quantity; it must not be described as a native 1,000-object board merely because the request asked for 1,000.

`tokens-split1000` instead requests 500 tokens for each of two controllers, testing an actual total of 1,000 native permanents. `tokens-varied-split1000` also varies native tap/counter/damage state while retaining exact object identities. Their projections and recording growth are measured separately. The cap is a pinned implementation behavior, not a Magic rules limit, an application-introduced cap or a universal machine maximum. Synthetic 1,000/5,000-object client scenes remain separately labelled even when a native stress case reaches a similar total.

## Finding classification and current acceptance state

Keep the **status** and **research classification** separate. A `suspected_upstream` or `known_upstream` label never turns a failed assertion into a pass. `known_upstream` requires an exact, relevant primary upstream report or fix with matching conditions/version evidence; a similar issue is only research context. A derived interaction without that match remains suspected until investigated. Preparation mistakes, unsupported prompt policy and transport/presentation faults must be distinguished from engine-state defects.

The [measured report](MECHANICS_REPORT.md) and [structured index](../bridge/tests/mechanics-report.json) retain the actual run series, latest-build follow-ups and failures. No manifest count is a claim that all cases passed. Older measured runs, intentionally failing baseline reproductions and focused fixes retain their own source/JAR hashes and limitations in the linked research documents. In particular, the Nine Lives/Banefire discrepancy remains a failed expected-counter assertion classified as suspected upstream; no engine patch is implied. An outer execution interruption is explicitly separate from a failed native game; its raw child evidence and scoped cleanup remain retained.

For the rules references, precise prior observations and client measurements, read:

- [Core mechanics research and fixture limitations](mechanics/core-research.md)
- [Advanced mechanics research, mutate/copy/loop cases and suspected findings](mechanics/advanced-research.md)
- [Client stability, actual input, synthetic/native-frame scopes and performance measurements](mechanics/client.md)

## Reading and retaining a run

The runner prints its `REPORT.md` path. By default, a fresh owned `/tmp` run contains a unique `executions/<mode>-<id>/` directory. Optional `--run-dir /tmp/love2gathering-mechanics-review-001` chooses a run root; use a fresh name for an independent preservation baseline. A reused run root retains its original baseline and writes a new execution directory instead of replacing earlier evidence.

`results.json` and `REPORT.md` aggregate scenario status, production/client scope status and engine preservation. Per-case directories retain `scenario.json`, native `result.json`, `combined-result.json`, source/JAR/configuration/list hashes, process identity/command, GC/resource logs, action traces and native snapshots where applicable. A visible merged-token frame is saved before its separate face-down privacy check. Production replay exports use lossless paged gzip JSONL instead of accumulating a complete recording in memory.

Read the exact expected/actual assertion and raw watchdog result for every failure. `not_run`, incomplete production games, checkpoints without a native outcome and skipped escalation levels remain visible. A nonzero runner exit means required findings, a harness/cleanup failure or failed preservation; an intentionally narrow invocation establishes only its selected scopes. Temporary evidence may be removed by system cleanup, so retain the printed run directory when sharing a regression report, without including live credentials or user data.
