#!/usr/bin/env python3
"""Reject any outgoing change to the supplied XMage gitlink or .gitmodules.

This inspects parent Git objects/index entries only. It deliberately does not
checkout, stage, reset, clean, commit or push anything inside the submodule.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys

ENGINE_PATH = 'engine/mage'
ENGINE_PIN = 'd9b266fc981024873ac7ec5f90ee7121a060725e'
GITMODULES_BLOB = 'ba0dc072e733b30fdbf680dc0fb9b651ec0d7f32'


class GuardError(ValueError):
    pass


def git(*arguments):
    result = subprocess.run(['git', '--no-replace-objects', *arguments], capture_output=True)
    if result.returncode:
        raise GuardError(result.stderr.decode(errors='replace').strip() or 'Git inspection failed')
    return result.stdout


def commit_id(reference):
    return git('rev-parse', '--verify', '--end-of-options', reference + '^{commit}').decode().strip()


def check_entries(entries, label):
    gitlinks = {path: (mode, oid, stage) for path, mode, oid, stage in entries if mode == '160000'}
    if gitlinks != {ENGINE_PATH: ('160000', ENGINE_PIN, '0')}:
        raise GuardError(label + ': XMage gitlink must remain ' + ENGINE_PIN + '; no other gitlinks may be added')
    modules = [(mode, oid, stage) for path, mode, oid, stage in entries if path == '.gitmodules']
    if modules != [('100644', GITMODULES_BLOB, '0')]:
        raise GuardError(label + ': .gitmodules must remain unchanged with the supplied magefree/mage URL')


def tree_entries(reference):
    for record in git('ls-tree', '-r', '-z', reference).split(b'\0'):
        if record:
            metadata, path = record.split(b'\t', 1)
            mode, kind, oid = metadata.decode().split()
            yield path.decode(errors='surrogateescape'), mode, oid, '0'


def index_entries():
    for record in git('ls-files', '--stage', '-z').split(b'\0'):
        if record:
            metadata, path = record.split(b'\t', 1)
            mode, oid, stage = metadata.decode().split()
            if stage != '0':
                raise GuardError('Index contains an unresolved merge; finish it before publishing')
            yield path.decode(errors='surrogateescape'), mode, oid, stage


def check(base=None, head='HEAD', index=False):
    head_id = commit_id(head)
    revisions = [head_id]
    if base:
        base_id = commit_id(base)
        ancestor = subprocess.run(['git', '--no-replace-objects', 'merge-base', '--is-ancestor', base_id, head_id], capture_output=True)
        if ancestor.returncode:
            raise GuardError('The publish base is not an ancestor of HEAD; this guard never authorizes a force push')
        outgoing = git('rev-list', '--reverse', base_id + '..' + head_id).decode().splitlines()
        revisions = list(dict.fromkeys([base_id, *outgoing, head_id]))
    for revision in revisions:
        check_entries(list(tree_entries(revision)), 'Commit ' + revision[:12])
    if index:
        check_entries(list(index_entries()), 'Index')
    return {'passed': True, 'enginePath': ENGINE_PATH, 'enginePin': ENGINE_PIN,
            'gitmodulesBlob': GITMODULES_BLOB, 'snapshotsChecked': len(revisions),
            'outgoingCommits': max(0, len(revisions) - 1) if base else None,
            'indexChecked': index, 'nestedWorktreeUntouched': True}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', help='Already-published ancestor; every outgoing commit is checked')
    parser.add_argument('--head', default='HEAD', help='Parent commit/ref to inspect (default HEAD)')
    parser.add_argument('--index', action='store_true', help='Also reject a staged gitlink/.gitmodules change')
    args = parser.parse_args(argv)
    try:
        report = check(args.base, args.head, args.index)
    except GuardError as exc:
        print('XMage publish guard rejected the push: ' + str(exc), file=sys.stderr)
        return 1
    print(json.dumps(report))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
