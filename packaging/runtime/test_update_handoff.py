"""Deferred updater contract and real isolated Linux installer replacement."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent;PROJECT=HERE.parents[1]
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
handoff=module('update_handoff',HERE/'update_handoff.py')
installer=module('update_linux_installer',PROJECT/'packaging/linux/installer.py')
builder=module('update_package_builder',PROJECT/'packaging/build.py')
OLD='2026.11.17.1';NEW='2026.11.18.2'
def release(version):return dict(applicationId=handoff.APP_ID,version=version,channel='development',sourceRevision='a'*40,tag='DEV-'+version+'-1-'+'a'*12,builtAtUTC='2026-11-18T10:00:00Z')
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

class UpdateHandoffTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='love2gathering-update-handoff-');self.base=Path(self.tmp.name)
        self.root=self.base/'Games with spaces 100% $value'/'Love2Gathering';self.root.mkdir(parents=True)
        self.session=self.base/'session';self.session.mkdir();(self.session/'updates').mkdir()
        (self.root/'release.json').write_text(json.dumps(release(OLD)))
        (self.root/'update-installation.json').write_text(json.dumps({'method':'linux-run'}))
        self.context_path=handoff.create_context(self.root,self.session,{})
        self.context=handoff.document(self.context_path)
        self.artifact=self.session/'updates'/('Love2Gathering-'+NEW+'-linux-x86_64.run');self.artifact.write_bytes(b'verified installer fixture')
        self.job={k:self.context[k]for k in('token','root','method','channel')}
        self.job.update(schema=1,installerPath=str(self.artifact),checksum=sha(self.artifact),expectedSize=self.artifact.stat().st_size,version=NEW,tag=release(NEW)['tag'],revision=release(NEW)['sourceRevision'])
        self.identify()
    def tearDown(self):self.tmp.cleanup()
    def identify(self):self.job['candidateId']=hashlib.sha256((self.job['tag']+'\n'+Path(self.job['installerPath']).name+'\n'+str(self.job['expectedSize'])+'\n'+self.job['checksum']).encode()).hexdigest()
    def plan(self):
        path=self.session/'update-plan.json'
        handoff.atomic_json(path,dict(context=self.context,job=self.job,parentPid=os.getpid(),parentIdentity='a-dead-parent'))
        return path
    def test_context_is_explicit_installed_and_outside_payload(self):
        self.assertEqual(self.context['root'],str(self.root));self.assertNotEqual(self.context['token'],'')
        self.assertEqual(handoff.installation_method(self.root,{'FLATPAK_ID':handoff.APP_ID}),'flatpak')
        (self.root/'update-installation.json').unlink();self.assertIsNone(handoff.create_context(self.root,self.session,{}))
        with self.assertRaises(ValueError):handoff.create_context(self.root,self.root/'session',{})
    def test_artifact_identity_hash_size_and_candidate_paths_are_rechecked(self):
        self.assertEqual(handoff.validate_job(self.context,self.job),self.artifact)
        for key,value in [('token','wrong'),('root',str(self.base)),('checksum','0'*64),('expectedSize',1),('method','deb'),('installerPath',str(self.base/'outside.run')),('tag','DEV-'+NEW),('version','2026.02.30.1'),('version','2026.11.18.65536'),('version',OLD),('revision','b'*40),('candidateId','0'*64)]:
            with self.subTest(key=key),self.assertRaises(ValueError):handoff.validate_job(self.context,dict(self.job,**{key:value}))
        self.artifact.write_bytes(b'tampered installer fixture')
        with self.assertRaises(ValueError):handoff.validate_job(self.context,self.job)
    def test_symlink_installer_is_not_followed(self):
        target=self.base/'outside';self.artifact.rename(target);self.artifact.symlink_to(target)
        with self.assertRaises(ValueError):handoff.validate_job(self.context,self.job)
    def test_another_completed_installation_invalidates_the_old_context(self):
        (self.root/'release.json').write_text(json.dumps(release(NEW)))
        with self.assertRaises(ValueError):handoff.validate_job(self.context,self.job)
    def test_owned_flatpak_host_context_retains_its_private_session(self):
        context=dict(self.context,method='flatpak',externalHost=True)
        handoff.atomic_json(self.context_path,context);env={'FLATPAK_ID':handoff.APP_ID,'LOVE2GATHERING_FLATPAK_UPDATE_CONTEXT':str(self.context_path)}
        self.assertEqual(handoff.create_context(self.root,self.base/'other-session',env),self.context_path)
        altered=dict(context,revision='b'*40);handoff.atomic_json(self.context_path,altered)
        with self.assertRaises(ValueError):handoff.create_context(self.root,self.base/'other-session',env)
    def test_flatpak_host_request_is_left_for_only_the_owned_outer_coordinator(self):
        context=dict(self.context,method='flatpak',externalHost=True);handoff.atomic_json(self.context_path,context)
        renamed=self.artifact.with_name('Love2Gathering-'+NEW+'-x86_64.flatpak');self.artifact.rename(renamed)
        self.job.update(method='flatpak',installerPath=str(renamed));self.identify();handoff.atomic_json(context['requestPath'],self.job)
        calls=[];env={'FLATPAK_ID':handoff.APP_ID,'LOVE2GATHERING_FLATPAK_UPDATE_CONTEXT':str(self.context_path)}
        with patch.dict(os.environ,env):self.assertTrue(handoff.prepare_handoff(self.context_path,spawn=lambda *a,**kw:calls.append(a)))
        self.assertFalse(calls);self.assertTrue(Path(context['requestPath']).is_file());self.assertFalse((self.session/'update-helper.py').exists())
    def test_commands_do_not_use_a_shell_and_preserve_selected_prefix(self):
        self.assertEqual(handoff.install_command(self.context,self.job),[str(self.artifact),'--prefix',str(self.root),'--yes'])
        job=dict(self.job,method='windows-setup',installerPath='C:\\Updates with spaces\\setup.exe')
        command=handoff.install_command(self.context,job,windows=True)
        self.assertIn(' /D='+str(self.root),command);self.assertNotIn('cmd.exe',command)
        with self.assertRaises(ValueError):handoff.install_command(dict(self.context,root='C:\\bad"folder'),job,windows=True)
        which=lambda name:'/usr/bin/'+name
        rpm=handoff.install_command(self.context,dict(self.job,method='rpm'),which=which)
        self.assertEqual(rpm[:5],['/usr/bin/pkexec','/usr/bin/rpm','--upgrade','--prefix',str(self.root)])
        flatpak=handoff.install_command(self.context,dict(self.job,method='flatpak'),which=which)
        self.assertEqual(flatpak,['/usr/bin/xdg-open',str(self.artifact)])
    def test_prepare_copies_helper_outside_root_and_retires_request(self):
        handoff.atomic_json(self.context['requestPath'],self.job);launched=[]
        self.assertTrue(handoff.prepare_handoff(self.context_path,spawn=lambda *args,**kwargs:launched.append((args,kwargs))))
        self.assertTrue((self.session/'update-helper.py').is_file());self.assertTrue((self.session/'update-request.accepted.json').is_file())
        self.assertEqual(launched[0][0][0][1],str(self.session/'update-helper.py'))
        self.assertTrue(launched[0][1]['start_new_session']);self.assertNotIn('shell',launched[0][1])
        plan=handoff.document(self.session/'update-plan.json');self.assertEqual(plan['parentIdentity'],handoff.process_identity(os.getpid()))
    def test_live_exact_parent_prevents_installer_execution(self):
        calls=[]
        with patch.object(handoff,'process_identity',return_value='a-dead-parent'),self.assertRaises(ValueError):
            handoff.apply_plan(self.plan(),run=lambda *a,**kw:calls.append(a),timeout=0)
        self.assertFalse(calls)
    def test_failed_or_unperformed_install_never_restarts_or_reports_success(self):
        launched=[]
        for code in(1,0):
            with self.subTest(code=code),self.assertRaises(ValueError):
                handoff.apply_plan(self.plan(),run=lambda *a,**kw:subprocess.CompletedProcess(a,code),spawn=lambda *a,**kw:launched.append(a))
        self.assertFalse(launched);self.assertFalse((self.session/'update-result.json').exists())
    def test_success_requires_selected_release_before_restart(self):
        executable=self.root/'love2gathering';executable.write_text('fixture');launched=[]
        def install(*args,**kwargs):
            (self.root/'release.json').write_text(json.dumps(release(NEW)));return subprocess.CompletedProcess(args,0)
        result=handoff.apply_plan(self.plan(),run=install,spawn=lambda *a,**kw:launched.append(a))
        self.assertEqual(result['state'],'installed');self.assertEqual(launched[0][0],[str(executable)])
    def test_flatpak_handoff_does_not_claim_completed_installation(self):
        self.job['method']='flatpak';self.context['method']='flatpak'
        new=self.artifact.with_name('Love2Gathering-'+NEW+'-x86_64.flatpak');self.artifact.rename(new);self.job['installerPath']=str(new)
        self.identify()
        with patch.object(handoff,'install_command',return_value=['desktop-portal',str(new)]):
            result=handoff.apply_plan(self.plan(),run=lambda *a,**kw:subprocess.CompletedProcess(a,0))
        self.assertEqual(result['state'],'system_installer_opened')
    def test_real_deferred_linux_installer_replaces_whole_package_and_preserves_sql(self):
        home=self.base/'home';home.mkdir();probe=self.base/'restarted'
        env=dict(os.environ,HOME=str(home),XDG_DATA_HOME=str(home/'data'),XDG_CONFIG_HOME=str(home/'config'),LOVE2GATHERING_UPDATE_PROBE=str(probe),PYTHONDONTWRITEBYTECODE='1')
        def payload(version,extra):
            path=self.base/('payload-'+version);(path/'runtime/java/bin').mkdir(parents=True);(path/'bridge/target/lib').mkdir(parents=True);(path/'share/icons').mkdir(parents=True)
            java=path/'runtime/java/bin/java';java.write_text('#!/bin/sh\nprintf \'openjdk version "21.0.1"\\n\'\n');java.chmod(0o755)
            app=path/'love2gathering';app.write_text('#!/bin/sh\nprintf restarted > "$LOVE2GATHERING_UPDATE_PROBE"\n');app.chmod(0o755)
            (path/'app.love').write_text('client-'+version);(path/'bridge/target/xmage-bridge.jar').write_text('bridge-'+version)
            (path/'bridge/target/lib'/extra).write_text(version);(path/'release.json').write_text(json.dumps(release(version)));(path/'share/icons/love2gathering.png').write_bytes(b'fixture-icon')
            return path
        # The root exists from setup; initial installer accepts only an empty folder.
        for name in('release.json','update-installation.json'):(self.root/name).unlink()
        first=payload(OLD,'obsolete.jar')
        with patch.dict(os.environ,env,clear=True),contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(installer.main(['--payload',str(first),'--prefix',str(self.root),'--yes']),0)
        inside=self.root/'my-decks.sqlite';outside=self.base/'images.sqlite'
        for p in(inside,outside):
            with sqlite3.connect(p)as db:db.execute('CREATE TABLE keep(value TEXT)');db.execute("INSERT INTO keep VALUES('saved')")
        before={str(p):sha(p)for p in(inside,outside)}
        self.artifact.unlink();second=payload(NEW,'new.jar')
        with patch.object(builder,'VERSION',NEW):archive,run=builder.portable(self.artifact.parent,second)
        self.assertEqual(run,self.artifact)
        self.job.update(checksum=sha(run),expectedSize=run.stat().st_size)
        self.identify()
        handoff.atomic_json(self.context['requestPath'],self.job)
        # This real supervisor child exits before its independent helper starts
        # the real .run installer. No application/user process is signalled.
        script='import importlib.util,sys;s=importlib.util.spec_from_file_location("handoff",sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.prepare_handoff(sys.argv[2])'
        parent=subprocess.run([sys.executable,'-c',script,str(HERE/'update_handoff.py'),str(self.context_path)],env=env,capture_output=True,text=True,timeout=15)
        self.assertEqual(parent.returncode,0,parent.stderr)
        until=time.monotonic()+30;result=self.session/'update-result.json'
        while not result.exists()and time.monotonic()<until:time.sleep(.1)
        self.assertTrue(result.exists(),(self.session/'update.log').read_text())
        self.assertEqual(handoff.document(result)['state'],'installed',(self.session/'update.log').read_text())
        self.assertEqual((self.root/'app.love').read_text(),'client-'+NEW);self.assertEqual((self.root/'bridge/target/xmage-bridge.jar').read_text(),'bridge-'+NEW)
        self.assertFalse((self.root/'bridge/target/lib/obsolete.jar').exists());self.assertTrue((self.root/'bridge/target/lib/new.jar').exists())
        self.assertTrue(probe.exists());self.assertEqual({str(p):sha(p)for p in(inside,outside)},before)

if __name__=='__main__':unittest.main(verbosity=2)
