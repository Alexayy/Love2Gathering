-- Draft presentation and local deck editing only. Native draft projections own
-- the offered pack, pick identities, pool, basic-land options and validation.
local Assets=require('app.assets')
local Layout=require('app.layout')
local RichText=require('app.richtext')
local UI={cardCache={},cardCacheClock=0,cardCacheLimit=96}
function UI.layout(w,h,building)
    local margin,gap=26,14
    local top=150;local footer=62
    local side=math.max(280,math.min(building and 380 or 335,w*.29))
    return {main={x=margin,y=top,w=w-margin*2-gap-side,h=h-top-footer},
        side={x=w-margin-side,y=top,w=side,h=h-top-footer},
        footer={x=margin,y=h-54,w=w-margin*2,h=42},gap=gap}
end
function UI.cardName(card)return tostring(card and (card.name or card.displayName) or 'Card')end
function UI.groups(pool,selected)
    local groups,lookup={},{}
    for _,card in ipairs(pool or {})do
        local name=UI.cardName(card);local group=lookup[name]
        if not group then group={name=name,cards={},selected={},available={}};lookup[name]=group;groups[#groups+1]=group end
        group.cards[#group.cards+1]=card
        local target=selected and selected[tostring(card.id)] and group.selected or group.available
        target[#target+1]=card
    end
    table.sort(groups,function(a,b)return a.name:lower()<b.name:lower()end)
    return groups
end
local function button(v,label,icon,w,h,options)
    options=options or {};options.W=w;options.H=h
    options.Image={Image=w<=42 and v.r.assets:iconImage(icon,17)or v.r.assets:buttonImage(icon,label,w,h,{font=v.r.fonts[14],iconSize=17})}
    return v.S.Button(label,options)
end
local function heading(v,text,icon,width,color)
    local S=v.S;S.Image('draft-heading-'..text,{Image=v.r.assets:iconImage(icon,20,color),W=20,H=20});S.SameLine()
    S.Textf(text,{W=width-30,Color=color or v.r.colors.accent})
end
local function nativeText(value)
    if type(value)=='table'then value=table.concat(value,'\n')end
    return tostring(value or ''):gsub('<[^>]+>',''):gsub('&nbsp;',' '):gsub('&mdash;?','—'):gsub('&ndash;?','–'):gsub('&bull;?','\n• '):gsub('&lt;','<'):gsub('&gt;','>'):gsub('&amp;','&')
end
local function description(card,data)
    local cost=nativeText(card.manaCost or data.mana_cost or data.manaCost)
    local kind=nativeText(card.type or data.type_line or data.type)
    local rules=nativeText(card.rules or data.oracle_text or data.rules)
    local stats=kind:lower():find('creature',1,true)and card.power and card.toughness and(tostring(card.power)..'/'..tostring(card.toughness))or nil
    return cost,kind,rules,stats
end
local function fallback(v,card,data,w,h,caption)
    local cost,kind,rules,stats=description(card,data);local scale=Layout.scale or 1
    local key=table.concat({Assets.rasterEpoch,UI.cardName(card),cost,kind,rules,stats or'',caption or'',w,h,scale,tostring(v.r.fonts[12])},'\31')
    UI.cardCacheClock=UI.cardCacheClock+1;local cached=UI.cardCache[key]
    if cached then cached.used=UI.cardCacheClock;return cached.image end
    local canvas=Assets.rasterize(w*scale,h*scale,function()
        love.graphics.scale(scale);v.r.assets:panel(0,0,w,h,{.055,.085,.12,1})
        v.r:text(v.r:fit(UI.cardName(card),w-16,12,2),8,8,12,v.r.colors.text,w-16)
        if cost~=''then v.r.assets:mana(cost,8,43,15)end
        v.r:text(v.r:fit(kind,w-16,10,2),8,66,10,v.r.colors.muted,w-16)
        RichText.draw(v.r,rules,8,94,w-16,{size=10,color=v.r.colors.text,maxLines=math.max(1,math.min(5,math.floor((h-118)/13)))})
        if stats then v.r:text(stats,w-47,h-23,12,v.r.colors.text,39,'right')end
        if caption then v.r:text(caption,8,h-23,10,v.r.colors.accent,w-(stats and 56 or 16))end
    end)
    UI.cardCache[key]={image=canvas,used=UI.cardCacheClock}
    local count=0;for _ in pairs(UI.cardCache)do count=count+1 end
    while count>UI.cardCacheLimit do
        local oldest,used;for candidate,entry in pairs(UI.cardCache)do if not used or entry.used<used then oldest,used=candidate,entry.used end end
        UI.cardCache[oldest]=nil;count=count-1
    end
    return canvas
end
local function cardButton(v,card,w,h,action,disabled,id,caption)
    local S,m=v.S,v.m;local data=m:cardData(card)or card;local art=m:getArt(data,true)
    local cost,kind,rules,stats=description(card,data)
    local tooltip=UI.cardName(card)..' · right-click to inspect'
    for _,text in ipairs({cost,kind,rules,stats or''})do if text~=''then tooltip=tooltip..'\n'..text end end
    local options={W=w,H=h,Disabled=disabled,Tooltip=tooltip,Image={Image=art or fallback(v,card,data,w,h,caption)}}
    S.PushID('draft-card-'..tostring(id or card.id))
    local label=UI.cardName(card)
    if S.Button(label,options)then action(card)end
    if S.IsControlHovered()and S.IsMouseClicked(2)then m.inspectCard=data end
    S.PopID()
end
UI.button=button;UI.heading=heading;UI.cardButton=cardButton
local function deckCount(deck)
    local count=0
    for _,selected in pairs(deck and deck.mainIds or {})do if selected then count=count+1 end end
    for _,amount in pairs(deck and deck.basics or {})do count=count+amount end
    return count
end
UI.deckCount=deckCount
function UI.tournament(v,draft,width)
    local tournament=draft and draft.tournament;if not tournament then return end
    local S,m=v.S,v.m;local names={}
    for _,member in ipairs(m.room and m.room.members or {})do names[member.id]=member.name end
    for _,standing in ipairs(tournament.standings or {})do names[standing.seatId]=standing.name end
    heading(v,'Round '..tostring(tournament.round or 0),'players',width,v.r.colors.accent);S.NewLine()
    if tournament.status=='completed'then S.Textf('Tournament complete',{W=width,Color=v.r.colors.gold})end
    if m.roomTournamentRole=='bye'then S.Textf('You have a bye this round.',{W=width,Color=v.r.colors.gold})
    elseif m.roomTournamentRole=='eliminated'then S.Textf('Your tournament run is complete. Standings remain visible.',{W=width,Color=v.r.colors.muted})end
    for index,match in ipairs(tournament.matches or {})do
        local opponents={};for _,id in ipairs(match.seatIds or {})do opponents[#opponents+1]=names[id]or tostring(id)end
        S.Textf(table.concat(opponents,' · ')..(match.bye and' · bye'or match.finished and' · finished'or' · playing'),{W=width,Color=match.finished and v.r.colors.muted or v.r.colors.text})
    end
    S.NewLine();heading(v,'Standings','check',width,v.r.colors.accent)
    for _,standing in ipairs(tournament.standings or {})do
        S.Textf(tostring(standing.name)..' · '..tostring(standing.points or 0)..' pts'..(standing.eliminated and' · eliminated'or''),{W=width,Color=standing.seatId==m.roomParticipantId and v.r.colors.accent or v.r.colors.text})
    end
    local champion=tournament.champion or tournament.winnerSeatId
    if champion then S.NewLine();S.Textf('Champion · '..tostring(type(champion)=='table'and champion.name or names[champion]or champion),{W=width,Color=v.r.colors.gold})end
end
local function errors(v,value,width)
    if not value then return end
    local S=v.S
    if type(value)=='table'then
        local entries=value.errors or value
        for _,entry in ipairs(entries)do S.Textf(type(entry)=='table'and(entry.message or entry.error or 'Deck requires changes')or tostring(entry),{W=width,Color=v.r.colors.gold})end
    else S.Textf(tostring(value),{W=width,Color=v.r.colors.gold})end
end
local function pool(v,draft,width,height)
    local S=v.S
    heading(v,'Your pool · '..#(draft.pool or {}),'library',width);S.NewLine()
    S.BeginListBox('draft-pool',{W=width,H=height-90})
    for _,group in ipairs(UI.groups(draft.pool))do
        S.PushID('pool-'..group.name)
        if S.TextSelectable(#group.cards..' × '..group.name,{W=width-24})then v.m.inspectCard=group.cards[1]end
        S.PopID()
    end
    S.EndListBox()
end
local function picking(v,draft,l)
    local S,m=v.S,v.m;local main=l.main;local inner=main.w-28
    v:window('draft-pack',main.x,main.y,main.w,main.h)
    heading(v,'Your pack · pick '..tostring(draft.pickNumber or '?'),'pack',inner);S.NewLine()
    local columns=math.max(3,math.floor((inner-30)/132));local cw=math.floor((inner-30-(columns-1)*12)/columns);local ch=math.floor(cw*1.4)
    S.BeginListBox('draft-pack-cards',{W=inner,H=main.h-94})
    if #(draft.pack or {})==0 then
        S.Textf(draft.status=='initializing'and'XMage is preparing the boosters…'or'Waiting for the next pack…',{W=inner-22,Color=v.r.colors.muted})
    else
        for index,card in ipairs(draft.pack or {})do
            if index>1 and(index-1)%columns~=0 then S.SameLine({Pad=8})end
            cardButton(v,card,cw,ch,function(chosen)m:pickDraftCard(chosen.id)end,m.roomBusy or m.roomDisconnected or not draft.pickToken,'pack-'..card.id)
            if index%columns==0 then S.NewLine()end
        end
    end
    S.EndListBox();S.EndWindow()
    local side=l.side
    v:window('draft-picks',side.x,side.y,side.w,side.h)
    pool(v,draft,side.w-28,side.h-28)
    if draft.secondsRemaining~=nil then
        S.NewLine();S.Image('pick-clock-icon',{Image=v.r.assets:iconImage('turn',18),W=18,H=18});S.SameLine();S.Text('Pick clock · '..tostring(math.max(0,math.floor(draft.secondsRemaining)))..' s',{Color=v.r.colors.gold})
    end
    S.EndWindow()
end
local function building(v,draft,l)
    local S,m=v.S,v.m;local deck=m.roomDraftDeck or {mainIds={},basics={}};local locked=m.roomBusy or m.roomDisconnected or(draft.status~='building'and draft.status~='ready')
    local main=l.main;local inner=main.w-28
    v:window('draft-build-pool',main.x,main.y,main.w,main.h)
    heading(v,'Drafted cards · click to add','library',inner);S.NewLine()
    S.BeginListBox('draft-build-cards',{W=inner,H=main.h-86})
    local columns=math.max(3,math.floor((inner-30)/140));local cw=math.floor((inner-30-(columns-1)*12)/columns);local ch=math.floor(cw*1.4)
    for index,group in ipairs(UI.groups(draft.pool,deck.mainIds))do
        if index>1 and(index-1)%columns~=0 then S.SameLine({Pad=8})end
        local card=group.available[1]or group.cards[1]
        cardButton(v,card,cw,ch,function(chosen)m:setDraftCard(chosen.id,true)end,locked or #group.available==0,'pool-'..index,#group.selected..' / '..#group.cards..' in main')
        if index%columns==0 then S.NewLine()end
    end
    S.EndListBox();S.EndWindow()
    local side=l.side;local width=side.w-28
    v:window('draft-build-deck',side.x,side.y,side.w,side.h)
    if draft.status=='competing'or draft.status=='completed'then
        heading(v,'Native tournament','players',width);S.NewLine()
        S.BeginListBox('draft-tournament',{W=width,H=side.h-88});UI.tournament(v,draft,width-20);S.EndListBox();S.EndWindow();return
    end
    local minimum=draft.minDeckSize or(((m.roomCapabilities or {}).draft or {}).minDeckSize)or 40
    heading(v,'Main deck · '..deckCount(deck)..' / '..minimum,'library',width);S.NewLine()
    S.BeginListBox('draft-main-list',{W=width,H=side.h-142})
    local content=width-18
    for index,group in ipairs(UI.groups(draft.pool,deck.mainIds))do if #group.selected>0 then
        S.PushID('draft-main-'..index)
        S.Textf(#group.selected..' × '..group.name,{W=content-68});S.SameLine()
        if button(v,'Remove','minus',30,26,{Disabled=locked,Tooltip='Move one copy to the sideboard'})then m:setDraftCard(group.selected[#group.selected].id,false)end
        S.SameLine()
        if button(v,'Add','plus',30,26,{Disabled=locked or #group.available==0,Tooltip='Add one drafted copy'})then m:setDraftCard(group.available[1].id,true)end
        S.PopID()
    end end
    S.NewLine();heading(v,'Basic lands','land',content,v.r.colors.accent)
    local basics=draft.basicLands or((m.roomCapabilities or {}).draft or {}).basicLands or {}
    for index,land in ipairs(basics)do
        local name=type(land)=='table'and land.name or land;local symbol=type(land)=='table'and land.manaSymbol or 'land'
        local count=deck.basics[name]or 0
        S.PushID('basic-'..index)
        S.Image('symbol',{Image=v.r.assets:iconImage(symbol or'land',18),W=18,H=18});S.SameLine();S.Textf(name,{W=content-142});S.SameLine()
        if button(v,'Remove basic','minus',28,26,{Disabled=locked or count==0,Tooltip='Remove one '..name})then m:setDraftBasic(name,count-1)end
        S.SameLine()
        if S.Input('basic-count-'..index,{Text=tostring(count),W=42,H=26,NumbersOnly=true,NoDrag=true,MinNumber=0,MaxNumber=250,Align='center',ReadOnly=locked,Tooltip='Number of '..name})then
            local value=tonumber(S.GetInputText());if value then m:setDraftBasic(name,value)end
        end
        S.SameLine()
        if button(v,'Add basic','plus',28,26,{Disabled=locked or count>=250,Tooltip='Add one '..name})then m:setDraftBasic(name,count+1)end
        S.PopID()
    end
    if #basics==0 then S.Textf('Basic-land choices are provided by XMage.',{W=content,Color=v.r.colors.muted})end
    S.NewLine();errors(v,m.roomDraftValidation,content)
    if deck.dirty and(draft.selection or draft.deck)then S.Textf('Local changes are not submitted yet. The last submitted deck remains active.',{W=content,Color=v.r.colors.gold})end
    S.Textf('All unselected drafted cards remain in your sideboard. XMage checks the submitted deck.',{W=content,Color=v.r.colors.muted})
    S.EndListBox();S.NewLine()
    local accepted=draft.selection or draft.deck
    local submitLabel=accepted and(deck.dirty and'Submit changes'or'Deck submitted')or'Submit deck'
    if button(v,submitLabel,'check',width,37,{Disabled=locked or(accepted and not deck.dirty)})then m:submitDraftDeck()end
    S.EndWindow()
end
function UI.build(v,w,h)
    local S,m=v.S,v.m;local draft=m.roomDraft;local after=draft and(draft.status=='building'or draft.status=='ready'or draft.status=='competing'or draft.status=='completed');local l=UI.layout(w,h,after)
    v:window('draft-title',26,100,w-52,42)
    if draft and(draft.status=='competing'or draft.status=='completed')then
        heading(v,'Limited tournament · round '..tostring((draft.tournament or {}).round or 0),'players',w-90,v.r.colors.accent)
    elseif draft and(draft.status=='building'or draft.status=='ready')then
        heading(v,draft.status=='ready'and'Draft complete · decks submitted'or'Draft complete · build your deck','library',w-90,v.r.colors.accent)
    elseif draft then
        heading(v,'Draft · pack '..tostring(draft.packNumber or '?')..' / '..tostring(draft.packCount or '?'),'pack',w-90,v.r.colors.accent)
    else heading(v,'Draft','pack',w-90,v.r.colors.accent)end
    S.EndWindow()
    if not draft then
        v:window('draft-unavailable',l.main.x,l.main.y,l.main.w,l.main.h)
        S.Textf(m.roomError or 'The native draft is preparing your seat…',{W=l.main.w-32,Color=v.r.colors.muted});S.EndWindow()
    elseif after then building(v,draft,l)
    else picking(v,draft,l)end
    v:window('draft-footer',l.footer.x,l.footer.y,l.footer.w,l.footer.h)
    if button(v,'Room','network',120,30)then m:showRooms()end;S.SameLine()
    local room=m.room or {};local host=room.hostId==m.roomParticipantId
    if host and room.phase=='building'and room.canStart then if button(v,'Start round','play',155,30,{Disabled=m.roomBusy or(m.roomDraftDeck and m.roomDraftDeck.dirty)})then m:startRoom()end;S.SameLine()end
    if host and room.canNextRound then if button(v,'Next round','next',155,30,{Disabled=m.roomBusy})then m:nextRoomRound()end;S.SameLine()end
    local status=draft and(draft.status=='ready'and'Deck submitted · waiting for the table'or draft.status=='building'and'Build your limited deck'or draft.status=='drafting'and'Only your current pack and picks are visible'or draft.status)or'Waiting for XMage'
    if m.roomDraftDeck and m.roomDraftDeck.dirty and draft and(draft.selection or draft.deck)then status='Local changes · submit changes to update your accepted deck'end
    if m.roomBusy then status='Waiting for the native draft…'end
    S.Textf(m.roomError or status,{W=l.footer.w-165,Color=m.roomError and v.r.colors.gold or v.r.colors.muted})
    S.EndWindow()
end
return UI
