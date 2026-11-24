-- Presentation contracts; native mechanic legality is tested in bridge fixtures.
local FX=require('app.mechanic_fx');local Board=require('app.board_fx');local count=0
local function check(value,label)assert(value,label);count=count+1;print('MECHANIC FX PASS '..label)end
local required={'flashback','jump_start','evoke','convoke','mutate','morph','megamorph','disguise','manifest','cloak','haste','extort','trample','reach','flying','vigilance','first_strike','double_strike','deathtouch','lifelink','menace','defender','hexproof','ward','indestructible','protection','infect','toxic','wither','prowess','exalted','regeneration','persist','undying','flash','kicker','multikicker','buyback','bargain','casualty','improvise','delve','escape','overload','dash','blitz','emerge','spectacle','surge','prototype','bestow','cycling','channel','unearth','ninjutsu','equip','reconfigure','crew','saddle','foretell','plot','suspend','rebound','adventure','modal_double_faced','split','fuse','cascade','discover','storm','replicate','transform','meld','phasing','scry','surveil','landfall'}
for _,name in ipairs(required)do local p=FX.profile(name);check(p.coverage=='explicit'and p.glyph~='unknown'and p.recipe~='neutral','Authored named profile '..name)end
check(FX.profile('First strike').id=='first_strike'and FX.profile('Jump-start').id=='jump_start','Native identifiers normalize without interpreting rules text')
check(FX.profile('New unknown mechanic').coverage=='generic','An unknown mechanic remains an honest generic static label')
check(FX.profile('Flying').icon=='ability-flying' and FX.profile('First strike').icon=='ability-first-strike'
    and FX.profile('Trample').icon=='ability-trample','Common current combat keywords use the Mana Arena glyphs')
check(FX.profile('Cycling').icon=='ability-cycling' and FX.profile('Jump-start').icon=='ability-jumpstart'
    and FX.profile('Flashback').icon=='flashback','Native alternate interactions resolve their exact published glyph names')
check(FX.profile('Hexproof from red').icon=='ability-hexproof-red' and not FX.profile('Hexproof from planeswalkers').icon,
    'Colored hexproof uses a matching glyph and unsupported variants keep their specific text')
check(not FX.profile('Shroud').icon and FX.profile('Shroud').label=='shroud','Unmapped keywords retain a text label')
check(FX.profile('paradigm').coverage=='unsupported','An explicit native TODO is not advertised as an implemented mechanic')
local card={id='card',colors={'U'},currentKeywords={{id='flying'}},mechanicCapabilities={{id='flashback'}}}
local ps=FX.cardProfiles(card);check(#ps==2 and ps[1].id=='flashback','Current native keywords compose with alternate interaction capabilities')
check(FX.hasOptions(card),'An alternate play capability has the shared options affordance')
card.currentKeywords={{id='reach'}};check(FX.cardProfiles(card)[2].id=='reach','Replaced native characteristics invalidate the per-card presentation cache')
check(#FX.cardProfiles({id='removed',currentKeywords={},keywords={'haste'}})==0,'An explicitly empty current keyword list suppresses printed abilities that were lost')
local equips={{id='equip',parameter='Equip legendary creature {3}'},{id='equip',parameter='Equip {7}'}}
local equipment=FX.cardProfiles({currentKeywords=equips,mechanicCapabilities=equips})
check(#equipment==1 and equipment[1].parameter=='Equip legendary creature {3}\nEquip {7}' and not FX.profile('equip').parameter,
    'Blackblade Reforged keeps both distinct native equip costs in its inspector and one battlefield badge')
local granted={keywords={'trample'},currentKeywords={{id='trample',name='trample'}},printing={keywords={}}}
check(FX.cardProfiles(granted)[1].gained and FX.tooltip(granted)=='Trample · granted',
    'A granted native combat keyword stays identified when the current descriptor array is present')
granted.printing.keywords={'trample'}
check(not FX.cardProfiles(granted)[1].gained,'Replacing printed keyword metadata refreshes the grant indication')
granted.currentKeywords={}
check(#FX.cardProfiles(granted)==0,'Legacy traits cannot restore an explicitly removed current ability')
local secret={id='secret',hidden=true,faceDown=true,colors={'R'},currentKeywords={{id='haste'}},mechanicCapabilities={{id='mutate'}}}
check(#FX.cardProfiles(secret)==1 and FX.cardProfiles(secret)[1].id=='face_down'and not FX.hasOptions(secret),'Hidden faces never leak their printed mechanics or private capabilities')
check(FX.color(secret)[1]==FX.color({faceDown=true,colors={'U'}})[1],'A hidden color cannot change effect tint')
check(#FX.cardProfiles({hidden=true,keywords={'haste'}})==0,'A private hand back does not advertise a face-down mechanic')
check(FX.operation({type='zone',fromZone='BATTLEFIELD',toZone='GRAVEYARD'})=='departure','A generic graveyard move does not claim destruction or sacrifice')
check(FX.operation({nativeType='DESTROYED_PERMANENT'})=='destroy'and FX.operation({nativeType='SACRIFICED_PERMANENT'})=='sacrifice','Confirmed native operation types retain distinct material treatments')
check(FX.operation({type='impact',manaValue=12})==nil,'A resolved large spell is not assumed to enter the battlefield')
check(FX.operation({type='impact',entry=true})=='entry','An actual native entry may receive the arrival recipe')
check(FX.operation({operation='enter_battlefield',entry=true})=='entry','The production adapter uses the same actual-entry presentation contract')
check(FX.operation({operation='resolved',successful=true})=='resolve'and FX.operation({operation='resolved',successful=false})==nil,'Only a confirmed native successful resolution receives its outcome recipe')
check(FX.operation({type='resolve',success=false})==nil,'A countered or unconfirmed resolution has no successful payoff')
check(FX.operation({operation='ability',nativeType='TRIGGERED_ABILITY'})=='trigger'and FX.operation({operation='ability',nativeType='ACTIVATED_ABILITY'})=='activation','Production generic ability operations retain exact native trigger/activation identity')
check(FX.operation({operation='return_to_hand'})=='return'and FX.operation({operation='mana_generated'})=='mana_added','Production native operation names reach their destination and payment treatments')
local contextual=FX.newDirector();local hasty={id='haste',currentKeywords={{id='haste'}}}
FX.queue(contextual,{id='attack',operation='attack',sourceId='haste',targetId='opponent'},hasty)
check(contextual.pending[1].profile.id=='haste','A confirmed attack can accent the attacker\'s current native Haste without inventing attack permission')
FX.flush(contextual,function(id)return id=='haste'and{x=20,y=30,w=100,h=140}or id=='opponent'and{x=500,y=400,w=80,h=100}or nil end)
check(contextual.events[1].to.x==70 and contextual.events[1].to.y==100,'Haste attack streak stays on the actual attacker instead of the defending player')
local combatAccent=FX.newDirector();local trampler={id='trampler',currentKeywords={{id='trample'}}}
FX.queue(combatAccent,{id='combat',operation='damage',sourceId='trampler',combat=true,amount=3},trampler)
FX.queue(combatAccent,{id='burn',operation='damage',sourceId='trampler',combat=false,amount=3},trampler)
check(combatAccent.pending[1].profile.id=='trample'and combatAccent.pending[2].profile==nil,'A current Trample accent accompanies real combat damage but never noncombat burn')
local reaching=FX.newDirector();FX.queue(reaching,{id='block',operation='block',sourceId='reach',targetId='attacker'},{id='reach',currentKeywords={{id='reach'}}})
check(reaching.pending[1].profile.id=='reach','A declared native blocker can show its current public Reach interception signature')
local d=FX.newDirector();local game={revision=1,animationEvents={{id='past',operation='entry',targetId='card',commander=true}}}
FX.observe(d,game,{card=card},'game')
check(#d.pending==0,'Initial connection seeds retained events without replaying old effects')
game.revision=2;game.animationEvents[#game.animationEvents+1]={id='new',operation='entry',targetId='card',commander=true}
FX.observe(d,game,{card=card},'game');check(#d.pending==1,'A new native entry queues exactly one presentation')
FX.observe(d,game,{card=card},'game');check(#d.pending==1,'Duplicate snapshots do not repeat the same event')
local function anchor(key)return key=='card'and{x=10,y=20,w=100,h=140}or nil end
FX.flush(d,anchor);check(#d.events==1 and d.events[1].commander,'Resolved screen anchors retain actual commander identity')
FX.update(d,.15,{});local _,dy=FX.offset(d,card,{})
check(dy~=0,'Native entry contributes a card rise/fall pose without waiting for an animation callback')
check(FX.offset(d,card,{reducedMotion=true})==0,'Reduced motion suppresses card displacement')
FX.update(d,2,{presentationPacing='Minimal'});check(#d.events==0 and#d.pool==1,'Completed effects return their object to the bounded pool')
check(next(d.pool[1])==nil,'Released pooled effects retain no former card, player or hidden state')
game.revision=1;FX.observe(d,game,{card=card},'game');check(#d.pending==0,'A revision rollback rebuilds decoration instead of replaying history')
local bounded=FX.newDirector();bounded.initialized=true;bounded.identity='crowd'
local events={};for i=1,100 do events[i]={id='wipe-'..i,operation='destroy',targetId='card-'..i,batchId='one-native-resolution'}end
FX.observe(bounded,{revision=1,animationEvents=events},{card=card},'crowd');FX.flush(bounded,function(key)return type(key)=='string'and key:match('^card%-')and{x=10,y=20,w=100,h=140}or nil end)
check(#bounded.events==64 and bounded.stats.dropped==36,'A hundred native outcomes keep a bounded visual backlog without merging rules events')
check(bounded.major and bounded.major.count==100,'One actual native batch retains its full affected count despite the decoration cap')
local trails=FX.newDirector();trails.initialized=true;trails.identity='trails';local transfers={}
for i=1,50 do transfers[i]={id='draw-'..i,nativeType='DREW_CARD',targetId='card'}end
FX.observe(trails,{revision=1,animationEvents=transfers},{card=card},'trails');FX.flush(trails,anchor)
check(#trails.events==32,'Simultaneous transfer trails have an independent bound')
local travel=FX.newDirector();FX.queue(travel,{id='native-flashback-cast',operation='cast',sourceId='spell',targetId='spell',playerId='p',fromZone='GRAVEYARD',toZone='STACK',castMode='flashback'},nil)
FX.flush(travel,function()return nil end,{},nil,{p={graveyard={x=10,y=20,w=80,h=110}}},nil,{stack={x=800,y=100,w=160,h=90}},{{id='stack',sourceId='spell',kind='spell'}})
check(travel.events[1].from.x==50 and travel.events[1].to.x==880,'A flashback cast travels from the actual graveyard zone to its exact native stack row')
local lines={};love={graphics={setColor=function()end,setLineWidth=function()end,polygon=function()end,circle=function()end,
    line=function(...)lines[#lines+1]={...}end,arc=function()end,ellipse=function()end,rectangle=function()end,setLineJoin=function()end,push=function()end,pop=function()end}}
local r={model={page='table',settings={},game={stack={{id='stack-1',sourceId='source',controllerId='human',targetIds={'target'}}},combat={groups={}}},stackHover=nil,stackHits={}},
    colors={accent={.4,.9,.8},purple={.7,.5,1}},boardPlayers={},cardRects={target={x=500,y=200,w=100,h=140},source={x=12,y=14,w=30,h=40}},
    stackRows={['stack-1']={x=700,y=100,w=180,h=120,visible=true}},assets={iconSymbol=function()end}}
Board.links(r);check(#lines==0,'Unhovered stack objects do not leave permanent full-table target arrows')
r.hoverStackId='stack-1';Board.links(r)
check(#lines>0 and lines[1][1]>650 and lines[1][3]>=500,'Hovered stack connections originate at the exact visible stack row, not the source preview')
lines={};r.stackRows['stack-1'].visible=false;Board.links(r);check(#lines==0,'A clipped or closed stack row cannot keep a stale arrow')
r.stackRows['stack-1'].visible=true;r.previousCardRects={target=r.cardRects.target};r.cardRects.target=nil;lines={};Board.links(r)
check(#lines==0,'A departed target ghost is never reused as a current target connection')
r.cardRects.target={x=500,y=200,w=100,h=140};r.model.game.stack[1].targets={{id='target',changedZones=true}};lines={};Board.links(r)
check(#lines==0,'A native changed-zones target never redirects to a new incarnation sharing its card UUID')
r.model.game.stack[1].targetIds=nil;lines={};Board.links(r)
check(#lines==0,'Structured target metadata preserves changed-zones safety without a legacy target ID array')
local fragmentBudget=FX.newDirector()
for i=1,32 do FX.queue(fragmentBudget,{id='fragments-'..i,operation='cast',sourceId='card',targetId='card',castMode='flashback'},card)end
FX.flush(fragmentBudget,anchor);r.assets.particles={};for i=1,245 do r.assets.particles[i]={}end
FX.draw(fragmentBudget,r);check(fragmentBudget.stats.drawPrimitives==256,'Flashback fragments share the particle cap with existing native-state effects')
for _,p in pairs(FX.profiles)do FX.glyph(p,0,0,20,0)end
check(true,'Every explicit and composed glyph renders through supported vector primitives')
print('Mechanic FX contracts: '..count..' passed')
