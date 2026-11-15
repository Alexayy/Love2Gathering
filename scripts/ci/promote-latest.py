#!/usr/bin/env python3
"""Promote the highest complete stable installer release; run in stable-latest CI concurrency."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

SPEC = importlib.util.spec_from_file_location('installer_publisher', Path(__file__).with_name('publish-release.py'))
PUBLISHER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUBLISHER)
MAX_PAGES = 20


def numeric_tag(tag):
    if not isinstance(tag, str) or not re.fullmatch(r'v[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[1-9][0-9]{0,4}', tag):return None
    version = tag[1:]
    try:PUBLISHER.version_value(version)
    except PUBLISHER.ReleaseError:return None
    numbers = tuple(map(int, version.split('.')))
    return numbers if numbers[-1] <= 65535 else None


def promote(gh):
    candidates = []
    for page in range(1, MAX_PAGES + 1):
        values = gh.api(f'repos/{PUBLISHER.REPOSITORY}/releases?per_page=100&page={page}')
        if not isinstance(values, list) or len(values) > 100:
            raise PUBLISHER.ReleaseError('Invalid bounded release listing')
        for release in values:
            if not isinstance(release, dict):raise PUBLISHER.ReleaseError('Invalid release listing entry')
            version = numeric_tag(release.get('tag_name'))
            if version and release.get('draft') is False and release.get('prerelease') is False:
                candidates.append((version, release))
        if len(values) < 100:break
    else:
        raise PUBLISHER.ReleaseError('Release listing exceeds its scan bound; refusing an incomplete Latest decision')
    if not candidates:raise PUBLISHER.ReleaseError('No published stable installer release is available')
    _, selected = max(candidates, key=lambda item:item[0])
    tag = selected['tag_name'];commit = selected.get('target_commitish');version = tag[1:]
    if not isinstance(commit,str) or not re.fullmatch(r'[a-f0-9]{40}',commit):
        raise PUBLISHER.ReleaseError('Highest stable release has no exact source commit')
    # Never fall back to an older release when the highest candidate is foreign
    # or incomplete: its full commit/tag/channel/manifest/assets must validate.
    if not PUBLISHER.check_published(gh, version, tag, commit, 'stable', 'master'):
        raise PUBLISHER.ReleaseError('Highest stable release is not completely published')
    try:latest = gh.api(f'repos/{PUBLISHER.REPOSITORY}/releases/latest')
    except PUBLISHER.NotFound:latest = None
    if latest is not None:
        if not isinstance(latest, dict):raise PUBLISHER.ReleaseError('Invalid current Latest identity')
        if latest.get('id') == selected['id'] and latest.get('tag_name') == tag:
            return {'tag':tag,'changed':False,'url':latest.get('html_url')}
        previous = numeric_tag(latest.get('tag_name'))
        if previous and previous > numeric_tag(tag):
            raise PUBLISHER.ReleaseError('A newer Latest exists; refusing to move backward')
    verified = PUBLISHER.get_release(gh,tag)
    PUBLISHER.verify_release(verified,tag,commit,'stable',draft=False)
    if verified['id'] != selected['id']:raise PUBLISHER.ReleaseError('Stable release identity changed during promotion')
    PUBLISHER.verify_tag(gh,tag,commit,required=True)
    gh.command('release','edit',tag,'--repo',PUBLISHER.REPOSITORY,'--latest=true')
    latest = gh.api(f'repos/{PUBLISHER.REPOSITORY}/releases/latest')
    if not isinstance(latest,dict) or latest.get('id') != selected['id'] or latest.get('tag_name') != tag:
        raise PUBLISHER.ReleaseError('Could not verify promoted Latest release')
    return {'tag':tag,'changed':True,'url':latest.get('html_url')}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__);parser.parse_args(argv)
    try:
        if os.environ.get('GITHUB_REPOSITORY') != PUBLISHER.REPOSITORY or os.environ.get('GITHUB_REF') != 'refs/heads/master':
            raise PUBLISHER.ReleaseError('Stable promotion is restricted to the project master branch')
        if not os.environ.get('GH_TOKEN'):raise PUBLISHER.ReleaseError('GH_TOKEN is required for stable promotion')
        print(json.dumps(promote(PUBLISHER.GitHub())))
    except (PUBLISHER.ReleaseError, OSError, ValueError, TypeError, subprocess.SubprocessError) as exc:
        parser.exit(1,'Stable promotion aborted: '+str(exc)+'\n')
    return 0


if __name__ == '__main__':raise SystemExit(main())
