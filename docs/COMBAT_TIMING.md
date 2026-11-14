# Combat confirmation and sacrifice timing

XMage validates blocker declarations and combat damage. Clicking a blocker is a provisional assignment; **Done** completes the native declaration. A confirmed blocked attacker remains blocked if its blocker is subsequently sacrificed. Without trample or another applicable native effect, it does not then deal combat damage to the defending player. Sacrificing a creature before declaring it as a blocker does not block anything.

The compact shield control enables an opponent-turn stop at native `DECLARE_BLOCKERS`: **after blockers are confirmed, before combat damage**. The adjacent combat-stop picker exposes beginning of combat, after attackers, before damage, after first-strike damage, after normal damage and end of combat, independently for own and opponents' turns. A first-strike stop occurs after that damage has happened. Full control remains available. Stops never answer blocker selections or sacrifice costs automatically.

The battlefield labels an assignment **PROVISIONAL** until native `DECLARED_BLOCKERS` confirms it, then **BLOCKED**, including when its blocker list becomes empty. This label does not promise damage prevention: trample and other native abilities still apply. Current keyword icons and current rules include temporarily granted abilities; the original printing remains separate.

During a native battlefield choice, the floating stack folds into a compact header control so it cannot cover the permanent being selected. **Show stack while choosing** expands it for inspection; the existing stack toolbar control remains available. Once that choice ends, the usual stack layout returns. The game stack, choices and costs are unchanged. This specifically fixes the small-window case where Ayara's pending ability covered the Rat being offered for its sacrifice cost.

## Native evidence

`CombatTimingFixture` uses real engine cards, blocker selection, production bridge responses, Ayara's native sacrifice/tap costs, native stack resolution and native damage steps. Only initial zones and turn position are deterministic fixtures. It proves:

| Situation | Native result |
| --- | --- |
| Confirm a Rat block, then sacrifice it against a 2-power attacker without trample | 0 damage to defender |
| Sacrifice the Rat before declaring a block | 2 damage to defender |
| Confirm a block, then sacrifice it against a 6-power trampler | 6 damage to defender |
| A 2/2 Rat survives the first strike of a 1-power double striker, then is sacrificed before normal damage | 0 damage to defender |

The fixture also checks an empty bluff stop before damage, normal versus cannot-block native Rat tokens, and Goreclaw's real attack trigger granting trample to eligible creatures and losing it during native end-of-turn cleanup. Run it through `scripts/test-engine-fixtures.sh`; results are in `bridge/tests/combat-timing-report.json`.

`tests/combat_timing_ui.sh` separately exercises actual LÖVE/Slab controls and HTTP responses against the test-only `NativeViewServer` Ayara and Goreclaw scenes. Its zones are fixtures, not a production-deck match. The final 34 checks use separate 1440×900 and 1120×760 processes, retaining actual physical/logical dimensions. They cover provisional/confirmed display, the native before-damage stop, folded-stack access to the sacrifice target, actual ability/cost responses, final damage, the combat-stop picker and visible granted Trample in card details. Results are in `tests/combat-timing-ui-report.json`.

The separately inspected user recording contains a confirmed Rat block followed by Ayara sacrifice on turn 22. Goreclaw's attack trigger had already granted trample to all three large attackers. Native live rules and damage events explain the resulting damage. The bounded, anonymized public chronology is retained in `bridge/tests/ayara-replay-diagnosis.json`; no hands or credentials were copied.

## Projection fields

- `combat.groups[].blocked` is native combat state. `declarationConfirmed` acknowledges native validation for that group's defending player in the current combat phase. An empty `blockerIds` array does not clear either flag.
- `prompt.combat.declarationConfirmed:false` and `message` distinguish an unfinished blocker selection from priority after confirmation.
- `card.currentRules` contains the current native ability rules. `card.keywords` lists recognized exact native keyword-ability classes; it is display metadata, not a complete legality API. `card.abilityIcons` contains the native icon type, hint and optional text. `card.printing.keywords` remains tied to the original printing/template.
- The priority timer uses the native holder and timestamps, in a separate reserved display lane. It shows elapsed time and imposes no invented timeout penalty.

Multiplayer terrain follows native active-player/turn changes by default. Manual focus, panning or zoom remain free for that turn; the next turn resumes following. Disable **Follow the active player** in presentation settings to keep manual control across turns. The local hand remains fixed.
