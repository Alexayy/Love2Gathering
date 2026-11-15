-- Labels derived from native values, without mutating game data or permissions.
package.path='./?.lua;'..package.path
local P=require('app.card_presentation');local Board=require('app.board_fx');local json=require('lib.json');local n=0
local function check(value,label)assert(value,label);n=n+1 end
local card={id='solemn',name='Solemn Simulacrum',type='Creature',power='3',toughness='3',damage=1}
local before=json.encode(card);local stats=P.stats(card)
check(stats.native=='3/3'and stats.shown=='3/2'and stats.damage==1,'Remaining defense is a label separate from native P/T and damage')
check(json.encode(card)==before,'Display calculations preserve native card values')
card.damage=4;check(P.stats(card).shown=='3/-1','Overmarked defense never invents native toughness or clamps legality')
card.toughness='*';check(P.stats(card).remaining==nil and P.stats(card).shown=='3/*','Unknown toughness is never guessed')
check(P.stats({power='',toughness='',type='Land'})==nil,'Empty native noncreature stats have no badge')
check(P.stats({power='0',toughness='0',type='Artifact'})==nil,'Ordinary noncreatures do not gain a0/0badge')
check(P.stats({power='0',toughness='0',type='Creature'})~=nil,'A real0/0creature retains its native stats')
local face={id='manifest',faceDown=true,power='2',toughness='2',damage=1,faceDownIdentity={id='manifest',name='Willbender',power='1',toughness='2'}}
local original=json.encode(face);local peek=P.peek(face)
check(peek.name=='Willbender'and peek.faceDownContext.nativePT=='2/2'and peek.faceDownContext.damage==1,'Only native supplied peek carries separate face-down board context')
check(peek~=face.faceDownIdentity and json.encode(face)==original,'Peeking never mutates either native projection')
face.hidden=true;check(P.peek(face)==face,'Hidden opponent cards cannot borrow a supplied identity')
face.hidden=false;face.faceDownIdentity.id='foreign';check(P.peek(face)==face,'Peek UUID must match the actual permanent')
face.faceDownIdentity=nil;check(P.peek(face)==face,'Ownership alone never fabricates a peek')
local commander={commandZonePlays=2,deaths=7,additionalTax={manaCost='{4}',otherCosts={}}}
check(P.commanderLabel(commander):find('extra {4}',1,true)and P.commanderLabel(commander):find('7 deaths',1,true),'Native tax and independent death history retain exact values')
commander.additionalTax={manaCost='',otherCosts={'Pay 2 life'}}
check(P.commanderLabel(commander):find('Pay 2 life',1,true)and not P.commanderLabel(commander):find('{14}',1,true),'Nonmana commander tax is never inferred from deaths')
local r={model={game={combat={groups={{attackerId='a',blockerIds={'b'},declarationConfirmed=false}}}}}}
check(Board.cardStatus(r,{id='b'}).label=='BLOCK ASSIGNED','Native unconfirmed block has a provisional label')
r.model.game.combat.groups[1].declarationConfirmed=true
check(Board.cardStatus(r,{id='b'}).confirmed,'Only acknowledged native block gets confirmed presentation')
r.model.prompt=function()return{combat={role='block_target',blockerId='b'}}end
check(Board.cardStatus(r,{id='b'}).label=='CHOOSE ATTACKER','Selected blocker is distinct from assigned blocker')
r.model.prompt=function()return{combat={role='attackers'}}end
check(Board.cardStatus(r,{id='a',attacking=true}).label=='ATTACK SELECTED','Individual native attacker selection stays provisional')
local player={name='Player',life=40,commanders={{name='Liesa',commandZonePlays=2,deaths=1,additionalTax={otherCosts={'Pay 2 life'}}}},commanderDamageReceived={{name='First commander',amount=6},{name='Second commander',amount=4}}}
local saved=json.encode(player)
check(P.commanderDamageSummary(player,true)=='Max commander damage: 6','Commander damage summary is the highest individual ledger entry rather than its sum')
check(P.commanderDamageSummary(player,false)=='Commander damage disabled','Native disabled commander damage remains explicit')
check(P.commanderDamageSummary(player,nil)==nil,'Other native game types gain no invented commander damage rule')
local tooltip=P.playerTooltip(player,true)
check(tooltip:find('First commander · 6 damage received',1,true)and tooltip:find('Second commander · 4 damage received',1,true),'Player tooltip preserves each actual commander damage entry')
check(tooltip:find('2 command casts · 1 deaths',1,true)and tooltip:find('Pay 2 life',1,true),'Player tooltip exposes native counts and actual nonmana commander cost')
check(json.encode(player)==saved,'Commander summaries and details leave the native ledger untouched')
check(Board.damageActor({}, {source={controllerId='source-player'}},{sourceId='source',playerId='damaged-player'})=='source-player','Damage outline follows the exact native source controller')
check(Board.damageActor({oldBoardCards={source={controllerId='last-native-controller'}}},{},{sourceId='source',playerId='damaged-player'})=='last-native-controller','Last observed native source controller survives a removed damage source')
check(Board.damageActor({}, {},{sourceId='missing',playerId='damaged-player'})==nil,'Unknown damage sources never take the victim player color')
check(P.manaCost({manaCost='{X}{U/P}'},{mana_cost='{2}{R}'})=='{X}{U/P}','Card header prefers the supplied native cost over catalog printing data')
check(P.manaCost({manaCost=''},{mana_cost='{2}{R}'})=='','An explicit empty native cost never borrows another face cost')
check(P.manaCost({}, {mana_cost='{W}{B}'})=='{W}{B}','Pure catalog cards retain the supplied printing cost')
check(P.eliminated({life=0})==false and P.eliminated({life=-2,lost=false,left=false})==false,'Life totals alone never eliminate a seat')
check(P.eliminated({lost=true})and P.eliminated({left=true}),'Only native lost or left state marks a seat out')
for _,case in ipairs({{'Precombat Main','PRECOMBAT'},{'POSTCOMBAT_MAIN','POSTCOMBAT'},{'Beginning of Combat','COMBAT'},{'Declare Attackers','COMBAT'},{'Declare Blockers','COMBAT'},{'First Combat Damage','COMBAT'},{'End Combat','COMBAT'},{'End Step','END'},{'Cleanup','END'},{'Draw','DRAW'},{'Upkeep','UPKEEP'}})do
 check(P.phaseKey({step=case[1]})==case[2],'Native step maps to its displayed phase: '..case[1])
end
check(P.phaseKey({step='Untap',phase='Beginning'})==nil,'An unrepresented native step does not invent a later upkeep window')
print('Card presentation: '..n..' checks (display only)')
