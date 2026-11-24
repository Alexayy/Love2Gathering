-- Read-only details for an entitled game object or catalog card.
local json=require('lib.json')
local Rich=require('app.richtext')
local Presentation=require('app.card_presentation')
local Choices=require('app.card_choices')
local Keywords=require('app.keywords')
local Mechanics=require('app.mechanic_fx')
local Window=require('lib.Slab.Internal.UI.Window')
local Region=require('lib.Slab.Internal.UI.Region')
local UI={}

local function text(value)
    if type(value)=='string' or type(value)=='number' then return tostring(value) end
    if type(value)=='table' and value~=json.null then return table.concat(value,'\n') end
    return ''
end

local function inspectRelated(m,card,context)
    if m.page=='table' then m:inspectTableCard(card,context)
    else m.inspectCard=Presentation.peek(card) end
end

local function currentState(v,object,width)
    local S,C=v.S,v.r.colors
    local stats=Presentation.stats(object)
    local context=object.faceDownContext
    if context then
        local label
        if object.zone=='EXILED' then label='Face-down in exile · private identity'
        elseif object.zone and object.zone~='BATTLEFIELD' then label='Face-down card · private identity'
        else label='Face-down on the battlefield'..(context.nativePT and ' · native P/T '..context.nativePT or '')..' · '..tostring(context.damage or 0)..' damage marked' end
        S.Textf(label,{W=width,Color=C.gold})
    elseif stats then
        S.Textf(v.m.page=='table' and stats.label or 'Power / toughness · '..stats.native,{W=width,Color=C.gold})
    end
    local counters=Presentation.counterSummary(object)
    if counters~='' then S.Textf('Counters · '..counters,{W=width,Color=C.gold}) end
    local status={}
    if object.zone then status[#status+1]=text(object.zone):lower():gsub('^%l',string.upper) end
    if object.tapped then status[#status+1]='Tapped' end
    if object.attacking then status[#status+1]='Attacking' end
    if object.blocking then status[#status+1]='Blocking' end
    for _,player in ipairs(v.m.game and v.m.game.players or {}) do
        if player.id==object.controllerId then status[#status+1]='Controlled by '..player.name end
        if player.id==object.ownerId and player.id~=object.controllerId then status[#status+1]='Owned by '..player.name end
    end
    if #status>0 then S.Textf(table.concat(status,' · '),{W=width,Color=C.muted}) end
end

local function abilities(v,object,width)
    local profiles=Mechanics.cardProfiles(object)
    if #profiles==0 then return end
    local S,C=v.S,v.r.colors
    S.Separator();S.Text('Mechanics and current abilities',{Color=C.gold})
    for _,entry in ipairs(profiles) do
        local label=entry.label:gsub('^%l',string.upper)
        local color=entry.gained and C.gold or C.text
        if entry.icon then
            S.Image('mechanic-icon-'..entry.id,{Image=v.r.assets:iconImage(entry.icon,20,color),W=20,H=20})
            S.SameLine({CenterY=true})
        end
        if entry.gained then S.Text(label..' · granted',{Color=color})
        else S.Textf(label,{W=width-(entry.icon and 28 or 0),Color=color}) end
        if entry.parameter and entry.parameter:lower()~=entry.label:lower() then
            Rich.slab(v,'mechanic-details-'..entry.id,entry.parameter,width,{size=14,color=C.muted})
        end
    end
end

local function relationships(v,object,width)
    local S,m,C=v.S,v.m,v.r.colors
    local merged=object.mutate
    if merged and type(merged.components)=='table' and #merged.components>0 then
        S.Separator();S.Text('Mutate components · '..#merged.components,{Color=C.gold})
        local selected
        for index,component in ipairs(merged.components) do
            local key=tostring(component.id or index)
            local label=(component.id==merged.topId and 'Top · ' or 'Component · ')..text(component.name)
            S.PushID('mutate-component-'..key)
            if S.TextSelectable(label,{Selected=v.inspectMutateComponentId==key,Tooltip='Inspect this component’s original printing.'}) then v.inspectMutateComponentId=key end
            S.PopID()
            if v.inspectMutateComponentId==key then selected=component end
        end
        if selected then
            local printed=selected.printing or selected
            S.Textf('Component printing · '..text(selected.name),{W=width,Color=C.accent})
            local stats=Presentation.stats(printed)
            if stats then S.Text('Printed '..stats.native,{Color=C.muted}) end
            local image=not selected.hidden and m:getArt(selected,true)
            if image then S.Image('mutate-component-art',{Image=image,W=180,H=180*image:getHeight()/image:getWidth()}) end
        end
    end
    local attached=(v.r.boardAttached or {})[object.id] or {}
    if #attached>0 then S.Separator();S.Text('Attached cards',{Color=C.gold}) end
    for _,entry in ipairs(attached) do
        S.PushID(tostring(entry.id))
        if S.TextSelectable(text(entry.name)) then inspectRelated(m,entry) end
        S.PopID()
    end
    for _,entry in ipairs(object.linkedExile or {}) do
        S.PushID(tostring(entry.id))
        if S.TextSelectable('Exiled here · '..(entry.hidden and 'Face-down card' or text(entry.name))) and not entry.hidden then
            inspectRelated(m,entry,{linkedHostId=object.id})
        end
        S.PopID()
    end
end

local function details(v,object,data,width,hidden)
    local S,C=v.S,v.r.colors
    if hidden then currentState(v,object,width);return end
    local stack=v.m.tableDetailSource and v.m:tableStackEntry(v.m.tableDetailSource)
    if stack and text(stack.rules)~='' then
        S.Text(stack.kind=='spell' and 'Spell on the stack' or 'Ability on the stack',{Color=C.gold})
        Rich.slab(v,'inspected-stack-rule',stack.rules,width,{size=16,color=C.text})
        S.Separator()
    end
    local face=data.card_faces and data.card_faces[(tonumber(data.requested_face) or 0)+1]
    if face and face.name~=object.name then face=nil end
    local printed=object.printing or {}
    local printedType=text(face and face.type_line or data.type_line or printed.type_line)
    local typeLine=printedType
    if object.currentRules~=nil or object.zone=='BATTLEFIELD' or printedType=='' then
        local currentType=Presentation.currentTypeLine(object)
        if currentType~='' then typeLine=currentType end
    end
    if typeLine~='' then S.Textf(typeLine,{W=width,Color=C.text}) end
    Rich.slab(v,'inspected-cost',Presentation.manaCost(object,face or data),width,{size=20,color=C.gold})
    currentState(v,object,width)
    local current=text(object.currentRules)
    if current~='' then
        if S.Button(v.inspectCurrentRules and 'Hide current rules' or 'Show current rules',{W=width,H=32}) then v.inspectCurrentRules=not v.inspectCurrentRules end
        if v.inspectCurrentRules then Rich.slab(v,'inspected-current-rules',current,width,{size=16,color=C.gold}) end
    end
    local rules=text(face and face.oracle_text or data.oracle_text or object.rules)
    if rules~='' and (rules~=current or not v.inspectCurrentRules) then
        S.Separator();S.Text(data.oracle_text and 'Oracle text' or 'Rules text',{Color=C.muted})
        Rich.slab(v,'inspected-rules',Keywords.annotate(rules,v.m.settings.keywordReminders),width,{size=16,color=C.text})
    end
    abilities(v,object,width)
    local printing={}
    if object.zone=='BATTLEFIELD' and printedType~='' and typeLine~='' and
            printedType:gsub(' — ',' · ')~=typeLine then
        printing[#printing+1]='Printed type · '..printedType
    end
    local nativeSet=text(printed.set or (object.currentRules and object.set)):upper()
    local nativeNumber=text(printed.number or (object.currentRules and object.number))
    local scanSet,scanNumber
    local selected=text(object.selectedPrintingId)
    if (selected=='' or selected==data.printing_id) and (not data.printingExact or data.printingResolved~=false) then
        scanSet=text(data.set):upper();scanNumber=text(data.collector_number)
        local edition=text(data.set_name)
        if edition=='' then edition=scanSet end
        local number=scanNumber
        if not data.printing_id then
            if edition=='' then edition=nativeSet end
            if number=='' then number=nativeNumber end
        end
        local artist=text(face and face.artist or data.artist)
        if edition~='' then printing[#printing+1]=edition end
        if number~='' then printing[#printing+1]='#'..number end
        if artist~='' then printing[#printing+1]='Art by '..artist end
    end
    local printedStats=Presentation.stats(printed)
    if printedStats then printing[#printing+1]='Printed P/T '..printedStats.native end
    if text(data.loyalty)~='' then printing[#printing+1]='Loyalty '..text(data.loyalty) end
    if text(data.defense)~='' then printing[#printing+1]='Defense '..text(data.defense) end
    if #printing>0 then S.Separator();S.Text('Printing',{Color=C.gold});S.Textf(table.concat(printing,' · '),{W=width,Color=C.text}) end
    if nativeSet~='' and (selected~='' or data.printing_id) and (nativeSet~=scanSet or nativeNumber~=scanNumber) then
        S.Textf('XMage printing · '..nativeSet..(nativeNumber~='' and ' #'..nativeNumber or ''),{W=width,Color=C.muted})
    end
    relationships(v,object,width)
end

function UI.build(v,w,h)
    local S,m,C=v.S,v.m,v.r.colors
    local object=Presentation.peek(m.inspectCard)
    local hidden=object.hidden or object.faceDown
    local data=hidden and {} or m:cardData(object) or object
    local key=table.concat({m.page,tostring(m.game and m.game.gameId),tostring(object.id or object.name),tostring(object.faceDownContext~=nil),tostring(hidden==true),tostring(data.requested_face or 0)},':')
    local pw,ph=math.min(1030,w-56),math.min(800,h-78)
    v:window('inspect-card',(w-pw)/2,(h-ph)/2-8,pw,ph,'Card details',{AutoSizeContent=false,BgColor={.025,.04,.06,.99}})
    if v.inspectKey~=key then
        Region.ResetTransform(Window.GetItemId('card-details-text'))
        v.inspectKey=key;v.inspectCurrentRules=false;v.inspectMutateComponentId=nil
    end
    local x,y=S.GetCursorPos({Absolute=true})
    local inner=pw-18
    if not hidden and m.page=='table' and m:prompt() then
        if S.Button('Actions / ways to play',{W=192,H=32}) then
            require('app.card_actions').open(m,object);m:closeTableInspection();v.inspectKey=nil;S.EndWindow();return
        end
    end
    S.SetCursorPos(x+inner-130,y,{Absolute=true})
    if S.Button('Close details',{W=130,H=32}) then m:closeTableInspection();v.inspectKey=nil;S.EndWindow();return end
    local bodyY=y+43
    local bodyH=ph-76
    local image
    if hidden then image=Choices.cardImage(v,{hidden=true},150,210)
    else image=m:getArt(object,true) end
    local imageW=0
    if image then
        local ratio=image:getWidth()/image:getHeight()
        imageW=math.floor(math.min(inner*.47,bodyH*ratio))
        local imageH=imageW/ratio
        S.SetCursorPos(x,bodyY+(bodyH-imageH)/2,{Absolute=true})
        S.Image('inspected-art',{Image=image,W=imageW,H=imageH})
    end
    local indent=image and imageW+22 or 0
    local listWidth=inner-indent
    local contentWidth=listWidth-24
    S.Indent(indent);S.SetCursorPos(x+indent,bodyY,{Absolute=true})
    S.BeginListBox('card-details-text',{W=listWidth,H=bodyH,ScrollStep=64,BgColor={.032,.049,.07,1}})
    S.Indent(6)
    S.PushFont(v.r.assets:titleFont(22,m.settings))
    S.Textf(hidden and (object.faceDown and 'Face-down card' or 'Hidden card') or text(object.name or data.name),{W=contentWidth,Color=C.accent})
    S.PopFont()
    if not image and not hidden and m.artworkLabel then S.Textf(m:artworkLabel(object),{W=contentWidth,Color=C.muted}) end
    details(v,object,data,contentWidth,hidden)
    S.Unindent(6);S.EndListBox();S.Unindent(indent);S.EndWindow()
end
return UI
