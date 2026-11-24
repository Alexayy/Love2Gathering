-- Actual Model/API, native engine production decks and LÖVE/Slab input.
-- No projected states, prompts, answers or card zones are injected.
function love.errorhandler(message)
    io.stderr:write('NATIVE COMMANDER UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Layout=require('app.layout');local Preferences=require('app.preferences');local json=require('lib.json')
local Priority=require('app.priority')
local m,r,v,prefs,runner,Cursor,Region
local mouse={x=0,y=0};local down={};local buttons={};local checks={};local cases={}
local elapsed,wake=0,0;local shots={};local seen={}
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('NATIVE COMMANDER UI PASS '..label)end
local function wait(seconds)wake=elapsed+(seconds or .06);coroutine.yield()end
local function untilReady(fn,limit,message)
    local deadline=elapsed+(limit or 20)
    while not fn() do assert(elapsed<deadline,message);wait(.06)end
end
local function move(x,y)
    local ox,oy=mouse.x,mouse.y;mouse.x=x*Layout.scale;mouse.y=y*Layout.scale
    love.mousemoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy,false)
end
local function click(box)
    assert(box,'Required visible control is missing');move(box.x+box.w/2,box.y+box.h/2);wait(.04)
    down[1]=true;love.mousepressed(mouse.x,mouse.y,1,false,1);wait(.04)
    down[1]=false;love.mousereleased(mouse.x,mouse.y,1,false,1);wait(.09)
end
local function screenshot(name)
    shots[#shots+1]=name;wait(.15)
end
local function hit(kind,id)
    for _,entry in ipairs(r.hits)do if entry.kind==kind and (not id or entry.playerId==id)then return entry end end
end
local function settleOpening(count)
    local deadline=elapsed+45;local starting,kept=false,false
    while elapsed<deadline do
        assert(not m.game or not m.game.error,m.game and m.game.error)
        local game=m.game;local prompt=m:prompt()
        if game and game.phase=='Precombat Main' and prompt and prompt.type=='select' then
            check(starting and kept,'Starting-player and Keep buttons reached native main phase: '..count)
            return game
        end
        if prompt and not m.actionBusy and not seen[prompt.id] then
            local label
            if prompt.mulligan then
                check(prompt.mulligan.free and prompt.mulligan.downTo==7,'Native free Commander mulligan metadata: '..count)
                label='Keep';kept=true
            elseif (prompt.message or ''):lower():find('starting player',1,true)then
                label=m.playerName;starting=true
                check(#prompt.choices==count,'Every native player appears in starting-player choices: '..count)
            else
                local choice=Priority.passChoice(prompt)
                if choice then label=prompt.priority and 'Pass Priority' or choice.label end
            end
            assert(label,'Unexpected native opening prompt: '..json.encode(prompt))
            local box=buttons[label]
            if box then seen[prompt.id]=true;click(box)else wait(.08)end
        else wait(.08)end
    end
    error('Native opening sequence timed out for '..count..' seats: '..json.encode(m.game and m.game.prompt))
end
local function stop()
    local done=false;m.pollTimer=9999
    m:request('engine','POST','/session/stop',{},function(data,err)assert(data,err);done=true end)
    untilReady(function()return done and not m.polling end,15,'Native match stop timed out')
    m.game=nil;m.pollTimer=0;m.page='lobby';m.actionBusy=false;m.answeredPrompt=nil;wait(.15)
end
local function scenario()
    untilReady(function()return #m.decks>=20 and m.engineHealth.ok and m.settingsLoaded end,25,'Bundled decks/engine/settings did not load')
    m.playerName='Commander UI Human';m:setLobbyFormat('Commander');m.playerDeckId='commander-krenko-goblins'
    m.settings.resolution='1440x900';m.settings.uiScale=1;m.settings.renderScale=1;m.settings.showCardArt=false;m.settings.vsync=false;m.settings.sfxEnabled=false;m.settings.animations=false;m.settings.particles=false
    prefs:apply(true);m.page='lobby';m.logOpen=false;m.stackOpen=false;wait(.2)
    for _,count in ipairs({4,6})do
        seen={};click(buttons[tostring(count)]);check(m:lobbyPlayerCount()==count,'Actual Commander lobby seat button: '..count)
        local before=m.game and m.game.gameId
        click(buttons['Start match'])
        untilReady(function()return m.game and m.game.gameId~=before and m.page=='table' and #m.game.players==count end,35,'Native match did not start through lobby')
        check(m.game.playerCount==count and m.game.format=='Commander','Actual Model/API startup projects all native seats: '..count)
        local game=settleOpening(count);local human
        for _,player in ipairs(game.players)do
            check(player.life==40 and #player.command==1,'Native starting life and command zone: '..player.name..' / '..count)
            if player.human then human=player else check(#player.hand==0 and player.handCount>=7,'Native bot hand remains private: '..player.name..' / '..count)end
        end
        check(human and #human.hand==human.handCount and human.handCount>=7,'Actual human starting hand rendered: '..count)
        check(#r.multiplayerSeats==count and r.tableCamera.rows==math.ceil(count/2),'Native projection uses complete pannable terrain: '..count)
        screenshot(count..'-overview')
        local last=game.players[#game.players];local nav=assert(hit('seat-focus',last.id));click(nav)
        check(r.tableCamera.focusIndex==nav.focusIndex,'Actual callbacks focus native last bot: '..count)
        screenshot(count..'-focus')
        click(assert(hit('table-overview')));check(r.tableCamera.mode=='overview','Overview returns to actual full native table: '..count)
        cases[#cases+1]={players=count,gameId=game.gameId,replayId=game.replayId,phase=game.phase,humanHand=human.handCount,hiddenBots=count-1,revision=game.revision}
        stop()
    end
    local output=assert(io.open('/tmp/love2gathering-commander-live-ui-report.json','w'));output:write(json.encode({scope='Actual LÖVE/Slab input, Model/API requests and native XMage production Commander starts; temporary catalog storage; card snapshot unavailable, artwork disabled',checks=checks,cases=cases}));output:close()
    print('NATIVE COMMANDER UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return down[button]or false end
    m=Model.new();r=Renderer.new(m);v=View.new(S,m,r);prefs=Preferences.new(m,S,r);v.preferences=prefs
    local original=S.Button;S.Button=function(label,options)
        local dx,dy=Region.Transform(nil,0,0);local result=original(label,options);local x,y,w,h=Cursor.GetItemBounds()
        buttons[label]={x=x+dx,y=y+dy,w=w,h=h};return result
    end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    elapsed=elapsed+dt;assert(elapsed<155,'Native Commander UI acceptance exceeded 155 seconds')
    m:update(dt);prefs:update();S.Update(dt);r:update(dt)
    if elapsed>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
    buttons={};v:build();r:mousemoved(Layout.mouse())
end
function love.draw()
    prefs:beginFrame();r:draw();prefs:endScene();S.Draw()
    if #shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)
        local output=assert(io.open('/tmp/love2gathering-commander-live-'..name..'.png','wb'));output:write(data:encode('png'):getString());output:close()
    end)end
end
function love.mousepressed(x,y,button,touch,clicks)
    S.OnMousePressed(x,y,button,touch,clicks)
    if not m.settingsOpen and not m.zoneView and not m.inspectCard and S.IsVoidHovered()then r:mousepressed(x/Layout.scale,y/Layout.scale,button,clicks)end
end
function love.mousereleased(x,y,button,touch,clicks)S.OnMouseReleased(x,y,button,touch,clicks);r:mousereleased(x/Layout.scale,y/Layout.scale,button)end
function love.mousemoved(x,y,dx,dy,touch)S.OnMouseMoved(x,y,dx,dy,touch);r:mousemoved(x/Layout.scale,y/Layout.scale)end
function love.quit()if m then m:quit()end;S.OnQuit()end
