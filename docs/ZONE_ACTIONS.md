# Native zone actions and stable card choices

XMage remains the authority for every offered object, ability, cost, target and
zone transition. The adapter and Lua UI add descriptions and reversible local
selection; they do not implement card rules or modify the engine.

## Current offers

`prompt.actionable` is the complete current object-selection boundary. A present
empty list disables all card actions. `prompt.cardActions` describes those same
offered UUIDs, their native source zones and available native ability options.
The descriptions reuse the exact native computation already used to construct
the query, rather than running another playable-action simulation.

An option's ability UUID is informational until XMage actually asks an ability
choice. Selecting a graveyard, exile, command or hand card sends its current
object UUID. Any subsequent ability, optional cost, mode, target and payment
choices use the separate responses offered by XMage. Cost text is explicitly
labelled **before choices**: reductions, optional costs, target-dependent costs
and the final payment remain native decisions. Unknown descriptions never grant
or remove legality.

The shared actions sheet is available from card inspection. Several native
options open the sheet automatically. Graveyard and exile popups mark legal
cards with a `PLAY` frame and permit dragging them out of the popup. A drag
retains the native game, prompt and zone-opening identities; changing any of
them cancels the drag. It dispatches a native UUID and never inserts a permanent
locally.

The exile extension contains only current native offers in `EXILED`. An expired
offer disappears even if the card remains in exile. Face-down cards stay hidden
unless the projection explicitly provides that viewer's private identity. This
allows the owner to use a legally offered foretold card while other humans
receive only the hidden card. Replay and disconnected-room controls cannot send
live actions.

## Staged selections

The bridge labels the whole native target-selection operation with a stable
`cardPanel.interactionId`. Its consecutive query IDs can change without closing
the popup. Native minimum/maximum bounds, per-card selected flags and exact
choice IDs remain separate fields.

For a native multipick, clicking toggles a visible local `SELECTED` marker and
selection count. **Confirm selection** is enabled only within the native bounds.
Only confirmation begins the sequence of currently offered native UUIDs. The
same panel remains visible during acknowledgement and across the next native
query; an already accepted selected UUID is not toggled twice. Scry/surveil retain
their existing destination/order staging. Required decisions have no invented
Escape cancellation.

## Public targets and event metadata

Stack target projection includes all selected modes. Native
`Target.hasChangedZones` prevents an arrow from attaching to a returned card
that has the same card UUID but is a different rules object. Selected mode text,
native paid costs, paid alternative mechanics and accepted Convoke contributors
remain inspectable metadata.

`currentKeywords` and `mechanicCapabilities` come from effective native abilities,
including gained/lost abilities. Original printing metadata stays separate.
Native keyword classes, typed ability words and keyword-action effect classes
provide identities; arbitrary rules text is not parsed into legality or causes.
Unclassified interactions retain their native class/rule and generic presentation.

Confirmed events distinguish destroy, sacrifice, exile, return, discard, mill,
tap, counters, face changes and actual entry. A battlefield entry has one entry
identity and carries its native mana value/commander impact data; spell
resolution alone does not imply an entry or a slam. Resolution observers ignore
simulations and restore their enclosing scope even after exceptions.

Cause attribution uses the actual zone-change source ability, an exact matching
active native ability, or an exact matching currently resolving stack ability.
For example, Convoke tap events identify actual contributors and the committed
cast carries native accepted contributor references. Extort life events use the
resolving native Extort ability. Evoke uses the native paid alternative-cost tag
and typed sacrifice-trigger condition, rather than its printed presence or an
assumed cast mode. Missing causes remain generic.

## Acceptance

Run from the repository root:

```sh
python3 bridge/tests/test_zone_actions.py
lua5.4 tests/zone_actions.lua
lua5.4 tests/card_choices.lua
tests/match_choices_ui.sh
LOVE2GATHERING_NATIVE_ZONE_FRAMES=/tmp/love2gathering-mechanics-zone-actions-<run>/native tests/zone_actions_ui.sh
```

The native wrapper builds a fresh adapter in owned temporary storage, hashes its
sources/dependencies, verifies the engine identity remains unchanged and applies
resource limits. Its 59 native checks cover actual Flashback Memory Deluge,
Counterspell replacement/exile, private two-card selection, Jump-start discard
and full payment, temporary exile spell/land permissions and native cleanup,
Foretell's private identity and later-turn restriction, gained/lost abilities,
sixty-creature Wrath with an indestructible survivor and one native batch, and
stack target incarnation changes. Initial zones/resources and explicit turn or
cleanup boundaries are deterministic fixtures.

The graphical test uses the exported viewer-filtered frames with actual
LÖVE/Slab drawing and mouse input. Its local adapter replays the already accepted
native UUID sequence. It proves staging, indicators, stable modal identity,
confirmation dispatch, graveyard/exile drag, private Foretell presentation,
expired offers and stale/disconnect/replay guards. It is not a live GUI-to-engine
match or a WAN acceptance test. Existing native gameplay/visibility/Commander and
native entry/X/counter regressions also pass against the frozen adapter.
