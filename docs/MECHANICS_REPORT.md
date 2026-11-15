# Mechanics and stability report — 2026-11-15

This is a consolidated, scoped run series with remaining findings. It is **not an all-green full run or exhaustive Magic coverage**. [Structured results](../bridge/tests/mechanics-report.json) retain source/JAR/configuration hashes, per-scenario expected/actual values, resource measurements and raw evidence paths. [Reproduction and budget guide](MECHANICS_TESTING.md).

## Executed coverage

| Scope | Executed result |
| --- | --- |
| Directed native mechanics | 74 scenarios, including 61 combined interactions; 136 invocations in the consolidated coverage matrix: **130 pass, 3 fail, 3 budget_exceeded**. Critical mutate/copy/loop cases repeat three times. Earlier reruns remain retained separately and are not double-counted in this matrix. |
| Temporary lists | 20 generated lists; 18 accepted by native format validation. Two intentionally unsuitable Modern resources remain fixture-only; no user deck was created or modified. |
| Latest bridge follow-up | Three repetitions of the strengthened merged-token/copy-provenance case pass **42 assertions each**. Eight lifecycle regressions and seven existing native fixture groups pass on the final v6 JAR. |
| Native production games | Four normal-start games reach native outcomes. Five of six complete test scopes pass; the deckout game's initial recording-export check exceeds its 30-second budget. A separate preserved-recording verification later passes. |
| Multiplayer production | Four/six-seat Commander tests observe every player's turn and entitled state, then stop. These are **partial games**, not completed Commander matches. |
| Current client stress | 14 cases pass; synthetic 5,000-object rendering exceeds its CPU-frame budget. Actual native 1,000-object rendering/input separately passes 12 checks. |
| Watchdog/recovery | Busy Java and genuine injected monitor-deadlock faults repeat three times, with three spaced dumps per fault and scoped termination. Following tests run. Crash/outage recovery and actual large-outbox recovery pass. |
| Framework regressions | 43 Python tests pass: ownership/descendants, cancellation, cleanup, aggregation, offered-choice policies and lossless replay export. |

Final legend-copy/SBA selection and mutated-token attachments each pass three repetitions. The attachment case actually casts Gemrazer for its native alternative 1GG cost from a three-green mana pool, which becomes empty; its target is auto-selected by the engine because it is the sole legal host. The separate legend case uses an actual offered UUID response. Bonesplitter/Rancor, two counters, marked damage and tap state survive the merge with native live10/6.

The native fixture matrix covers current/original characteristics, counters, negative toughness/SBA, threshold effects, control and zone changes, attachments, APNAP/manual/nested triggers, copy variants, replacement/prevention, mutate, native combat damage, sacrifice/discard/tap/X costs, modes, piles, amount distributions, mana choices and multiple human perspectives. Exact definitions and limitations are in the [core](mechanics/core-research.md) and [advanced](mechanics/advanced-research.md) notes and manifests.

Prepared native zones and injected pre-paid stack spells establish resolution/state assertions. They do not establish normal shuffled-game reachability or production cost payment. The separately identified normal-start games supply production evidence. No production shuffle seed is claimed.

## Fixes in application code

- Native answers claim a prompt once and validate offered response type/value and native amount bounds before recording. The old bridge accepted 15 simultaneous duplicates in the 16-attempt reproducer; the fixed bridge accepts exactly one, and the actual catalog stores one accepted action.
- Game identities and frontend callback generations fence delayed actions/state across rematches and room routing. Starting a replacement match refuses a predecessor whose actual GAME thread is still alive.
- Stop-request acknowledgement is separate from actual thread termination. A deliberately held GAME test remains visibly stopping until the thread really exits. Concession signals bypass an ordinary answer lock; the held-answer regression fails before that correction and passes three times afterward.
- Frontend concede/stop traffic has an independent worker lane. A delayed ordinary request no longer queues those controls behind it. Transport failures do not fabricate game outcomes or silently retry an uncertain accepted answer.
- Crowded battlefields have a bounded, searchable exact-instance browser. Native IDs remain target identities; merged components are inspection metadata. The original token, native merged top and native copy-source artwork identities remain separate from current P/T/counters/controller.
- Obsolete visual pose history is pruned instead of accumulating every historical token ID. Churning 20 groups of 1,000 synthetic instances retains current poses and clears old ones.
- Ordinary tokens reuse their existing original `printing` descriptor; the bridge adds separate template metadata only when mutation, transformation or copying requires it. This removes redundant recorded data without omitting a frame, action, trigger, decision or journal sequence.
- The harness streams lossless replay exports to paged gzip instead of holding whole recordings in memory. Ownership uses private inherited markers plus PID birth identity, including independent-session descendants. SIGTERM/SIGINT cancellation now stops active owned children, fences queued launches, closes services and retains an interrupted report.

The baseline failures, corrected runs and harness-only preparation/capture/scrolling mistakes remain retained; they are not all labelled product defects. [Client details](mechanics/client.md).

## Researched and derived findings

**Suspected upstream: Nine Lives and Banefire X=5.** The native resolution fixture deals five unpreventable damage but leaves zero incarnation counters, repeated three times in each directed batch. The original expectation remains one counter, following the [official M21 ruling](https://magic.wizards.com/en/news/feature/core-set-2021-and-jumpstart-release-notes-2020-06-20). Skullcrack is a separate passing control: three damage and one counter. This is observed native state, not a displayed-P/T or artwork assertion. The injected-spell fixture explicitly sets its X value; it does not claim normal Banefire casting/payment acceptance. No exact matching upstream issue was found, so the classification stays **suspected_upstream**, with status **fail**. Engine code was not patched.

**Historical fixed regression:** [XMage #9839](https://github.com/magefree/mage/issues/9839), Darksteel Mutation suppressing a blinked Wall of Omens ETB, passes three times at the pin. It is historical context, not a currently reproduced engine bug.

[XMage #16046](https://github.com/magefree/mage/issues/16046) motivated additional merged-token/copy/GUI identity tests. The generic cases pass after our projection/UI fixes; the full reported Tatsunari/Heron/Dirge Bat sequence was not reproduced. Mutated-commander free spells, Six/retrace alternate costs, Grist DFC copies and Silent Hallcreeper mode exhaustion are separately researched contexts, with untested exact conditions clearly marked in the linked research notes.

Additional derived native cases pass: Angel of Vitality crossing its life threshold during simultaneous lifelink/damage before SBA; losing that threshold making existing marked damage lethal; Tarmogoyf responding to both graveyards; Vigor with Solemnity; and copied-token components retaining their exact original-card provenance when another creature mutates underneath.

The pinned copy-of-an-already-merged branch supplies no original Card artwork reference. That provenance remains unavailable; the frontend does not guess an edition from the copied name or borrow physical merged components.

## Loops and termination

| Interaction | Native observation, repeated three times |
| --- | --- |
| Sporemound + Life and Limb | Native draw after 17 resolutions in this fixture. |
| Stuffy Doll + Pariah's Shield | Native draw after 18 resolutions. |
| Polyraptor + Marauding Raptor | Pending native work after the declared 24-resolution checkpoint; **budget_exceeded**, no invented draw or winner. |
| Enduring Renewal + Altar + Ornithopter | Three explicit optional cycles, then an offered native Pass exits without a terminal result. |
| Kiki/Conscripts/Impact Tremors | Three explicitly activated damaging cycles, then an offered native Pass; the driver does not silently continue to a win. |
| Nine Lives + Solemnity | Working legal lock: native damage prevention, zero prohibited counters, live game; not classified as an infinite computation. |

The native 500-token-per-controller implementation cap can truncate a growing token sequence. The Polyraptor checkpoint therefore is not proof of an unbounded sequence at this pin. Repeated hashes/revisions alone never establish an infinite loop. Health responses never establish GAME progress.

Injected busy/deadlocked Java workers are diagnostic faults, not card interactions. Dumps, actual thread exit, native stop/concession where applicable, and owned-process termination are recorded separately. Watchdog limits never award a game outcome. Pathological MAD-bot positions and arbitrary loop families remain unverified.

## Token, transport and recording measurements

Final heavy-profile native operations include actual state/trigger processing and fired-event observation. Times below include the concurrent native recording workload; they are not pure token allocation benchmarks.

| Requested / actual | Create + effects | Projection | Java JSON encode | Projection bytes | Flush result |
| --- | ---: | ---: | ---: | ---: | --- |
| 1 / 1 | 155 ms | 5.1 ms | 0.4 ms | 6,548 | 16 ms, pass |
| 10 / 10 | 348 ms | 6.0 ms | 0.6 ms | 24,695 | 25 ms, pass |
| 100 / 100 | 2.30 s | 36.3 ms | 3.8 ms | 206,616 | 388 ms, pass |
| 500 / 500 | 29.65 s | 17.5 ms | 10.9 ms | 629,156 | 21.89 s, pass under 45 s allowance |
| 1,000 / 500, one controller | 35.57 s | 16.9 ms | 10.9 ms | 629,156 | Existing native cap observed; not a 1,000-object board |
| 1,000 / 1,000, two controllers | 135.48 s | 42.9 ms | 25.2 ms | 1,095,920 | 45 s expires with 706 durable pending events |

The 1,000-object operation fires 3,003 observed native GameEvents. The resulting recording has 3,002 journal entries; raw native events and the recorder's frame/log/action entries have different scopes. Python decodes its captured projection in about 7.8 ms; five static loopback transfers take roughly 0.8–1.0 ms each. This is a captured-native-frame transport fixture, not a new native HTTP game execution.

The first 256 MiB split-1,000 recording attempt hit its disk ceiling. A separate initial 500-object attempt preserved 389 pending events at an eight-second flush ceiling. Both original failures remain retained. The larger declared heavy profile reaches an actual 1,000-object state but still exceeds its 45-second recording allowance; its outbox/SQL directory reaches about 1.03 GB. The whole split-1,000 case remains **budget_exceeded**.

The first recovery attempt also exceeds its 60-second allowance. A subsequent new recorder process, using the same original test data and a 90-second ceiling, delivers the remaining 328 events in 30.67 seconds. Authoritative SQL then contains exactly 3,002 contiguous entries, last sequence 3,001, zero pending, finalized **aborted**, with no fabricated game result. This proves durability/recovery for the captured workload; it does not turn the original throughput failure into a pass.

The last fully passing native creation/projection/recording level here is **500**, using the expanded 45-second flush profile. The actual 1,000-object native state and UI pass their quantity/inspection assertions, while recording misses its budget. Varied native split-1,000 escalation is **not_run** after that finding. Varied 1,000-object frontend tests remain explicitly synthetic. Native 5,000-object escalation was not attempted.

## Actual frontend and rendering limits

At the tested 1,440×900 UI size, actual LÖVE rendering/input of the captured native 1,000-object frame passes 12 checks, retains every exact ID, and finds/opens the last UUID from each 500-object controller group. There is no native target prompt in that frame: the check inspects objects and submits zero gameplay actions. CPU-frame p95 is **24.05 ms**, Lua JSON decode **57.19 ms**, and peak process RSS **274.6 MB**. The cards heavily overlap on the board; the exact-instance browser is the access route.

Current synthetic CPU-frame p95 is about 25.05 ms for 1,000 equal cards, 29.71 ms for varied cards, 24.67 ms under churn and 50.79 ms for 1,000 cards plus a 1,000-entry stack/long log. The 5,000-object scene still preserves exact-last-instance selection, but **126.12 ms exceeds its 60 ms frame allowance**. That case is a performance budget finding, not a native game result or a universal maximum.

Art routing passes 34 checks, including both captured native merged hosts; component inspection passes 10 checks across the copied-token frame. Real image decoding uses generated local fixture pixels. The large-board scenes use local placeholders; no illustration acquisition occurs. These measurements are CPU submission/input timings, not GPU completion or full-art framerate guarantees. Captures were inspected; [the client evidence index](../tests/mechanics_client_report.json) links them.

Machine: Linux x86_64, 24 logical CPUs, 16,699,637,760 bytes RAM, Python 3.12.3, Java 21 and LÖVE 11.5. Native fixtures use ActiveProcessorCount=2 and bounded heaps; production uses a separate owned engine. Some independent bounded runs overlap on the workstation. Exact per-case resource samples and configurations remain in raw evidence.

## Production and historical-run integrity

Final v6 production completes a burn mirror, burn/control, control/control deckout and control/burn with native outcomes. Four/six-seat Commander checks are partial seat rotations. P01/P02/P06 and both rotation scopes pass their replay checks. P03 reaches native deckout at turn 109 with 162 accepted actions, but its initial 30-second replay-export check expires. A separate read-only verification of the preserved recording passes in 24.15 seconds under a declared 90-second ceiling: all 4,498 journal rows, 2,748 frames and 162 accepted actions match, rejected attempts are absent, terminal result and bot-hand privacy hold. Its 605,623,291 raw export bytes become 44,650,756 gzip bytes without loss. The original failure remains unchanged; this is a load-sensitive verification/export finding rather than evidence of a lost native game.

An earlier completed full run passes all six production scopes. Another outer execution exits with signal 15 after its directed tests; its production child finishes, but the parent does not reach its client/cleanup stage. The exact signal sender is unverified; the timeline fits an outer execution lifetime limit. That run is **interrupted**, not silently relabelled complete. Its three orphaned test services were verified by PID birth/cwd/storage/ownership, stopped individually, and the databases/reports preserved. Cancellation cleanup now has focused regressions. Raw files and each build's scope remain linked in the structured index.

## Preservation and reproduction

Engine verification compares **93,956 entries** against the pre-task content/mode/symlink baseline, including generated outputs. Content, existing dirty/diff state, HEAD/index gitlinks and `.gitmodules` match. The final read-only cleanup audit checks 672 recorded PID/birth identities and finds zero live owned processes. The pin remains `d9b266fc981024873ac7ec5f90ee7121a060725e`. Only isolated bridge/test builds were made; the installed payload was not overwritten.

All application saves, metadata indexes, outboxes, caches and frontend test homes belong to owned temporary directories. Original user data, collections, source metadata, bundled lists and engine files were not modified. No images were acquired, no release process changed, and no push/publication occurred. Failed evidence is retained under `/tmp/love2gathering-mechanics-20261115T022333Z-0d97911c` and the separately indexed client roots. Temporary paths can later be removed by system cleanup; the repository JSON index and this report preserve their identities and measured findings.

From the repository root:

```sh
python3 scripts/test-mechanics.py --mode full --jobs 1
```

This command is expected to report the retained native discrepancy and any measured budget findings at this pin. It does not promise an all-green exit. See the guide for smoke/stress modes, narrow repro IDs and manifest budgets. Remaining work includes recording-throughput optimization, the untested exact upstream sequences, varied native 1,000-object escalation, arbitrary pathological bot states and wider card/format/platform coverage.
