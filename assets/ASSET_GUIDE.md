# Asset analysis and runtime selection

The supplied distributions were inspected before integration: image contact sheets on the client's dark background, actual PNG dimensions and decoded alpha, font glyph rendering and CSS code points, and OGG codec/duration/channel metadata. No new artwork was generated. The runtime selection is approximately **840 KB**, excluding the existing interface fonts, the card bulk file and the preserved music collection.

## Fonts and icon

- `keyrune/mana.ttf`: the supplied Mana 1.17.1 font. Runtime mappings are recorded in `keyrune/glyphs.lua`, extracted from its original CSS rather than guessed from letter codes. W/U/B/R/G are U+E600–U+E604; colorless is **U+E904**, X is U+E615, tap U+E61A, untap U+E61B, snow U+E619 and Phyrexian U+E618. Numerals 0–20 use the font's actual glyphs. The source CSS contains 462 mapped symbols; runtime mana, zone and card-type mappings are retained in the client.
- `keyrune/keyrune.ttf`: supplied Keyrune font. **Theros Beyond Death is THB, U+E961**; THS is the original Theros set and is a different symbol.
- `icons/thb.png`: THB rendered from the Keyrune font, upright and unmirrored, centered on a transparent **256×256 RGBA** image. Its visible alpha bounds are `(26,12)`–`(232,243)`. The gold color works on the dark table; there is no baked-in square background.
- Font notices are retained in `keyrune/LICENSE-mana.md`, `keyrune/LICENSE-keyrune.md` and the complete SIL OFL 1.1 text in `keyrune/OFL.txt`. `icons/README.txt` records the derivation. The client uses the prepared fonts; the unused SVG/code distributions are archived separately.

## Kenney UI and particles

The supplied UI Pack 2.0 contains multiple color families, default/double-resolution variants, beveled/gloss/gradient buttons and directional arrows. The contact sheet showed that the **Grey/default square line** asset fits a dark client without a heavy glossy treatment. The selected original is retained as `kenney/ui/panel.png`:

- 64×64 indexed PNG with palette transparency; decoded alpha spans 0–255 and corner alpha is zero.
- Nine slices use an **8-pixel border**. Corners and edge thickness stay fixed while only the middle portions stretch.
- The neutral image is tinted at draw time for dark or accent panels. It is not rotated or used as a stretched single image.
- The supplied Kenney CC0 notice remains at `kenney/ui/LICENSE.txt`.

The official [Kenney Particle Pack](https://kenney.nl/assets/particle-pack) was downloaded with `curl` from its published download link, then all 80 transparent tiles were rendered into a contact sheet before selection. The download endpoint requires a browser User-Agent and its asset-page Referer. The retained files are:

| File | Dimensions | Decoded alpha | Visual role |
| --- | --- | --- | --- |
| `kenney/particles/circle_05.png` | 512×512 | 0–236 | Soft radial glow; gentle casts and resolution |
| `kenney/particles/star_04.png` | 512×512 | 0–223 | Small four-point sparkle among the glows |

Both are indexed PNGs with real palette transparency and zero-alpha corners, not white or black background images. Their shapes are centered. The glow has no directional orientation; the star can rotate naturally. Runtime particles use a short outward velocity and fade, a limited particle count and additive blending; no smoke/fire/explosion sheets are needed for this table. The pack's CC0 notice is retained at `kenney/particles/LICENSE.txt`.

## Sound and music

Three supplied Kenney effects are retained as `kenney/sounds/click.ogg`, `cast.ogg` and `resolve.ogg`, with the UI pack's CC0 license at `kenney/ui/LICENSE.txt`. They decode as stereo Vorbis at 44.1 kHz, with durations approximately 0.367, 0.094 and 0.227 seconds respectively. Sound sources are cached, cloned for playback and limited to 12 simultaneous voices. Disabled or unavailable audio is handled safely.

The original **82 MB music-loop collection remains intact**, including its CC0 license and attribution to Abstraction / Tallbeard Studios. `Assets.ambient` suggests `Week 19 - Dark Portents SHROUDED FUTURE.ogg` as an optional loop: 33.424 seconds, stereo Vorbis at 44.1 kHz. This selection is exposed to the application settings; creating, looping and adjusting the streaming music source belongs to the main application. The original OGG contains a metadata image stream as well as its audio; it is not a video track used by the client.

## Runtime API

`local assets = require('app.assets').new()` provides:

| Method | Behavior |
| --- | --- |
| `assets:mana(symbol,x,y,size,color)` | Draw one symbol, a hybrid/Phyrexian symbol, or a complete `{2}{U}{R}` cost; returns width. Supports `T`/`Q` aliases for tap/untap. |
| `assets:panel(x,y,w,h,style)` | Nine-slice panel; style is `dark`, `accent` or an RGBA tint table. |
| `assets:particle(kind,x,y,count)` | Emit a short `cast`, `resolve`, `impact` or `click` effect. |
| `assets:update(dt)` | Advance particles and retire completed sound voices. |
| `assets:drawParticles()` | Draw active effects while preserving graphics state. |
| `assets:playSound(kind,volume)` | Play a cached short effect; zero volume safely skips playback. |
| `assets:icon()` | Return `assets/icons/thb.png` for `love.window.setIcon`. |
| `assets:iconSymbol(name,x,y,size,tint)` | Draw an actual Mana zone/type glyph, or a native vector for a generic interface action. |
| `assets:iconImage(name,size,tint)` | Cached native-resolution icon drawable for Slab images. |
| `assets:buttonImage(name,label,w,h,opts)` | Cached icon-and-label image that keeps the icon square inside a wider Slab button. |

The application calls `update` once per frame, draws particles over the table and controls music/sound preferences. These visual and audio effects never change rules or resolve game actions.

## Cleanup and verification

Unused web distributions, source SVG collections, alternate font formats, UI colors/sizes, preview sheets and unused UI sounds were moved intact outside the project to:

`/tmp/love2gathering-unused-distributions-20261112/`

The original `mana-1.17.1`, `keyrune-master` and `kenney_ui-pack` directories are available there for restoration. The downloaded complete particle ZIP and extracted contact-sheet source remain under `/tmp/love2gathering-kenney-particles*`. The card bulk data, rules PDF, existing interface fonts and all music files were preserved.

Run `tests/assets-input.sh` to execute **33 actual LÖVE/Slab checks**: fast Ctrl+A, selection replacement, UTF-8 caret boundaries, Ctrl+Left/Right and Ctrl+Shift selection, Ctrl+Backspace/Delete, clipboard copy/cut/paste including middle-of-text caret position, Home/End, held Shift navigation, mouse caret placement/drag/highlight, real font glyph coverage, panel/particle/icon metadata and OGG decoding. The test restores the clipboard it found on startup.

Visually inspected captures: `/tmp/love2gathering-assets-input.png` (visible caret and selection, mana symbols, hybrid costs, THB icon and dark nine-slice panels) and `/tmp/love2gathering-assets-particles.png` (transparent particle rendering). Contact sheets are `/tmp/love2gathering-ui-contact.png`, `/tmp/love2gathering-font-contact.png` and `/tmp/love2gathering-particle-contact.png`.

## Inline symbols and icon rendering

`app/richtext.lua` draws mana tokens inside ordinary card rules and costs, including hybrids, Phyrexian hybrids, tap/untap and explicit newlines. Word wrapping and long-word splitting preserve UTF-8. Its Slab adapter caches transparent canvases at native interface resolution, independently of table render scale. The bounded LRU cache uses a display-context generation so resolution changes do not reuse canvases cleared by the graphics driver. `Assets.invalidateRasterCaches()` also invalidates them after a same-size native display-mode reset.

Zone and card-type icons use their verified font glyphs: library U+E9CB, hand U+E9CA, graveyard U+E9CC, exile U+E9CD and commander U+E9C6. Generic controls such as settings, save, home, replay, play and pause use native vector geometry rather than an unrelated Magic symbol.

Run `tests/richtext.sh` for **19 actual LÖVE checks** covering token handling, wrapping, UTF-8, native-scale rasterization, alpha correctness, cache limits, icon mappings, display-size changes and same-size context invalidation. Visually inspected captures are `/tmp/love2gathering-richtext-native.png` and `/tmp/love2gathering-richtext-scaled.png`. The builder uses these icons for color/type filters, sections and actions, with inline mana in costs and preview rules.
