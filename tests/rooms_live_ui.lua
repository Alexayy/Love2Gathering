-- Two real API clients, two local gateways and native XMage. Initial choices,
-- room actions, first picks, building and game opening use actual Slab input.
-- The remaining offered picks use Model helpers over the real transport.
local originalClipboard
function love.errorhandler(message)
    if originalClipboard then pcall(love.system.setClipboardText,originalClipboard)end
    io.stderr:write('NATIVE ROOM UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
local S=require('lib.Slab');local API=require('app.api');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local DraftUI=require('app.draft_ui');local json=require('lib.json')
local clients,active,runner,Cursor,Region
local buttons,controls,selections={},{},{};local mouse={x=0,y=0};local down=false;local keys={}
local clock,wake=0,0;local checks={};local shots={};local helperPicks=0;local ownershipState
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('NATIVE ROOM UI PASS '..label)end
local function wait(seconds)wake=clock+(seconds or .06);coroutine.yield()end
local function untilReady(fn,limit,label)
    local deadline=clock+(limit or 30)
    while not fn()do
        for _,client in ipairs(clients)do assert(not client.m.roomError,client.m.roomError)end
        assert(clock<deadline,label);wait(.06)
    end
end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x=x*Layout.scale;mouse.y=y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy)end
local function click(box)
    assert(box,'Required native room control is missing');move(box.x+box.w/2,box.y+box.h/2);wait(.04);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.04);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.12)
end
local function switch(index)active=clients[index];move(2,2);wait(.15)end
local function number(label,value)
    click(controls[label]);keys.lctrl=true;S.OnKeyPressed('a','a',false);S.OnKeyReleased('a','a');keys={};wait(.05);S.OnTextInput(tostring(value));wait(.12)
end
local function screenshot(name)shots[#shots+1]=name;wait(.15)end
local function own(client)
    for _,member in ipairs(client.m.room and client.m.room.members or {})do if member.id==client.m.roomParticipantId then return member end end
end
local function draftDone(client)local d=client.m.roomDraft;return d and(d.status=='building'or d.status=='ready')end
local function opening()
    local deadline=clock+50;local answered={};local kept={}
    while clock<deadline do
        local all=true
        for index,client in ipairs(clients)do
            local m=client.m;local p=m:prompt()
            assert(not(m.game and m.game.error),m.game and m.game.error)
            if not(m.game and m.game.phase and m.game.phase~=''and kept[index])then all=false end
            if p and not m.actionBusy and not m.priorityBusy and not answered[p.id..':'..index]then
                local label
                if p.mulligan then label='Keep';kept[index]=true
                elseif(p.message or''):lower():find('starting player',1,true)then
                    for _,choice in ipairs(p.choices or {})do if choice.label==m.playerName then label=choice.label;break end end
                elseif p.priority and m.game.phase~='Precombat Main'then
                    for _,choice in ipairs(p.choices or {})do if choice.id=='done'then label=choice.label;break end end
                end
                if label then switch(index);if buttons[label]then answered[p.id..':'..index]=true;click(buttons[label])end end
            end
        end
        if all then check(kept[1]and kept[2],'Both real drafted humans keep native opening hands through actual Slab controls');return end
        wait(.06)
    end
    error('Native drafted game opening did not reach human main priority')
end
local function scenario()
    untilReady(function()return clients[1].m.settingsLoaded and clients[2].m.settingsLoaded and clients[1].m.engineHealth.ok and clients[2].m.engineHealth.ok end,30,'Real catalog/engine/preferences did not load')
    for _,client in ipairs(clients)do
        local m=client.m;m.settings.resolution='1440x900';m.settings.windowMode='Windowed';m.settings.uiScale=1;m.settings.renderScale=1;m.settings.vsync=false;m.settings.showCardArt=false;m.settings.sfxEnabled=false;m.settings.animations=false;m.settings.particles=false;m.settings.fontFamily='Built-in DejaVu Sans';client.p:apply(true);m:showRooms()
    end
    untilReady(function()return clients[1].m.roomCapabilities and clients[2].m.roomCapabilities end,25,'Native room capabilities did not load')
    local caps=active.m.roomCapabilities.draft;local selected
    for _,set in ipairs(caps.sets or {})do if set.code=='M21'then selected=set.code;break end end
    assert(selected,'Native Core Set 2021 boosters were not offered')
    click(buttons.Draft)
    local setup=active.m.roomSetup;setup.name='Native UI draft acceptance';setup.maxPlayers=4;setup.draft.mode='booster';setup.draft.profile='Limited';setup.draft.pairing='swiss';setup.draft.timing='BEGINNER';setup.draft.sets=json.array({selected,selected,selected})
    wait(.1);click(buttons['Create invite room'])
    untilReady(function()return active.m.room end,20,'Host invitation room did not open')
    check(active.m.room.config.kind=='draft'and active.m.room.config.draft.sets[2]==selected,'Actual Create submits a native traditional three-pack configuration')
    click(buttons['Copy code']);local code=love.system.getClipboardText();check(code:sub(1,5)=='L2G1-','Actual Copy returns one self-contained native invitation code')
    switch(2);click(buttons['Paste code']);click(buttons['Join room'])
    untilReady(function()return active.m.room and active.m.roomParticipantId end,20,'Second gateway did not join by code')
    check(clients[1].m.roomParticipantId~=clients[2].m.roomParticipantId,'Independent real gateways authenticate two distinct human seats')
    click(buttons.Ready);switch(1);click(buttons['Add bot']);click(buttons['Add bot']);click(buttons.Ready)
    untilReady(function()return active.m.room.canStart end,20,'Real human/bot seats did not become ready')
    check(#active.m.room.members==4,'Actual native room contains two humans and two optional bots')
    screenshot('ready');click(buttons['Start draft'])
    untilReady(function()return clients[1].m.roomDraft and clients[2].m.roomDraft and #(clients[1].m.roomDraft.pack or{})>0 and #(clients[2].m.roomDraft.pack or{})>0 end,45,'Native private opening packs did not arrive')
    local ids={};for _,card in ipairs(clients[1].m.roomDraft.pack)do ids[card.id]=true end
    for _,card in ipairs(clients[2].m.roomDraft.pack)do assert(not ids[card.id],'Private opening pack instances overlap')end
    for _,client in ipairs(clients)do for _,player in ipairs(client.m.roomDraft.players or{})do assert(not player.pack and not player.pool,'Peer draft contents leaked in public seat metadata')end end
    check(true,'Native opening packs contain distinct instances and public seats expose no peer pack/pool')
    for index=1,2 do
        switch(index);local card=active.m.roomDraft.pack[1];screenshot(index==1 and'host-pack'or'guest-pack')
        local w,h=Layout.dimensions();local l=DraftUI.layout(w,h,false)
        for _,offered in ipairs(active.m.roomDraft.pack)do
            local box=assert(buttons[offered.name..' · right-click to inspect'],'Native pack card control is missing')
            assert(box.x>=l.main.x and box.x+box.w<=l.main.x+l.main.w-26,'Native card extends beyond the pack viewport')
        end
        check(true,'Every native pack card fits the horizontal viewport without clipping · client '..index)
        click(buttons[card.name..' · right-click to inspect'])
        untilReady(function()return not active.m.roomBusy and #(active.m.roomDraft.pool or{})>=1 end,15,'Actual card click was not accepted by the native draft')
        check(true,'Actual Slab pack-card click submits its native token and instance · client '..index)
    end
    local deadline=clock+120
    while not(draftDone(clients[1])and draftDone(clients[2]))do
        assert(clock<deadline,'Real native draft did not complete its boosters')
        for _,client in ipairs(clients)do
            local m=client.m;local draft=m.roomDraft;assert(not m.roomError,m.roomError)
            if draft and draft.status=='drafting'and draft.pickToken and #(draft.pack or{})>0 and not m.roomBusy then
                assert(m:pickDraftCard(draft.pack[1].id),'Offered native helper pick was refused locally');helperPicks=helperPicks+1
            end
        end
        wait(.04)
    end
    local pools={}
    for index=1,2 do
        switch(index);local draft=active.m.roomDraft;pools[index]=#draft.pool
        check(#draft.pool>=40,'Native boosters produce a complete owned draft pool · client '..index)
        local chosen
        for _,card in ipairs(draft.pool)do if tostring(card.type):lower():find('creature',1,true)then chosen=card;break end end
        assert(chosen,'Native pool contained no creature for the UI acceptance deck')
        click(buttons[chosen.name..' · right-click to inspect'])
        number('Number of Plains',39)
        check(DraftUI.deckCount(active.m.roomDraftDeck)==40,'Actual pool selection and basic-land input build forty cards · client '..index)
        screenshot(index==1 and'host-builder'or'guest-builder');click(buttons['Submit deck'])
        untilReady(function()local seat=own(active);return seat and seat.ready and active.m.roomDraft.selection end,20,'Native Limited validator did not accept the submitted UI deck')
        check(active.m.roomDraft.selection.main[1]==chosen.id and active.m.roomDraft.selection.basics.Plains==39,'Native accepted selection preserves its owned UUID and basic quantity · client '..index)
    end
    switch(1);untilReady(function()return active.m.room.canStart end,20,'Native accepted decks did not enable the first round')
    screenshot('native-decks-ready');click(buttons['Start round'])
    untilReady(function()return clients[1].m.roomGameActive and clients[2].m.roomGameActive end,40,'Native first-round pairings did not route both clients')
    for _,client in ipairs(clients)do
        check(client.m.api.roomSession and client.m.api.roomSession.gameId==client.m.game.gameId,'Actual engine route is bound to the assigned native game · '..client.m.playerName)
        local humans=0;for _,player in ipairs(client.m.game.players)do if player.human then humans=humans+1 else assert(#(player.hand or{})==0,'Other player hand leaked')end end
        check(humans==1,'Native game view exposes exactly one entitled hand · '..client.m.playerName)
    end
    opening();switch(1);screenshot('host-native-board');switch(2);screenshot('guest-native-board')
    local summary={passed=true,scope='Two actual frontend/API instances, two real local gateways and native XMage; actual room/first-pick/building/opening Slab input; remaining native offered picks submitted by Model helper; no injected game/draft projections',checks=checks,helperPicks=helperPicks,poolSizes=pools,gameIds={clients[1].m.game.gameId,clients[2].m.game.gameId},physical={love.graphics.getDimensions()},logical={Layout.dimensions()}}
    switch(1);active.m:showRooms();wait(.15);click(buttons['Close room']);untilReady(function()return not active.m.roomConnectionId end,20,'Native room close did not finish')
    untilReady(function()return clients[2].m.room and clients[2].m.room.phase=='closed'end,20,'Second native frontend did not observe host close')
    check(clients[2].m.game==nil and clients[2].m.api.roomSession==nil,'Closing the real room clears the second frontend’s stale game route')
    summary.checks=checks
    local output=assert(io.open('/tmp/love2gathering-rooms-live-ui-report.json','w'));output:write(json.encode(summary));output:close()
    print('NATIVE ROOM UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
    originalClipboard=love.system.getClipboardText();S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(b)return b==1 and down or false end
    love.keyboard.isScancodeDown=function(...)for _,key in ipairs({...})do if keys[key]then return true end end;return false end
    clients={};local originalNew=API.new
    for index,name in ipairs({'UI Draft Host','UI Draft Guest'})do
        API.new=function()return originalNew({catalogPort=tonumber(os.getenv('LOVE2GATHERING_CATALOG_PORT')),enginePort=tonumber(os.getenv('LOVE2GATHERING_ENGINE_PORT')),roomPort=tonumber(os.getenv(index==1 and'LOVE2GATHERING_ROOM_HOST_PORT'or'LOVE2GATHERING_ROOM_GUEST_PORT'))})end
        local m=Model.new();m.playerName=name
        local r=Renderer.new(m);local v=View.new(S,m,r);local p=Preferences.new(m,S,r);v.preferences=p
        local originalWindow=v.window;v.window=function(self,id,...)return originalWindow(self,name..':'..id,...)end
        clients[index]={m=m,r=r,v=v,p=p,port=index==1 and os.getenv('LOVE2GATHERING_ROOM_HOST_PORT')or os.getenv('LOVE2GATHERING_ROOM_GUEST_PORT')}
    end
    API.new=originalNew;active=clients[1];active.p:apply()
    for _,name in ipairs({'Button','Input','BeginComboBox','TextSelectable'})do
        local original=S[name];S[name]=function(id,options)
            local dx,dy=Region.Transform(nil,0,0);local result=original(id,options);local x,y,w,h=Cursor.GetItemBounds()
            local target=name=='Button'and buttons or name=='TextSelectable'and selections or controls
            local key=options and options.Tooltip or id;target[key]={x=x+dx,y=y+dy,w=w,h=h};target[id]=target[id]or target[key]
            if name=='Button'and options and options.Tooltip then target[options.Tooltip:match('^[^\n]+')]=target[key]end
            return result
        end
    end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    clock=clock+dt;assert(clock<280,'Native room UI acceptance exceeded 280 seconds')
    for _,client in ipairs(clients)do client.m:update(dt);client.r:update(dt)end
    active.p:update();S.Update(dt)
    if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
    buttons,controls,selections={},{},{};active.v:build();active.r:mousemoved(Layout.mouse())
    local ownership={};for _,client in ipairs(clients)do if client.m.roomConnectionId then ownership[#ownership+1]={port=client.port,connectionId=client.m.roomConnectionId}end end
    local encoded=json.encode(ownership)
    if encoded~=ownershipState then local output=assert(io.open(love.filesystem.getSource()..'/ownership.json','w'));output:write(encoded);output:close();ownershipState=encoded end
end
function love.draw()
    active.p:beginFrame();active.r:draw();active.p:endScene();S.Draw()
    if #shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)local output=assert(io.open('/tmp/love2gathering-rooms-live-'..name..'.png','wb'));output:write(data:encode('png'):getString());output:close()end)end
end
function love.quit()
    if originalClipboard then love.system.setClipboardText(originalClipboard)end
    for _,client in ipairs(clients or{})do client.m:quit()end;S.OnQuit()
end
