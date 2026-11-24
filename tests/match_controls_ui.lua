-- Production main callbacks and Slab controls; isolated synthetic protocol data.
local json=require('lib.json');local requests={}
package.preload['app.api']=function()return{escape=function(value)return tostring(value)end,new=function()return{
 request=function(_,service,method,path,body,callback)
  if method=='POST'then requests[#requests+1]={service=service,method=method,path=path,body=json.decode(json.encode(body or{}))}end
  if callback then
   local receipt=service=='room' and method=='POST' and {ok=true} or nil
   callback(receipt,nil,method=='POST'and 200 or 404)
  end
 end,update=function()end,quit=function()end,setNativeSession=function()end,escape=function(value)return tostring(value)end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Choices=require('app.card_choices')
assert(love.filesystem.load('application-main.lua'))()
local output=assert(os.getenv('L2G_MATCH_CONTROLS_OUTPUT'));local m,r,v,p,runner
local clock,wake=0,0;local mouse={x=2,y=2};local down,dispatch,buttons,shots,checks,captures,modes={},{},{},{},{},{},{}
local undoTrace={}
local buttonImages={}
local detailRegion
local textLines={}
local function clone(value)return json.decode(json.encode(value))end
local function check(ok,label,details)assert(ok,label..(not ok and details and' / '..json.encode(details)or''));checks[#checks+1]=label;print('MATCH CONTROLS UI PASS '..label);io.stdout:flush()end
local function wait(t)wake=clock+(t or .07);coroutine.yield()end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;dispatch.mousemoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy,false)end
local function press(box,button)
 assert(box,'Missing actual input target');button=button or 1;move(box.x+box.w/2,box.y+box.h/2);wait(.04);down[button]=true;dispatch.mousepressed(mouse.x,mouse.y,button,false,1);wait(.05)
end
local function release(button)button=button or 1;down[button]=nil;dispatch.mousereleased(mouse.x,mouse.y,button,false,1);wait(.1)end
local function click(box,button)press(box,button);release(button)end
local function shot(name)shots[#shots+1]=name;wait(.09)end
local function hit(id)for _,entry in ipairs(r.hits)do if entry.card and entry.card.id==id then return entry end end end
local function scene(count)
 local players={}
 for i=1,count do players[i]={id='p'..i,name=i==1 and'Synthetic local player'or'Synthetic opponent '..i,human=i==1,isLocal=i==1,seat=i-1,life=20,hand=i==1 and{{id='hand-native',name='Native offered hand card',type='Instant',manaCost='{1}{U}',rules='Synthetic input fixture'}}or{},handCount=i==1 and 1 or 0,libraryCount=60,battlefield={{id='p'..i..'-creature',name='Native visible creature',type='Creature',manaCost='{2}{G}',power='3',toughness='3'}},command={},graveyard={},exile={},mana={}}end
 return{gameId='SYNTHETIC-MATCH-CONTROLS-'..count,running=true,error=json.null,revision=1,turn=2,phase='Precombat Main',step='Precombat Main',activePlayerId='p1',players=players,stack={},log={},prompt={id=100+count,type='select',priority=true,message='Choose an offered card',actionable={'hand-native'},choices={{id='hand-native',responseType='uuid'}}},priority={pending=false,canEndTurn=true,autoPass=false,stops={own={},opponent={}}}}
end
local function adopt(frame)
 m.replay=nil;m.page='table';m.zoneView=nil;m.inspectCard=nil;m.settingsOpen=false;m.answeredPrompt=nil;m.actionBusy=false;m.priorityBusy=false;m.roomConnectionId=nil;m.room=nil;m.roomBusy=false;m.gameBusy=false;m:setGame(frame)
 m.logOpen=false;m.stackOpen=false
 r.cameraIdentity=nil;r.poses={};r.ghosts={};r.drag=nil;v.cardChoiceState=nil;v.cardChoiceModal=nil;v.combatChoiceState=nil;move(2,2)
end
local function complete(kind)
 local frame=scene(2);frame.running=false;frame.result={gameId=frame.gameId,completed=true,outcome=kind};frame.players[1].won=kind=='win';frame.players[1].lost=kind=='loss';adopt(frame)
 m.logOpen=true;m.stackOpen=true
 m.lastMatchRequest={format='Modern',playerDeckId='synthetic-player-deck',botDeckId='synthetic-bot-deck',players=2}
end
local function lastRequest(path)local last=requests[#requests];return last and last.path==path and last end
local function bounds(label)
 local box=assert(buttons[label],label);local w,h=Layout.dimensions();check(box.x>=0 and box.y>=0 and box.x+box.w<=w and box.y+box.h<=h,'Actual '..label..' control stays inside the scaled viewport');return box
end
local function iconInk(label)
 local image=assert(buttonImages[label],'Missing actual icon image');local data=image:newImageData();local count=0
 for y=0,data:getHeight()-1 do for x=0,data:getWidth()-1 do local rr,gg,bb,aa=data:getPixel(x,y);if aa>.2 and rr+gg+bb>.5 then count=count+1 end end end
 data:release();return count
end
local function spaceShortcut()
 local frame=scene(2)
 local passage={id='hand-native',label='Fabled Passage',responseType='uuid'}
 local done={id='done',label='Pass / Done',responseType='boolean',value=true}
 frame.prompt.choices={passage,done};adopt(frame)
 local function space(repeated)
  dispatch.keypressed('space','space',repeated or false)
  dispatch.keyreleased('space','space')
 end
 local before=#requests
 space()
 local request=lastRequest('/session/action')
 check(#requests==before+1 and request and request.body.type=='boolean' and request.body.value==true and request.body.promptId==frame.prompt.id,
  'Space passes native priority even when Fabled Passage appears first')
 frame.prompt.id=frame.prompt.id+1;adopt(frame);before=#requests;space(true)
 check(#requests==before,'Holding Space cannot advance a later decision through keyboard repeat')
 frame.prompt.choices={passage,{id='done',label='Pass',responseType='boolean',value=true,selectable=false}}
 adopt(frame);before=#requests;space()
 check(#requests==before,'Space ignores disabled pass choices and card names when passing is unavailable')
 frame.prompt.choices={passage,done}
 frame.prompt.priority=nil
 for _,role in ipairs({'attackers','blockers'}) do
  frame.prompt.combat={role=role};adopt(frame);before=#requests;space()
  request=lastRequest('/session/action')
  check(#requests==before+1 and request.body.type=='boolean' and request.body.value==true,'Space confirms the native '..role..' declaration')
 end
 frame.prompt.combat=nil
 for _,kind in ipairs({'play_mana','choose_ability','pick_target'}) do
  frame.prompt.type=kind;adopt(frame);before=#requests;space()
  check(#requests==before,'Space leaves '..kind..' untouched even with Passage and a boolean choice')
 end
end
local function scrollDetails(suffix)
 local frame=scene(2)
 local host=frame.players[1].battlefield[1]
 host.currentRules=string.rep('Pay {2}{G} to activate this synthetic ability.\n',36)
 host.counters={['+1/+1']=3}
 host.printing={power='2',toughness='2',type_line='Creature',set='ORI',number='12'}
 host.selectedPrintingId='preferred-'..suffix
 m:rememberCard({id='test-print',printing_id='test-print',name=host.name,oracle_text='Reach',type_line='Creature',artist='Default artist',set_name='Default set'})
 adopt(frame);m.inspectCard=host;wait(.15)
 local printed=table.concat(textLines,'\n')
 check(printed:find('XMage printing · ORI #12',1,true) and not printed:find('Default artist',1,true),'Unresolved preferred printing keeps the native set and suppresses another artist: '..suffix)
 m.printingMetadata[host.selectedPrintingId]={card={id='test-card',printing_id=host.selectedPrintingId,name=host.name,set='TST',set_name='Preferred set',collector_number='23',artist='Preferred artist'}}
 wait(.12);printed=table.concat(textLines,'\n')
 check(printed:find('Preferred set · #23 · Art by Preferred artist',1,true) and printed:find('XMage printing · ORI #12',1,true),'Resolved scan credits and the native edition retain distinct identities: '..suffix)
 local close=bounds('Close details')
 click(assert(buttons['Show current rules']))
 check(v.inspectCurrentRules and detailRegion,'Full details expand current rules independently of Oracle text: '..suffix)
 move(detailRegion.x+detailRegion.w*.65,detailRegion.y+detailRegion.h*.6);wait(.05)
 dispatch.wheelmoved(0,-14);wait(.15)
 local _,scrollY=require('lib.Slab.Internal.UI.Region').Transform(detailRegion.id,0,0)
 check(scrollY < -100 and buttons['Close details'].y==close.y,'Long rules scroll while Close details stays fixed: '..suffix)
 click(close)
 m.inspectCard=frame.players[2].battlefield[1];wait(.14)
 local _,freshY=require('lib.Slab.Internal.UI.Region').Transform(detailRegion.id,0,0)
 check(freshY==0 and not v.inspectCurrentRules,'A new card opens at the top with its own rules state: '..suffix)
 click(assert(buttons['Close details']))
end
local function scenario()
 spaceShortcut()
 for _,mode in ipairs({{1120,720,1,1},{1440,900,1.25,.75}})do
  m.settings.resolution=mode[1]..'x'..mode[2];m.settings.uiScale=mode[3];m.settings.renderScale=mode[4];p:apply(true);wait(.15)
  local suffix=mode[3]==1 and'minimum'or'scaled';modes[#modes+1]={physical={love.graphics.getDimensions()},logical={Layout.dimensions()},uiScale=Layout.scale,renderScale=mode[4]}
  scrollDetails(suffix)
  adopt(scene(2));m.settings.animations=true;m.settings.reducedMotion=false;wait(.2)
  local hand=assert(hit('hand-native'));local w,h=Layout.dimensions();move(hand.x+hand.w/2,h-55);wait(.3);hand=assert(hit('hand-native'));press(hand)
  check(r.drag and r.drag.card.id=='hand-native','Actual main left press starts the offered hand drag: '..suffix)
  local origin={x=r.drag.x+r.drag.w/2,y=r.drag.y+r.drag.h/2};move(w*.55,h*.42);wait(.08);local before=#requests
  down[2]=true;dispatch.mousepressed(mouse.x,mouse.y,2,false,1)
  local ghost=r.ghosts[#r.ghosts]
  check(not r.drag and ghost and not ghost.accepted and math.abs(ghost.target.x-origin.x)<.01 and math.abs(ghost.target.y-origin.y)<.01,'Right press cancels locally and returns the ghost to the exact original hand anchor: '..suffix)
  check(#requests==before and#m.game.players[1].hand==1 and m.game.players[1].hand[1].id=='hand-native','Cancellation preserves the hand card and sends no native action: '..suffix)
  shots[#shots+1]='cancel-return-'..suffix;release(2);release(1)
  check(#requests==before and not r.drag and not r.panGesture and not m.inspectCard,'Both late releases after cancel cannot cast, inspect or begin a pan: '..suffix)
  wait(.25);hand=assert(hit('hand-native'));click(hand,2)
  check(not m.inspectCard and m:pinnedTableCard().id=='hand-native','Right-click pins the exact hand card without opening a modal: '..suffix)
  hand=assert(hit('hand-native'));click(hand,3);check(m.inspectCard and m.inspectCard.id=='hand-native','Middle-click opens the hand card details: '..suffix);click(buttons['Close details'])
  m.settings.animations=false;m.settings.reducedMotion=true;adopt(scene(4));wait(.2)
  local card=assert(hit('p1-creature'));click(card,3);check(m.inspectCard and m.inspectCard.id=='p1-creature','Multiplayer middle-click opens the visible card details: '..suffix);click(buttons['Close details'])
  -- Fit Table shows the entire world. Zoom first so there is terrain to pan across.
  move(w*.6,h*.55);wait(.08);dispatch.wheelmoved(0,4);wait(.08)
  check(r.tableCamera.zoom>r.tableCamera.overviewZoom,'The wheel zooms into the fitted table before panning: '..suffix)
  local cameraX,cameraY=r.tableCamera.x,r.tableCamera.y;down[2]=true;dispatch.mousepressed(mouse.x,mouse.y,2,false,1);wait(.04);move(w*.6+55,h*.55+30);wait(.04);release(2)
  check(math.abs(r.tableCamera.x-cameraX)+math.abs(r.tableCamera.y-cameraY)>10 and not m.inspectCard,'Idle right-drag still pans the table without inspecting: '..suffix)

  local frame=scene(2);frame.prompt={id=700,type='play_mana',message='Native payment fixture',actionable={},choices={},undoChoice={id='native-undo',label='Undo last mana action',responseType='undo',value=true}};adopt(frame);wait(.2)
  local undo=bounds('Undo last mana action');check(not undo.disabled,'Native undo metadata exposes an enabled actual toolbar button: '..suffix)
  check(iconInk('Undo last mana action')>10,'The actual Undo toolbar image has visible icon pixels rather than a blank raster: '..suffix)
  local options=assert(buttons['Table options'])
  check(undo.y>options.y+options.h and undo.y+undo.h<=78 and undo.x>w*.83,'Undo leaves the turn heading, priority text, toolbar and phase strip clear: '..suffix)
  shot('native-undo-'..suffix);before=#requests;click(undo)
  local request=lastRequest('/session/action');check(#requests==before+1 and request and request.body.type=='undo'and request.body.value==true and request.body.promptId==700 and request.body.expectedGameId==frame.gameId,'Undo submits only the exact native undo response and prompt/game identity: '..suffix,{before=before,requests=requests,prompt=m:prompt(),button=buttons['Undo last mana action'],trace=undoTrace})
  m.actionBusy=true;wait(.1);check(buttons['Undo last mana action'].disabled,'Pending native action disables the undo button: '..suffix);before=#requests;click(buttons['Undo last mana action']);check(#requests==before,'A pending disabled undo cannot submit again: '..suffix)
  m.actionBusy=false;m.game.prompt.undoChoice=json.null;wait(.1);check(not buttons['Undo last mana action'],'A prompt without native undo permission exposes no undo control: '..suffix)

  for _,kind in ipairs({'win','loss','draw'})do
   complete(kind)
   if kind=='win'then
    m.confirmConcede=true;v.combatStopsOpen=true;m.actionBusy=true
    v.cardChoiceState={committing=true,gameId=m.game.gameId,lastAnswered=m.game.prompt.id,identity='retained-native-choice'}
   end
   wait(.18);bounds('Rematch');bounds('Main menu')
   check(not m:prompt()and v.inputLock=='match-complete'and not buttons['End Turn']and not buttons['Table options']and not buttons['Stack 0'],'The terminal '..kind..' view locks result controls and hides the stale native prompt and toolbar: '..suffix)
   shot('outcome-'..kind..'-'..suffix)
   if kind=='win'then
    check(not m.confirmConcede and not v.combatStopsOpen and not v.cardChoiceModal,'Completed duel retires unbuilt concede/combat/committing-choice modal locks: '..suffix)
    local count=#requests;click(buttons['Rematch']);check(#requests==count+1 and lastRequest('/session/start'),'The actual result Rematch remains clickable after an opponent finishes during retained gameplay modals: '..suffix)
   end
  end
  before=#requests;click(buttons['Rematch']);request=lastRequest('/session/start')
  check(#requests==before+1 and request and request.body.playerDeckId=='synthetic-player-deck'and request.body.botDeckId=='synthetic-bot-deck','Actual practice Rematch repeats the retained match setup once: '..suffix)
  click(buttons['Main menu']);check(m.page=='decks','Actual Main menu leaves the finished game for Decks: '..suffix)

  complete('loss');m.roomConnectionId='synthetic-connection';m.roomParticipantId='local-seat';m.room={phase='playing',config={kind='constructed'},canRematch=true};wait(.15)
  before=#requests;click(bounds('Request rematch'));request=lastRequest('/client/rooms/synthetic-connection/rematch');check(#requests==before+1 and request,'Actual PvP Request rematch uses the room coordinator instead of practice game start: '..suffix)
  m.room.rematchRequest={id='synthetic-request',gameId=m.game.gameId,requesterId='remote-seat',requesterName='Synthetic opponent',approvedSeatIds={'remote-seat'}};wait(.15)
  bounds('Accept rematch');bounds('Decline');shot('rematch-incoming-'..suffix);before=#requests;click(buttons['Accept rematch']);request=lastRequest('/client/rooms/synthetic-connection/rematch-response')
  check(#requests==before+1 and request and request.body.accept==true and request.body.requestId=='synthetic-request','Actual accept submits the current request ID and a true response: '..suffix)
  before=#requests;click(buttons['Decline']);request=lastRequest('/client/rooms/synthetic-connection/rematch-response');check(#requests==before+1 and request and request.body.accept==false and request.body.requestId=='synthetic-request','Actual decline submits the same request ID with false: '..suffix)
  m.room.rematchRequest.requesterId='local-seat';m.room.rematchRequest.approvedSeatIds={'local-seat'};wait(.15);check(buttons['Cancel rematch request']and not buttons['Accept rematch'],'The requester gets waiting/cancel controls instead of self-acceptance: '..suffix)
  shot('rematch-waiting-'..suffix);before=#requests;click(buttons['Cancel rematch request']);request=lastRequest('/client/rooms/synthetic-connection/rematch-cancel');check(#requests==before+1 and request and request.body.requestId=='synthetic-request','Actual cancel addresses only the pending rematch request: '..suffix)
 end
 local report={checks=checks,captures=captures,modes=modes,requests=requests,scope='Production keyboard and mouse callbacks, LÖVE/Slab controls and scaled rendering with synthetic priority, combat, payment and room prompts and mock transport.'}
 local out=assert(io.open(output..'/report.json','w'));out:write(json.encode(report));out:close();print('MATCH CONTROLS UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return down[button]==true end
 m=Model.new();m.loaded=true;m.settingsLoaded=true;m.profileLoaded=true;m.page='table';m.settings.windowMode='Windowed';m.settings.skybox='Off';m.settings.showCardArt=false;m.settings.animations=false;m.settings.reducedMotion=true;m.settings.particles=false;m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.vsync=false;m.settings.autoFollowTurn=false;m.settings.showTooltips=false;m.uiLayout={};m.catalogHealth={ready=false};m.profile={};m.logOpen=false;m.stackOpen=false
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p.appliedLoaded=true
 for i=1,30 do local name=debug.getupvalue(love.keypressed,i);if not name then break end;if name=='model'then debug.setupvalue(love.keypressed,i,m)elseif name=='renderer'then debug.setupvalue(love.keypressed,i,r)elseif name=='view'then debug.setupvalue(love.keypressed,i,v)end end
 for _,name in ipairs({'mousemoved','mousepressed','mousereleased','wheelmoved','keypressed','keyreleased','textinput'})do dispatch[name]=love[name];love[name]=function()end end
 local Cursor=require('lib.Slab.Internal.Core.Cursor');local Window=require('lib.Slab.Internal.UI.Window');local button=S.Button
 local textf=S.Textf;S.Textf=function(label,options)textLines[#textLines+1]=label;return textf(label,options)end
 local list=S.BeginListBox
 S.BeginListBox=function(id,options)
  if id=='card-details-text' then
   local x,y=S.GetCursorPos({Absolute=true});x,y=Window.TransformPoint(x,y)
   detailRegion={id=Window.GetItemId(id),x=x,y=y,w=options.W,h=options.H}
  end
  return list(id,options)
 end
 S.Button=function(label,options)local result=button(label,options);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);buttons[label]={x=x,y=y,w=w,h=h,disabled=options and options.Disabled};buttonImages[label]=options and options.Image and options.Image.Image
  local Mouse=require('lib.Slab.Internal.Input.Mouse');if label=='Undo last mana action'and(Mouse.IsClicked(1)or Mouse.IsReleased(1))then local mx,my=Window.GetMousePosition();undoTrace[#undoTrace+1]={x=mx,y=my,clicked=Mouse.IsClicked(1),released=Mouse.IsReleased(1),obstructed=Window.IsObstructedAtMouse(),hot=require('lib.Slab.Internal.UI.Region').GetHotInstanceId(),lock=v.inputLock,result=result}end
  return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<45,'Match controls GUI timed out');S.Update(dt);r:update(dt);r.uiHovered=not S.IsVoidHovered()
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,error=coroutine.resume(runner);assert(ok,error)end
 buttons={};buttonImages={};textLines={};v:build()
end
function love.draw()
 p:beginFrame();r:draw();p:endScene();S.Draw({DeferOverlays=true});love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();Choices.draw(v);love.graphics.pop();S.DrawOverlays();p:endFrame()
 if#shots>0 then local path=output..'/'..table.remove(shots,1)..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local out=assert(io.open(path,'wb'));out:write(data:encode('png'):getString());out:close()end)end
end
function love.quit()if p then p:quit()end;S.OnQuit()end
function love.errorhandler(message)local problem=debug.traceback(tostring(message),2);io.stderr:write(problem..'\n');local out=assert(io.open(output..'/failure.txt','w'));out:write(problem);out:close();return function()return 1 end end
