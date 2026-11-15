# Storage, cleanup and image downloads

## Database and image-cache locations

`service/paths.py` resolves the data directory in this order:

1. `LOVE2GATHERING_DATA_DIR`, when explicitly set.
2. The active database directory saved by Settings.
3. `XDG_DATA_HOME/love2gathering`, when explicitly set.
4. An existing `.local/share/love2gathering/app.sqlite` at the nearest mounted-drive ancestor of the project.
5. `$HOME/.local/share/love2gathering`.

The launcher exports that result for the catalog, native replay recorder and room host. Standalone catalog/downloader commands use the same resolver; their explicit `--data-dir` takes precedence. Merely launching does not copy, remove or merge an older home store. Settings Storage and `/health.storage.dataDirectory` show the actual destination. The copied home directory remains a separate backup.

`app.sqlite` is authoritative for saves and replay metadata/events. A separate cache stores authoritative image BLOBs in **`images.sqlite`**, with JPEG folders as optional export mirrors. New installations use `DATA/cache/images.sqlite`. An existing combined `app.sqlite` stays combined until an explicit location change; it is never silently split at startup. The cache resolver uses `LOVE2GATHERING_CACHE_DIR`, a matching saved cache location, then the database's persisted cache reference. Missing persisted database/cache files stop startup with a reconnect-drive explanation rather than creating an empty replacement.

The generated card index in `service/data/catalog.sqlite` is separate. `replay-outbox.sqlite` contains native delivery work and is never purged as a cache. Source JSONL, bundled decks and external image-library paths are outside cleanup scope.

### Prepare a location change

Open **Settings → Storage → Locations**. Type or browse the database and image-cache folders, then **Check locations**. The review shows copies, temporary space and free space on each affected drive. **Prepare and use after restart** opens a confirmation before any copies begin. Image BLOBs are copied in bounded batches into the selected `images.sqlite`; decks, profiles, layouts, history and recordings remain in `app.sqlite`. Both databases retain WAL, busy-timeout and full-synchronous behavior. Image-cache ownership is tied to the saves database, preventing accidental use of another library's cache.

Preparation pauses writes and new matches. Active/pending native recordings, a downloader or maintenance job must finish first. Other catalog writers are fenced, and native outbox writes use a coordinated retirement marker. The current store, native delivery state and staged copies are checked again at activation. A changed source or a foreign file that appeared at the destination causes activation to fail without replacing it.

When copies are ready, close the client and launch it again with **`run.sh`**. The launcher activates verified copies before starting any writers. **Cancel location change** works during preparation or while awaiting restart. It restores the current store and removes only this operation's staged copies. Originals are retained as backups, including `.before-…` backups for files replaced in the same folder. Consequently, changing locations alone does **not** reclaim the original copy's disk space.

`storage-paths.json` under `${XDG_CONFIG_HOME:-$HOME/.config}/love2gathering` records the active/prepared locations; `LOVE2GATHERING_CONFIG_DIR` overrides that directory for tests. Explicit data/cache environment overrides take precedence and are reported in Settings. Do not point a second catalog at another installation's pending location change. Standalone services should be stopped before activation; use the launcher to finish a prepared change.

## Cleanup

Settings → Storage → Cleanup asynchronously scans counts and sizes. Successful totals stay cached until **Refresh usage**, completed maintenance or a relevant download update; navbar polling does not repeatedly rescan a large HDD cache. Purge buttons open a confirmation with the selected category's consequences. No cleanup runs on startup.

| Category | Removes | Preserves |
| --- | --- | --- |
| Full-card scans | Cached full-card JPEG BLOBs, including normal/large scans, and managed full-card exports | Cropped art, decks, profiles, settings and source metadata |
| Cropped artwork | Cached `art_crop` BLOBs and managed cropped-art exports | Full-card scans and saved avatar/playmat references; those references may show a missing-image placeholder |
| Replays | Finished playback timelines and their events | Match-history summaries, active recordings and native outbox work |
| Duplicate exports | Managed `image-library` JPEG copies whose bytes match an authoritative cached SQL image | SQL images, unique/changed exports, legacy backup directories and external mirrors |

The displayed duplicate estimate is an upper bound based on matching keys/sizes. Actual deletion compares bytes. Symlinks and unrecognized filenames are not followed. Original legacy backups remain untouched. Import barriers prevent retained legacy/external files from silently repopulating an explicitly purged image category. A deliberate later download can cache that category again.

Replay purge tombstones prevent delayed retries from recreating a deleted timeline. History keeps participants, decks and native outcomes, but a purged match no longer has a playback recording. A replay with pending native events, unfinished delivery or active recording is protected. A fully acknowledged terminal outbox row is safe even when its engine process remains alive.

Deleting SQL rows makes pages **reusable inside the database**; it does not promise an immediate smaller file. Duplicate-export cleanup returns filesystem space directly. **Compact database** is a separate explicit VACUUM operation after cleanup, covering both saves and a separate image database. It needs temporary free space on each affected drive (the interface displays the conservative requirement), and refuses active/pending recording. During exclusive maintenance ordinary storage access may briefly report busy; health and progress remain available. Duplicate-export-only cleanup permits ordinary SQL readers.

Purges and compaction exclude image jobs through cross-process locks. Compaction uses a bounded owned child process and a temporary directory on the data drive. Closing the catalog cancels owned maintenance and stops that child. A cancelled purge may already have removed some selected items; other categories remain intact. Do not use cleanup tests against a user's real store.

## Scan before downloading

Settings → Storage → Downloads selects full cards, art crops or both, and normal/large full scans. **Scan download size** streams the configured local JSONL/JSONL.GZ into a persistent SQL work plan. It does not make Scryfall/CDN requests. The plan retains exact printing/face/kind identity, including extended-art printings and multi-face cards. An existing large scan can satisfy the same printing/face's normal scan.

The result distinguishes total image identities, cached identities, missing identities and unique network requests. Identical source URLs can be fetched once while retaining each printing's cache entry. Byte estimates use a bounded sample of up to 512 existing cached images for each kind, with labeled conservative defaults when there is no sample. A range communicates uncertainty: remote image sizes are unknown until fetched. Extra SQL/mirror storage and reusable SQL pages are shown separately from network bytes. No mass HEAD requests are used to estimate a library. Sampling and final sizing use read-only transactions after short plan writes, allowing replay/deck/settings writes to continue during an estimate.

**Start download** is explicit. Progress, downloaded count/bytes and transfer speed appear in a small clickable navbar ribbon; during gameplay a compact toolbar indicator opens the same controls. **Pause**, **Resume** and **Cancel** keep committed images. Restarting the catalog pauses interrupted work and does not automatically resume network access. A second client can inspect/control the shared job. A source change requires a new scan; purging images invalidates an older plan.

Managed downloads and new standalone `scripts/download-card-images.py` jobs default to **SQLite only**, avoiding a second JPEG copy. Optional mirror export writes separate `full-cards` and `art-crops` files after SQL commits. The CLI accepts `--export-mirrors` or an explicit `--output` folder to request exports, and `--sql-only` to suppress them. Saved job choices are retained. Existing mirrors can repair SQL without another request when explicitly included in a plan.

Requests retain the downloader's pacing, bounded JPEG/provenance checks and retries. Bulk work checks both database and cache drives and pauses before crossing the 3 GiB free-space reserve. A few explicit selected-image downloads use their smaller separately documented reserve. A download failure or pause does not invalidate already committed images. The app still uses local-only foreground image reads by default.

## Loading and responsiveness

The client startup gate hydrates saved settings, profile, legacy deck lists and panel layout before showing the first client view. It also prepares the cached avatar and up to eight visible deck covers with a two-second optional local-only budget; missing/error/pending counts remain distinct, and pending artwork continues in the background. Display changes run behind that gate; icon canvases are regenerated afterward. The loading circle and percentage also appear on the download ribbon and respect reduced motion. A missing cached image remains a missing-image state rather than a reason to download the whole library at startup.

Foreground preferences, metadata searches, image reads and maintenance use separate bounded HTTP queues. Two visible-image readers and two reserved selected-image readers keep an old slow selection from occupying every image socket. Two reserved selected point-metadata readers similarly bypass ordinary deck lookups; identical in-flight reads are coalesced. Ordered saves and native actions retain their own routes. A read of the same resource waits behind queued writes, so chained refreshes cannot adopt a pre-save snapshot. A busy SQLite request returns **503 with Retry-After** within a three-second interactive lock budget instead of holding a socket for the background writer's 30-second budget. Explicit remote image waits have their own timeout and do not consume the remaining SQL lock budget. Only read requests retry once; an uncertain mutation or native action is never automatically resubmitted.

Metadata results use a detached, thread-safe 256-entry / 8 MiB memory cache, invalidated when the local generated index is replaced. The client retains at most 512 name lookups and bounded decoded-image caches. SQL image aliases select the winning cache identity before loading its BLOB, and cached-printing preference stops after its first match. Printing, face, kind and exact-edition boundaries remain intact.

Plan cache checking/removal uses 256-row transactions and yields between batches. Downloads prioritize exact saved editions and profile art, then covers/commanders and one default printing per card in owned/Starter decks. Other reprints remain in the plan. Existing cached scans are reused; a larger scan can satisfy a normal request. Direct CDN image requests reuse one TLS connection per sequential downloader, preserving proxy settings, provider pacing, JPEG limits and bounded retries. There is no Redis dependency or extra parallel CDN acquisition.

Restart through the updated launcher to load API 14 and these changes. It does not reuse an incompatible old catalog, stop an existing user's service, split an old combined database, or automatically resume paused downloads. The active user cache and ongoing downloads are excluded from acceptance tests; local controlled measurements do not predict Internet bandwidth or cold-drive latency.

## On-demand images and memory

Storage → Downloads and Presentation expose **Cache only** / **Download as needed** using the existing persisted `localArtworkOnly` boolean. Both modes prefer authoritative local SQL images. Explicitly selecting a Builder card or edition tile is an exception to Cache only: it acquires that selection's missing exact image at highest priority without changing the saved mode. Merely opening Builder or hovering does not enable that exception. On-demand fetches an image only after a cache miss and commits it; revisiting it or restarting does not require another transfer. Browsing additional cards can request their images too. Source metadata/URLs remain catalog-owned Scryfall references; there is no user-supplied CDN URL setting.

`artworkMemoryMiB` accepts 128/256/512 (default 256), shared across card/profile/gallery decoded textures. Logical pixel accounting includes higher-precision textures, with an additional 512-image safety bound and separate negative-status limits. Aliases of one GPU Image are charged once and evicted together; ready textures do not consume the independent negative-status allowance. GPU objects borrowed by UI draw commands retire through their normal lifetime rather than premature release; incremental collection bounds the working set. HTTP workers decode requested JPEG/PNG responses before handing ImageData to the main thread; channel and callback owners release their references explicitly. Completion processing prioritizes selections and delivers at most two image completions / 8 MiB per update, allowing one larger bounded image when it is first. Compressed replies are bounded at 3 MiB and image headers at 4,194,304 pixels before allocation. This budget is not a hard RSS/GPU/system total or an XMage heap cap.

Builder metadata pages sort selected identities before reading JSON. Broad default name pages use the existing name index; sparse/empty results retain selective plans. Printing pages have detached bounded caching and their own request lane; point metadata lookups remain independent of broad searches. Catalog connection scopes now close deterministically. SQL image alias selection uses covering index keys separately per image kind, preserving exact faces/editions without inspecting every candidate’s overflow-backed metadata.

## Optional Starter ZIP

The optional media package is independent of installers and user decks. Its version 1 manifest lists exact printing/Oracle/face/kind/source identities, byte sizes and SHA256 hashes. Inspection validates the bounded central directory, every declared JPEG and catalog identity before offering installation. Limits: 4,000 images, 3 MiB per JPEG, 1 MiB manifest and 2 GiB archive/uncompressed total. No archive extraction or executable content is used; undeclared/duplicate/traversal/symlink/encrypted entries are rejected.

The local JSON controls preview asynchronously, then install only the reviewed job ID. Import validates the archive again, checks disk space, coordinates with bulk download and purge/relocation locks, and inserts only absent SQL keys. Existing images/settings/decks/profiles are preserved. It retains 64 MiB plus room for the next image and yields between writes. A failure can leave already committed valid images; re-inspection resumes without overwriting them. Ready GPU textures stay usable; missing/error artwork entries are retried after a successful import. ZIP files are never silently reimported after Purge.

`scripts/starter-image-pack.py plan/export` opens source catalog/image SQL in read-only mode without constructing Storage or applying migrations. Explicit `build` uses the same paced image Fetcher only for missing selected Starter entries, publishing a new ZIP only after successful completion. No original SQL is modified and existing output files are not replaced. The supplied local complete package was additionally validated/imported/reimported into an empty temporary store; `tests/starter-image-pack-report.json` retains counts and SHA256.

The manual optional workflow uses verified metadata in disposable CI storage, selects all twenty library IDs and independently verifies complete image coverage before retaining its separate ZIP/SHA/provenance artifact. It has read-only repository permission, no user-cache inputs, no engine initialization and no automatic Release publication. Installer payloads include the import support/tool but no card-image bundle.

## Selected-image priority and disposable small variants

API14 image requests retain cache-first exact identity. `priority=selected&network=1` is an explicit Builder selection's exception to Cache-only browsing; ordinary views do not acquire a whole library. The foreground is ordered selected → visible → background, with one process-local image disk operation at a time. Metadata/settings/replay connections retain SQLite WAL concurrency and FULL synchronization. Separate current CLI processes yield through an advisory foreground marker before their next bounded background step; an older binary cannot acquire the new scheduling policy retroactively.

`variant=thumb` requests one aspect-preserving JPEG derivative, up to256pixels wide/512high. Images too large for that physical display target use the original. `art_sources` and `art_thumbnails` live beside image BLOBs in the configured cache, keyed by exact original identity/digest/version. Foreign keys and content invalidation triggers protect purge/replacement, including older writers. The original is retained. Combined→split relocation drops disposable image tables from the prepared application DB and can rebuild derivatives in images.sqlite.

Generation is asynchronous and low priority. Owned service/download/import/CLI lifecycles explicitly enable a lazy retiring worker; bare Storage consumers launch no thread. Its64-key queue is bounded; overflow retains the original and a later visible request schedules the derivative again. There is no eager legacy-library conversion. Original fallback responses expose `X-Love2Gathering-Art-Variant`, `X-Love2Gathering-Thumb-Pending` or `X-Love2Gathering-Thumb-Unavailable`; pending variants retry only while requested, at least one second apart. Optional-codec absence keeps originals available without an endless pending loop. Pillow/JPEG is packaged or declared by installers; source launch reports its absence without installing anything.

`/health.imageVariants` reports codec/queue capability. `/art/cache-info` separates `.thumbnailImages`/`.thumbnailBytes`, `.thumbnails` worker counts and `.io` aggregate waiting/operation/stage durations. Image replies expose `Server-Timing` for catalog/queue/local/network portions. These are diagnostics, not external CDN or physical-drive benchmarks. Small variants consume additional cache bytes; export duplicates remain separately optional. New jobs/CLI defaults avoid exports, and saved job choices are preserved.

## Local API

Catalog API 14 includes these controls, the six current card-back styles, exact card editions and grouped per-token artwork choices. All mutation bodies require a direct local JSON request without browser-origin headers. Location routes accept validated directory paths; the explicit image-pack inspector accepts one bounded local ZIP input path. Purge, compaction and download controls cannot choose arbitrary filesystem paths.

| Request | Body / behavior |
| --- | --- |
| `GET /storage/status?refresh=1` | Start/refresh asynchronous usage statistics; return current operation and cached statistics promptly |
| `POST /storage/purge` | `{ "categories": ["full_cards", "art_crops", "replays", "export_duplicates"] }`; select only desired categories |
| `POST /storage/compact` | `{}` |
| `GET /downloads/status` | Durable job state, plan estimates, validity, progress, speed and free space |
| `POST /downloads/scan` | `{ "fullSize": "normal", "kinds": ["normal", "art_crop"], "mirrors": false }` |
| `POST /downloads/control` | `{ "command": "start" }`; also `pause`, `resume`, `cancel` |
| `GET /storage/image-packs/status` | Bounded preview/import state and progress |
| `POST /storage/image-packs/inspect` | `{ "path": "/…/Starter-images.zip" }`; validate a user-selected local archive without writing images |
| `POST /storage/image-packs/install` | `{ "jobId": "…" }`; import only the inspected archive and preserve existing SQL images |
| `GET /storage/locations` | Active/configured paths, explicit overrides and operation/restart state |
| `POST /storage/locations/validate` | `{ "databaseDirectory": "/…", "cacheDirectory": "/…" }`; validate and estimate without copying |
| `POST /storage/locations` | The same two fields; prepare verified copies and require launcher restart |
| `POST /storage/locations/cancel` | `{}`; cancel this installation's running or prepared change |

The frontend fences stale status responses and clears affected decoded images/replay views after confirmed purge. A fast operation that completes before the next poll still triggers invalidation. New image commits retry missing artwork without needlessly discarding ready decoded textures.

## Verification scope

`service/tests/test_paths.py` covers destination precedence without home writes. `test_maintenance.py` covers scoped purges, preserved history/outboxes, mirror barriers, lock exclusions and real temporary SQLite shrink/reopen. `test_downloads.py` covers streamed plans, estimates, pacing/control recovery, URL/face identity, reserve protection and plan invalidation. `test_storage_http.py` exercises the actual local routes against isolated SQL and a bounded fake image fetcher. These tests never purge or bulk-download into the user's cache.

`tests/storage_model.lua` checks async request fencing and UI invalidation. `tests/storage_ui.sh` drives actual LÖVE/Slab controls against an explicitly synthetic async service ledger; its captures verify layout and input, not Internet transfer or native gameplay. Broader service/model checks cover existing migration, deck/profile and replay behavior independently.

`test_storage_locations.py` and `test_storage_locations_http.py` use temporary real SQLite stores for preparation, split-image reads, cancellation, atomic activation/recovery, cross-writer fences and destination ownership. `tests/storage_locations_ui.sh` drives actual text input, folder picker, validation and confirmations against an isolated real catalog. `ReplayRelocationFixture` separately verifies native JDBC retirement and crash recovery. None relocates the user's actual library.
