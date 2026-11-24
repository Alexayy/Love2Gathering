-- Explicit whole-package updates. No startup network or client-side execution.
local Updates={}
local json=require('lib.json')
local function object(value)return type(value)=='table'and value~=json.null end
local function idle(m)
    return not m.roomConnectionId and not m.roomGameActive
        and not(m.liveGame and m.liveGame.running==true)
        and not(m.game and m.game.running==true and not m.replay)
end
function Updates.canApply(m)return idle(m)and not m.updateBusy and not m.updateQuitting and not m.updateApplying end
local function request(m,path,body,callback)
    m.updateEpoch=(m.updateEpoch or 0)+1;local epoch=m.updateEpoch;m.updateBusy=true
    m:request('catalog','POST','/updates/'..path,body,function(data,error)
        if m.updateEpoch~=epoch then return end
        m.updateBusy=false
        if object(data)then m.updateState=data else m.updateState={state='error',error=error or'Update service is unavailable.'}end
        m.updatePollAt=0
        if callback then callback(data)end
    end,true)
end
function Updates.check(m)request(m,'check',{})end
function Updates.download(m,id)request(m,'download',{candidateId=id})end
function Updates.auth(m,token)
    if m.updateBusy or m.updateApplying then return false end
    request(m,'auth',{token=token});return true
end
function Updates.apply(m,id)
    if not Updates.canApply(m)then return false end
    m.updateApplying=true;m.updateApprovedCandidate=id
    request(m,'apply',{candidateId=id},function(data)
        local function confirmed(value)
            m.updateApplying=false
            if object(value)and value.state=='apply_requested'and idle(m)then
                m.updateState=value;m.updateQuitting=true;love.event.quit(0)
            end
        end
        if object(data)then confirmed(data)
        else
            -- A lost ACK must not repeat an installer request. Reconcile the
            -- already approved candidate through one idempotent local read.
            local epoch=m.updateEpoch
            m:request('catalog','GET','/updates/status',nil,function(value)
                if m.updateEpoch~=epoch then return end
                if object(value)and object(value.candidate)and value.candidate.id==id then confirmed(value)
                else m.updateApplying=false end
            end,true)
        end
    end)
    return true
end
function Updates.pending(view,w,h)
    if not view.m.updateApplying then return end
    view:window('update-install-pending',(w-420)/2,(h-150)/2,420,150,'Preparing update',{Layer='ContextMenu',AllowMove=false,BgColor={.025,.04,.06,.99}})
    view.S.Textf('Preparing the verified installer. The app will close after your saved changes finish writing.',{W=384,Color=view.r.colors.text})
    view.S.EndWindow()
end
function Updates.poll(m)
    local state=m.updateState
    if not state or(state.state~='checking'and state.state~='downloading')or m.updateBusy or m.updatePolling then return end
    local now=love.timer.getTime();if now<(m.updatePollAt or 0)then return end
    m.updatePollAt=now+.6;m.updatePolling=true;local epoch=m.updateEpoch
    m:request('catalog','GET','/updates/status',nil,function(data,error)
        m.updatePolling=false
        if m.updateEpoch~=epoch then return end
        if object(data)then m.updateState=data else m.updateState={state='error',error=error or'Could not read update progress.'}end
    end,true)
end
function Updates.build(view,width,info)
    local m,S,C=view.m,view.S,view.r.colors
    Updates.poll(m)
    S.Separator();S.NewLine();S.Text('Application updates',{Color=C.accent});S.NewLine()
    S.Textf('Updates replace the client, bridge and bundled resources together. Saved decks, settings, replays and card images are preserved.',{W=width,Color=C.muted});S.NewLine()
    local packaged=info and info.packaged
    if not packaged then S.Textf('Use an installed release for in-app updates. Source checkouts keep their repository workflow.',{W=width,Color=C.muted});S.NewLine();return end
    local state=m.updateState or{};local working=m.updateBusy or state.state=='checking'or state.state=='downloading'or state.state=='apply_requested'
    S.Textf(state.authenticated==true and'GitHub access token saved.'or'Private releases require GitHub access for this repository.',{W=width,Color=C.muted});S.NewLine()
    S.Textf('Use a fine-grained token with this repository selected and Contents: read. The token is used only for update downloads.',{W=width,Color=C.muted});S.NewLine()
    if S.Input('update-github-access',{Text=m.updateAuthToken or'',IsPassword=true,ReturnOnText=true,W=math.min(360,width),H=34,Align='left',ReadOnly=working,Tooltip='GitHub access token for private release updates'})then m.updateAuthToken=S.GetInputText()end;S.NewLine()
    if S.Button('Save GitHub access',{W=math.min(220,width),H=36,Disabled=working or not m.updateAuthToken or m.updateAuthToken==''})then
        local token=m.updateAuthToken;m.updateAuthToken='';S.SetInputFocus(nil);Updates.auth(m,token)
    end;S.NewLine()
    if state.authenticated==true then
        if S.Button('Forget GitHub access',{W=math.min(220,width),H=34,Disabled=working})then m.updateAuthToken='';S.SetInputFocus(nil);Updates.auth(m,'')end;S.NewLine()
    end
    if S.Button(state.state=='checking'and'Checking for updates…'or'Check for updates',{W=math.min(330,width),H=38,Disabled=working})then Updates.check(m)end;S.NewLine()
    if state.state=='unavailable'then S.Textf('This installation cannot update itself. Install the latest complete package from Releases to enable the matching updater.',{W=width,Color=C.gold});S.NewLine()end
    if state.state=='idle'then S.Text('This release channel is up to date.',{Color=C.muted});S.NewLine()end
    local candidate=object(state.candidate)and state.candidate
    if candidate then
        S.Textf('Available · '..tostring(candidate.version)..' · '..tostring(state.channel or info.channel),{W=width,Color=C.gold});S.NewLine()
        if state.state=='available'or state.state=='error'then
            if S.Button('Download complete update',{W=math.min(330,width),H=38,Disabled=m.updateBusy})then Updates.download(m,candidate.id)end;S.NewLine()
        end
        if state.state=='downloading'then
            local progress=object(state.progress)and state.progress or{}
            S.Text(string.format('Downloading · %.1f / %.1f MiB',(progress.downloadedBytes or 0)/1048576,(progress.totalBytes or candidate.expectedSize or 0)/1048576),{Color=C.muted});S.NewLine()
        elseif state.state=='ready'or state.state=='apply_requested'then
            S.Textf('Download verified. Installation starts after this app and its local services close.',{W=width,Color=C.accent});S.NewLine()
            if not idle(m)then S.Textf('Finish the current game and leave your room before installing.',{W=width,Color=C.gold});S.NewLine()end
            local label=state.method=='flatpak'and state.automaticInstall~=true and'Close and open system installer'or'Close, install and restart'
            if S.Button(label,{W=math.min(360,width),H=42,Disabled=not Updates.canApply(m)})then Updates.apply(m,candidate.id)end;S.NewLine()
        end
    end
    if type(state.error)=='string'and state.error~=''then S.Textf(state.error,{W=width,Color=C.gold});S.NewLine()end
end
return Updates
