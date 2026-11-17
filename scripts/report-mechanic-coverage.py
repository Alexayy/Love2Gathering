#!/usr/bin/env python3
"""Read-only presentation vocabulary inventory; no rules, images or user SQL."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata',type=Path)
    parser.add_argument('--output',type=Path,default=ROOT/'tests/mechanic-coverage-report.json')
    args=parser.parse_args()
    classes=[]
    for file in sorted((ROOT/'engine/mage/Mage/src/main/java/mage/abilities/keyword').glob('*.java')):
        if re.search(r'public\s+(?:(?:final|abstract)\s+)?class\s+\w+Ability\b',file.read_text()):
            classes.append({'id':re.sub(r'Ability$','',file.stem),'name':file.stem,'source':'native_keyword_class'})
    keywords=set();cards=0;digest=hashlib.sha256()
    if args.metadata:
        with args.metadata.open('rb')as source:
            for line in source:
                digest.update(line)
                if not line.strip():continue
                card=json.loads(line);cards+=1
                keywords.update(value for value in card.get('keywords',[])if isinstance(value,str))
    observed={'nativeKeywordClasses':classes,'metadataKeywords':[{'id':name,'name':name,'source':'printing_metadata'}for name in sorted(keywords)]}
    lua=shutil.which('lua5.4')or shutil.which('lua')
    if not lua:parser.error('A Lua interpreter is required to inspect the actual runtime registry')
    script="""local FX=require('app.mechanic_fx');local json=require('lib.json');local observed=json.decode(io.read('*a'))
local classes={};for _,row in ipairs(observed.nativeKeywordClasses)do classes[FX.normalize(row.id)]=true end
local groups={nativeKeywordClasses=observed.nativeKeywordClasses,keywordAbilities={},keywordActions={},abilityWords={},namedInteractions={}}
for _,row in ipairs(observed.metadataKeywords)do local p=FX.profile(row);local group=p.category=='keyword_action'and'keywordActions'or p.category=='ability_word'and'abilityWords'or(classes[p.id]or p.coverage=='explicit'or p.coverage=='composed')and'keywordAbilities'or'namedInteractions';table.insert(groups[group],row)end
local output={};for name,rows in pairs(groups)do output[name]=FX.coverage(rows)end
local explicit,composed=0,0;for _,p in pairs(FX.profiles)do if p.coverage=='explicit'then explicit=explicit+1 else composed=composed+1 end end
output.registry={explicit=explicit,composed=composed};io.write(json.encode(output))"""
    result=subprocess.run([lua,'-e',script],cwd=ROOT,input=json.dumps(observed),text=True,capture_output=True,check=True)
    coverage=json.loads(result.stdout)
    totals={inventory:{kind:len(rows)for kind,rows in data.items()}for inventory,data in coverage.items()if inventory!='registry'}
    report={'scope':'Read-only inventory of native keyword ability class names and optional public printing keyword labels against the actual presentation registry. Native class presence is not runtime legality; metadata keywords are not proof a permanent currently has that ability.',
            'registry':coverage.pop('registry'),'counts':totals,'inventories':coverage,
            'coverageMeaning':{'explicit':'Authored named glyph and contextual recipe. Event animation still requires truthful native semantics and anchors.',
                               'composed':'Named vocabulary mapped to reusable recipe/glyph families; not a bespoke full animation.',
                               'generic':'Static named sigil only. Unsupported semantic animation; no invented event cause.',
                               'unsupported':'No presentation support.'},
            'metadata':None if not args.metadata else{'entries':cards,'sha256':digest.hexdigest()},
            'sourceSha256':{'app/mechanic_fx.lua':hashlib.sha256((ROOT/'app/mechanic_fx.lua').read_bytes()).hexdigest()}}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps({'registry':report['registry'],'counts':totals,'output':str(args.output)},indent=2))


if __name__=='__main__':main()
