#!/usr/bin/env python3
"""Fresh native zone offers, private multipick, current mechanics and mass-destruction acceptance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from mechanics.runtime import OwnedProcess, build_bridge, isolated_env, java_tools, sha, write_json


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--build-report', type=Path, help='Reuse only a build whose source and JAR hashes still match')
    parser.add_argument('--report-file', type=Path, default=ROOT / 'bridge/tests/zone-actions-report.json')
    args = parser.parse_args(argv)
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='love2gathering-mechanics-zone-actions-'))
    if not str(output).startswith('/tmp/love2gathering-mechanics-') or output.is_symlink():
        parser.error('Use a fresh owned mechanics /tmp directory')
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error('Output must be empty')

    def engine_identity():
        def git(*values):
            return subprocess.check_output(['git', *values], cwd=ROOT)
        return dict(head=git('rev-parse', 'HEAD:engine/mage').decode().strip(),
                    index=git('rev-parse', ':engine/mage').decode().strip(), gitmodules=sha(ROOT / '.gitmodules'),
                    status=git('-C', 'engine/mage', 'status', '--porcelain=v1', '--untracked-files=all').decode(),
                    diff=hashlib.sha256(git('-C', 'engine/mage', 'diff', '--binary')).hexdigest())

    before = engine_identity()
    build, result, watch, failure = None, {}, {}, None
    sources = [ROOT / 'bridge/tests/love2gathering' / name for name in (
        'TriggerFixture.java', 'ActionabilityFixture.java', 'GameplayPresentationFixture.java', 'ZoneActionsFixture.java')]
    try:
        if args.build_report:
            document = json.loads(args.build_report.read_text())
            build = document.get('build', document)
            recorded = build.get('sources') or build.get('sourceHashes')
            if not recorded or any(sha(ROOT / name) != digest for name, digest in recorded.items()):
                raise ValueError('Bridge source changed since this build')
            if sha(Path(build['jar'])) != build['jarSha256']:
                raise ValueError('Bridge JAR changed since this build')
        else:
            build = build_bridge(output / 'build')
        classes = output / 'fixture-classes'
        classes.mkdir()
        command = [str(java_tools()['javac']), '--release', '21', '-encoding', 'UTF-8', '-cp',
                   build['classpath'], '-d', str(classes), *map(str, sources)]
        compiled = subprocess.run(command, capture_output=True, text=True, timeout=30)
        (output / 'fixture-compile.log').write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            raise RuntimeError('Fixture compilation failed; see fixture-compile.log')
        work = output / 'native'
        env = isolated_env(work)
        process = OwnedProcess([
            str(java_tools()['java']), '-XX:ActiveProcessorCount=2', '-Xmx768m', '-Djava.awt.headless=true',
            '-Duser.home=' + env['HOME'], '-cp', str(classes) + os.pathsep + build['classpath'],
            'love2gathering.ZoneActionsFixture', str(ROOT), str(work)], work, env=env)
        watch = process.wait({'wallSeconds': 60, 'cpuSeconds': 45, 'rssBytes': 1200 * 1024 ** 2,
                              'diskBytes': 64 * 1024 ** 2})
        if (work / 'result.json').is_file():
            result = json.loads((work / 'result.json').read_text())
        if watch.get('status') != 'pass' or result.get('passed') is not True:
            raise AssertionError('Native zone acceptance failed; see native/process.log')
    except Exception as exc:
        failure = str(exc)
    unchanged = engine_identity() == before
    report = dict(status='pass' if failure is None and unchanged else 'fail', failure=failure,
                  engineUnchanged=unchanged, build=build, fixture=result, watchdog=watch,
                  sourceHashes={str(path.relative_to(ROOT)): sha(path) for path in sources}, output=str(output),
                  scope='Actual pinned XMage casts, costs, UUID target selection, viewer privacy, permission cleanup, '
                        'effective gained/lost abilities, native object-incarnation targets and sixty-creature '
                        'Wrath on GAME threads. Initial resources/zones and cleanup boundary are deterministic. '
                        'No engine edits, acquisition, live GUI-to-engine, WAN or full shuffled-match claim.')
    write_json(output / 'report.json', report)
    write_json(args.report_file, report)
    print('Zone actions ' + report['status'] + '; ' + str(output / 'report.json'))
    if failure:
        print(failure, file=sys.stderr)
    return 0 if report['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
