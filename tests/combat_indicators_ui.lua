-- Actual LÖVE/Slab callback and pixel checks; all game projections are synthetic.
function love.errorhandler(error)
 io.stderr:write('COMBAT INDICATORS UI FAILED '..tostring(error)..'\n'..debug.traceback()..'\n');io.stderr:flush()
 return function()return 1 end
end
package.preload['app.api']=function()return{new=function()return{request=function()end,update=function()end,quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Layout=require('app.layout');local Priority=require('app.priority');local json=require('lib.json')
local m,r,v,runner,clock,wake,checks,buttons,requests,mouse,down,shots,reports,pending
local Cursor=require('lib.Slab.Internal.Core.Cursor');local Region=require('lib.Slab.Internal.UI.Region')
local label='Stop after confirmed blockers, before combat damage · opponents’ turns'
local function check(ok,text)assert(ok,text);checks=checks+1;print('COMBAT INDICATORS UI PASS '..text)end
local function wait(t)wake=clock+(t or .08);coroutine.yield()end
local function copy(value)return json.decode(json.encode(value))end
local function fixture()
 local human={id='human',name='Synthetic human',human=true,life=40,hand={},handCount=0,libraryCount=90,battlefield={},graveyard={},exile={},command={},mana={}}
 local bot={id='bot',name='Synthetic bot',seat=1,life=40,hand={},handCount=0,libraryCount=90,battlefield={},graveyard={},exile={},command={},mana={}}
 local groups={}
 for i=1,3 do
  local card={id='attacker-'..i,name='Synthetic attacker '..i,type='Creature',power='3',toughness='3',controllerId='bot'}
  bot.battlefield[i]=card;groups[i]={attackerId=card.id,defenderId='human',attackingPlayerId='bot',blockerIds={},blocked=i==1,declarationConfirmed=true}
  human.battlefield[i]={id='defender-'..i,name='Synthetic defender '..i,type='Creature',power='2',toughness='2'}
 end
 return{gameId='SYNTHETIC-INDICATOR-FIXTURE',revision=1,running=true,turn=2,phase='Combat',step='DECLARE_BLOCKERS',activePlayerId='bot',
  players={human,bot},stack={},log={},combat={groups=groups},priority={pending=false,stops={own={},opponent={}},autoPass=true}}
end
local function move(x,y)
 local oldX,oldY=mouse.x,mouse.y;mouse.x=x*Layout.scale;mouse.y=y*Layout.scale
 S.OnMouseMoved(mouse.x,mouse.y,mouse.x-oldX,mouse.y-oldY)
end
local function click(button)
 move(button.x+button.w/2,button.y+button.h/2);wait(.03)
 down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.03)
 down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.08)
end
local function acknowledge()
 local command=assert(pending);pending=nil
 local frame=copy(m.game);frame.revision=frame.revision+1;frame.priority.stops=copy(command.body.stops);frame.priority.autoPass=command.body.autoPass;frame.priority.pending=false
 command.callback(frame)
end
local function imageInk(image)
 local data=image:newImageData();local colored=0
 for y=0,data:getHeight()-1 do for x=0,data:getWidth()-1 do local rr,gg,bb,aa=data:getPixel(x,y);if aa>.5 and gg>rr*1.4 then colored=colored+1 end end end
 return colored
end
local function scenario()
 for _,size in ipairs({{1120,720,1},{2560,1080,1},{2560,1080,1.25}})do
  love.window.setMode(size[1],size[2],{vsync=0,resizable=true});require('app.assets').invalidateRasterCaches();S.SetScale(Layout.setScale(size[3]))
  m.uiLayout={matchPrefs={priority={autoPass=true,stops={own=json.array(),opponent=json.array()}}}};m:setGame(fixture());move(0,0);wait(.15)
  local w,h=Layout.dimensions();local button=assert(buttons[label]);local name=size[1]..'-ui'..Layout.scale
  check(button.w==208 and button.h==32,'Quick stop is a readable 208×32 control '..name)
  local phaseBottom=0
  for _,hit in ipairs(r.hits)do if hit.kind=='phase-stop'then phaseBottom=math.max(phaseBottom,hit.y+hit.h)end end
  local terrainTop=r.tableLayout.viewport.y
  check(phaseBottom>0 and button.x>=w-250 and button.x+button.w<=w and button.y>=phaseBottom and button.y+button.h<=terrainTop,
      ('Quick stop at %.0f..%.0f clears phase stops (%.0f) and terrain (%.0f) in %s'):format(button.y,button.y+button.h,phaseBottom,terrainTop,name))
  check(button.tooltip:find('OFF · confirmed',1,true),'Disabled stop is explicitly confirmed OFF '..name)
  local offInk=imageInk(button.image);shots[#shots+1]={name=name..'-off',button=copy({x=button.x,y=button.y,w=button.w,h=button.h}),state='off'};wait(.08)
  local count=#requests;click(button)
  check(#requests==count+1 and pending and pending.body.command=='configure','Actual click submits the existing native configure command '..name)
  check(pending.body.stops.opponent[1]=='DECLARE_BLOCKERS'and #pending.body.stops.own==0,'Quick stop preserves native after-blocker/opponent semantics '..name)
  check(Priority.stopPresentation(m,Priority.beforeDamage,'opponent').status=='pending'and buttons[label].disabled,'Awaiting acknowledgement is visibly pending and disabled '..name)
  local pendingButton=buttons[label]
  shots[#shots+1]={name=name..'-pending',button={x=pendingButton.x,y=pendingButton.y,w=pendingButton.w,h=pendingButton.h},state='pending'};wait(.08)
  acknowledge();wait(.1);button=assert(buttons[label])
  check(button.tooltip:find('ON · confirmed',1,true)and not button.disabled,'Native acknowledgement changes the actual control to ON '..name)
  check(imageInk(button.image)>offInk+100,'ON uses a visibly stronger colored shield and label '..name)
  shots[#shots+1]={name=name..'-on',button={x=button.x,y=button.y,w=button.w,h=button.h},state='on'};wait(.08)
  click(button);check(Priority.stopPresentation(m,Priority.beforeDamage,'opponent').status=='pending','Disable also waits for acknowledgement '..name)
  acknowledge();wait(.08);check(Priority.stopPresentation(m,Priority.beforeDamage,'opponent').status=='off','Acknowledged disable returns OFF '..name)
  m.uiLayout.matchPrefs.priority.stops.opponent={'DECLARE_BLOCKERS'};wait(.08)
  check(buttons[label].tooltip:find('Not yet confirmed',1,true),'Unacknowledged saved preference never looks enabled '..name)
  m.uiLayout.matchPrefs.priority.stops.opponent={};m.game.priority.pending=true;wait(.08)
  check(buttons[label].disabled,'Pending native queue also disables the stop control '..name)
  m.game.priority.pending=false;wait(.08)
  reports[#reports+1]={name=name,physical={love.graphics.getDimensions()},logical={w,h},stop={x=button.x,y=button.y,w=button.w,h=button.h}}
 end
 local file=assert(io.open('/tmp/love2gathering-combat-indicators-ui.json','w'));file:write(json.encode({checks=checks,cases=reports,requests=#requests,scope='Synthetic native-shaped acknowledgement/combat states; actual Slab clicks/pixels. No native rules, service, network or user saves.'}));file:close()
 print('COMBAT INDICATORS UI COMPLETE '..checks..' checks');love.event.quit(0)
end
function love.load()
 clock,wake,checks=0,0,0;buttons={};requests={};mouse={x=0,y=0};down=false;shots={};reports={}
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function()return down end
 S.SetINIStatePath(nil);S.Initialize({'nocursor'},true)
 m=Model.new();m.settings.animations=false;m.settings.reducedMotion=true;m.settings.particles=false;m.settings.sfxEnabled=false;m.settings.showTooltips=false;m.settings.showCardArt=false;m.settings.skyboxBrightness=0;m.page='table';m.logOpen=false;m.stackOpen=false;m.settingsLoaded=true
 m.request=function(self,service,method,path,body,callback)
  requests[#requests+1]={service=service,method=method,path=path,body=copy(body)}
  if service=='engine'and path=='/session/priority'then pending={body=copy(body),callback=callback}end
 end
 r=Renderer.new(m);v=View.new(S,m,r)
 local original=S.Button;S.Button=function(text,options)
  local dx,dy=Region.Transform(nil,0,0);local result=original(text,options);local x,y,w,h=Cursor.GetItemBounds()
  buttons[text]={x=x+dx,y=y+dy,w=w,h=h,tooltip=options and options.Tooltip or'',disabled=options and options.Disabled or false,image=options and options.Image and options.Image.Image}
  return result
 end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<40,'Combat indicator fixture exceeded40seconds');S.Update(dt);r:update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,error=coroutine.resume(runner);assert(ok,error)end
 buttons={};v:build();r:mousemoved(Layout.mouse())
end
function love.draw()
 love.graphics.push();love.graphics.scale(Layout.scale);r:draw();love.graphics.pop();S.Draw()
 if #shots>0 then local job=table.remove(shots,1);love.graphics.captureScreenshot(function(data)
  local b=job.button;local rr,gg,bb=data:getPixel(math.floor((b.x+b.w-8)*Layout.scale),math.floor((b.y+b.h/2)*Layout.scale))
  if job.state=='on'then check(gg>rr*1.5,'Actual ON control pixels are strongly green')elseif job.state=='pending'then check(rr>gg and gg>bb,'Pending control pixels use a separate amber surface')end
  local file=assert(io.open('/tmp/love2gathering-combat-indicators-'..job.name..'.png','wb'));file:write(data:encode('png'):getString());file:close()
 end)end
end
function love.quit()S.OnQuit()end
