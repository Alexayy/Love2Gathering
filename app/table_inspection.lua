-- A table selection retains an exact native object and the projection that
-- entitled this viewer to see it. Every new frame resolves that source again.
local Presentation=require('app.card_presentation')
local json=require('lib.json')
local Inspection={}
local zones={'battlefield','hand','graveyard','exile','command'}
local kinds={permanent='battlefield',hand='hand',command='command'}
-- Native arrays are shared by every draw of a snapshot. Recheck the cached
-- slot before use so a replay seek or an in-place reordered test frame is safe.
local positions=setmetatable({}, {__mode='k'})
local function find(items,id)
    if not items or not id or id==json.null then return end
    local slots=positions[items]
    local pos=slots and slots[id]
    if pos and items[pos] and items[pos].id==id then return items[pos] end
    for i,item in ipairs(items) do
        if item.id==id then
            if not slots then slots={};positions[items]=slots end
            slots[id]=i
            return item
        end
    end
end
local function cardInRows(rows,id,field)
    for _,row in ipairs(rows or {}) do
        local card=row[field]
        if type(card)=='table' and card.id==id then return card end
    end
end
local function inGroups(groups,id)
    for _,group in ipairs(groups or {}) do
        local card=find(group.cards,id)
        if card then return card end
    end
end
local function inZone(game,id,zone,owner,preferred)
    local p=preferred and find(game.players,preferred)
    local preferredCard=p and find(p[zone],id)
    if preferredCard then return preferredCard,preferred end
    for _,p in ipairs(game.players or {}) do
        if p.id~=preferred and (not owner or p.id==owner) then
            local card=find(p[zone],id)
            if card then return card,p.id end
        end
    end
end
local function promptCard(game,p,id)
    local panel=p.cardPanel
    local card=find(panel and panel.cards,id) or find(p.pile1,id) or find(p.pile2,id)
        or cardInRows(p.choices,id,'card') or cardInRows(p.amountMessages,id,'card')
    if card then return card end
    if type(p.damageSourceCard)=='table' and p.damageSourceCard.id==id then return p.damageSourceCard end
    for _,choice in ipairs(p.choices or {}) do
        if choice.responseType=='uuid' and (choice.value or choice.id)==id then return inZone(game,id,'battlefield') end
    end
end
local function current(model,ref)
    local game=model.game
    if not game or ref.gameId~=game.gameId or ref.replay~=model.replay
            or ref.connection~=model.roomConnectionId or ref.route~=(model.api and model.api.routeGeneration) then return end
    local id=ref.id
    if ref.playableExile then return find(require('app.card_actions').extension(model),id) end
    if ref.zoneName then return inZone(game,id,ref.zoneName,ref.playerId,ref.preferredPlayer or ref.playerId) end
    if ref.linkedHostId then
        local host=inZone(game,ref.linkedHostId,'battlefield')
        if host and not host.hidden and not host.faceDown then return find(host.linkedExile,id) end
        return
    end
    if ref.libraryPlayerId then
        local card=model:libraryTop(ref.libraryPlayerId)
        if card and card.id==id then return card end
    elseif ref.groups then
        for _,group in ipairs(ref.groups) do
            local card=inGroups(game[group],id)
            if card then return card end
        end
    elseif ref.stackId then
        local obj=find(game.stack,ref.stackId)
        if obj then
            if obj.sourceCard and obj.sourceCard.id==id then return obj.sourceCard end
            if obj.id==id then return obj end
        end
    elseif ref.promptId then
        local p=model.replay and game.prompt or model:prompt()
        if p and p.id==ref.promptId then return promptCard(game,p,id) end
    elseif ref.history then
        for index,entry in ipairs(game.log or {}) do
            if type(entry)=='table' and (ref.entryId and entry.id==ref.entryId
                    or not ref.entryId and ref.sequence and ref.sequence==entry.sequence
                    or ref.logIndex==index and entry.timestamp==ref.timestamp and entry.text==ref.text
                        and entry.sourceId==ref.sourceId and entry.category==ref.category) then
                if entry.sourceCard and entry.sourceCard.id==id then return entry.sourceCard end
                if entry.sourceId==id and ref.fallbackZone then return inZone(game,id,ref.fallbackZone,ref.fallbackOwner) end
            end
        end
    elseif ref.commander then
        local player=find(game.players,ref.commander)
        local row=player and find(player.commanders,id)
        if row then return row.sourceCard and row.sourceCard.id and row.sourceCard or row.card and row.card.id and row.card
            or {id=id,name=row.name,zone=row.zone} end
    end
end
local function display(model,card,ref,publicBack)
    if not card or card.id~=ref.id or (ref.nativeZone and card.zone~=ref.nativeZone) then return end
    local shown=Presentation.peek(card)
    if not shown.hidden and not shown.faceDown then return shown end
    if publicBack and card.faceDown and (ref.zoneName=='battlefield' or ref.promptId) then
        card=inZone(model.game,ref.id,'battlefield')
        if not card or not card.faceDown then return end
        return {id=card.id,hidden=true,faceDown=true,name='Face-down card',power=card.power,toughness=card.toughness,
            damage=card.damage,counters=card.counters,tapped=card.tapped,attacking=card.attacking,blocking=card.blocking}
    end
end
local function source(model,card,context)
    local game=model.game
    if type(card)~='table' or not card.id or card.id==json.null or not game then return end
    context=context or {}
    -- An existing reference is most often supplied by the pinned preview.
    if context.tableSource then return context.id==card.id and context or nil end
    local zone=type(context.zone)=='table' and context.zone
    local expected=context.gameId or context.libraryGameId or zone and (zone.gameId or zone.libraryGameId)
    if expected and expected~=game.gameId then return end
    local id=card.id
    local ref={tableSource=true,id=id,gameId=game.gameId,replay=model.replay,connection=model.roomConnectionId,
        route=model.api and model.api.routeGeneration,nativeZone=card.zone}
    if context.libraryPlayerId or zone and zone.libraryPlayerId then
        ref.libraryPlayerId=context.libraryPlayerId or zone.libraryPlayerId
    elseif context.stackId then ref.stackId=context.stackId
    elseif context.linkedHostId then ref.linkedHostId=context.linkedHostId
    elseif context.history then
        local entry=context.entry
        if not entry then
            for _,item in ipairs(game.log or {}) do
                if type(item)=='table' and item.sourceCard==card then entry=item;break end
            end
        end
        if type(entry)~='table' then return end
        ref.history=true;ref.entryId=entry.id;ref.sequence=entry.sequence
        if not ref.entryId and not ref.sequence then
            -- Older recordings can lack the event ID and sequence. Preserve
            -- the same row across polls, and expire it when the log rolls.
            for i,row in ipairs(game.log or {}) do if row==entry then ref.logIndex=i;break end end
            if not ref.logIndex then return end
            ref.timestamp=entry.timestamp;ref.text=entry.text;ref.category=entry.category;ref.sourceId=entry.sourceId
        end
        if not entry.sourceCard or not entry.sourceCard.id then
            for _,name in ipairs(zones) do
                local obj,owner=inZone(game,id,name)
                if obj then ref.fallbackZone=name;ref.fallbackOwner=owner;break end
            end
        end
    elseif context.commanderPlayerId then ref.commander=context.commanderPlayerId
    elseif context.choice then
        local p=model.replay and game.prompt or model:prompt()
        if not p or not p.id then return end
        if context.choice~=p and context.choice.id~=p.id then
            local offered=find(p.choices,context.choice.id)
            if not offered or offered~=context.choice then return end
        end
        ref.promptId=p.id
    elseif context.lookedAt then ref.groups={'lookedAt'}
    elseif zone and zone.revealed then ref.groups={'revealed','lookedAt'}
    elseif zone and zone.playerId and zone.zoneName then
        if zone.memberIds and not zone.memberIds[id] then return end
        ref.zoneName=zone.zoneName;ref.playerId=zone.playerId
    elseif (zone and zone.playableExile) or context.kind=='exile-hand' then ref.playableExile=true
    elseif kinds[context.kind] then
        ref.zoneName=kinds[context.kind]
        ref.preferredPlayer=ref.zoneName=='battlefield' and card.controllerId or card.ownerId
    else
        for _,name in ipairs(zones) do
            local obj,owner=inZone(game,id,name)
            if obj then ref.zoneName=name;ref.playerId=name~='battlefield' and owner or nil;ref.preferredPlayer=owner;return ref end
        end
        for _,p in ipairs(game.players or {}) do
            if model:libraryTop(p) and p.libraryTop.id==id then ref.libraryPlayerId=p.id;return ref end
            if cardInRows(p.commanders,id,'sourceCard') then ref.commander=p.id;return ref end
        end
        for _,key in ipairs({'revealed','lookedAt'}) do
            if inGroups(game[key],id) then ref.groups={key};return ref end
        end
        for _,obj in ipairs(game.stack or {}) do
            if obj.id==id or obj.sourceCard and obj.sourceCard.id==id then ref.stackId=obj.id;return ref end
        end
        local p=model.replay and game.prompt or model:prompt()
        if p and p.id and promptCard(game,p,id) then ref.promptId=p.id else return end
    end
    return ref
end
local function resolve(model,card,context,publicBack)
    local ref=source(model,card,context)
    if ref then
        local shown=display(model,current(model,ref),ref,publicBack)
        if shown then
            if card.hidden and not shown.hidden then return end
            return shown,ref
        end
    end
end
function Inspection.install(Model)
    function Model:tableStackEntry(ref)
        if ref and ref.stackId and display(self,current(self,ref),ref,false) then
            return find(self.game.stack,ref.stackId)
        end
    end
    function Model:resolveTableCard(card,context) return resolve(self,card,context,false) end
    function Model:pinTableCard(card,context)
        local shown,ref=resolve(self,card,context,false)
        if not shown then return false end
        self.tablePin=ref
        return true
    end
    function Model:pinnedTableCard()
        local ref=self.tablePin
        if ref then
            local shown=display(self,current(self,ref),ref,false)
            if shown then return shown,ref end
            self.tablePin=nil
        end
    end
    function Model:clearTablePreview() self.tablePin=nil end
    function Model:inspectTableCard(card,context)
        local shown,ref=resolve(self,card,context,true)
        if not shown then return false end
        self.tableDetailSource=ref;self.tableDetailCard=shown;self.inspectCard=shown
        return true
    end
    function Model:closeTableInspection()
        self.tableDetailSource=nil;self.tableDetailCard=nil;self.inspectCard=nil;self.libraryTopInspect=nil
    end
    function Model:refreshTableInspection()
        self:pinnedTableCard()
        if not self.tableDetailSource then return end
        if self.inspectCard~=self.tableDetailCard then
            self.tableDetailSource=nil;self.tableDetailCard=nil
            return
        end
        local ref=self.tableDetailSource
        local shown=display(self,current(self,ref),ref,self.tableDetailCard.hidden)
        self.inspectCard=shown;self.tableDetailCard=shown
        if not shown then self.tableDetailSource=nil end
    end
end
return Inspection
