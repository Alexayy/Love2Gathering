#!/usr/bin/env python3
"""Validate shipped starter decks against local Scryfall and XMage data.
Run from any directory. First run streams the bulk file once into a small local cache.
"""
import argparse, collections, json, re, sqlite3, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
PROJECT=ROOT.parent

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--refresh',action='store_true')
    args=p.parse_args()
    manifest=json.loads((ROOT/'library.json').read_text())
    decks=[json.loads((ROOT/(item['id']+'.json')).read_text()) for item in manifest]
    names={x['name'] for d in decks for z in ('commander','main','sideboard') for x in d[z]}
    cache=ROOT/'card-reference.json'
    cards={} if args.refresh or not cache.exists() else json.loads(cache.read_text())
    missing=names-cards.keys()
    # The application catalog is the same local bulk data, already deduplicated.
    catalog=PROJECT/'service/data/catalog.sqlite'
    if missing and catalog.exists():
        db=sqlite3.connect(catalog)
        for name in list(missing):
            row=db.execute('SELECT payload FROM cards WHERE name=? COLLATE NOCASE',(name,)).fetchone()
            if row:
                card=json.loads(row[0])
                cards[name]={k:card.get(k) for k in ('name','type_line','color_identity','legalities','set','collector_number')}
                missing.remove(name)
        db.close()
        cache.write_text(json.dumps(cards,ensure_ascii=False,indent=2)+'\n')
    if missing:
        source=next((PROJECT/'assets').glob('all-cards*.jsonl'))
        print('Streaming',source.name,'for',len(missing),'cards...',flush=True)
        for line in source.open():
            card=json.loads(line)
            if card['name'] in missing and card.get('lang')=='en':
                cards[card['name']]={k:card.get(k) for k in ('name','type_line','color_identity','legalities','set','collector_number')}
                missing.remove(card['name'])
                if not missing: break
        cache.write_text(json.dumps(cards,ensure_ascii=False,indent=2)+'\n')
    errors=[]
    implemented=set()
    for path in (PROJECT/'engine/mage').rglob('*.java'):
        # XMage supplies printed card names in the ExpansionSet entry, but normalized
        # class filenames are enough to prove that an implementation exists here.
        implemented.add(path.stem.lower())
    fmtcounts=collections.Counter(d['format'] for d in decks)
    if fmtcounts!={'Modern':5,'Standard':5,'Pioneer':5,'Commander':5}: errors.append('Expected 5 decks in each format: '+str(fmtcounts))
    report=[]
    for d in decks:
        issue=[]
        main=sum(x['count'] for x in d['main'])
        side=sum(x['count'] for x in d['sideboard'])
        cmd=sum(x['count'] for x in d['commander'])
        commander=d['format']=='Commander'
        if (main,side,cmd)!=((99,0,1) if commander else (60,15,0)): issue.append(f'Counts {main}/{side}/{cmd}')
        totals=collections.Counter()
        identity=set()
        if commander:
            for x in d['commander']:
                card=cards.get(x['name'],{})
                identity.update(card.get('color_identity',[]))
                if 'Legendary' not in card.get('type_line','') or 'Creature' not in card.get('type_line',''):
                    issue.append('Starter commander must be a legendary creature '+x['name'])
        for zone in ('commander','main','sideboard'):
            for x in d[zone]:
                name=x['name']; totals[name]+=x['count']
                if x['count']<1 or not isinstance(x['count'],int): issue.append('Bad quantity '+name)
                card=cards.get(name)
                if not card:
                    issue.append('Missing card '+name); continue
                if card['legalities'].get(d['format'].lower())!='legal': issue.append('Snapshot illegal '+name)
                if commander and not set(card['color_identity']).issubset(identity): issue.append('Color identity '+name)
                # Split and DFC names use the front face for class names.
                front=name.split(' // ')[0]
                normal=re.sub('[^A-Za-z0-9]','',front).lower()
                if normal not in implemented and re.sub('[^A-Za-z0-9]','',name).lower() not in implemented: issue.append('XMage class not found '+name+' ('+normal+')')
        for name,count in totals.items():
            card=cards.get(name,{})
            if 'Basic' not in card.get('type_line','') and count>(1 if commander else 4): issue.append('Too many copies '+name)
        report.append(dict(id=d['id'],format=d['format'],main=main,sideboard=side,commander=cmd,cards=len(totals),errors=issue))
        errors.extend(d['id']+': '+s for s in issue)
    out=dict(snapshot='all-cards-20260922091740.jsonl',verified_date='2026-11-12',total_decks=len(decks),format_counts=fmtcounts,passed=not errors,checks=['deck size','sideboard size','commander count','copy limits','Scryfall snapshot legality','XMage implementation class','commander color identity','legendary creature commander'],decks=report,errors=errors)
    (ROOT/'validation-report.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
    for error in errors: print(error)
    print(f'{len(decks)} decks; {len(names)} distinct cards; {len(errors)} errors')
    return bool(errors)

if __name__=='__main__': sys.exit(main())
