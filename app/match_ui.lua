local Layout=require('app.layout')
local RichText=require('app.richtext')
local Log=require('app.log')
local Window=require('lib.Slab.Internal.UI.Window')
local CardChoices=require('app.card_choices')
local json=require('lib.json')
local UI={}
local function iconButton(v,label,icon,action,active,disabled,size)
    local S=v.S
    size=size or 38
    if S.Button(label,{Image={Image=v.r.assets:iconImage(icon,size-8)},W=size,H=size,Tooltip=label,Active=active,Disabled=disabled}) then action() end
end
local function option(v,choice,width)
    local label=v.r:fit(tostring(choice.label or choice.id),width-20,16,3)
    local _,breaks=label:gsub('\n','')
    v.S.PushID('choice-'..tostring(choice.id or choice.value or label))
    if v.S.Button(label,{W=width,H=math.max(38,(breaks+1)*20+14),VLines=breaks+1,Tooltip=choice.label,Disabled=v.m.actionBusy}) then v.m:answerChoice(choice) end
    v.S.PopID()
end
function UI.toolbar(v,w,h)
    local S,m=v.S,v.m
    v:window('match-toolbar',w-278,10,262,34)
    local buttons={
        {m.roomConnectionId and 'Room' or 'Lobby','home',function() if m.roomConnectionId then m:showRooms() else m.page='lobby' end end},
        {'Settings','settings',function() m.settingsOpen=not m.settingsOpen end},
        {'Show / hide log','log',function() m.logOpen=not (m.logOpen~=false);m:setUIOption('logOpen',m.logOpen) end,m.logOpen~=false},
        {'Show / hide stack','stack',function() m.stackOpen=not (m.stackOpen~=false);m:setUIOption('stackOpen',m.stackOpen) end,m.stackOpen~=false},
        {'Save replay','save',function() m:saveReplay() end,nil,m.roomGameActive and m.game and m.game.replayAvailable==false},
        {'Replay library','replay',function() m:showReplays() end},
        {m.replay and 'Close replay' or 'Concede match',m.replay and 'close' or 'concede',function() if m.replay then m:closeReplay() else m.confirmConcede=true end end},
    }
    for i,item in ipairs(buttons) do if i>1 then S.SameLine() end;iconButton(v,item[1],item[2],item[3],item[4],item[5],28) end
    S.EndWindow()
end
function UI.priority(v,w,h)
    local m,S=v.m,v.S;if m.replay or not m.game or m.game.running==false then return end
    local state=m.game.priority or {};local options=m:priorityOptions()
    v:window('priority-mode',w-320,10,34,34)
    iconButton(v,options.autoPass and 'Automatic priority · click for full control' or 'Full control · click for automatic priority',options.autoPass and 'play' or 'pause',function() m:toggleAutoPass() end,not options.autoPass,m.priorityBusy,28)
    S.EndWindow()
    if state.yielding then
        v:window('cancel-yield',w-258,h-112,238,42)
        if S.Button('Cancel End Turn',{Image={Image=v.r.assets:buttonImage('pause','Cancel End Turn',210,30)},W=210,H=30,Disabled=m.priorityBusy}) then m:cancelYield() end
        S.EndWindow()
    end
end
function UI.log(v,w,h)
    local m,S=v.m,v.S;local L=Layout.table(w,h);m.logHover=nil
    if m.logOpen==false then return end
    v:window('floating-log',L.log.x,L.log.y,L.log.w,L.log.h,'Match log')
    S.Text('You',{Color={.32,.91,.73}});S.SameLine();S.Text(v.m.roomGameActive and 'Opponents' or 'Bot',{Color={.74,.59,1}});S.SameLine();S.Text('Actions',{Color={.48,.77,1}});S.SameLine()
    local verbose=((m.uiLayout or {}).matchPrefs or {}).logVerbose==true
    if S.CheckBox(verbose,'Verbose',{Tooltip='Include stack triggers and resolutions. Hover an entry for its full text.'})then m:setUIOption('logVerbose',not verbose)end
    S.Separator()
    local log=m.game and m.game.log or {}
    local width=select(1,S.GetWindowSize())-32
    for _,entry in ipairs(Log.entries(log,m.game and m.game.players,verbose))do
        S.PushID('log-'..entry.index)
        S.Rectangle({W=4,H=19,Color=entry.actorColor,Rounding=2});S.SameLine()
        local source=Log.source(entry,m.game);local data=source and(m:cardData(source)or source);local art=data and(m:getArt(data,true)or CardChoices.cardImage(v,source,64,90))
        S.Image('log-icon',{Image=art or v.r.assets:iconImage(entry.icon,18),W=art and 13 or 18,H=18,Tooltip=source and source.name or entry.category})
        if source and S.IsControlHovered()then m.logHover={card=source}end
        S.SameLine()
        local text,height=RichText.canvas(v.r,entry.text,width-38,{size=14,color=entry.color,maxLines=2})
        S.Image('log-text',{Image=text,W=width-38,H=height,Tooltip=entry.fullText})
        S.PopID()
    end
    S.EndWindow()
end
function UI.stack(v,w,h)
    local S,m=v.S,v.m;local stack=m.game and m.game.stack or {};m.stackHits={};m.stackHover=nil
    if #stack==0 or m.stackOpen==false then return end
    local prompt=m:prompt();if prompt and prompt.type=='order' then return end
    local panelH=m.replay and math.min(360,math.max(100,h-520)) or math.min(430,h-365)
    v:window('floating-stack',w-536,340,386,panelH,'Stack · '..#stack)
    local width=select(1,S.GetWindowSize())-32
    for i,object in ipairs(stack) do
        local source=type(object.sourceCard)=='table'and object.sourceCard.name and object.sourceCard or {name=object.artName or object.sourceName or object.name}
        local data=m:cardData(source) or source;local art=m:getArt(data,true)or CardChoices.cardImage(v,source,76,106)
        local x,y=S.GetCursorPos({Absolute=true});local cardW=76;local cardH=106
        S.PushID('stack-'..tostring(object.id or i))
        if art then
            if S.Button('Inspect source card',{Image={Image=art},W=cardW,H=cardH,Tooltip=source.name}) then m.inspectCard=source end
        else S.Rectangle({W=cardW,H=cardH,Color={.10,.14,.20},Rounding=5}) end
        S.Indent(cardW+12)
        S.SetCursorPos(x+cardW+12,y,{Absolute=true})
        S.Text((object.isTop or (object.isTop==nil and i==1)) and 'RESOLVES NEXT' or ('STACK '..i),{Color=v.r.colors.purple})
        S.Textf(object.sourceName or object.name or source.name or 'Ability',{W=width-cardW-18,Color=v.r.colors.text})
        local rules=object.rules
        if not rules or rules=='' then rules=data.oracle_text or source.rules or source.type or data.type_line or '' end
        if type(rules)=='table' then rules=table.concat(rules,'\n') end
        RichText.slab(v,'stack-rules',rules,width-cardW-18,{size=14,color=v.r.colors.muted})
        local _,bottom=S.GetCursorPos({Absolute=true})
        S.Unindent(cardW+12)
        local sx,sy=Window.TransformPoint(x,y);local wx,wy=S.GetWindowPosition();local ww,wh=S.GetWindowSize()
        local hit={x=sx,y=sy,w=width,h=math.max(cardH,bottom-y),clip={x=wx,y=wy+(S.GetStyle().WindowTitleH or 20),w=ww,h=wh},id=object.id,sourceId=object.sourceId,sourceCard=source,targets=object.targets or {}}
        m.stackHits[#m.stackHits+1]=hit
        local mx,my=Layout.mouse()
        if not Window.IsObstructedAtMouse()and mx>=hit.x and mx<=hit.x+hit.w and my>=math.max(hit.y,hit.clip.y)and my<=math.min(hit.y+hit.h,hit.clip.y+hit.clip.h)then m.stackHover=hit end
        S.SetCursorPos(x,math.max(y+cardH,bottom)+10,{Absolute=true});S.Separator()
        S.PopID()
    end
    S.EndWindow()
end
function UI.prompt(v,w,h)
    local S,m=v.S,v.m;local p=m:prompt();if CardChoices.build(v,w,h,p)then return end;if not p then return end
    if p.mulligan then
        local L=Layout.table(w,h);local mw=math.min(520,L.board.w-70);local x=L.board.x+(L.board.w-mw)/2
        v:window('mulligan',x,h/2-99,mw,198,'Opening hand')
        S.PushFont(v.r.fonts[24]);S.Text('Keep this hand?',{Color=v.r.colors.text});S.PopFont();S.NewLine()
        S.Text(p.mulligan.free and 'Your first Commander mulligan is free.' or 'Choose your starting hand.',{Color=v.r.colors.muted});S.NewLine()
        local bw=(mw-36)/2
        if S.Button('Keep',{W=bw,H=46,Disabled=m.actionBusy}) then m:answerChoice(p.mulligan.keepChoice) end;S.SameLine()
        if S.Button('Mulligan Down to '..tostring(p.mulligan.downTo),{W=bw,H=46,Disabled=m.actionBusy}) then m:answerChoice(p.mulligan.mulliganChoice) end
        S.EndWindow();return
    end
    if p.manaWheel then return end
    if p.type=='select' then
        local controls={}
        for _,choice in ipairs(p.choices or {}) do if choice.responseType~='uuid' then controls[#controls+1]=choice end end
        local endTurn=p.priority==true
        local bw=math.min(430,150*math.max(1,#controls)+(endTurn and 152 or 0));local x=w-bw-16
        v:window('priority-controls',x,h-62,bw,49)
        for i,choice in ipairs(controls) do
            if i>1 then S.SameLine() end
            S.PushID('control-'..i)
            if S.Button(choice.label or 'Pass',{W=(bw-32-(endTurn and 152 or 0))/math.max(1,#controls)-4,H=32,Disabled=m.actionBusy or m.priorityBusy}) then m:answerChoice(choice) end
            S.PopID()
        end
        if endTurn then
            if #controls>0 then S.SameLine() end
            if S.Button('End Turn',{Image={Image=v.r.assets:buttonImage('next','End Turn',144,32)},W=144,H=32,Disabled=m.actionBusy or m.priorityBusy}) then m:endTurn() end
        end
        S.EndWindow();return
    end
    local pw=360;local ph=math.min(400,math.max(185,115+#(p.choices or {})*45));local width=pw-32
    v:window('floating-actions',w-pw-18,134,pw,ph,'Choose an action')
    RichText.slab(v,'prompt-message',p.message or '',width,{size=16,color=v.r.colors.text});S.NewLine()
    if p.type=='order' then
        S.Textf('Leftmost resolves first.',{W=width,Color=v.r.colors.muted})
        if S.Button('Confirm order',{W=width,H=38,Disabled=m.actionBusy}) then m:submitOrder() end
    else
        for _,key in ipairs({'pile1','pile2'}) do
            if p[key] and #p[key]>0 then
                S.Text(key=='pile1' and 'PILE 1' or 'PILE 2',{Color=v.r.colors.purple})
                for _,card in ipairs(p[key]) do S.Textf(card.name,{W=width,Color=v.r.colors.muted}) end
                S.Separator()
            end
        end
        for _,choice in ipairs(p.choices or {}) do option(v,choice,width) end
        if p.type=='multi_amount' then
            if v.amountPrompt~=p.id then v.amountPrompt=p.id;v.amountValues={} end
            for i,entry in ipairs(p.amountMessages or {}) do
                S.Textf(entry.message or entry.label or '',{W=width,Color=v.r.colors.muted})
                v.amountValues[i]=v.amountValues[i] or tostring(entry.defaultValue or entry.min or 0)
                if S.Input('amount-'..i,{Text=v.amountValues[i],NumbersOnly=true,MinNumber=entry.min or 0,MaxNumber=entry.max,W=width,H=30}) then v.amountValues[i]=S.GetInputText() end
            end
            if S.Button('Confirm distribution',{W=width,H=36,Disabled=m.actionBusy}) then
                local values=require('lib.json').array();for i=1,#(p.amountMessages or {}) do values[i]=tonumber(v.amountValues[i]) or 0 end
                m:answer('multi_amount',values)
            end
        elseif p.type=='amount' or p.type=='integer' then
            if v.numberPrompt~=p.id then v.numberPrompt=p.id;v.numberValue=tostring(p.min or 0) end
            if S.Input('amount',{Text=v.numberValue,NumbersOnly=true,MinNumber=p.min or 0,MaxNumber=p.max,W=width,H=30}) then v.numberValue=S.GetInputText() end
            if S.Button('Confirm amount',{W=width,H=36,Disabled=m.actionBusy}) then m:answer('integer',tonumber(v.numberValue) or 0) end
        elseif (p.type=='string' or p.type=='text') and #(p.choices or {})==0 then
            if v.textPrompt~=p.id then v.textPrompt=p.id;v.textValue='' end
            if S.Input('response',{Text=v.textValue,W=width,H=30,Align='left'}) then v.textValue=S.GetInputText() end
            if S.Button('Confirm',{W=width,H=36,Disabled=m.actionBusy}) then m:answer('string',v.textValue) end
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
    local title='Match complete'
    for _,player in ipairs(game.players or {})do if player.human or player.isLocal then
        if player.won then title='Victory'elseif player.lost then title='Defeat'end;break
    end end
    local pw=math.min(500,w-70);v:window('match-complete',(w-pw)/2,math.max(120,h/2-100),pw,200,title)
    if game.error and game.error~=json.null then S.Textf(tostring(game.error),{W=pw-34,Color=v.r.colors.gold});S.NewLine()end
    local width=pw-34;local allowed=m.canRematch and m:canRematch()or false
    if m.roomConnectionId and not allowed then
        if S.Button('Return to room',{W=width,H=38})then m:showRooms()end
    elseif S.Button('Rematch',{W=width,H=38,Disabled=not allowed or m.gameBusy})then m:rematch()end
    S.NewLine()
    if S.Button('Main menu',{W=width,H=38,Disabled=m.gameBusy})then if m.goMain then m:goMain()end end
    S.EndWindow()
end
function UI.build(v,w,h)
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
