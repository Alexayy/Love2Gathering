# Client stability and stress evidence

`tests/mechanics_client.py` runs client checks in owned child processes. It never launches the production engine script or contacts the user's catalog/engine/gateway. Each invocation has a new run ID, temporary runtime, independent application data/cache/config directories and independent XDG/LÖVE preference locations. Graphical fixtures replace only the service API with a recording stub. The transport fixture instead uses actual LÖVE worker threads and an owned loopback HTTP fault server on an allocated port.

```sh
python3 tests/mechanics_client.py --mode full --output /tmp/l2g-client-new-run
```

Use a **fresh empty** output directory. `smoke` runs model/transport, art-enabled visual-identity routing and 1/10-object rendering; `full` adds 100/500/1,000 objects, varied objects, 20 creation/removal waves, a combined long-stack/log scene and mutate-component inspection. `stress` attempts 5,000 synthetic objects only after the 1,000-object level leaves the configured frame/RSS headroom. `--timeout`, `--cpu-seconds`, `--rss-mb`, `--disk-mb` and `--frame-budget-ms` configure test budgets. These are test budgets, never Magic limits or automatic game outcomes.

An independently captured native projection can supplement the synthetic scenes:

```sh
python3 tests/mechanics_client.py --mode full --native /tmp/owned-native-run/projection.json --output /tmp/l2g-client-with-native
```

`--only native-projection` renders just that projection, plus the watchdog self-test. `--only artwork --native PATH` checks artwork request identity for any captured merged/copied hosts, together with controlled metadata and generated decoded pixel fixtures. It does not download or claim to show genuine card illustrations. The native projection is not a resumable game, and rendering it does not execute its Magic mechanics. The report explicitly distinguishes `client_model_transport`, `client_transport`, `client_artwork_transport_and_decode`, `synthetic_rendering_fixture` and `native_projection_client_render`.

## Reproduced application defects

1. **Concede queued behind a slow state/action request.** The previous service worker serialized all requests with an eight-second socket timeout. A read-only copy of `63798e8:app/api.lua` was exercised against a 1.5-second state response; its concession waited approximately 1.38 seconds and arrived after the state completed. The fixed API has a separate lazy engine/room **control lane only for concession/practice stop**. Ordinary actions retain their ordered worker. Actual delayed-state and delayed-action tests assert the concession arrives before the stalled response, within the 0.7-second test budget.
2. **Replacement games retained old context and accepted unfenced callbacks.** Earlier model source had no game/generation guards around answer callbacks. An old failed answer could clear a new game's busy/prompt latch, and an old successful answer could adopt its old game snapshot. `API:setNativeSession`, route generations and model game/poll fences prevent these callbacks from changing a newer opening. A new native game also clears old inspection and concession-confirmation context. The read-only earlier-source model reproduction fails at the first stale-inspection assertion and therefore does not execute its later callback assertions. The current model regression exercises those callbacks and preserves the newer game and its reused prompt ID.
3. **Repeated token IDs retained historical presentation poses.** `Renderer.poses` retained every historical world/screen ID until a whole camera/game reset. Current drawing marks active poses and removes poses unseen for more than two frames. The 20×1,000-object synthetic churn test retains the current 1,000 poses and releases all of them after the field clears. It never caps or removes native objects.
4. **An overlapped permanent had no practical individual browser entry.** Battlefield row icons now open the exact-instance zone browser. The browser uses full native IDs as control identities, paginates without dropping objects, searches names/object IDs, and displays the projected P/T, counters, damage and tapped state. Identical token names no longer share one Slab control ID. Actual input finds and selects the last instance in a 1,000/5,000-object field using the current prompt's offered ID.
5. **A card merged on top of a token was sent to the token illustration catalog.** The host correctly stayed a token, but its Gemrazer printing could not resolve as token art. Artwork and image-status routing now follow the exact native `mutate.topId` component, or a native token's `copySourceCard`, without changing host token status, native ID or live values. Ordinary tokens resolve against exported `tokenTemplate`, preserving their original artwork family when current stats/name/colors differ. Catalog enrichment retains these metadata fields. The art-enabled LÖVE regression checks actual exact-printing/local-only request paths and real image decoding with controlled generated pixels, including an actual captured native merged host.

Room control requests retain the authenticated seat route and the room's expected native game ID. A room client refuses the local `/session/stop` route. Practice controls carry `expectedGameId`; the bridge separately rejects a control that belongs to a replaced session. Client-side routing alone is not proof of that bridge validation.

Ordinary answers and native-session POSTs also retain their expected game identity. An explicitly old room game ID is refused locally; it is never rewritten into the next round's identity. This matters for boolean/priority responses whose prompt number could be reused after a rematch. The actual HTTP regression verifies that the stale request is not sent under the new round label.

## Slow or stopping sessions

The match HUD displays elapsed pending-request time after two seconds. It does not classify a loop or declare an outcome. Concession remains **requested** until native acknowledgement. Native `execution.stopRequested` with unconfirmed termination remains visible even when HTTP has completed; obsolete prompts are hidden using that explicit native flag. `terminationConfirmed` retires the waiting indication without inventing a win, loss or draw. Opening and closing Settings remains interactive while these indications are present.

The client never kills a shared multiplayer server. Its test watchdog owns only the process group it started, records sampled process state/CPU/RSS and applies configured wall/CPU/disk budgets. A deliberate sleeping child is terminated externally and the next independent child successfully runs. GAME thread termination and native outbox recovery require the separate bridge/harness tests.

## Input and representation coverage

The actual LÖVE/Slab fixture clicks boolean false, UUID, offered string, amount, distributed amounts, mode, pile, mana-wheel and manual-resolution-order controls. It verifies exact `responseType`/`value` payloads. An unknown prompt receives no guessed fallback. The model regression preserves an explicitly empty `actionable` array, rejects duplicate pending clicks, retains native live/printing values separately, and prevents stale callbacks across native game IDs/reconnect generations. A dropped HTTP response is recorded as uncertain and is not automatically retried.

Mutate component rows come from `card.mutate.components`, with the top component identified only by `topId`. Clicking a component inspects its original printing while the merged host remains the inspected permanent; it sends no independent targeting action. Host current P/T and component printed P/T remain separately labeled. Fresh native captured frames were checked with actual scrolling, component clicks and Close controls: seven checks for the Gemrazer merge, ten for both hosts in the copied-token-top scene. The art-enabled check passes 34 assertions including both native merged hosts, with controlled catalog metadata and generated pixels. These captured-frame checks do not execute their Magic mechanics; native merge/copy/zone outcomes belong to the native fixtures.

Artwork routing never chooses an arbitrary component when native top metadata is missing or hidden. The pinned native `CopyTokenFunction` does not attach a copy-source card to a copied merged permanent; such a token may lack native illustration provenance. The client does not infer that missing identity from its name, rules or current P/T. Ordinary copied-card tokens with native `copySourceCard` retain their card illustration route. Generated image fixtures prove request/decode/cache behavior, separately from a real catalog's possession of that illustration.

## Final measurements and limits

Reports retain JSON encode/decode size/time, fixture/projection consumption time, field/card-draw CPU submission time, real hit-test CPU time, texture/Lua memory and sampled process RSS/CPU. `love.graphics.flushBatch` submits drawing; the timing is **not a GPU completion measurement**. PNGs are captured outside the timed phase. Process logs, snapshots, source hashes, action traces and watchdog reasons are stored under the selected output directory. Failing runtimes are retained for diagnosis; successful temporary runtime/data directories are removed.

The final current-production-source stress run completed in 53.4 seconds: **14 pass, one `budget_exceeded`**, including its watchdog self-test. The budget finding is the synthetic 5,000-object frame time; its eight identity/input assertions still pass. Model (21), actual HTTP faults (14), art request/decode (34), and captured native copied/merged-host UI (10) checks pass separately.

| Scene | p95 frame CPU submission |
| --- | ---: |
| 1 / 10 / 100 equal synthetic objects | 1.59 / 1.97 / 4.21 ms |
| 500 / 1,000 equal synthetic objects | 14.22 / 25.05 ms |
| 1,000 varied synthetic objects | 29.71 ms |
| 1,000 objects with 20 replacement waves | 24.67 ms |
| 1,000 varied objects + 1,000 stack objects + 80 log rows | 50.79 ms |
| 5,000 equal synthetic objects | 126.12 ms — exceeds 60 ms test budget |
| Actual native 1,000-object captured frame, 500 per controller | 24.05 ms |

The outer watchdog observed peak process-tree RSS of 426.8 MB and confirmed descendant termination. Its raw exit status is `fail` because the client intentionally exits 1 for its embedded `budget_exceeded` result; no outer watchdog limit fired (`watchdogReason:null`). The compact index preserves that distinction. Concurrent native stress shared this machine, so these measurements are not quiet-machine or GPU-completion guarantees. Earlier 5,000-object measurements were approximately 118–123 ms; the final run remains degraded. These results do not establish a universal maximum or a 1,001–4,999-object boundary. Crowded battlefield rows visibly overlap; exact-instance browsing supplies access to individual objects.

The independently captured native 1,000-object frame is 1,095,920 bytes and contains 500 Wolf tokens per controller. The client retains all 1,000 exact renderer IDs and passes 12 actual LÖVE/input checks, including searching and inspecting each controller's final exact native UUID. Its snapshot has no offered target prompt; these clicks inspect the correct instances and send **zero gameplay actions**. JSON decoding took 57.19 ms and peak sampled client RSS was 274.6 MB. A lone catalog playmat lookup is recorded separately from gameplay.

That UI result does **not** make the native 1,000-object pipeline a pass. The native fixture created the correct objects and fired 3,003 native events, taking 135.478 seconds for creation/effects. Recording then exceeded its declared 45-second flush budget, with 706 entries durably pending. The native case remains `budget_exceeded`; cleanup confirms its native executor terminated. The pinned engine's separate per-controller token-production bound is recorded by the native runner. Synthetic 1,000/5,000-object scenes do not demonstrate those quantities under one native controller.

`tests/mechanics_client_report.json` is the compact evidence index, retaining each run's source hashes, raw report paths, measured cases and inspected screenshots. Final stress evidence is `/tmp/love2gathering-mechanics-client-stress-final-20261115-e/summary.json`; final actual-native-1,000 UI evidence is `/tmp/love2gathering-client-native1000-final-20261115-g/summary.json`. Production-source hashes match between those runs; the latter adds test-only exact-instance browser coverage.

Two test-harness defects are retained as separate evidence. The first native merge UI attempt clicked a component below the inspector viewport; its diagnostic reports no selected component, an unchanged host and no requests. The corrected fixture scrolls the actual inspector and inspects every merged host. An art fixture initially captured an empty first framebuffer despite passing its request/decode assertions; waiting three drawn frames produces an inspected visible capture. Neither failure is relabeled as a native mechanic failure, and their original reports/captures remain indexed.

No image acquisition, bulk download, live credentials, user deck edits, engine modifications, release changes or remote publishing are part of this client runner. Full production match completion, native loop handling, combat legality and accepted replay/outbox events require the separate native/production evidence.
