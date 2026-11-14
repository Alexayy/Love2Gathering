-- Invite-code room presentation. Room transport and native state are provided
-- by app.rooms; this view never enumerates public or discoverable rooms.
local Rooms=require('app.rooms')
local Shared=require('app.draft_ui')
local UI={}
function UI.layout(w,h)
    local margin,gap=26,16;local width=w-margin*2
    local setup=math.max(360,math.min(480,width*.40))
    return {setup={x=margin,y=158,w=setup,h=h-184},
        seats={x=margin+setup+gap,y=158,w=width-setup-gap,h=h-184},
        invite={x=margin,y=100,w=width,h=45}}
end
local function identity(item)return type(item)=='table'and(item.id or item.code or item.value)or item end
local function label(item)
    if type(item)~='table'then return tostring(item)end
    return tostring(item.label or item.name or item.id or item.code)
end
local function choice(v,id,title,current,items,width,changed)
    local S=v.S;S.Text(title,{Color=v.r.colors.muted})
    local selected=tostring(current or 'Unavailable')
    for _,item in ipairs(items or {})do if identity(item)==current then selected=label(item);break end end
    if S.BeginComboBox(id,{Selected=selected,W=width})then
        for _,item in ipairs(items or {})do if S.TextSelectable(label(item),{Selected=identity(item)==current})then changed(identity(item))end end
        S.EndComboBox()
    end
end
local function info(v,text,width,color)v.S.Textf(text,{W=width,Color=color or v.r.colors.muted})end
local function errorText(value)
    if type(value)=='table'then
        local out={};for _,entry in ipairs(value)do out[#out+1]=type(entry)=='table'and(entry.message or entry.error or tostring(entry))or tostring(entry)end
        return table.concat(out,'\n')
    end
    return tostring(value or '')
end
local function randomPool(v,width,sets)
    local S,m=v.S,v.m;local pool=m.roomSetup.draft.randomSets;local selected={};local labels={}
    for _,code in ipairs(pool)do selected[code]=true end
    for _,item in ipairs(sets or {})do labels[identity(item)]=label(item)end
    Shared.heading(v,'Eligible booster sets','shuffle',width);S.NewLine()
    info(v,#pool==0 and'All supported booster sets'or(#pool..' selected · XMage chooses boosters from this pool'),width,v.r.colors.accent)
    S.NewLine();S.Text('Find a supported set',{Color=v.r.colors.muted})
    if S.Input('room-random-set-search',{Text=m.roomRandomSetSearch or'',W=width,H=30,Align='left'})then m.roomRandomSetSearch=S.GetInputText()end
    local query=(m.roomRandomSetSearch or''):lower();local available={};local current
    for _,item in ipairs(sets or {})do
        local code=identity(item)
        if not selected[code]and(label(item)..' '..tostring(code)):lower():find(query,1,true)then
            available[#available+1]=item
            if code==m.roomRandomSetChoice then current=code end
        end
    end
    m.roomRandomSetChoice=current or(available[1]and identity(available[1]))
    S.NewLine();choice(v,'room-random-set','Add a supported set',m.roomRandomSetChoice,available,width,function(code)m.roomRandomSetChoice=code end)
    S.NewLine()
    if Shared.button(v,'Add set','plus',width,30,{Disabled=not m.roomRandomSetChoice})then Rooms.setRandomSet(m,m.roomRandomSetChoice,true)end
    for _,code in ipairs(pool)do
        S.NewLine();S.Textf(v.r:fit(labels[code]or tostring(code),width-42,14,2),{W=width-42,Color=v.r.colors.text});S.SameLine()
        if Shared.button(v,'Remove '..(labels[code]or tostring(code)),'minus',30,30,{Tooltip='Remove '..(labels[code]or tostring(code))})then Rooms.setRandomSet(m,code,false)end
    end
    if #available==0 then S.NewLine();info(v,query~=''and'No additional sets match your search.'or'All supported sets are already selected.',width)end
end
local function setup(v,width,height)
    local S,m=v.S,v.m;local setup=m.roomSetup;local caps=m.roomCapabilities or {};local game=caps.game or {};local draft=caps.draft or {}
    Shared.heading(v,'Create a private table','network',width);S.NewLine()
    S.BeginListBox('room-create-fields',{W=width,H=height-120})
    local inner=width-16
    S.Text('Your name',{Color=v.r.colors.muted})
    if S.Input('room-name',{Text=setup.playerName,W=inner,H=30,Align='left'})then setup.playerName=S.GetInputText()end
    S.NewLine();S.Text('Room name',{Color=v.r.colors.muted})
    if S.Input('room-title',{Text=setup.name,W=inner,H=30,Align='left'})then setup.name=S.GetInputText()end
    S.NewLine()
    local modes={{id='constructed',label='Decks'},{id='draft',label='Draft'}}
    for i,kind in ipairs(modes)do
        if i>1 then S.SameLine()end
        if Shared.button(v,kind.label,kind.id=='draft'and'pack'or'library',(inner-8)/2,34,{Active=setup.kind==kind.id})then setup.kind=kind.id;Rooms.fitSetup(m)end
    end
    S.NewLine()
    if setup.kind=='constructed'then
        choice(v,'room-format','Format',setup.format,game.formats,inner,function(value)setup.format=value;Rooms.fitSetup(m)end)
    else
        local d=setup.draft
        choice(v,'room-draft-mode','Draft',d.mode,draft.modes,inner,function(value)d.mode=value;Rooms.fitSetup(m)end)
        S.NewLine();choice(v,'room-draft-profile','Deck profile',d.profile,draft.profiles,inner,function(value)d.profile=value end)
        if #(draft.pairings or {})>0 then S.NewLine();choice(v,'room-draft-pairing','Rounds',d.pairing,draft.pairings,inner,function(value)d.pairing=value end)end
        if #(draft.timings or {})>0 then S.NewLine();choice(v,'room-draft-timing','Pick clock',d.timing,draft.timings,inner,function(value)d.timing=value end)end
        S.NewLine()
        if d.mode=='booster'then
            local count=3;for _,mode in ipairs(draft.modes or {})do if identity(mode)==d.mode and type(mode)=='table'then count=mode.packCount or count end end
            for index=1,count do
                choice(v,'room-pack-'..index,'Pack '..index,d.sets[index],draft.sets,inner,function(value)d.sets[index]=value end)
                if index<count then S.NewLine()end
            end
        elseif d.mode=='cube'then
            choice(v,'room-cube','Cube',d.cubeId,draft.cubes,inner,function(value)d.cubeId=value end)
        elseif d.mode=='random'then randomPool(v,inner,draft.sets)end
    end
    S.NewLine();local counts={};for count=m.roomSetupMinPlayers or 2,m.roomSetupMaxPlayers or 2 do counts[#counts+1]=count end
    choice(v,'room-players','Seats',setup.maxPlayers,counts,inner,function(value)setup.maxPlayers=value end)
    S.NewLine();info(v,'Only people with your invitation code can join. Add bot seats after creating the room.',inner)
    if m.roomCapabilityError then S.NewLine();info(v,m.roomCapabilityError,inner,v.r.colors.gold)end
    S.EndListBox();S.NewLine()
    if Shared.button(v,m.roomBusy and 'Creating…'or'Create invite room','network',width,38,{Disabled=m.roomBusy or not m.roomCapabilities or m.roomCapabilitiesBusy})then m:hostRoom()end
end
local function ownMember(m)
    for _,member in ipairs(m.room and m.room.members or {})do if member.id==m.roomParticipantId then return member end end
end
local function members(v,width,height)
    local S,m=v.S,v.m;local room=m.room;local count=0;for _ in ipairs(room.members or {})do count=count+1 end
    local draftSeats={};for _,seat in ipairs(m.roomDraft and m.roomDraft.players or {})do draftSeats[seat.seatId or seat.id]=seat end
    Shared.heading(v,'Seats · '..count..' / '..tostring((room.config or {}).maxPlayers or '?'),'players',width);S.NewLine()
    S.BeginListBox('room-member-list',{W=width,H=height-66})
    for index,member in ipairs(room.members or {})do
        S.PushID('room-member-'..member.id)
        local draftSeat=draftSeats[member.id];local forfeited=draftSeat and draftSeat.forfeited
        local tint=member.id==m.roomParticipantId and v.r.colors.accent or(member.bot or forfeited)and v.r.colors.purple or v.r.colors.text
        S.Image('avatar',{Image=v.r.assets:iconImage((member.bot or forfeited)and'bot'or'player',23,tint),W=23,H=23});S.SameLine()
        local suffix=member.id==room.hostId and' · host'or''
        S.Textf(v.r:fit(member.name..suffix,width-130,16,1),{W=width-130,Color=tint});S.SameLine()
        S.Image('ready',{Image=v.r.assets:iconImage(member.ready and'check'or'pause',20,member.ready and v.r.colors.accent or v.r.colors.muted),W=20,H=20})
        info(v,member.bot and'XMage bot'or forfeited and'Left the table'or member.connected==false and'Disconnected · seat retained'or'Connected',width-30,member.connected==false and v.r.colors.gold or v.r.colors.muted)
        if forfeited then info(v,'Left · XMage completes this draft seat',width-30,v.r.colors.gold)
        elseif draftSeat and room.phase=='drafting'then info(v,(draftSeat.picking and'Choosing'or'Waiting')..' · '..tostring(draftSeat.poolCount or 0)..' picked',width-30)end
        if member.deckName then info(v,member.deckName,width-30)end
        S.Separator();S.NewLine();S.PopID()
    end
    if m.roomDraft and m.roomDraft.tournament then S.NewLine();Shared.tournament(v,m.roomDraft,width-24)end
    S.EndListBox()
end
local function connected(v,width,height)
    local S,m=v.S,v.m;local room=m.room;local config=room.config or {};local own=ownMember(m);local host=room.hostId==m.roomParticipantId
    Shared.heading(v,room.name or config.name or 'Private table','network',width);S.NewLine()
    S.BeginListBox('room-your-seat',{W=width,H=math.max(130,height-250)})
    local inner=width-16
    info(v,config.kind=='draft'and'Draft table'or tostring(config.format or 'Constructed')..' table',inner,v.r.colors.accent)
    if room.phase=='starting'then S.NewLine();info(v,'XMage is preparing the table…',inner,v.r.colors.accent)end
    S.NewLine()
    if config.kind~='draft'and room.phase=='lobby'then
        Shared.heading(v,'Your deck','library',inner)
        v:deckPicker('room-deck',m.roomDeckId,config.format or m.format,inner,function(id)m:selectRoomDeck(id)end)
        info(v,'Your deck remains private. XMage validates it before play.',inner)
    elseif config.kind=='draft'then
        info(v,'Your pack, picks and draft pool are private to your seat.',inner)
    end
    if host and room.phase=='lobby'then
        S.NewLine();local bots,humans=0,0;for _,member in ipairs(room.members or {})do if member.bot then bots=bots+1 else humans=humans+1 end end
        Shared.heading(v,'Bot seats · '..bots,'bot',inner,v.r.colors.purple)
        if Shared.button(v,'Remove','minus',(inner-8)/2,32,{Disabled=m.roomBusy or bots==0})then m:setRoomBots(bots-1)end;S.SameLine()
        if Shared.button(v,'Add bot','plus',(inner-8)/2,32,{Disabled=m.roomBusy or humans+bots>=(config.maxPlayers or math.huge)})then m:setRoomBots(bots+1)end
    end
    if m.roomError then S.NewLine();info(v,m.roomError,inner,v.r.colors.gold)end
    S.EndListBox();S.NewLine()
    if room.phase=='lobby'then
        if Shared.button(v,own and own.ready and'Not ready'or'Ready','check',width,35,{Active=own and own.ready,Disabled=m.roomBusy or not own or m.roomDisconnected})then m:setRoomReady(not own.ready)end
        if host then S.NewLine();if Shared.button(v,config.kind=='draft'and'Start draft'or'Start match','play',width,38,{Disabled=m.roomBusy or m.roomDisconnected or room.canStart==false})then m:startRoom()end end
    elseif m.roomDraft and(room.phase=='drafting'or room.phase=='building')then
        if Shared.button(v,'Open draft','pack',width,36)then m.page='draft'end
    elseif room.phase=='playing'and m.game then
        if Shared.button(v,'Return to match','play',width,36)then m.page='table'end
    elseif m.roomDraft and(room.phase=='playing'or room.phase=='completed')then
        if Shared.button(v,'View draft pool','library',width,36)then m.page='draft'end
    end
    if host and room.phase=='building'then S.NewLine();if Shared.button(v,'Start drafted round','play',width,36,{Disabled=m.roomBusy or not room.canStart or(m.roomDraftDeck and m.roomDraftDeck.dirty)})then m:startRoom()end end
    if host and room.canNextRound then S.NewLine();if Shared.button(v,'Next round','next',width,36,{Disabled=m.roomBusy})then m:nextRoomRound()end end
    S.NewLine()
    if host then info(v,'Closing the room disconnects everyone.',width,v.r.colors.muted)end
    if Shared.button(v,host and'Close room'or'Leave room','back',width,32,{Disabled=m.roomBusy,Tooltip=host and'Close this room for everyone'or'Leave your seat'})then m:leaveRoom()end
end
function UI.build(v,w,h)
    local S,m=v.S,v.m;Rooms.fitSetup(m);local l=UI.layout(w,h)
    v:window('room-invite',l.invite.x,l.invite.y,l.invite.w,l.invite.h,nil,{AutoSizeContent=false})
    if m.room then
        local width=l.invite.w-180
        S.Input('invite-code',{Text=m.room.inviteCode or '',ReadOnly=true,W=width,H=28,Align='left',Tooltip='Share this single invitation code'})
        S.SameLine();if Shared.button(v,'Copy code','copy',132,29)then m:copyRoomCode()end
    else Shared.heading(v,'Rooms · invite code only','network',l.invite.w-30,v.r.colors.accent)end
    S.EndWindow()
    v:window('room-setup',l.setup.x,l.setup.y,l.setup.w,l.setup.h)
    if m.room then connected(v,l.setup.w-28,l.setup.h-26)else setup(v,l.setup.w-28,l.setup.h-26)end
    S.EndWindow()
    v:window('room-members',l.seats.x,l.seats.y,l.seats.w,l.seats.h)
    local inner=l.seats.w-28
    if m.room then members(v,inner,l.seats.h-26)
    else
        Shared.heading(v,'Join friends','players',inner);S.NewLine()
        info(v,'Paste the invitation code shared by the host.',inner);S.NewLine()
        if S.Input('join-code',{Text=m.roomInviteInput,W=inner,H=35,Align='left'})then m.roomInviteInput=S.GetInputText()end
        S.NewLine()
        if Shared.button(v,'Paste code','copy',(inner-8)/2,34,{Disabled=m.roomBusy})then m.roomInviteInput=love.system.getClipboardText()or''end;S.SameLine()
        if Shared.button(v,m.roomBusy and'Connecting…'or'Join room','network',(inner-8)/2,34,{Disabled=m.roomBusy})then m:joinRoom()end
        if m.roomLastCode then S.NewLine();if Shared.button(v,'Use previous code','replay',inner,32,{Disabled=m.roomBusy})then m.roomInviteInput=m.roomLastCode end end
        S.NewLine();info(v,'The code contains the host connection information. You do not need to enter an address.',inner)
        if m.roomError then S.NewLine();info(v,errorText(m.roomError),inner,v.r.colors.gold)end
        if m.roomCapabilityError then S.NewLine();if Shared.button(v,'Reload options','replay',inner,32)then m:refreshRoomCapabilities()end end
    end
    if m.roomDisconnected then S.NewLine();if Shared.button(v,'Reconnect to your seat','replay',inner,35,{Disabled=m.roomBusy})then m:rejoinRoom()end end
    S.EndWindow()
end
return UI
