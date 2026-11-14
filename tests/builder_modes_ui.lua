local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Builder=require('app.builder');local json=require('lib.json')
local m,r,v,p,runner,Cursor,Region;local time,wake,frames=0,0,0;local mouse={x=1,y=1};local down=false;local held={}
local checks,shots,captures,created={},{},{},{};local buttons,inputs,choices={},{},{};local id
local function check(ok,s)assert(ok,s);checks[#checks+1]=s;print('BUILDER MODES PASS '..s)end
local function wait(s)wake=time+(s or .08);coroutine.yield()end
local function ready(fn,timeout,label)local untilTime=time+(timeout or 15);while not fn()do assert(time<untilTime,label);wait(.06)end end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy);r:mousemoved(x,y)end
local function press(clicks)clicks=clicks or 1;down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,clicks);if not r:inputBlocked()and S.IsVoidHovered()then local x,y=Layout.toLogical(mouse.x,mouse.y);r:mousepressed(x,y,1,clicks)end end
local function release()down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);local x,y=Layout.toLogical(mouse.x,mouse.y);r:mousereleased(x,y,1)end
local function click(box)assert(box,'Missing actual builder control');move(box.x+box.w/2,box.y+box.h/2);wait(.05);press();wait(.05);release();wait(.15)end
local function hit(kind,name)for _,h in ipairs(r.hits)do if h.kind==kind and h.card and h.card.name==name then return h end end end
local function custom(label)for _,h in ipairs(r.hits)do if h.tooltip==label or h.tooltip==label..' deck builder layout'or(label=='Next'and h.tooltip=='Next ›')then return h end end end
local function shot(name)shots[#shots+1]=name;wait(.14)end
local function mode(w,h,scale,desktop)
 m.settings.resolution=desktop and'Desktop'or(w..'x'..h);m.settings.windowMode=desktop and'Borderless'or'Windowed';m.settings.uiScale=scale;m.settings.vsync=false;p:apply(true);wait(.2)
end
local function query(value,target)
 target=target or value
 click(inputs.query);held.lctrl=true;S.OnKeyPressed('a','a',false);wait(.04);S.OnKeyReleased('a','a');held.lctrl=false;S.OnTextInput(value)
 ready(function()return m.search==value and not m.searchTimer and not m.searchBusy and hit('search',target)end,20,'Actual card query did not render '..target);wait(.08)
end
local function idle()return not m.mutationBusy and#(m.mutationQueue or{})==0 end
local function amount(name)for _,c in ipairs(m.editDeck.main)do if c.name==name then return c.count end end;return 0 end
local function drag(name)
 local card=assert(hit('search',name),'Missing actual search image');local L=Builder.layout(Layout.dimensions(),select(2,Layout.dimensions()),m.settings.builderLayout)
 move(card.x+card.w/2,card.y+card.h/2);wait(.08);press();wait(.08);check(r.drag and r.drag.kind=='search','Actual '..m.settings.builderLayout..' search press begins a drag')
 local x,y=L.list.x+L.list.w*.45,L.list.y+math.min(70,L.list.h-20)
 for i=1,4 do local sx,sy=card.x+card.w/2,card.y+card.h/2;move(sx+(x-sx)*i/4,sy+(y-sy)*i/4);wait(.04)end
 release();ready(idle,15,'Validated card drop did not settle');wait(.1)
 check(not m.inspectCard,'Actual search-to-list drag does not open an inspect modal')
end
local function geometry(label)
 local w,h=Layout.dimensions();local L=Builder.layout(w,h,m.settings.builderLayout)
 check(inputs.query and inputs.query.y+inputs.query.h<L.grid.y,'Search field remains above card images in '..label)
 check(buttons.Validate and buttons.Validate.x+buttons.Validate.w<=w and buttons.Validate.y+buttons.Validate.h<=h,'Validate control remains fully visible in '..label)
 local next=assert(custom('Next'));check(next.y+next.h<=h-8 and next.x+next.w<=w,'Actual paging footer stays inside '..label)
 check(L.list.y+L.list.h<=h-12,'Shared deck drop target remains within '..label)
 if m.settings.builderLayout=='Simplified'then check(buttons['More filters']and buttons['More filters'].x+buttons['More filters'].w<=w-10,'All inline color/more-filter controls fit '..label)end
end
local function save()
 click(buttons['Save *']or buttons.Save);ready(function()return not m.dirty and m:findDeck(id)end,20,'Actual deck save did not finish')
end
local function scenario()
 ready(function()return m.settingsLoaded and m.catalogHealth.ready and m.profileLoaded end,30,'Temporary API7 catalog did not initialize')
 m.settings.localArtworkOnly=true;m.settings.animations=false;m.settings.particles=false;m.settings.sfxEnabled=false
 local display=select(3,love.window.getPosition())or 1;for i=1,love.window.getDisplayCount()do local w,h=love.window.getDesktopDimensions(i);if w==2560 and h==1080 then display=i end end
 love.window.setMode(2560,1080,{fullscreen=true,fullscreentype='desktop',display=display,vsync=0});mode(2560,1080,1,true)
 m.format='Modern';m:newDeck();id=m.editDeck.id;m.editDeck.name='Builder UI acceptance '..os.time();wait(.15)
 click(custom('Simplified'));ready(function()return m.settings.builderLayout=='Simplified'end,5,'Actual Simplified switch did not apply');check(m.settings.builderLayout=='Simplified','Actual builder layout control switches to Simplified')
 query('Lightning Bolt');geometry('Simplified2560×1080');drag('Lightning Bolt');check(amount('Lightning Bolt')==1,'Actual validated Simplified drop adds exactly one Lightning Bolt')
 query('Basic Land — Plains','Plains');drag('Plains');check(amount('Plains')==1,'Actual validated Simplified drop adds exactly one Plains')
 ready(function()return hit('builder-card','Plains')and hit('builder-card','Lightning Bolt')end,10,'Simplified spell/land columns did not render')
 local land,spell=hit('builder-card','Plains'),hit('builder-card','Lightning Bolt');check(land.x>spell.x+spell.w+15,'Actual land cards have a separate column after mana-value spell columns')
 shot('simple-2560');click(buttons['More filters']);wait(.15);check(v.builderFiltersOpen and buttons['Close filters'],'Actual More filters opens the supported type/sort/set controls')
 local card=assert(hit('search','Plains'));move(card.x+card.w/2,card.y+card.h/2);wait(.06);press(2);wait(.05);release();wait(.15)
 check(amount('Plains')==1 and not r.drag and not m.inspectCard,'Outside-popup double-click cannot add or inspect an underlying search card');shot('simple-more-filters');click(buttons['Close filters']);check(not v.builderFiltersOpen,'Actual filter popup closes before card dragging')
 card=assert(hit('search','Plains'));move(card.x+card.w/2,card.y+card.h/2);wait(.05);press();wait(.06);check(r.drag,'A real card drag starts before the modal race fixture')
 v.builderFiltersOpen=true;wait(.1);local L=Builder.layout(Layout.dimensions(),select(2,Layout.dimensions()),'Simplified');move(L.list.x+100,L.list.y+65);wait(.08);release();wait(.12)
 check(amount('Plains')==1 and not r.drag,'A modal opening during an actual drag blocks release into the underlying deck');click(buttons['Close filters'])
 click(buttons.Preview);wait(.12);check(m.inspectCard,'Actual Preview opens card details')
 card=assert(hit('search','Plains'));move(card.x+card.w/2,card.y+card.h/2);wait(.05);press(2);wait(.05);release();wait(.1)
 check(amount('Plains')==1,'Card details block outside double-click additions');click(buttons['Close details'])
 save();local done,data=false;m:request('catalog','GET','/decks/'..id,nil,function(d)data=d;done=true end,true);ready(function()return done end,10,'Saved deck read did not finish');data=data.deck or data
 check(m.count(data,'main')==2 and data.main[1].count==1 and data.main[2].count==1,'Actual saved unfinished deck preserves both dragged quantities')
 local fresh=Model.new();ready(function()fresh:update(.05);return fresh.settingsLoaded end,20,'Fresh frontend settings did not load');check(fresh.settings.builderLayout=='Simplified','A fresh frontend instance restores the persisted Simplified layout');fresh.api:quit()
 mode(1120,720,.85);geometry('Simplified1120×720 at.85');shot('simple-1120-scaled')
 mode(1120,720,1.25);geometry('Simplified1120×720 requested1.25');check(Layout.scale<=1.25,'Smaller window records the actual clamped interface scale');shot('simple-1120-clamped')
 click(custom('Classic'));ready(function()return m.settings.builderLayout=='Classic'end,5,'Actual Classic switch did not apply');query('Lightning Bolt');geometry('Classic1120×720');shot('classic-1120');drag('Lightning Bolt');check(amount('Lightning Bolt')==2,'Classic layout still accepts a real card drop into its shared deck list')
 save();done=false;data=nil;m:request('catalog','GET','/decks/'..id,nil,function(d)data=d;done=true end,true);ready(function()return done end,10,'Saved Classic quantities did not reload');data=data.deck or data
 local boltCount=0;for _,entry in ipairs(data.main)do if entry.name=='Lightning Bolt'then boltCount=entry.count end end
 check(boltCount==2 and m.count(data,'main')==3 and data.draft==true,'Actual Classic save persists two Lightning Bolts and one Plains as an unfinished deck')
 mode(2560,1080,1.25,true);geometry('Classic2560×1080 at1.25');shot('classic-2560-scaled')
 check(m.editDeck.main[1]and amount('Lightning Bolt')==2 and amount('Plains')==1,'Switching layouts and display scale preserves every deck quantity')
 local f=assert(io.open('/tmp/love2gathering-builder-modes-ui-report.json','w'));f:write(json.encode({passed=true,checks=checks,captures=captures,physical={love.graphics.getDimensions()},logical={Layout.dimensions()},scope='Actual Model/API7 catalog validation/storage, frontend pointer dispatch and card-image drag; Classic/Simplified shared bounds and fresh-model persisted settings. No native game or engine legality claim.'}));f:close();print('BUILDER MODES COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.errorhandler(e)io.stderr:write('BUILDER MODES FAILED '..tostring(e)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(b)return b==1 and down end;love.keyboard.isDown=function(...)for i=1,select('#',...)do if held[select(i,...)]then return true end end;return false end
 m=Model.new();r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p
 local req=m.request;m.request=function(self,service,method,path,body,callback,quiet)return req(self,service,method,path,body,function(data,err,failed)
  if method=='POST'and path=='/decks'and data then local d=data.deck or data;local found=false;for _,value in ipairs(created)do if value==d.id then found=true end end;if not found then created[#created+1]=d.id;local f=assert(io.open(os.getenv('LOVE2GATHERING_BUILDER_TEST_IDS'),'w'));f:write(json.encode(created));f:close()end end
  if callback then callback(data,err,failed)end
 end,quiet)end
 local function box()local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();return{x=x+dx,y=y+dy,w=w,h=h}end
 for _,name in ipairs({'Button','Input','TextSelectable'})do local original=S[name];S[name]=function(label,options)local result=original(label,options);(name=='Input'and inputs or name=='TextSelectable'and choices or buttons)[label]=box();return result end end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 time=time+dt;frames=frames+1;assert(time<100,'Builder modes acceptance timed out');m:update(dt);p:update();S.Update(dt);r:update(dt)
 if time>=wake and coroutine.status(runner)~='dead'then local ok,e=coroutine.resume(runner);assert(ok,e)end
 buttons={};inputs={};choices={};v:build();r.uiHovered=not S.IsVoidHovered()
end
function love.draw()
 p:beginFrame();r:draw();p:endScene();S.Draw();love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();love.graphics.pop();p:endFrame()
 if#shots>0 then local name=table.remove(shots,1);local path='/tmp/love2gathering-builder-'..name..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local f=assert(io.open(path,'wb'));f:write(data:encode('png'):getString());f:close()end)end
end
function love.quit()m.game=nil;m.uiLayoutTimer=nil;m.api:quit();p:quit();S.OnQuit()end
