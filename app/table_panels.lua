local Layout=require('app.layout')
local Window=require('lib.Slab.Internal.UI.Window')
local Rich=require('app.richtext')
local Log=require('app.log')
local Panels={}
local function layout(v,w,h)return v.r.tableLayout or Layout.table(w,h,v.m)end
function Panels.toolbar(v,w,h)
    local m,S=v.m,v.S;local stack=m.game and m.game.stack or{}
    v:window('table-tools',w-294,15,278,43,nil,{AllowFocus=false,Border=0,BgColor={0,0,0,0}})
    if S.Button('Stack '..#stack,{W=90,H=36,Active=m.stackOpen~=false})then m.stackOpen=m.stackOpen==false;m:setUIOption('stackOpen',m.stackOpen)end
    S.SameLine()
    if S.Button('Table options',{W=170,H=36,Active=v.tableOptionsOpen==true})then v.tableOptionsOpen=not v.tableOptionsOpen end
    S.EndWindow()
    local prompt=m.prompt and m:prompt();local undo=not m.replay and prompt and prompt.undoChoice
    if undo then
        v:window('native-mana-undo',w-472,15,162,43,nil,{AllowFocus=false,Border=0,BgColor={0,0,0,0}})
        if S.Button(undo.label or'Undo last mana action',{W=154,H=36,Disabled=m.actionBusy or m.priorityBusy or m.roomDisconnected})then m:answerChoice(undo)end
        S.EndWindow()
    end
    if not v.tableOptionsOpen then return end
    v:window('table-options',w-430,63,412,math.min(658,h-94),'Table options',{Layer='ContextMenu',AllowMove=false,AllowResize=false,ResetPosition=true,BgColor={.025,.04,.06,.99}})
    local function button(label,fn)
        if S.Button(label,{W=370,H=34})then fn()end;S.NewLine()
    end
    button('Close options',function()v.tableOptionsOpen=false end)
    if not m.replay then
        local options=m:priorityOptions();local state=m.game and m.game.priority or{}
        if S.CheckBox(options.autoPass,'Auto-pass empty priority',{Disabled=m.priorityBusy or m.roomDisconnected})then m:toggleAutoPass()end;S.NewLine()
        if S.CheckBox(options.passWithOnlyMana==true,'Include mana-only windows',{Disabled=m.priorityBusy or m.roomDisconnected or state.manaOnlyPolicySupported~=true})then m:toggleManaOnlyPass()end;S.NewLine()
        S.Textf('Mana-only means XMage offers mana abilities and no other legal action, including other zones. Explicit stops and Full Control always hold priority.',{W=370,Color=v.r.colors.muted});S.NewLine()
        button('Combat stops',function()v.tableOptionsOpen=false;v.combatStopsOpen=true end)
    end
    if v.r.tableCamera then
        button('Fit Table',function()v.r.tableCamera:overview();v.tableOptionsOpen=false end)
        button('My Battlefield',function()for i,p in ipairs(v.r.multiplayerSeats or{})do if p.human then v.r.tableCamera:focus(i);break end end;v.tableOptionsOpen=false end)
    end
    button(m.logOpen==true and'Close history drawer'or'Open history drawer',function()m.logOpen=m.logOpen~=true;m:setUIOption('logOpen',m.logOpen)end)
    local prefs=(m.uiLayout or{}).matchPrefs or{}
    if S.CheckBox(prefs.logPinned==true,'Pin history beside the table')then m:setUIOption('logPinned',not prefs.logPinned)end;S.NewLine()
    button('Presentation settings',function()m.settingsOpen=true;v.tableOptionsOpen=false;v.settingsTab='Presentation'end)
    if not m.replay then button('Save replay',function()m:saveReplay()end)end
    button('Replay library',function()m:showReplays();v.tableOptionsOpen=false end)
    button(m.roomConnectionId and'Return to room'or'Return to lobby',function()if m.roomConnectionId then m:showRooms()else m.page='lobby'end;v.tableOptionsOpen=false end)
    button(m.replay and'Close replay'or'Concede match',function()if m.replay then m:closeReplay()else m.confirmConcede=true end;v.tableOptionsOpen=false end)
    S.EndWindow()
end
function Panels.stack(v,w,h)
    local m,S,r=v.m,v.S,v.r;local stack=m.game and m.game.stack or{}
    r.stackRows={};r.hoverStackId=nil;m.stackHits={};m.stackHover=nil
    local rail=layout(v,w,h).rail;if not rail or m.stackOpen==false then return end
    v:window('docked-stack',rail.x,rail.y,rail.w-14,rail.h-14,nil,{AllowMove=false,AllowResize=false,ResetPosition=true,ResetSize=true,BgColor={.019,.032,.046,.98}})
    local width=rail.w-42
    S.PushFont(r.fonts[20]);S.Text('STACK · '..#stack,{Color=r.colors.text});S.PopFont();S.NewLine()
    if #stack==0 then S.Textf('The stack is empty. Casts and abilities appear here; hovering shows their exact targets.',{W=width,Color=r.colors.muted});S.EndWindow();return end
    S.Textf('Hover an object for its connections. First resolves next.',{W=width,Color=r.colors.muted});S.NewLine()
    S.BeginListBox('stack-rail-scroll',{W=width,H=math.max(120,rail.h-118),AlwaysShowScrollBarY=true})
    for i,object in ipairs(stack)do
        S.PushID('native-stack-'..tostring(object.id or i))
        local x,y=S.GetCursorPos({Absolute=true});local source=type(object.sourceCard)=='table'and object.sourceCard or{name=object.sourceName or object.name or'Ability'}
        local cardW,cardH=58,81;local art=require('app.card_choices').cardImage(v,source,cardW,cardH)
        if S.Button('Inspect '..tostring(object.sourceName or object.name or'object'),{W=cardW,H=cardH,Image=art and{Image=art}or nil,Tooltip=source.name})then m.inspectCard=source;m.commanderDetails=nil end
        S.Indent(cardW+10);S.SetCursorPos(x+cardW+10,y,{Absolute=true})
        S.Text(i==1 and'NEXT TO RESOLVE'or('STACK '..i),{Color=i==1 and r.colors.gold or r.colors.muted})
        S.Textf(object.sourceName or object.name or'Ability',{W=width-cardW-18,Color=r.colors.text})
        local controller=(r.boardPlayers or{})[object.controllerId]
        S.Textf((object.kind=='spell'and'Spell'or'Ability')..' · '..(controller and controller.name or'Unknown controller'),{W=width-cardW-18,Color=controller and r:playerColor(controller)or r.colors.muted})
        local _,bottom=S.GetCursorPos({Absolute=true});S.Unindent(cardW+10)
        S.SetCursorPos(x,math.max(y+cardH,bottom)+6,{Absolute=true})
        local targets={};for _,target in ipairs(object.targets or{})do targets[#targets+1]=target.name or target.id or'Native target'end
        if #targets>0 then S.Textf('Targets · '..table.concat(targets,', '),{W=width-12,Color=r.colors.gold});S.NewLine()end
        local rules=object.rules or source.rules or'';if type(rules)=='table'then rules=table.concat(rules,'\n')end
        Rich.slab(v,'stack-rules',rules,width-12,{size=14,color=r.colors.muted,maxLines=4})
        if object.modes then S.Textf('Modes · '..(type(object.modes)=='table'and table.concat(object.modes,', ')or tostring(object.modes)),{W=width-12,Color=r.colors.text})end
        if type(object.paidOptions)=='table'and#object.paidOptions>0 then S.Textf('Paid options · '..table.concat(object.paidOptions,', '),{W=width-12,Color=r.colors.gold})end
        local _,by=S.GetCursorPos({Absolute=true});local sx,sy=Window.TransformPoint(x,y)
        local hit={id=object.id,stackId=object.id,x=sx,y=sy,w=width-10,h=math.max(82,by-y),
            visible=true,clip={x=rail.x+8,y=rail.y+76,w=rail.w-22,h=rail.h-92},sourceId=object.sourceId,sourceCard=source,targets=object.targets or{}}
        hit.visible=hit.y+hit.h>=hit.clip.y and hit.y<=hit.clip.y+hit.clip.h
        r.stackRows[object.id or tostring(i)]=hit;m.stackHits[#m.stackHits+1]=hit
        local mx,my=Layout.mouse()
        if hit.visible and not Window.IsObstructedAtMouse()and mx>=hit.x and mx<=hit.x+hit.w and my>=math.max(hit.y,hit.clip.y)and my<=math.min(hit.y+hit.h,hit.clip.y+hit.clip.h)then
            m.stackHover=hit;r.hoverStackId=object.id
        end
        S.Separator();S.NewLine();S.PopID()
    end
    S.EndListBox();S.EndWindow()
end
function Panels.log(v,w,h)
    local m,S=v.m,v.S;m.logHover=nil;if m.logOpen~=true then return end
    local L=layout(v,w,h);local box=L.safe.history
    v:window('history-drawer',box.x,box.y,box.w,box.h,'History',{AllowMove=false,AllowResize=false,ResetPosition=true,ResetSize=true,BgColor={.018,.03,.046,.99}})
    if S.Button('Close history',{W=box.w-32,H=30})then m.logOpen=false;m:setUIOption('logOpen',false)end;S.NewLine()
    local verbose=((m.uiLayout or{}).matchPrefs or{}).logVerbose==true
    if S.CheckBox(verbose,'Include repetitive triggers and resolutions')then m:setUIOption('logVerbose',not verbose)end;S.NewLine()
    for _,entry in ipairs(Log.entries(m.game and m.game.log or{},m.game and m.game.players,verbose))do
        S.PushID(tostring(entry.index))
        local source=Log.source(entry,m.game)
        if source then
            local art=require('app.card_choices').cardImage(v,source,36,50)
            S.Image('history-source',{Image=art or v.r.assets:iconImage(entry.icon,20),W=art and 15 or 20,H=20,Tooltip=source.name})
            if S.IsControlHovered()then m.logHover={card=source}end
        end
        Rich.slab(v,'history-entry',entry.text,box.w-45,{size=14,color=entry.color,maxLines=3})
        S.PopID();S.NewLine()
    end
    S.EndWindow()
end
function Panels.commander(v,w,h)
    local m,S=v.m,v.S;if not m.commanderDetails then return end
    local player;for _,p in ipairs(m.game and m.game.players or{})do if p.id==m.commanderDetails then player=p end end
    if not player then m.commanderDetails=nil;return end
    local width=math.min(620,w-60);local height=math.min(700,h-100)
    v:window('commander-details',(w-width)/2,(h-height)/2,width,height,'Commander details',{Layer='ContextMenu',AllowMove=false})
    if S.Button('Close commander details',{W=width-34,H=32})then m.commanderDetails=nil end;S.NewLine()
    S.Text((player.name or'Player')..' · '..tostring(player.life)..' life',{Color=v.r:playerColor(player)});S.NewLine()
    for _,cmd in ipairs(player.commanders or{})do
        S.PushID('commander-'..tostring(cmd.id))
        S.Textf(cmd.name or'Commander',{W=width-42,Color=v.r.colors.gold});S.NewLine()
        S.Text('Current zone · '..tostring(cmd.zoneName or cmd.zone or'Unknown'));S.NewLine()
        Rich.slab(v,'native-cmd-tax',require('app.card_presentation').commanderLabel(cmd),width-42,{size=16,color=v.r.colors.text})
        local offers=cmd.availableCastingOptions or{}
        if #offers==0 then S.Textf('No current native casting offer. Reductions and additional choices are checked when XMage offers the action.',{W=width-42,Color=v.r.colors.muted})end
        for _,offer in ipairs(offers)do
            Rich.slab(v,'cmd-offer-'..tostring(offer.id),tostring(offer.label or'Cast')..' '..tostring(offer.manaCost or''),width-42,{size=16,color=v.r.colors.accent})
        end
        local source=cmd.sourceCard or{id=cmd.id,name=cmd.name}
        if S.Button('Inspect commander',{W=210,H=32})then m.inspectCard=source;m.commanderDetails=nil end
        S.Separator();S.NewLine();S.PopID()
    end
    S.Text('Commander combat damage received',{Color=v.r.colors.gold});S.NewLine()
    if m.game.commanderDamageEnabled==false then S.Text('Commander damage is disabled.')
    elseif #(player.commanderDamageReceived or{})==0 then S.Text('No commander combat damage recorded.')
    else for _,entry in ipairs(player.commanderDamageReceived)do S.Textf((entry.name or'Commander')..' · '..tostring(entry.amount or 0)..' damage',{W=width-42,Color=v.r.colors.text});S.NewLine()end end
    for key,value in pairs(player.counters or{})do if tonumber(value)and value~=0 then S.Text(tostring(key)..' · '..tostring(value));S.NewLine()end end
    S.EndWindow()
end
return Panels
