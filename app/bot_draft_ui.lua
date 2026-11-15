local Rooms=require('app.rooms')
local UI={}
local function value(item)return type(item)=='table'and(item.id or item.code or item.value)or item end
local function label(item)return type(item)=='table'and(item.label or item.name or item.id or item.code)or tostring(item)end
local function button(v,text,icon,w,h,disabled)
    return v.S.Button(text,{W=w,H=h,Disabled=disabled,Image={Image=v.r.assets:buttonImage(icon,text,w,h,{font=v.r.fonts[16],iconSize=20})}})
end
local function choice(v,id,title,current,items,w,changed)
    v.S.Text(title,{Color=v.r.colors.muted})
    local labels,ids,selected={},{},tostring(current or'Unavailable')
    for _,item in ipairs(items or{})do local text=tostring(label(item));labels[#labels+1]=text;ids[text]=value(item);if value(item)==current then selected=text end end
    v:combo(id,selected,labels,w,function(text)if ids[text]then changed(ids[text])end end)
    v.S.NewLine()
end
local function pack(v,index,draft,caps,w)
    local selected=tostring(draft.sets[index]or'Choose booster')
    for _,set in ipairs(caps.sets or{})do if value(set)==draft.sets[index]then selected=label(set);break end end
    if button(v,'Pack '..index..' · '..selected,'pack',w,38)then
        local options={};for _,set in ipairs(caps.sets or{})do options[#options+1]={code=value(set),name=label(set)}end
        require('app.set_picker').open(v,{id='bot-draft-pack-'..index,title='Choose pack '..index,items=options,allowAll=false,selected=draft.sets[index],owner=draft,
            isCurrent=function()return v.m.page=='lobby'and v.m.lobbyMode=='draft'and v.m.roomSetup.draft==draft and not v.m.botDraftBusy end,
            onSelect=function(code)for _,set in ipairs(caps.sets or{})do if tostring(value(set)):lower()==code then draft.sets[index]=value(set);break end end end})
    end
    v.S.NewLine()
end
function UI.build(v,w,h)
    local S,m=v.S,v.m;Rooms.fitSetup(m);local setup=m.roomSetup;setup.kind='draft';Rooms.fitSetup(m)
    local caps=m.roomCapabilities and m.roomCapabilities.draft;local width=w-56
    v:window('bot-draft-setup',28,100,width,h-190,nil,{AutoSizeContent=false})
    if button(v,'Constructed practice','back',230,36,m.botDraftBusy)then m.lobbyMode='constructed'end
    S.SameLine({Pad=20,CenterY=true});S.Text('Draft with XMage bots',{Color=v.r.colors.accent});S.NewLine()
    S.BeginListBox('bot-draft-fields',{W=width-28,H=math.max(180,h-284)})
    S.Indent(14);S.NewLine(.5);local inner=math.min(760,width-74)
    S.Textf('Choose boosters, draft your cards, then build from your pool. XMage handles bot picks, bot decks and tournament rounds.',{W=inner,Color=v.r.colors.muted});S.NewLine()
    if not caps then
        S.Textf(m.roomCapabilityError or'Loading installed draft options…',{W=inner,Color=v.r.colors.gold})
    else
        if caps.botSupport~=true then S.Textf('Bot drafting is not available in the installed engine.',{W=inner,Color=v.r.colors.gold});S.NewLine()end
        local draft=setup.draft
        local counts={};for n=m.roomSetupMinPlayers or 4,m.roomSetupMaxPlayers or 16 do counts[#counts+1]={id=n,label='You + '..(n-1)..' bots'}end
        choice(v,'bot-draft-count','Seats',setup.maxPlayers,counts,inner,function(id)setup.maxPlayers=id end)
        choice(v,'bot-draft-mode','Draft procedure',draft.mode,caps.modes,inner,function(id)draft.mode=id;Rooms.fitSetup(m)end)
        choice(v,'bot-draft-profile','Deck rules',draft.profile,caps.profiles,inner,function(id)draft.profile=id end)
        if#(caps.pairings or{})>0 then choice(v,'bot-draft-pairing','Rounds',draft.pairing,caps.pairings,inner,function(id)draft.pairing=id end)end
        if#(caps.timings or{})>0 then choice(v,'bot-draft-timing','Pick clock',draft.timing,caps.timings,inner,function(id)draft.timing=id end)end
        if draft.mode=='booster'then
            local count=3;for _,mode in ipairs(caps.modes or{})do if type(mode)=='table'and value(mode)==draft.mode then count=mode.packCount or count end end
            for index=1,count do pack(v,index,draft,caps,inner)end
        elseif draft.mode=='cube'then choice(v,'bot-draft-cube','Cube',draft.cubeId,caps.cubes,inner,function(id)draft.cubeId=id end)
        elseif draft.mode=='random'then S.Textf('XMage chooses from its supported random booster pool.',{W=inner,Color=v.r.colors.muted})end
    end
    if m.roomConnectionId then S.NewLine();S.Textf('A private room is already open. Return to it or leave it before starting another draft.',{W=inner,Color=v.r.colors.gold});if button(v,'Open current room','players',inner,36)then m:showRooms()end end
    local error=m.botDraftError or m.room and m.room.error
    if error then S.NewLine();S.Textf(error,{W=inner,Color=v.r.colors.gold})end
    S.NewLine(.5);S.Unindent(14);S.EndListBox();S.EndWindow()
    v:window('bot-draft-start',28,h-70,width,52,nil,{AutoSizeContent=false})
    if button(v,m.botDraftBusy and'Preparing draft…'or'Start bot draft','play',260,40,m.botDraftBusy or m.roomBusy or m.roomConnectionId~=nil or not caps or caps.botSupport~=true)then m:startBotDraft()end
    S.SameLine({Pad=20,CenterY=true});S.Text('Private draft · '..tostring((setup.maxPlayers or 4)-1)..' bot seats',{Color=v.r.colors.muted})
    S.EndWindow()
end
return UI
