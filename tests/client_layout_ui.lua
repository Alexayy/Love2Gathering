-- Real LÖVE/Slab rendering and read-only catalog calls. No native matches or
-- persisted user settings are changed by this layout acceptance.
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local json=require('lib.json')
local m,r,v,p,runner,Cursor,Region,DC;local clock,wake=0,0;local controls,buttons,labels,windows={},{},{},{}
local mouse={x=2,y=2};local down=false;local checks,captures,shots,geometry={},{},{},{}
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('CLIENT LAYOUT PASS '..label)end
local function wait(t)wake=clock+(t or .1);coroutine.yield()end
local function untilReady(fn,label)for _=1,150 do if fn()then return end;wait(.1)end;error('Timed out: '..label)end
local function shot(name)shots[#shots+1]=name;wait(.2)end
local function mode(w,h,scale)
 m.settings.resolution=w..'x'..h;m.settings.windowMode='Windowed';m.settings.uiScale=scale or 1;m.settings.vsync=false;p:apply(true);wait(.2)
end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy);r:mousemoved(x,y)end
local function click(box)
 assert(box,'Missing actual client control');move(box.x+box.w/2,box.y+box.h/2);wait(.06);down=true
 S.OnMousePressed(mouse.x,mouse.y,1,false,1);if S.IsVoidHovered()then r:mousepressed(mouse.x/Layout.scale,mouse.y/Layout.scale,1,1)end
 wait(.06);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);r:mousereleased(mouse.x/Layout.scale,mouse.y/Layout.scale,1);wait(.2)
end
local function nav(label)for _,hit in ipairs(r.hits)do if hit.tooltip==label and hit.y==16 then return hit end end end
local function scenario()
 untilReady(function()return m.catalogHealth.ready and#m.decks>=20 end,'real catalog and bundled decks')
 check(m.catalogHealth.apiVersion>=7,'Read-only test uses the actual API7 catalog')
 for _,size in ipairs({{2560,1080,1},{1120,720,1},{2560,1080,1.25}})do
  mode(size[1],size[2],size[3]);local w,h=Layout.dimensions();m.page='decks';wait(.4)
  geometry[#geometry+1]={requested={size[1],size[2]},physical={love.graphics.getDimensions()},logical={w,h},uiScale=Layout.scale}
  local previous=0
  for _,name in ipairs({'Decks','Builder','Lobby','Rooms','Replays','Gallery'})do
   local item=assert(nav(name),name);check(item.x>=previous and item.y+item.h<=82 and item.h==50,'Navigation '..name..' fits the original header at '..size[1]..'/'..Layout.scale);previous=item.x+item.w
  end
  check(previous<=w-364,'Navigation leaves separate profile and settings controls')
  local header;for _,item in ipairs(r.hits)do if item.kind=='collection-section'and item.section=='user'then header=item end end
  check(header and header.h==44,'My Decks uses the larger collapsible header')
  m:setCollectionFormat('Commander');m.uiLayout={collection={collapsed={starter=false,preconstructed=true}}};wait(.5);shot('decks-'..size[1]..'-'..size[3])
  m.page='lobby';m:setLobbyFormat('Commander');m:setLobbyPlayers(6);m.engineHealth={ready=true};wait(.3)
  check(buttons['2']and buttons['4']and buttons['5']and buttons['6']and math.abs(buttons['2'].y-buttons['6'].y)<1,'All player-count buttons share one horizontal row')
  check(buttons.yourDeck and buttons.botDeck5,'Six-seat lobby constructs all independent deck selectors')
  check(buttons['Start match']and buttons['Start match'].y+buttons['Start match'].h<=h,'Start match remains visible above the bottom edge')
  check(windows['lobby-decks'].y>windows['lobby-setup'].y+windows['lobby-setup'].h,'Lobby settings and seat panels have real separation')
  shot('lobby-'..size[1]..'-'..size[3])
  m.page='rooms';m:showRooms();wait(.3)
  local invite=assert(windows['room-invite']);check(invite.options.AutoSizeContent==false,'Room banner uses fixed content bounds without a phantom scrollbar')
  check(controls['room-title']and controls['room-title'].h>=30,'Room name retains padded input geometry');shot('rooms-'..size[1]..'-'..size[3])
  m:showReplays();untilReady(function()return not m.replaysBusy end,'isolated native recordings');wait(.3)
  local refresh=assert(buttons['Refresh recordings']);local count=assert(labels[tostring(m.replaysTotal or#(m.replays or{}))..' recordings'])
  check(refresh.w>=r.fonts[16]:getWidth('Refresh recordings')+60,'Refresh recordings has enough space for its full label and icon')
  check(math.abs(count.y-(refresh.y+(refresh.h-count.font:getHeight())/2+require('app.fonts').textOffset(count.font,tostring(m.replaysTotal)..' recordings')))<=1.1,'Recording count aligns optically with Refresh recordings')
  check(#(m.replays or{})>0,'Replay rows use real isolated native recordings')
  for _,row in ipairs(m.replays or{})do local date=row.createdAt or row.startedAt or'';if type(date)=='number'then date=os.date('%Y-%m-%d %H:%M',math.floor(date/1000))end;local text=labels[tostring(date)];if text then check(text.x>refresh.x+115,'Replay date stays in the information column beside Open')end end
  shot('replays-'..size[1]..'-'..size[3])
  click(assert(nav('Settings')));check(m.page=='settings'and not m.settingsOpen,'Navbar Settings opens its own page');wait(.2);shot('settings-'..size[1]..'-'..size[3]);m:closeSettings();check(m.page=='replays','Closing Settings returns to its originating page')
 end
 local f=assert(io.open('/tmp/love2gathering-client-layout-ui-report.json','w'));f:write(json.encode({passed=true,checks=checks,captures=captures,geometry=geometry,scope='Actual LÖVE/Slab at three physical/UI-scale combinations; read-only API7 deck and native-recording data from explicit isolated catalog, no native rules assertion'}));f:close();print('CLIENT LAYOUT COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.errorhandler(err)io.stderr:write('CLIENT LAYOUT FAILED '..tostring(err)..'\n'..debug.traceback()..'\n');return function()return 1 end end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region');DC=require('lib.Slab.Internal.Core.DrawCommands')
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(b)return b==1 and down end
 m=Model.new();m.loaded=true;m.settingsLoaded=true;m.uiLayout={};m.settings.animations=false;m.settings.particles=false;m.settings.sfxEnabled=false;m.settings.renderScale=1
 m:refreshDecks();m:loadProfile();m.catalogHealth={};m.healthTimer=0
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p.appliedLoaded=true
 local function box()local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();return{x=x+dx,y=y+dy,w=w,h=h}end
 for _,name in ipairs({'Button','Input','BeginComboBox'})do local original=S[name];S[name]=function(id,opts)local out=original(id,opts);(name=='Button'and buttons or controls)[id]=box();return out end end
 local window=v.window;function v:window(id,x,y,w,h,title,opts)window(self,id,x,y,w,h,title,opts);windows[id]={x=x,y=y,w=w,h=h,options=opts or{}}end
 local print=DC.Print;DC.Print=function(text,x,y,c,font,...)labels[tostring(text)]={x=x,y=y,font=font or S.GetStyle().Font};return print(text,x,y,c,font,...)end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<100,'Client layout acceptance timed out');S.OnMouseMoved(mouse.x,mouse.y,0,0);p:update();m:update(dt);S.Update(dt);r:update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 controls={};buttons={};labels={};windows={};v:build();r.uiHovered=not S.IsVoidHovered()
end
function love.draw()
 p:beginFrame();r:draw();p:endScene();S.Draw();p:endFrame()
 if#shots>0 then local name=table.remove(shots,1);local path='/tmp/love2gathering-client-'..name..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local f=assert(io.open(path,'wb'));f:write(data:encode('png'):getString());f:close()end)end
 love.timer.sleep(.034)
end
function love.quit()m.uiLayoutTimer=nil;m.game=nil;m.api:quit();p:quit();S.OnQuit()end
