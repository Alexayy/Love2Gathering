local UI={}
function UI.build(v,w,h)
    local S,m=v.S,v.m
    v:window('replay-library',24,100,w-48,h-124)
    local refreshW=math.max(244,math.ceil(v.r.fonts[16]:getWidth('Refresh recordings')+70))
    if S.Button('Refresh recordings',{Image={Image=v.r.assets:buttonImage('replay','Refresh recordings',refreshW,44,{font=v.r.fonts[16]})},W=refreshW,H=44,Tooltip='Refresh saved matches'}) then m:refreshReplays() end
    local count=m.replayLoading and('Loading '..(m.replayLoadProgress or 0)..' frames…')or tostring(m.replaysTotal or#(m.replays or{}))..' recordings'
    S.SameLine({Pad=16,CenterY=true});local _,countY=S.GetCursorPos({Absolute=true})
    S.SetCursorPos(nil,countY+require('app.fonts').textOffset(v.r.fonts[16],count),{Absolute=true});S.Text(count,{Color=v.r.colors.muted});S.NewLine()
    if m.replaysBusy then S.Text('Loading recordings…',{Color=v.r.colors.muted}) end
    for _,recording in ipairs(m.replays or {}) do
        S.PushID(recording.id)
        local title=recording.title or ((recording.playerName or 'You')..' vs '..(recording.botName or 'XMage bot'))
        local rowX,rowY=S.GetCursorPos({Absolute=true})
        if S.Button('Open recording',{Image={Image=v.r.assets:buttonImage('play','Open',108,38)},W=108,H=38,Disabled=m.replayLoading}) then m:openReplay(recording.id) end
        -- Indent the whole information column, including its wrapped lines/date.
        S.Indent(124);S.SetCursorPos(nil,rowY,{Absolute=true})
        S.Textf(title,{W=w-230,Color=v.r.colors.text})
        S.Textf(tostring(recording.format or'')..' · '..tostring(recording.status or'recording')..' · '..tostring(recording.frameCount or 0)..' frames',{W=w-230,Color=v.r.colors.muted})
        local created=recording.createdAt or recording.startedAt or ''
        if type(created)=='number' then created=os.date('%Y-%m-%d %H:%M',math.floor(created/1000)) end
        S.Image('recording-date',{Image=v.r.assets:iconImage('calendar',14),W=14,H=14});S.SameLine();S.Text(tostring(created),{Color=v.r.colors.muted})
        local _,bottom=S.GetCursorPos({Absolute=true});S.Unindent(124)
        S.SetCursorPos(rowX,math.max(rowY+48,bottom+8),{Absolute=true})
        S.Separator();S.PopID()
    end
    if not m.replaysBusy and #(m.replays or {})==0 then S.Textf('Your matches are recorded automatically. Save a replay from the table, then open it here.',{W=w-98,Color=v.r.colors.muted}) end
    if (m.replaysTotal or 0)>#(m.replays or {}) then
        if S.Button('Load more',{W=180,H=35}) then m:refreshReplays(true) end
    end
    S.EndWindow()
end
return UI
