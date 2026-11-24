#!/usr/bin/env python3
"""Offline native Flatpak host-update acceptance using two tiny owned bundles.

Requires the already installed Freedesktop 25.08 SDK/runtime. No runtime, metadata,
card images or release assets are acquired. GitHub metadata is a deterministic
fixture; the package bytes, sandbox, installed prefix, update and restart are real.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
APP_ID = 'io.github.Alexayy.Love2Gathering'


APPLICATION = r'''import hashlib,io,json,pathlib,sys,time
root=pathlib.Path('/app/share/Love2Gathering');sys.path.insert(0,str(root/'service'))
from updates import UpdateManager,API,RELEASE_PAGE
probe,next_bundle=sys.argv[1:3];probe=pathlib.Path(probe);bundle=pathlib.Path(next_bundle)
release=json.loads((root/'release.json').read_text());ctx=pathlib.Path(__import__('os').environ['LOVE2GATHERING_FLATPAK_UPDATE_CONTEXT'])
with probe.open('a')as out:out.write(json.dumps({'version':release['version'],'contextVersion':json.loads(ctx.read_text())['version'],'sandbox':__import__('os').environ.get('FLATPAK_ID')})+'\n')
if release['version']=='2026.11.17.10':
 value='2026.11.18.11';tag='v'+value;name='Love2Gathering-'+value+'-x86_64.flatpak';blob=bundle.read_bytes();sums=(hashlib.sha256(blob).hexdigest()+'  '+name+'\n').encode()
 base=RELEASE_PAGE+'/download/'+tag+'/'
 remote={'tag_name':tag,'target_commitish':'b'*40,'draft':False,'prerelease':False,'html_url':RELEASE_PAGE+'/tag/'+tag,'published_at':'2026-11-18T00:00:00Z','body':'Native offline fixture','assets':[{'name':name,'size':len(blob),'state':'uploaded','browser_download_url':base+name},{'name':'SHA256SUMS','size':len(sums),'state':'uploaded','browser_download_url':base+'SHA256SUMS'}]}
 def fetch(url):return io.BytesIO(json.dumps(remote).encode()if url==API+'/latest'else sums if url==base+'SHA256SUMS'else blob if url==base+name else b'')
 class EmptyCredentials:
  def get(self):return ''
  def set(self,token):raise AssertionError('Native fixture never configures credentials')
 manager=UpdateManager(ctx,fetcher=fetch,credentials=EmptyCredentials());assert manager.status()['supported'],manager.status();assert manager.status()['automaticInstall'],manager.status()
 manager.check();manager.thread.join(10);assert manager.status()['state']=='available',manager.status();candidate=manager.status()['candidate']
 manager.download(candidate['id']);manager.thread.join(10);assert manager.status()['state']=='ready',manager.status();manager.apply(candidate['id']);assert manager.status()['state']=='apply_requested'
'''


def main():
    flatpak = shutil.which('flatpak')
    if not flatpak: raise RuntimeError('Flatpak is not installed')
    base = Path(tempfile.mkdtemp(prefix='love2gathering-flatpak-native-host-'))
    home = base / 'home'; home.mkdir()
    prefix = base / 'Games with spaces 100 percent'
    env = dict(os.environ, HOME=str(home), XDG_DATA_HOME=str(base / 'data'), XDG_CONFIG_HOME=str(base / 'config'),
               XDG_CACHE_HOME=str(base / 'cache'), FLATPAK_USER_DIR=str(prefix), PYTHONDONTWRITEBYTECODE='1')
    log = (base / 'native.log').open('w')
    def run(*command, **options):
        print('NATIVE FLATPAK HOST: ' + command[0] + ' ' + command[1], flush=True)
        return subprocess.run(command, env=env, check=True, stdout=log, stderr=subprocess.STDOUT, timeout=options.pop('timeout', 60), **options)
    report = dict(passed=False, output=str(base), scope=__doc__.strip(), userStoreModified=False, acquisition=False)
    try:
        for ref in ('org.freedesktop.Sdk', 'org.freedesktop.Platform'):
            run(flatpak, '--system', 'info', ref + '//25.08')
        repo = base / 'bundle-repo'; bundles = []
        for version, revision in (('2026.11.17.10', 'a' * 40), ('2026.11.18.11', 'b' * 40)):
            work = base / ('build-' + version)
            run(flatpak, 'build-init', '--arch=x86_64', str(work), APP_ID, 'org.freedesktop.Sdk', 'org.freedesktop.Platform', '25.08')
            app = work / 'files/share/Love2Gathering'; (app / 'service').mkdir(parents=True); (app / 'host-tools').mkdir()
            release = dict(applicationId=APP_ID, version=version, sourceRevision=revision, channel='stable',
                           tag='v' + version, builtAtUTC='2026-11-18T00:00:00Z')
            (app / 'release.json').write_text(json.dumps(release)); (app / 'fixture.py').write_text(APPLICATION)
            shutil.copy2(PROJECT / 'service/updates.py', app / 'service/updates.py')
            for name in ('install-flatpak.py', 'update-host.py'): shutil.copy2(HERE / name, app / 'host-tools' / name)
            (work / 'files/bin').mkdir(); launcher = work / 'files/bin/love2gathering'
            launcher.write_text('#!/bin/sh\nexec python3 /app/share/Love2Gathering/fixture.py "$@"\n'); launcher.chmod(0o755)
            run(flatpak, 'build-finish', '--command=love2gathering', '--filesystem=' + str(base), str(work))
            run(flatpak, 'build-export', str(repo), str(work), 'stable')
            bundle = base / ('Love2Gathering-' + version + '-x86_64.flatpak')
            run(flatpak, 'build-bundle', str(repo), str(bundle), APP_ID, 'stable'); bundles.append(bundle)
        # A disabled existing local remote prevents the installer from acquiring
        # a remote descriptor. The required SDK/runtime were checked above.
        run(flatpak, '--user', 'remote-add', '--if-not-exists', '--no-gpg-verify', '--disable', 'flathub', repo.as_uri())
        run(sys.executable, str(HERE / 'install-flatpak.py'), str(bundles[0]), '--prefix', str(prefix))
        original = subprocess.check_output([flatpak, '--user', 'info', '--show-commit', APP_ID], env=env, text=True).strip()
        saves = home / '.var/app' / APP_ID / 'data/app.sqlite'; saves.parent.mkdir(parents=True, exist_ok=True); saves.write_bytes(b'preserve offline saves/cache/replays')
        probe = base / 'launches.jsonl'
        run(str(prefix / 'love2gathering'), str(probe), str(bundles[1]), timeout=120)
        rows = [json.loads(line) for line in probe.read_text().splitlines()]
        current = subprocess.check_output([flatpak, '--user', 'info', '--show-commit', APP_ID], env=env, text=True).strip()
        assert [row['version'] for row in rows] == ['2026.11.17.10', '2026.11.18.11'], rows
        assert all(row['contextVersion'] == row['version'] and row['sandbox'] == APP_ID for row in rows)
        assert original != current and saves.read_bytes() == b'preserve offline saves/cache/replays'
        results = [json.loads(path.read_text()) for path in (home / '.var/app' / APP_ID / 'data/love2gathering/runtime').glob('host-update-*/update-result.json')]
        assert len(results) == 1 and results[0]['state'] == 'installed' and results[0]['commit'] == current, results
        report.update(passed=True, fromCommit=original, toCommit=current, launches=rows, savesPreserved=True, exactCustomPrefix=True)
    except Exception as error:
        report['failure'] = str(error)
    finally:
        log.close()
        hashes = {str(path.relative_to(PROJECT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in (HERE / 'install-flatpak.py', HERE / 'update-host.py', PROJECT / 'service/updates.py')}
        report['sourceSha256'] = hashes
        (base / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(dict(passed=report['passed'], report=str(base / 'report.json'), failure=report.get('failure'))))
    return 0 if report['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())
