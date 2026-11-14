package.path='./?.lua;'..package.path
local Board=require('app.board_fx');local passed=0
local function check(value,label)assert(value,label);passed=passed+1;print('BOARD FX PASS '..label)end
local function card(id)return{id=id,name=id,type='Creature',power='2',toughness='2'}end
local host,aura,exiled=card('host'),card('aura'),card('exiled');aura.attachedToId='host';host.linkedExile={exiled}
local game={gameId='game',revision=1,turn=1,players={{id='human',human=true,life=40,battlefield={host,aura},graveyard={},hand={}},{id='bot',seat=1,life=40,battlefield={},graveyard={},hand={}}},stack={},combat={step='DECLARE_BLOCKERS',groups={{attackerId='host',defenderId='human',blockerIds={},blocked=true}}}}
local r={model={game=game,settings={}},colors={accent={0,1,0},purple={1,0,1}},bursts={},cardRects={host={x=100,y=200,w=100,h=140}},playerRects={human={x=20,y=30,w=100,h=50},bot={x=600,y=30,w=100,h=50}}}
function r:burst(kind,x,y)self.bursts[#self.bursts+1]={kind=kind,x=x,y=y}end
Board.prepare(r);check(r.boardAttached.host[1]==aura and r.boardCards.host==host,'Native attachment identity is separate from its host')
local order={};function r:drawCard(c,x,y,w,h,options)order[#order+1]={id=c.id,angle=options.angle}end
Board.layers(r,host,1,2,100,140,{})
check(order[1].id=='aura'and order[2].id=='exiled'and order[2].angle==math.pi/2 and order[3].id=='host','Attachments and entitled linked exile render behind the unchanged host')
check(Board.color(r,r.boardPlayers.human)~=Board.color(r,r.boardPlayers.bot),'Players have distinct stable presentation colors')
Board.update(r,.01)
r.playerRects={human={x=20,y=30,w=100,h=50},bot={x=600,y=30,w=100,h=50}}
game.revision=2;game.players[1].life=43;game.stack={{id='spell',sourceId='host',controllerId='human'}}
Board.update(r,.01);Board.flush(r)
local life,cast
for _,e in ipairs(r.boardEffects)do if e.kind=='life_gain'then life=e elseif e.kind=='cast'then cast=e end end
check(life and life.amount==3 and life.x==70 and life.y==55,'Life changes originate at the actual player frame')
check(cast and cast.x==150 and cast.y==270,'Cast particles originate at the source card, not the screen center')
game.revision=3;game.combat.step='FIRST_COMBAT_DAMAGE';Board.update(r,.01)
check(#r.pendingBoardFX==0,'A still-blocked attacker without surviving blockers does not falsely strike a player')
game.revision=4;game.combat.groups[1].blockerIds={'aura'};game.combat.step='COMBAT_DAMAGE';Board.update(r,.01)
check(#r.pendingBoardFX==0,'A damage-step label alone never invents damage or first-strike participants')
r.cardRects.aura={x=400,y=200,w=100,h=140}
game.revision=5;game.animationEvents={{id='first-hit',type='damage',combat=true,sourceId='host',targetId='aura',amount=2,step='FIRST_COMBAT_DAMAGE'}}
Board.update(r,.01);Board.flush(r)
check(r.cardMotions.host and not r.cardMotions.aura,'Only the native first-strike damage source lunges; its target does not retaliate')
game.revision=6;game.combat={groups={},step='POSTCOMBAT_MAIN'}
game.animationEvents[2]={id='second-hit',type='damage',combat=true,sourceId='host',targetId='aura',amount=2,step='COMBAT_DAMAGE'}
Board.update(r,.01)
local second=r.pendingBoardFX[#r.pendingBoardFX]
check(second.kind=='clash'and second.delay>0 and second.step=='COMBAT_DAMAGE','A polled batch retains distinct first/double-strike timing even after combat ends')
Board.flush(r);local before=r.cardMotions.host
Board.update(r,.6)
check(r.cardMotions.host and r.cardMotions.host~=before,'A delayed second hit starts its own motion instead of overwriting the first')
game.revision=7;game.animationEvents[3]={id='burn',type='damage',combat=false,sourceId='aura',targetId='host',amount=3,step='COMBAT_DAMAGE'}
Board.update(r,.01)
check(#r.pendingBoardFX==1 and r.pendingBoardFX[1].kind=='damage','Noncombat burn during a combat step never becomes a combat lunge')
r.model.settings.reducedMotion=true;check(Board.offset(r,host)==0,'Reduced motion suppresses card displacement');r.model.settings.reducedMotion=false
r.model.settings.animations=false;check(Board.offset(r,host)==0,'Disabling animations suppresses card displacement');r.model.settings.animations=true
game.revision=8;game.combat.groups={};game.players[1].battlefield={aura};game.players[1].graveyard={host};Board.update(r,.01)
check(r.pendingBoardFX[#r.pendingBoardFX].kind=='death','A battlefield-to-graveyard transition shatters; other disappearances are not inferred as death')
game.revision=9;game.animationEvents[4]={id='between-polls-death',type='zone',targetId='aura',fromZone='BATTLEFIELD',toZone='GRAVEYARD'}
game.players[1].battlefield={};game.players[1].graveyard={host}
Board.update(r,.01)
check(r.pendingBoardFX[#r.pendingBoardFX].kind=='death'and r.pendingBoardFX[#r.pendingBoardFX].targetId=='aura','Native death events survive a skipped transient graveyard snapshot')
game.revision=10;game.animationEvents[5]={id='extra-combat-step',type='step',step='COMBAT_DAMAGE'}
game.animationEvents[6]={id='extra-combat-hit',type='damage',combat=true,sourceId='aura',targetId='host',amount=1,step='COMBAT_DAMAGE'}
Board.update(r,.01)
check(r.pendingBoardFX[#r.pendingBoardFX].delay>0,'Retained native step identities separate same-step extra combats within one turn')
check(Board.anchor(r,nil)==nil,'Redacted or missing sources never borrow an unrelated stack anchor')
local battlefieldBox={x=100,y=200,w=100,h=140,kind='permanent'}
r.previousCardRects={host=battlefieldBox};r.cardRects.host={x=800,y=600,w=80,h=112,kind='pile'}
check(Board.anchor(r,'host')==battlefieldBox,'A newly dead card retains its last battlefield effect anchor instead of its new graveyard pile')
local metadata={id='printing-id',name='Angel of Vitality',oracle_text='Printed rules',power='2',toughness='2'}
package.preload['app.api']=function()return{new=function()return{}end}end
local Model=require('app.model');local m=setmetatable({byName={['Angel of Vitality']=metadata}},{__index=Model})
local live=m:cardData({id='native-id',name='Angel of Vitality',power='5',toughness='5',counters={['+1/+1']=1}})
check(live.id=='printing-id'and live.objectId=='native-id'and live.power=='5'and metadata.power=='2','Artwork identity stays distinct from current native P/T and the catalog is not mutated')
print('Board presentation checks: '..passed..' passed')
