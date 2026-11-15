local UI={}
local function button(v,label,icon,width,height,opts)
    opts=opts or{};opts.W=width;opts.H=height;opts.Tooltip=opts.Tooltip or label
    opts.Image={Image=v.r.assets:buttonImage(icon,label,width,height,{font=v.r.fonts[16],iconSize=20})}
    return v.S.Button(label,opts)
end
function UI.build(v,w,h)
    if v.m.lobbyMode=='draft'then return require('app.bot_draft_ui').build(v,w,h)end
    local S,m=v.S,v.m;local gap=18;local width=w-56;local setupW=math.min(width*.59,math.max(590,width*.52));local nameW=width-setupW-gap
    local setupH=m.format=='Commander'and 206 or 166;local decksTop=118+setupH
    v:window('lobby-setup',28,100,setupW,setupH,nil,{AutoSizeContent=false})
    S.Text('Format and seats',{Color=v.r.colors.accent});S.SameLine({Pad=20,CenterY=true})
    if button(v,'Draft with bots','pack',math.min(210,setupW-240),28,{Disabled=m.gameBusy})then m:openBotDraft()end
    S.NewLine()
    local rowX,rowY=S.GetCursorPos({Absolute=true});local formatW=math.min(205,setupW-320)
    v:combo('format',m.format,m.playFormats and m:playFormats()or{'Modern','Standard','Pioneer','Commander'},formatW,function(value)m:setLobbyFormat(value)end)
    if m.format=='Commander'then
        for i,count in ipairs({2,4,5,6})do
            S.SetCursorPos(rowX+formatW+12+(i-1)*72,rowY,{Absolute=true})
            if button(v,tostring(count),'players',62,36,{Active=m:lobbyPlayerCount()==count,Tooltip=count..' players · you and '..(count-1)..' bots'})then m:setLobbyPlayers(count)end
        end
    else S.SameLine({Pad=20,CenterY=true});S.Text('1 player · 1 bot',{Color=v.r.colors.muted})end
    S.NewLine()
    S.Image('opening-dice',{Image=v.r.assets:iconImage('dice-6',22,v.r.colors.gold),W=22,H=22});S.SameLine({CenterY=true})
    local choices={'Roll 2d6'};local ids={'dice'};local selected='Roll 2d6'
    for i=1,m:lobbyPlayerCount()do local label=i==1 and'You go first'or'Bot '..(i-1)..' goes first';choices[#choices+1]=label;ids[#ids+1]=i==1 and'local'or'bot-'..(i-1);if m.practiceStartingSeatId==ids[#ids]then selected=label end end
    if selected=='Roll 2d6'then m.practiceStartingSeatId='dice'end
    v:combo('practice-starting-player',selected,choices,math.min(330,setupW-75),function(value)for i,label in ipairs(choices)do if value==label then m.practiceStartingSeatId=ids[i]end end end)
    if m.format=='Commander'then
        S.NewLine()
        if S.CheckBox(m.commanderDamage~=false,'Commander combat damage (21)',{Tooltip='XMage tracks combat damage from each commander. Disable for a house-rule practice game without the 21-damage loss condition.'})then m.commanderDamage=m.commanderDamage==false end
    end
    S.EndWindow()
    v:window('lobby-name',28+setupW+gap,100,nameW,104,nil,{AutoSizeContent=false})
    S.Text('Your name',{Color=v.r.colors.accent});S.NewLine()
    if S.Input('playerName',{Text=m.playerName,W=nameW-30,H=36,Align='left',Tooltip='Name for this match'})then m.playerName=S.GetInputText()end
    S.EndWindow()
    v:window('lobby-decks',28,decksTop,width,h-decksTop-86)
    local columns=w>=1600 and 3 or 2;local tileW=(width-42-(columns-1)*18)/columns
    S.BeginListBox('lobby-seats',{W=width-30,H=math.max(100,h-decksTop-120)})
    S.BeginLayout('lobby-seat-columns',{Columns=columns,AlignX='left',AlignY='top'})
    local count=m:lobbyPlayerCount()
    for i=1,count do
        S.SetLayoutColumn((i-1)%columns+1)
        local own=i==1;local title=own and(m.playerName or'You')or'XMage Bot '..(i-1)
        local tint=own and v.r.colors.accent or v.r.colors.purple
        local titleW=math.min(tileW,math.ceil(v.r.fonts[16]:getWidth(title)+42))
        S.Image('seat-role-'..i,{Image=v.r.assets:buttonImage(own and'profile'or'bot',title,titleW,30,{font=v.r.fonts[16],iconSize=22,color=tint,iconTint=tint}),W=titleW,H=30})
        local id=own and m.playerDeckId or(i==2 and m.botDeckId or m.botDeckIds[i-1])
        require('app.deck_picker').button(v,own and'yourDeck'or i==2 and'botDeck'or'botDeck'..(i-1),id,m.format,tileW,function(value)if own then m.playerDeckId=value else m:setBotDeck(i-1,value)end end,{height=146})
        S.NewLine();S.NewLine()
    end
    S.EndLayout();S.EndListBox();S.EndWindow()
    v:window('lobby-start',28,h-70,width,52,nil,{AutoSizeContent=false})
    local ready=m.engineHealth.ok or m.engineHealth.status=='ok'or m.engineHealth.ready
    if button(v,m.gameBusy and'Starting…'or'Start match','play',260,40,{Disabled=m.gameBusy or not ready})then m:startGame()end
    S.SameLine({Pad=18,CenterY=true});S.Text('1 player · '..(count-1)..' bots'..(m.format=='Commander'and' · 40 life'or' · 20 life'),{Color=v.r.colors.muted})
    if m.game then S.SameLine({Pad=20,CenterY=true});if button(v,'Return to match','back',220,40)then m.page='table'end end
    S.EndWindow()
end
return UI
