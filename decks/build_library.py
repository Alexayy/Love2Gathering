#!/usr/bin/env python3
"""Regenerate the curated starter decks; no cards are downloaded."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parent
DECKS = []
def parse(text):
    out=[]
    for line in text.strip().splitlines():
        line=line.strip()
        if line:
            count,name=line.split(' ',1)
            out.append(dict(name=name,count=int(count)))
    return out

def add(id,name,fmt,description,main,side='',commander=''):
    DECKS.append(dict(id=id,name=name,format=fmt,description=description,commander=parse(commander),main=parse(main),sideboard=parse(side)))

add('modern-boros-burn','Boros Burn','Modern','Fast red damage with white interaction; tests prowess, combat and targeted spells.', '''
4 Goblin Guide
4 Monastery Swiftspear
4 Eidolon of the Great Revel
4 Lightning Bolt
4 Lava Spike
4 Rift Bolt
4 Boros Charm
4 Lightning Helix
4 Searing Blaze
4 Skullcrack
4 Inspiring Vantage
4 Sacred Foundry
4 Arid Mesa
4 Sunbaked Canyon
4 Mountain
''','''
3 Path to Exile
3 Smash to Smithereens
3 Rest in Peace
3 Deflecting Palm
3 Roiling Vortex
''')
add('modern-green-tron','Green Tron','Modern','Assemble Urza lands and cast large threats. Expedition Map and Sylvan Scrying test library search.', '''
4 Urza's Mine
4 Urza's Power Plant
4 Urza's Tower
4 Forest
1 Boseiju, Who Endures
1 Sanctum of Ugin
2 Blast Zone
4 Expedition Map
4 Chromatic Star
4 Chromatic Sphere
4 Ancient Stirrings
4 Sylvan Scrying
4 Karn Liberated
4 Karn, the Great Creator
2 Ugin, the Spirit Dragon
3 Wurmcoil Engine
2 Ulamog, the Ceaseless Hunger
2 Oblivion Stone
3 Relic of Progenitus
''','''
3 Nature's Claim
3 Thragtusk
3 Dismember
3 Veil of Summer
3 Pithing Needle
''')
add('modern-merfolk','Merfolk','Modern','Islandwalk and tribal lords build an evasive board; Aether Vial exercises activated abilities.', '''
4 Island
4 Cavern of Souls
4 Mutavault
4 Seachrome Coast
4 Waterlogged Grove
4 Aether Vial
4 Tide Shaper
4 Silvergill Adept
4 Lord of Atlantis
4 Master of the Pearl Trident
4 Merfolk Trickster
4 Vodalian Hexcatcher
4 Svyelun of Sea and Sky
4 Spreading Seas
4 Force of Negation
''','''
3 Dismember
3 Relic of Progenitus
3 Hurkyl's Recall
3 Counterspell
3 Kira, Great Glass-Spinner
''')
add('modern-azorius-control','Azorius Control','Modern','Instant-speed answers, sweepers and planeswalkers exercise priority, stack and loyalty actions.', '''
4 Flooded Strand
4 Hallowed Fountain
4 Glacial Fortress
4 Island
3 Plains
3 Celestial Colonnade
2 Field of Ruin
4 Snapcaster Mage
4 Counterspell
4 Prismatic Ending
4 Solitude
4 Teferi, Time Raveler
4 Opt
3 Supreme Verdict
3 Memory Deluge
2 Teferi, Hero of Dominaria
2 Jace, the Mind Sculptor
2 March of Otherworldly Light
''','''
3 Rest in Peace
3 Dovin's Veto
3 Celestial Purge
3 Wear // Tear
3 Timely Reinforcements
''')
add('modern-jund','Jund Midrange','Modern','Discard, efficient removal and graveyard-sensitive creatures provide interactive games.', '''
4 Verdant Catacombs
4 Bloodstained Mire
2 Overgrown Tomb
2 Blood Crypt
1 Stomping Ground
2 Raging Ravine
2 Blackcleave Cliffs
2 Blooming Marsh
2 Swamp
1 Forest
1 Mountain
4 Tarmogoyf
4 Scavenging Ooze
4 Bloodbraid Elf
4 Lightning Bolt
4 Thoughtseize
4 Fatal Push
3 Inquisition of Kozilek
3 Liliana of the Veil
3 Abrupt Decay
4 Seasoned Pyromancer
''','''
3 Nihil Spellbomb
3 Alpine Moon
3 Collective Brutality
3 Kolaghan's Command
3 Anger of the Gods
''')

add('standard-white-lifegain','White Lifegain','Standard','Lifegain grows Pridemate and Essence Channeler; an accessible deck for checking simultaneous triggers.', '''
24 Plains
4 Hinterland Sanctifier
4 Healer's Hawk
4 Leonin Vanguard
4 Ajani's Pridemate
4 Essence Channeler
4 Dazzling Angel
4 Helpful Hunter
4 Banishing Light
4 Felidar Retreat
''','''
3 Exorcise
3 Day of Judgment
3 Authority of the Consuls
3 Requisition Raid
3 Rest in Peace
''')
add('standard-blue-tempo','Blue Tempo','Standard','Evasive threats backed by counters and bounce; teaches stack interaction and combat timing.', '''
24 Island
4 Spectral Sailor
4 Faerie Dreamthief
4 Mockingbird
4 Tempest Djinn
4 Tolarian Terror
4 Opt
4 Into the Roil
4 Essence Scatter
4 Negate
''','''
3 Disdainful Stroke
3 Unable to Scream
3 Refute
3 Mazemind Tome
3 Ghost Vacuum
''')
add('standard-black-midrange','Black Midrange','Standard','Removal, card draw and resilient creatures; death triggers and sacrifice choices matter.', '''
24 Swamp
4 Deep-Cavern Bat
4 Preacher of the Schism
4 Enduring Tenacity
4 Bloodletter of Aclazotz
4 Forsaken Miner
4 Bitter Triumph
4 Shoot the Sheriff
4 Phyrexian Arena
4 Duress
''','''
3 Malicious Eclipse
3 Deadly Cover-Up
3 Ghost Vacuum
3 Feed the Swarm
3 Liliana, Dreadhorde General
''')
add('standard-red-aggro','Red Aggro','Standard','Low-cost attackers, burn and prowess provide a fast bot opponent without banned red staples.', '''
24 Mountain
4 Emberheart Challenger
4 Ghitu Lavarunner
4 Fanatical Firebrand
4 Manifold Mouse
4 Slickshot Show-Off
4 Burst Lightning
4 Lightning Strike
4 Boltwave
4 Witchstalker Frenzy
''','''
3 Abrade
3 Torch the Tower
3 Obliterating Bolt
3 Scorching Shot
3 Pyroclasm
''')
add('standard-green-stompy','Green Stompy','Standard','Mana creatures accelerate large tramplers; combat and permanent abilities drive the game.', '''
24 Forest
4 Llanowar Elves
4 Scavenging Ooze
4 Dwynen's Elite
4 Elvish Archdruid
4 Dwynen, Gilt-Leaf Daen
4 Gigantosaurus
4 Ghalta, Primal Hunger
4 Bushwhack
4 Overrun
''','''
3 Reclamation Sage
3 Broken Wings
3 Bite Down
3 Snakeskin Veil
3 Soul-Guide Lantern
''')

add('pioneer-izzet-phoenix','Izzet Phoenix','Pioneer','Mandatory Phoenix deck: cantrips and graveyard setup return Arclight Phoenix automatically at combat.', '''
4 Arclight Phoenix
4 Picklock Prankster // Free the Fae
4 Consider
4 Opt
4 Sleight of Hand
4 Treasure Cruise
4 Pieces of the Puzzle
4 Lightning Axe
4 Fiery Impulse
2 Spell Pierce
2 Temporal Trespass
4 Steam Vents
4 Spirebluff Canal
4 Riverglide Pathway // Lavaglide Pathway
4 Shivan Reef
3 Island
1 Mountain
''','''
3 Mystical Dispute
3 Abrade
3 Aether Gust
2 Brotherhood's End
2 Crackling Drake
2 Disdainful Stroke
''')
add('pioneer-lotus-field','Lotus Field Combo','Pioneer','Mandatory Lotus Field deck: copy Lotus Field with Thespian\'s Stage, untap for mana, tutor and win with Approach.', '''
4 Arboreal Grazer
4 Vizier of Tumbling Sands
4 Sylvan Scrying
4 Hidden Strings
4 Impulse
1 Shimmer of Possibility
4 Pore Over the Pages
3 Emergent Ultimatum
3 Bala Ged Recovery // Bala Ged Sanctuary
2 Dark Petition
1 Omniscience
1 Behold the Beyond
1 Lier, Disciple of the Drowned
1 Approach of the Second Sun
1 Mastermind's Acquisition
4 Lotus Field
4 Thespian's Stage
4 Botanical Sanctum
4 Yavimaya Coast
2 Boseiju, Who Endures
1 Otawara, Soaring City
1 Breeding Pool
1 Island
1 Forest
''','''
3 Mystical Dispute
3 Leyline of Sanctity
3 Tear Asunder
2 Thought Distortion
2 Path of Peril
1 Approach of the Second Sun
1 Supreme Verdict
''')
add('pioneer-rakdos-midrange','Rakdos Midrange','Pioneer','Discard and removal support value creatures, Fable chapters and Blood tokens.', '''
4 Bloodtithe Harvester
4 Bonecrusher Giant // Stomp
4 Graveyard Trespasser // Graveyard Glutton
4 Fable of the Mirror-Breaker // Reflection of Kiki-Jiki
2 Sheoldred, the Apocalypse
4 Thoughtseize
4 Fatal Push
2 Go for the Throat
2 Kroxa, Titan of Death's Hunger
2 Reckoner Bankbuster
4 Blood Crypt
4 Blackcleave Cliffs
4 Blightstep Pathway // Searstep Pathway
4 Haunted Ridge
2 Hive of the Eye Tyrant
2 Den of the Bugbear
2 Swamp
2 Mountain
4 Duress
''','''
3 Unlicensed Hearse
3 Extinction Event
3 Abrade
3 Damping Sphere
3 Rending Volley
''')
add('pioneer-white-humans','White Humans','Pioneer','A tribal curve with Thalia taxes, lieutenant counters and Brave the Elements combat finishes.', '''
4 Recruitment Officer
4 Dauntless Bodyguard
4 Hopeful Initiate
4 Thalia, Guardian of Thraben
4 Thalia's Lieutenant
4 Coppercoat Vanguard
4 Adeline, Resplendent Cathar
4 Brutal Cathar // Moonrage Brute
4 Brave the Elements
16 Plains
4 Mutavault
4 Cavern of Souls
''','''
3 Portable Hole
3 Rest in Peace
3 Wedding Announcement // Wedding Festivity
3 Destroy Evil
3 Reidane, God of the Worthy // Valkmira, Protector's Shield
''')
add('pioneer-azorius-spirits','Azorius Spirits','Pioneer','Flash and flying threats combine with lord bonuses and protective spirits.', '''
4 Mausoleum Wanderer
4 Spectral Sailor
4 Rattlechains
4 Supreme Phantom
4 Empyrean Eagle
4 Shacklegeist
4 Spell Queller
4 Selfless Spirit
4 Geistlight Snare
4 Curious Obsession
4 Hallowed Fountain
4 Seachrome Coast
4 Hengegate Pathway // Mistgate Pathway
4 Adarkar Wastes
3 Island
1 Plains
''','''
3 Portable Hole
3 Rest in Peace
3 Mystical Dispute
3 Disdainful Stroke
3 Skyclave Apparition
''')

COMMON='''
1 Sol Ring
1 Arcane Signet
1 Mind Stone
1 Wayfarer's Bauble
1 Commander's Sphere
1 Swiftfoot Boots
1 Lightning Greaves
1 Skullclamp
1 Solemn Simulacrum
1 Burnished Hart
'''
def commander(id,name,leader,description,spells,land):
    main=parse(COMMON)+parse(spells)+[dict(name=land,count=37)]
    DECKS.append(dict(id=id,name=name,format='Commander',description=description,commander=[dict(name=leader,count=1)],main=main,sideboard=[]))
commander('commander-giada-angels','Giada Angels','Giada, Font of Hope','Mono-white Angels. Giada adds counters as Angels enter; life and combat triggers test the full rules engine.', '''
1 Bishop of Wings
1 Youthful Valkyrie
1 Righteous Valkyrie
1 Resplendent Angel
1 Angel of Vitality
1 Starnheim Aspirant
1 Inspiring Overseer
1 Angel of Sanctions
1 Angel of Finality
1 Serra Angel
1 Baneslayer Angel
1 Lyra Dawnbringer
1 Archangel of Thune
1 Archangel of Tithes
1 Angelic Skirmisher
1 Angel of Serenity
1 Herald of War
1 Emeria Shepherd
1 Sephara, Sky's Blade
1 Avacyn, Angel of Hope
1 Angel of the Dire Hour
1 Adarkar Valkyrie
1 Karmic Guide
1 Serra's Emissary
1 Angelic Arbiter
1 Battle Angels of Tyr
1 Angel of Invention
1 Angel of Jubilation
1 Linvala, Keeper of Silence
1 Valkyrie Harbinger
1 Swords to Plowshares
1 Path to Exile
1 Generous Gift
1 Disenchant
1 Return to Dust
1 Wrath of God
1 Day of Judgment
1 Austere Command
1 Cleansing Nova
1 Land Tax
1 Gift of Estates
1 Marble Diamond
1 Pearl Medallion
1 Herald's Horn
1 Vanquisher's Banner
1 Endless Atlas
1 Dawn of Hope
1 Well of Lost Dreams
1 Cosmos Elixir
1 Luminarch Ascension
1 Court of Grace
1 Sigarda's Splendor
''','Plains')
commander('commander-talrand-spells','Talrand Spells','Talrand, Sky Summoner','Mono-blue spells create Drake tokens, then protect an evasive army. Draw, scry, counterspells and trigger ordering.', '''
1 Brainstorm
1 Ponder
1 Preordain
1 Opt
1 Consider
1 Serum Visions
1 Sleight of Hand
1 Gitaxian Probe
1 Peek
1 Impulse
1 Frantic Search
1 Fact or Fiction
1 Deep Analysis
1 Treasure Cruise
1 Dig Through Time
1 Chart a Course
1 Windfall
1 Blue Sun's Zenith
1 Counterspell
1 Arcane Denial
1 Negate
1 Essence Scatter
1 Dispel
1 Spell Pierce
1 Swan Song
1 Mana Leak
1 Memory Lapse
1 Unwind
1 Rewind
1 Exclude
1 Into the Roil
1 Blink of an Eye
1 Snap
1 Unsummon
1 Rapid Hybridization
1 Pongify
1 Reality Shift
1 Resculpt
1 Aetherize
1 Evacuation
1 Cyclonic Rift
1 High Tide
1 Sapphire Medallion
1 Sky Diamond
1 Thought Vessel
1 Bident of Thassa
1 Reconnaissance Mission
1 Coastal Piracy
1 Favorable Winds
1 Murmuring Mystic
1 Archaeomancer
1 Wavebreak Hippocamp
''','Island')
commander('commander-ayara-devotion','Ayara Devotion','Ayara, First of Locthwain','Mono-black devotion and sacrifice. Enter, death and life-drain triggers create an engine-driven value loop.', '''
1 Blood Artist
1 Zulaport Cutthroat
1 Bastion of Remembrance
1 Gray Merchant of Asphodel
1 Kokusho, the Evening Star
1 Syr Konrad, the Grim
1 Pawn of Ulamog
1 Pitiless Plunderer
1 Reassembling Skeleton
1 Persistent Specimen
1 Bloodsoaked Champion
1 Gravecrawler
1 Carrion Feeder
1 Viscera Seer
1 Woe Strider
1 Midnight Reaper
1 Grim Haruspex
1 Morbid Opportunist
1 Midnight Banshee
1 Plaguecrafter
1 Fleshbag Marauder
1 Merciless Executioner
1 Ravenous Chupacabra
1 Dusk Legion Zealot
1 Phyrexian Rager
1 Sengir Autocrat
1 Endrek Sahr, Master Breeder
1 Abhorrent Overlord
1 Ophiomancer
1 Chittering Witch
1 Ogre Slumlord
1 Crypt Ghast
1 Nirkana Revenant
1 Charcoal Diamond
1 Jet Medallion
1 Ashnod's Altar
1 Altar of Dementia
1 Village Rites
1 Deadly Dispute
1 Sign in Blood
1 Night's Whisper
1 Read the Bones
1 Phyrexian Arena
1 Victimize
1 Animate Dead
1 Reanimate
1 Living Death
1 Feed the Swarm
1 Go for the Throat
1 Infernal Grasp
1 Crux of Fate
1 Mutilate
''','Swamp')
commander('commander-krenko-goblins','Krenko Goblins','Krenko, Mob Boss','Mono-red Goblins create tokens, attack and sacrifice for damage. Many simultaneous enter/death triggers.', '''
1 Skirk Prospector
1 Goblin Sledder
1 Mogg Raider
1 Goblin Chirurgeon
1 Goblin Arsonist
1 Foundry Street Denizen
1 Goblin Instigator
1 Mogg War Marshal
1 Goblin Matron
1 Goblin Ringleader
1 Goblin Warchief
1 Goblin Chieftain
1 Goblin King
1 Hobgoblin Bandit Lord
1 Goblin Piledriver
1 Goblin Wardriver
1 Goblin Trashmaster
1 Goblin Cratermaker
1 Goblin Chainwhirler
1 Goblin Sharpshooter
1 Krenko, Tin Street Kingpin
1 Krenko, Baron of Tin Street
1 Siege-Gang Commander
1 Goblin Rabblemaster
1 Pashalik Mons
1 Goblin Bombardment
1 Impact Tremors
1 Raid Bombardment
1 Shared Animosity
1 Boggart Shenanigans
1 Goblin Warrens
1 Goblin War Strike
1 Hordeling Outburst
1 Krenko's Command
1 Dragon Fodder
1 Empty the Warrens
1 Battle Hymn
1 Brightstone Ritual
1 Skirk Fire Marshal
1 Conspicuous Snoop
1 Rundvelt Hordemaster
1 Squee, Dubious Monarch
1 Legion Loyalist
1 Ruby Medallion
1 Fire Diamond
1 Herald's Horn
1 Vanquisher's Banner
1 Idol of Oblivion
1 Faithless Looting
1 Thrill of Possibility
1 Chaos Warp
1 Abrade
''','Mountain')
commander('commander-goreclaw-stompy','Goreclaw Stompy','Goreclaw, Terror of Qal Sisma','Mono-green ramp and large creatures. Cost reductions, trample, fight and draw triggers reward attacking.', '''
1 Llanowar Elves
1 Elvish Mystic
1 Fyndhorn Elves
1 Arbor Elf
1 Sakura-Tribe Elder
1 Wood Elves
1 Farhaven Elf
1 Reclamation Sage
1 Eternal Witness
1 Beast Whisperer
1 Garruk's Packleader
1 Soul of the Harvest
1 Primordial Sage
1 Elemental Bond
1 Garruk's Uprising
1 Guardian Project
1 Return of the Wildspeaker
1 Rishkar's Expertise
1 Harmonize
1 Hunter's Insight
1 Cultivate
1 Kodama's Reach
1 Rampant Growth
1 Nature's Lore
1 Three Visits
1 Skyshroud Claim
1 Emerald Medallion
1 Moss Diamond
1 Garruk Wildspeaker
1 Nissa, Who Shakes the World
1 Karametra's Acolyte
1 Selvala, Heart of the Wilds
1 Whisperer of the Wilds
1 Gigantosaurus
1 Ghalta, Primal Hunger
1 Ghalta, Stampede Tyrant
1 Thragtusk
1 Acidic Slime
1 Terastodon
1 Woodfall Primus
1 End-Raze Forerunners
1 Craterhoof Behemoth
1 Pathbreaker Ibex
1 Thunderfoot Baloth
1 Avenger of Zendikar
1 Rampaging Baloths
1 Hornet Queen
1 Ulvenwald Hydra
1 Beast Within
1 Krosan Grip
1 Heroic Intervention
1 Overwhelming Stampede
''','Forest')

if __name__=='__main__':
    for d in DECKS:
        n=sum(x['count'] for x in d['main'])
        expected=99 if d['format']=='Commander' else 60
        side=sum(x['count'] for x in d['sideboard'])
        if n != expected or side!=(0 if d['format']=='Commander' else 15):
            raise SystemExit(f"Bad counts in {d['id']}: {n}/{side}")
        (ROOT/(d['id']+'.json')).write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'library.json').write_text(json.dumps([dict(id=d['id'],name=d['name'],format=d['format'],description=d['description']) for d in DECKS],ensure_ascii=False,indent=2)+'\n')
    print('Wrote',len(DECKS),'complete starter decks')
