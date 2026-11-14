# Settings: implemented controls and future ideas

The first section describes working controls in this build. The ideas below are proposals only; they have no saved keys or inactive switches in the application.

## Implemented presentation additions

| Control | Default | Applied behavior |
| --- | --- | --- |
| Application typeface | Beleren | Uses the supplied face throughout headings, body text, lobby and gameplay. Missing glyphs/fonts fall back to DejaVu. Legacy font selections remain readable but do not replace Beleren. |
| Space background | Galaxy | Selects Galaxy, Nebula, Band, Dark, Day or Off. Supplied panoramas fill the window with aspect-preserving cropping; at most two stay decoded. |
| Background brightness | 32% | Multiplies the selected background's actual brightness. |
| Playmat opacity | 88% | Changes the visibility of each player's selected artwork behind the field. |
| Counter display | Dice | Dice/Text preserves the exact native count and counter name. Pips represent 1–6; other values stay exact numerals on the blank die. |
| Pointer style | Kenney | Supplied arrow/hand, pan/drag, text and resize states use reviewed hotspots, with safe platform fallback and explicit System mode. |
| Pointer size | 55% | Scales the supplied cursor bitmap and hotspot together, including text selection. |
| Font quality | High | Rasterizes Beleren at twice native DPI; Standard uses native DPI. Logical layout/caret geometry stays independent of board render scale. |
| Card back | Arcane | Arcane, Azure, Verdant and Crimson use supplied Kenney card backs; hidden card faces stay hidden. |
| Board impact strength | 55% | Smooth terrain/independent-card impact on resolved native commanders or mana value >5, including X. Reduced motion and disabled animations suppress it. |
| Explain keywords | On | Adds short explanations for recognized abilities in card details, without changing engine decisions or rules. |
| Color theme | Midnight | Midnight, Amethyst, Ocean, Ember and Obsidian affect both custom rendering and Slab controls. |
| Player/opponent accents | Theme colors | A color picker or validated #RRGGBB value changes actual frame/name/control colors. Reset restores the theme's value. |
| Panel opacity | 65% | Changes panel transparency independently of playmat/background controls; controls and tooltips retain readable surfaces. |
| Follow the active player | On | Multiplayer camera follows a new native turn; manual focus/pan stays in effect for the rest of that turn. |
| Deck builder layout | Classic | Classic preserves the existing side-by-side editor. Simplified uses an upper browser, independent Mana identity toggles/exact identity and lower overlapping deck/land columns, with modal extra filters. |
| Window mode/resolution | Desktop Borderless | Uses the display's full desktop dimensions without a frame by default; explicit saved display choices remain supported. |

These controls work alongside existing render/UI scale, motion/particles, contrast/color palette, tooltips, local artwork and audio controls. Mana and set symbols retain their own supplied fonts. Settings open as a dedicated page outside gameplay and a popup above the table. **Apply and save** applies presentation preferences and persists them; game options explicitly apply to the next match.

Storage offers scoped explained Purge, separate Compact, a download-size/count scan, explicit download/pause/resume and clickable navbar progress. **Locations** browses independent saves/image-cache folders, estimates temporary space and prepares verified copies for the next launcher restart. Originals remain backups; this is a distinct confirmed operation from Apply. Details: [Storage](../service/STORAGE.md).

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
