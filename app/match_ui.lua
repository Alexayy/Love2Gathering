local Layout=require('app.layout')
local RichText=require('app.richtext')
local Log=require('app.log')
local Window=require('lib.Slab.Internal.UI.Window')
local CardChoices=require('app.card_choices')
local Priority=require('app.priority')
local json=require('lib.json')
local UI={}
local function iconButton(v,label,icon,action,active,disabled,size)
    local S=v.S
    size=size or 38
    if S.Button(label,{Image={Image=v.r.assets:iconImage(icon,size-8)},W=size,H=size,Tooltip=label,Active=active,Disabled=disabled}) then action() end
end
local function option(v,promptKey,choice,width)
    local label=tostring(choice.label or choice.id)
    v.S.PushID(promptKey..':'..tostring(choice.id or choice.value or label))
    if RichText.button(v,label,label,width,{tooltip=choice.detail or label,
            disabled=v.m.actionBusy or v.m.roomDisconnected or v.m.priorityBusy or choice.selectable==false}) then
        v.m:answerChoice(choice)
    end
    v.S.PopID()
end
local function priorityControls(v,w,h,prompt)
    local S,m=v.S,v.m
    local endTurn=prompt.priority==true
    local pass=endTurn and Priority.passChoice(prompt)
    local choices={}
    for _,choice in ipairs(prompt.choices or {}) do
        if choice.responseType~='uuid' and choice~=pass then choices[#choices+1]=choice end
    end
    local gap,passWidth,endWidth=6,194,110
    local fixed=(pass and passWidth+gap or 0)+(endTurn and endWidth+gap or 0)
    local widthLimit=math.max(68,math.floor((w-40-fixed)/math.max(1,#choices))-gap)
    local widths,total={},fixed
    for i,choice in ipairs(choices) do
        local label=tostring(choice.label or choice.id)
        widths[i]=math.min(widthLimit,258,math.max(80,v.r.fonts[14]:getWidth(label)+24))
        total=total+widths[i]+gap
    end
    if total==0 then return end
    local width=total-gap
    v:window('priority-controls',w-width-20,h-59,width+2,46,nil,{Border=0,BgColor={0,0,0,0},AutoSizeContent=false})
    local key=CardChoices.promptKey(m,prompt)
    local disabled=m.actionBusy or m.roomDisconnected or m.priorityBusy
    local x,y=S.GetCursorPos({Absolute=true})
    local function place(buttonWidth)
        S.SetCursorPos(x,y,{Absolute=true})
        x=x+buttonWidth+gap
    end
    for i,choice in ipairs(choices) do
        place(widths[i])
        local label=tostring(choice.label or choice.id)
        S.PushID(key..':'..tostring(choice.id))
        if RichText.button(v,label,label,widths[i],{size=14,maxLines=1,height=42,disabled=disabled or choice.selectable==false}) then m:answerChoice(choice) end
        S.PopID()
    end
    if endTurn then
        place(endWidth)
        S.PushID(key)
        if S.Button('End Turn',{W=endWidth,H=42,Disabled=disabled,Tooltip='Yield priority until a configured stop'}) then m:endTurn() end
        S.PopID()
    end
    if pass then
        place(passWidth)
        S.PushID(key..':'..tostring(pass.id))
        local C=v.r.colors
        local ink=disabled and C.muted or {.12,.085,.035,1}
        local image=v.r.assets:buttonImage('play','Pass Priority   [Space]',passWidth,42,
            {font=v.r.fonts[16],iconSize=16,color=ink,iconTint=ink})
        if S.Button('Pass Priority',{Image={Image=image},W=passWidth,H=42,Disabled=disabled,
                Color=disabled and C.panel or C.gold,HoverColor={1,.84,.47,1},PressColor={.85,.59,.23,1},
                Tooltip=pass.label or 'Pass priority'}) then m:answerChoice(pass) end
        S.PopID()
    end
    S.EndWindow()
end
local function abilityChoices(v,w,h,prompt)
    local S,m=v.S,v.m;local choices=prompt.choices or{}
    local pw=math.min(520,w-48);local ph=math.min(380,h-130,92+#choices*48)
    local width=pw-32
    v:window('native-ability-choice',(w-pw)/2,math.max(116,(h-ph)/2),pw,ph,'Choose an action',{AllowMove=false})
    RichText.slab(v,'ability-prompt-message',prompt.message or'',width,{size=16,maxLines=2});S.NewLine()
    local promptKey=CardChoices.promptKey(m,prompt)
    if v.abilityPromptKey~=promptKey then
        require('lib.Slab.Internal.UI.Region').ResetTransform(Window.GetItemId('native-ability-choices'))
        v.abilityPromptKey=promptKey
    end
    S.BeginListBox('native-ability-choices',{W=width,H=ph-65})
    for _,choice in ipairs(choices)do
        local label=tostring(choice.label or choice.id)
        local text=label;local tooltip=label
        if type(choice.manaCost)=='string'and choice.manaCost~=''then
            text=text..'  '..choice.manaCost
            tooltip=tooltip..'\nMana cost before choices: '..choice.manaCost
        end
        if type(choice.detail)=='string'and choice.detail~=''then tooltip=tooltip..'\n'..choice.detail end
        S.PushID(promptKey..':'..tostring(choice.id))
        if RichText.button(v,label,text,width-18,{tooltip=tooltip,disabled=m.actionBusy or m.roomDisconnected or m.priorityBusy or choice.selectable==false})then m:answerChoice(choice)end
        S.PopID()
    end
    S.EndListBox();S.EndWindow()
end
function UI.toolbar(v,w,h)return require('app.table_panels').toolbar(v,w,h)end
function UI.priority(v,w,h)
    local m,S=v.m,v.S;if m.replay or not m.game or m.game.running==false then return end
    local state=m.game.priority or{};local options=m:priorityOptions()
    local stop=Priority.stopPresentation(m,Priority.beforeDamage,'opponent');local C=v.r.colors
    local tint=stop.status=='on'and C.accent or stop.status=='off'and C.muted or C.gold
    local fill=stop.status=='on'and{tint[1]*.24,tint[2]*.24,tint[3]*.24,1}
        or stop.status=='off'and{.06,.075,.10,1}or{.24,.17,.065,1}
    local hover={math.min(1,fill[1]+.07),math.min(1,fill[2]+.07),math.min(1,fill[3]+.07),1}
    local tooltip='Stop after confirmed blockers, before combat damage · opponents’ turns'
    tooltip=tooltip..'\n'..(stop.status=='on'and'ON · confirmed by XMage. After Done confirms blockers, priority stops before damage.'
        or stop.status=='off'and'OFF · confirmed by XMage. Click to enable this stop.'
        or stop.pending and'WAIT · a native priority update is still pending.'or'Not yet confirmed by XMage; the saved choice is not shown as active.')
    local stopBox=Layout.beforeDamage(w)
    v:window('before-damage-stop',stopBox.x,stopBox.y,stopBox.w,stopBox.h,nil,{AllowFocus=false,Border=0,BgColor={0,0,0,0},AutoSizeContent=false})
    local image=v.r.assets:buttonImage('block',stop.label,208,32,{font=v.r.fonts[12],iconSize=24,color=tint,iconTint=tint,gap=8})
    if S.Button('Stop after confirmed blockers, before combat damage · opponents’ turns',{Image={Image=image},W=208,H=32,Tooltip=tooltip,
        Color=fill,HoverColor=hover,PressColor=hover,Disabled=stop.pending})then m:togglePhaseStop(Priority.beforeDamage,'opponent')end
    S.EndWindow()
    if v.combatStopsOpen then
        v:window('combat-step-stops',w-480,54,460,350,'Combat stops',{Layer='ContextMenu',BgColor={.025,.04,.06,.99}})
        if S.Button('Close combat stops',{W=426,H=28})then v.combatStopsOpen=false end
        S.NewLine();local sx,sy=S.GetCursorPos({Absolute=true})
        for index,group in ipairs(Priority.combatSteps)do
            S.PushID('combat-step-'..index)
            local rowY=sy+(index-1)*31
            S.SetCursorPos(sx,rowY,{Absolute=true});S.Text(group.label,{Color=v.r.colors.text})
            for sideIndex,side in ipairs({'own','opponent'})do
                S.SetCursorPos(sx+235+(sideIndex-1)*76,rowY,{Absolute=true})
                local checked=m:phaseStop(group,side)
                if S.CheckBox(checked,side=='own'and'You'or'Opponents',{Disabled=m.priorityBusy,Tooltip='Stop '..group.label..' · '..(side=='own'and'your turn'or'opponents’ turns')})then m:togglePhaseStop(group,side)end
            end
            S.PopID()
        end
        S.SetCursorPos(sx,sy+#Priority.combatSteps*31+6,{Absolute=true})
        S.Textf('Before combat damage waits after Done confirms blockers. First-strike stops occur after first-strike damage.',{W=426,Color=v.r.colors.muted})
        S.EndWindow()
    end
    if state.yielding then
        v:window('cancel-yield',w-258,h-112,238,42)
        if S.Button('Cancel End Turn',{Image={Image=v.r.assets:buttonImage('pause','Cancel End Turn',210,30)},W=210,H=30,Disabled=m.priorityBusy}) then m:cancelYield() end
        S.EndWindow()
    end
end
function UI.log(v,w,h)return require('app.table_panels').log(v,w,h)end
function UI.stack(v,w,h)return require('app.table_panels').stack(v,w,h)end
function UI.prompt(v,w,h)
    local S,m=v.S,v.m;local p=m:prompt();if CardChoices.build(v,w,h,p)then return end;if not p then return end
    if p.mulligan then
        local L=Layout.table(w,h);local mw=math.min(520,L.board.w-70);local x=L.board.x+(L.board.w-mw)/2
        v:window('mulligan',x,h/2-99,mw,198,'Opening hand')
        S.PushFont(v.r.fonts[24]);S.Text('Keep this hand?',{Color=v.r.colors.text});S.PopFont();S.NewLine()
        S.Text(p.mulligan.free and 'Your first Commander mulligan is free.' or 'Choose your starting hand.',{Color=v.r.colors.muted});S.NewLine()
        local bw=(mw-36)/2
        if S.Button('Keep',{W=bw,H=46,Disabled=m.actionBusy or m.roomDisconnected}) then m:answerChoice(p.mulligan.keepChoice) end;S.SameLine()
        if S.Button('Mulligan Down to '..tostring(p.mulligan.downTo),{W=bw,H=46,Disabled=m.actionBusy or m.roomDisconnected}) then m:answerChoice(p.mulligan.mulliganChoice) end
        S.EndWindow();return
    end
    if p.manaWheel then return end
    if require('app.mana_payment_ui').build(v,w,h,p) then return end
    if p.type=='choose_ability'then abilityChoices(v,w,h,p);return end
    if p.type=='select' then
        priorityControls(v,w,h,p)
        return
    end
    local pw=360;local ph=math.min(400,math.max(185,115+#(p.choices or {})*45));local width=pw-32
    v:window('floating-actions',math.max(24,(w-pw)/2),math.max(162,h*.32),pw,ph,'Choose an action',{AllowMove=false})
    RichText.slab(v,'prompt-message',p.message or '',width,{size=16,color=v.r.colors.text});S.NewLine()
    if p.type=='order' then
        S.Textf('Leftmost resolves first.',{W=width,Color=v.r.colors.muted})
        if S.Button('Confirm order',{W=width,H=38,Disabled=m.actionBusy or m.roomDisconnected}) then m:submitOrder() end
    else
        for _,key in ipairs({'pile1','pile2'}) do
            if p[key] and #p[key]>0 then
                S.Text(key=='pile1' and 'PILE 1' or 'PILE 2',{Color=v.r.colors.purple})
                for _,card in ipairs(p[key]) do S.Textf(card.name,{W=width,Color=v.r.colors.muted}) end
                S.Separator()
            end
        end
        local promptKey=CardChoices.promptKey(m,p)
        for _,choice in ipairs(p.choices or {}) do option(v,promptKey,choice,width) end
        if p.type=='multi_amount' then
            if v.amountPrompt~=p.id then v.amountPrompt=p.id;v.amountValues={} end
            for i,entry in ipairs(p.amountMessages or {}) do
                S.Textf(entry.message or entry.label or '',{W=width,Color=v.r.colors.muted})
                v.amountValues[i]=v.amountValues[i] or tostring(entry.defaultValue or entry.min or 0)
                if S.Input('amount-'..i,{Text=v.amountValues[i],NumbersOnly=true,MinNumber=entry.min or 0,MaxNumber=entry.max,W=width,H=30}) then v.amountValues[i]=S.GetInputText() end
            end
            if S.Button('Confirm distribution',{W=width,H=36,Disabled=m.actionBusy or m.roomDisconnected}) then
                local values=require('lib.json').array();for i=1,#(p.amountMessages or {}) do values[i]=tonumber(v.amountValues[i]) or 0 end
                m:answer('multi_amount',values)
            end
        elseif p.type=='amount' or p.type=='integer' then
            if v.numberPrompt~=p.id then v.numberPrompt=p.id;v.numberValue=tostring(p.min or 0) end
            if S.Input('amount',{Text=v.numberValue,NumbersOnly=true,MinNumber=p.min or 0,MaxNumber=p.max,W=width,H=30}) then v.numberValue=S.GetInputText() end
            if S.Button('Confirm amount',{W=width,H=36,Disabled=m.actionBusy or m.roomDisconnected}) then m:answer('integer',tonumber(v.numberValue) or 0) end
        elseif (p.type=='string' or p.type=='text') and #(p.choices or {})==0 then
            if v.textPrompt~=p.id then v.textPrompt=p.id;v.textValue='' end
            if S.Input('response',{Text=v.textValue,W=width,H=30,Align='left'}) then v.textValue=S.GetInputText() end
            if S.Button('Confirm',{W=width,H=36,Disabled=m.actionBusy or m.roomDisconnected}) then m:answer('string',v.textValue) end
        end
    end
    S.EndWindow()
end
function UI.replayControls(v,w,h)
    local m,S=v.m,v.S;local replay=m.replay;if not replay then return end
    local width=math.min(690,w-290);v:window('replay-controls',(w-width)/2,h-96,width,79,'Replay · view only')
    iconButton(v,'Previous frame','previous',function() m:stepReplay(-1) end);S.SameLine()
    iconButton(v,replay.playing and 'Pause replay' or 'Play replay',replay.playing and 'pause' or 'play',function() m:toggleReplay() end);S.SameLine()
    iconButton(v,'Next frame','next',function() m:stepReplay(1) end);S.SameLine()
    if S.InputNumberSlider('replay-frame',replay.index or 1,1,math.max(1,#replay.frames),{W=math.max(120,width-365),H=30,Step=1}) then m:seekReplay(math.floor(S.GetInputNumber()+.5)) end;S.SameLine()
    S.Text((replay.index or 0)..' / '..#replay.frames);S.SameLine()
    v:combo('replay-speed',tostring(replay.speed)..'x',{'0.5x','1x','2x','4x','8x'},70,function(value)
        replay.speed=tonumber(value:match('[%d.]+')) or 1;m.uiLayout=m.uiLayout or {};m.uiLayout.replayPrefs={speed=replay.speed};m.uiLayoutTimer=.4
    end)
    S.EndWindow()
end
function UI.endMatch(v,w,h)
    local m,S=v.m,v.S;local game=m.game
    if m.replay or not game or game.running~=false then return end
    local outcome=require('app.outcome').state(m);local duel=outcome and outcome.mode=='duel'
    local title=outcome and outcome.title or game.error and game.error~=json.null and'Match interrupted'or'Match stopped'
    local pw=math.min(500,w-70);local request=m.room and m.room.rematchRequest
    local height=request and 268 or 204
    v:window('match-complete',(w-pw)/2,duel and math.max(120,math.min(h-height-24,h/2+35))or math.max(120,h/2-100),pw,height,not duel and title or nil,{AutoSizeContent=false,BgColor={.025,.04,.06,.96}})
    if game.error and game.error~=json.null then S.Textf(tostring(game.error),{W=pw-34,Color=v.r.colors.gold});S.NewLine()end
    local width=pw-34;local allowed=m.canRematch and m:canRematch()or false
    if request and request.gameId==game.gameId then
        local approved=false;for _,id in ipairs(request.approvedSeatIds or{})do if id==m.roomParticipantId then approved=true end end
        if request.requesterId==m.roomParticipantId or approved then
            S.Textf('Waiting for the other players to accept the rematch…',{W=width,Color=v.r.colors.gold});S.NewLine()
            if request.requesterId==m.roomParticipantId and S.Button('Cancel rematch request',{W=width,H=38,Disabled=m.roomBusy})then m:cancelRematch(request.id)end
        else
            S.Textf((request.requesterName or'Player')..' is asking for a rematch',{W=width,Color=v.r.colors.accent});S.NewLine()
            if S.Button('Accept rematch',{W=(width-12)/2,H=38,Disabled=m.roomBusy})then m:respondRematch(true,request.id)end;S.SameLine({Pad=12})
            if S.Button('Decline',{W=(width-12)/2,H=38,Disabled=m.roomBusy})then m:respondRematch(false,request.id)end
        end
    elseif m.room and m.room.phase=='starting'then S.Text('Starting the rematch…',{Color=v.r.colors.gold})
    elseif m.roomConnectionId and not allowed then
        if S.Button('Return to room',{W=width,H=38})then m:showRooms()end
    elseif S.Button(m.roomConnectionId and'Request rematch'or'Rematch',{W=width,H=44,Disabled=not allowed or m.gameBusy or m.roomBusy})then m:rematch()end
    S.NewLine()
    if S.Button('Main menu',{W=width,H=38,Disabled=m.gameBusy})then if m.goMain then m:goMain()end end
    S.EndWindow()
end
function UI.build(v,w,h)
    local outcome=require('app.outcome').state(v.m)
    if outcome and outcome.mode=='duel'then UI.endMatch(v,w,h);return end
    UI.toolbar(v,w,h);UI.priority(v,w,h);UI.log(v,w,h);UI.stack(v,w,h)
    if v.m.replay then CardChoices.build(v,w,h,nil);UI.replayControls(v,w,h) else UI.prompt(v,w,h) end
    UI.endMatch(v,w,h)
    if v.m.confirmConcede then
        v:window('concede-confirm',w/2-205,h/2-75,410,150,'Concede match')
        v.S.Text('Concede this match?');v.S.NewLine()
        if v.S.Button('Concede',{W=185,H=36}) then v.m:concede();v.m.confirmConcede=false end;v.S.SameLine()
        if v.S.Button('Continue',{W=185,H=36}) then v.m.confirmConcede=false end
        v.S.EndWindow()
    end
end
return UI
