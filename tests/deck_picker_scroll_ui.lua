-- Actual Slab scrolling/raster work; local metadata fixtures, no service writes.
local json=require('lib.json');local requests={};local pending={};local time=0
package.preload['app.api']=function()return{escape=function(s)return tostring(s)end,new=function()return{request=function(_,service,method,path,body,cb)
 requests[#requests+1]={service=service,method=method,path=path};pending[#pending+1]={path=path,cb=cb,at=time+.04}
 end,quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Region=require('lib.Slab.Internal.UI.Region');local Window=require('lib.Slab.Internal.UI.Window');local Assets=require('app.assets')
local m,r,v,prefs,runner;local mouse={x=1,y=1};local down=false;local buttons,inputs={},{};local clock=0;local wake=0;local completedBuilds,wakeBuild=0,0;local checks={};local samples={};local frameArt,rasterCount=0,0;local visible,hidden=0,0;local grid,barBox;local barAlpha=0;local output=assert(os.getenv('LOVE2GATHERING_DECK_SCROLL_OUTPUT'))
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('DECK SCROLL PASS '..label);io.stdout:flush()end
-- Slab claims wheel input in one build and applies it in the following build.
-- A slow frame can satisfy a clock-only wait before that second build runs,
-- because this coroutine resumes before v:build(). Always let both complete.
local function wait(dt)wake=clock+(dt or .08);wakeBuild=completedBuilds+2;coroutine.yield()end
local function move(x,y)local dx,dy=x*Layout.scale-mouse.x,y*Layout.scale-mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,dx,dy)end
local function click(box)assert(box,'Missing control');move(box.x+box.w/2,box.y+box.h/2);wait(.04);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.04);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.12)end
-- Match the list child, not its similarly named choose-deck-tiles window.
-- Instance enumeration order is unspecified; the outer window stays at zero.
local function isDeckList(id)return id:find('%.deck%-tiles$')~=nil end
local function scrollY()for _,id in ipairs(Region.GetInstanceIds())do if isDeckList(id)then local _,y=Region.Transform(id,0,0);return-y end end;return 0 end
local function shot(name)love.graphics.captureScreenshot(function(data)local f=assert(io.open(output..'/'..name..'.png','wb'));f:write(data:encode('png'):getString());f:close()end);wait(.1)end
local function scenario()
 wait(.2)
 for _,scale in ipairs({1,1.25})do
  m.settings.uiScale=scale;prefs:apply(true);wait(.15);click(buttons.yourDeck)
  check(v.deckSelection and grid,'Visible player deck opens the actual lobby selection popup at scale '..scale)
  check(visible>0 and hidden>20 and frameArt<20,'Only viewport-adjacent tiles request artwork/raster images')
  local start=scrollY();move(grid.x+grid.w/2,grid.y+grid.h/2);for _=1,30 do wait(.04);if isDeckList(Region.GetHotInstanceId())then break end end;check(isDeckList(Region.GetHotInstanceId()),'Wheel targets the hovered deck list');S.OnWheelMoved(0,-1)
  -- Reproduce the slow rendering frame that previously made this assertion
  -- intermittently run before Slab consumed the first wheel event.
  if scale==1 then love.timer.sleep(.2)end
  wait(.15);local delta=scrollY()-start
  check(delta>=99 and delta<=101,'A wheel notch moves100 logical content pixels at scale '..scale..' delta '..delta)
  samples[#samples+1]={scale=scale,wheelPixels=delta,visible=visible,hidden=hidden,artLookups=frameArt}
  local before=rasterCount;wait(.35);check(rasterCount==before,'A settled popup builds no new UI raster images while idle')
  move(2,2);wait(1.2);check(barAlpha==1,'The vertical scrollbar remains fully visible after mouseleave and idle')
  shot('scroll-idle-scale'..scale)
  local beforeDrag=scrollY();assert(barBox,'Missing visible thumb');local sx=barBox.x+barBox.w/2;move(sx,barBox.y+barBox.h/2);wait(.06)
  down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.06);move(sx,grid.y+grid.h-25);wait(.08);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.15)
  check(scrollY()>beforeDrag+100,'Dragging the persistent scrollbar rapidly reaches lower decks')
  local beforeWheel=scrollY();move(2,2);wait(.05);S.OnWheelMoved(0,-2);wait(.1);check(scrollY()==beforeWheel,'A forced-visible scrollbar does not consume wheels outside its list')
  local choice
  for i=1,64 do local name=string.format('Scroll deck%02d',i);local box=buttons[name];if box and not box.invisible and box.y>=grid.y and box.y+box.h<=grid.y+grid.h then choice={name=name,box=box};break end end
  assert(choice,'No fully visible deck after scrolling');shot('before-selection');click(choice.box)
  check(not v.deckSelection and m:findDeck(m.playerDeckId).name==choice.name,'A scrolled visible tile still selects the exact intended deck')
  click(buttons.yourDeck);check(scrollY()==0,'A reopened deck chooser starts at the first group')
  click(inputs['deck-tile-search']);S.OnTextInput('no-matching-deck-zz');wait(.2)
  check(visible==0 and barBox and barBox.h<=grid.h and barAlpha==1,'An empty result keeps its scrollbar inside the list bounds')
  click(buttons['Close deck selection']);check(not v.deckSelection,'Close still releases the actual picker after scrolling and filtering')
 end
 for _,call in ipairs(requests)do assert(call.method=='GET','Unexpected persistence/native action')end
 local f=assert(io.open(output..'/report.json','w'));f:write(json.encode({checks=checks,samples=samples,requests=requests,slowFrameSeconds=.2,scope='Actual LÖVE/Slab with controlled deck metadata, one genuine local JPEG and a deliberate slow wheel frame. No native match, SQL writes or image acquisition.'}));f:close();love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function()return down end
 m=Model.new();m.loaded=true;m.settingsLoaded=true;m.profileLoaded=true;m.uiLayout={};m.page='lobby';m.format='Commander';m.catalogHealth={ready=true};m.settings.windowMode='Windowed';m.settings.resolution='1440x900';m.settings.uiScale=1;m.settings.vsync=false;m.settings.skybox='Off';m.settings.musicEnabled=false;m.settings.sfxEnabled=false
 m.decks={};for i=1,64 do m.decks[i]={id='scroll-'..i,name=string.format('Scroll deck%02d',i),format='Commander',origin='user',main={{name='Forest'..i,count=99}},commander={},sideboard={},colorIdentity={'G'}}end
 m.playerDeckId=m.decks[1].id;m.botDeckId=m.decks[2].id;m.botDeckIds={m.decks[2].id,m.decks[3].id,m.decks[4].id};m.startersLoaded=true;m.starterDecks={}
 local art=love.graphics.newImage('land.jpg');m.getArt=function()frameArt=frameArt+1;return art end
 r=Renderer.new(m);v=View.new(S,m,r);prefs=Preferences.new(m,S,r);v.preferences=prefs;prefs:apply(true);prefs.appliedLoaded=true
 local raster=Assets.rasterize;Assets.rasterize=function(...)rasterCount=rasterCount+1;return raster(...)end
 local Cursor=require('lib.Slab.Internal.Core.Cursor');local scopes={};local push,pop=S.PushID,S.PopID;S.PushID=function(id)scopes[#scopes+1]=id;return push(id)end;S.PopID=function()scopes[#scopes]=nil;return pop()end
 local button=S.Button;S.Button=function(id,options)local result=button(id,options);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);buttons[id]={x=x,y=y,w=w,h=h,invisible=options.Invisible};if scopes[#scopes]and scopes[#scopes]:match('^tile%-')then if options.Invisible then hidden=hidden+1 else visible=visible+1 end end;return result end
 local input=S.Input;S.Input=function(id,options)local result=input(id,options);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);inputs[id]={x=x,y=y,w=w,h=h};return result end
 local list=S.BeginListBox;S.BeginListBox=function(id,options)if id=='deck-tiles'then local x,y=S.GetCursorPos({Absolute=true});x,y=Window.TransformPoint(x,y);grid={x=x,y=y,w=options.W,h=options.H}end;return list(id,options)end
 local Draw=require('lib.Slab.Internal.Core.DrawCommands');local rectangle=Draw.Rectangle;Draw.Rectangle=function(mode,x,y,w,h,color,...)
  if grid and mode=='fill'and math.abs(x-(grid.x+grid.w-13))<1 and w==10 and h>=10 and color and color[4]==1 then barAlpha=1;barBox={x=x,y=y,w=w,h=h}end
  return rectangle(mode,x,y,w,h,color,...)
 end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;time=clock;assert(clock<45,'Scroll fixture timed out')
 for i=#pending,1,-1 do if pending[i].at<=time then local call=table.remove(pending,i);call.cb({decks={},total=0},nil,200)end end
 m:updateCollection(dt);S.Update(dt);if clock>=wake and completedBuilds>=wakeBuild and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 buttons={};inputs={};visible,hidden,frameArt=0,0,0;barAlpha=0;v:build();completedBuilds=completedBuilds+1
end
function love.draw()love.graphics.clear(.02,.03,.05);S.Draw()end
function love.quit()prefs:quit();S.OnQuit()end
function love.errorhandler(message)local problem=debug.traceback(tostring(message),2);print(problem);local f=assert(io.open(output..'/failure.txt','w'));f:write(problem);f:close();return function()return 1 end end
