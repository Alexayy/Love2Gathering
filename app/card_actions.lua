-- One viewer's current native offers. These records never grant permissions.
local json=require('lib.json')
local Rich=require('app.richtext')
local Presentation=require('app.card_presentation')
local Actions={}
local function list(value)return type(value)=='table'and value~=json.null and value or{}end
local function prompt(m)return not m.replay and m.prompt and m:prompt()or nil end
function Actions.record(m,card)
    local current=prompt(m);if not current or type(card)~='table'or card.hidden then return nil end
    for _,record in ipairs(list(current.cardActions))do if tostring(record.objectId)==tostring(card.id)and m:canSelect(card.id)then return record end end
end
function Actions.options(m,card)local record=Actions.record(m,card);return record and list(record.options)or{}end
function Actions.state(m,card)
    if type(card)~='table'or card.hidden then return{status='unknown',available=false,options={},count=0}end
    local current=prompt(m);local record=Actions.record(m,card);local options=record and list(record.options)or{}
    local available=current and m:canSelect(card.id)or false
    return{status=available and'available'or(current and'unavailable'or'unknown'),available=available,
        sourceZone=record and record.sourceZone or card.zone,options=options,count=#options,
        mechanics=list(card.mechanicCapabilities or card.currentKeywords),detailsKnown=record~=nil}
end
function Actions.extension(m)
    local out,seen={},{};if not prompt(m)then return out end
    for _,player in ipairs(list(m.game and m.game.players))do for _,card in ipairs(list(player.exile))do
        local record=Actions.record(m,card)
        local display=Presentation.peek(card)
        if record and record.sourceZone=='EXILED'and not display.hidden and not display.faceDown and not seen[card.id]then out[#out+1]=display;seen[card.id]=true end
    end end
    return out
end
function Actions.open(m,card)
    if not card or card.hidden then return false end
    local current=prompt(m)
    m.cardActionSheet={card=card,objectId=card.id,gameId=m.game and m.game.gameId,promptId=current and current.id}
    return true
end
function Actions.select(m,card)
    if not prompt(m)or m.roomDisconnected or m.actionBusy or m.priorityBusy or not m:canSelect(card.id)then return false end
    if #Actions.options(m,card)>1 then return Actions.open(m,card)end
    return Actions.commit(m,card)
end
function Actions.commit(m,card)
    if not prompt(m)or m.roomDisconnected or m.actionBusy or m.priorityBusy or not m:canSelect(card.id)then return false end
    return m:selectCard(card)
end
function Actions.build(v,w,h)
    local m,S=v.m,v.S;local sheet=m.cardActionSheet;if not sheet then return false end
    if sheet.gameId~=(m.game and m.game.gameId)or m.replay then m.cardActionSheet=nil;return false end
    local current=prompt(m);local state=Actions.state(m,sheet.card)
    -- A new native decision cannot be answered with this sheet's old IDs.
    local fresh=current and current.id==sheet.promptId
    local pw=math.min(720,w-60);local ph=math.min(h-110,260+math.min(4,#state.options)*78)
    v:window('native-card-actions',(w-pw)/2,math.max(72,(h-ph)/2),pw,ph,'Card actions',{Layer='ContextMenu',BgColor={.025,.04,.06,.99}})
    local inner=select(1,S.GetWindowSize())-42
    S.Text(sheet.card.name or'Card',{Color=v.r.colors.text});S.NewLine()
    S.Text('Source zone: '..tostring(state.sourceZone or'Native object')..' · '..(fresh and state.available and'Available now'or'No current native offer'),{Color=state.available and v.r.colors.accent or v.r.colors.muted});S.NewLine()
    S.BeginListBox('native-action-details',{W=inner,H=math.max(65,ph-178)})
    if#state.options==0 then S.Textf('Inspect the card for its printed mechanics. XMage offers actions only at the appropriate timing and with the required resources.',{W=inner-22,Color=v.r.colors.muted})end
    for index,option in ipairs(state.options)do
        S.PushID('native-action-option-'..index)
        S.Textf(tostring(option.label or option.kind or'Native action'),{W=inner-22,Color=v.r.colors.text});S.NewLine()
        local costs={};if option.manaCost and option.manaCost~=''then costs[#costs+1]=option.manaCost end
        for _,cost in ipairs(list(option.otherCosts))do if cost~=''then costs[#costs+1]=cost end end
        Rich.slab(v,'native-option-cost','Cost before choices: '..(#costs>0 and table.concat(costs,' · ')or'Native choice')..(option.requiresTargets and' · Targets required'or''),inner-22,{size=14,color=v.r.colors.muted,maxLines=3});S.NewLine()
        if option.costFinal==false then S.Textf(option.costNote or'XMage confirms optional costs, targets and final payment after selection.',{W=inner-22,Color=v.r.colors.muted});S.NewLine()end
        S.PopID()
    end
    S.EndListBox();S.NewLine()
    if S.Button('Choose this object',{W=inner*.58,H=38,Disabled=not fresh or not state.available or m.actionBusy or m.roomDisconnected,Tooltip='Select the current native object. XMage then asks for any ability, mode, target, extra cost or payment choices.'})then
        if Actions.commit(m,sheet.card)then m.cardActionSheet=nil;m.zoneView=nil end
    end
    S.SameLine();if S.Button('Close actions',{W=inner*.38,H=38})then m.cardActionSheet=nil end
    S.EndWindow();return true
end
return Actions
