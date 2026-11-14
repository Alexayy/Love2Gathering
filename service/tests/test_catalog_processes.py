"""Concurrent installed instances reuse a completed index instead of its temp file."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import time
import unittest

SERVICE = Path(__file__).resolve().parents[1]


class CatalogProcessTests(unittest.TestCase):
    def test_two_processes_build_one_complete_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp);source = root / 'cards.jsonl'
            source.write_text(json.dumps({'object':'card','id':'printing','oracle_id':'oracle','name':'Concurrent Card','lang':'en','type_line':'Artifact','colors':[],'color_identity':[],'legalities':{'modern':'legal'}})+'\n')
            code = '''import sys,time
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from catalog import Catalog
original=Catalog.build
def slow(self):
 with open(sys.argv[4],'a') as trace:trace.write('build\\n')
 time.sleep(.4)
 return original(self)
Catalog.build=slow
c=Catalog(Path(sys.argv[2]),Path(sys.argv[3]));c.ensure()
assert c.status()['state']=='ready',c.status()
assert c.search()['total']==1
'''
            command=[sys.executable,'-c',code,str(SERVICE),str(source),str(root/'catalog.sqlite'),str(root/'builds.txt')]
            first=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            second=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            for process in (first,second):
                output,error=process.communicate(timeout=15)
                self.assertEqual(process.returncode,0,(output,error))
            self.assertEqual((root/'builds.txt').read_text(),'build\n')
            self.assertFalse((root/'catalog.building').exists())


if __name__=='__main__':unittest.main()
