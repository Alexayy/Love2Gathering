-- Real LÖVE callbacks, Slab controls, Model/API and native production decks.
-- No game states, prompts, answers, card zones or priority projections injected.
function love.errorhandler(message)
    io.stderr:write('NATIVE PRIORITY UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Layout=require('app.layout');local Preferences=require('app.preferences');local json=require('lib.json');local Priority=require('app.priority')
local m,r,v,prefs,runner,Cursor,Region
local mouse={x=0,y=0};local down={};local buttons={};local checks={};local calls={};local samples={};local shots={}
local elapsed,wake=0,0
local function clone(value)return json.decode(json.encode(value))end
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('NATIVE PRIORITY UI PASS '..label)end
local function wait(seconds)wake=elapsed+(seconds or .06);coroutine.yield()end
local function untilReady(fn,limit,label)
    local deadline=elapsed+(limit or 20)
    while not fn()do assert(elapsed<deadline,label..': '..json.encode(m.game and {prompt=m.game.prompt,priority=m.game.priority}));wait(.06)end
end
local function move(x,y)
    local ox,oy=mouse.x,mouse.y;mouse.x=x*Layout.scale;mouse.y=y*Layout.scale
    love.mousemoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy,false)
end
local function click(box)
    assert(box,'Required native UI control is missing');move(box.x+box.w/2,box.y+box.h/2);wait(.04)
    down[1]=true;love.mousepressed(mouse.x,mouse.y,1,false,1);wait(.04)
    down[1]=false;love.mousereleased(mouse.x,mouse.y,1,false,1);wait(.12)
end
local function phaseHit(phase,side)
    for _,hit in ipairs(r.hits)do if hit.kind=='phase-stop' and hit.phase==phase and hit.side==side and hit.w<=24 then return hit end end
end
local function screenshot(name,gold)
    shots[#shots+1]={name=name,gold=gold};wait(.15)
end
local function pass()
    local prompt=m:prompt();assert(prompt,'Native prompt disappeared before Pass')
    for _,choice in ipairs(prompt.choices or {})do
        if choice.id=='done' or tostring(choice.label):lower():find('pass',1,true)then
            local box=buttons[choice.label];if box then click(box);return true end
        end
    end
    return false
end
local function stop()
    local done=false;m.pollTimer=9999
    m:request('engine','POST','/session/stop',{},function(data,err)assert(data,err);done=true end)
    untilReady(function()return done and not m.polling end,15,'Native match stop timed out')
    m.game=nil;m.pollTimer=0;wait(.1)
end
local function scenario()
    untilReady(function()return #m.decks>=20 and m.engineHealth.ok and m.settingsLoaded end,25,'Native engine/settings/bundled lists did not load')
    m.playerName='Priority UI Human';m:setLobbyFormat('Modern');m.playerDeckId='modern-boros-burn';m.botDeckId='modern-merfolk'
    m.settings.resolution='1440x900';m.settings.uiScale=1;m.settings.renderScale=1;m.settings.vsync=false;m.settings.showCardArt=false;m.settings.sfxEnabled=false;m.settings.animations=false;m.settings.particles=false
    prefs:apply(true);m.page='lobby';m.logOpen=true;m.stackOpen=true;wait(.2)
    click(buttons['Start match'])
    untilReady(function()return m.game and m.page=='table' and m.game.gameId and #m.game.players==2 and m:prompt()end,35,'Actual Start match did not create the native duel')
    check(m.game.format=='Modern','Actual lobby Start match loads both validated bundled Modern decks')
    for _,group in ipairs(Priority.groups)do for _,side in ipairs({'own','opponent'})do
        if m:phaseStop(group,side) then
            click(assert(phaseHit(group.key,side),'Missing native phase icon'))
            untilReady(function()return not m.priorityBusy end,10,'Phase icon configure did not finish')
        end
    end end
    -- Select through the actual icons on every run, including when temporary
    -- preferences already retained stops from an earlier acceptance run.
    click(assert(phaseHit('END','opponent')))
    untilReady(function()return not m.priorityBusy end,10,'Opponent end-step icon configure did not finish')
    click(assert(phaseHit('PRECOMBAT','own')))
    untilReady(function()return not m.priorityBusy end,10,'Own main icon configure did not finish')
    check(m:phaseStop(Priority.groups[6],'opponent'),'Actual bot icon selects an opponent end-step stop')
    check(m:phaseStop(Priority.groups[3],'own'),'Actual player icon selects an own main-phase stop')
    local starting,kept=false,false;local deadline=elapsed+45
    while elapsed<deadline do
        local game=m.game;local prompt=m:prompt();assert(not game.error,game.error)
        if prompt and prompt.priority and game.priority and game.priority.reason=='stop' and game.priority.stopStep=='PRECOMBAT_MAIN'then break end
        if prompt and not m.actionBusy and not m.priorityBusy then
            if prompt.mulligan and buttons.Keep then kept=true;click(buttons.Keep)
            elseif (prompt.message or ''):lower():find('starting player',1,true)and buttons[m.playerName]then starting=true;click(buttons[m.playerName])
            elseif prompt.priority then if not pass()then wait(.08)end
            else error('Unexpected native opening prompt: '..json.encode(prompt))end
        else wait(.08)end
    end
    check(starting and kept,'Actual starting-player and Keep Slab buttons reach native main priority')
    untilReady(function()return m:prompt() and m.game.priority and m.game.priority.reason=='stop' and m.game.priority.stopStep=='PRECOMBAT_MAIN'end,10,'Own main stop was not held')
    local human,bot
    for _,player in ipairs(m.game.players)do if player.human then human=player else bot=player end end
    check(human and #human.hand==human.handCount and bot and #bot.hand==0,'Real human hand is present and native bot hand remains hidden')
    local policy=m.game.priority
    check(policy.paused and policy.stopPlayerId==human.id and policy.stops.opponent[1]=='END_TURN','Native state confirms own stop and configured opponent end step')
    local handHits=0;for _,hit in ipairs(r.hits)do if hit.kind=='hand'then handHits=handHits+1 end end
    check(handHits==human.handCount,'Real projected hand renders as selectable card hit regions')
    local automaticBefore=policy.autoPassCount or 0
    samples[#samples+1]=clone(policy);screenshot('own-main',true)
    check(buttons['End Turn']~=nil,'Native priority prompt exposes the actual End Turn control')
    click(buttons['End Turn'])
    local endDeadline=elapsed+60;local passed=0
    while elapsed<endDeadline do
        local game=m.game;local prompt=m:prompt();assert(not game.error,game.error)
        local state=game.priority or {}
        if prompt and state.reason=='stop' and state.stopStep=='END_TURN' and state.stopPlayerId==bot.id then break end
        if prompt and not m.actionBusy and not m.priorityBusy then
            check(not (state.autoPass and state.reason=='new_turn' and (state.meaningfulActionCount or 0)==0),'Automatic priority does not force a question at an empty new-turn boundary')
            samples[#samples+1]=clone(state)
            assert(prompt.priority,'Unexpected non-priority prompt after End Turn: '..json.encode(prompt))
            if pass()then passed=passed+1 else wait(.08)end
        else wait(.08)end
    end
    untilReady(function()return m:prompt() and m.game.priority.reason=='stop' and m.game.priority.stopStep=='END_TURN' and m.game.priority.stopPlayerId==bot.id end,5,'Opponent end-step stop was not reached')
    local stopped=m:prompt();policy=m.game.priority;samples[#samples+1]=clone(policy)
    check(passed==0 and policy.autoPassCount>automaticBefore,'End Turn reaches the selected opponent stop without asking to Pass empty priority windows')
    check(policy.paused and not policy.yielding and policy.stopPlayerId==bot.id,'Native opponent end step is held with yielding canceled')
    check(stopped.priority and stopped.id==m.game.prompt.id and type(stopped.actionable)=='table','Paused stop retains the actual native prompt and actionable IDs')
    wait(.55);check(m:prompt() and m:prompt().id==stopped.id,'The selected native stop stays paused without submitting an automatic answer')
    screenshot('opponent-end',true)
    check(pass(),'Actual Slab Pass is available at the selected opponent end step')
    untilReady(function()return m:prompt() and m:prompt().id~=stopped.id end,20,'Pass did not resume the native stop')
    check(m:prompt().id~=stopped.id,'Actual Pass resumes the held stop and preserves subsequent native choices')
    local toggle=buttons['Automatic priority · click for full control']
    if toggle then
        click(toggle);untilReady(function()return not m.priorityBusy and m.game.priority.autoPass==false end,10,'Full-control icon did not apply')
        check(m.game.priority.autoPass==false,'Actual priority-mode icon switches the native engine to full control')
        click(assert(buttons['Full control · click for automatic priority']))
        untilReady(function()return not m.priorityBusy and m.game.priority.autoPass==true end,10,'Automatic priority icon did not resume')
        check(m.game.priority.autoPass==true,'Actual priority-mode icon returns the native engine to automatic passing')
    end
    local replayId=m.game.replayId;local gameId=m.game.gameId
    local commandCount=0;for _,call in ipairs(calls)do if call.path=='/session/priority'then commandCount=commandCount+1 end end
    check(commandCount>=3,'Actual UI sent native configure and End Turn commands through Model/API')
    screenshot('resumed',false);stop()
    local output=assert(io.open('/tmp/love2gathering-priority-live-ui-report.json','w'))
    output:write(json.encode({scope='Actual LÖVE/Slab callbacks, Model/API and XMage production bundled Modern duel; temporary catalog; no injected projections or answers',checks=checks,gameId=gameId,replayId=replayId,prioritySamples=samples,engineCalls=calls,physical={love.graphics.getDimensions()},logical={Layout.dimensions()}}));output:close()
    print('NATIVE PRIORITY UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return down[button]or false end
    m=Model.new();r=Renderer.new(m);v=View.new(S,m,r);prefs=Preferences.new(m,S,r);v.preferences=prefs
    local originalRequest=m.request;m.request=function(self,service,method,path,body,callback,quiet)
        if service=='engine'and method=='POST'then calls[#calls+1]={path=path,body=clone(body)}end
        return originalRequest(self,service,method,path,body,callback,quiet)
    end
    local originalButton=S.Button;S.Button=function(label,options)
        local dx,dy=Region.Transform(nil,0,0);local result=originalButton(label,options);local x,y,w,h=Cursor.GetItemBounds()
        buttons[label]={x=x+dx,y=y+dy,w=w,h=h};return result
    end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    elapsed=elapsed+dt;assert(elapsed<160,'Native priority UI acceptance exceeded 160 seconds')
    m:update(dt);prefs:update();S.Update(dt);r:update(dt)
    if elapsed>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
    buttons={};v:build();r:mousemoved(Layout.mouse())
end
function love.draw()
    prefs:beginFrame();r:draw();prefs:endScene();S.Draw()
    if #shots>0 then local job=table.remove(shots,1);love.graphics.captureScreenshot(function(data)
        if job.gold then
            local w,h=Layout.dimensions();local L=Layout.table(w,h);local width=math.min(460,w-400);local x=(w-width)/2;local y=L.viewport.y+12
            local rr,gg,bb=data:getPixel(math.floor((x+width-20)*Layout.scale),math.floor((y+22)*Layout.scale))
            check(rr>.14 and gg>.08 and bb<rr*.65,'Actual native '..job.name..' pause has a visible gold status surface')
        end
        local output=assert(io.open('/tmp/love2gathering-priority-live-'..job.name..'.png','wb'));output:write(data:encode('png'):getString());output:close()
    end)end
end
function love.mousepressed(x,y,button,touch,clicks)
    S.OnMousePressed(x,y,button,touch,clicks)
    if not m.settingsOpen and not m.zoneView and not m.inspectCard and S.IsVoidHovered()then r:mousepressed(x/Layout.scale,y/Layout.scale,button,clicks)end
end
function love.mousereleased(x,y,button,touch,clicks)S.OnMouseReleased(x,y,button,touch,clicks);r:mousereleased(x/Layout.scale,y/Layout.scale,button)end
function love.mousemoved(x,y,dx,dy,touch)S.OnMouseMoved(x,y,dx,dy,touch);r:mousemoved(x/Layout.scale,y/Layout.scale)end
function love.quit()if m then m:quit()end;S.OnQuit()end
