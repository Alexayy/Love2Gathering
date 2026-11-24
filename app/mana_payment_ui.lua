local RichText=require('app.richtext')
local CardChoices=require('app.card_choices')
local Window=require('lib.Slab.Internal.UI.Window')
local Region=require('lib.Slab.Internal.UI.Region')

local UI={}

local function button(v,promptKey,choice,label,width,height,visible,sourceDisabled,options)
    local S,m=v.S,v.m
    options=options or {}
    S.PushID(promptKey..':'..tostring(choice.id))
    local description=options.name or choice.label or 'Pay mana'
    if type(choice.manaColor)=='string' then description=description..' · '..choice.manaColor end
    if visible==false then
        S.Button(description,{W=width,H=height,Invisible=true,Disabled=true})
    elseif RichText.button(v,description,label,width,{height=height,size=14,maxLines=options.lines or 1,
            tooltip=options.tooltip or description,disabled=m.actionBusy or m.priorityBusy or m.roomDisconnected or sourceDisabled or choice.selectable==false}) then
        m:answerChoice(choice)
    end
    local hovered=visible~=false and S.IsControlHovered()
    S.PopID()
    return hovered
end

local function symbols(colors)
    local tokens={}
    for _,color in ipairs(colors or {}) do tokens[#tokens+1]='{'..color..'}' end
    return table.concat(tokens)
end

local function optionWidth(choice)
    local count=#(choice.manaColors or {})
    return count==0 and 78 or math.max(44,24+count*18)
end

local function sourceLabels(sources,players,playerId)
    local names,numbers,counts={},{},{}
    for _,source in ipairs(sources) do names[source.label or 'Mana source']=true end
    local function record(id,name)
        if id and names[name] and not numbers[id] then
            counts[name]=(counts[name] or 0)+1
            numbers[id]=counts[name]
        end
    end
    -- The board also contains tapped copies that may disappear from the next
    -- payment prompt. Keep the remaining copies numbered by that same order.
    for _,player in ipairs(players or {}) do
        if player.id==playerId or not playerId and (player.isLocal or player.human) then
            for _,card in ipairs(player.battlefield or {}) do
                if not card.hidden and not card.faceDown then record(card.id,card.name) end
            end
        end
    end
    for _,source in ipairs(sources) do record(source.value or source.id,source.label or 'Mana source') end
    local labels={}
    for _,source in ipairs(sources) do
        local id,name=source.value or source.id,source.label or 'Mana source'
        if counts[name]>1 then labels[id]=name..' ('..numbers[id]..')' end
    end
    return labels
end

function UI.build(v,w,h,prompt)
    if prompt.type~='play_mana' then return false end
    local S=v.S
    local promptKey=CardChoices.promptKey(v.m,prompt)
    local pool,sources,options,controls={},{},{},{}
    for _,choice in ipairs(prompt.choices or {}) do
        if choice.responseType=='mana' then
            pool[#pool+1]=choice
        elseif choice.responseType=='uuid' then
            sources[#sources+1]=choice
        elseif choice.responseType=='mana_source' then
            local source=options[choice.sourceId] or {}
            source[#source+1]=choice
            options[choice.sourceId]=source
        else
            controls[#controls+1]=choice
        end
    end

    local dockX,pw=require('app.layout').manaDock(w)
    local width=pw-32
    local rowHeight=36
    local listHeight=math.min(#sources*(rowHeight+5)+6,math.max(66,math.min(250,h*.31)))
    local height=(#pool>0 and 122 or 89)+listHeight+(#sources>0 and 48 or 0)+(#controls>0 and 54 or 0)
    -- Anchor clear of the center of the battlefield. The source cards there
    -- remain available to the ordinary exact-card click handler.
    v:window('mana-payment',dockX,math.max(148,h-height-94),pw,height,nil,
        {Title='Mana payment',AllowMove=false,BgColor={.035,.052,.074,.99}})
    RichText.slab(v,'payment-cost',prompt.message or '',width,{size=16,maxLines=2,color=v.r.colors.text})
    if #pool>0 then
        S.Text('Spend from mana pool',{Color=v.r.colors.accent})
        local x,y=S.GetCursorPos({Absolute=true})
        local poolWidth=math.min(78,math.floor((width-(#pool-1)*5)/#pool))
        for i,choice in ipairs(pool) do
            S.SetCursorPos(x+(i-1)*(poolWidth+5),y,{Absolute=true})
            local label=choice.manaSymbol and choice.manaCount and ('{'..choice.manaSymbol..'} ×'..choice.manaCount) or choice.label
            button(v,promptKey,choice,label,poolWidth,34)
        end
    else
        S.Text('No pool mana offered',{Color=v.r.colors.muted})
    end
    if #sources>0 then
        local hovered=v.manaRulePrompt==promptKey and v.manaRuleText
        RichText.slab(v,'mana-source-rule',hovered or 'Choose a mana source',width,
            {color=hovered and v.r.colors.text or v.r.colors.muted,size=14,minHeight=38,maxLines=2})
        v.manaRuleText=nil
        v.manaRulePrompt=promptKey
        local gameId=v.m.game and v.m.game.gameId
        local pending=prompt.pendingAction
        local casting=type(pending)=='table' and pending.sourceId
        if v.manaPaymentGame~=gameId or v.manaPaymentSource~=casting then
            Region.ResetTransform(Window.GetItemId('payment-sources'))
            v.manaPaymentGame,v.manaPaymentSource=gameId,casting
        end
        local x,y=S.GetCursorPos({Absolute=true})
        local _,listY=Window.TransformPoint(x,y)
        S.BeginListBox('payment-sources',{W=width,H=listHeight,ScrollStep=82})
        local labels=sourceLabels(sources,v.m.game.players,prompt.playerId)
        for _,source in ipairs(sources) do
            local sourceId=source.value or source.id
            local choices=options[sourceId] or {}
            local left=math.min(154,math.floor(width*.32))
            local right=width-left-28
            local rowX,rowY=S.GetCursorPos({Absolute=true})
            local _,screenY=Window.TransformPoint(rowX,rowY)
            local visible=screenY+rowHeight>=listY and screenY<=listY+listHeight
            local sourceDisabled=visible and (source.selectable==false or not v.m:canSelect(sourceId))
            local sourceName=labels[sourceId] or source.label
            local sourceInfo=labels[sourceId] and {name=sourceName,tooltip=sourceName..'\n'..tostring(sourceId)} or nil
            button(v,promptKey,source,sourceName,left,rowHeight,visible,sourceDisabled,sourceInfo)
            local total=0
            for _,choice in ipairs(choices) do total=total+optionWidth(choice)+4 end
            if total<=right then
                for _,choice in ipairs(choices) do
                    S.SameLine({Pad=4})
                    local label=symbols(choice.manaColors)
                    if button(v,promptKey,choice,label~='' and label or 'Choose',optionWidth(choice),rowHeight,visible,sourceDisabled) then
                        v.manaRuleText=choice.label
                    end
                end
            else
                local colors,seen={},{}
                for _,choice in ipairs(choices) do
                    for _,color in ipairs(choice.manaColors or {}) do
                        if not seen[color] then colors[#colors+1]=color;seen[color]=true end
                    end
                end
                S.SameLine({Pad=4})
                button(v,promptKey..':picker',source,'Choose '..symbols(colors),right,rowHeight,visible,sourceDisabled)
            end
        end
        S.EndListBox()
    end
    if #controls>0 then
        local x,y=S.GetCursorPos({Absolute=true})
        local controlWidth=math.floor((width-(#controls-1)*5)/#controls)
        for i,choice in ipairs(controls) do
            S.SetCursorPos(x+(i-1)*(controlWidth+5),y,{Absolute=true})
            button(v,promptKey,choice,choice.label,controlWidth,44,true,false,{lines=2})
        end
    end
    S.EndWindow()
    return true
end

return UI
