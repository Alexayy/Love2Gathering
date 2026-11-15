"""Temporary targeted lists and streamed local printing identities; no acquisition."""
import collections
import json
from pathlib import Path
from .runtime import ROOT, sha, write_json


# Each purpose differs mechanically; lands fill lists, never change test rules.
SPECS=[
 ('control','baseline pass/land control',['Mountain'],[]),
 ('burn','production burn and combat',['Mountain'],['Goblin Guide','Monastery Swiftspear','Ghitu Lavarunner','Lightning Bolt','Lava Spike','Shock','Lightning Strike','Searing Spear','Skewer the Critics']),
 ('white-tokens','multiple tokens and token anthem',['Plains'],['Raise the Alarm','Secure the Wastes','Anointed Procession','Intangible Virtue','Soul Warden']),
 ('token-growth','landfall copy growth',['Forest'],['Scute Swarm','Avenger of Zendikar','Parallel Lives','Doubling Season']),
 ('token-variety','different native token templates',['Forest','Swamp'],['Tireless Provisioner','Academy Manufactor','Chatterfang, Squirrel General']),
 ('death-triggers','ETB/death/sacrifice and nested triggers',['Swamp'],['Blood Artist','Zulaport Cutthroat','Woe Strider','Ayara, First of Locthwain']),
 ('optional-loop','player-controlled repeat without forced outcome',['Plains'],['Ornithopter','Enduring Renewal',"Ashnod's Altar"]),
 ('raptor-loop','mandatory token growth with finite native resource behavior',['Mountain','Forest'],['Polyraptor','Marauding Raptor','Forerunner of the Empire']),
 ('saproling-loop','mandatory land/token feedback',['Forest'],['Sporemound','Life and Limb']),
 ('spell-copy','spell copy/retarget',['Island','Mountain'],['Twincast','Reverberate','Lightning Bolt']),
 ('permanent-copy','copiable vs current characteristics',['Island','Forest'],['Clone','Spark Double','Rite of Replication','Quasiduplicate','Grizzly Bears']),
 ('ability-copy','copied and doubled triggers',['Plains','Forest'],['Strionic Resonator','Panharmonicon','Wall of Omens','Soul Warden','Grizzly Bears']),
 ('mutate','successive native merge choices',['Island','Forest','Mountain'],['Migratory Greathorn','Gemrazer','Sea-Dasher Octopus','Porcuparrot','Grizzly Bears']),
 ('replacement','replacement order and token multiplication',['Plains','Forest'],['Parallel Lives','Anointed Procession','Doubling Season','Academy Manufactor','Tireless Provisioner']),
 ('layers','type/ability/characteristic interactions',['Plains','Forest'],['Humility','Opalescence','Darksteel Mutation','Bonesplitter','Rancor']),
 ('combat','native evasion/strike/trample/lifelink',['Plains','Forest','Swamp'],['Vampire Nighthawk','Colossal Dreadmaw','Fencing Ace','Deadly Recluse','Rancor']),
 ('costs','X, mixed mana and additional costs',['Mountain','Swamp','Island'],['Fireball','Manamorphose','Village Rites','Mind Stone','Merfolk Looter']),
 ('zones','blink, exile replacement and attachments',['Plains'],['Cloudshift','Ephemerate','Rest in Peace','Oblivion Ring','Wall of Omens']),
]


def generate(directory, manifests=()):
    directory=Path(directory);deck_dir=directory/'decks';deck_dir.mkdir(parents=True,exist_ok=True)
    names=set();decks=[]
    for identifier,purpose,lands,spells in SPECS:
        counts=collections.Counter({name:4 for name in spells});remaining=60-sum(counts.values())
        for index in range(remaining):counts[lands[index%len(lands)]]+=1
        deck={'id':'mechanics-'+identifier,'name':'Mechanics: '+purpose,'format':'Modern',
              'main':[{'name':name,'count':count}for name,count in sorted(counts.items())],
              'sideboard':[],'commander':[]}
        path=deck_dir/(identifier+'.json');write_json(path,deck);names.update(counts)
        decks.append({'id':identifier,'purpose':purpose,'path':str(path),'sha256':sha(path),
                      'nativeValidation':'pending','productionEligible':False,
                      'scope':'purpose-built list; legality must be validated before any production start'})
    # Two normal Commander lists preserve their immutable source composition.
    for identifier in ('commander-krenko-goblins','commander-giada-angels'):
        source=ROOT/'decks'/(identifier+'.json')
        if not source.is_file():continue
        deck=json.loads(source.read_text());deck['id']='mechanics-'+identifier;deck['name']='Mechanics: '+deck['name']
        path=deck_dir/(identifier+'.json');write_json(path,deck)
        names.update(e['name']for zone in('main','sideboard','commander')for e in deck.get(zone,[]))
        decks.append({'id':identifier,'purpose':'normal validated Commander production play', 'path':str(path),'sha256':sha(path),'nativeValidation':'pending','productionEligible':False,'sourceTemplate':str(source.relative_to(ROOT))})
    for manifest in manifests:
        value=json.loads(Path(manifest).read_text())
        for scenario in(value if isinstance(value,list)else value.get('scenarios',[])):
            cards=scenario.get('cards',[])
            if isinstance(cards,dict):names.update(cards)
            else:
                for card in cards:
                    if isinstance(card,str):names.add(card)
                    elif isinstance(card,dict)and card.get('name'):names.add(card['name'])
    source=next(iter(sorted((ROOT/'assets').glob('*scryfall-default.jsonl'))),None)
    if source is None:raise RuntimeError('No supplied local Scryfall JSONL; no automatic network acquisition')
    card_map=json.loads((ROOT/'bridge/card-map.json').read_text());mapped={name.casefold()for name in card_map}
    wanted={name.casefold()for name in names};found=set();records=0
    subset=directory/'metadata.jsonl'
    with source.open()as rows,subset.open('w')as out:
        for row in rows:
            raw=json.loads(row);name=raw.get('name','')
            if raw.get('lang','en')=='en'and name.casefold()in wanted:
                out.write(row if row.endswith('\n')else row+'\n');found.add(name.casefold());records+=1
    result={'decks':decks,'deckCount':len(decks),'requiredNames':sorted(names),
            'missingMetadata':sorted(n for n in names if n.casefold()not in found),
            'missingNativeMap':sorted(n for n in names if n.casefold()not in mapped),
            'metadata':str(subset),'metadataRows':records,'metadataSha256':sha(subset),
            'source':str(source),'sourceSha256':sha(source),'acquisition':False}
    write_json(directory/'generation.json',result)
    return result
