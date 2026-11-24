-- Actual main callbacks/API/Slab over a test-only HTTP facade. Initial zones
-- are deterministic fixtures; responses and resulting effects are native.
function love.errorhandler(message)io.stderr:write('COMBAT TIMING UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
local json=require('lib.json');local Layout=require('app.layout');local S=require('lib.Slab');local API=require('app.api');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences')
local m,r,v,p,Cursor,Window;local mouse={x=2,y=2};local pressed={};local clock,wake=0,0;local runner;local buttons,checks,shots={},{},{};local reports={};local strong={};local sceneBusy=false;local textLedger={}
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('COMBAT TIMING UI PASS '..label);io.stdout:flush()end
local function wait(t)wake=clock+(t or .1);coroutine.yield()end
local function ready(fn,label,seconds)local deadline=clock+(seconds or 12);while not fn()do if clock>=deadline then io.stderr:write(json.encode({prompt=m and m.game and m.game.prompt,actionBusy=m and m.actionBusy,toasts=m and m.toasts})..'\n');error(label)end;wait(.06)end end
local function request(method,path,body)
    local done,result,problem=false
    m.api:request('engine',method,path,body,function(data,err,code)result=data;problem=err or(code and code>=400 and json.encode(data));done=true end)
    ready(function()return done end,'Native request did not finish: '..path);assert(not problem,tostring(problem));return result
end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;love.mousemoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy,false)end
local function click(box,button)
    assert(box,'Missing native UI control');button=button or 1;move(box.x+box.w/2,box.y+box.h/2);wait(.16)
    pressed[button]=true;love.mousepressed(mouse.x,mouse.y,button,false,1);wait(.16);pressed[button]=nil;love.mousereleased(mouse.x,mouse.y,button,false,1);wait(.24)
end
local function shot(name)move(2,2);wait(.12);shots[#shots+1]=name;wait(.16)end
local function fixture(name)
    sceneBusy=true;ready(function()return not m.polling and not m.actionBusy end,'Prior native poll did not finish');m.game=nil;m.answeredPrompt=nil;m.actionBusy=false;m.priorityBusy=false;v.cardChoiceState=nil;v.cardChoiceHits={};v.cardChoiceDrag=nil;m.inspectCard=nil;m.zoneView=nil
    local opened=request('POST','/fixture/'..name,{});assert(opened.fixture and opened.scenario==name,'Not a native fixture server')
    local state=request('GET','/session/state');m:setGame(state);m.page='table';m.pollTimer=0;sceneBusy=false
    ready(function()return m.game and m.game.players and#m.game.players==2 end,'Native fixture board did not arrive');wait(.25)
end
local function finish(name)
    local report
    ready(function()report=request('GET','/fixture/result');return report.nativeResult and report.nativeResult.done end,'Native '..name..' operation did not finish',15)
    assert(report.scenario==name and not report.nativeResult.error,json.encode(report));reports[name]=report;return report
end
local function cardHit(name)
    for _,hit in ipairs(r.hits or {})do if hit.card and hit.card.name==name and(hit.kind=='permanent'or hit.kind=='card')then return hit end end
end
local function nativeDone()
    local prompt=m:prompt();for _,choice in ipairs(prompt and prompt.choices or {})do if choice.responseType=='boolean'and choice.value==true then return buttons[choice.label]end end
end
local function scenario()
    ready(function()return m.catalogHealth.ready end,'Temporary catalog did not become ready',25)
    local requested=tonumber(os.getenv('COMBAT_TEST_WIDTH'));local sizes=requested and{{requested,requested==1120 and 760 or 900}}or{{1440,900},{1120,760}}
    for _,size in ipairs(sizes)do
        m.settings.resolution=size[1]..'x'..size[2];m.settings.windowMode='Windowed';m.settings.presentationVersion=2;p:apply(true);wait(.2)
        m.uiLayout={}
        fixture('ayara');ready(function()return m:prompt()and m:prompt().combat and m:prompt().combat.role=='blockers'end,'Native Ayara blocker choice did not arrive')
        check(m:prompt().combat.declarationConfirmed==false,'Native choice clearly labels unconfirmed blocker selection at '..size[1])
        check(tostring(m:prompt().combat.message):find('not confirmed',1,true),'Native prompt explains Done confirmation before activating abilities at '..size[1])
        local old=m:prompt().id;click(cardHit('Relentless Rats'));ready(function()return m:prompt()and m:prompt().id~=old and not m.actionBusy end,'Rat assignment was not acknowledged')
        local group=m.game.combat.groups[1]
        check(group.blocked and group.declarationConfirmed==false and#group.blockerIds==1,'Selected Rat block is still provisional before Done at '..size[1]);shot('ayara-provisional-'..size[1])
        local label='Stop after confirmed blockers, before combat damage · opponents’ turns'
        if not m:phaseStop(require('app.priority').beforeDamage,'opponent')then click(assert(buttons[label]))end
        ready(function()return not m.priorityBusy and m:phaseStop(require('app.priority').beforeDamage,'opponent')end,'Before damage stop did not acknowledge')
        local native=request('GET','/session/state');local has=false;for _,step in ipairs(native.priority.stops.opponent)do if step=='DECLARE_BLOCKERS'then has=true end end
        check(has,'Actual compact stop control configures native DECLARE_BLOCKERS at '..size[1])
        click(nativeDone());ready(function()return m:prompt()and m:prompt().priority and m.game.combat.groups[1].declarationConfirmed end,'Confirmed pre-damage priority did not arrive')
        check(m.game.priority.reason=='stop'and m.game.priority.stopStep=='DECLARE_BLOCKERS','Actual native stop visibly pauses after confirmed blockers at '..size[1])
        check(require('app.board_fx').blockStatus(m.game.combat.groups[1])=='BLOCKED','Attacker badge reflects native confirmed Blocked at '..size[1])
        local holder;for _,player in ipairs(m.game.players)do if player.human then holder=player end end
        check(holder and m.game.priorityPlayerId==holder.id and tonumber(m.game.priorityStartedAt),'Native holder and actual priority timestamp drive dedicated rope at '..size[1]);shot('ayara-confirmed-'..size[1])
        click(cardHit('Ayara, First of Locthwain'));ready(function()return m:prompt()and m:prompt().type=='choose_ability'end,'Native Ayara activation selector did not open')
        local found;for text,box in pairs(buttons)do if tostring(text):find('Sacrifice another black creature',1,true)then found=box end end;click(assert(found))
        ready(function()return m:prompt()and m:prompt().pendingAction and not m.actionBusy end,'Native sacrifice cost did not arrive')
        check(not m:prompt().priority and m:prompt().pendingAction.kind=='activation','Native sacrifice cost remains interactive, outside auto priority at '..size[1])
        move(2,2);wait(.3)
        shot('ayara-cost-'..size[1])
        check(buttons['Show stack while choosing']and#m.stackHits==0,'Stack automatically folds so native battlefield sacrifice choices stay accessible at '..size[1])
        click(cardHit('Relentless Rats'));local report=finish('ayara')
        check(report.nativeResult.sacrificed and report.nativeResult.nativeDamageToDefender==0 and report.nativeResult.lifeAfter==20,'Actual confirmed Rat block then Ayara sacrifice prevents nontrample native damage at '..size[1])
        check(report.nativeResult.combat.groups[1].blocked and report.nativeResult.combat.groups[1].declarationConfirmed and#report.nativeResult.combat.groups[1].blockerIds==0,'Native confirmed blocked state remains after Rat disappears at '..size[1])
        check(#report.acceptedActions==5,'Only five genuine gameplay inputs assign/confirm/activate/select/sacrifice at '..size[1]);shot('ayara-after-sacrifice-'..size[1]);report.display={requested=size,physical={love.graphics.getDimensions()},logical={Layout.dimensions()}};reports[tostring(size[1])]=report
        click(assert(buttons['Choose combat step stops']));wait(.1);shot('combat-step-picker-'..size[1])
        check(v.combatStopsOpen and buttons['Close combat stops'],'Compact combat picker opens actual step controls at '..size[1]);click(assert(buttons['Close combat stops']))
    end
    v.combatStopsOpen=false;fixture('goreclaw');local goreReport=finish('goreclaw');wait(.2)
    local gore=assert(cardHit('Goreclaw, Terror of Qal Sisma')).card
    check(goreReport.nativeResult.gainedTrample and gore.currentRules:find('\ntrample',1,true),'Actual Goreclaw native attack trigger grants live Trample independently from printed rules')
    check(strong.Trample,'Actual battlefield renderer visibly labels the temporary gained Trample ability');shot('goreclaw-gained-trample')
    click(cardHit('Goreclaw, Terror of Qal Sisma'),3);ready(function()return m.inspectCard and buttons['Show current rules']end,'Current native card details did not open')
    check(textLedger['Trample · granted'],'Actual card details visibly identify temporary granted Trample')
    click(assert(buttons['Show current rules']));check(v.inspectCurrentRules,'Current native rules can be expanded separately from catalog printing');shot('goreclaw-current-rules')
    local out=assert(io.open('/tmp/love2gathering-combat-timing-ui-'..tostring(requested or'all')..'-report.json','w'));out:write(json.encode({passed=true,checks=checks,cases=reports,scope='Actual main.lua callbacks, Slab controls and asynchronous HTTP against test-only native initial zones; production Session.action, actual blocker confirmation, native pre-damage stop, Ayara cost and real combat damage; requested and actual display dimensions retained'}));out:close();print('COMBAT TIMING UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
local originalNew=API.new;API.new=function(options)options=options or{};options.enginePort=assert(tonumber(os.getenv('LOVE2GATHERING_ENGINE_PORT')));options.catalogPort=assert(tonumber(os.getenv('LOVE2GATHERING_CATALOG_PORT')));return originalNew(options)end
local modelNew=Model.new;Model.new=function(...)m=modelNew(...);m.settings.windowMode='Windowed';local width=tonumber(os.getenv('COMBAT_TEST_WIDTH'))or 1440;m.settings.resolution=width..'x'..(width==1120 and 760 or 900);m.settings.presentationVersion=2;return m end
local rendererNew=Renderer.new;Renderer.new=function(...)r=rendererNew(...);local original=r.strong;r.strong=function(self,text,...)strong[tostring(text)]=true;return original(self,text,...)end;return r end
local viewNew=View.new;View.new=function(...)v=viewNew(...);return v end
local preferencesNew=Preferences.new;Preferences.new=function(...)p=preferencesNew(...);return p end
assert(love.filesystem.load('application.lua'))()
local appLoad,appUpdate,appDraw,appQuit=love.load,love.update,love.draw,love.quit
function love.load()
    appLoad({});Cursor=require('lib.Slab.Internal.Core.Cursor');Window=require('lib.Slab.Internal.UI.Window')
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return pressed[button]==true end
    m.loaded=true;m.settingsLoaded=true;m.page='table';m.uiLayout={};m.settings.showCardArt=true;m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.particles=false;m.settings.animations=false;m.settings.uiScale=1;m.settings.renderScale=1;m.settings.windowMode='Windowed';m.settings.presentationVersion=2;m.settings.vsync=false;m.settings.frameLimit=0;p.appliedLoaded=true;p:apply(true)
    for _,name in ipairs({'Button','CheckBox'})do local original=S[name];S[name]=function(a,b,c)local result=original(a,b,c);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);buttons[name=='CheckBox'and b or a]={x=x,y=y,w=w,h=h};return result end end
    local originalText=S.Text;S.Text=function(value,...)textLedger[tostring(value)]=true;return originalText(value,...)end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    clock=clock+dt;assert(clock<180,'Native UI acceptance exceeded180 seconds');buttons={};textLedger={};S.OnMouseMoved(mouse.x,mouse.y,0,0,false);appUpdate(dt)
    if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
end
function love.draw()
    appDraw()
    if #shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)local out=assert(io.open('/tmp/love2gathering-combat-timing-'..name..'.png','wb'));out:write(data:encode('png'):getString());out:close()end)end
end
function love.quit()if appQuit then return appQuit()end end
function love.errorhandler(message)io.stderr:write('COMBAT TIMING UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
