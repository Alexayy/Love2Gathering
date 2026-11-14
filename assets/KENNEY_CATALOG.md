# Supplied Kenney asset catalog

Audited 2026-11-14. The 23 supplied pack directories contain 12,454 files: 8,927 PNGs and 297 audio files (54,032,968 source bytes). Every PNG header and every audio stream was inspected programmatically; source licenses were read. Twenty contact sheets, containing pack previews and evenly distributed real sprites, were visually inspected. This is a full file/format inventory with representative visual review, not a claim to have viewed all 8,927 PNGs individually.

The machine-readable [inventory](kenney/inventory.json) records every dimension histogram, mode, extension count, license hash, audio file codec/rate/channels/duration and the reviewed representative source paths/alpha ranges. Original supplied distributions remain in place. Curated runtime files are byte-for-byte copies, with exact source paths in [provenance](kenney/runtime/provenance.json) and licenses beside them. No ZIP archives were present directly under `assets/kenney/` during this audit.

| Supplied pack | Files | PNGs | OGG | Image sizes and review decision |
| --- | ---: | ---: | ---: | --- |
| `kenney_background-elements` | 135 | 125 | 0 | 26 x 29–2048 x 2048; 56 distinct sizes. Colored landscape/castle/tree sprites; preserved as source references. They would compete with card illustration and the space table, so no runtime selection. |
| `kenney_background-elements-remastered` | 171 | 162 | 0 | 20 x 43–2168 x 2142; 113 distinct sizes. Layered 1024 px landscape presets and default/retina foliage. Preserved; no forced scenery behind cards. |
| `kenney_board-game-icons` | 774 | 513 | 0 | 64 x 64, 128 x 128, 918 x 515, 1344 x 832, 2688 x 1664. Flat transparent card/book/pawn/dice masks. Selected collection, deck actions, expandable books, table and exact-count dice. |
| `kenney_board-game-info` | 868 | 577 | 0 | 128 x 128, 256 x 256, 918 x 515. Precomposed age/player/time pictograms and labels in default/fantasy/space styles. Preserved; native seat limits and live timings cannot be replaced by baked labels. |
| `kenney_boardgame-pack` | 583 | 539 | 12 | 64 x 38–1216 x 192; 12 distinct sizes. Colored physical pieces, chips, standard playing cards and bonus dice audio. Preserved; ordinary poker card faces do not represent Magic cards. |
| `kenney_casino-audio` | 58 | 0 | 55 | Audio only. Short card slide/shuffle/pack and chip/dice Foley plus a 35 s preview mix. Selected card-slide and shuffle only, not preview music or gambling chips. |
| `kenney_cursor-pack` | 1096 | 729 | 0 | 32 x 32, 64 x 64, 918 x 515. Basic/outline pointers and hands at 32/64 px. Selected basic arrow and pointing hand; accurate hotspots, native I-beam and resize cursors remain. |
| `kenney_cursor-pixel-pack` | 227 | 223 | 0 | 16 x 16, 320 x 176, 339 x 186, 918 x 515. 16 px pixel cursor tiles and sheets; some tiles deliberately empty. Preserved; current interface is not pixel-art and has high-DPI controls. |
| `kenney_development-essentials` | 22 | 19 | 0 | 1 x 1, 4 x 4, 16 x 16, 256 x 256, 918 x 515. 1 px/4 px fills, 256 px noise/gradient/UV diagnostics. Preserved; useful development references, no unnecessary debug texture in product. |
| `kenney_emotes-pack` | 534 | 513 | 0 | 16 x 16–918 x 515; 7 distinct sizes. Pixel and vector speech/reaction bubbles. Preserved; native prompt instructions remain readable text, with no invented player emotes. |
| `kenney_fantasy-ui-borders` | 286 | 282 | 0 | 48 x 48–918 x 515; 11 distinct sizes. Transparent geometric frames/insets/dividers. Existing curated nine-slice frame, inset and divider remain runtime skin. |
| `kenney_game-icons` | 434 | 425 | 0 | 50 x 50, 100 x 100, 918 x 515, 1024 x 512, 1024 x 2048. Neutral white/black interface masks. Selected real profile/avatar, gear, save, delete, add/remove and zoom controls. |
| `kenney_googly-eyes` | 12 | 9 | 0 | 325 x 330, 326 x 330, 918 x 515, 1024 x 1024. Large layered eyes and five finished eyes. Preserved; unrelated to the game and intentionally not placed on cards. |
| `kenney_impact-sounds` | 133 | 0 | 130 | Audio only. Generic/material/punch/footstep clips. Selected quiet soft impact; footsteps and weapon impacts are not forced into interface actions. |
| `kenney_input-prompts_1.5` | 4667 | 3056 | 0 | 64 x 64–2176 x 2048; 26 distinct sizes. Keyboard/mouse/controller/touch instructions in default/double resolution, some colored accents. Selected right-button and scroll-wheel instructions for actual board controls; controller-specific prompts are not shown without controller support. |
| `kenney_interface-sounds` | 103 | 0 | 100 | Audio only. Short mono/stereo UI clicks, confirmations, backs, plucks and transitions. Selected click, confirm, cancel and resolution pluck. |
| `kenney_light-masks-1.0` | 460 | 457 | 0 | 512 x 512, 918 x 515. Default opaque grayscale, inverted and genuinely transparent 512 px light masks. Preserved; existing bounded transparent particle glow remains sufficient. |
| `kenney_pattern-pack` | 256 | 171 | 0 | 256 x 256, 512 x 512, 918 x 515, 3072 x 1792, 6144 x 3584. 256/512 px high-contrast geometric repeat textures. Preserved for future explicit playmat choices; no noisy pattern behind rules or card text. |
| `kenney_pattern-pack(1)` | 256 | 171 | 0 | 256 x 256, 512 x 512, 918 x 515, 3072 x 1792, 6144 x 3584. Second supplied Pattern Pack directory. Preserved, not deleted or used as an extra runtime duplicate. |
| `kenney_pattern-pack-pixel` | 137 | 133 | 0 | 16 x 16, 128 x 128, 135 x 135, 918 x 515. 16 px color/grayscale pattern tiles and 128 px sheet. Preserved; pixel patterns conflict with the present smooth interface. |
| `kenney_skyboxes-space` | 12 | 8 | 0 | 918 x 515, 4096 x 2048. Five full 4096×2048 panoramas (not cubemap crosses), source preview and two samples. All five selected as lazy, cropped and dimmable backgrounds. |
| `kenney_splat-pack` | 113 | 73 | 0 | 256 x 256, 512 x 512, 918 x 515. White transparent splatter silhouettes at 256/512 px plus sheet. Preserved; no persistent ink splats over important cards. |
| `kenney_ui-pack-space-expansion` | 1117 | 742 | 0 | 8 x 16–918 x 515; 33 distinct sizes. Neutral/colored glass/screw-corner controls, bars, shadows and focus reticles. Existing neutral nine-slice panel/button/square and reticle remain runtime skin. |

All 23 pack notices identify Kenney assets under CC0 1.0; the original notices are preserved. Runtime copies keep eight relevant license notices under `kenney/runtime/licenses/`, and the pre-existing theme/particle notices remain. This does not extend to Magic card art, Mana/Keyrune font terms, the user-supplied Beleren font, or other unrelated files.

## Audio details

All 297 audio files probe as Vorbis in OGG containers. Boardgame bonus: 12 stereo 44.1 kHz clips, 0.230–1.481 s. Casino: 54 stereo 44.1 kHz clips plus one 48 kHz preview, 0.172–35.107 s. Impact: 130 stereo 44.1 kHz clips, 0.106–1.741 s. Interface: 77 mono and 23 stereo 44.1 kHz clips, 0.010–1.944 s. These are stream measurements, not a claim to have listened to all clips. The seven selected runtime effects are also decoded by LÖVE in the presentation test; playback is capped at 12 voices. Do not play a die-roll sound merely because a static counter is drawn.

## Display font provenance

`fonts/Beleren2016-Bold.ttf` was already supplied by the user (137,124 bytes). Its SFNT metadata identifies Beleren2016, version 1.200, Delve Fonts / Delve Withrington, and Copyright(c)2014–2016 Wizards of the Coast, a Hasbro Subsidiary, all rights reserved. No separate distribution license or font name-table license entry accompanied it. It is retained in place, not relabeled CC0/OFL. It is the default display face for headings, deck names and card details; readable body text retains the existing application-font setting. Users can select Application font for titles too. Missing/unsupported title glyphs fall back to bundled DejaVu.

## Runtime use and resource bounds

- Runtime icons use source alpha bounds in a draw quad; source pixels are unchanged. Masks preserve aspect ratio and are tinted mint/purple/neutral by the caller.
- Dice 1–6 show actual pips. Other exact values, including 7/13/127, are printed on the blank die; no modulo or rule inference. Text is an available alternative.
- Space images use centered aspect-cover cropping and a real brightness multiplier. The five source panoramas decode to roughly 32 MiB each; at most two are retained on the GPU. Off preserves the prior flat background.
- Kenney cursors use their visible arrow/finger hotspots. Native text and resize feedback remains; unsupported custom cursors fall back safely.
- Existing fantasy/space nine-slice controls keep their geometry, clipping and dark mint/purple identity. Body labels on buttons remain in the readable application font.
- Magic ability icons come from verified Mana 1.17.1 CSS mappings, not guessed Unicode or unrelated board-game symbols. Six existing plus ten newly verified keyword glyphs are covered by actual font/render checks.

## Verification

`tests/assets_presentation.sh`: 82 actual LÖVE checks, including pixels, supplied fonts/UTF-8, icons, 16 keyword glyphs, panorama crop/dimming/cache bounds, exact counters, all seven sound decoders, native/custom cursors, cached card/profile/Gallery texture filtering, one-per-activation/muted UI audio and real Slab settings input/persistence dispatch. It uses temporary assets and no game/service/user saves. Captures: `/tmp/love2gathering-assets-presentation.png` and `/tmp/love2gathering-assets-settings.png`; both visually inspected. Report: `tests/assets-presentation-report.json`.
