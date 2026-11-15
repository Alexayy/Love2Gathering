#!/usr/bin/env python3
"""One numeric installer version and branch-specific, commit-bound release tags."""
import argparse
from datetime import date as calendar_date, datetime
import json
import os
from pathlib import Path
import re
import subprocess
from zoneinfo import ZoneInfo


def identifiers(number, attempt, commit, date=None, *, branch='development'):
    if not 1 <= int(number) <= 65535 or not 1 <= int(attempt) <= 99999:
        raise ValueError('Build number/attempt is outside the installer resource bounds')
    if not re.fullmatch('[0-9a-f]{40}', commit):
        raise ValueError('A complete lowercase commit SHA is required')
    if branch not in ('development', 'master'):
        raise ValueError('Only development and master produce installer releases')
    day = date or datetime.now(ZoneInfo('Europe/Belgrade')).date()
    version = f'{day.year}.{day.month:02}.{day.day:02}.{int(number)}'
    return {'version': version, 'branch': branch,
            'channel': 'stable' if branch == 'master' else 'development',
            'tag': f'v{version}' if branch == 'master' else f'DEV-{version}-{int(attempt)}-{commit[:12]}'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--number', default=os.environ.get('GITHUB_RUN_NUMBER'), required=not os.environ.get('GITHUB_RUN_NUMBER'))
    p.add_argument('--attempt', default=os.environ.get('GITHUB_RUN_ATTEMPT', '1'))
    p.add_argument('--commit', default=os.environ.get('GITHUB_SHA'), required=not os.environ.get('GITHUB_SHA'))
    p.add_argument('--branch', default=os.environ.get('GITHUB_REF_NAME', 'development'))
    p.add_argument('--date', type=calendar_date.fromisoformat, help='Explicit commit date for isolated checks')
    args = p.parse_args()
    try:
        # Validate environment/CLI values before passing the SHA to git.
        values = identifiers(args.number, args.attempt, args.commit, args.date, branch=args.branch)
        day = args.date
        if day is None:
            # A retry next day must keep the same numeric version/stable tag.
            timestamp = subprocess.check_output(['git', 'show', '-s', '--format=%cI', args.commit], text=True).strip()
            day = datetime.fromisoformat(timestamp).astimezone(ZoneInfo('Europe/Belgrade')).date()
        values = identifiers(args.number, args.attempt, args.commit, day, branch=args.branch)
    except (ValueError, subprocess.CalledProcessError) as exc:
        p.error(str(exc))
    if os.environ.get('GITHUB_OUTPUT'):
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as stream:
            for key, value in values.items():stream.write(key + '=' + value + '\n')
    print(json.dumps(values))


if __name__ == '__main__':main()
