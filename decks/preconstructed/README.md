# Historical preconstructed product source

`catalog.jsonl.gz` is the compact prepared MTGJSON snapshot, dated **2026-11-14**: 3,154 source records, with 1,183 ready deck products, 611 separately labelled packets and 1,360 non-deck collections excluded from default browsing. The catalog API indexes this local source into a separate table in `app.sqlite`; the frontend fetches bounded summaries and one detailed list at a time.

`manifest.json` contains the official archive checksum, provider/index URLs, snapshot version, classification totals and complete-provider-index coverage statement. `LICENSE-MTGJSON.txt` preserves the upstream MIT notice. These files contain metadata and quantities, not card image downloads or user decks.

Products are historical, unvalidated templates. In particular, a release-era Standard label is not a claim of current Standard legality. Editing/copying creates a new owned deck and uses the ordinary construction checks without changing this source. Wizards/XMage validation still controls what can actually start.

Refresh, provenance, categories, archive limits and API details are documented in [service/PRECONS.md](../../service/PRECONS.md). The explicit updater is `python3 scripts/sync-precons.py`; use `--offline` to rebuild from its previously verified local cache. Application startup never downloads the bulk archive.
