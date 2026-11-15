# Love: 2 Gathering

A LÖVE desktop client with Slab controls, a 2D Magic table and a fanned hand. **XMage runs the game**: legal actions, mana, combat, targets, stack resolution, triggers and the computer opponent. The client displays that state and sends your choices back to the engine.

**Settings → About** shows the build version, channel and revision, credits, source links and offline license notices. Project-authored code is [MIT licensed](LICENSE). Dependencies, card content and supplied assets retain their own terms; see [Credits](CREDITS.md) and [third-party notices and rights status](THIRD_PARTY_NOTICES.md). This is an independent, unofficial project. Contribution instructions are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Installers

Release builds include DEB, relocatable RPM, Flatpak, a Windows setup executable and a Linux installer with a folder picker. See [installation and build instructions](packaging/README.md) for custom locations such as `/mnt/Games/Love2Gathering`, menu shortcuts, dependencies and uninstall behavior. Saves and image caches remain separate from the application folder.

Pushes to `development` build the installers and publish a `DEV-<version>-<attempt>-<revision>` prerelease. Pushes to `master` publish a normal `v<version>` release. Both use [Releases](https://github.com/Alexayy/Love2Gathering/releases), with the exact version/revision embedded in About. Use `bash scripts/push-development.sh` after committing to check the outgoing XMage pin and push only the parent branch. The helper leaves the engine submodule untouched; [CI and publishing details](packaging/README.md#build-again) describe the checks and reports. Releases whose workflow files differ from the default branch may need the optional `RELEASE_TOKEN` secret; [token setup](packaging/README.md#build-again) explains the GitHub permission requirement.

## Start

XMage is a Git submodule pinned to the engine revision used by this client. Clone this repository with `git clone --recurse-submodules https://github.com/Alexayy/Love2Gathering.git`. For an existing clone, initialize it from the project root:

```sh
git submodule update --init --recursive
```

Install **Java 21, Python 3 and LÖVE 11.5** (Pillow enables small image variants and is included/declared by the installers), then run (the launcher can also use a development JDK already installed under `.tools/jdk-*/`):

```sh
./run.sh
```

The launcher starts the local card catalog, XMage, room-code gateway and the desktop window. The first build downloads Java dependencies; if Maven is unavailable, the script downloads a local copy using `curl` and `tar`. The supplied large `assets/all-cards*.jsonl` source is indexed locally into `service/data/catalog.sqlite`. Indexing progress appears in the client; set `LOVE2GATHERING_CATALOG_SOURCE` to select a particular snapshot.

The loading screen waits for your saved theme, colors, profile, decks and panel layout, applies the saved display settings, then prepares the icon graphics before opening the client. Its rotating circle and percentage show progress; reduced motion keeps the circle still. If saved data cannot be read, **Retry loading saved data** retries it instead of opening a default profile. Local artwork remains usable while a background image download runs.


Build and service logs are in `.runtime/engine-build.log`, `.runtime/engine.log`, `.runtime/catalog.log` and `.runtime/rooms.log`. The launcher reuses a catalog with **API 14 or newer** and matching database/cache/source, and starts a separate engine and gateway for each desktop instance, so opening another client preserves an existing match. It selects available local ports and stops only services it started.

The splash opens while the launcher checks dependencies, storage, local version, catalog, XMage build, bridge and gateway. It decodes the curated graphics/audio and prepares fonts before opening the client. Card illustrations stream from the local cache as needed. Failures remain visible with the relevant stage; missing metadata offers an explicit saved-library fallback. The version check reads the installed revision; it does not download an application update.

`./run.sh --services-only` keeps the services running in a terminal and prints the exact command for connecting a client. `love .` opens only the frontend; use the printed port settings when those services are on nondefault ports.

## Decks and builder

Decks has collapsible **My Decks**, **Starter** and **Preconstructed** groups. My Decks contains your saved lists. Starter preserves the [twenty included lists](decks/README.md), five each for **Modern, Standard, Pioneer and Commander**, including **Izzet Phoenix** and **Lotus Field Combo**. Constructed starters contain 60 main-deck and 15 sideboard cards; Commander starters contain one commander and 99 other cards.

Preconstructed contains **1,183 deck products** from the acquired MTGJSON snapshot, grouped by expansion, plus a separate **611-packet** category for Jumpstart and similar partial decks. Search by deck, expansion or face commander, use the format selector, and page through the results. Historical formats remain browsable even when they are unsupported by this client. Ordinary Secret Lair drops and other non-deck collections stay outside the deck browser; complete Secret Lair Commander decks remain included. **Calling All Angels** is a Commander product led by **Giada, Font of Hope**. [Source coverage and licenses](service/PRECONS.md) document the complete acquired provider index and its limits.

Square deck tiles fit the **whole illustration** into their image area without trimming it, with the deck name, face commander where supplied, card count and Mana color-identity symbols. Group and expansion headers fold away lists while you browse. The lobby uses the same card-based selection with a searchable tile popup. Its scrollbar stays visible and can be dragged; wheel scrolling moves about 100 logical pixels per step. Reopening or changing the search starts at the first group. Recent product pages and full lists are reused briefly, and offscreen tiles do not request artwork or build thumbnail graphics.

Edit, duplicate or delete your owned lists, or choose them for the lobby. Editing an original Starter or preconstructed list creates an independent copy in My Decks. Historical archives ask for a supported target format; if the list needs repairs, the builder opens the complete unsaved copy with named errors. Invalid copies do not enter My Decks until corrected and saved. Original quantities and source templates remain intact. Plane/scheme products keep those auxiliary zones in their archive; copying confirms that the constructed copy uses its main deck, sideboard and commanders.

Select a preview card as the deck's cover. The builder supports name/rules/type search, format/color/type/set filters, and name/color/set sorting. Double-click a search result or drag it into the list to add it; use `−` / `+` to change quantities. Choose the main deck, sideboard or commander zone before adding cards.

The **Set** control opens a separate grid in both builder layouts and the edition/artwork picker. Search by set name or code, page through matching sets, and choose a tile to filter. The active set is marked; **All sets** clears the filter and stays visible on every page. Close or Escape keeps the current filter and any staged artwork choice.

The navbar keeps the page actions beside the navigation: **Import**, **History** and **New deck** on Decks; the deck name and **Classic / Simplified** controls in Builder. Hover an icon for its label. Right-click the application name for **Border Toggle**, **Minimize** or **Exit**. Border Toggle switches between borderless fullscreen and a bordered, maximized window.

Choose **Classic** or **Simplified** in the navbar. Simplified places the card browser, search and Mana filters above the deck, with additional filters in a popup. The lower deck uses overlapping columns by mana value and a separate land section. Drag cards into that lower section to add them; double-click a deck card to remove one copy. Drag the divider above the lower deck up or down to give either section more height. The selected layout is saved; the split remains in place for the current client session.

Simplified's Mana buttons toggle independently. White + Black includes cards whose identity contains either selected color. **Exact identity** instead requires precisely the selected colors: White + Black + Green shows Abzan identity only. Colorless selects empty identity, and All clears the filter. Classic keeps its existing color selector.

Use the **edition/artwork** icon on a deck card or its preview to choose a printing of that card. The popup includes reprints, alternate treatments, basic lands and commanders, with set/search filters and an active selection. **Apply edition** changes every copy of that card in the chosen zone; **Default art** removes the override. Save the deck to retain it. Exact choices use their own cached image; a missing scan stays marked as missing.

Token artwork opens from the saved deck’s token control. Each related token has its own active-art tile and **Default**, **Manual**, **Random selected** or **Random all** mode. Random selected uses only outlined choices in its grid; Random all uses the matching token family’s complete catalog. Apply the popup choice, then **Save token artwork**.

Saving checks format legality, copy limits across the deck and sideboard, Commander color identity and eligible commanders/pairs. Basic lands and cards with printed copy-count exceptions are handled separately. Errors identify the cards that need changes. An otherwise valid unfinished list can be saved as an explicit **draft**; it must meet the format's full construction requirements before play. XMage performs final validation when the match starts.

The application accepts up to 250 copies per card entry as an input resource bound; the format's game-rule copy limits still apply.

Construction checks use the configured local metadata snapshot. Format changes are not fetched automatically. Historical product labels describe their release era; they do not certify current legality. Editable constructed formats are **Modern, Standard, Pioneer and Commander**, with native **Limited** rules reserved for drafts. The installed engine can reject a list even when the selected snapshot labels its cards legal.

## Lobby and table

Choose your deck and each bot's deck in the lobby; every deck uses the same format. Commander defaults to **4 players: you and three XMage MAD bots**. Choose **5 or 6 players** for four or five bots, or **2** for the existing duel. Each bot has its own deck selector; scroll the setup list to reach additional seats. Commander uses native Commander legality, **40 starting life and one free mulligan**. Games are single-game practice sessions; between-game sideboarding and tournament scoring are not included.

Multiplayer uses a **2×2 world-space battlefield** for four players, with a third row for five or six. It opens focused on your field at normal card size. The player buttons move the camera to that player's field. Hold the **right mouse button and drag** to pan across the table, or **scroll to zoom**. The four-square icon explicitly fits the whole table into an overview; choosing a player from that overview restores readable card scale. Terrain extends from the compact header to the bottom of the window. Recorded multiplayer games use the same camera in read-only playback.

Your hand rests as a compact fan along the bottom so the table remains visible. Moving onto it expands the fan and enlarges the hovered card; leaving it collapses the hand. A stationary right-click opens card details. Highlighted player buttons select an engine-offered target when a target prompt is active. Graveyard, exile and commander zones belong to each seat; the magnifying-glass control opens publicly revealed cards and cards the engine lets you look at. Opponent hands remain hidden.

Resting, expanded and hovered hand cards are 5% larger. Battlefield cards are about 10% larger, with adaptive duel spacing that preserves the land/creature row gaps and mana indicators. Multiplayer keeps the fixed hand and its existing camera controls.

By default the camera follows the next active player when the turn changes, while your hand stays fixed. Manual movement remains in effect until the next turn. Disable **Follow the active player** in Settings to keep manual focus across turns.

The table uses larger cards and controls, with configurable UI scale. Your hand fans across the bottom. Hover to inspect a card and right-click for its full view. Click a highlighted card or drag it onto the table to choose a legal action. Card highlights come from XMage's current playable actions, including costs, available mana, timing, priority and the land limit.

When an effect reveals the top of a library or lets you look at it, that library displays its entitled top card. Click the highlighted top card to play it when XMage offers the action; hover or right-click to inspect it. Courser of Kruphix permits lands from the top, while other cards can grant different permissions. The engine still enforces timing, payment and land limits. A private look remains private to its player, and ordinary libraries stay face down.

During a match the application name and main navigation header are hidden. The field fills the window. Small mana-source rows sit centered lower in your field; crowded rows move left and overlap within their bounds. The icon toolbar opens the lobby, settings, log, stack and recordings. Hover over an icon for its label.

The log and stack are floating windows: drag their title bars or resize their edges. Their placement is saved. The log marks your actions in mint and the opponent's in purple, with separate colors and icons for casting, combat, damage, triggers and other actions. The stack shows source-card images and rules text, with the next object to resolve labeled first.

Hover a stack image to inspect the full card. Target arrows connect stack objects to their projected targets; larger outlined combat arrows show attackers and gold lines show assigned blockers. Separate attackers retain distinct colors inside their controller's outline. XMage supplies legal blocking choices, including evasion and blocker-count restrictions. Invalid selections produce a short message. The player holding priority is outlined, including in the fixed multiplayer seat strip. The rope displays elapsed decision time; it does not impose an invented timeout or penalty.

Battlefield badges show current native power/toughness and counters independently of the printed scan. Equipment and Auras overlap behind their host; player Auras retain owner/controller information. Entitled cards linked in exile appear rotated beneath their source. Hover the host to inspect its attachments and linked cards. Damage, life changes and deaths have effects at their actual card/player positions. Combat lunges follow actual native damage events, preserving separate first-strike and regular damage; a phase label alone never generates a hit. Reduced motion and animation preferences suppress movement.

**Scry** and **surveil** use image rows: drag cards between **Top / Bottom** or **Top / Graveyard**, arrange each row and press **Confirm**. The leftmost Top card is drawn first. Look-at views remain available to inspect and close without answering the engine. Other card choices use images or highlighted legal board objects. **Cancel** is available only when XMage offers cancellation of an unfinished activation; it cannot undo a paid sacrifice or a resolved effect.

The log's saved **Verbose** checkbox includes trigger/resolution details. Compact card thumbnails and bounded text keep the existing panel dimensions; hover for the full entry. Scrolling the log does not zoom the table. After a practice game, choose **Rematch** or **Main menu**. A constructed room's host can rematch with the existing ready seats/decks after native completion; drafts retain their tournament round controls.

The opening-hand decision appears in the center with **Keep** and **Mulligan**, including the engine's resulting hand size. XMage asks for any required cards to put on the bottom of the library. When a mana source offers choices, its mana wheel shows the abilities or colors actually offered by the engine. Other prompts cover targets, modes, amounts, divided amounts and confirmations. Graveyard, exile and revealed-card views let you inspect relevant cards.

Use the compact action controls or **Space** to pass when the engine offers Pass / Done. Trigger ordering is automatic by default. Enable manual trigger ordering for a new match to drag simultaneous triggers left to right; **the leftmost resolves first**. Confirm the order to continue.

**Automatic priority** passes native priority windows when XMage reports no meaningful playable action; mana sources alone do not require an extra Pass click. Available spells, flash/instant responses, non-mana abilities and special actions stay interactive. The transport uses XMage's conservative playable calculation, so some targetless actions can still retain an extra prompt. Targets, costs, mana payment, combat decisions, mulligans and other choices always require their actual answers.

The phase strip now contains **real stops**. Each phase has a human icon for your turn and a bot icon for opponents' turns. Click an icon to toggle that stop; gold means enabled. A stop holds once at that step even if your hand has no legal reaction, allowing a bluff. A gold **Stopped at…** banner appears only when the engine confirms that priority is held there. Choose **End step** to act before an opponent finishes their turn. Old explicit WAIT selections migrate to real stops; the old SKIP placeholders are not executed.

**End Turn** yields the current and subsequent ordinary priority in that turn. A new stack object, new turn, selected stop or required choice cancels that yield. Normal automatic priority then continues: it offers legal reactions and passes empty windows. **Cancel End Turn** stops the yield, and the play/pause icon beside the toolbar switches between automatic priority and **full control**. Stop/full-control preferences are saved. These controls are disabled during replay and while a replaced priority prompt is awaiting engine confirmation.

The Combat stop menu distinguishes beginning of combat, after attackers, **Before damage** (after confirmed blockers), first-strike damage, regular damage and end of combat. Selecting a blocker is provisional until **Done** confirms the declaration. A confirmed blocked attacker remains marked **Blocked** if its blocker is later sacrificed. Current native keywords appear on the card, with granted abilities in gold and in card details. For example, Goreclaw can grant trample until end of turn; sacrificing an already confirmed blocker then permits trample damage. [Combat timing and native verification](docs/COMBAT_TIMING.md) explains these states.

The larger **Before damage** control shows the acknowledged opponent-turn stop as **ON/OFF**, and uses a separate amber state while waiting for confirmation. It toggles the existing native after-blockers stop. **Concede match** ends the whole local bot practice after XMage records your loss. In rooms, conceding removes only your seat and the remaining players continue.

## Private multiplayer and drafts

Open **Rooms**, enter your name, choose a format and seat count, and create a private room. Share **Copy code** with friends; they paste that single code into **Join room**. Joining uses the code exclusively; there is no public room browser or separate address field. Each human chooses their own saved deck and presses **Ready**; the host can fill empty seats with XMage bots and start when everyone is ready. Modern/Standard/Pioneer rooms support two players; Commander rooms support **2–10**, the installed engine's native capacity. Bot seats in a constructed room use the host's deck.

For a draft, choose **Draft** before creating the room:

- **Booster draft**: select the set for each of the three packs, including mixed-set drafts.
- **Random booster draft**: leave the eligible set list empty for all supported booster sets, or search and add the sets you want in the pool. XMage randomly chooses the packs from that pool. These choices stay independent of Traditional draft's three pack slots.
- **Cube draft**: choose an installed native cube, including Modern, Legacy, Vintage, Pauper and Peasant card pools and historical cube versions.

All three procedures support **4–16 seats**, humans and/or native bots. Choose **Swiss** or **single elimination**, plus the native pick clock. Each player sees only their own current pack and picks. Pick a card to pass the pack; XMage handles passing, deadlines and automatic timeout picks. At the end, select cards for your main deck, add basic lands and submit. Unselected picks become the sideboard; native **Limited** rules require at least 40 main-deck cards. The host starts the round after every deck is accepted.

XMage generates pairings and standings; completed native game results award points or eliminate players. The host advances after all matches finish. A bye does not start a game. A drawn elimination game repeats the same pairing. These rounds use **one game per pairing**; between-game sideboarding and best-of-three are not implemented. Deck rules are Limited; different card pools come from set/cube selection. This engine revision does not expose Commander Draft.

Temporary connection loss retains your seat; **Reconnect to your seat** reuses the current connection. Deliberately leaving a draft gives that seat to native automatic picks/deck building and bots for subsequent rounds. Leaving a running match concedes only your own seat. Closing the host's room ends that room for everyone. A server restart ends its live rooms; invitation codes are not resumable saved games. Only the designated host perspective is recorded in the hosting server's catalog, keeping other humans' private hands out of the shared recording browser.

On a LAN, the host's gateway advertises its local address automatically; the host's computer must remain running and reachable. Internet play requires a reachable server address; this build does not supply a public hosting service or NAT relay. Run the included host without a desktop window behind your HTTPS reverse proxy:

```sh
scripts/run-room-server.sh --port 17380 --bind 127.0.0.1 --public-url https://rooms.example.com
```

Start desktops that should create rooms on that server with:

```sh
LOVE2GATHERING_ROOM_SERVER_URL=https://rooms.example.com ./run.sh
```

Guests still join with the invitation code alone; it includes the server location. `LOVE2GATHERING_ROOM_PUBLIC_URL` configures the advertised address for a desktop that hosts rooms itself. The server needs Java 21 and Python 3; only the gateway is exposed to the network, while XMage and the catalog remain on loopback. See [room hosting and protocol](service/ROOMS.md) for setup and verification limits.

## Settings and artwork

Hover help appears above the interface while surrounding controls keep their positions, including in the Settings popup during a match.

Settings open as a full page outside gameplay and as a popup above a running match. They cover display mode/resolution, VSync, antialiasing, render scale, texture filtering, frame limit and UI scale; animations/particles; music, sound effects and volume; and accessibility options such as reduced motion, contrast, color-friendly palettes and tooltips. Use **Apply and save** to apply and persist changes. Trigger-order and automatic pool-payment settings apply when starting a match. New installations use desktop-size **borderless fullscreen**.

The supplied **Beleren** font is used throughout the client, lobby and table. Unsupported glyphs or an unavailable font file fall back to bundled DejaVu. Mana and set symbols retain their supplied fonts. Text controls center the visible glyphs and retain padding for input, selection and caret handling.

Presentation offers **Midnight, Amethyst, Ocean, Ember and Obsidian** palettes, with editable player/opponent accents. Panel opacity defaults to **65%** and is adjustable independently of the playmat and skybox. Smaller, adjustable Kenney pointers cover clickable, dragging, panning, resizing and text-editing states; unsupported cursor backends retain a native fallback.

Presentation offers five supplied Kenney **space backgrounds**, **Off**, background brightness and playmat opacity. Backgrounds and playmats fill their areas with aspect-preserving cropping. **Counter display → Dice / Text** keeps the exact native value and counter name: dice 1–6 use pips, larger values remain exact numbers. **Explain keywords** adds short reminders for recognized abilities in card details. Accessibility offers **Pointer style → System / Kenney** and pointer size. Graphics offers Standard/High font raster quality and six card backs: four Kenney styles plus the supplied Classic Magic and Mystic Eye images, displayed with their original colors and proportions. Kenney slider tracks/handles support dragging and double-click numeric entry. The Audio page controls the selected Kenney interface/card/shuffle/impact/dice sounds, music and volumes.

Practice offers a chosen first player or animated **2d6** by default. Room games always use the server's dice result, rerolling tied highest scores. A resolved commander or spell with native mana value greater than five gives the terrain and individual cards a brief, eased shake; paid X comes from XMage. Motion/intensity settings control it. Target/attack lines have separate colors with their owner's outline. Bots choose a commander illustration or an in-identity full-art basic-land playmat, using exact cached art when available.

Automatic mana payment spends mana already in your pool. This XMage revision has no whole-board automatic land tapper; activate the engine-offered mana sources when needed. Card details, rules and costs render inline Mana symbols, including hybrid costs and tap symbols. **Cache only** is enabled by default for browsing. Explicitly selecting or previewing a Builder card, or clicking an edition candidate, downloads that exact missing image with priority. Enable **Download as needed** for other displayed images. The supplied Mana/Keyrune glyphs, Kenney effects/UI/sounds and music are described with their licenses in [the asset guide](assets/ASSET_GUIDE.md).

The interface uses the supplied **Kenney Fantasy UI Borders** and **Space Expansion** assets for frames, surfaces, buttons, inputs and sliders, with curated icons, gradients, noise, light masks, patterns, panoramas, cursors and sounds from the other supplied packs. Original packs and licenses are preserved. The [Kenney audit](assets/KENNEY_CATALOG.md) records the full PNG contact-sheet review and runtime choices. [Settings ideas](docs/SETTINGS_IDEAS.md) separates implemented controls from possible future improvements.

Choose **Settings → Storage → Downloads → Card image source** (also under Presentation). **Cache only** browses downloaded images; explicit Builder card/edition selections can fetch their own missing image. **Download as needed** reads that same disk cache first, downloads only missing images displayed in the builder/game/gallery, then retains them for later views and restarts. It does not start a whole-library download. The current provider is Scryfall’s image CDN; there is no arbitrary alternate-CDN selector.

Small card images use one cached JPEG derivative, up to 256 pixels wide, when it has enough pixels for the physical display size after UI, camera and display scaling. Inspect and larger views keep the original. Derivatives are prepared in the background after download/import or on first use of an existing image; originals stay usable while preparation runs. This adds some cache space, but does not create export-folder copies. New jobs default to SQL storage without exports; existing export choices and files remain unchanged.

Selected images take precedence over ordinary image requests and background download/import work. Image reads and uploads are bounded to reduce disk contention and frame spikes. A cached image can still take time to reach the screen on a busy or cold drive.

**Settings → Graphics → Decoded artwork cache** offers 128, 256 or 512 MiB, default 256. This is a shared memory budget for card/gallery/profile textures; eviction leaves disk images intact. HTTP and JPEG/PNG decoding run on worker threads, while texture upload stays on the graphics thread. This helps target a client footprint around/below 1 GiB, but is not a hard limit on all allocations or the separate Java XMage process.

## Profile, avatars and playmats

Click your name/avatar in the main header, or **Profile and playmat** in Settings, to choose your name, a card-art avatar and optional playmat. Search the existing artwork gallery and save the selected printing/face. Missing local images remain placeholders under the local-artwork-only setting. Changes apply to new games and room joins; they do not rename an existing native player.

Profile avatars use square previews, while playmats retain the illustration's landscape view. Profile and Gallery distinguish **not cached**, **loading** and **failed** images. Choose **Download avatar**, **Download playmat**, or the selected Gallery illustration's download button to fetch that exact printing without enabling general foreground downloads. A missing illustration never substitutes a different artist's art. Cache totals and the bulk downloader's paused status are shown when available; a partially downloaded library is not a complete offline collection.

Player avatars and playmats travel with public room/draft seats into native games and recordings. Bots use a commander or deck portrait when available. Life totals always come from XMage, including Commander starting life and later gains/losses; profiles do not offer an HP override. The [profile guide](docs/PROFILES.md) describes persistence, exact artwork identity and privacy boundaries.

## Optional Starter image pack

Starter pictures are a **separate optional ZIP**, keeping installers small. It contains full-card scans and art crops for the twenty Starter decks, including needed image faces, rather than every printing of every card. Your other decks and alternate editions use the same local cache and optional on-demand policy.

Open **Settings → Storage → Downloads → Optional Starter image pack**. **Browse** for its ZIP (or drop the ZIP into the client), then **Inspect pack** to check editions, checksums, image count and required bytes. Inspection writes no images. **Install images** is explicit, preserves already cached images and retains at least 64 MiB free space. Pause an active bulk image job before installation; inspection can run while that download continues. A partial interruption retains committed images and can resume through Inspect/Install. Purging cached images does not automatically reinstall the pack.

For this local build, `build/artifacts/Love2Gathering-Starter-images-2026-11-15.zip` contains **1,030 images from 506 card names across all twenty Starters**, about **86 MiB**, with its adjacent `.sha256` file. It was built from 974 existing images and 56 explicitly acquired missing images, with no writes to the source cache. Images retain their catalog printing/face/source identities. Choose a pack matching the installed metadata; unrelated or unknown editions are rejected.

The manual **Optional Starter image pack** GitHub Actions workflow builds and validates a separate ZIP, checksum and provenance artifact on `development`. It does not add images to installers, initialize XMage or publish a Release. An Actions artifact wraps the pack files: extract that download and select the inner `Love2Gathering-starter-images.zip` in Settings. The workflow has not been dispatched for this local change.

A local builder can also run `scripts/starter-image-pack.py plan` or `export` with `--catalog`, `--database` and a new `--output` destination. Those commands use existing SQL read-only and never download. Explicit **build** fetches only missing Starter images; omitting `--database` gives a separate cache-free CI acquisition. See [storage details](service/STORAGE.md).

## Gallery and offline image downloads

**Gallery** presents artwork with the card name, set, illustrator and printing's release year. Search by card/artist/set/year, filter by set or artist, and choose **Extended art**, **Borderless** or **Showcase** variants. Click an image for an art-only enlargement. Artist, Shop and Services buttons open reviewed links; unresearched artists have no invented links. The initial reviewed registry covers the original five bundled Commander illustrations and several additional artists. See [the catalog guide](service/README.md#artwork-metadata-and-offline-images) for coverage and provenance.

Open **Settings → Storage → Downloads** to scan the configured local card list without downloading. Choose full cards, cropped art or both, and normal or large scans. The result shows cached/missing image counts, unique network requests, an estimated size range and required additional disk space. Press **Start download** explicitly; **Pause** and **Resume** retain committed images. A small navbar progress bar shows progress and opens these controls. New managed downloads use SQLite only by default, avoiding duplicate JPEG exports.

The command-line downloader also supports resumable full card scans, including their printed frame/stats, and separate cropped illustrations:

```sh
python3 scripts/download-card-images.py --metadata /path/to/cards.jsonl --output /path/to/image-library
```

New command-line jobs default to the application's authoritative SQLite cache without separate exports. An explicit `--output` folder, as above, or `--export-mirrors` also creates **`full-cards/`** and **`art-crops/`** folders. All supplied printings and image faces, including extended-art printings, are retained. Restarting reuses saved images and preserves the job's export choice; `--sql-only` suppresses exports. Add `--limit 2` for a small trial, `--dry-run` to inspect entries without downloading, or `--full-size large` for larger full-card scans.

Runtime images resolve printing, face and image kind locally, reusing a cached same-card printing when appropriate. Full-card scans never substitute for art crops. Gallery keeps exact printing/face identity so its illustrator and set credits match the displayed image. See [image identity and library APIs](service/LIBRARY.md).

If the original metadata is missing, obtain a new source explicitly without overwriting another file:

```sh
python3 scripts/download-card-images.py --bootstrap-metadata default_cards --metadata /new/path/cards.jsonl --limit 2
LOVE2GATHERING_CATALOG_SOURCE=/new/path/cards.jsonl ./run.sh
```

The bootstrap fetches the entire selected metadata collection; `--limit` bounds image entries. Use `all_cards` instead of `default_cards` to include all languages. Omit `--limit` when ready to cache the complete image collection. `--data-dir` selects the application SQLite directory; otherwise the normal data-directory environment settings apply. Detailed behavior, source documentation and tested download scope are in [the asset guide](assets/ASSET_GUIDE.md#optional-offline-card-image-library).

## Recordings

New games are recorded automatically by the engine, including game-state frames, accepted actions and structured logs. The **Save replay** icon flushes the current recording without ending the game. Open **Replays** from the main navigation or the table's replay icon to browse and open recordings, including recordings from earlier launches. Playback provides pause/play, a timeline, previous/next frame and speeds from 0.5× to 8×. **Space** toggles playback; **Left / Right** step frames.

A replay is a read-only view of the recorded game; it does not resume a playable XMage session. The bot's hidden hand remains hidden. A recording interrupted by a process shutdown can retain its saved frames with an interrupted status. If the catalog is temporarily unavailable, the engine keeps events in a durable SQLite outbox and reports pending synchronization rather than reporting a successful save.

## Deck imports, token art and match history

Open **Import** from Decks to paste a deck list or supported public deck URL, or drop a TXT, DEC, COD, CSV or JSON export onto the app. Preview preserves main deck, sideboard, commanders and supplied printing information before saving. Archidekt, Moxfield and MTGGoldfish links use bounded public export/API routes; a site's access refusal shows a text-export fallback. Native validation still runs before playing.

**Token art** in the deck editor/manager offers **Default**, **Random selected** and **Random all**. Illustrations match the native token's original identity even when effects change its current stats or colors. Missing token metadata remains a placeholder. Lobby deck buttons now show a square cover, name and supplied Mana color symbols, with a searchable card grid for selection.

**History** lists participants, deck names and native win/loss/draw outcomes and opens their saved replay. Interrupted or incomplete games are labeled accordingly. Private remote-room recordings belong to the hosting server's catalog; guests do not receive another player's replay perspective.

## Saved data

The application's saves live in **`app.sqlite`**: owned decks/covers, profile artwork references, preferences, hidden bundled lists, layouts, indexed product templates and recordings. A separate **`images.sqlite`** holds cached artwork. Fresh installations use `DATA/cache/`; existing combined databases remain intact until an explicit split. `LOVE2GATHERING_DATA_DIR` overrides the saved database location, then XDG/mounted-drive/home defaults apply. `LOVE2GATHERING_CACHE_DIR` overrides the saved image-cache location. The launcher, catalog and downloader share these choices. Existing legacy files remain backups. SQLite uses WAL transactions; use SQLite's backup facility or close the application before copying databases.

Open **Settings → Storage → Locations** to browse independent database/cache folders. **Check locations** estimates copies and temporary space. Confirm **Prepare and use after restart**, then restart through `run.sh` once copies are ready. New matches/saves pause during preparation. You can cancel before restart; originals remain backups. The split physically moves image BLOBs out of the saves database. Missing saved drives stop startup with an explanation. See [location changes and recovery](service/STORAGE.md#prepare-a-location-change).

`replay-outbox.sqlite` in that directory provides durable engine recording delivery during service interruptions. The generated card catalog is separately stored in `service/data/catalog.sqlite`. Bundled source lists remain in `decks/`; deleting one from your collection hides it without deleting that source. XMage's working files are isolated by port in `data/engine-PORT`.

The catalog and engine bind only to loopback. Their preferred ports are **17370** and **17371**; the room gateway prefers **17380** and accepts network room connections. The launcher selects available ports when needed. `LOVE2GATHERING_CATALOG_PORT`, `LOVE2GATHERING_ENGINE_PORT` and `LOVE2GATHERING_ROOM_PORT` also support explicitly configured services. **Lobby** remains local practice; **Rooms** provides human multiplayer and drafting. The bot is XMage's existing AI; its strength varies by deck, and complex Phoenix/Lotus Field decisions may be weaker than straightforward combat play.

Open **Settings → Storage → Cleanup** to inspect image/replay counts, disk usage and reusable database space. Each **Purge** opens an explanation and confirmation. Full-card scans and art crops can be cleared separately. Replay cleanup removes completed/failed/aborted playback timelines while retaining match-history summaries; active recordings and pending native deliveries are protected. **Duplicate exports** deletes only managed JPEG copies that match an image already in SQLite. Decks, settings, profiles and original metadata are preserved.

Deleting SQL images/events makes pages reusable. **Compact database** is a separate explicit action for saves and image databases that can return that space to their drives; it needs temporary free space and is unavailable during active/pending recording. Do not close the app during compaction. No cleanup or image download runs automatically at startup. [Storage behavior and limits](service/STORAGE.md) describes safe scopes, estimates and recovery.

## Verification and development

```sh
python3 -m unittest discover -s service/tests -v
lua tests/frontend_model.lua
lua tests/card_choices.lua
lua tests/board_fx.lua
lua tests/library_model.lua
lua tests/collection_model.lua
lua tests/profile_model.lua
lua tests/builder_model.lua
lua tests/builder_layout.lua
lua tests/replay_model.lua
lua tests/json_codec.lua
lua tests/table_camera.lua
lua tests/priority_model.lua
lua tests/gallery_model.lua
lua tests/rooms_model.lua
lua tests/api_rooms.lua
python3 decks/validate_library.py
tests/assets-input.sh
tests/richtext.sh
tests/quit_storage.sh
scripts/test-engine-fixtures.sh
tests/multiplayer_ui.sh
tests/lobby_ui.sh
tests/match_choices_ui.sh
tests/library_ui.sh
tests/theme.sh
tests/assets_presentation.sh
```

The isolated [mechanics runner](docs/MECHANICS_TESTING.md) adds 74 directed native scenarios, 16 lifecycle/stress manifests, generated temporary decks, production games, watchdog/outbox recovery and actual LÖVE checks. Read the [current findings and measured limits](docs/MECHANICS_REPORT.md), including failed native expectations and recording/rendering budget findings; this suite deliberately does not report universal or all-green Magic coverage. Run `python3 scripts/test-mechanics.py --mode full --jobs 1` from the repository root. This workflow leaves the entire engine tree read only and builds the bridge in temporary storage.

Earlier engine evidence includes **20/20 deck startups**, automatic/manual simultaneous triggers with nested Pridemate counters, legal-action/mana-wheel/mulligan fixtures, and a complete **Modern bot game: eight turns and 65 actual engine prompt answers**. Both sides played lands, cast and resolved spells, life totals changed, and the game ended normally. See [the engine reports](bridge/README.md#acceptance-checks). This does not establish exhaustive card/combo coverage or optimal bot strategy.

The independent-cache/presentation continuation passes [172 service tests](tests/service-refresh-report.json), [27 Lua model groups](tests/client-model-refresh-report.json), real temporary-store [Locations UI checks](tests/storage-locations-ui-report.json), and actual [cursor/font/slider/clip](tests/presentation-refresh-ui-report.json), [startup resource/error](tests/startup-ui-report.json) and [gameplay presentation](tests/gameplay-presentation-ui-report.json) checks. A separate [real launcher smoke](tests/startup-main-report.json) opens the splash and client with isolated services and a split cache. [Native opening/impact fixtures](bridge/tests/starting-presentation-report.json) and [JDBC relocation/recovery](bridge/tests/replay-relocation-report.json) establish their engine behaviors separately from UI fixtures. No acceptance test relocates or purges the user's library.

The separate [recording report](bridge/tests/replay-recording-report.json) verifies a complete native game with **63 answers, 413 recorded frames and 220 log events**, reopening SQLite, spell/ability source artwork/text, hidden bot hands, saving during play and recovery after a catalog outage and recorder-process crash. Recording happens in the engine; it does not depend on frontend polling.

Actual LÖVE/Slab input checks cover UTF-8 editing, selection, clipboard shortcuts, caret placement and asset loading. Frontend tests that inject a game state verify their own rendering/interactions; real-engine acceptance is recorded separately.

The combat/cache/layout correction adds [76 native combat checks](bridge/tests/combat-timing-report.json) and [34 actual native-action UI checks](tests/combat-timing-ui-report.json), including confirmed Rat sacrifice at actual 1440×900 and 1120×760. It separately verifies [50 global-control checks](tests/global-controls-ui-report.json), [46 builder/save checks](tests/builder-modes-ui-report.json), [100 client layout checks](tests/client-layout-ui-report.json), [54 Profile/Gallery checks](tests/profile-ui-report.json) and [16 real precon-picker/native-validation checks](tests/deck-picker-ui-report.json). The camera/input fixture has 293 checks; these fixture scopes do not claim exhaustive card coverage. Exact cache coverage and selected-image download evidence are linked from [the artwork report](tests/artwork-profile-gallery-report.json).

Earlier collection/profile backend verification passed **95 service tests**, including **15 preconstructed** and **7 profile** cases. [Preconstructed HTTP evidence](service/tests/precons-live-report.json) adds 16 read-only checks against the real local catalog. Profile verification separately includes 15 model, 16 native fixture, [24 actual Profile UI checks](tests/profile-ui-report.json) and [12 actual room/recording HTTP checks](tests/profile-live-report.json). [Collection/replay acceptance](tests/collection-replay-ui-report.json) has 91 actual UI/service checks with inspected captures, including square art, colors, ownership, date layout, playmats and keyword details. The [asset presentation checks](tests/assets-presentation-report.json) cover 82 actual LÖVE checks; installed fonts, theme, input and rich text separately pass 19, 16, 33 and 19 checks. Collection model tests add 24 request/ownership/save regressions; keyword display tests add nine.

Earlier gameplay/library checks include 68 native view assertions, 17 production priority HTTP checks, and 29 actual frontend/native checks for scry/surveil/look-at, activation cancellation, live 5/5 display and blocking. [Real room rematch acceptance](tests/room-rematch-live-report.json) completes two native games and verifies opposite recorded outcomes. Board presentation was rerun with the new font/dice/profile integration: 35 checks; multiplayer terrain/input separately passes 253. Saved native frames and synthetic presentation data are distinguished in their reports. These checks establish their tested flows, not exhaustive card coverage.

With an isolated catalog running, `tests/builder_integration.sh` checks real saves, copy exceptions, rapid fifth-copy rejection and format changes. `tests/ux-run.sh` checks responsive rendering, centered mulligan dispatch, mana-wheel choices, trigger dragging, scaled popup movement and visible settings controls. Set `LOVE2GATHERING_CATALOG_PORT` to that test service; these tests must not use an active user's collection. UI captures distinguish the requested display size from the actual window size supplied by the desktop.

`tests/table_replay_ui.sh` additionally checks full-width table layout, centered/crowded mana rows, movable/resizable SQLite-backed panels and playback of an actual completed native recording. Use a temporary catalog containing the recorded engine acceptance game. Synthetic table fixtures establish layout, while the native recording establishes the content actually saved by XMage.

Technical architecture, safe test setup and contributor instructions are in [AGENTS.md](AGENTS.md). [CODEX.md](CODEX.md) records the development workflow and verification. The [upstream XMage review](docs/XMAGE_UPSTREAM_REVIEW.md) compares a newer development revision; this application retains its tested engine pin.
