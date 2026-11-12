local UI={}
function UI.build(v,w,h)
    local S,m=v.S,v.m
    v:window('replay-library',24,173,w-48,h-197)
    if S.Button('Refresh recordings',{Image={Image=v.r.assets:buttonImage('replay','Refresh recordings',210,38)},W=210,H=38}) then m:refreshReplays() end
    S.SameLine();S.Text(m.replayLoading and ('Loading '..(m.replayLoadProgress or 0)..' frames…') or 'Saved in SQLite',{Color=v.r.colors.muted});S.NewLine()
    if m.replaysBusy then S.Text('Loading recordings…',{Color=v.r.colors.muted}) end
    for _,recording in ipairs(m.replays or {}) do
        S.PushID(recording.id)
        local title=recording.title or ((recording.playerName or 'You')..' vs '..(recording.botName or 'XMage bot'))
        if S.Button('Open recording',{Image={Image=v.r.assets:buttonImage('play','Open',108,38)},W=108,H=38,Disabled=m.replayLoading}) then m:openReplay(recording.id) end
        S.SameLine();S.Textf(title..'  ·  '..tostring(recording.format or '')..'  ·  '..tostring(recording.status or 'recording')..'  ·  '..tostring(recording.frameCount or 0)..' frames',{W=w-230})
        local created=recording.createdAt or recording.startedAt or ''
        if type(created)=='number' then created=os.date('%Y-%m-%d %H:%M',math.floor(created/1000)) end
        S.Text(tostring(created),{Color=v.r.colors.muted})
        S.Separator();S.PopID()
    end
    if not m.replaysBusy and #(m.replays or {})==0 then S.Textf('Your matches are recorded automatically. Save a replay from the table, then open it here.',{W=w-98,Color=v.r.colors.muted}) end
    if (m.replaysTotal or 0)>#(m.replays or {}) then
        if S.Button('Load more',{W=180,H=35}) then m:refreshReplays(true) end
    end
    S.EndWindow()
end
return UI
