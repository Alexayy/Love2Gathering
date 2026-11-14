# Asset analysis and runtime selection

The supplied distributions were inspected before integration: image contact sheets on the client's dark background, actual PNG dimensions and decoded alpha, font glyph rendering and CSS code points, and OGG codec/duration/channel metadata. No new artwork was generated. The current curated selection includes about **7.6 MiB** of new runtime icons, cursors, short sounds and five skybox panoramas, plus the earlier approximately 840 KB UI/particle/icon selection. Full supplied pack directories remain intact. The [complete Kenney catalog](KENNEY_CATALOG.md) records the current inventory and selection rationale.

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

Zone and card-type icons use their verified font glyphs: library U+E9CB, hand U+E9CA, graveyard U+E9CC, exile U+E9CD and commander U+E9C6. Generic controls use the reviewed Kenney masks where supplied (including settings, save and profile); home, replay and remaining controls retain native interface geometry. Magic zone symbols retain their real Mana mappings.

Run `tests/richtext.sh` for **19 actual LÖVE checks** covering token handling, wrapping, UTF-8, native-scale rasterization, alpha correctness, cache limits, icon mappings, display-size changes and same-size context invalidation. Visually inspected captures are `/tmp/love2gathering-richtext-native.png` and `/tmp/love2gathering-richtext-scaled.png`. The builder uses these icons for color/type filters, sections and actions, with inline mana in costs and preview rules.

## Multiplayer navigation and installed fonts

Multiplayer continues the existing icon treatment: `commander`, `library`, `hand`, `graveyard` and `exile` use their supplied Mana glyphs. Generic controls `player`, `bot`, `players`, `life`, `focus`, `pan` and `overview` use the same small native-vector style as the existing settings and replay controls. Player badges, a four-way pan indicator and a grid overview communicate board navigation without adding unrelated card symbols. They are available through `iconSymbol`, `iconImage` and `buttonImage`; no additional image distribution or font license is required.

The retained bitmap assets remain the transparent THB icon, Kenney nine-slice panel and two particles. The sound effects and full licensed music bundle are preserved. The archived distribution directories described above are historical temporary locations; they are not required at runtime and may no longer exist on another checkout.

Accessibility settings offer an **Application font** choice on systems with Fontconfig. `app/fonts.lua` caches at most 256 installed Latin-capable TTF/OTF families, loads only a selected discovered font file with a 24 MB resource bound, and preserves bundled DejaVu as a glyph fallback. Preferences store a family name rather than an absolute path. A missing or unreadable saved font falls back to bundled DejaVu with a visible message. Discovery failure leaves the built-in font available. Apply and save updates table text, Slab controls, rich text and button labels; the supplied Mana glyph font remains independent.

`tests/fonts.sh` runs **19 actual LÖVE checks**, including visible multiplayer icons, native font loading, unsupported-family fallback, an actual font dropdown selection and Apply/save dispatch. SQLite tests separately verify font-family persistence and malformed input rejection. The font and icon capture is `/tmp/love2gathering-fonts-icons.png`.

## Supplied fantasy and space theme

The newly supplied **Fantasy UI Borders 1.0** and **UI Pack: Sci-fi 2.0** (the space-expansion folder) were inspected as contact sheets on the dark application background before selection. The original extracted distributions and ZIPs remain intact. Runtime uses seven unmodified PNGs in `kenney/theme/`, alongside both original CC0 notices and exact source paths in its README:

| Runtime file | Original shape and dimensions | Slicing and role |
| --- | --- | --- |
| `fantasy-frame.png` | Transparent ornamental corner frame, 48×48 | Fourteen-pixel source borders, eleven-pixel drawn borders; main panels and player fields |
| `fantasy-inset.png` | Transparent doubled inset frame, 48×48 | Fourteen-pixel source borders; small adjustable drawn borders for text inputs |
| `fantasy-divider.png` | Right-capped ornamental rule, 96×18 | Right cap retained; straight segment stretches horizontally |
| `space-panel.png` | Neutral glass panel, 64×64 | Eight-pixel source/drawn borders; windows and dark surfaces |
| `space-button.png` | Neutral rectangular screw-corner button, 192×64 | Twelve-pixel source borders; drawn borders fit the unchanged control height |
| `space-square.png` | Matching square control, 64×64 | Twelve-pixel source borders; compact toolbar and checkbox surfaces |
| `space-focus.png` | Upright targeting reticle, 30×30 | Aspect-preserving focus/target icon |

Every selected image has real transparency with alpha spanning 0–255. Fantasy frame centers remain transparent; space surfaces retain their source highlights and screws. Sprites are never mirrored or rotated. Nine-slice stretching preserves all corners and caps. Runtime tint keeps the dark background, mint human/action accents and purple opponent accents; explicit panel tint tables and alpha remain supported.

`app/theme.lua` draws these sprites without changing layout or input bounds. `Assets:panel` uses the glass and fantasy frame; `control`, `frame` and `divider` expose the corresponding presentations. `Theme.install(Slab,assets)` registers an optional Slab draw-command skin. It styles existing window, title, button, combo and input rectangles in their existing draw batches, so native clipping, transforms, scrolling and hit geometry stay together. Without installation Slab retains its original rendering; missing curated images fall back to the earlier panel assets.

The Gallery uses the existing icon API with `gallery`, `artist`, `calendar` and `external` interface vectors. Magic zones and costs continue to use the supplied Mana font independently of application font choices.

`tests/theme.sh` passes **16 actual LÖVE checks**, including image alpha and nine slices, tint/alpha preservation, graphics-state restoration, real button/combo dispatch, both themed packs and nested control visibility at UI scale 1.25. The inspected capture is `/tmp/love2gathering-theme.png`; source contact sheets are `/tmp/love2gathering-fantasy-new-contact.png` and `/tmp/love2gathering-space-new-contact.png`.

## Optional offline card-image library

`scripts/download-card-images.py` streams the supplied Scryfall JSONL metadata rather than issuing a search for each card. It retains every printing and image face in the chosen source, with separate **full-cards/** and **art-crops/** JPEG mirrors. The same images are committed to the configured SQL image cache under the application's printing/face/kind keys. Existing SQLite images win over older mirrors; restarting repairs missing mirrors without repeating downloads. Interrupted or incomplete JPEGs are retried within bounds and are never accepted as complete mirror files.

First inspect a bounded selection without writing or downloading:

```sh
python3 scripts/download-card-images.py --metadata /path/to/all-cards.jsonl --dry-run --limit 20
```

Download from that local source using the configured user-data directory and an explicit mirror destination:

```sh
python3 scripts/download-card-images.py --metadata /path/to/all-cards.jsonl --output /path/to/image-library
```

`--limit 2` provides a small two-image trial. `--full-size large` chooses 672×936 full-card JPEGs instead of the default 488×680 normal images; art crops keep their supplied dimensions. `--data-dir` overrides `LOVE2GATHERING_DATA_DIR` and the normal user-data location. A full printing/language library can require many GB, with the requested mirrors storing an additional copy of the SQLite image content.

When no source exists, metadata downloading is an explicit operation, never a startup side effect:

```sh
python3 scripts/download-card-images.py --bootstrap-metadata default_cards --metadata /new/path/cards.jsonl --limit 2
```

Use `all_cards` for every language, or `default_cards` for Scryfall's default printing collection. Bootstrap downloads the complete chosen metadata file even when image work is limited; it streams compressed JSONL into a new plain JSONL destination usable by `LOVE2GATHERING_CATALOG_SOURCE`. It refuses to overwrite an existing source. Current metadata feeds and image keys follow [Scryfall's bulk data](https://scryfall.com/docs/api/bulk-data) and [imagery documentation](https://scryfall.com/docs/api/images).

Requests use HTTPS, an identifying User-Agent and Accept headers, default 0.15-second pacing, and bounded transient retries. A repeated HTTP 429 stops retrying that request. This follows [Scryfall's published access guidance](https://scryfall.com/docs/faqs/i-m-having-trouble-accessing-the-scryfall-api-or-i-m-blocked-17); no recurring per-card API searches are used.

Eleven isolated backend tests verify separate printings/faces, shared scans for split/adventure faces, source streaming, gzip and older array metadata, atomic bootstrap, durable resume, mirror repair/import, interruption/retry, dry-run/limits and unsafe-input rejection. A live smoke downloaded one printing's normal image (488×680) and art crop (626×457): 135,732 bytes total. A second run reused both SQLite images with zero downloads. The smoke used temporary storage and did not download the full bulk metadata collection.

Runtime artwork is now **local-only by default**. Cache identity includes printing, image face and kind; `normal` can reuse a cached larger scan, while `art_crop` remains separate. Runtime same-card aliases can reuse another cached printing; exact Gallery requests retain the actual printing's credits. Token pictures use catalog token identities and per-deck preferences. Missing scans remain a card-rendered placeholder until the downloader supplies them or the user explicitly enables missing-image downloads. See [the library guide](../service/LIBRARY.md).

Board overlays continue using the curated Kenney focus reticle, impact/cast/resolve particles and supplied fonts/Mana symbols. Their coordinates come from visible native card/player geometry. Damage and combat movements follow native event IDs; hidden or missing source information does not create an effect at a fabricated screen location. No additional asset distribution was introduced for these overlays.

## Supplied-pack inventory and applied presentation

The [Kenney catalog](KENNEY_CATALOG.md) preserves the original 23-pack inventory and the later complete PNG review: 8,978 PNG files, 7,688 unique binaries and 29 visually reviewed contact sheets. SVG variants and audio listening are not claimed exhaustive. Every selected runtime file has its exact source in `kenney/runtime/provenance.json` with copied CC0 notices. Original packs are untouched.

`Assets:titleFont(size,settings)` and the body font now use the user-supplied `fonts/Beleren2016-Bold.ttf` throughout the application. Legacy font settings remain readable, but the current presentation always selects Beleren. Missing files/glyphs use DejaVu fallbacks. `Fonts.textOffset` measures the supplied face's glyph bearings in a bounded cache so controls center visible ink rather than its unusually generous line box. The catalog records Beleren's actual proprietary copyright and absence of a bundled license; it is not represented as CC0 or OFL.

`Assets:background(w,h,settings)` centers and crops the selected full 4096×2048 panorama with aspect preserved; `skyboxBrightness` multiplies real image pixels. `skybox` accepts Galaxy/Nebula/Band/Dark/Day/Off. Only two decoded panoramas remain cached, and Off preserves the earlier flat scene. The renderer separately applies `playmatOpacity` to real profile artwork.

`Assets:counterBadge(value,x,y,size,style,tint)` shows actual pips for 1–6, then exact text on the blank die for any other value; `counterStyle='Text'` removes the die surface. These labels display native counters without adding game rules. `cursorStyle='Kenney'` is the default and applies reviewed pointer, hand, pan, drag and resize hotspots after Slab; text editing uses a smaller custom Kenney bracket cursor and unsupported cursor backends fall back safely. `keywordReminders` controls explanatory card-detail text. Presentation keys have matching backend validation and defaults.

`assets:setSettings(settings)` synchronizes custom panels and the Slab skin. `Assets.palette(settings)` resolves the five reviewed dark palettes and optional player/opponent colors; `panelOpacity` defaults to `.65` while readable controls and tooltip surfaces remain opaque. Runtime additions are the source pack's open/closed hands, four resize cursors and confirmed-block shield. Exact paths, bounds and CC0 provenance are in `kenney/runtime/provenance.json`; complete supplied packs remain untouched.

The new semantic icon names are `profile`, `avatar`, `settings`, `save`, `delete`, `add`, `remove`, `zoom-in`, `zoom-out`, `expand`, `collapse`, `starter`, `preconstructed`, `collection`, `collections`, `add-card`, `remove-card`, `shuffle`, `dice`, `dice-0` through `dice-6`, `playmat`, `tap-card`, `mouse-right` and `mouse-scroll`. Source images retain their alpha/orientation; draw quads trim transparent margins while preserving aspect ratio.

Additional verified Mana 1.17.1 mappings support defender, double strike, first strike, flash, indestructible, menace, reach, surveil, vigilance and ward, alongside the six earlier keywords. Code points come from the [official pinned CSS](https://raw.githubusercontent.com/andrewgioia/mana/v1.17.1/css/mana.css) and are tested against the actual bundled font. No unrelated board-game icon substitutes for a Magic keyword.

`Theme.install` now emits one quiet UI click per accepted button/checkbox/list selection, independent of hover/paint frames. It remains idempotent and observes the applied sound toggle/volume. `Assets:playSound` keeps its 12-voice bound and supplies reviewed click/cast/resolve/impact/confirm/cancel/shuffle clips. Native game-event sound triggers belong to the renderer; static dice never roll or make random sounds.

`tests/assets_presentation.sh` checks actual LÖVE fonts, pixels, audio decoders, custom/system cursors and Slab settings clicks using temporary assets and no service/user data. Its report and inspected captures are listed in the catalog. Existing fonts/theme/input checks remain separate regressions.


## Split cache, surfaces and startup preparation

Cached BLOBs live in `images.sqlite` when the cache is split; existing combined stores remain supported. JPEG folders are optional mirrors, never the only index of cached artwork. Settings → Storage → Locations prepares independent database/cache folders, verifies copies and requires a launcher restart. See [storage recovery and cleanup](../service/STORAGE.md). No bulk download runs during startup.

`runtime/enhancements.lua` adds the reviewed generic controls, a custom text cursor, dice Foley, four card backs, Space Expansion slider surfaces, development gradients/noise, hex pattern and light masks. `app/surfaces.lua` renders grayscale masks with luminance-to-alpha conversion, retains bounded texture/quad caches and restores graphics state. Do not draw these opaque grayscale source files as ordinary transparent PNGs. Slider handles preserve Slab input behavior; numeric text appears only during editing. Small custom cursors resolve through Slab's provider, preserving scaled hotspots and system fallback.

Beleren uses native-DPI rasterization in Standard quality and twice native DPI in High quality. Both keep logical text/caret geometry; they are independent of board render scale. The splash decodes only curated modules/resources and prepares real fonts/canvases while launcher build/services progress. Failures remain visible. Detailed GUI evidence is in `tests/presentation-refresh-ui-report.json`, `tests/startup-ui-report.json` and the separate real-launcher `tests/startup-main-report.json`.

Bot basic-land playmats use a bounded metadata pool of English basic printings explicitly marked `full_art:true` in the supplied snapshot. Regenerate it with `scripts/prepare-playmat-basics.py --source PATH`; this streams the snapshot without fetching images. Exact cached illustrations retain their printing identity. Missing illustrations stay as a faint supplied pattern; they do not cause network downloads.
