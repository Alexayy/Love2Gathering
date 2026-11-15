"""Regression checks for diagnostic aggregation, never native rules assertions."""
import json
from pathlib import Path
import tempfile
import os
import signal
import sys
import unittest
from unittest.mock import patch
from . import harness
from .production import CASES


class AggregationTest(unittest.TestCase):
    def test_child_failure_cannot_be_hidden_by_other_production_completions(self):
        value={'minimumCompletedMet':True,'results':[{'status':'pass'}for _ in CASES]}
        self.assertEqual(harness.scope_status(value,{'status':'pass'},production=True),'pass')
        value['results'][2]['status']='budget_exceeded'
        self.assertEqual(harness.scope_status(value,{'status':'pass'},production=True),'budget_exceeded')
        self.assertEqual(harness.scope_status({'status':'pass'},{'status':'budget_exceeded'}),'budget_exceeded')
        self.assertEqual(harness.scope_status(None,{'status':'pass'}),'fail')

    def test_partial_production_is_not_a_success(self):
        self.assertEqual(harness.scope_status({'minimumCompletedMet':True,'results':[{'status':'pass'}]},production=True),'fail')

    def test_child_declared_budget_is_distinct_from_external_watchdog_failure(self):
        watch={'status':'fail','exitCode':1,'ownedProcessTerminated':True,'watchdogReason':None}
        self.assertEqual(harness.scope_status({'status':'budget_exceeded'},watch),'budget_exceeded')
        watch['watchdogReason']='descendants_survived_parent'
        self.assertEqual(harness.scope_status({'status':'budget_exceeded'},watch),'fail')

    def run_case(self,*,native,watch,projection=None,cleanup=None,identifier='diagnostic-case'):
        with tempfile.TemporaryDirectory(prefix='love2gathering-mechanics-test-harness-')as tmp:
            root=Path(tmp)
            class Process:
                def __init__(self,command,directory,**kw):
                    harness.write_json(directory/'result.json',native)
                    if projection is not None:(directory/'projection.json').write_bytes(projection)
                    if cleanup is not None:harness.write_json(directory/'cleanup.json',cleanup)
                def wait(self,*args,**kw):return watch
            spec={'id':identifier,'fixtureClass':'love2gathering.Diagnostic','budgets':{}}
            with patch.object(harness,'OwnedProcess',Process):
                return harness.run_case(spec,1,root,{}, {'classpath':'fixture','sourceHashes':{}},{})

    def test_malformed_projection_preserves_watchdog_failure_and_evidence(self):
        row=self.run_case(native={},watch={'status':'budget_exceeded'},projection=b'{partial')
        self.assertEqual(row['status'],'budget_exceeded')
        self.assertIn('projectionInspectionError',row['metrics'])

    def test_unterminated_native_decision_overrides_early_pass(self):
        row=self.run_case(native={'status':'pass'},watch={'status':'pass'},cleanup={'gameThreadAlive':True})
        self.assertEqual(row['status'],'hang_suspected')

    def test_upstream_classification_does_not_silence_failed_expectation(self):
        row=self.run_case(native={'status':'fail'},watch={'status':'fail'},identifier='adv-prevent-unpreventable-banefire')
        self.assertEqual(row['status'],'fail')
        self.assertEqual(row['findingClassification'],'suspected_upstream')

    def test_sigterm_runs_cleanup_and_retains_an_interrupted_report(self):
        with tempfile.TemporaryDirectory(prefix='love2gathering-mechanics-test-main-')as tmp:
            root=Path(tmp);harness.write_json(root/'baseline.json',{})
            closed=[];prior=signal.getsignal(signal.SIGTERM)
            class Services:
                def __init__(self,*a):pass
                def start(self):
                    from .runtime import OwnedProcess,isolated_env
                    self.child=OwnedProcess([sys.executable,'-c','import time;time.sleep(60)'],root/'actual-owned-child',env=isolated_env(root/'actual-owned-child'))
                    os.kill(os.getpid(),signal.SIGTERM)
                def close(self):self.child.stop();closed.append(not self.child.owns())
            class Process:
                def __init__(self,command,directory,**kw):harness.write_json(directory/'result.json',{'decks':[]})
                def wait(self,*a,**kw):return{'status':'pass'}
            patches=[patch.object(harness,'manifests',return_value=[]),patch.object(harness,'generate',return_value={'missingMetadata':[],'missingNativeMap':[],'decks':[],'metadata':'fixture'}),patch.object(harness,'build_bridge',return_value={'jarSha256':'fixture'}),patch.object(harness,'compile_fixtures',return_value={'sourceHashes':{},'classpath':'fixture'}),patch.object(harness,'watchdog_selftest'),patch.object(harness,'Services',Services),patch.object(harness,'OwnedProcess',Process),patch.object(harness,'verify_engine',return_value={'passed':True})]
            try:
                for item in patches:item.start()
                self.assertEqual(harness.main(['--mode','full','--run-dir',tmp]),1)
                report=json.loads(next((root/'executions').glob('*/results.json')).read_text())
                self.assertTrue(report['interrupted']);self.assertEqual(closed,[True]);self.assertEqual(signal.getsignal(signal.SIGTERM),prior)
            finally:
                for item in reversed(patches):item.stop()
                harness.RUN_CANCELLED.clear()


if __name__=='__main__':unittest.main()
