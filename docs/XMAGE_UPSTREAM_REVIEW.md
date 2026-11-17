# XMage update — 2026-11-17

The integration advances from `d9b266fc981024873ac7ec5f90ee7121a060725e` to **`c5a5215fa086f487c793627446d5d27e81dfbc97`**, the exact upstream development revision reviewed on November 17. This contains **65 commits, 270 changed files and 34 new card implementation classes**. The version label advances from 1.4.63V1 to 1.4.63V2 while Maven artifacts remain 1.4.63. The official submodule URL is unchanged; no local engine source changes were made. [Exact comparison](https://github.com/magefree/mage/compare/d9b266fc981024873ac7ec5f90ee7121a060725e...c5a5215fa086f487c793627446d5d27e81dfbc97).

## Added cards and sets

| Set | Newly implemented cards |
| --- | --- |
| MSC | Archnemesis; Doom's Time Platform; Extract Power; Galactus, Devourer of Worlds; Glorious Purpose; H.E.R.B.I.E., Lovable Robot; Iron Monger, Sadistic Tycoon; Living Laser; Sauron, Dino Devotee; Typhoid Mary, Fractured; Ultron, Unlimited |
| MSH | Political Triumph; Robot Domination; Taskmaster, Mercenary Mimic |
| NAU | Abyssal Lotus; Calmwater Mentor; Ring of Unity; Salinae, the Ocean Mother; Shimmering Citadel; Tecton, Malignant Ruin |
| FRA | Jace's Machinations; Sanctum Lurker; Uldaros Theorix |
| FRC | Dack Fayden, Helping Hand; Jace, Multiverse Architect; Jhoira, Weatherlight Corsair; Teferi's Reproach |
| HOB | Azog, Moria's Ruin; Elrond, Moon-Reader; Woodland Weavemaster |
| TRK | U.S.S. Voyager, Lone Wanderer |
| TRC | Borg Incursion |
| BOT | Soundwave, Sonic Spy |
| MKC | Eye of Duskmantle |

New set definitions are **Nauctis: The Sunken Realm (NAU)**, **Nauctis: The Sunken Realm Commander (NAC)** and **Wizards Play Network 2027 (PW27)**. NAC adds a Crucible of Worlds printing; PW27 adds four promotional printings of existing cards. A set definition is not a complete implemented set or permission to draft it: NAU's upstream booster support remains disabled until its details exist. Installed implementation coverage and current format legality remain separate checks. [Set sources at the reviewed revision](https://github.com/magefree/mage/tree/c5a5215fa086f487c793627446d5d27e81dfbc97/Mage.Sets/src/mage/sets).

## Changes the client must follow

| Upstream change | Integration handling |
| --- | --- |
| `ACTIVATED_ABILITY` now also covers mana abilities, which do not create stack objects; Loot, the Pathfinder uses `ExhaustManaAbility` | Preserve null-safe event projection and the native ability/color wheel. The compatibility fixture activates ordinary mana and pays/chooses Loot's native exhaust mana, checking the empty stack and resulting mana. |
| Sanctum Lurker changes the state-based action for zero-loyalty planeswalkers | Display the native board and counters without frontend death heuristics. The fixture checks survival at zero loyalty and native removal after Lurker leaves. |
| Connive/surveil event payloads and conditional random modes | Retain generic native choices and event metadata; no Lua card-specific rules or fabricated options. These remain engine decisions. |
| Double-faced entering/counters, blink/copy, transformed/merged permanents in Thieves' Auction/Gerrymandering, Balance with departed players and multiple-defender attack requirements | Consume native state/projections. Native, multiplayer/privacy and recording checks protect the adapter boundary; they do not prove every changed card interaction. |
| New implementations, set printings and installed inventory | Regenerate `bridge/card-map.json` during the engine build and rebuild all required engine/bridge artifacts. Report the exact revision in capabilities, About, source attribution, release provenance and publication guards. |
| Stock Java client image/download/UI updates | These do not update the LÖVE renderer, local catalog or artwork downloader automatically. Keep our existing exact-printing and explicit-download contracts. |

The build downloads current **metadata only** through `scripts/ci/prepare-metadata.py`. The separate November 17 verification source contains 120,139 printings (656,621,303 bytes), updated at 10:06:30 UTC, SHA256 `271185c794ec19ae11bf844c7c582988d90b536e9793c616f060fede82ad0b13`. The supplied September source and user saves remain intact. All 34 added names are present in that source, including the front-face alias for Soundwave, Sonic Spy. A new engine implementation appears in the Builder only when its card also exists in the selected metadata source; format legality still comes from native validation. No card images are acquired for this update.

## Verification

`scripts/build-engine.sh` rebuilds the required XMage modules, generated card map and bridge against the new pin. Upstream API changes require a clean reactor build to avoid old card bytecode remaining compatible only with the prior engine. `UpstreamCompatibilityFixture` adds **51 native checks** covering all 34 installed new classes, the new set printings, exact revision, mana events without stack objects, exhaust payment/color choice, the zero-loyalty exception and an unchanged Nimble Obstructionist constructor that detects stale bytecode. [Focused report](../bridge/tests/upstream-compatibility-report.json).

The fresh payload also passed the existing native fixture gate, all 20 bundled deck startups, a completed eight-turn game, replay delivery/reopening/outage/crash recovery, native priority, human-seat multiplayer privacy and draft HTTP checks. Separate library-top, native recovery and gameplay-presentation gates rebuilt and checked their production adapter classes. [Final integration report](../bridge/tests/upstream-integration-report.json) records the exact payload hashes and evidence scopes. These tests do not establish every new card interaction or native Windows/Fedora installer behavior.

The publication guard permits the exact previously published development/master base snapshots only for this reviewed transition. Every outgoing commit and the index must use the new canonical pin and the unchanged official `.gitmodules`; unexpected or intermediate pins, extra gitlinks and downgrades remain rejected. Only the parent branch is published, with recursive submodule pushes disabled.
