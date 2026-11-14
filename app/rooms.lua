-- Invite-only room coordination. The local gateway owns invite decoding,
-- remote credentials, membership and per-seat native game/draft projections.
local API=require('app.api')
local json=require('lib.json')
local Rooms={}
local function copy(value)return json.decode(json.encode(value))end
local function value(item)return type(item)=='table'and(item.id or item.code or item.value)or item end
local function choose(items,current)
    for _,item in ipairs(items or {})do if value(item)==current then return current end end
    return items and items[1]and value(items[1])or nil
end
local function find(items,id)
    for _,item in ipairs(items or {})do if value(item)==id then return item end end
end
local function init(m)
    m.roomSetup=m.roomSetup or {name='Friends table',playerName=m.playerName or 'Planeswalker',kind='constructed',format=m.format or 'Commander',maxPlayers=4,draft={sets=json.array(),randomSets=json.array()}}
    m.roomInviteInput=m.roomInviteInput or '';m.roomPollTimer=m.roomPollTimer or 0;m.roomGeneration=m.roomGeneration or 0
end
local function path(m,suffix)return '/client/rooms/'..API.escape(m.roomConnectionId)..(suffix or '')end
local function validation(data)
    if type(data)~='table'then return nil end
    return data.validation or data.errors or data.error
end
function Rooms.fitSetup(m)
    init(m);local caps=m.roomCapabilities or {};local game=caps.game or {};local draft=caps.draft or {};local setup=m.roomSetup
    if not m.roomCapabilities then m.roomSetupMinPlayers=2;m.roomSetupMaxPlayers=math.max(4,setup.maxPlayers or 4);return end
    setup.format=choose(game.formats,setup.format)or setup.format
    setup.draft=setup.draft or {sets=json.array(),randomSets=json.array()};local d=setup.draft
    d.mode=choose(draft.modes,d.mode);d.profile=choose(draft.profiles,d.profile);d.pairing=choose(draft.pairings,d.pairing);d.timing=choose(draft.timings,d.timing)
    d.cubeId=choose(draft.cubes,d.cubeId)
    local mode=find(draft.modes,d.mode)or {};local format=find(game.formats,setup.format)or {}
    local minimum=setup.kind=='draft'and(mode.minPlayers or draft.minPlayers or 4)or(type(format)=='table'and format.minPlayers or game.minPlayers or 2)
    local maximum=setup.kind=='draft'and(mode.maxPlayers or draft.maxPlayers or minimum)or(type(format)=='table'and format.maxPlayers or game.maxPlayers or minimum)
    setup.maxPlayers=math.max(minimum,math.min(maximum,tonumber(setup.maxPlayers)or minimum))
    d.sets=json.array(d.sets or {})
    for i=1,(mode.packCount or draft.packCount or 3)do d.sets[i]=choose(draft.sets,d.sets[i])end
    -- An empty random pool means all native booster sets. Never derive it
    -- from the traditional pack choices, which remain available on mode changes.
    local pool,seen=json.array(),{}
    for _,code in ipairs(d.randomSets or {})do
        if find(draft.sets,code)and not seen[code]then pool[#pool+1]=code;seen[code]=true end
    end
    d.randomSets=pool
    m.roomSetupMinPlayers,m.roomSetupMaxPlayers=minimum,maximum
end
function Rooms.setRandomSet(m,code,included)
    Rooms.fitSetup(m)
    local pool=m.roomSetup.draft.randomSets
    if not find((m.roomCapabilities or {}).draft and m.roomCapabilities.draft.sets,code)then return false end
    for index,selected in ipairs(pool)do if selected==code then
        if included then return false end
        table.remove(pool,index);return true
    end end
    if not included then return false end
    pool[#pool+1]=code;return true
end
local function draftIdentity(draft)
    return draft and tostring(draft.id or '')..':'..tostring(draft.status or '')or nil
end
local function tournamentRole(draft,id)
    local tournament=draft and draft.tournament
    if not tournament then return nil end
    for _,standing in ipairs(tournament.standings or {})do if standing.seatId==id and standing.eliminated then return 'eliminated'end end
    for _,match in ipairs(tournament.matches or {})do if match.bye then for _,seat in ipairs(match.seatIds or {})do if seat==id then return 'bye'end end end end
end
local function ownedGame(m,game)
    return game and game.gameId and m.roomOwnedGameIds and m.roomOwnedGameIds[game.gameId]
end
local function clearRoomLive(m)
    if m.replay then
        if m.roomGameActive or ownedGame(m,m.liveGame)then m.liveGame=nil end
    elseif m.roomGameActive or ownedGame(m,m.game)then m.game=nil end
    m.polling=false;m.actionBusy=false;m.priorityBusy=false
end
function Rooms.install(Model)
    if Model.roomsInstalled then return end
    Model.roomsInstalled=true
    local originalQuit=Model.quit
    function Model:quit()
        if self.roomConnectionId and not self.roomLeaveQueued then self.api:request('room','POST',path(self,'/leave'),{},function()end)end
        if originalQuit then return originalQuit(self)end
    end
    function Model:showRooms()
        init(self);if self.replay then self.replay.playing=false end
        self.page='rooms'
        if not self.roomCapabilities then self:refreshRoomCapabilities()end
        if self.roomConnectionId then self.roomPollTimer=0 end
    end
    function Model:refreshRoomCapabilities()
        init(self);self.roomCapabilitiesVersion=(self.roomCapabilitiesVersion or 0)+1;local version=self.roomCapabilitiesVersion
        self.roomCapabilitiesBusy=true
        self:request('room','GET','/client/capabilities',nil,function(data,err)
            if version~=self.roomCapabilitiesVersion then return end
            self.roomCapabilitiesBusy=false
            if data then self.roomCapabilities=data;self.roomCapabilityError=nil;Rooms.fitSetup(self)
            else self.roomCapabilityError=err or 'Room capabilities are unavailable'end
        end,true)
    end
    function Model:applyRoomSnapshot(data,generation,sequence)
        if not data or generation~=self.roomGeneration or sequence<(self.roomResponseFence or 0)or sequence<(self.roomAppliedResponse or 0)then return false end
        if not data.room then return false end
        local previous=self.room;local incoming=data.room
        if previous and previous.id==incoming.id and incoming.revision and previous.revision and incoming.revision<previous.revision then return false end
        self.roomAppliedResponse=sequence
        if data.connectionId then self.roomConnectionId=data.connectionId end
        self.roomParticipantId=data.participantId or self.roomParticipantId
        self.room=incoming;self.roomError=nil;self.roomDisconnected=false
        if data.capabilities then self.roomCapabilities=data.capabilities end
        local oldDraft=self.roomDraft;local draft=data.draft
        if oldDraft and draft and oldDraft.id==draft.id and oldDraft.revision and draft.revision and draft.revision<oldDraft.revision then draft=oldDraft end
        self.roomDraft=draft
        local deck=self.roomDraftDeck;local empty=deck and not next(deck.mainIds or {})
        if empty then for _,count in pairs(deck.basics or {})do if count>0 then empty=false;break end end end
        if draft and(draft.status=='building'or draft.status=='ready'or draft.status=='competing'or draft.status=='completed')and(not deck or deck.draftId~=draft.id or(empty and not deck.dirty and draft.selection))then
            self.roomDraftDeck={draftId=draft.id,mainIds={},basics={},dirty=false}
            local saved=draft.selection or draft.deck or {}
            for _,id in ipairs(saved.main or {})do local selected=type(id)=='table'and id.id or id;if selected then self.roomDraftDeck.mainIds[tostring(selected)]=true end end
            if type(saved.basics)=='table'and#saved.basics>0 then for _,entry in ipairs(saved.basics)do self.roomDraftDeck.basics[entry.name]=entry.count end
            else for name,count in pairs(saved.basics or {})do self.roomDraftDeck.basics[name]=count end end
        end
        if draft and draftIdentity(draft)~=self.roomDraftStage then
            self.roomDraftStage=draftIdentity(draft)
            if draft.status=='drafting'or draft.status=='building'or draft.status=='ready'then self.page='draft'end
        end
        if data.game and incoming.phase=='playing'then
            self.roomOwnedGameIds=self.roomOwnedGameIds or {};self.roomOwnedGameIds[data.game.gameId]=true
            local live=self.replay and self.liveGame or self.game
            local first=not self.roomGameActive or not live or live.gameId~=data.game.gameId
            if first and self.replay and self.closeReplay then self:closeReplay()end
            if self.roomRoutedConnection~=self.roomConnectionId or self.roomRoutedGameId~=data.game.gameId then
                if self.api.setRoomSession then self.api:setRoomSession({connectionId=self.roomConnectionId,gameId=data.game.gameId})end
                self.roomRoutedConnection=self.roomConnectionId;self.roomRoutedGameId=data.game.gameId
            end
            self.roomGameActive=true
            self:setGame(data.game)
            if first then self.page='table'end
        elseif data.game and self.roomGameActive then self:setGame(data.game)end
        local role=tournamentRole(draft,self.roomParticipantId)
        if(incoming.phase=='playing'and not data.game)or incoming.phase=='completed'then
            local navigate=self.roomGameActive or self.page=='table'or self.roomPhaseLast~=incoming.phase
            if incoming.phase=='completed'then self.roomCompletedGame=data.game or(self.replay and self.liveGame or self.game)end
            clearRoomLive(self)
            if self.api.setRoomSession then self.api:setRoomSession(nil)end
            self.roomGameActive=false;self.roomRoutedConnection=nil;self.roomRoutedGameId=nil
            if navigate and not self.replay then self.page='rooms'end
        end
        self.roomTournamentRole=role
        if incoming.phase=='closed'or incoming.phase=='failed'then
            if self.api.setRoomSession then self.api:setRoomSession(nil)end
            clearRoomLive(self)
            self.roomGameActive=false;self.roomRoutedConnection=nil;self.roomRoutedGameId=nil;self.roomError=incoming.error or incoming.message or 'This room is closed'
            if not self.replay then self.page='rooms'end
        end
        self.roomPhaseLast=incoming.phase
        return true
    end
    function Model:roomRequest(method,suffix,body,mutation,callback)
        if not self.roomConnectionId then return false end
        local generation=self.roomGeneration;self.roomRequestSequence=(self.roomRequestSequence or 0)+1;local sequence=self.roomRequestSequence
        if mutation then self.roomResponseFence=sequence end
        self:request('room',method,path(self,suffix),body,function(data,err,details)
            if generation~=self.roomGeneration then return end
            if data then self:applyRoomSnapshot(data,generation,sequence)
            elseif sequence>=(self.roomResponseFence or 0)then self.roomError=err or 'Room request failed';self.roomDisconnected=method=='GET'or self.roomDisconnected end
            if callback then callback(data,err,details)end
        end,true)
        return true
    end
    function Model:connectRoom(join,config)
        init(self);if self.roomBusy or self.roomConnectionId then return false end
        config=copy(config);config.settings=copy(self.settings or {})
        if self.profileOptions then
            config.profile=self:profileOptions()
            config.profile.name=config.playerName or config.name or config.profile.name
        end
        if self.priorityOptions then config.priority=self:priorityOptions()end
        self.roomGeneration=self.roomGeneration+1;local generation=self.roomGeneration
        self.roomRequestSequence=1;self.roomResponseFence=1;self.roomAppliedResponse=0;self.roomBusy=true;self.roomError=nil
        self:request('room','POST',join and '/client/join'or '/client/rooms',config,function(data,err)
            if generation~=self.roomGeneration then return end
            self.roomBusy=false
            if data and data.connectionId then self:applyRoomSnapshot(data,generation,1);self.roomPollTimer=0
            else self.roomError=err or 'Could not connect to the room'end
        end,true)
        return true
    end
    function Model:hostRoom()
        if self.storageLocationBlocked then self:toast('Restart or cancel the storage location change before hosting a room.',true);return false end
        init(self);Rooms.fitSetup(self)
        return self:connectRoom(false,copy(self.roomSetup))
    end
    function Model:joinRoom(code)
        init(self);code=tostring(code or self.roomInviteInput):match('^%s*(.-)%s*$')
        if #code<1 or #code>2048 then self.roomError='Enter a valid invitation code';return false end
        self.roomInviteInput=code
        return self:connectRoom(true,{code=code,name=self.roomSetup.playerName})
    end
    function Model:rejoinRoom()
        if not self.roomConnectionId then return false end
        self.roomGeneration=self.roomGeneration+1;self.roomPolling=false;self.roomBusy=false;self.roomDisconnected=false;self.roomPollTimer=0
        return self:refreshRoom()
    end
    function Model:refreshRoom()
        if not self.roomConnectionId or self.roomPolling then return false end
        self.roomPolling=true
        return self:roomRequest('GET','',nil,false,function()self.roomPolling=false end)
    end
    function Model:roomMutation(suffix,body,callback)
        if self.roomBusy or not self.roomConnectionId then return false end
        self.roomBusy=true
        return self:roomRequest('POST',suffix,body or {},true,function(data,err,details)
            self.roomBusy=false;self.roomPollTimer=0
            if callback then callback(data,err,details)end
        end)
    end
    function Model:setRoomReady(ready)return self:roomMutation('/ready',{ready=ready==true})end
    function Model:selectRoomDeck(id)
        local deck=self:findDeck(id);if not deck then return false end
        self.roomDeckId=id
        return self:roomMutation('/deck',{deck=copy(deck)})
    end
    function Model:setRoomBots(count)return self:roomMutation('/bots',{count=math.max(0,math.floor(tonumber(count)or 0))})end
    function Model:startRoom()if self.storageLocationBlocked then self:toast('Restart or cancel the storage location change before starting a match.',true);return false end;return self:roomMutation('/start',{})end
    function Model:nextRoomRound()return self:roomMutation('/next-round',{})end
    function Model:leaveRoom()
        if self.roomBusy or not self.roomConnectionId then return false end
        local wasGame=self.roomGameActive or ownedGame(self,self.replay and self.liveGame or self.game)
        if self.replay and self.closeReplay then self:closeReplay()end
        local invite=self.room and self.room.inviteCode;self.roomLeaveQueued=true
        return self:roomMutation('/leave',{},function(data)
            self.roomLeaveQueued=false
            if not data then return end
            self.roomLastCode=invite or self.roomLastCode
            self.roomGeneration=self.roomGeneration+1
            if self.api.setRoomSession then self.api:setRoomSession(nil)end
            self.room=nil;self.roomDraft=nil;self.roomDraftDeck=nil;self.roomDraftStage=nil;self.roomConnectionId=nil;self.roomParticipantId=nil
            self.roomPolling=false;self.roomBusy=false;self.roomError=nil;self.roomGameActive=false;self.roomRoutedConnection=nil;self.roomRoutedGameId=nil;self.page='rooms'
            self.roomOwnedGameIds=nil;self.roomCompletedGame=nil;self.roomPhaseLast=nil;self.roomTournamentRole=nil
            if wasGame then self.game=nil;self.polling=false;self.pollTimer=0 end
        end)
    end
    function Model:copyRoomCode()
        local code=self.room and self.room.inviteCode
        if not code or not love.system or not love.system.setClipboardText then return false end
        love.system.setClipboardText(code);self:toast('Invitation code copied');return true
    end
    function Model:pickDraftCard(id)
        local draft=self.roomDraft
        if not draft or draft.status~='drafting'or not draft.pickToken then return false end
        local found=false;for _,card in ipairs(draft.pack or {})do if tostring(card.id)==tostring(id)then found=true;break end end
        if not found then return false end
        return self:roomMutation('/draft/pick',{pickToken=draft.pickToken,cardId=id})
    end
    function Model:setDraftCard(id,selected)
        local draft,deck=self.roomDraft,self.roomDraftDeck
        if not draft or not deck or self.roomBusy or(draft.status~='building'and draft.status~='ready')then return false end
        for _,card in ipairs(draft.pool or {})do if tostring(card.id)==tostring(id)then
            deck.mainIds[tostring(id)]=selected and true or nil;deck.dirty=true;self.roomDraftValidation=nil;return true
        end end
        return false
    end
    function Model:setDraftBasic(name,count)
        local draft,deck=self.roomDraft,self.roomDraftDeck
        if not draft or not deck or self.roomBusy or(draft.status~='building'and draft.status~='ready')then return false end
        local basics=draft.basicLands or((self.roomCapabilities or {}).draft or {}).basicLands or {}
        for _,land in ipairs(basics)do if(type(land)=='table'and land.name or land)==name then
            count=tonumber(count);if not count or count%1~=0 or count<0 or count>250 then return false end
            deck.basics[name]=count;deck.dirty=true;self.roomDraftValidation=nil;return true
        end end
        return false
    end
    function Model:submitDraftDeck()
        local draft,deck=self.roomDraft,self.roomDraftDeck
        if not draft or not deck or(draft.status~='building'and draft.status~='ready')then return false end
        local main=json.array();for _,card in ipairs(draft.pool or {})do if deck.mainIds[tostring(card.id)]then main[#main+1]=card.id end end
        local basics={};for name,count in pairs(deck.basics)do if count>0 then basics[name]=count end end
        return self:roomMutation('/draft/deck',{main=main,basics=basics},function(data,err,details)
            if data then deck.dirty=false;self.roomDraftValidation=nil
            else self.roomDraftValidation=validation(details)or err end
        end)
    end
    function Model:updateRooms(dt)
        if not self.roomConnectionId then return end
        self.roomPollTimer=(self.roomPollTimer or 0)-dt
        if self.roomPollTimer<=0 and not self.roomPolling then self.roomPollTimer=.6;self:refreshRoom()end
    end
end
return Rooms
