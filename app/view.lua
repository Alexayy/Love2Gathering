local C=require('app.renderer').colors
local Model=require('app.model')
local Layout=require('app.layout')
local RichText=require('app.richtext')
local View={};View.__index=View
local formats={'Modern','Standard','Pioneer','Commander'}
local function plain(value)
    if type(value)=='table' then return tostring(value.message or value.text or value.label or '') end
    return tostring(value or ''):gsub('<[^>]*>',''):gsub('&nbsp;',' '):gsub('&amp;','&'):gsub('&gt;','>'):gsub('&lt;','<')
end
function View.new(S,model,renderer)
    local self=setmetatable({S=S,m=model,r=renderer},View)
    local style=S.GetStyle()
    style.Font=renderer.fonts[16]
    style.WindowBackgroundColor={.055,.073,.106,.99};style.WindowTitleFocusedColor={.08,.18,.20,1}
    style.WindowTitleUnfocusedColor={.07,.12,.16,1};style.ButtonColor={.105,.20,.24,1};style.ButtonHoveredColor={.13,.33,.34,1}
    style.ButtonPressedColor={.16,.45,.40,1};style.TextColor=C.text;style.TextDisabledColor=C.muted
    style.InputBgColor={.032,.047,.073,1};style.InputSelectColor={.13,.47,.55,.88};style.SeparatorColor={.15,.21,.28,1}
    style.ComboBoxColor={.09,.14,.19,1};style.ComboBoxHoveredColor={.12,.24,.27,1};style.ComboBoxDropDownColor={.12,.23,.26,1}
    style.ComboBoxDropDownHoveredColor={.16,.34,.33,1};style.InputEditBgColor={.055,.10,.15,1};style.CheckBoxSelectedColor=C.accent
    style.ScrollBarColor={.17,.28,.32,1};style.ScrollBarHoveredColor={.23,.46,.45,1};style.TextHoverBgColor={.10,.26,.27,1}
    style.WindowRounding=10;style.ButtonRounding=5;style.WindowBorder=12
    require('app.theme').install(S,renderer.assets)
    return self
end
function View:window(id,x,y,w,h,title)
    local movable=title~=nil;local resizable=id=='floating-log' or id=='floating-stack'
    local border=(id=='match-toolbar' or id=='priority-mode') and 6 or 14
    local geometryId=id=='floating-stack' and self.m.replay and 'floating-stack-replay' or id
    local vw,vh=Layout.dimensions();self.floatBases=self.floatBases or {};self.floatReset=self.floatReset or {}
    local base=self.floatBases[id];local revision=self.m.uiLayoutVersion or 0
    local first=movable and (not base or base.revision~=revision or base.vw~=vw or base.vh~=vh or base.geometryId~=geometryId)
    if movable then
        if first then
            local saved=(self.m.uiLayout or {})[geometryId]
            if saved and saved.x and saved.y then
                x=saved.x*vw;y=saved.y*vh
                if resizable then w=(saved.w or w/vw)*vw;h=(saved.h or h/vh)*vh end
            end
            w=math.max(250,math.min(w,vw-32));h=math.max(100,math.min(h,vh-48))
            local titleH=math.max(self.S.GetStyle().WindowTitleH or 0,self.S.GetStyle().Font:getHeight())
            x=math.max(8,math.min(x,vw-w-22));y=math.max(8,math.min(y,vh-h-22-titleH))
            base={x=x,y=y,w=w,h=h,revision=revision,vw=vw,vh=vh,geometryId=geometryId};self.floatBases[id]=base
        end
        x,y=base.x,base.y
        if resizable then w,h=base.w,base.h end
    end
    self.S.BeginWindow(id,{X=x,Y=y,W=w,H=h,Title=title,AutoSizeWindow=false,AllowMove=movable,AllowResize=resizable,ResetPosition=not movable or first or self.floatReset[id],ResetSize=not resizable or first or self.floatReset[id],NoSavedSettings=true,Border=border,ShowMinimize=false,ConstrainPosition=true})
    self.floatReset[id]=nil
    if movable and not love.mouse.isDown(1) then
        local ax,ay=self.S.GetWindowPosition();local aw,ah=self.S.GetWindowSize()
        -- Slab reports outer title position and body size including its border.
        aw,ah=aw-border,ah-border
        if math.abs(ax-base.x)>.5 or math.abs(ay-base.y)>.5 or (resizable and (math.abs(aw-base.w)>.5 or math.abs(ah-base.h)>.5)) then
            base.x,base.y,base.w,base.h=ax,ay,aw,ah;self.floatReset[id]=true
            if self.m.setUILayout then self.m:setUILayout(geometryId,{x=ax/vw,y=ay/vh,w=aw/vw,h=ah/vh}) end
        end
    end
end
function View:combo(id,selected,items,width,changed)
    local S=self.S
    if S.BeginComboBox(id,{Selected=tostring(selected or ''),W=width}) then
        for _,v in ipairs(items) do if S.TextSelectable(tostring(v),{Selected=v==selected}) then changed(v) end end
        S.EndComboBox()
    end
end
function View:decks(w,h)require('app.collection_ui').build(self,w,h)end
function View:builder(w,h) require('app.builder').build(self,w,h) end
function View:deckPicker(id,deckId,format,width,changed)
    require('app.deck_picker').button(self,id,deckId,format,width,changed)
end
function View:lobby(w,h)
    local S,m=self.S,self.m;local height=h-226
    self:window('lobby',28,202,math.min(515,w*.44),height)
    local width=math.min(515,w*.44)-25;local count=m:lobbyPlayerCount()
    local function label(text,icon,color)
        S.Image('lobby-label-'..text,{Image=self.r.assets:iconImage(icon,19,color),W=19,H=19});S.SameLine();S.Text(text,{Color=color or C.text})
    end
    local function button(text,icon,bw,bh,options)
        options=options or {};options.W=bw;options.H=bh
        options.Image={Image=self.r.assets:buttonImage(icon,text,bw,bh,{font=self.r.fonts[16],iconSize=18})}
        return S.Button(text,options)
    end
    label('MATCH SETUP',m.format=='Commander' and 'commander' or 'library',C.accent);S.Separator()
    -- Keep the launch controls visible while additional seats scroll at small sizes.
    S.BeginListBox('lobby-setup',{W=width,H=math.max(200,height-160)})
    local content=width-14
    label('Format','library')
    self:combo('format',m.format,formats,content,function(v)m:setLobbyFormat(v)end)
    if m.format=='Commander' then
        S.NewLine();label('Players','players',C.accent)
        local choices={2,4,5,6};local bw=(content-24)/4
        for i,players in ipairs(choices) do
            if i>1 then S.SameLine() end
            if button(tostring(players),'players',bw,31,{Color=count==players and {.13,.37,.34,1} or nil,Tooltip=players..' players: you and '..(players-1)..' XMage bot'..(players>2 and 's' or '')}) then m:setLobbyPlayers(players);count=players end
        end
    end
    S.NewLine();label('Your name','player',C.accent)
    if S.Input('playerName',{Text=m.playerName,W=content,H=28,Align='left'}) then m.playerName=S.GetInputText() end
    S.NewLine();label('YOUR DECK','library',C.accent)
    self:deckPicker('yourDeck',m.playerDeckId,m.format,content,function(id) m.playerDeckId=id end)
    local deck=m:findDeck(m.playerDeckId)
    if deck then S.Textf(deck.description or '',{W=content,Color=C.muted}) end
    for index=1,count-1 do
        S.NewLine();label(count==2 and 'XMAGE BOT DECK' or 'XMAGE BOT '..index,'bot',C.purple)
        self:deckPicker(index==1 and 'botDeck' or 'botDeck'..index,index==1 and m.botDeckId or m.botDeckIds[index],m.format,content,function(id)m:setBotDeck(index,id)end)
        if count==2 then
            local bot=m:findDeck(m.botDeckId);if bot then S.Textf(bot.description or '',{W=content,Color=C.muted}) end
        end
    end
    S.NewLine();label(m.format=='Commander' and '40 life · one free mulligan' or '20 life · single game',m.format=='Commander' and 'commander' or 'library',C.muted)
    S.Text(m.settings.manualTriggers and 'Trigger order: manual, left → right' or 'Trigger order: automatic',{Color=C.muted})
    S.EndListBox();S.NewLine()
    label('1 human · '..(count-1)..' XMage bot'..(count>2 and 's' or ''),'players',C.text)
    local connected=m.engineHealth.ok or m.engineHealth.status=='ok' or m.engineHealth.ready
    if button(m.gameBusy and 'Starting engine match…' or 'Start match','play',width,40,{Disabled=m.gameBusy or not connected}) then m:startGame() end
    if not connected then S.Textf('The XMage bridge is starting. First launch compiles the engine; see the launcher log for progress.',{W=width,Color=C.gold}) end
    if m.game then if button('Return to current match','back',width,28) then m.page='table' end end
    S.EndWindow()
end
function View:table(w,h) require('app.match_ui').build(self,w,h) end
function View:replays(w,h) require('app.replay_ui').build(self,w,h) end
function View:gallery(w,h) require('app.gallery').build(self,w,h) end
function View:rooms(w,h) require('app.room_ui').build(self,w,h) end
function View:draft(w,h) require('app.draft_ui').build(self,w,h) end
function View:settings(w,h) require('app.settings').build(self,w,h) end
function View:modals(w,h)
    local S,m=self.S,self.m
    require('app.deck_picker').popup(self,w,h)
    require('app.collection_ui').modals(self,w,h)
    if m.deleteConfirm then
        self:window('delete-deck',w/2-230,h/2-85,460,170,'Delete deck')
        S.Textf('Remove '..m.deleteConfirm.name..' from your collection?',{W=432});S.NewLine()
        if S.Button('Remove',{W=210,H=32}) then m:deleteDeck(m.deleteConfirm);m.deleteConfirm=nil end;S.SameLine()
        if S.Button('Cancel',{W=210,H=32}) then m.deleteConfirm=nil end
        S.EndWindow()
    end
    if m.zoneView then
        local zone=m.zoneView
        self:window('zone-view',w/2-270,155,540,h-260,zone.label)
        if S.Button('Close zone',{W=510,H=28}) then m.zoneView=nil
        else
            for _,card in ipairs(zone.cards) do
                if S.TextSelectable(plain(card.name or card.label),{W=510}) then
                    if m:selectCard(card) then m.zoneView=nil else m.previewCard=card;m.inspectCard=card end
                end
            end
            if #zone.cards==0 then S.Text('This zone is empty.',{Color=C.muted}) end
        end
        S.EndWindow()
    end
    if m.inspectCard then
        self:window('inspect-card',w/2-185,110,370,h-180,'Card details')
        if S.Button('Close details',{W=340,H=27}) then m.inspectCard=nil
        else
            local card=m:cardData(m.inspectCard) or m.inspectCard;local art=m:getArt(card)
            if art then S.Image('inspected-art',{Image=art,W=285,H=399}) end
            S.PushFont(self.r.assets:titleFont(22,m.settings));S.Textf(plain(card.name),{W=340,Color=C.accent});S.PopFont()
            RichText.slab(self,'inspected-cost',card.mana_cost or card.manaCost or '',340,{size=20,color=C.gold})
            S.Textf(plain(card.type_line or card.type),{W=340,Color=C.muted});S.Separator()
            RichText.slab(self,'inspected-rules',require('app.keywords').annotate(card.oracle_text or card.rules or'',m.settings.keywordReminders),340,{size=16,color=C.text})
            if m.inspectCard.power and m.inspectCard.toughness then S.Text('Current '..m.inspectCard.power..'/'..m.inspectCard.toughness,{Color=C.gold})end
            local attached=(self.r.boardAttached or{})[m.inspectCard.id]or{}
            if #attached>0 then S.Separator();S.Text('Attached cards',{Color=C.gold})end
            for _,entry in ipairs(attached)do if S.TextSelectable(entry.name)then m.inspectCard=entry end end
            for _,entry in ipairs(m.inspectCard.linkedExile or{})do if S.TextSelectable('Exiled here · '..(entry.name or'Face down'))and not entry.hidden then m.inspectCard=entry end end
        end
        S.EndWindow()
    end
    if m.settingsOpen then self:settings(w,h) end
end
function View:build()
    local w,h=Layout.dimensions()
    self.S.PushFont(self.r.fonts[16])
    if self.m.page=='decks' then self:decks(w,h)
    elseif self.m.page=='builder' then self:builder(w,h)
    elseif self.m.page=='lobby' then self:lobby(w,h)
    elseif self.m.page=='table' then self:table(w,h)
    elseif self.m.page=='replays' then self:replays(w,h) end
    if self.m.page=='gallery' then self:gallery(w,h) end
    if self.m.page=='rooms' then self:rooms(w,h) end
    if self.m.page=='draft' then self:draft(w,h) end
    if self.m.page=='import' then require('app.library_ui').import(self,w,h)end
    if self.m.page=='history' then require('app.library_ui').history(self,w,h)end
    if self.m.page=='tokens' then require('app.library_ui').tokens(self,w,h)end
    if self.m.page=='profile'then require('app.profile_ui').build(self,w,h)end
    self:modals(w,h)
    self.S.PopFont()
end
return View
