"""Fake-GitHub promotion selection; package/hash integrity has its own publisher suite."""
from copy import deepcopy
import importlib.util
import io
import os
from pathlib import Path
import unittest
from unittest.mock import patch

SPEC=importlib.util.spec_from_file_location('latest_promoter',Path(__file__).with_name('promote-latest.py'))
promoter=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(promoter)
P=promoter.PUBLISHER


def release(number,**changes):
    return {'id':number,'tag_name':f'v2026.11.15.{number}','target_commitish':f'{number:040x}',
            'draft':False,'prerelease':False,'html_url':'https://github.com/'+P.REPOSITORY+'/releases/tag/'+f'v2026.11.15.{number}'}|changes


class FakeGitHub:
    def __init__(self,releases,*,latest=None,pages=None):
        self.releases=deepcopy(releases);self.latest=deepcopy(latest);self.pages=pages;self.commands=[];self.calls=[]
    def api(self,path,*args):
        self.calls.append(path);prefix='repos/'+P.REPOSITORY
        if path.startswith(prefix+'/releases?'):
            page=int(path.rsplit('=',1)[1])
            return deepcopy(self.pages[page-1]if self.pages is not None else self.releases)
        if path==prefix+'/releases/latest':
            if self.latest is None:raise P.NotFound('404')
            return deepcopy(self.latest)
        if path.startswith(prefix+'/releases/tags/'):
            tag=path.split('/releases/tags/',1)[1]
            return deepcopy(next(r for r in self.releases if r['tag_name']==tag))
        if path.startswith(prefix+'/git/ref/tags/'):
            tag=path.split('/git/ref/tags/',1)[1]
            return {'object':{'type':'commit','sha':next(r for r in self.releases if r['tag_name']==tag)['target_commitish']}}
        raise AssertionError('Unexpected read '+path)
    def command(self,*args):
        self.commands.append(args)
        assert args[:2]==('release','edit')and'--latest=true'in args
        selected=next(r for r in self.releases if r['tag_name']==args[2])
        assert selected['draft']is False and selected['prerelease']is False
        self.latest=deepcopy(selected);return''


class PromotionTests(unittest.TestCase):
    def test_old_completion_promotes_highest_published_version_and_retry_is_read_only(self):
        gh=FakeGitHub([release(42),release(43)],latest=release(41))
        with patch.object(P,'check_published',return_value=True)as verify:
            result=promoter.promote(gh)
            self.assertEqual(result['tag'],'v2026.11.15.43');self.assertTrue(result['changed'])
            verify.assert_called_once_with(gh,'2026.11.15.43','v2026.11.15.43',f'{43:040x}','stable','master')
            self.assertEqual(gh.commands[0][2],'v2026.11.15.43')
            before=deepcopy(gh.commands);self.assertFalse(promoter.promote(gh)['changed']);self.assertEqual(gh.commands,before)

    def test_four_part_numeric_order_is_used_without_semver_or_text_order_assumptions(self):
        gh=FakeGitHub([release(99),release(100),release(9)])
        with patch.object(P,'check_published',return_value=True):self.assertEqual(promoter.promote(gh)['tag'],'v2026.11.15.100')

    def test_development_prerelease_draft_and_unrelated_tags_are_not_candidates(self):
        gh=FakeGitHub([release(42),release(99,prerelease=True),release(100,draft=True),
                      release(101,tag_name='DEV-2026.11.15.101-1-'+'a'*12),release(102,tag_name='v2026.11.15')])
        with patch.object(P,'check_published',return_value=True):self.assertEqual(promoter.promote(gh)['tag'],'v2026.11.15.42')

    def test_missing_or_foreign_highest_release_never_falls_back_or_mutates(self):
        for validation in (False,P.ReleaseError('manifest mismatch')):
            gh=FakeGitHub([release(42),release(43)])
            options={'side_effect':validation}if isinstance(validation,Exception)else{'return_value':validation}
            with patch.object(P,'check_published',**options),self.assertRaises(P.ReleaseError):promoter.promote(gh)
            self.assertEqual(gh.commands,[])
        gh=FakeGitHub([release(42),release(43,target_commitish='master')])
        with patch.object(P,'check_published',side_effect=AssertionError('Unbound commit reached verifier')),self.assertRaises(P.ReleaseError):promoter.promote(gh)
        self.assertEqual(gh.commands,[])

    def test_all_bounded_pages_are_scanned_and_exceeding_bound_fails_closed(self):
        ignored=[release(i+1,prerelease=True)for i in range(100)]
        gh=FakeGitHub([release(42),release(100)],pages=[ignored,[release(42),release(100)]])
        with patch.object(P,'check_published',return_value=True):self.assertEqual(promoter.promote(gh)['tag'],'v2026.11.15.100')
        gh=FakeGitHub([],pages=[ignored]*promoter.MAX_PAGES)
        with self.assertRaisesRegex(P.ReleaseError,'scan bound'):promoter.promote(gh)
        self.assertEqual(gh.commands,[])

    def test_newer_existing_latest_blocks_a_stale_listing(self):
        gh=FakeGitHub([release(42)],latest=release(43))
        with patch.object(P,'check_published',return_value=True),self.assertRaisesRegex(P.ReleaseError,'move backward'):promoter.promote(gh)
        self.assertEqual(gh.commands,[])

    def test_entrypoint_rejects_development_or_foreign_repository_before_network(self):
        for repo,ref in [(P.REPOSITORY,'refs/heads/development'),('foreign/repo','refs/heads/master')]:
            with patch.dict(os.environ,{'GITHUB_REPOSITORY':repo,'GITHUB_REF':ref,'GH_TOKEN':'synthetic-fixture'},clear=True), \
                 patch.object(P,'GitHub',side_effect=AssertionError('Unentitled network use')),patch('sys.stderr',io.StringIO()),self.assertRaises(SystemExit):promoter.main([])


if __name__=='__main__':unittest.main()
