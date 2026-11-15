"""Lightweight ownership and watchdog regression tests; no engine or user services."""
import ctypes
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from mechanics import runtime


@unittest.skipUnless(sys.platform=='linux'and Path('/proc/self/stat').exists(),'Linux /proc ownership diagnostics')
class OwnedProcessTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Reap only these tests' deliberately orphaned descendants ourselves.
        cls.libc=ctypes.CDLL(None,use_errno=True);old=ctypes.c_int()
        if cls.libc.prctl(37,ctypes.byref(old),0,0,0)!=0:raise unittest.SkipTest('Subreaper unavailable')
        cls.old_subreaper=old.value
        if cls.libc.prctl(36,1,0,0,0)!=0:raise unittest.SkipTest('Cannot own orphan cleanup')
    @classmethod
    def tearDownClass(cls):cls.libc.prctl(36,cls.old_subreaper,0,0,0)
    def setUp(self):
        runtime.RUN_CANCELLED.clear()
        self.temporary=tempfile.TemporaryDirectory(prefix='love2gathering-mechanics-runtime-');self.root=Path(self.temporary.name);self.owned=[];self.orphan_pids=[]
    def tearDown(self):
        runtime.RUN_CANCELLED.clear()
        for process in reversed(self.owned):process.stop()
        deadline=time.monotonic()+2
        while self.orphan_pids and time.monotonic()<deadline:
            for pid in list(self.orphan_pids):
                try:reaped,_=os.waitpid(pid,os.WNOHANG)
                except ChildProcessError:reaped=pid
                if reaped:self.orphan_pids.remove(pid)
            if self.orphan_pids:time.sleep(.01)
        self.temporary.cleanup()
    def process(self,code,name='process'):
        work=self.root/name
        process=runtime.OwnedProcess([sys.executable,'-c',code],work,env=runtime.isolated_env(work));self.owned.append(process);return process
    def wait_file(self,path):
        deadline=time.monotonic()+3
        while not path.exists()and time.monotonic()<deadline:time.sleep(.01)
        self.assertTrue(path.exists(),'Child did not publish its setup marker')
        return path.read_text()
    def child_script(self,*,parent_exit=False,ignore_term=False,grandchild=False):
        child="import time;time.sleep(60)"
        if grandchild:
            child="import subprocess,sys,time;from pathlib import Path;p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)'],start_new_session=True);Path('grandchild.pid').write_text(str(p.pid));time.sleep(60)"
        if ignore_term:child="import signal;signal.signal(signal.SIGTERM,signal.SIG_IGN);"+child
        root="import subprocess,sys,time;from pathlib import Path;"
        if ignore_term:root+="import signal;signal.signal(signal.SIGTERM,signal.SIG_IGN);"
        root+=f"p=subprocess.Popen([sys.executable,'-c',{child!r}],start_new_session=True);Path('child.pid').write_text(str(p.pid));"
        root+='time.sleep(.05)'if parent_exit else'time.sleep(60)'
        return root
    def assert_dead(self,pid):
        identity=runtime.proc_identity(pid);self.assertTrue(identity is None or identity['state']=='Z',f'Owned PID {pid} survived')
    def test_normal_process_and_next_scenario_still_run(self):
        first=self.process('print("complete")');result=first.wait({'wallSeconds':3})
        self.assertEqual(result['status'],'pass');self.assertTrue(result['ownedProcessTerminated'])
        next_process=self.process('print("next")','next');self.assertEqual(next_process.wait({'wallSeconds':3})['status'],'pass')
    def test_runner_cancellation_stops_child_and_preserves_unrelated_process(self):
        process=self.process('import time;time.sleep(60)')
        unrelated=subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)'],start_new_session=True)
        timer=threading.Timer(.15,runtime.RUN_CANCELLED.set);timer.start()
        try:
            result=process.wait({'wallSeconds':10})
            self.assertEqual(result['watchdogReason'],'runner_cancelled');self.assertEqual(result['status'],'budget_exceeded')
            self.assertTrue(result['ownedProcessTerminated']);self.assertLess(result['wallSeconds'],2);self.assertIsNone(unrelated.poll())
        finally:
            timer.join(timeout=2);runtime.RUN_CANCELLED.clear();unrelated.terminate();unrelated.wait(timeout=3)
    def test_cancellation_already_set_is_bounded_and_clear_allows_next_scenario(self):
        process=self.process('import time;time.sleep(60)');runtime.RUN_CANCELLED.set()
        result=process.wait({'wallSeconds':10});self.assertEqual(result['watchdogReason'],'runner_cancelled');self.assertTrue(result['ownedProcessTerminated'])
        runtime.RUN_CANCELLED.clear();following=self.process('print("after cancellation")','following')
        self.assertEqual(following.wait({'wallSeconds':3})['status'],'pass')
    def test_wall_timeout_terminates_owned_root(self):
        process=self.process('import time;time.sleep(60)');result=process.wait({'wallSeconds':.15})
        self.assertEqual(result['status'],'budget_exceeded');self.assertEqual(result['watchdogReason'],'wall_time');self.assertTrue(result['ownedProcessTerminated']);self.assert_dead(process.process.pid)
    def test_parent_exit_finds_reparented_new_session_child(self):
        process=self.process(self.child_script(parent_exit=True));pid=int(self.wait_file(process.directory/'child.pid'));self.orphan_pids.append(pid)
        process.process.wait(timeout=2);result=process.wait({'wallSeconds':3})
        self.assertEqual(result['watchdogReason'],'descendants_survived_parent');self.assertEqual(result['exitCode'],0);self.assertTrue(result['ownedProcessTerminated']);self.assert_dead(pid)
    def test_stop_discovers_grandchild_sessions_and_preserves_unrelated_process(self):
        process=self.process(self.child_script(grandchild=True));child=int(self.wait_file(process.directory/'child.pid'));grandchild=int(self.wait_file(process.directory/'grandchild.pid'));self.orphan_pids.extend([child,grandchild])
        unrelated=subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)'],start_new_session=True)
        try:
            process.stop();self.assert_dead(child);self.assert_dead(grandchild);self.assertFalse(process.owns());self.assertIsNone(unrelated.poll())
        finally:unrelated.terminate();unrelated.wait(timeout=3)
    def test_ignored_term_escalates_for_root_and_child(self):
        process=self.process(self.child_script(ignore_term=True));child=int(self.wait_file(process.directory/'child.pid'));self.orphan_pids.append(child)
        process.stop();self.assert_dead(process.process.pid);self.assert_dead(child);self.assertTrue(process.log.closed)
    def test_nested_owner_markers_remain_owned_by_outer_runner(self):
        work=self.root/'nested';env=runtime.isolated_env(work)
        code="import time;time.sleep(60)"
        outer=self.process('import time;time.sleep(60)','outer')
        env['LOVE2GATHERING_TEST_OWNER']=outer.owner_token
        nested=runtime.OwnedProcess([sys.executable,'-c',code],work,env=env);self.owned.append(nested)
        self.assertIn(nested.process.pid,{p['pid']for p in outer.alive_members(scan=True)})
        outer.stop();self.assert_dead(nested.process.pid)
    def test_stale_birth_identity_never_receives_signal(self):
        identity=runtime.proc_identity(os.getpid());identity['birthTicks']+=1
        with patch.object(runtime.os,'kill')as kill,patch.object(runtime.signal,'pidfd_send_signal',create=True)as pidfd_signal:
            self.assertFalse(runtime.OwnedProcess._signal_identity(identity,signal.SIGTERM));kill.assert_not_called();pidfd_signal.assert_not_called()
    def test_exception_in_recovery_still_removes_owned_process(self):
        process=self.process('import time;time.sleep(60)')
        with self.assertRaisesRegex(RuntimeError,'injected recovery failure'):
            process.wait({'wallSeconds':.1},recover=lambda:(_ for _ in()).throw(RuntimeError('injected recovery failure')))
        self.assertFalse(process.owns());self.assertTrue(process.log.closed)
    def test_fast_exit_cannot_hide_large_output_from_disk_budget(self):
        process=self.process("from pathlib import Path;Path('payload').write_bytes(b'x'*100000)");process.process.wait(timeout=3)
        result=process.wait({'wallSeconds':3,'diskBytes':10000})
        self.assertEqual(result['watchdogReason'],'disk_bytes');self.assertGreater(result['diskBytes'],100000)
    def test_sibling_output_is_charged_and_overlapping_roots_are_not_double_counted(self):
        sibling=self.root/'sibling';sibling.mkdir();payload=sibling/'payload';payload.write_bytes(b'x'*100000)
        self.assertEqual(runtime.OwnedProcess._disk_size([sibling,payload]),100000)
        process=self.process('import time;time.sleep(60)');result=process.wait({'wallSeconds':3,'diskDirectories':[str(sibling)],'diskBytes':10000})
        self.assertEqual(result['watchdogReason'],'disk_bytes')
    def test_shared_sql_budget_is_distinct_from_runner_disk(self):
        service=self.root/'catalog';service.mkdir();(service/'app.sqlite').write_bytes(b'x'*100000)
        process=self.process('import time;time.sleep(60)');result=process.wait({'wallSeconds':3,'sharedDiskDirectories':[str(service)],'sharedDiskBytes':10000})
        self.assertEqual(result['watchdogReason'],'shared_service_disk_bytes');self.assertGreaterEqual(result['sharedServiceDiskBytes'],100000)
    def test_external_service_rss_is_counted_without_taking_cleanup_ownership(self):
        external=self.process("import time;payload=bytearray(32*1024*1024);from pathlib import Path;Path('ready').write_text('ready');time.sleep(60)",'service');self.wait_file(external.directory/'ready')
        process=self.process('import time;time.sleep(60)');result=process.wait({'wallSeconds':3,'externalOwnedPids':[external.identity],'rssBytes':25*1024*1024})
        self.assertEqual(result['watchdogReason'],'rss');self.assertTrue(external.owns(),'Measurement does not authorize service termination')
    def test_listener_identity_cannot_alias_another_process_port(self):
        process=self.process('import time;time.sleep(60)')
        with socket.socket()as listener:
            listener.bind(('127.0.0.1',0));listener.listen();port=listener.getsockname()[1]
            self.assertTrue(runtime.owns_listener(runtime.proc_identity(os.getpid()),port));self.assertFalse(runtime.owns_listener(process.identity,port))


class ServicesOwnershipTest(unittest.TestCase):
    def setUp(self):self.temporary=tempfile.TemporaryDirectory(prefix='love2gathering-mechanics-services-');self.root=Path(self.temporary.name)
    def tearDown(self):self.temporary.cleanup()
    def fake_process(self,pid=123):
        process=Mock();process.identity={'pid':pid,'birthTicks':100};process.owns.return_value=False;process.process.poll.return_value=None;process.directory=self.root/'fake';return process
    def test_partial_start_closes_previous_services_without_masking_failure(self):
        services=runtime.Services(self.root,'/tmp/metadata.jsonl');catalog=self.fake_process();services.processes['catalog']=catalog
        with patch.object(services,'_start',side_effect=ValueError('injected startup failure')):
            with self.assertRaisesRegex(ValueError,'injected startup failure'):services.start()
        catalog.stop.assert_called_once();self.assertTrue(json.loads((self.root/'cleanup.json').read_text())['catalog']['terminated'])
    def test_cleanup_attempts_every_service_after_one_stop_fails(self):
        services=runtime.Services(self.root,'/tmp/metadata.jsonl');catalog=self.fake_process(1);engine=self.fake_process(2);engine.stop.side_effect=RuntimeError('injected failed stop');services.processes={'catalog':catalog,'engine':engine}
        with self.assertRaisesRegex(RuntimeError,'cleanup incomplete'):services.close()
        engine.stop.assert_called_once();catalog.stop.assert_called_once();self.assertIn('injected failed stop',json.loads((self.root/'cleanup.json').read_text())['engine']['error'])
    def test_cleanup_error_keeps_the_original_startup_exception(self):
        services=runtime.Services(self.root,'/tmp/metadata.jsonl')
        with patch.object(services,'_start',side_effect=ValueError('original startup failure')),patch.object(services,'close',side_effect=RuntimeError('cleanup failure')):
            with self.assertRaisesRegex(ValueError,'original startup failure')as result:services.start()
        self.assertIn('cleanup failure',' '.join(result.exception.__notes__))
    def test_port_collision_does_not_probe_or_accept_foreign_health(self):
        services=runtime.Services(self.root,'/tmp/metadata.jsonl');process=self.fake_process()
        with patch.object(runtime,'OwnedProcess',return_value=process),patch.object(runtime,'owns_listener',return_value=False),patch.object(runtime,'http_json')as health,patch.object(runtime.time,'monotonic',side_effect=[0,0,46]),patch.object(runtime.time,'sleep'):
            with self.assertRaisesRegex(RuntimeError,'readiness timed out'):services.launch('engine',['fake'],{},17371)
        health.assert_not_called();self.assertIs(services.processes['engine'],process)
    def test_catalog_health_must_match_isolated_storage(self):
        services=runtime.Services(self.root,'/tmp/metadata.jsonl');process=self.fake_process()
        with patch.object(runtime,'OwnedProcess',return_value=process),patch.object(runtime,'owns_listener',return_value=True),patch.object(runtime,'http_json',return_value={'ready':True,'storage':{'dataDirectory':'/user/data','cacheDirectory':'/user/cache'}}),patch.object(runtime.time,'monotonic',side_effect=[0,0,46]),patch.object(runtime.time,'sleep'):
            with self.assertRaisesRegex(RuntimeError,'storage identity'):services.launch('catalog',['fake'],{'LOVE2GATHERING_DATA_DIR':'/tmp/owned/data','LOVE2GATHERING_CACHE_DIR':'/tmp/owned/cache'},17370)

if __name__=='__main__':unittest.main()
