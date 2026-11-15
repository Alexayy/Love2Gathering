local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Builder=require('app.builder');local Nav=require('app.navigation');local json=require('lib.json')
local m,r,v,p,Cursor,Region,runner;local time,wake=0,0;local mouse={x=2,y=2};local down={};local controls,buttons,windows={},{},{};local checks,captures,shots={},{},{};local phase='build';local previewAfterSlab=false
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('NAVIGATION PASS '..label)end
local function wait(delay)wake=time+(delay or .09);coroutine.yield()end
local function move(x,y)local a,b=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-a,mouse.y-b);r:mousemoved(x,y)end
local function press(button)button=button or 1;down[button]=true;S.OnMousePressed(mouse.x,mouse.y,button,false,1);if not r:inputBlocked()and S.IsVoidHovered()then r:mousepressed(mouse.x/Layout.scale,mouse.y/Layout.scale,button,1)end end
local function release(button)button=button or 1;down[button]=false;S.OnMouseReleased(mouse.x,mouse.y,button,false,1);r:mousereleased(mouse.x/Layout.scale,mouse.y/Layout.scale,button)end
local function click(box,button)assert(box,'Missing click target');move(box.x+box.w/2,box.y+box.h/2);wait();press(button);wait();release(button);wait(.18)end
local function hit(label)for _,b in ipairs(r.hits)do if b.tooltip==label then return b end end end
local function shot(name)shots[#shots+1]=name;wait(.15)end
local function bounds()local x,y,w,h=Cursor.GetItemBounds();local dx,dy=Region.Transform(nil,0,0);return{x=x+dx,y=y+dy,w=w,h=h}end
local function mode(w,h,scale)
 m.settings.windowMode='Windowed';m.settings.resolution=w..'x'..h;m.settings.uiScale=scale;p:apply(true);wait(.25)
end
local function navGeometry(label)
 local w=Layout.dimensions();local L=Nav.layout(w,m.page,m.game~=nil)
 check(L.brand.x+L.brand.w<L.pages[1].x,label..' brand does not overlap navigation')
 for _,b in ipairs(L.pages)do check(b.x>=0 and b.x+b.w<L.profile.x,label..' nav '..b.page..' fits before profile')end
 check(L.dynamic.w>=270 and L.dynamic.x+L.dynamic.w<L.profile.x,label..' dynamic actions have their own navbar region')
 check(L.settings.x+L.settings.w<=w-16 and L.profile.x+L.profile.w<L.settings.x,label..' profile and Settings remain separate')
 check(hit('Settings')and hit('Settings').y==16,label..' Settings cog uses the existing navbar height')
end
local function fixture()
 local forest={name='Forest',type_line='Basic Land — Forest',mana_cost='',cmc=0,color_identity={'G'},oracle_text='{T}: Add {G}.'}
 local bolt={name='Lightning Bolt',type_line='Instant',mana_cost='{R}',cmc=1,color_identity={'R'},oracle_text='Lightning Bolt deals 3 damage to any target.'}
 local bear={name='Grizzly Bears',type_line='Creature — Bear',mana_cost='{1}{G}',cmc=2,color_identity={'G'},oracle_text='',power='2',toughness='2'}
 local data={Forest=forest,['Lightning Bolt']=bolt,['Grizzly Bears']=bear}
 m.cards={forest,bolt,bear};m.total=3;m.offset=0;m.editDeck={id='navigation-fixture',name='Navigation test deck',format='Modern',main={{name='Forest',count=12},{name='Lightning Bolt',count=4},{name='Grizzly Bears',count=4}},commander={},sideboard={}};m.selectedSection='main'
 m.cardData=function(_,card)return data[card.name]or card end;m.getArt=function()return nil end
 m.setSearchLimit=function(self,n)self.searchLimit=n end;m.searchCards=function()end;m.searchChanged=function()end
 m.showCardPrintings=function(self,card,zone)self.printingTest={name=card.name,zone=zone}end
 m.catalogHealth={ready=true};m.engineHealth={ready=true};m.sets={};m.profile={name='UI test'};m.profileLoaded=true
end
local function scenario()
 for _,size in ipairs({{1120,720,1},{2560,1080,1.25}})do
  mode(size[1],size[2],size[3]);m.page='decks';wait(.2);navGeometry('Decks '..size[1]);local w,h=Layout.dimensions()
  for _,name in ipairs({'Import','History','New deck'})do local b=assert(hit(name));check(b.y==16 and b.y+b.h<=82,'Deck action '..name..' lives inside the navbar')end
  check(windows['collection-search'].y<160 and require('app.collection_ui').layout(w,h).y<220,'Collection headers/search reclaim the removed hero area')
  shot('decks-'..size[1])
  m.page='builder';m.settings.builderLayout='Simplified';wait(.2);navGeometry('Builder '..size[1])
  check(controls['deck-name']and controls['deck-name'].y+controls['deck-name'].h<=70,'Editable deck name is in the navbar at '..size[1])
  check(hit('Classic deck builder layout').y<82 and hit('Simplified deck builder layout').y<82,'Layout toggles are in the navbar at '..size[1])
  local L=Builder.layout(w,h,'Simplified',m.simpleBuilderSplitRatio)
  check(L.list.h>=180 and L.controls.y==100,'Simplified deck stays visible below compact controls at '..size[1])
  local divider;for _,b in ipairs(r.hits)do if b.kind=='builder-divider'then divider=b end end
  check(divider and not r:inputBlocked(),'A real divider exposes a draggable hit target')
  local before=L.list.h;move(divider.x+divider.w/2,divider.y+divider.h/2);wait();press();wait();move(divider.x+divider.w/2,divider.y-80);wait(.15);release();wait(.15)
  local resized=Builder.layout(w,h,'Simplified',m.simpleBuilderSplitRatio)
  check(resized.list.h>before+10 and math.abs(r.builderDrop.y-resized.list.y)<.01,'Dragging the divider expands the shared deck drawing/drop area')
  check(resized.grid.y+resized.cardH+24<resized.pagerY and resized.list.y+resized.list.h<=h-12,'Resized cards, pager and deck remain separated')
  shot('builder-resized-'..size[1]);m.simpleBuilderSplitRatio=nil;wait(.12)
  local card;for _,b in ipairs(r.hits)do if b.kind=='builder-card'then card=b;break end end
  check(card,'Deck contains real drawing/hit card geometry')
  local artHit;for _,b in ipairs(r.hits)do if b.kind=='printing-art'then artHit=b;break end end
  click(artHit);check(m.printingTest and m.printingTest.zone=='main','Simplified art icon dispatches the exact deck zone')
  local search;for _,b in ipairs(r.hits)do if b.kind=='search'then search=b;break end end
  move(search.x+search.w/2,search.y+search.h/2);wait(.15);check(previewAfterSlab,'Card hover preview is drawn in the foreground after Slab panels')
  shot('builder-preview-'..size[1]);move(2,2);wait(.12)
  click(hit('Classic deck builder layout'));check(m.settings.builderLayout=='Classic','Navbar Classic toggle retains its actual action')
  check(windows['builder-search'].y==100 and controls['deck-name'].y<70,'Classic builder also uses the reclaimed content origin')
  m.page='lobby';wait(.2);check(windows['lobby-setup'].y==100,'Lobby has no redundant page hero');shot('lobby-'..size[1])
  m.page='replays';wait(.2);check(windows['replay-library'].y==100,'Replay browser has no redundant page hero');shot('replays-'..size[1])
 end
 m.page='decks';wait(.15);local L=Nav.layout(Layout.dimensions(),m.page,false)
 click(L.brand,2);check(v.brandMenu and buttons['Border Toggle']and buttons.Minimize and buttons.Exit,'Brand right-click opens all three icon window actions')
 check(r:inputBlocked(),'Brand menu locks underlying renderer actions');shot('brand-menu')
 click({x=Layout.dimensions()-8,y=85,w=2,h=2});check(not v.brandMenu,'Outside press dismisses the brand menu without activating a background action')
 click(Nav.layout(Layout.dimensions(),m.page,false).brand,2);wait(.12)
 local oldMinimize=love.window.minimize;local minimized=0;love.window.minimize=function()minimized=minimized+1 end
 click(buttons.Minimize);love.window.minimize=oldMinimize;check(minimized==1 and not v.brandMenu,'Minimize menu action dispatches exactly once')
 click(Nav.layout(Layout.dimensions(),m.page,false).brand,2)
 local oldQuit=love.event.quit;local requested=0;love.event.quit=function()requested=requested+1 end
 click(buttons.Exit);love.event.quit=oldQuit;check(requested==1,'Exit requests normal LÖVE quit rather than terminating the process')
 m.settings.windowMode='Borderless';m.settings.resolution='Desktop';p:apply(true);wait(.25)
 Nav.toggleBorder(v);wait(.3);local _,_,flags=love.window.getMode();check(not flags.fullscreen and m.settings.windowMode=='Windowed','Border Toggle applies decorated maximized mode')
 Nav.toggleBorder(v);wait(.3);_,_,flags=love.window.getMode();check(flags.fullscreen and flags.fullscreentype=='desktop','Border Toggle restores borderless desktop fullscreen')
 local file=assert(io.open('/tmp/love2gathering-navigation-builder-report.json','w'));file:write(json.encode({passed=true,checks=checks,captures=captures,scope='Actual isolated LÖVE/Slab/Renderer/View input and native display modes, synthetic deck/card data. Minimize/Exit dispatch intercepted; no user saves, catalog calls or native matches.',physical={love.graphics.getDimensions()},logical={Layout.dimensions()}}));file:close();print('NAVIGATION COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.errorhandler(message)io.stderr:write('NAVIGATION FAILED '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(b)return down[b]or false end
 m=Model.new();m.page='decks';m.loaded=true;m.settingsLoaded=true;m.settings.sfxEnabled=false;m.settings.animations=false;m.settings.particles=false;m.saveSettings=function()end
 m.decks={};m.starterDecks={};m.precons={};m.preconsTotal=0;m.preconStats={formats={}};m.replays={};m.replaysTotal=0;m.uiLayout={}
 fixture();r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p
 local window=v.window;v.window=function(self,id,x,y,w,h,...)windows[id]={x=x,y=y,w=w,h=h};return window(self,id,x,y,w,h,...)end
 for _,name in ipairs({'Input','Button','BeginComboBox'})do local original=S[name];S[name]=function(id,options)local result=original(id,options);(name=='Button'and buttons or controls)[id]=bounds();return result end end
 local card=r.drawCard;r.drawCard=function(self,value,x,y,w,h,options)if options and options.noHit and w==244 and phase=='foreground'then previewAfterSlab=true end;return card(self,value,x,y,w,h,options)end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 time=time+dt;assert(time<80,'Navigation test timed out');p:update();S.Update(dt);r:update(dt)
 if time>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 controls={};buttons={};windows={};v:build();r.uiHovered=not S.IsVoidHovered()
end
function love.draw()
 phase='scene';p:beginFrame();r:draw();p:endScene();S.Draw();phase='foreground';r:drawForeground();if S.DrawTooltips then S.DrawTooltips()end;p:endFrame();phase='done'
 if#shots>0 then local name=table.remove(shots,1);local path='/tmp/love2gathering-navigation-'..name..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local f=assert(io.open(path,'wb'));f:write(data:encode('png'):getString());f:close()end)end
 love.timer.sleep(.025)
end
function love.quit()m.api:quit();p:quit();S.OnQuit()end
