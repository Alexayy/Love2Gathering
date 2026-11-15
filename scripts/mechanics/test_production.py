"""The test driver must not invent legality or silently answer unknown prompts."""
import copy
from pathlib import Path
import sys
import unittest
import gzip
import json
import tempfile
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from mechanics.production import supported_answer,replay_checks,BudgetExceeded,main,CASES,run_production

class ProductionDriverTest(unittest.TestCase):
    def state(self,prompt):
        return {'gameId':'test-game','players':[{'id':'human','human':True,'hand':[{'id':'bolt','name':'Lightning Bolt'},{'id':'mountain','name':'Mountain'}],'battlefield':[{'id':'source','name':'Mountain'}]},{'id':'opponent','human':False,'hand':[]}],'prompt':prompt}
    def choice(self,identifier,response='uuid',value=None):
        c={'id':identifier,'label':identifier,'responseType':response}
        if value is not None:c['value']=value
        return c
    def test_present_empty_actionable_never_plays_visible_card(self):
        p={'id':1,'priority':True,'type':'select','actionable':[],'choices':[self.choice('bolt'),self.choice('done','boolean',True)]}
        self.assertEqual(supported_answer(self.state(p),'burn'),{'type':'boolean','value':True})
    def test_missing_actionable_is_not_an_implicit_all_cards(self):
        p={'id':1,'priority':True,'type':'select','choices':[self.choice('bolt'),self.choice('done','boolean',True)]}
        with self.assertRaisesRegex(AssertionError,'actionable'):supported_answer(self.state(p),'burn')
    def test_offered_playability_is_used_without_a_mana_estimate(self):
        p={'id':1,'priority':True,'type':'select','actionable':['bolt'],'choices':[self.choice('bolt'),self.choice('done','boolean',True)]}
        self.assertEqual(supported_answer(self.state(p),'burn'),{'type':'uuid','value':'bolt'})
    def test_a_non_actionable_mountain_is_not_a_payment_source(self):
        p={'id':1,'type':'play_mana','actionable':[],'choices':[self.choice('source'),self.choice('done','boolean',True)]}
        with self.assertRaisesRegex(AssertionError,'no offered red payment'):supported_answer(self.state(p),'burn')
    def test_pool_response_does_not_require_card_actionability(self):
        p={'id':1,'type':'play_mana','actionable':[],'choices':[self.choice('mana-R','mana','RED')]}
        self.assertEqual(supported_answer(self.state(p),'burn'),{'type':'mana','value':'RED'})
    def test_unknown_prompt_never_chooses_first_answer(self):
        p={'id':1,'type':'ask','message':'Unknown ability choice','choices':[self.choice('yes','boolean',True),self.choice('no','boolean',False)]}
        with self.assertRaisesRegex(AssertionError,'Unknown production prompt'):supported_answer(self.state(p),'burn')
    def test_unknown_target_never_chooses_first_uuid(self):
        p={'id':1,'type':'pick_target','message':'Unknown target semantics','choices':[self.choice('unrelated')],'actionable':['unrelated']}
        with self.assertRaisesRegex(AssertionError,'Unknown production prompt'):supported_answer(self.state(p),'burn')
    def test_mulligan_keeps_native_false_even_when_yes_comes_first(self):
        p={'id':1,'type':'ask','mulligan':{'handSize':7},'choices':[self.choice('mulligan','boolean',True),self.choice('keep','boolean',False)]}
        self.assertEqual(supported_answer(self.state(p),'pass'),{'type':'boolean','value':False})
    def test_explicit_pass_policy_does_not_cast_an_offered_spell(self):
        p={'id':1,'priority':True,'type':'select','actionable':['bolt'],'choices':[self.choice('bolt'),self.choice('done','boolean',True)]}
        self.assertEqual(supported_answer(self.state(p),'pass'),{'type':'boolean','value':True})
    def test_choice_policy_does_not_mutate_native_projection(self):
        s=self.state({'id':1,'priority':True,'type':'select','actionable':['bolt'],'choices':[self.choice('bolt'),self.choice('done','boolean',True)]});before=copy.deepcopy(s)
        supported_answer(s,'burn');self.assertEqual(s,before)

class ProductionReplayExportTest(unittest.TestCase):
    def test_streamed_archive_is_lossless_and_only_accepted_prompt_inputs_count(self):
        action={'promptId':17,'type':'boolean','value':False}
        events=[{'sequence':0,'type':'frame','data':{'running':True,'players':[{'human':False,'hand':[]}]}},{'sequence':1,'type':'action','data':{'input':{'type':'auto_priority'},'promptId':None}},{'sequence':2,'type':'action','data':{'input':action,'promptId':17}},{'sequence':3,'type':'frame','data':{'running':False,'prompt':None,'players':[{'human':False,'hand':[]}]}}]
        class Catalog:
            def call(self,path,**kwargs):
                return {'events':events,'total':4}if'/events?'in path else {'status':'completed','eventCount':4,'lastSequence':3,'result':{'completed':True}}
        with tempfile.TemporaryDirectory()as directory:
            result=replay_checks(Catalog(),'owned-replay',[action],Path(directory),completed=True)
            with gzip.open(result['archive'],'rt',encoding='utf-8')as source:restored=[json.loads(row)for row in source]
            self.assertEqual(restored,events);self.assertEqual(result['eventCount'],4);self.assertEqual(result['acceptedPromptActions'],1)
    def test_expired_replay_budget_makes_no_catalog_request(self):
        class Catalog:
            def call(self,*args,**kwargs):raise AssertionError('Expired verifier must not send requests')
        with tempfile.TemporaryDirectory()as directory:
            with self.assertRaises(BudgetExceeded):replay_checks(Catalog(),'owned',[],Path(directory),completed=True,verification_seconds=0)
    def test_cli_refuses_success_without_three_native_completions(self):
        summary={'results':[{'status':'pass'}]*len(CASES),'minimumCompletedMet':False,'completedNativeGames':2,'statuses':{'pass':len(CASES)}}
        with patch('mechanics.production.run_production',return_value=summary):
            self.assertEqual(main(['--engine-url','http://127.0.0.1:17401','--catalog-url','http://127.0.0.1:17402','--generation','/tmp/generation.json','--output','/tmp/results']),1)

    def test_distinct_production_cases_keep_deckout_and_both_burn_directions(self):
        self.assertEqual([case[0]for case in CASES],['P01','P02','P03','P06','P04','P05'])
        by_id={case[0]:case[1:]for case in CASES}
        self.assertEqual(by_id['P02'],('burn','control','burn',2))
        self.assertEqual(by_id['P03'],('control','control','pass',2))
        self.assertEqual(by_id['P06'],('control','burn','pass',2))
    def test_minimum_completions_does_not_hide_deckout_budget_failure(self):
        results=[{'status':'budget_exceeded'if case[0]=='P03'else'pass'}for case in CASES]
        summary={'results':results,'minimumCompletedMet':True,'completedNativeGames':3,'statuses':{'pass':5,'budget_exceeded':1}}
        with patch('mechanics.production.run_production',return_value=summary):
            self.assertEqual(main(['--engine-url','http://127.0.0.1:17401','--catalog-url','http://127.0.0.1:17402','--generation','/tmp/generation.json','--output','/tmp/results']),1)
    def test_cli_accepts_all_six_checked_cases(self):
        summary={'results':[{'status':'pass'}for _ in CASES],'minimumCompletedMet':True,'completedNativeGames':4,'statuses':{'pass':6}}
        with patch('mechanics.production.run_production',return_value=summary):
            self.assertEqual(main(['--engine-url','http://127.0.0.1:17401','--catalog-url','http://127.0.0.1:17402','--generation','/tmp/generation.json','--output','/tmp/results']),0)

if __name__=='__main__':unittest.main()
