# Native combat, commander and image presentation

This frontend presents XMage choices. It does not implement combat legality, lethal assignment, menace, commander tax or commander loss rules in Lua. The engine submodule remains pinned and unchanged.

## Combat choices

`prompt.actionable` remains authoritative, including an explicitly empty array. An attacker prompt also exports `combat.role="attackers"` and `selectedAttackerIds`. Individual UUID answers were already supported by the pinned HumanPlayer; explicit image controls and selected state make them accessible beside All attack. Blocker selection is provisional until the native Done choice confirms it.

Native `multi_amount` prompts use numeric text fields and an image grid when exact target identity is available. Reordering this grid is presentation only. Every field retains its original one-based native index, and confirmation sends the original index order. Ranges and totals come from the native prompt; XMage validates the response. The bridge attaches combat card IDs only when its native title, header, complete ordered row labels and live combat group match uniquely. Other distributions retain their generic labels and behavior.

Modern Magic no longer uses the old damage-assignment ordering procedure. See the [Foundations update bulletin](https://magic.wizards.com/en/news/announcements/foundations-update-bulletin) and [release notes](https://magic.wizards.com/en/news/feature/foundations-release-notes). A display drag is therefore never sent as an invented combat-order command. The installed engine remains responsible for its offered choices and accepted assignment.

The popup stages changes locally until explicit confirmation. Prompt/game identity and modal guards reject stale releases, background board clicks and answers from a previous opening. Modal transitions clear hidden Slab focus and hot scrolling state. Zone grids consume the complete opening gesture before accepting their first card click, so a library-count press cannot accidentally play the newly overlaid image. Escape dismisses a retained look view; it does not invent cancellation for a required native choice. Native offered Cancel controls remain available.

## Battlefield layout and manual payment

Duel and multiplayer share the same illustration renderer. It uses the exact face’s cached art crop first, then the illustration area of its full scan. A missing image falls back to the card’s title and type icon. Hidden faces keep their card backs. Titles and native P/T stay in screen-readable orientation when the tile tilts. The layout and pointer hit tests use the same rotation. Hands, stack entries and inspection keep their full card format.

Each seat places creatures at the front, with a separate strip for planeswalkers when present. Support permanents and lands occupy the rear left and right. The renderer classifies the current XMage object after continuous effects. A tapped creature land retains normal artwork and a tap symbol, while a tapped noncreature land also has muted artwork.

The duel centers its two life portraits across the combat rows. Multiplayer fits the seats above the screen-space hand. During payment, individual XMage offers keep equivalent lands separately clickable. The right-side panel binds each source, mana ability and floating-mana button to its current prompt choice. The primary pass button also requires an explicit pass choice. The integrated interaction and render fixture runs with `tests/battlefield_style_ui.sh`.

## Table card preview and details

Hover draws a full card in the left part of the screen, independently of camera zoom, and releases it when the pointer leaves. A stationary right-click pins a card. The preview stays available while playing or selecting targets. Exposed stack entries also show their own rules during a card choice. A battlefield preview can show the current type, P/T, counters and granted keywords alongside the printed face. Middle-click opens scrollable details. Closing details returns to the underlying choice or zone with its selection intact.

The model resolves a pin or an open inspector against the viewer’s current XMage projection, including its zone, prompt, stack row or revealed library top. Playback repeats that check on each frame. The renderer uses the full printing scan when available and falls back to text. The preview has no left-button hit region. The integration fixture `tests/table_preview_ui.sh` runs the production mouse callbacks with Starter scans at two UI and render scales.

## Public zones and face-down inspection

Graveyard/exile and entitled library cards use paged image grids with text search. A select panel sorts basic lands first without changing engine indices or zone ordering. Cards are selectable only when native offered IDs allow them; unavailable visible candidates remain grey. These views never request an unentitled card's name or artwork.

`faceDownIdentity` is a native inspection-only subcard supplied only to the entitled controller. The battlefield retains its card back and current face-down characteristics. Hover/inspect may use the subcard while separately describing the native face-down P/T and damage. Catalog enrichment refuses a hidden or face-down host card; remembered images do not grant permission.

## Commander metadata

Practice `/session/start` and constructed `/multiplayer/start` accept `commanderDamage` (default true). Room creation validates an actual boolean, stores it in immutable room configuration and carries it through start and rematch. For Commander, the bridge calls the native `setCheckCommanderDamage` before game initialization. False is a house rule that disables the native commander combat-damage tracking/loss condition.

State exports `commanderDamageEnabled`. Each player has:

- `commanders`: entries with `id`, `name`, current `zone`/`zoneName`, entitled/public `sourceCard`, `commandZonePlays`, `deaths`, native `availableCastingOptions` and `additionalTax` (`manaCost`, `otherCosts`).
- `commanderDamageReceived`: entries with `commanderId`, `ownerId`, `name` and `amount` from the native combat-damage watcher. Disabled tracking has no fabricated ledger.

Cast counts come from `CommanderPlaysCountWatcher`; death history comes from actual native dies events in an independently copied bridge watcher. Tax is the native `commanderCost` on a detached ability, including non-mana exceptions such as Liesa. A death count is never used to calculate a casting cost. [Official Commander overview](https://magic.wizards.com/en/formats/commander) describes the ordinary tax and 21-damage rule.

## Derived damage labels and activity

Native power, toughness and marked damage remain separate. A card badge may show `power/(toughness − marked damage)` with the second number red. Inspect labels identify native P/T, marked damage and the derived remaining value, so indestructible creatures and other unusual states do not become client-side rules decisions.

`Model:activityState()` distinguishes pending action/control, an acknowledged choice/priority transition awaiting the next state, connection errors, state reads delayed over 0.8 seconds, hand-image work and an ordinary player wait. The last has `busy=false`. A supplied loading-circle asset is drawn near the existing pointer, with elapsed time after 0.8 seconds. No cursor backend is repeatedly replaced and no gameplay choice is passed automatically.

## Match image warmup

`app/game_art.lua` uses native game identity and the local perspective. It first requests missing exact hand metadata and full-card images with a separate hand priority; this explicit game-start acquisition overrides Cache only. At most two hand image requests are pending, with texture uploads still subject to the existing per-frame bounds and shared decoded-memory budget. An explicitly selected Builder card keeps its own priority and cancellation policy.

After the hand settles, a single background `/art/download` request acquires each needed full-card/art-crop image into the existing cache. The queue is deduplicated and bounded at 512 identities, uses the local submitted practice deck (or local accepted draft selection), and includes Plains, Island, Swamp, Mountain, Forest and Wastes. Exact per-deck printing selections are preserved. Background acquisition stores bytes without decoding the whole deck to GPU textures. Failures do not spin in a tight retry loop. Game, local-player, room-connection and route changes invalidate callbacks. Replays, ambiguous human perspectives and a prepared storage relocation do not initiate warmup.

## Verification scope

The focused native gameplay fixture exercises actual offered UUID attackers, menace acceptance/rejection, damage assignment and private face-down/commander state. Separate Slab fixtures drive real text input, card dragging, confirmation, zone grids, modal guards and room/lobby layout. Their synthetic scenes are presentation tests, not complete real games. See `tests/gameplay-presentation-report.json` for the final run's gates and limitations.

## Native answers, undo and completion

Native `HumanPlayer.setResponse*` can wait for the GAME thread to finish publishing a question to its observers. A local HTTP action must not hold its acknowledgement open during that wait. `NativeInputQueue` validates and records the accepted answer, then delivers it through a bounded, per-perspective worker. Delivery rechecks game/prompt identity after native response opening. A rejected or stale queued answer cannot answer a newer question. Input workers retire when idle; game execution and actual undo stay on GAME threads.

`state.inputDelivery` carries a pending count, delivery ID, original prompt ID and a bounded error. A failed delivery restores controls only if that exact question is still active and the frontend had answered it. It never automatically resends a cost or selects another response. Transport diagnostics use the existing replay `log` event with `data.type="input_delivery"`; the SQLite outbox and catalog preserve idempotent sequence semantics. Native state, native health, proxied private game-state reads and capability discovery have separate frontend workers, while ordinary mutations retain their ordered lane. Existing route-generation and assigned-game fences still reject late state responses. This avoids hiding prepared state/health behind a slow mutation socket; it does not extend every timeout.

An actual reversible mana bookmark adds `prompt.undoChoice`, with native response type `undo`. There is no client turn snapshot or guessed rollback. The bookmark is armed only after its exact response is open and fenced, so a stale queued undo cannot affect a later valid answer. Selection cancellation remains limited to offered native Cancel, apart from a local unsubmitted drag cancelled by right-click/Escape.

The bridge disables native automatic target selection for human seats so equipment presents even a sole legal target. Native Greaves tests explicitly equip Giada, then activate Equip and select Angel of Jubilation; the shrouded old wearer is not offered as a target. Angel of Serenity pays its native seven-mana cost and resolves a three-target battlefield/graveyard ETB in the focused fixture. The original timeout regression reproduced delayed response opening, rather than an Angel-specific rules failure.

`state.result` is captured on GAME from native completed outcomes. Error, abort, spectator and stale-game results never become a fabricated draw. Duel completion owns the input lock and hides retained native prompts, with one fullscreen outcome and its rematch/menu controls. Multiplayer elimination uses native lost/left state to dim that seat and show OUT; zero life alone is insufficient. Room rematch requests and all-human consent are documented in [ROOMS.md](../service/ROOMS.md).

Card headers measure the actual current/native mana cost and retain its symbols beside the name, wrapping the full cost on small cards. Stronger phase markers keep native stop hit regions intact and show the exact step. These are presentation changes; no mana, timing or combat rule is calculated in Lua.
