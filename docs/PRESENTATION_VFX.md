# Native-state motion and mechanic presentation

This is the LÖVE 11.5/Slab implementation. XMage still owns every legal action,
cost, target, priority decision and outcome. `app/mechanic_fx.lua` draws current
native descriptors and accepted native events; it does not parse rules text or
logs to decide why something happened. `app/board_fx.lua` supplies the existing
combat presentation, current anchors and renderer integration.

## Visible language

Card edges carry at most one dominant and one secondary mechanic signature,
with two static badges and `+N` for additional mechanics. The inspector retains
the complete named list. Static badges, native P/T, counters and action markers
remain readable when animation, particles, intensity or ambient effects are off.
The branching action marker uses the actual offered native object, and shows an
option count only when `app/card_actions.lua` supplies that native option list.
A subdued capability marker describes an interaction, not current legality.

| Mechanic | Identifiable signature and contextual motion |
| --- | --- |
| Flashback | Broken return ring; graveyard-to-exact-stack-row reforming fragments |
| Jump-start | Fuel notch and lightning; accepted discard travels toward its spell |
| Evoke | Offset echo cards; transient casting silhouette and an explicit native sacrifice seal |
| Convoke | Contributor sockets; accepted native tapped contributors converge toward their spell |
| Mutate | Interleaved layers; actual merge shifts and settles layers without an entry slam |
| Face down / face up | Neutral folded shell; public shell unfolds only after the native face-up event |
| Haste | Leading speed streak; stronger cue on native actionable objects and declared attacks |
| Extort | Toll clock; actual native life transfers travel toward the source/controller |
| Trample | Overflow chevron; sparse attacking dust and accent on actual damage |
| Reach | Net silhouette and interception arc, distinct from Flying's open wing/lift |

Native damage remains exact: a keyword never invents damage, retaliation, a
first-strike participant or trample overflow. A recipe needs an exact native
mechanic/cast-mode descriptor to receive its named event accent. Missing causes
or anchors produce a restrained generic cue, or no decoration.

Destruction fractures outward, sacrifice contracts into an offering seal, exile
separates into planes, return follows a destination arc and generic graveyard
departure stays neutral. Shared noise only dissolves/reforms an outer frame;
the scanned card image, name, cost, rules and counters are never warped.

## Native contracts

Cards expose current `currentKeywords` and `mechanicCapabilities` descriptor
arrays, including `id`, `name`, `category`, `nativeClass`, `parameter` and native
provenance where available. An explicitly empty current array suppresses older
printing keywords. `card.mechanics` can provide a complete combined array.
Cache invalidation follows replacement descriptor arrays and
`characteristicsRevision`.

Events have stable `id`/`sequence`, `nativeType`, `operation`, exact
`sourceId`/`targetId`, optional `abilityId`, `mechanic`/`mechanics`, `castMode`,
`fromZone`/`toZone`, player/controller identities and `amount`/`combat`/`step`.
`batchId`/`resolutionId` groups only a real native resolution. Generic movement
to a graveyard never implies destroy or sacrifice. `operation='resolved'`
requires `successful=true` or `success=true` for a resolution outcome.

`causeSourceId` retains the original native card UUID separately from an event's
stack-object `sourceId`. Exact stack rows accept either the native stack UUID or
its original source UUID; paired native zone-to-stack events retain the casting
zone. `paymentForId` and `contributorId` identify accepted Convoke payments.
Native costs tags also export committed `contributors` and `paidMechanics`.
Convoke uses the scoped actual special action, Evoke uses the paid native costs
tag/typed trigger condition, and Extort life events use the actual resolving
stack ability only when its source identity matches. Keyword presence alone
does not supply these causes.

An actual permanent entering the battlefield emits `entry=true`,
`operation='enter_battlefield'` with its native permanent UUID, commander flag
and mana value. Native commander and mana-value-above-five entries get the
larger rise/settle/contact treatment. Stack disappearance, successful instant
resolution, countering, merging, turning face up, reconnection and replay seek
do not produce a phantom entry slam. X uses the native captured stack value.

Unentitled hidden objects reveal neither printing mechanics, color, intensity
nor hidden commander/value. Public face-down permanents use one neutral shell;
private hand backs do not advertise a face-down mechanic. Effects never restore
departed cards as interactive ghost cards.

## Renderer hooks and coordinates

`Board.cardUnderlay(r, card, x, y, w, h, options)` runs before the card surface;
`Board.cardOverlay(...)` runs after the upright text/badge layer. Coordinates
are local to the current card transform, supplied by the renderer. Skip either
hook for `presentationGhost` or `imageOnly` previews. A public face-down view
passes `kind='permanent'`, `kind='attachment'` or `publicFaceDown=true`.
`Board.mechanicBadges` tells the renderer to avoid a duplicate legacy badge row;
`Board.mechanicTooltip(card)` exposes the full list and fallback limitations.

The normal lifecycle remains `Board.update` → current table/card drawing →
`Board.foreground`. Prepare/flush use actual current logical screen coordinates
after camera pan/zoom and UI scaling. `r.stackRows[stackUUID]` contains exact
`x/y/w/h`, `visible` and optional `clip`; `r.zoneRects[playerUUID][zone]` and the
previous zone/card rectangles supply legitimate departure/cast origins.

Stack target arrows are shown for the hovered/selected exact native stack
object. They originate at its clipped current row and terminate at the current
target edge, including another exact stack row. They never borrow a source-card
preview, previous target ghost or screen center. Native `changedZones=true`
prevents redirecting to a later incarnation sharing a UUID. The actual emitted
geometry is exposed in `r.boardLinks` for endpoint/pan acceptance.

## Bounds and preferences

- Director: 64 active/pending effects, 64 pooled objects, 32 transfer trails,
  512 retained event IDs, one active major wave. Full native affected counts
  survive decoration dropping. Large batches prefer explicit material outcomes.
- Particle budget: 256 including existing asset particles, ambient dust,
  fracture shards, Flashback fragments and life-transfer motes. Ambient dust
  alone is limited to 48. Vector badges/edge strokes are bounded separately by
  two recipes per card and the 64-effect director.
- Offscreen event material is culled to the shared table viewport. Active drag,
  panning, inspection and mandatory input suppress disruptive card/terrain poses.
  A new native prompt shortens old decoration rather than awaiting an animation
  callback. Pooled objects are fully cleared before reuse.
- Entry offsets are bounded to 12 horizontal / 44 upward / 12 downward logical
  pixels and 0.055 radians. Camera shake has its own bounded preference and
  does not change state or legality.

`vfxIntensity` controls edge/event opacity; `ambientKeywordFX` disables idle
edge motion; `presentationPacing` is Standard, Fast (1.65×) or Minimal (4×
retirement with no displacement). `cameraShake`, `parallax` (lift contact
shadow) and `distortion` (edge material/membrane) have independent effects.
Existing `animations`, `particles` and `reducedMotion` settings remain applied.
Reduced motion and Minimal keep static state/badges and immediate input.

## Reused assets and inspection

The implementation reuses curated assets through `app/assets.lua` and
`app/surfaces.lua`; no new asset download or dependency is required. The asset
contact sheet at `build/presentation-vfx/asset-contact.png` was visually viewed.
This was representative inspection of the runtime selection, not a claim to
have viewed every supplied pack file.

| Actual path | Applied use |
| --- | --- |
| `assets/kenney/particles/circle_05.png` | Existing bounded soft particles |
| `assets/kenney/particles/star_04.png` | Existing spark particles |
| `assets/kenney/runtime/surfaces/perlin-noise.png` | Cached luminance mask for edge dissolution |
| `assets/kenney/runtime/surfaces/ring_a_noise.png` | Contact halo / transient echo |
| `assets/kenney/runtime/surfaces/pattern_72.png` | Lattice / indestructible edge material |
| `assets/kenney/runtime/surfaces/circle_a.png` | Existing spotlight surface |
| `assets/kenney/runtime/surfaces/gradient-vertical.png` | Existing depth/fade surface |

The inspected existing skin also includes `assets/kenney/theme/` fantasy frame,
inset and divider, space panel/button/square/focus. Those remain the application
skin, not new VFX. Beleren, DejaVu and Mana font roles are preserved. Existing
rate-limited cast/impact audio remains in Board; this change adds no audio files
and does not claim a full listening audit.

## Coverage and extension

`tests/mechanic-coverage-report.json` inventories the actual registry, all 248
keyword Ability classes in the pinned native engine, and the public keyword
labels in the 120,139-row metadata source. Native class presence is not proof
of a card's current ability or runtime legality.

| Inventory | Explicit | Composed | Generic static | Unsupported |
| --- | ---: | ---: | ---: | ---: |
| Registry | 79 | 276 | — | — |
| Native keyword classes | 64 | 183 | 0 | 1 |
| Metadata keyword abilities | 66 | 139 | 0 | 1 |
| Metadata keyword actions | 7 | 27 | 0 | 0 |
| Metadata ability words | 1 | 36 | 0 | 0 |
| Metadata named/flavor interactions | 0 | 0 | 660 | 0 |

Explicit means a named authored glyph/contextual recipe; composed means a
reviewed named mapping to a reusable semantic family. Neither claims a bespoke
animation for every card or an observed native event for every mapping.
Paradigm is unsupported because its pinned native class is a TODO stub.
Unknown future mechanics keep their name and a static neutral sigil, and are
not advertised as authored animation support.

To extend a mechanic, add an explicit row or reviewed composition in
`app/mechanic_fx.lua`, reuse/add a distinct vector glyph and contextual edge
recipe, and add an exact native-class mapping in `NativeMechanics` when needed.
Only add event behavior after an authoritative operation/mechanic identity and
anchor exist. Never derive legality or causal semantics from rules/log text.
Exercise hidden views, reduced motion, actionability, stale snapshots and caps,
then regenerate coverage:

```sh
python3 scripts/report-mechanic-coverage.py --metadata build/update-verification/cards.jsonl
```

## Acceptance evidence

`tests/mechanic_fx.lua` passes 121 pure presentation contracts;
`tests/board_fx.lua` passes 52; `tests/combat_indicators.lua` passes 19. Lua 5.1
syntax validation also passes for these modules and the graphical harness.
These pure checks are not native rules tests.

`bridge/tests/test_mechanic_causes.py` compiles and runs
`MechanicCauseFixture.java` against a fresh or hash-verified bridge JAR. Its 33
checks exercise accepted native Evoke cost/entry/later sacrifice, Extort payment
and exact life transfer, five accepted Convoke contributors without pool mana,
Mutate merge without entry, hidden Morph/paid face-up without another entry,
new Haste attacker selection, legal Reach-versus-Flying interception, and actual
native Trample damage assignment in a prepared combat group. Only initial
zones/resources and the Trample group are prepared; this is not a complete
production game or GUI acceptance. `tests/mechanic_causes.lua` consumes those
actual frames and passes 20 director/endpoint contracts using synthetic geometry.

The GUI harness additionally captures eight detailed native outcome scenes at
`build/presentation-vfx/native-causes.png`, retaining exact source-frame hashes.
This caught stack/source UUID mismatches that synthetic event fixtures did not.

`tests/mechanic_fx_ui.sh` draws through actual LÖVE, verifies identical pixels
for different hidden colors/mechanics, verifies still reduced-motion pixels,
and captures named profile/material and crowded scenes. Its labeled synthetic
benchmark draws 100 cards and 50 confirmed destroy fixture outcomes, with a
matching 100-card baseline after 20 warmup frames and vsync off. This is CPU
draw-submission timing, not full-app frame time, GPU timing or a guaranteed FPS.

The same harness consumes the actual viewer-filtered native Wrath frames at
`build/table-overhaul/zone-actions/wipe-{before,after}.json`. It checks one
60-permanent native destroy batch and the actual indestructible Darksteel Myr
survivor. Its native-wipe picture uses synthetic noninteractive geometry; only
the current native survivor is drawn as a live card. This is native event
consumption evidence, not a complete playable-match or full-table UX test.

Final reports include exact source hashes, renderer identity and capture paths:
`tests/mechanic-vfx-ui-report.json` and
`tests/mechanic-vfx-software-ui-report.json`. The software run uses Mesa
llvmpipe; its 100-card baseline mean/p95 is 8.23/12.93 ms and effects mean/p95 is
16.51/17.83 ms. The primary OpenGL 4.6 Radeon run (Ryzen 7 6800HS integrated
graphics, Mesa 25.2.8) measures baseline mean/p95 0.59/0.94 ms and effects
1.99/2.55 ms. These measurements expose the cost of maximum crowded effects on
software rendering; Fast/Minimal, ambient and intensity controls reduce
presentation load. The reports retain full measurements and source hashes.

Run the graphical check with a distinct output/report location when comparing
drivers, so captures and provenance do not overwrite each other:

```sh
LOVE2GATHERING_VFX_OUTPUT="$PWD/build/presentation-vfx-software" \
LOVE2GATHERING_VFX_REPORT="$PWD/tests/mechanic-vfx-software-ui-report.json" \
tests/mechanic_fx_ui.sh
```

Remaining limits: full native runtime examples for every composed mechanic are
not established; missing native cause/anchor data intentionally stays generic.
The crowded benchmark is one layout/workload, and software timing is not a
Windows VM acceptance result. All legality and engine-version acceptance stay
with the bridge/native tests; no engine source or gitlink is changed here.
