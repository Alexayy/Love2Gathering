-- Two independent frontend models and actual Slab input. The gateway/native
-- projections below are synthetic; native/network acceptance is separate.
local originalClipboard
function love.errorhandler(message)
    if originalClipboard then pcall(love.system.setClipboardText,originalClipboard)end
    io.stderr:write('ROOM/DRAFT UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
local json=require('lib.json');local function clone(v)return json.decode(json.encode(v))end
local gateway={connections={},calls={},revision=0}
local caps={game={formats={{id='Modern',minPlayers=2,maxPlayers=2},{id='Commander',minPlayers=2,maxPlayers=10}},maxPlayers=10},
    draft={modes={{id='booster',label='Booster draft',minPlayers=4,maxPlayers=16,packCount=3},{id='random',label='Random draft',minPlayers=4,maxPlayers=16,packCount=3},{id='cube',label='Cube draft',minPlayers=4,maxPlayers=16,packCount=3}},profiles={{id='Limited',label='Limited',minDeckSize=40}},pairings={{id='swiss',label='Swiss'},{id='elimination',label='Single elimination'}},timings={{id='REGULAR',label='Regular'}},sets={{code='one',name='Fixture set one'},{code='two',name='Fixture set two'}},cubes={{code='CubeOne',name='Fixture cube one'},{code='CubeTwo',name='Fixture cube two'}},basicLands={{name='Plains',manaSymbol='W'},{name='Island',manaSymbol='U'}},minDeckSize=40}}
local function member(id)for _,p in ipairs(gateway.room.members)do if p.id==id then return p end end end
local function canStart()
    if not gateway.room then return false end
    if #gateway.room.members~=gateway.room.config.maxPlayers then return false end
    for _,p in ipairs(gateway.room.members)do if not p.ready then return false end end
    return true
end
local function game(id)
    local players={}
    for _,p in ipairs(gateway.room.members)do players[#players+1]={id=p.id,name=p.name,human=p.id==id,bot=p.bot,life=20,hand=p.id==id and{{id=id..'-hand',name=id..' private hand',type='Land'}}or{},handCount=7,battlefield={},libraryCount=33,graveyard={},exile={},command={},mana={}}end
    return {gameId='SYNTHETIC-ROOM-GAME',revision=gateway.revision,running=true,players=players,stack={},log={},turn=1,phase='Precombat Main',step='Precombat Main',activePlayerId='Host'}
end
local function envelope(id)
    gateway.room.revision=gateway.revision;gateway.room.canStart=canStart()
    return clone({connectionId=id..'-connection',participantId=id,room=gateway.room,draft=gateway.drafts and gateway.drafts[id],game=gateway.room.phase=='playing'and game(id)or nil})
end
local function handle(client,method,path,body)
    gateway.calls[#gateway.calls+1]={client=client,method=method,path=path,body=body and clone(body)}
    if path=='/client/capabilities'then return clone(caps)end
    if path=='/client/rooms'and method=='POST'then
        gateway.revision=gateway.revision+1;gateway.connections[client..'-connection']=client
        gateway.room={id='private-fixture-room',name=body.name,hostId=client,phase='lobby',inviteCode='L2G-INVITE-ONLY',config=clone(body),members={{id=client,name=body.playerName,bot=false,connected=true,ready=false}}}
        return envelope(client)
    end
    if path=='/client/join'then
        if body.code~='L2G-INVITE-ONLY'then return nil,'Invalid fixture invitation',400 end
        gateway.revision=gateway.revision+1;gateway.connections[client..'-connection']=client
        gateway.room.members[#gateway.room.members+1]={id=client,name=body.name,bot=false,connected=true,ready=false};return envelope(client)
    end
    local connection,suffix=path:match('^/client/rooms/([^/]+)(.*)$');local id=gateway.connections[connection]
    if not id then return nil,'Unknown fixture connection',404 end
    if method=='GET'then return envelope(id)end
    gateway.revision=gateway.revision+1
    if suffix=='/bots'then
        local humans={};for _,p in ipairs(gateway.room.members)do if not p.bot then humans[#humans+1]=p end end;gateway.room.members=humans
        for i=1,body.count do gateway.room.members[#gateway.room.members+1]={id='bot'..i,name='XMage Bot '..i,bot=true,connected=true,ready=true}end
    elseif suffix=='/ready'then member(id).ready=body.ready
    elseif suffix=='/start'then
        if not canStart()then return nil,'Fixture seats are not ready',409 end
        if gateway.room.phase=='building'then gateway.room.phase='playing'
        else
            gateway.room.phase='drafting';gateway.drafts={}
            for _,p in ipairs(gateway.room.members)do if not p.bot then
                gateway.drafts[p.id]={id='SYNTHETIC-PRIVATE-DRAFT',revision=1,status='drafting',packNumber=1,pickNumber=1,packCount=3,pickToken=p.id..'-pick-token',secondsRemaining=45,players=clone(gateway.room.members),pack={{id=p.id..'-offered',name=p.id..' pack card',type='Creature',power='2',toughness='2'}},pool={}}
            end end
        end
    elseif suffix=='/draft/pick'then
        local d=gateway.drafts[id]
        if body.pickToken~=d.pickToken or body.cardId~=d.pack[1].id then return nil,'Stale fixture pick',409 end
        d.pool={d.pack[1],{id=id..'-extra',name=id..' drafted extra',type='Instant'}};d.pack={};d.pickToken=nil;d.revision=d.revision+1
        local all=true;for _,draft in pairs(gateway.drafts)do if #draft.pool==0 then all=false end end
        if all then gateway.room.phase='building';for _,draft in pairs(gateway.drafts)do draft.status='building';draft.revision=draft.revision+1 end;for _,p in ipairs(gateway.room.members)do if not p.bot then p.ready=false end end end
    elseif suffix=='/draft/deck'then
        local count=#body.main;for _,n in pairs(body.basics)do count=count+n end
        if count<40 then return nil,'Fixture native validator needs 40 cards',422 end
        gateway.drafts[id].status='ready';gateway.drafts[id].deck=clone(body);member(id).ready=true
    elseif suffix=='/leave'then
        if id==gateway.room.hostId then gateway.room.phase='closed'end
        gateway.connections[connection]=nil;return {left=true}
    else return nil,'Unknown fixture operation',404 end
    return envelope(id)
end
local clientNumber=0
package.preload['app.api']=function()
    local API={};function API.escape(s)return tostring(s):gsub('([^%w%-_%.~])',function(c)return string.format('%%%02X',c:byte())end)end
    function API.new()
        clientNumber=clientNumber+1;local name=clientNumber==1 and'Host'or'Guest';local self={jobs={},name=name,catalogPort=17499}
        function self:request(service,method,path,body,callback)
            self.jobs[#self.jobs+1]={service=service,method=method,path=path,body=body,callback=callback};return #self.jobs
        end
        function self:update()
            local jobs=self.jobs;self.jobs={}
            for _,job in ipairs(jobs)do
                local data,err,code
                if job.service=='room'then data,err,code=handle(self.name,job.method,job.path,job.body)
                else data={}end
                if job.callback then job.callback(data,err,code or 200)end
            end
        end
        function self:setRoomSession(route)self.route=route and route.connectionId or nil end
        function self:quit()self:update()end
        return self
    end
    return API
end
local S=require('lib.Slab');local Model=require('app.model');require('app.rooms').install(Model)
local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local RoomUI=require('app.room_ui');local DraftUI=require('app.draft_ui')
local clients,active,runner,Cursor,Region
local mouse={x=0,y=0};local down=false;local keys={};local buttons,controls,selections={},{},{}
local clock,wake=0,0;local checks={};local shots={}
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('ROOM/DRAFT UI PASS '..label)end
local function wait(t)wake=clock+(t or .08);coroutine.yield()end
local function ready(fn,label)local deadline=clock+10;while not fn()do assert(clock<deadline,label);wait(.06)end end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x=x*Layout.scale;mouse.y=y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy)end
local function click(box)
    assert(box,'Missing fixture control');move(box.x+box.w/2,box.y+box.h/2);wait(.04);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.04);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.12)
end
local function choose(id,label)
    click(controls[id]);ready(function()return selections[label]end,'Dropdown did not show '..label);click(selections[label])
end
local function switch(index)active=clients[index];move(2,2);wait(.15)end
local function number(label,text)
    click(controls[label]);keys.lctrl=true;S.OnKeyPressed('a','a',false);S.OnKeyReleased('a','a');keys={};wait(.06);S.OnTextInput(text);wait(.12)
end
local function shot(name)shots[#shots+1]=name;wait(.12)end
local function scenario()
    for _,client in ipairs(clients)do client.m:showRooms()end
    ready(function()return clients[1].m.roomCapabilities and clients[2].m.roomCapabilities end,'Capabilities did not load')
    click(buttons.Draft);check(active.m.roomSetup.kind=='draft','Actual draft mode button selects a native draft table')
    choose('room-draft-mode','Random draft');check(active.m.roomSetup.draft.mode=='random','Native random draft is available through the mode picker')
    check(#active.m.roomSetup.draft.randomSets==0,'Random draft initially permits all supported booster sets')
    move(150,450);wait(.06);S.OnWheelMoved(0,-100);wait(.18)
    number('room-random-set-search','two');choose('room-random-set','Fixture set two');click(buttons['Add set'])
    check(#active.m.roomSetup.draft.randomSets==1 and active.m.roomSetup.draft.randomSets[1]=='two','Actual search, native set picker and Add select the eligible random pool')
    check(buttons['Add set'].disabled,'An already selected set cannot be added twice')
    number('room-random-set-search','');choose('room-random-set','Fixture set one');click(buttons['Add set'])
    check(table.concat(active.m.roomSetup.draft.randomSets,',')=='two,one','Multiple eligible native sets retain their explicit selection order')
    click(buttons['Remove Fixture set two']);click(buttons['Remove Fixture set one'])
    check(json.encode(active.m.roomSetup.draft.randomSets)=='[]','Actual remove controls restore the all-supported booster pool')
    shot('random-all-supported')
    choose('room-random-set','Fixture set two');click(buttons['Add set']);shot('random-pool-options')
    move(150,450);wait(.06);S.OnWheelMoved(0,100);wait(.18)
    choose('room-draft-mode','Cube draft');choose('room-cube','Fixture cube two');check(active.m.roomSetup.draft.cubeId=='CubeTwo','Native cube picker preserves the selected cube ID')
    shot('cube-options');choose('room-draft-mode','Booster draft')
    move(150,450);wait(.06);S.OnWheelMoved(0,-100);wait(.18)
    choose('room-pack-2','Fixture set two');check(active.m.roomSetup.draft.sets[2]=='two','Actual per-pack set picker preserves the second booster choice')
    shot('traditional-options');move(150,450);wait(.06);S.OnWheelMoved(0,100);wait(.18);choose('room-draft-mode','Random draft')
    check(active.m.roomSetup.draft.randomSets[1]=='two'and active.m.roomSetup.draft.sets[2]=='two','Actual mode changes preserve independent traditional packs and random eligible sets')
    click(buttons['Create invite room'])
    ready(function()return active.m.room end,'Host room did not open');check(active.m.roomParticipantId=='Host','Actual create button receives the host membership')
    local config=active.m.room.config.draft;check(config.mode=='random'and json.encode(config.randomSets)=='["two"]','Actual room creation submits the explicit random booster pool')
    click(buttons['Copy code']);check(love.system.getClipboardText()=='L2G-INVITE-ONLY','Copy button copies only the shared invitation code')
    switch(2);click(buttons['Paste code']);check(active.m.roomInviteInput=='L2G-INVITE-ONLY','Second frontend pastes the invitation into one code field')
    click(buttons['Join room']);ready(function()return active.m.room end,'Guest room did not open');check(active.m.roomParticipantId=='Guest','Actual join button creates a separate guest membership')
    click(buttons.Ready);switch(1)
    click(buttons['Add bot']);click(buttons['Add bot']);click(buttons.Ready)
    ready(function()return active.m.room.canStart end,'Both humans and bot seats did not become ready');check(#active.m.room.members==4,'Host adds two optional bot seats through actual controls')
    shot('two-clients-ready');click(buttons['Start draft'])
    ready(function()return active.m.roomDraft and active.m.roomDraft.status=='drafting'end,'Draft pack did not open')
    check(active.m.roomDraft.pack[1].name=='Host pack card','Host sees its own personalized pack')
    shot('host-pack');click(buttons['Host pack card · right-click to inspect'])
    switch(2);ready(function()return active.m.roomDraft and active.m.roomDraft.status=='drafting'end,'Guest pack did not open')
    check(active.m.roomDraft.pack[1].name=='Guest pack card','Second client sees a different private pack')
    click(buttons['Guest pack card · right-click to inspect'])
    ready(function()return active.m.roomDraft.status=='building'end,'Native building projection did not open')
    for _,index in ipairs({1,2})do
        switch(index);ready(function()return active.m.roomDraft and active.m.roomDraft.status=='building'end,'Builder did not load')
        local name=index==1 and'Host'or'Guest'
        click(buttons[name..' pack card · right-click to inspect']);check(DraftUI.deckCount(active.m.roomDraftDeck)==1,'Actual pool card click adds one owned instance · '..name)
        number('Number of Plains','39');check(active.m.roomDraftDeck.basics.Plains==39 and DraftUI.deckCount(active.m.roomDraftDeck)==40,'Actual basic-land numeric input builds a forty-card local list · '..name)
        shot(name:lower()..'-builder');click(buttons['Submit deck']);ready(function()return active.m.roomDraft.status=='ready'end,'Submitted fixture deck did not become ready')
        check(active.m.roomDraftDeck.mainIds[name..'-offered'],'Submitted deck retains the exact selected pool instance · '..name)
        number('Number of Plains','40');check(active.m.roomDraftDeck.dirty and buttons['Submit changes'],'Ready native-profile decks remain editable before the first round · '..name)
        click(buttons['Submit changes']);ready(function()return not active.m.roomBusy and not active.m.roomDraftDeck.dirty end,'Ready deck changes were not acknowledged')
        number('Number of Plains','39');click(buttons['Submit changes']);ready(function()return not active.m.roomBusy and not active.m.roomDraftDeck.dirty end,'Final ready deck changes were not acknowledged')
        check(active.m.roomDraftDeck.basics.Plains==39,'Actual ready-deck re-submit preserves the intended final quantities · '..name)
    end
    switch(1);ready(function()return active.m.room.canStart end,'Ready draft decks did not enable the first round')
    click(buttons['Start round']);ready(function()return active.m.game and active.m.page=='table'end,'First drafted round did not route to gameplay')
    check(active.m.api.route=='Host-connection','Host gameplay uses its authenticated room connection')
    ready(function()return clients[2].m.game end,'Guest game projection did not load')
    local guest=clients[2].m
    for _,p in ipairs(guest.game.players)do if p.id~='Guest'then check(#p.hand==0,'Guest projection hides the hand of '..p.name)end end
    active.m:showRooms();wait(.15);click(buttons['Close room']);ready(function()return not active.m.roomConnectionId end,'Host close did not clear its connection')
    ready(function()return guest.room and guest.room.phase=='closed'end,'Guest did not observe host close');check(guest.game==nil and guest.api.route==nil,'Closing a room removes stale guest gameplay and authentication routing')
    switch(2);click(buttons['Leave room']);ready(function()return not active.m.roomConnectionId end,'Guest could not leave closed room')
    for _,c in ipairs(clients)do c.m.settings.resolution='1120x720';c.m.settings.uiScale=1.25;c.p:apply(true)end
    wait(.2);local _,h=Layout.dimensions()
    check(buttons['Create invite room'].y+buttons['Create invite room'].h<=h and buttons['Join room'].y+buttons['Join room'].h<=h,'Create/join controls remain reachable in the smallest supported window')
    shot('1120-invite-only')
    switch(1);move(150,450);wait(.06);S.OnWheelMoved(0,-100);wait(.18)
    check(controls['room-random-set-search'].y>=215 and buttons['Add set'].y+buttons['Add set'].h<h-100,'Random pool search and Add controls remain visible after scrolling the smallest window')
    number('room-random-set-search','one');choose('room-random-set','Fixture set one');click(buttons['Add set'])
    check(table.concat(active.m.roomSetup.draft.randomSets,',')=='two,one','Random pool search, native choice and Add remain interactive in the smallest supported window')
    shot('1120-random-pool')
    for _,call in ipairs(gateway.calls)do assert(call.path~='/rooms'and call.path~='/client/rooms/list','No room discovery request is allowed')end
    check(true,'Two-client workflow never requests a public room browser')
    local output=assert(io.open('/tmp/love2gathering-room-draft-ui-report.json','w'));output:write(json.encode({passed=true,scope='Two independent frontend models; actual LÖVE/Slab input; synthetic room gateway and private native projections; no native/network drafting claim',checks=checks,calls=gateway.calls,physical={love.graphics.getDimensions()},logical={Layout.dimensions()}}));output:close()
    print('ROOM/DRAFT UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
    originalClipboard=love.system.getClipboardText();S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(b)return b==1 and down or false end
    love.keyboard.isScancodeDown=function(...)for _,key in ipairs({...})do if keys[key]then return true end end;return false end
    clients={}
    for index,name in ipairs({'Host','Guest'})do
        local m=Model.new();m.playerName=name;m.format='Commander';m.settingsLoaded=true;m.catalogHealth={ready=false};m.settings.showCardArt=false;m.settings.sfxEnabled=false;m.settings.vsync=false;m.settings.animations=false;m.settings.particles=false;m.uiLayout={}
        local r=Renderer.new(m);local v=View.new(S,m,r);local p=Preferences.new(m,S,r);v.preferences=p;p.appliedLoaded=true
        local original=v.window;v.window=function(self,id,...)return original(self,name..':'..id,...)end
        clients[index]={m=m,r=r,v=v,p=p}
    end
    active=clients[1];active.p:apply(true)
    for _,name in ipairs({'Button','Input','BeginComboBox','TextSelectable'})do
        local original=S[name];S[name]=function(id,options)
            local dx,dy=Region.Transform(nil,0,0);local result=original(id,options);local x,y,w,h=Cursor.GetItemBounds()
            local target=name=='Button'and buttons or name=='TextSelectable'and selections or controls
            target[(options and options.Tooltip)or id]={x=x+dx,y=y+dy,w=w,h=h,disabled=options and options.Disabled};target[id]=target[id]or target[(options and options.Tooltip)or id]
            if name=='Button'and options and options.Tooltip then target[options.Tooltip:match('^[^\n]+')]=target[options.Tooltip]end
            return result
        end
    end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    clock=clock+dt;assert(clock<120,'Room/draft UI acceptance exceeded 120 seconds')
    for _,c in ipairs(clients)do c.m.api:update();c.m:updateRooms(dt);c.r:update(dt)end
    active.p:update();S.Update(dt)
    if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
    buttons,controls,selections={},{},{}
    S.PushFont(active.r.fonts[16]);local w,h=Layout.dimensions()
    if active.m.page=='draft'then DraftUI.build(active.v,w,h)
    elseif active.m.page=='rooms'then RoomUI.build(active.v,w,h)end
    active.v:modals(w,h);S.PopFont()
end
function love.draw()
    active.p:beginFrame();active.r:draw();active.p:endScene();S.Draw()
    if #shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)local output=assert(io.open('/tmp/love2gathering-room-draft-'..name..'.png','wb'));output:write(data:encode('png'):getString());output:close()end)end
end
function love.quit()if originalClipboard then love.system.setClipboardText(originalClipboard)end;S.OnQuit()end
