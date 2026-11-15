#!/usr/bin/env python3
"""Plan/export cached Starter images, or explicitly BUILD missing images.

Plan/export never acquire images. Build explicitly acquires missing Scryfall
JPEGs directly into a new ZIP staging file. All source SQL is read-only; no
command constructs/migrates user Storage, changes decks or writes source caches.
"""
import argparse
from contextlib import closing
import json
from pathlib import Path
import sys
import time

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'service'))
from catalog import Catalog
from image_packs import EmptyImages, ReadonlyImages, build_starter_pack, export_starter_pack, starter_plan


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('plan', 'export', 'build'), help='Build explicitly fetches missing images; plan/export are local-only')
    parser.add_argument('--catalog', type=Path, required=True, help='Existing generated catalog.sqlite; opened read-only')
    parser.add_argument('--database', type=Path, help='Existing app.sqlite; opened read-only. Build may omit this to use no local cache')
    parser.add_argument('--cache', type=Path, help='Existing images.sqlite; otherwise follow the saved cache location')
    parser.add_argument('--decks', type=Path, default=PROJECT / 'decks', help='Starter JSON list directory')
    parser.add_argument('--deck', action='append', help='Select a Starter ID; repeat to select several, default all20')
    parser.add_argument('--full-size', choices=('normal', 'large'), default='normal')
    parser.add_argument('--output', type=Path, help='New ZIP destination; existing files are never overwritten')
    args = parser.parse_args(argv)
    if not args.catalog.is_file(): parser.error('Existing catalog database is missing; no index is built by this command')
    if args.command in ('export', 'build') and args.output is None: parser.error('Export/build require a new --output ZIP path')
    if args.command != 'build' and args.database is None: parser.error('Plan/export require an existing --database SQL source')
    if args.cache is not None and args.database is None: parser.error('--cache requires its --database owner')
    last = [0.0, None]
    def progress(phase, done, total):
        current = time.monotonic()
        if phase != last[1] or current-last[0] >= .5 or done == total:
            print(f'{phase}: {done}/{total}', file=sys.stderr, flush=True)
            last[:] = [current, phase]
    try:
        catalog = Catalog(PROJECT / 'unused-local-metadata.jsonl', args.catalog)
        with closing(ReadonlyImages(args.database, args.cache) if args.database is not None else EmptyImages()) as source:
            if args.command == 'plan': manifest = starter_plan(catalog, source, args.decks, args.deck, args.full_size, progress)
            else:
                action = build_starter_pack if args.command == 'build' else export_starter_pack
                manifest = action(catalog, source, args.decks, args.output, args.deck, args.full_size, progress)
        report = {'complete': manifest['complete'], 'decks': len(manifest['decks']), 'images': len(manifest['images']), 'totalBytes': sum(v['size'] for v in manifest['images']), 'missingEntries': len(manifest['missing']), 'missing': manifest['missing']}
        if args.command in ('export', 'build'): report['path'] = str(args.output.absolute())
        print(json.dumps(report, ensure_ascii=False, indent=2));return 0
    except (OSError, ValueError, KeyError) as exc:
        print(str(exc), file=sys.stderr);return 1


if __name__ == '__main__':
    raise SystemExit(main())
