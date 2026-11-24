-- Image browsing for the current entitled zone projection. Visibility and
-- prompt actionability remain separate; this module grants no permissions.
local Choices=require('app.card_choices')
local Presentation=require('app.card_presentation')
local Actions=require('app.card_actions')
local UI={}
local function visible(card)return type(card)=='table'and not card.hidden and not card.faceDown end
function UI.details(card)
    if not visible(card)then return'Face-down card'end
    local lines={tostring(card.name or card.label or'Card')};local context=card.faceDownContext
    if context and card.zone and card.zone~='BATTLEFIELD'then lines[#lines+1]=card.zone=='EXILED'and'Face-down in exile · private identity'or'Face-down card · private identity'
    elseif context then lines[#lines+1]='Face-down battlefield · native P/T '..tostring(context.nativePT or'unknown')..' · '..tostring(context.damage or 0)..' damage marked'
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
        if query==''or name:lower():find(query,1,true)or(visible(card)and tostring(card.id or''):lower():find(query,1,true))then out[#out+1]={original=original,card=card,index=index,name=name,visible=visible(card)}end
    end
    return out
end
function UI.build(v,w,h)
    v.zoneCardHits={};v.r.zoneCardRects={}
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
    v.zonePanelRect={x=(w-pw)/2,y=math.max(72,(h-ph)/2),w=pw,h=ph}
    v:window('zone-view',(w-pw)/2,math.max(72,(h-ph)/2),pw,ph,zone.label or'Cards',{BgColor={.025,.04,.06,.98}})
    local inner=select(1,S.GetWindowSize())-42
    if S.Button('Close zone',{W=inner,H=30,Disabled=not ready})then m.zoneView=nil;S.EndWindow();return end
    S.NewLine()
    S.Textf((zone.libraryPlayerId and'Only the visible top card is shown. 'or'')..'Choose a highlighted card for the current action. Right-click to pin its preview. Middle-click for details.',{W=inner,Color=v.r.colors.muted});S.NewLine()
    if S.Input('zone-search',{Text=zone.query or'',W=inner,H=34,Align='left',ReadOnly=not ready,Tooltip='Find a visible card by name or native object ID'})then zone.query=S.GetInputText();zone.offset=0 end
    S.NewLine()
    local cw,ch=112,157;local listH=math.max(100,ph-202);local cols=math.max(1,math.floor((inner-20)/(cw+12)))
    local rows=math.max(1,math.floor(listH/(ch+12)));local pageSize=math.min(24,cols*rows)
    local entries=UI.entries(zone,zone.query);zone.offset=math.max(0,math.min(zone.offset or 0,math.max(0,math.floor((#entries-1)/pageSize)*pageSize)))
    if S.Button('Previous cards',{W=140,H=28,Disabled=not ready or zone.offset==0})then zone.offset=math.max(0,zone.offset-pageSize)end
    S.SameLine();if S.Button('Next cards',{W=140,H=28,Disabled=not ready or zone.offset+pageSize>=#entries})then zone.offset=zone.offset+pageSize end
    S.SameLine();S.Text((#entries==0 and'0'or(zone.offset+1)..'–'..math.min(#entries,zone.offset+pageSize))..' / '..#entries);S.NewLine()
    local Window=require('lib.Slab.Internal.UI.Window')
    local gridX,gridY=Window.TransformPoint(S.GetCursorPos({Absolute=true}))
    v.zoneGridRect={x=gridX,y=gridY,w=inner,h=listH}
    local promptKey=Choices.promptKey(m,m:prompt())
    S.BeginListBox('zone-card-grid',{W=inner,H=listH})
    for position=zone.offset+1,math.min(#entries,zone.offset+pageSize)do
        local entry=entries[position];local card=entry.card;local index=position-zone.offset
        if(index-1)%cols~=0 then S.SameLine({Pad=8})elseif index>1 then S.NewLine()end
        S.PushID('zone-card-'..tostring(card.id or entry.index))
        local actionable=entry.visible and not m.replay and not m.roomDisconnected and m:canSelect(card.id)
        local rawX,rawY=S.GetCursorPos({Absolute=true});local x,y=Window.TransformPoint(rawX,rawY)
        local hit={x=x,y=y,w=cw,h=ch,card=card,ready=ready,available=actionable,zone=zone,promptKey=promptKey};v.zoneCardHits[#v.zoneCardHits+1]=hit
        v.r.zoneCardRects[card.id]=hit
        local selected=S.Button(entry.name,{W=cw,H=ch,Image={Image=Choices.cardImage(v,card,cw,ch)},Active=actionable,Disabled=not ready or not entry.visible or m.actionBusy or m.roomDisconnected,Tooltip=UI.details(card)..(actionable and'\nAvailable now · click or drag out to play'or'')})
        if actionable then
            local draw=require('lib.Slab.Internal.Core.DrawCommands')
            -- Queue the frame with Slab so clipping/scaling matches the image.
            draw.Rectangle('line',rawX+1,rawY+1,cw-2,ch-2,v.r.colors.accent,3,10,3)
            draw.Rectangle('fill',rawX+5,rawY+27,45,21,{.025,.06,.05,.96},3)
            draw.Print('PLAY',rawX+10,rawY+29,v.r.colors.accent,v.r.fonts[12])
        end
        if ready and entry.visible and S.IsControlHovered()then Choices.hoverCard(v,entry.original,{zone=zone}) end
        S.PopID()
        -- Playable cards submit only through the fenced press/release below.
        if selected and not actionable then
            m:pinTableCard(entry.original,{zone=zone})
            break
        end
    end
    if#entries==0 then S.Text(#(zone.cards or{})==0 and(zone.libraryPlayerId and'The top card is not currently visible.'or'This zone is empty.')or'No matching cards.',{Color=v.r.colors.muted})end
    S.EndListBox();S.EndWindow()
end
local function contains(box,x,y)return box and x>=box.x and x<=box.x+box.w and y>=box.y and y<=box.y+box.h end
function UI.press(v,x,y,button)
    local m=v.m;if button~=1 or v.inputLock~='zone-view' or not m.zoneView or m.actionBusy or m.replay or m.roomDisconnected or not contains(v.zoneGridRect,x,y)then return false end
    local key=Choices.promptKey(m,m:prompt())
    for i=#(v.zoneCardHits or{}),1,-1 do local hit=v.zoneCardHits[i]
        if hit.ready and hit.available and hit.zone==m.zoneView and hit.promptKey==key and contains(hit,x,y)then
            v.zoneDrag={hit=hit,x=x,y=y,startX=x,startY=y};return true
        end
    end
    return false
end
function UI.move(v,x,y)
    local drag=v.zoneDrag;if not drag then return false end
    drag.x=x;drag.y=y;drag.moved=drag.moved or math.abs(x-drag.startX)+math.abs(y-drag.startY)>6;return true
end
function UI.release(v,x,y,button)
    local drag=v.zoneDrag;if button~=1 or not drag then return false end
    v.zoneDrag=nil;local m=v.m
    if v.inputLock~='zone-view' or m.zoneView~=drag.hit.zone or m.roomDisconnected or m.replay or Choices.promptKey(m,m:prompt())~=drag.hit.promptKey then return true end
    if not drag.moved or not contains(v.zonePanelRect,x,y)then
        if Actions.select(m,drag.hit.card)and not m.cardActionSheet then m.zoneView=nil end
    end
    return true
end
function UI.ghost(v)
    local drag=v.zoneDrag;if not drag or not drag.moved or v.m.roomDisconnected then return end
    v.r:drawCard(drag.hit.card,drag.x-50,drag.y-70,100,140,{noHit=true,kind='zone-drag'})
end
return UI
