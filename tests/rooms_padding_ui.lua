-- Synthetic room/seat projections with actual Slab layout, pixels and clicks.
function love.errorhandler(message)
 io.stderr:write('ROOM PADDING FAILED '..tostring(message)..'\n'..debug.traceback()..'\n')
 return function()return 1 end
end
package.preload['app.api']=function()return{escape=function(s)return s end,new=function()return{catalogPort=17490,request=function()end,update=function()end,quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Region=require('lib.Slab.Internal.UI.Region');local json=require('lib.json')
local m,r,v,prefs,runner,Cursor;local checks,shots={},{};local fields,boxes,buttons={}, {},{};local frames=0
local mouse={x=1,y=1};local down=false
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('ROOM PADDING PASS '..label)end
local function wait(n)for _=1,n or 4 do coroutine.yield()end end
local function bounds()local x,y,w,h=Cursor.GetItemBounds();local dx,dy=Region.Transform(nil,0,0);return{x=x+dx,y=y+dy,w=w,h=h}end
local function click(box)
 assert(box);local ox,oy=mouse.x,mouse.y;mouse.x=(box.x+box.w/2)*Layout.scale;mouse.y=(box.y+box.h/2)*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy);wait(3)
 down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(3);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(4)
end
local function shot(name)
 love.graphics.captureScreenshot(function(data)
  local path='/tmp/love2gathering-rooms-padding-'..name..'.png';local f=assert(io.open(path,'wb'));f:write(data:encode('png'):getString());f:close();shots[#shots+1]=path
 end);wait(4)
end
local function connected()
 m.roomParticipantId='fixture-host';m.roomDeckId='fixture-deck'
 m.room={name='Friends table',hostId='fixture-host',phase='lobby',canStart=true,inviteCode='L2G1-FIXTURE-INVALID-NOT-A-CREDENTIAL',config={kind='constructed',format='Commander',maxPlayers=4,commanderDamage=false},members={{id='fixture-host',name='Aleksa',connected=true,ready=false},{id='fixture-bot',name='XMage Bot 1',bot=true,ready=true}}}
end
local function mode(w,h,scale)
 m.settings.resolution=w..'x'..h;m.settings.windowMode='Windowed';m.settings.uiScale=scale;m.settings.vsync=false;m.settings.showCardArt=false;m.settings.sfxEnabled=false
 prefs:apply(true);m.page='rooms';wait(7)
end
local function scenario()
 mode(1440,900,1)
 local field,box=fields['room-name'],boxes['room-create-fields']
 check(field.x>=box.x+12 and field.y>=box.y+6,'Create fields have real horizontal and vertical inset from their nested panel')
 check(fields['room-name'].x+fields['room-name'].w<box.x+box.w-12,'Text input leaves space for the nested panel border and scroll rail')
 local toggle=buttons['Commander damage (21)'];check(toggle~=nil,'Commander house-rule checkbox is present in room setup')
 click(toggle);check(m.roomSetup.commanderDamage==false,'Actual room checkbox input changes the option sent by hosting')
 shot('create-1440')
 connected();wait(7)
 local pane=boxes['room-your-seat'];local deck=buttons['room-deck']
 check(deck and deck.x>=pane.x+12,'The selected-deck tile has an inset inside the seat panel')
 local close=buttons['Close room'];check(close and close.y+close.h<select(2,Layout.dimensions())-12,'Host actions remain above the bottom window edge')
 check(buttons['Copy code'].h>=34 and fields['invite-code'].h>=34,'Invitation code and copy action have matching readable heights')
 shot('connected-1440')
 mode(1440,900,1.25);shot('connected-scaled')
 check(Layout.scale==1.25,'The room rendering check uses actual UI scale 1.25')
 mode(1120,720,1.25);wait(5)
 close=buttons['Close room'];check(close.y+close.h<select(2,Layout.dimensions())-12,'Close room stays reachable in the compact clamped window')
 check(fields['invite-code'].x+fields['invite-code'].w<buttons['Copy code'].x,'Invitation input and action never overlap')
 shot('connected-1120')
 local report={passed=true,scope='Synthetic rooms; actual LÖVE/Slab layout, checkbox input and inspected screenshots at 1440/1120 and UI scales 1/1.25. No network/native game or live invitation used.',checks=checks,screenshots=shots}
 local f=assert(io.open('/tmp/love2gathering-rooms-padding-report.json','w'));f:write(json.encode(report));f:close();love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor')
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down end
 m=Model.new();m.page='rooms';m.catalogHealth={ready=false};m.roomCapabilities={game={formats={{id='Commander',minPlayers=2,maxPlayers=6}},minPlayers=2,maxPlayers=6},draft={}}
 m.decks={{id='fixture-deck',name='Ayara practice',format='Commander',main={},commander={},sideboard={}}}
 r=Renderer.new(m);v=View.new(S,m,r);prefs=Preferences.new(m,S,r);v.preferences=prefs
 local begin=S.BeginListBox;S.BeginListBox=function(id,options)
  local x,y=S.GetCursorPos({Absolute=true});local dx,dy=Region.Transform(nil,0,0);boxes[id]={x=x+dx,y=y+dy,w=options.W,h=options.H};return begin(id,options)
 end
 local input=S.Input;S.Input=function(id,options)local result=input(id,options);fields[id]=bounds();return result end
 local button=S.Button;S.Button=function(id,options)local result=button(id,options);buttons[id]=bounds();return result end
 local checkbox=S.CheckBox;S.CheckBox=function(value,label,options)local result=checkbox(value,label,options);buttons[label]=bounds();return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 frames=frames+1;assert(frames<900,'Room padding acceptance timeout')
 if coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);if not ok then error(err)end end
 prefs:update();S.Update(dt);r:update(dt);fields,boxes,buttons={},{},{};v:build()
end
function love.draw()prefs:beginFrame();r:draw();prefs:endScene();S.Draw();prefs:endFrame()end
