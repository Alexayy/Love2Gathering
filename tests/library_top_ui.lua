-- Actual input/rendering of an exported native Courser scene. Transport is an
-- isolated action ledger; native play results are verified by the bridge test.
local json=require('lib.json');local actions={}
package.preload['app.api']=function()return{escape=function(v)return tostring(v)end,new=function()return{
 request=function(_,service,method,path,body,callback)
  if service=='engine'and path=='/session/action'then actions[#actions+1]=json.decode(json.encode(body));callback(nil,nil,200)
  elseif callback then callback(nil,nil,404)end
 end,update=function()end,quit=function()end,setNativeSession=function()end,escape=function(v)return tostring(v)end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout')
assert(love.filesystem.load('application-main.lua'))()
local native=json.decode(assert(love.filesystem.read('native-scene.json')))
local output=assert(os.getenv('L2G_LIBRARY_TOP_OUTPUT'));local m,r,v,p,runner
local elapsed,wake=0,0;local mouse={x=2,y=2};local buttons,rows,shots,checks,captures,geometry={},{},{},{},{},{};local down={};local dispatch={}
local function clone(value)return json.decode(json.encode(value))end
local function own(game)for _,player in ipairs(game.players)do if player.human then return player end end end
local original=assert(own(native));local top=assert(original.libraryTop);assert(top.id and native.gameId,'A genuine exported native top-card state is required')
local offered=false;for _,id in ipairs((native.prompt or{}).actionable or{})do if id==top.id then offered=true end end;assert(offered,'Exported native Courser top must actually be actionable')
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('LIBRARY TOP UI PASS '..label)end
local function wait(seconds)wake=elapsed+(seconds or .06);coroutine.yield()end
local function ready(predicate,message)for _=1,260 do if predicate()then return end;wait(.05)end;error(message)end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;dispatch.mousemoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy,false)end
local function press(box,button)assert(box,'Missing actual library control');move(box.x+box.w/2,box.y+box.h/2);wait(.04);down[button or 1]=true;dispatch.mousepressed(mouse.x,mouse.y,button or 1,false,1);wait(.04)end
local function release(button)down[button or 1]=nil;dispatch.mousereleased(mouse.x,mouse.y,button or 1,false,1);wait(.1)end
local function click(box,button)press(box,button);release(button)end
local function hit(kind,playerId)
 for index=#r.hits,1,-1 do local value=r.hits[index];if value.kind==kind and(not playerId or value.libraryPlayerId==playerId or value.playerId==playerId)then return value end end
end
local function shot(name)shots[#shots+1]=name;wait(.08)end
local revision=10000
local function adopt(game)
 revision=revision+1;game.revision=revision;m.actionBusy=false;m.answeredPrompt=nil
 m:setGame(game);return game
end
local function validateHits()
 for _,item in ipairs(r.hits)do
  if item.libraryPlayerId then
   if item.kind=='library-top'then local current=m:libraryTop(item.libraryPlayerId);if not(current and current.id==item.card.id)then return false end
   elseif item.kind~='library-zone'then return false end
  end
 end
 return true
end
local function multiplayer()
 local game=clone(native);game.gameId='UI-MULTIPLAYER-'..native.gameId;local human=own(game);local enemy
 for _,player in ipairs(game.players)do if not player.human then enemy=player;break end end
 local players={human}
 for index=2,4 do
  local player=clone(enemy);player.id='ui-seat-'..index;player.seat=index-1;player.name='Public fixture '..index;player.human=false;player.isLocal=false;player.isHuman=false;player.hand={};player.command={};player.battlefield={};player.graveyard={};player.exile={}
  if index~=3 then player.libraryTop=clone(top);player.libraryTop.id='ui-top-'..index;player.libraryTop.ownerId=player.id;player.libraryTopVisibility='public'else player.libraryTop=nil;player.libraryTopVisibility=nil end
  players[#players+1]=player
 end
 human.seat=0;game.players=players;game.activePlayerId=human.id;game.priorityPlayerId=human.id;return game
end
local function scenario()
 for _,mode in ipairs({{1120,720,1,1,false},{1440,900,1.25,.75,true}})do
  m.replay=nil;m.zoneView=nil;m.inspectCard=nil;m.libraryTopInspect=nil;m.settings.resolution=mode[1]..'x'..mode[2];m.settings.uiScale=mode[3];m.settings.renderScale=mode[4];p:apply(true)
  local game=mode[5]and multiplayer()or clone(native);local player=own(game);local source=clone(game)
  m.page='table';m.logOpen=false;m.stackOpen=false;r.cameraIdentity=nil;r.poses={};adopt(game);wait(.2)
  ready(function()return not require('app.dice').busy(r)end,'Native opening dice overlay did not finish')
  local name=mode[5]and'multiplayer-scaled'or'duel-native';geometry[#geometry+1]={mode=mode,physical={love.graphics.getDimensions()},logical={Layout.dimensions()}}
  local body=assert(hit('library-top',player.id));check(body.card.id==top.id and m:canSelect(body.card.id),'Projected Courser top is visible and actionable: '..name)
  check(validateHits(),'Offscreen library drawing leaves unrelated hit metadata intact: '..name)
  shot(name..'-playable-top');local before=#actions;click(body)
  check(#actions==before+1 and actions[#actions].type=='uuid'and actions[#actions].value==top.id and actions[#actions].expectedGameId==game.gameId,'Actual pile click sends the offered native top UUID: '..name)
  body=assert(hit('library-top',player.id));press(body);check(r.drag and r.drag.kind=='library-top','Actual top-card press begins a card drag: '..name)
  wait(.06);check(validateHits(),'A dragged top omitted from drawing cannot corrupt previous hits: '..name)
  local view=r.multiplayerView or r.tableLayout.viewport;move(view.x+view.w*.5,view.y+view.h*.55);wait(.04);release()
  check(#actions==before+2 and actions[#actions].value==top.id,'Actual drag also sends only the native top UUID: '..name)

  local noAction=clone(source);noAction.prompt.actionable={};adopt(noAction);wait(.1);before=#actions;click(assert(hit('library-top',player.id)))
  check(#actions==before and m.inspectCard and m.inspectCard.id==top.id,'Visible top with an empty native actionable list opens details without playing: '..name)
  click(buttons['Close details']);adopt(clone(source));wait(.1);local zoneActions=#actions;click(assert(hit('library-zone',player.id)))
  check(#actions==zoneActions,'Opening the library grid cannot select the image under its opening gesture: '..name)
  check(m.zoneView and#m.zoneView.cards==1 and m.zoneView.cards[1].id==top.id,'Library control opens a top-only live zone: '..name)
  shot(name..'-library-zone');click(assert(rows[top.id]));check(#actions==before+1 and not m.zoneView,'Actual entitled zone row sends the native action: '..name)

  click(assert(hit('library-zone',player.id)));local changed=clone(source);own(changed).libraryTop=clone(top);own(changed).libraryTop.id='ui-next-top';own(changed).libraryTop.name='Island';changed.prompt.actionable={}
  adopt(changed);wait(.1);check(#m.zoneView.cards==1 and m.zoneView.cards[1].id=='ui-next-top'and not rows[top.id],'An open zone replaces a changed top and drops its old row: '..name)
  own(changed).libraryTop=nil;own(changed).libraryTopVisibility=nil;adopt(clone(changed));wait(.1)
  check(#m.zoneView.cards==0 and not rows[top.id]and not hit('library-top',player.id),'Hidden top disappears from its live zone and table hit regions: '..name)
  click(buttons['Close zone']);adopt(clone(source));wait(.1)
  local pending=clone(source);pending.priority=pending.priority or{};pending.priority.pending=true;pending.priority.canEndTurn=false;pending.prompt.priority=true;adopt(pending);wait(.1);before=#actions;click(assert(hit('library-top',player.id)))
  check(#actions==before and m.inspectCard,'Pending priority acknowledgement never plays a stale highlighted top: '..name)
  local hidden=clone(source);own(hidden).libraryTop=nil;own(hidden).libraryTopVisibility=nil;adopt(hidden);wait(.1);check(not m.inspectCard,'Top-specific details close when native visibility disappears: '..name)

  m.replay={frames={{data=clone(source)},{data=clone(hidden)}},index=1,speed=1,playing=false};m:seekReplay(1);wait(.1);before=#actions;click(assert(hit('library-top',player.id)),2)
  check(#actions==before and m.inspectCard and m.inspectCard.id==top.id,'Actual replay right-click inspects without any live action: '..name)
  m:seekReplay(2);wait(.1);check(not m.inspectCard,'Replay frame changes also retire stale top-specific details: '..name)
  m.replay=nil;adopt(clone(source));wait(.1);press(assert(hit('library-top',player.id)));local staleCount=#actions;adopt(clone(hidden));release()
  check(#actions==staleCount and not r.drag,'A top changed during an actual drag cannot send an old UUID: '..name)
 end
 local file=assert(io.open(output..'/report.json','w'));file:write(json.encode({checks=checks,captures=captures,actions=actions,geometry=geometry,nativeGameId=native.gameId,nativeTopId=top.id,scope='Actual production callbacks, Slab zone rows and rendered native Courser duel scene; synthetic multiplayer expansion/visibility/priority/replay transitions are labeled presentation fixtures. A controlled action ledger records UUID submission; actual native land play is separately verified by the bridge fixture. No network, external images, user storage or running native game is used by this UI test.'}));file:close();love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return down[button]==true end
 m=Model.new();m.loaded=true;m.settingsLoaded=true;m.profileLoaded=true;m.settings.windowMode='Windowed';m.settings.skybox='Off';m.settings.showCardArt=false;m.settings.animations=false;m.settings.reducedMotion=true;m.settings.particles=false;m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.vsync=false;m.settings.autoFollowTurn=false;m.uiLayout={};m.catalogHealth={ready=false};m.profile={}
 for _,player in ipairs(native.players)do for _,zone in ipairs({'hand','battlefield','command','graveyard','exile'})do for _,card in ipairs(player[zone]or{})do m:rememberCard({id='catalog-'..card.id,printing_id='catalog-print-'..card.id,name=card.name,oracle_text=card.rules or'',type_line=card.type or'',image_uris={}})end end end
 m:rememberCard({id='catalog-top',printing_id='catalog-top',name=top.name,oracle_text=top.rules or'',type_line=top.type or'',image_uris={}})
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p.appliedLoaded=true
 for i=1,30 do local name=debug.getupvalue(love.keypressed,i);if not name then break end;if name=='model'then debug.setupvalue(love.keypressed,i,m)elseif name=='renderer'then debug.setupvalue(love.keypressed,i,r)elseif name=='view'then debug.setupvalue(love.keypressed,i,v)end end
 for _,name in ipairs({'mousemoved','mousepressed','mousereleased','wheelmoved','keypressed','keyreleased','textinput'})do dispatch[name]=love[name];love[name]=function()end end
 local Cursor=require('lib.Slab.Internal.Core.Cursor');local Window=require('lib.Slab.Internal.UI.Window');local scopes={};local push,pop=S.PushID,S.PopID
 S.PushID=function(id)scopes[#scopes+1]=id;return push(id)end;S.PopID=function()scopes[#scopes]=nil;return pop()end
 local function bounds()local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);return{x=x,y=y,w=w,h=h}end
 local button=S.Button;S.Button=function(label,opts)local result=button(label,opts);buttons[label]=bounds();local id=tostring(scopes[#scopes]or''):match('^zone%-card%-(.*)$');if id then rows[id]=bounds()end;return result end
 local selectable=S.TextSelectable;S.TextSelectable=function(label,opts)local result=selectable(label,opts);local id=tostring(scopes[#scopes]or''):match('^zone%-card%-(.*)$');if id then rows[id]=bounds()end;return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 elapsed=elapsed+dt;assert(elapsed<60,'Library top UI timed out');S.Update(dt);r:update(dt);r.uiHovered=not S.IsVoidHovered()
 if elapsed>=wake and coroutine.status(runner)~='dead'then local ok,problem=coroutine.resume(runner);assert(ok,problem)end
 buttons={};rows={};v:build()
end
function love.draw()
 p:beginFrame();r:draw();p:endScene();S.Draw({DeferOverlays=true});love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();love.graphics.pop();S.DrawOverlays();p:endFrame()
 if#shots>0 then local path=output..'/'..table.remove(shots,1)..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local file=assert(io.open(path,'wb'));file:write(data:encode('png'):getString());file:close()end)end
end
function love.quit()if p then p:quit()end;S.OnQuit()end
function love.errorhandler(message)local problem=debug.traceback(tostring(message),2);print(problem);local file=assert(io.open(output..'/failure.txt','w'));file:write(problem);file:close();return function()return 1 end end
