-- Actual main callbacks/API/Slab over a test-only HTTP facade. Initial zones
-- are deterministic fixtures; responses and resulting effects are native.
function love.errorhandler(message)io.stderr:write('DECK PICKER UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
local json=require('lib.json');local Layout=require('app.layout');local S=require('lib.Slab');local API=require('app.api');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences')
local m,r,v,p,Cursor,Window;local mouse={x=2,y=2};local pressed={};local clock,wake=0,0;local runner;local buttons,checks,shots={},{},{};local reports={};local strong={};local sceneBusy=false;local textLedger={};local inputs={};local keys={}
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('DECK PICKER UI PASS '..label);io.stdout:flush()end
local function wait(t)wake=clock+(t or .1);coroutine.yield()end
local function ready(fn,label,seconds)local deadline=clock+(seconds or 12);while not fn()do if clock>=deadline then io.stderr:write(json.encode({prompt=m and m.game and m.game.prompt,actionBusy=m and m.actionBusy,toasts=m and m.toasts})..'\n');error(label)end;wait(.06)end end
local function request(method,path,body)
    local done,result,problem=false
    m.api:request('engine',method,path,body,function(data,err,code)result=data;problem=err or(code and code>=400 and json.encode(data));done=true end)
    ready(function()return done end,'Native request did not finish: '..path);assert(not problem,tostring(problem));return result
end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;love.mousemoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy,false)end
local function click(box,button)
    assert(box,'Missing native UI control');button=button or 1;move(box.x+box.w/2,box.y+box.h/2);wait(.16);pressed[button]=true;love.mousepressed(mouse.x,mouse.y,button,false,1);wait(.16);pressed[button]=nil;love.mousereleased(mouse.x,mouse.y,button,false,1);wait(.24)
end
local function shot(name)move(2,2);wait(.12);shots[#shots+1]=name;wait(.16)end
local function input(box,value)
    click(box);keys.lctrl=true;S.OnKeyPressed('a','a',false);keys.lctrl=nil;S.OnKeyReleased('a','a');S.OnTextInput(value);wait(.35)
end
local function named(prefix)
    for label,box in pairs(buttons)do if tostring(label):sub(1,#prefix)==prefix then return box end end
end
local function scenario()
    m:refreshDecks();ready(function()return m.catalogHealth.ready and#m.decks>=20 end,'Isolated catalog did not load decks',25)
    local before=request('GET','/session/state');assert(not before.running,'Test engine must be idle')
    m:setLobbyFormat('Commander');m:setLobbyPlayers(2);m.playerDeckId=nil;m.page='lobby';m.logOpen=false;m.stackOpen=false
    for _,size in ipairs({{1440,900},{1120,760}})do
        m.settings.windowMode='Windowed';m.settings.resolution=size[1]..'x'..size[2];p:apply(true);wait(.2)
        ready(function()return buttons.yourDeck end,'Lobby selector did not render')
        check(buttons.yourDeck.h==146,'Actual lobby selector honors height146 at '..size[1])
        click(buttons.yourDeck);ready(function()return v.deckSelection and inputs['deck-tile-search']end,'Deck picker did not open')
        check(named('My Decks ·')and named('Starter ·')and named('Preconstructed ·'),'Actual picker exposes all three source groups at '..size[1])
        input(inputs['deck-tile-search'],'Calling All Angels')
        ready(function()local s=v.deckSelection;return s and not s.busy and not s.timer and s.total==1 end,'Real preconstructed search did not settle',20)
        local state=v.deckSelection;local original=state.precons[1];check(original.name=='Calling All Angels'and original.origin=='preconstructed','Actual catalog returns historical product summary at '..size[1])
        shot('search-results-'..size[1]);click(assert(named(original.expansion..' ·')));ready(function()return buttons['Calling All Angels']end,'Expansion did not reveal preconstructed tile')
        local choice=buttons['Calling All Angels'];check(choice.w==choice.h,'Actual preconstructed tile stays square at '..size[1]);shot('preconstructed-'..size[1])
        click(choice);ready(function()return not v.deckSelection and m:findDeck(m.playerDeckId)and m:findDeck(m.playerDeckId).sourceDeckId==original.id end,'Full native deck was not selected')
        local selected=m:findDeck(m.playerDeckId);local count=0;for _,entry in ipairs(selected.main)do count=count+entry.count end
        check(count==99 and#selected.commander==1 and selected.format=='Commander','Selection loads complete99+commander list into lobby at '..size[1])
        check(original.id==selected.sourceDeckId and original.id~=selected.id and selected.origin=='lobby-preconstructed','Temporary selection preserves immutable source identity at '..size[1])
        m:refreshDecks();wait(.4);check(m:findDeck(m.playerDeckId)==selected,'Real collection refresh preserves temporary selection at '..size[1]);shot('selected-'..size[1])
    end
    local selected=m:findDeck(m.playerDeckId);m:setBotDeck(1,selected.id);wait(.15)
    click(assert(buttons['Start match']));ready(function()return not m.gameBusy and m.game and#m.game.players==2 end,'Native preconstructed start did not publish both players',25)
    check(m.page=='table'and m.game and#m.game.players==2 and not m.game.error,'Actual native final validation accepts both complete temporary Commander lists')
    check(m.game.players[1].life==40 and m.game.players[2].life==40,'Native Commander starting life stays authoritative')
    request('POST','/session/stop',{});m.game=nil;m.page='lobby'
    local file=assert(io.open('/tmp/love2gathering-deck-picker-ui-report.json','w'));file:write(json.encode({passed=true,checks=checks,scope='Actual main callbacks, Slab selectors/search/expansion headers at two window sizes, real temporary catalog preconstructed lookup, full list selection and immutable source identity, real final native Commander validation on isolated engine; no user storage'}));file:close();print('DECK PICKER UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
local originalNew=API.new;API.new=function(options)options=options or{};options.enginePort=assert(tonumber(os.getenv('LOVE2GATHERING_ENGINE_PORT')));options.catalogPort=assert(tonumber(os.getenv('LOVE2GATHERING_CATALOG_PORT')));return originalNew(options)end
local modelNew=Model.new;Model.new=function(...)m=modelNew(...);m.settings.windowMode='Windowed';m.settings.resolution='1440x900';m.settings.presentationVersion=2;return m end
local rendererNew=Renderer.new;Renderer.new=function(...)r=rendererNew(...);local original=r.strong;r.strong=function(self,text,...)strong[tostring(text)]=true;return original(self,text,...)end;return r end
local viewNew=View.new;View.new=function(...)v=viewNew(...);return v end
local preferencesNew=Preferences.new;Preferences.new=function(...)p=preferencesNew(...);return p end
assert(love.filesystem.load('application.lua'))()
local appLoad,appUpdate,appDraw,appQuit=love.load,love.update,love.draw,love.quit
function love.load()
    appLoad({});Cursor=require('lib.Slab.Internal.Core.Cursor');Window=require('lib.Slab.Internal.UI.Window')
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return pressed[button]==true end;love.keyboard.isDown=function(...)for _,key in ipairs({...})do if keys[key]then return true end end;return false end
    m.loaded=true;m.settingsLoaded=true;m.page='lobby';m.uiLayout={};m.settings.showCardArt=true;m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.particles=false;m.settings.animations=false;m.settings.uiScale=1;m.settings.renderScale=1;m.settings.windowMode='Windowed';m.settings.presentationVersion=2;m.settings.vsync=false;m.settings.frameLimit=0;p.appliedLoaded=true;p:apply(true)
    for _,name in ipairs({'Button','CheckBox','Input'})do local original=S[name];S[name]=function(a,b,c)local dx,dy=require('lib.Slab.Internal.UI.Region').Transform(nil,0,0);local result=original(a,b,c);local x,y,w,h=Cursor.GetItemBounds();(name=='Input'and inputs or buttons)[name=='CheckBox'and b or a]={x=x+dx,y=y+dy,w=w,h=h};return result end end
    local originalText=S.Text;S.Text=function(value,...)textLedger[tostring(value)]=true;return originalText(value,...)end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    clock=clock+dt;assert(clock<180,'Native UI acceptance exceeded180 seconds');buttons={};inputs={};textLedger={};S.OnMouseMoved(mouse.x,mouse.y,0,0,false);appUpdate(dt)
    if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
end
function love.draw()
    appDraw()
    if #shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)local out=assert(io.open('/tmp/love2gathering-deck-picker-'..name..'.png','wb'));out:write(data:encode('png'):getString());out:close()end)end
end
function love.quit()if appQuit then return appQuit()end end
function love.errorhandler(message)io.stderr:write('DECK PICKER UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
