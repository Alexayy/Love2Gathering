#!/usr/bin/env python3
"""Build a bounded full-art basic-land metadata pool from a supplied JSONL snapshot."""
import argparse
import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
NAMES = ('Plains', 'Island', 'Swamp', 'Mountain', 'Forest', 'Wastes')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, help='Existing Scryfall JSONL; never downloaded by this tool')
    parser.add_argument('--output', type=Path, default=PROJECT / 'assets/card-art/full-art-basics.json')
    args = parser.parse_args()
    sources = sorted((PROJECT / 'assets').glob('all-cards*.jsonl'))
    source = args.source or (sources[0] if sources else None)
    if source is None:
        parser.error('Provide --source pointing to an existing JSONL snapshot')
    entries = {name: [] for name in NAMES}
    with source.open(encoding='utf-8') as stream:
        for line in stream:
            raw = json.loads(line)
            if (raw.get('name') not in entries or raw.get('full_art') is not True
                    or raw.get('lang') != 'en' or not raw.get('image_uris', {}).get('art_crop')):
                continue
            entries[raw['name']].append({
                'printingId': raw['id'], 'oracleId': raw['oracle_id'], 'name': raw['name'],
                'set': raw.get('set'), 'releasedAt': raw.get('released_at'), 'fullArt': True, 'face': 0,
            })
    for name, items in entries.items():
        items.sort(key=lambda item: (item.get('releasedAt') or '', item['printingId']), reverse=True)
        entries[name] = items[:96]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({
        'source': source.name,
        'provenance': 'Exact full_art:true, English basic-land printing metadata from supplied Scryfall snapshot; no image files included.',
        'lands': entries,
    }, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({name: len(items) for name, items in entries.items()}))


if __name__ == '__main__':
    main()
