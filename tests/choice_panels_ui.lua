-- Actual production callbacks and Slab controls over clearly labeled native
-- protocol fixtures. The action ledger is not a substitute for engine tests.
local json=require('lib.json');local actions={}
package.preload['app.api']=function()return{escape=function(v)return tostring(v)end,new=function()return{
 request=function(_,service,method,path,body,callback)
  if service=='engine'and path=='/session/action'then actions[#actions+1]=json.decode(json.encode(body));callback(nil,nil,200)
  elseif callback then callback(nil,nil,404)end
 end,update=function()end,quit=function()end,setNativeSession=function()end,escape=function(v)return tostring(v)end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Choices=require('app.card_choices')
assert(love.filesystem.load('application-main.lua'))()
local output=assert(os.getenv('L2G_CHOICE_PANELS_OUTPUT'))
local m,r,v,p,runner;local clock,wake=0,0;local mouse={x=2,y=2};local down,keys,dispatch={},{},{}
local controls,labels,scopes,shots,checks,captures,modes={},{},{},{},{},{},{}
local function clone(value)return json.decode(json.encode(value))end
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('CHOICE PANELS UI PASS '..label)end
local function wait(seconds)wake=clock+(seconds or .06);coroutine.yield()end
local function diceFinished()for _=1,160 do if not require('app.dice').busy(r)then wait(.12);return end;wait(.05)end;error('Native opening roll did not finish')end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;dispatch.mousemoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy,false)end
local function press(box,button)assert(box,'Missing actual control');move(box.x+box.w/2,box.y+box.h/2);wait(.04);down[button or 1]=true;dispatch.mousepressed(mouse.x,mouse.y,button or 1,false,1);wait(.05)end
local function release(button)down[button or 1]=nil;dispatch.mousereleased(mouse.x,mouse.y,button or 1,false,1);wait(.12)end
local function click(box,button)press(box,button);release(button)end
local function key(key,held)keys[key]=held;dispatch[held and'keypressed'or'keyreleased'](key,key,false)end
local function typeAt(box,text)
 click(box);key('lctrl',true);key('a',true);wait(.04);key('a',false);key('lctrl',false);dispatch.textinput(text);wait(.12)
end
local function shot(name)shots[#shots+1]=name;wait(.1)end
local function card(id,name,kind,power,toughness)return{id=id,name=name,type=kind,type_line=kind,manaCost='{1}{G}',mana_cost='{1}{G}',rules='Native offered fixture',oracle_text='Native offered fixture',power=power,toughness=toughness,counters={},image_uris={}}end
local forest=card('forest-native','Forest','Basic Land — Forest');local swamp=card('swamp-native','Swamp','Basic Land — Swamp')
local spell=card('spell-native','Visible spell','Sorcery');local bear1=card('bear-one','First blocker','Creature — Bear','2','2');local bear2=card('bear-two','Second blocker','Creature — Bear','2','2');local attacker=card('attacker-native','Native menace attacker','Creature — Giant','5','5')
local hidden={id='private-native',name='Unentitled secret',hidden=true,faceDown=true}
local function scene(prompt)
 return{gameId='choice-panels-fixture',running=true,revision=1,phase='COMBAT',step='DECLARE_BLOCKERS',turn=3,activePlayerId='opponent',priorityPlayerId='human',priority={autoPass=false,stops={},opponentStops={}},prompt=prompt,
  players={{id='human',human=true,isLocal=true,name='Fixture player',life=20,librarySize=40,hand={},command={},battlefield={clone(bear1),clone(bear2)},graveyard={clone(forest),clone(spell)},exile={clone(swamp),clone(hidden)},mana={}},
  {id='opponent',name='Fixture opponent',life=20,librarySize=40,hand={},command={},battlefield={clone(attacker)},graveyard={},exile={},mana={}}},combat={groups={{attackerId=attacker.id,attackerIds={attacker.id},blockerIds={bear1.id,bear2.id},minBlockers=2,maxBlockers=0,declarationConfirmed=false}}},stack={},log={},lookedAt={}}
end
local revision=100
local function adopt(prompt)
 revision=revision+1;local game=scene(prompt);game.revision=revision;m.replay=nil;m.zoneView=nil;m.inspectCard=nil;m.answeredPrompt=nil;m.actionBusy=false;m:setGame(game);m.page='table';v.cardChoiceState=nil;v.combatChoiceState=nil;v.cardChoiceDrag=nil;v.combatChoiceDrag=nil;return game
end
local function inputKey(nativeIndex)return'native-amount-'..nativeIndex..'/amount-'..v.combatChoiceState.identity..'-'..nativeIndex end
local function boundsCheck(label)
 local w,h=Layout.dimensions();for _,id in ipairs({'Confirm distribution'})do local b=assert(controls[id],id);check(b.x>=0 and b.y>=0 and b.x+b.w<=w and b.y+b.h<=h,label..' confirmation stays within the logical viewport')end
end
local function amount(id)
 return{id=id,type='multi_amount',message='Assign 5 combat damage to the blocking creatures',min=5,max=5,actionable={},choices={},combat={role='attacker_damage'},damageSourceId=attacker.id,damageSourceCard=clone(attacker),amountMessages={{nativeIndex=1,message='First blocker',min=0,max=5,defaultValue=2,targetId=bear1.id,card=clone(bear1)},{nativeIndex=2,message='Second blocker',min=0,max=5,defaultValue=3,targetId=bear2.id,card=clone(bear2)}}}
end
local function scenario()
 for _,mode in ipairs({{1120,720,1,1},{1440,900,1.25,.75}})do
  m.settings.resolution=mode[1]..'x'..mode[2];m.settings.uiScale=mode[3];m.settings.renderScale=mode[4];p:apply(true);wait(.18);local suffix=mode[3]==1 and'minimum'or'scaled';modes[#modes+1]={physical={love.graphics.getDimensions()},logical={Layout.dimensions()},scale=Layout.scale,renderScale=mode[4]}
  local prompt=amount(revision+1);adopt(prompt);wait(.18);boundsCheck(suffix)
  check(v.cardChoiceModal=='native-amount-distribution'and r:inputBlocked(),'The actual amount popup locks background board input: '..suffix)
  local before=#actions;local first,second=v.combatChoiceHits[1],v.combatChoiceDrops[2];press(first);check(v.combatChoiceDrag~=nil,'Production mouse press routes to the amount card drag through its own modal: '..suffix)
  move(second.x+second.w/2,second.y+40);wait(.05);release()
  check(v.combatChoiceState.rows[1].nativeIndex==2 and#actions==before,'Actual drag rearranges targets without answering or inventing damage order: '..suffix)
  typeAt(controls[inputKey(2)],'1');typeAt(controls[inputKey(1)],'4');check(v.combatChoiceState.values[1]=='4'and v.combatChoiceState.values[2]=='1','Actual amount text fields retain each native target index after dragging: '..suffix)
  shot('amount-distribution-'..suffix);click(controls['Confirm distribution'])
  check(#actions==before+1 and actions[#actions].type=='multi_amount'and actions[#actions].value[1]==4 and actions[#actions].value[2]==1,'Actual confirmation submits the native index array once: '..suffix)
  adopt(amount(revision+1));wait(.14);typeAt(controls[inputKey(1)],'5');typeAt(controls[inputKey(2)],'5');check(controls['Confirm distribution'].disabled,'An invalid native total disables confirmation rather than silently changing amounts: '..suffix)
  dispatch.keypressed('escape','escape',false);wait(.12);check(m:prompt()and v.cardChoiceModal=='native-amount-distribution','Escape never invents a cancellation of the required native amount decision: '..suffix)
  press(v.combatChoiceHits[1]);m.zoneView={label='Exile',cards={clone(swamp)}};wait(.1);move(700,500);release();check(not v.combatChoiceDrag and#actions==before+1,'A zone opened during the drag consumes the late release without an action: '..suffix)
  m.zoneView=nil

  local legal=clone(forest);legal.selectable=true;local refused=clone(swamp);refused.selectable=false
  local select={id=revision+1,type='pick_target',message='Search the library for an offered basic land',actionable={forest.id},choices={{id=forest.id,responseType='uuid',value=forest.id}},cardPanel={interactionId='library-'..revision,kind='select',stage='select',zone='LIBRARY',cards={clone(spell),legal,refused,clone(hidden)},doneChoice={id='done',label='Done',responseType='boolean',value=false}}}
  adopt(select);wait(.18);check(v.cardChoiceHits[1].card.id==forest.id and v.cardChoiceHits[2].card.id==swamp.id,'The actual library image grid puts visible basic lands before other cards: '..suffix)
  local grey=controls['native-card-'..swamp.id..'/Swamp'];check(grey and grey.disabled and grey.tint and grey.tint[1]<.5,'Unavailable visible library cards are grey and disabled from native permissions: '..suffix)
  check(not controls['native-card-'..hidden.id..'/Unentitled secret'],'The library grid never creates controls for a concealed identity: '..suffix)
  before=#actions;click(grey);check(#actions==before,'Clicking the grey library candidate cannot answer the native prompt: '..suffix)
  click(grey,2);check(m.inspectCard and m.inspectCard.id==swamp.id and#actions==before,'An unavailable visible card remains inspectable by right-click without becoming actionable: '..suffix);click(controls['Close details'])
  shot('library-grid-'..suffix);click(controls['native-card-'..forest.id..'/Forest']);check(#actions==before+1 and actions[#actions].value==forest.id,'The available basic-land image submits its original native UUID: '..suffix)

  local zonePrompt={id=revision+1,type='pick_target',message='Choose a card in your graveyard',actionable={forest.id},choices={{id=forest.id,responseType='uuid'}}}
  adopt(zonePrompt);m.zoneView={label='Fixture player · Graveyard',cards=m.game.players[1].graveyard};wait(.18)
  local zoneCard=controls['zone-card-'..forest.id..'/Forest'];check(zoneCard and zoneCard.image,'Graveyard browsing uses a real card-image button grid: '..suffix)
  before=#actions;shot('graveyard-grid-'..suffix);click(zoneCard);check(#actions==before+1 and actions[#actions].value==forest.id and not m.zoneView,'Actual graveyard image click forwards the offered UUID and closes the zone: '..suffix)
  m.zoneView={label='Fixture player · Exile',cards={clone(swamp),clone(hidden)}};wait(.16);local back=controls['zone-card-'..hidden.id..'/Face-down card'];check(back and back.disabled and not controls['zone-card-'..hidden.id..'/Unentitled secret'],'Exile displays an unentitled card only as a disabled generic back: '..suffix)
  shot('exile-grid-'..suffix);click(controls['zone-card-'..swamp.id..'/Swamp'],2);check(m.inspectCard and m.inspectCard.id==swamp.id,'Actual right-click opens a visible exiled card without answering: '..suffix)
  click(controls['Close details']);click(controls['Close zone'])

  local attack={id=revision+1,type='select',message='Choose attackers',actionable={bear1.id,bear2.id},combat={role='attackers',declarationConfirmed=false,selectedAttackerIds={bear1.id},message='Choose individual creatures, then Done.'},choices={{id=bear1.id,label=bear1.name,responseType='uuid',card=clone(bear1)},{id=bear2.id,label=bear2.name,responseType='uuid',card=clone(bear2)},{id='all',label='All attack',responseType='string',value='all'},{id='done',label='Done',responseType='boolean',value=true}}}
  adopt(attack);wait(.18);local chosen=controls['individual-combat-'..bear1.id..'/First blocker'];local individual=controls['individual-combat-'..bear2.id..'/Second blocker']
  check(chosen and chosen.active and individual and not individual.disabled,'Individual attacker images retain the native provisional selection separately from All attack: '..suffix)
  before=#actions;shot('individual-attackers-'..suffix);click(individual);check(#actions==before+1 and actions[#actions].type=='uuid'and actions[#actions].value==bear2.id,'An individual attacker button sends only that offered UUID: '..suffix)
 end
 local nativeFrames=love.filesystem.getInfo('native-attackers.json')and love.filesystem.getInfo('native-damage.json')
 if nativeFrames then
  local native=json.decode(assert(love.filesystem.read('native-attackers.json')));m.zoneView=nil;m.inspectCard=nil;m.answeredPrompt=nil;m.actionBusy=false;m:setGame(native);v.cardChoiceState=nil;v.combatChoiceState=nil;wait(.2)
  if require('app.dice').busy(r)then local before=#actions;click({x=50,y=250,w=80,h=140});check(#actions==before and not v.combatChoiceDrag and not controls['individual-combat-'..native.prompt.choices[1].id..'/'..native.prompt.choices[1].card.name],'The opening dice overlay hides native-choice controls and blocks their custom input')end
  diceFinished()
  local selected={};for _,id in ipairs(native.prompt.combat.selectedAttackerIds)do selected[id]=true end
  local candidate,active
  for _,choice in ipairs(native.prompt.choices)do if choice.responseType=='uuid'then local b=controls['individual-combat-'..choice.id..'/'..choice.card.name];if selected[choice.id]then active=b else candidate={button=b,id=choice.id}end end end
  check(active and active.active and candidate and candidate.button,'The genuine native attacker frame shows its selected and still-offered individual creatures')
  local before=#actions;shot('genuine-native-attackers');click(candidate.button);check(#actions==before+1 and actions[#actions].value==candidate.id,'Actual click on the genuine native frame submits its exact offered attacker UUID')
  native=json.decode(assert(love.filesystem.read('native-damage.json')));m.answeredPrompt=nil;m.actionBusy=false;m:setGame(native);v.combatChoiceState=nil;wait(.2);diceFinished()
  check(native.prompt.combat.role=='attacker_damage'and#v.combatChoiceHits==2,'The genuine native menace frame opens the two-blocker image/amount decision')
  local drop=v.combatChoiceDrops[1];press(v.combatChoiceHits[2]);move(drop.x+drop.w/2,drop.y+50);wait(.06);release();typeAt(controls[inputKey(1)],'1');typeAt(controls[inputKey(2)],'2')
  check(v.combatChoiceState.rows[1].nativeIndex==2 and v.combatChoiceState.rows[1].entry.targetId==native.prompt.amountMessages[2].targetId,'Native exact blocker identities remain bound to the original indices after an actual drag')
  before=#actions;shot('genuine-native-menace-damage');click(controls['Confirm distribution']);check(#actions==before+1 and actions[#actions].type=='multi_amount'and actions[#actions].value[1]==1 and actions[#actions].value[2]==2,'The genuine native damage frame submits [1,2], the same accepted native distribution checked by the bridge fixture')
  if love.filesystem.getInfo('native-land-search.json')then
   native=json.decode(assert(love.filesystem.read('native-land-search.json')));m.answeredPrompt=nil;m.actionBusy=false;m:setGame(native);v.combatChoiceState=nil;v.cardChoiceState=nil;wait(.2);diceFinished()
   check(v.cardChoiceHits[1].card.name=='Forest'and v.cardChoiceHits[2].card.name=='Island','The genuine Evolving Wilds library search puts both explicitly native Basic lands first')
   local nonbasic,forestChoice
   for _,entry in ipairs(native.prompt.cardPanel.cards)do if entry.name=='Temple Garden'then nonbasic=entry elseif entry.name=='Forest'then forestChoice=entry end end
   local refused=controls['native-card-'..tostring(nonbasic.choiceId or nonbasic.id)..'/Temple Garden'];check(refused and refused.disabled and refused.tint[1]<.5,'The genuine native-entitled nonbasic land is grey and cannot satisfy the Basic-land prompt')
   before=#actions;shot('genuine-native-land-search');click(refused);check(#actions==before,'Actual click on the genuine grey nonbasic candidate sends no action')
   typeAt(controls['native-card-search'],'Forest');check(#v.cardChoiceHits==1 and v.cardChoiceHits[1].card.id==forestChoice.id,'Actual choice search filters only the entitled native candidate grid')
   click(controls['native-card-'..tostring(forestChoice.choiceId or forestChoice.id)..'/Forest']);check(#actions==before+1 and actions[#actions].value==forestChoice.id,'The actual searched Forest button submits the same UUID accepted by the native Evolving Wilds fixture')
  end
 end
 local optional=amount(revision+100);optional.choices={{id='offered-cancel',label='Cancel amount choice',responseType='boolean',value=false}};adopt(optional);wait(.18)
 local cancel=controls['amount-option-1/Cancel amount choice'];check(cancel and not cancel.disabled,'An actual offered generic amount Cancel choice remains visible in the new popup')
 local before=#actions;click(cancel);check(#actions==before+1 and actions[#actions].type=='boolean'and actions[#actions].value==false,'The explicit Cancel button forwards its offered native false response without inventing an answer')
 adopt(amount(revision+200));wait(.15);click(controls[inputKey(1)]);check(S.IsAnyInputFocused(),'The amount field really has Slab keyboard focus before an asynchronous transition')
 m.game.prompt=nil;m.game.revision=m.game.revision+1;wait(.15);check(not S.IsAnyInputFocused()and not v.cardChoiceModalKey,'An asynchronously disappearing prompt clears hidden numeric-input focus and its modal identity')
 adopt(amount(revision+201));wait(.15);click(controls[inputKey(1)]);local nextPrompt=amount(revision+202);m.game.prompt=nextPrompt;m.game.revision=m.game.revision+1;wait(.15)
 check(not S.IsAnyInputFocused()and v.combatChoiceState.prompt.id==nextPrompt.id,'A replacement native prompt in the same game clears the previous amount field focus')
 click(controls[inputKey(1)]);local nextGame=scene(amount(revision+203));nextGame.gameId='replacement-choice-game';m:setGame(nextGame);wait(.15)
 check(not S.IsAnyInputFocused()and v.cardChoiceModalKey:find('replacement-choice-game',1,true),'A replacement game cannot retain keyboard focus in a prior native choice opening')
 m.game.prompt=nil;m.game.revision=m.game.revision+1;m.zoneView={label='Exile focus regression',cards={clone(swamp)}};wait(.2);click(controls['zone-search'])
 check(S.IsAnyInputFocused(),'The actual zone-search control has keyboard focus before closing its modal')
 dispatch.keypressed('escape','escape',false);dispatch.keyreleased('escape','escape');wait(.15)
 check(not m.zoneView and not S.IsAnyInputFocused()and not v.inputLock,'Escape clears the closed zone grid, hidden search focus and obsolete input lock')
 local file=assert(io.open(output..'/report.json','w'));file:write(json.encode({checks=checks,captures=captures,modes=modes,actions=actions,nativeFrames=nativeFrames~=nil,scope='Actual production main input callbacks, LÖVE rendering and Slab drag/text/button dispatch with explicit native-protocol presentation fixtures and optional genuine exported native attacker/menace-damage frames. Native legality/effects are independently tested by bridge fixtures; the UI uses an isolated action ledger with no service/network/user cache/native match.'}));file:close();love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return down[button]==true end;love.keyboard.isDown=function(...)for i=1,select('#',...)do if keys[select(i,...)]then return true end end;return false end;love.keyboard.isScancodeDown=love.keyboard.isDown
 m=Model.new();m.loaded=true;m.settingsLoaded=true;m.profileLoaded=true;m.settings.windowMode='Windowed';m.settings.skybox='Off';m.settings.showCardArt=false;m.settings.animations=false;m.settings.reducedMotion=true;m.settings.particles=false;m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.vsync=false;m.settings.autoFollowTurn=false;m.uiLayout={};m.catalogHealth={ready=false};m.profile={};m.logOpen=false;m.stackOpen=false
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p.appliedLoaded=true
 for i=1,30 do local name=debug.getupvalue(love.keypressed,i);if not name then break end;if name=='model'then debug.setupvalue(love.keypressed,i,m)elseif name=='renderer'then debug.setupvalue(love.keypressed,i,r)elseif name=='view'then debug.setupvalue(love.keypressed,i,v)end end
 for _,name in ipairs({'mousemoved','mousepressed','mousereleased','wheelmoved','keypressed','keyreleased','textinput'})do dispatch[name]=love[name];love[name]=function()end end
 local Cursor=require('lib.Slab.Internal.Core.Cursor');local Window=require('lib.Slab.Internal.UI.Window');local push,pop=S.PushID,S.PopID
 S.PushID=function(id)scopes[#scopes+1]=id;return push(id)end;S.PopID=function()scopes[#scopes]=nil;return pop()end
 local function bounds()local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);return{x=x,y=y,w=w,h=h}end
 for _,name in ipairs({'Button','Input'})do local original=S[name];S[name]=function(label,options)local result=original(label,options);local b=bounds();b.disabled=options and options.Disabled;b.active=options and options.Active;b.image=options and options.Image~=nil;b.tint=options and options.Image and options.Image.Color;controls[(#scopes>0 and table.concat(scopes,'/')..'/'or'')..label]=b;return result end end
 local text=S.Text;S.Text=function(label,options)local result=text(label,options);labels[label]=bounds();return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<65,'Choice panel GUI timed out');S.Update(dt);r:update(dt);r.uiHovered=not S.IsVoidHovered()
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,problem=coroutine.resume(runner);assert(ok,problem)end
 controls={};labels={};v:build()
end
function love.draw()
 p:beginFrame();r:draw();p:endScene();S.Draw({DeferOverlays=true});love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();Choices.draw(v);love.graphics.pop();S.DrawOverlays();p:endFrame()
 if#shots>0 then local path=output..'/'..table.remove(shots,1)..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local file=assert(io.open(path,'wb'));file:write(data:encode('png'):getString());file:close()end)end
end
function love.quit()if p then p:quit()end;S.OnQuit()end
function love.errorhandler(message)local problem=debug.traceback(tostring(message),2);print(problem);local file=assert(io.open(output..'/failure.txt','w'));file:write(problem);file:close();return function()return 1 end end
