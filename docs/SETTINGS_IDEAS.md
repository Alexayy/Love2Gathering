# Settings: implemented controls and future ideas

The first section describes working controls in this build. The ideas below are proposals only; they have no saved keys or inactive switches in the application.

## Implemented presentation additions

| Control | Default | Applied behavior |
| --- | --- | --- |
| Heading and card title font | Beleren | Uses the supplied display font for headings, deck names and card titles; Application font uses the independently selected body family for titles too. Missing glyphs/fonts fall back to DejaVu. |
| Space background | Galaxy | Selects Galaxy, Nebula, Band, Dark, Day or Off. Supplied panoramas fill the window with aspect-preserving cropping; at most two stay decoded. |
| Background brightness | 32% | Multiplies the selected background's actual brightness. |
| Playmat opacity | 88% | Changes the visibility of each player's selected artwork behind the field. |
| Counter display | Dice | Dice/Text preserves the exact native count and counter name. Pips represent 1–6; other values stay exact numerals on the blank die. |
| Pointer style | System | Kenney uses the supplied arrow/hand and correct hotspots, with native text/resize cursors and safe fallback. |
| Explain keywords | On | Adds short explanations for recognized abilities in card details, without changing engine decisions or rules. |

These controls work alongside existing display/resolution/render/UI scale, motion/particles, contrast/color palette, tooltips, local artwork and audio controls. Application font discovery uses Fontconfig on Linux. Mana and set symbols retain their own supplied fonts. **Apply and save** applies presentation preferences and persists them; game options explicitly apply to the next match.

Profile is a separate saved choice: name, exact card-art avatar and optional playmat, with search through actual printing/face artwork. Life has no override; it always follows XMage. Audio already has music/SFX enable switches plus master/music/SFX volume. Selected Kenney interface, card-slide/shuffle and impact clips use those controls. Detailed asset provenance is in [the supplied-pack audit](../assets/KENNEY_CATALOG.md), and profile behavior is in [PROFILES.md](PROFILES.md).

## Prioritized future options

| Priority | Idea | Intended benefit and acceptance requirement |
| --- | --- | --- |
| 1 | Separate hand and card-preview size | Let players enlarge their hand or reading preview without scaling every control. Preserve the fixed hand, terrain space, scaled hit regions and drag/drop behavior at small windows. |
| 2 | Target/combat line visibility and contrast | Offer clearer line width/opacity or optional quieter lines while retaining an accessible way to inspect every native target/block assignment. Do not invent targets or use color as the only distinction. |
| 3 | Camera overview/minimap and zoom shortcuts | Add quick orientation and keyboard focus/zoom alongside current seat buttons, right-drag, wheel and explicit overview. Keep keyboard input out of text fields and preserve cursor-centered camera math. |
| 4 | Reduced visual clutter preset | Offer a coherent quiet view for optional particles/movement/background contrast, with an easy way back to the prior preferences. Keep native P/T, counter names, priority and required choices visible. |
| 5 | Per-zone preview preferences | Let hand, battlefield, graveyard and stack previews use different sizes or delays. Public/entitled information stays inspectable, and hidden information remains hidden. |

Choose defaults after actual desktop interaction tests and screenshot review at normal/scaled resolutions. Each new control needs a bounded validated value, a working rendering/input effect and restart persistence. Avoid separate settings where the existing UI scale, reduced motion, brightness or preview toggle already solves the need.
