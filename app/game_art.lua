-- Bounded per-match warmup. Only the entitled hand and the local submitted
-- deck enter this queue; opponent libraries and hidden identities never do.
local API=require('app.api')
local GameArt={basics={'Plains','Island','Swamp','Mountain','Forest','Wastes'}}
local function now()return love.timer.getTime()end
local function localPlayer(game)
    local humans,only,explicit=0,nil,false
    for _,p in ipairs(game.players or{})do
        if game.localPlayerId and p.id==game.localPlayerId or p.isLocal==true then return p end
        if p.isLocal~=nil then explicit=true end
        if p.human then humans=humans+1;only=p end
    end
    if not game.localPlayerId and not explicit and humans==1 then return only end
end
local function identity(card)
    return tostring(card.selectedPrintingId or card.printing_id or card.name)..':'..tostring(card.requested_face or card.name)
end
local function scope(m,game,player)
    if not game or not player then return end
    return table.concat({tostring(game.gameId),tostring(player.id),tostring(m.roomConnectionId or''),tostring(m.roomGeneration or 0),tostring(m.api and m.api.routeGeneration or 0)},'|')
end
local function allowed(card)return type(card)=='table'and card.name and not card.hidden and not card.faceDown and not(card.token or card.isToken)end
local function submittedDeck(m)
    if not m.roomConnectionId and m.lastMatchRequest and m.lastMatchRequest.deck then return m.lastMatchRequest.deck end
    local id=m.roomConnectionId and m.roomDeckId or m.activeDeckId or m.lastMatchDeckId
    return id and m.findDeck and m:findDeck(id)or nil
end
local function entry(state,card)
    if not allowed(card)then return end
    local key=identity(card);local item=state.entries[key]
    if not item then
        if state.count>=512 then return end
        item={card=card,key=key,kinds={}};state.entries[key]=item;state.count=state.count+1
    end
    return item
end
local function printingFace(card,printed)
    if card.name==printed.name then return card.requested_face or printed.requested_face or 0 end
    for index,face in ipairs(printed.card_faces or{})do
        if face.name==card.name then return card.requested_face or index-1 end
    end
end
function GameArt.install(Model)
    function Model:updateGameArtwork()
        local game=self.game
        if self.replay or self.storageLocationBlocked or not game or not game.gameId or game.running==false then self.gameArtWarmup=nil;self.gameArtwork=nil;return end
        local player=localPlayer(game);if not player then self.gameArtWarmup=nil;self.gameArtwork=nil;return end
        local state=self.gameArtWarmup
        local key=scope(self,game,player)
        if not state or state.scope~=key then
            self.gameArtGeneration=(self.gameArtGeneration or 0)+1
            state={id=game.gameId,scope=key,token=self.gameArtGeneration,entries={},count=0,background={},index=1};self.gameArtWarmup=state
        end
        local function current()return not self.replay and not self.storageLocationBlocked and self.gameArtWarmup==state and self.game and self.game.running~=false and scope(self,self.game,localPlayer(self.game))==state.scope end
        local function resolve(item,hand)
            if item.data then return item.data end
            if item.metadataPending or(item.retryAt or 0)>now()then return end
            local card=item.card;local printing=card.selectedPrintingId or card.printing_id
            if card.image_uris and(not printing or card.printing_id==printing)then item.data=card;return card end
            local cached=printing and self.printingMetadata and self.printingMetadata[printing]
            if cached and cached.card and printingFace(card,cached.card)~=nil then
                item.data=cached.card;return item.data
            end
            if not printing and self.byName[card.name]then item.data=self.byName[card.name];return item.data end
            -- One hand metadata request and one background request at most.
            if state.metadataPending then return end
            item.metadataPending=true;item.failed=nil;state.metadataPending=true
            local path=printing and'/cards/'..API.escape(printing)..'?printing='..API.escape(printing)or'/cards/by-name?name='..API.escape(card.name)
            self.api:request('catalog','GET',path,nil,function(value,err,code)
                item.metadataPending=false;state.metadataPending=false
                if not current()then return end
                value=value and(value.card or value)
                if not err and code==200 and value and printingFace(card,value)~=nil then
                    item.data=value
                    if not printing then self:rememberCard(value,card.name)
                    else
                        self.printingMetadata=self.printingMetadata or{}
                        self.printingMetadata[printing]={card=value}
                        local count=0;for _ in pairs(self.printingMetadata)do count=count+1 end
                        if count>128 then for id,cached in pairs(self.printingMetadata)do if id~=printing and not cached.pending then self.printingMetadata[id]=nil;break end end end
                    end
                else item.retryAt=now()+30;item.failed=true end
            end,false,{priority=hand and'handMetadata'or nil,selectionToken=hand and('hand-metadata:'..state.token..':'..item.key)or nil,isCurrent=current})
        end
        local function exact(item,data)
            local card={};for key,value in pairs(data)do card[key]=value end
            card.requested_face=printingFace(item.card,data)
            card.printingExact=item.card.printingExact or item.card.selectedPrintingId~=nil;card.printingResolved=true
            return card
        end
        local hands,seen={},{}
        for _,card in ipairs(player.hand or{})do
            if allowed(card)then
                if not card.selectedPrintingId and self.cardPrintingSelection and submittedDeck(self)then
                    local choice=self:cardPrintingSelection(card,nil,submittedDeck(self))
                    if choice then local selected={};for key,value in pairs(card)do selected[key]=value end;selected.selectedPrintingId=choice.printingId;card=selected end
                end
                -- Exact native printing selections take precedence over names.
                local item=entry(state,card)
                if item and not seen[item.key]then hands[#hands+1]=item;seen[item.key]=true end
            end
        end
        local ready,pending=0,0
        for _,item in ipairs(hands)do
            local data=resolve(item,true)
            if data then
                local image,status=self:getArt(exact(item,data),true,'normal',{priority='hand',network=true,selectionToken='hand:'..state.token..':'..item.key,isCurrent=current})
                if image then ready=ready+1;item.kinds.normal=true
                elseif status~='error'and status~='missing'then pending=pending+1 end
            elseif not item.failed then pending=pending+1 end
        end
        self.gameArtwork={handTotal=#hands,handReady=ready,handPending=pending,phase=pending>0 and'hand'or'deck',completed=state.completed or 0,total=#state.background}
        if pending>0 or state.downloadPending or not self.catalogHealth.ready then return end
        if not state.prepared then
            state.prepared=true
            local deck=submittedDeck(self)
            if self.roomConnectionId and self.roomDraft and self.roomDraft.selection then
                local selected={};for _,id in ipairs(self.roomDraft.selection.main or{})do selected[tostring(type(id)=='table'and id.id or id)]=true end
                deck={main={},commander={},sideboard={}}
                for _,card in ipairs(self.roomDraft.pool or{})do if selected[tostring(card.id)]then deck.main[#deck.main+1]=card end end
            end
            local queued={}
            local function add(card)
                local item=entry(state,card);if item and not queued[item.key]then queued[item.key]=true;state.background[#state.background+1]=item end
            end
            -- Already visible cards stay ahead of background deck images.
            for _,item in ipairs(hands)do add(item.card)end
            for _,name in ipairs(GameArt.basics)do add({name=name})end
            for _,zone in ipairs({'commander','main','sideboard'})do
                for _,card in ipairs(deck and deck[zone]or{})do
                    local choices=false
                    for _,selection in ipairs(deck.printingSelections or{})do if selection.name==card.name and selection.zone==zone then
                        add({name=card.name,selectedPrintingId=selection.printingId});choices=true
                    end end
                    if not choices then add(card)end
                end
            end
        end
        local item=state.background[state.index]
        if not item then self.gameArtwork.phase='ready';return end
        local data=resolve(item,false)
        if not data then if item.failed then state.index=state.index+1 end;return end
        local kind=not item.kinds.normal and'normal'or not item.kinds.art_crop and'art_crop'or nil
        if not kind then state.index=state.index+1;state.completed=(state.completed or 0)+1;return end
        state.downloadPending=true
        self.api:request('catalog','POST','/art/download',{printingId=data.printing_id or data.id,face=printingFace(item.card,data),kind=kind},function(_,err,code)
            state.downloadPending=false
            if not current()then return end
            -- A refused/missing remote image is reported once, never a tight
            -- retry loop. New games can retry while ready cached images persist.
            item.kinds[kind]=true
            if err or code~=200 then state.failed=(state.failed or 0)+1 end
        end,false,{isCurrent=current})
    end
    local update=Model.update
    function Model:update(dt)update(self,dt);self:updateGameArtwork()end
end
return GameArt
