-- Image browsing for the current entitled zone projection. Visibility and
-- prompt actionability remain separate; this module grants no permissions.
local Choices=require('app.card_choices')
local Presentation=require('app.card_presentation')
local UI={}
local function visible(card)return type(card)=='table'and not card.hidden and not card.faceDown end
function UI.details(card)
    if not visible(card)then return'Face-down card'end
    local lines={tostring(card.name or card.label or'Card')};local context=card.faceDownContext
    if context then lines[#lines+1]='Face-down battlefield · native P/T '..tostring(context.nativePT or'unknown')..' · '..tostring(context.damage or 0)..' damage marked'
    else local stats=Presentation.stats(card);if stats then lines[#lines+1]=stats.label end end
    if card.tapped then lines[#lines+1]='Tapped'end
    local names={};for name,count in pairs(card.counters or{})do if tonumber(count)and tonumber(count)~=0 then names[#names+1]=name end end;table.sort(names)
    for _,name in ipairs(names)do lines[#lines+1]=tostring(name)..' '..tostring(card.counters[name])end
    return table.concat(lines,'\n')
end
function UI.entries(zone,query)
    local out={};query=tostring(query or''):lower()
    for index,original in ipairs(zone.cards or{})do
        local card=Presentation.peek(original)
        local name=visible(card)and tostring(card.name or card.label or'Card')or'Face-down card'
        if query==''or name:lower():find(query,1,true)or(visible(card)and tostring(card.id or''):lower():find(query,1,true))then out[#out+1]={card=card,index=index,name=name,visible=visible(card)}end
    end
    return out
end
function UI.build(v,w,h)
    local m,S=v.m,v.S;local zone=m.zoneView;if not zone then return end
    if not v.zoneUiOpening or v.zoneUiOpening.zone~=zone then v.zoneUiOpening={zone=zone,waiting=true}end
    local opening=v.zoneUiOpening
    if opening.waiting then
        if love.mouse.isDown(1)then opening.released=nil
        elseif opening.released then opening.waiting=false
        else opening.released=true end
    end
    -- A field/count button can open this large grid beneath the same pointer.
    -- Consume that complete opening gesture before its images accept clicks.
    local ready=not opening.waiting
    local pw,ph=math.min(1040,w-70),math.min(680,h-135)
    v:window('zone-view',(w-pw)/2,math.max(72,(h-ph)/2),pw,ph,zone.label or'Cards',{BgColor={.025,.04,.06,.98}})
    local inner=select(1,S.GetWindowSize())-42
    if S.Button('Close zone',{W=inner,H=30,Disabled=not ready})then m.zoneView=nil;S.EndWindow();return end
    S.NewLine()
    S.Textf(zone.libraryPlayerId and'Only the visible top card is shown. Choose a highlighted card to play it, or right-click for details.'or'Choose a highlighted card for the current action. Right-click any visible card for details.',{W=inner,Color=v.r.colors.muted});S.NewLine()
    if S.Input('zone-search',{Text=zone.query or'',W=inner,H=34,Align='left',ReadOnly=not ready,Tooltip='Find a visible card by name or native object ID'})then zone.query=S.GetInputText();zone.offset=0 end
    S.NewLine()
    local cw,ch=112,157;local listH=math.max(100,ph-202);local cols=math.max(1,math.floor((inner-20)/(cw+12)))
    local rows=math.max(1,math.floor(listH/(ch+12)));local pageSize=math.min(24,cols*rows)
    local entries=UI.entries(zone,zone.query);zone.offset=math.max(0,math.min(zone.offset or 0,math.max(0,math.floor((#entries-1)/pageSize)*pageSize)))
    if S.Button('Previous cards',{W=140,H=28,Disabled=not ready or zone.offset==0})then zone.offset=math.max(0,zone.offset-pageSize)end
    S.SameLine();if S.Button('Next cards',{W=140,H=28,Disabled=not ready or zone.offset+pageSize>=#entries})then zone.offset=zone.offset+pageSize end
    S.SameLine();S.Text((#entries==0 and'0'or(zone.offset+1)..'–'..math.min(#entries,zone.offset+pageSize))..' / '..#entries);S.NewLine()
    S.BeginListBox('zone-card-grid',{W=inner,H=listH})
    for position=zone.offset+1,math.min(#entries,zone.offset+pageSize)do
        local entry=entries[position];local card=entry.card;local index=position-zone.offset
        if(index-1)%cols~=0 then S.SameLine({Pad=8})elseif index>1 then S.NewLine()end
        S.PushID('zone-card-'..tostring(card.id or entry.index))
        local actionable=entry.visible and not m.replay and m:canSelect(card.id)
        local selected=S.Button(entry.name,{W=cw,H=ch,Image={Image=Choices.cardImage(v,card,cw,ch)},Active=actionable,Disabled=not ready or not entry.visible or m.actionBusy,Tooltip=UI.details(card)..(actionable and'\nAvailable for this action'or'\nRight-click to inspect')})
        if ready and entry.visible and S.IsControlHovered()then m.choiceHover={card=card};if S.IsMouseClicked(2)then
            if zone.libraryPlayerId then m:inspectLibraryTop(zone.libraryPlayerId,card.id,zone.libraryGameId)else m.inspectCard=card end
        end end
        S.PopID()
        if selected then
            if actionable and m:selectCard(card)then m.zoneView=nil
            elseif zone.libraryPlayerId then m:inspectLibraryTop(zone.libraryPlayerId,card.id,zone.libraryGameId)
            else m.previewCard=card;m.inspectCard=card end
            break
        end
    end
    if#entries==0 then S.Text(#(zone.cards or{})==0 and(zone.libraryPlayerId and'The top card is not currently visible.'or'This zone is empty.')or'No matching cards.',{Color=v.r.colors.muted})end
    S.EndListBox();S.EndWindow()
end
return UI
