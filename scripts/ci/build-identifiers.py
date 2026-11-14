#!/usr/bin/env python3
"""Numeric installer versions and unique development release tags for a CI run."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
from zoneinfo import ZoneInfo


def identifiers(number, attempt, commit, date=None):
    if not 1 <= int(number) <= 65535 or not 1 <= int(attempt) <= 99999:
        raise ValueError('Build number/attempt is outside the installer resource bounds')
    if not re.fullmatch('[0-9a-f]{40}', commit):
        raise ValueError('A complete lowercase commit SHA is required')
    day = date or datetime.now(ZoneInfo('Europe/Belgrade')).date()
    return {'version': f'{day.year}.{day.month:02}.{day.day:02}.{int(number)}',
            'tag': f'development-{int(number)}-{int(attempt)}-{commit[:12]}'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--number', default=os.environ.get('GITHUB_RUN_NUMBER'), required=not os.environ.get('GITHUB_RUN_NUMBER'))
    p.add_argument('--attempt', default=os.environ.get('GITHUB_RUN_ATTEMPT', '1'))
    p.add_argument('--commit', default=os.environ.get('GITHUB_SHA'), required=not os.environ.get('GITHUB_SHA'))
    args = p.parse_args();values = identifiers(args.number, args.attempt, args.commit)
    if os.environ.get('GITHUB_OUTPUT'):
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as stream:
            for key, value in values.items():stream.write(key + '=' + value + '\n')
    print(json.dumps(values))


if __name__ == '__main__':main()
