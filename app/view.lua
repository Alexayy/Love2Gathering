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
    renderer.view=self
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
function View:window(id,x,y,w,h,title,options)
    options=options or{}
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
    local windowOptions={X=x,Y=y,W=w,H=h,Title=title,AutoSizeWindow=false,AllowMove=movable,AllowResize=resizable,ResetPosition=not movable or first or self.floatReset[id],ResetSize=not resizable or first or self.floatReset[id],NoSavedSettings=true,Border=border,ShowMinimize=false,ConstrainPosition=true}
    for key,value in pairs(options)do windowOptions[key]=value end
    self.S.BeginWindow(id,windowOptions)
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
function View:lobby(w,h)require('app.lobby_ui').build(self,w,h)end
function View:table(w,h) require('app.match_ui').build(self,w,h) end
function View:replays(w,h) require('app.replay_ui').build(self,w,h) end
function View:gallery(w,h) require('app.gallery').build(self,w,h) end
function View:rooms(w,h) require('app.room_ui').build(self,w,h) end
function View:draft(w,h) require('app.draft_ui').build(self,w,h) end
function View:settings(w,h,options) require('app.settings').build(self,w,h,options) end
function View:modals(w,h)
    require('app.updates').pending(self,w,h)
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
    if m.zoneView then require('app.zone_ui').build(self,w,h)else self.zoneUiOpening=nil end
    require('app.table_panels').commander(self,w,h)
    require('app.card_actions').build(self,w,h)
    if m.inspectCard then
        self:window('inspect-card',w/2-185,110,370,h-180,'Card details')
        if S.Button('Close details',{W=340,H=27}) then m.inspectCard=nil
        else
            local card=m:cardData(m.inspectCard) or m.inspectCard;local art=m:getArt(card)
            if not m.replay and S.Button('Actions / ways to play',{W=340,H=34})then require('app.card_actions').open(m,m.inspectCard);m.inspectCard=nil;S.EndWindow();return end
            local mechanics=require('app.mechanic_fx').cardProfiles(m.inspectCard or card)
            if #mechanics>0 then
                S.Text('Mechanics and current abilities',{Color=C.gold});S.NewLine()
                for _,entry in ipairs(mechanics)do S.Textf(entry.label..(entry.parameter and(' · '..tostring(entry.parameter))or''),{W=340,Color=C.text});S.NewLine()end
                S.Separator()
            end
            local traits=require('app.card_traits').entries(m.inspectCard or card)
            if#traits>0 and#mechanics==0 then
                S.Text('Current abilities',{Color=C.gold})
                for _,entry in ipairs(traits)do
                    if entry.icon then S.Image('native-trait-'..entry.name,{Image=self.r.assets:iconImage(entry.icon,20,entry.gained and C.gold or C.text),W=20,H=20});S.SameLine({CenterY=true})end
                    S.Text(entry.label..(entry.gained and' · granted'or''),{Color=entry.gained and C.gold or C.text})
                end
                S.Separator()
            end
            if art then S.Image('inspected-art',{Image=art,W=285,H=399}) end
            S.PushFont(self.r.assets:titleFont(22,m.settings));S.Textf(plain(card.name),{W=340,Color=C.accent});S.PopFont()
            RichText.slab(self,'inspected-cost',card.mana_cost or card.manaCost or '',340,{size=20,color=C.gold})
            S.Textf(plain(card.type_line or card.type),{W=340,Color=C.muted});S.Separator()
            RichText.slab(self,'inspected-rules',require('app.keywords').annotate(card.oracle_text or card.rules or'',m.settings.keywordReminders),340,{size=16,color=C.text})
            if card.currentRules and card.currentRules~=''then
                if S.Button('Show current rules',{W=340,H=32})then self.inspectCurrentRules=not self.inspectCurrentRules end
                if self.inspectCurrentRules then RichText.slab(self,'inspected-current-rules',card.currentRules,340,{size=16,color=C.gold})end
            end
            local context=(m.inspectCard or card).faceDownContext
            if context then S.Textf('Face-down on the battlefield'..(context.nativePT and' · native P/T '..context.nativePT or'')..' · '..tostring(context.damage or 0)..' damage marked',{W=340,Color=C.gold})
            else local stats=require('app.card_presentation').stats(m.inspectCard);if stats then S.Textf(stats.label,{W=340,Color=C.gold})end end
            local merged=m.inspectCard.mutate
            if type(merged)=='table'and type(merged.components)=='table'and#merged.components>0 then
                if self.inspectMutateHostId~=m.inspectCard.id then self.inspectMutateHostId=m.inspectCard.id;self.inspectMutateComponentId=nil end
                S.Separator();S.Text('Mutate components · '..#merged.components,{Color=C.gold})
                local selected
                for index,component in ipairs(merged.components)do
                    local identity=tostring(component.id or index);local label=(component.id==merged.topId and'Top · 'or'Component · ')..plain(component.name or'Card')
                    S.PushID('mutate-component-'..identity)
                    if S.TextSelectable(label,{Tooltip='Inspect this component’s original printing. It is part of the merged permanent.'})then self.inspectMutateComponentId=identity end
                    S.PopID()
                    if self.inspectMutateComponentId==identity then selected=component end
                end
                if selected then
                    S.Textf('Component printing · '..plain(selected.name or'Card'),{W=340,Color=C.accent})
                    local printed=selected.printing or selected
                    if printed.power~=nil and printed.toughness~=nil then S.Text('Printed '..tostring(printed.power)..'/'..tostring(printed.toughness),{Color=C.muted})end
                    local componentArt=m:getArt(m:cardData(selected)or selected,true)
                    if componentArt then S.Image('mutate-component-art',{Image=componentArt,W=180,H=252})end
                end
            else self.inspectMutateHostId=nil;self.inspectMutateComponentId=nil end
            local attached=(self.r.boardAttached or{})[m.inspectCard.id]or{}
            if #attached>0 then S.Separator();S.Text('Attached cards',{Color=C.gold})end
            for _,entry in ipairs(attached)do if S.TextSelectable(entry.name)then m.inspectCard=entry end end
            for _,entry in ipairs(m.inspectCard.linkedExile or{})do if S.TextSelectable('Exiled here · '..(entry.name or'Face down'))and not entry.hidden then m.inspectCard=entry end end
        end
        S.EndWindow()
    end
    if m.settingsOpen and not m.storageFolderDialog and not m.imagePackFileDialog and not m.storageLocationConfirm then self:settings(w,h) end
    require('app.storage').modal(self,w,h)
    require('app.storage_locations').modal(self,w,h)
    require('app.image_packs').modal(self,w,h)
    if self.m.cardPrintingPicker then require('app.card_printings_ui').build(self,w,h)end
    require('app.set_picker').build(self,w,h)
end
function View:build()
    if self.inputPage~=self.m.page then
        require('lib.Slab.Internal.UI.Region').ClearHotInstance();self.S.SetInputFocus(nil)
        self.inputPage=self.m.page
    end
    if self.m.refreshLibraryViews then self.m:refreshLibraryViews()end
    local w,h=Layout.dimensions()
    local storageVisible=(self.m.page=='settings'or self.m.settingsOpen)and self.settingsTab=='Storage'and(self.m.storageSection or'cleanup')or false
    if(self.storageRegionVisible or false)~=storageVisible then
        -- A hidden nested Slab list does not get another Begin to release hover.
        -- Release it before rebuilding visible regions, keeping navbar input live.
        require('lib.Slab.Internal.UI.Region').ClearHotInstance()
    end
    self.storageRegionVisible=storageVisible
    if self.deckSelection and self.deckSelection.openPage and self.deckSelection.openPage~=self.m.page then require('app.deck_picker').close(self)end
    require('app.set_picker').current(self)
    local outcome=self.m.page=='table'and require('app.outcome').state(self.m)
    local completedDuel=outcome and outcome.mode=='duel'
    local endedGame=self.m.page=='table'and self.m.game and self.m.game.running==false and not self.m.replay
    local tableIdentity=self.m.replay or self.m.game and self.m.game.gameId
    if self.m.page~='table'or self.tableGameIdentity~=tableIdentity then
        self.tableOptionsOpen=false;self.combatStopsOpen=false
    end
    self.tableGameIdentity=tableIdentity
    if endedGame then
        -- These gameplay windows are no longer built after completion. Retire
        -- their locks even if the opponent finished while they were open.
        self.m.confirmConcede=false;self.combatStopsOpen=false;self.tableOptionsOpen=false
    end
    local Choices=require('app.card_choices');local choicePrompt=self.m.prompt and self.m:prompt()or nil
    self.cardChoiceModal=not endedGame and Choices.currentModal(self,choicePrompt)or nil
    local choiceKey=Choices.modalKey(self,choicePrompt,self.cardChoiceModal)
    if self.cardChoiceModalKey~=choiceKey then
        -- Input focus and hot scrolling belong to one native decision. An
        -- asynchronous prompt/game change must retire the hidden controls.
        require('lib.Slab.Internal.UI.Region').ClearHotInstance();self.S.SetInputFocus(nil)
        self.cardChoiceModalKey=choiceKey
    end
    local lock=self.m.updateApplying and'update-install-pending'or self.setPicker and'set-picker'or self.m.storageLocationConfirm and'storage-location-confirm'or self.themeColorEdit and'ColorPicker'or self.m.storagePurgePreview and'storage-purge-confirm'or self.m.cardPrintingPicker and'card-printing-picker'or self.m.tokenPicker and'token-art-picker'or self.brandMenu and'app-brand-menu'or self.deckSelection and'choose-deck-tiles'
        or self.m.settingsOpen and'settings'or self.m.inspectCard and'inspect-card'or self.m.cardActionSheet and'native-card-actions'or self.m.commanderDetails and'commander-details'or self.m.zoneView and'zone-view'
        or self.m.galleryInspect and'gallery-inspect'or self.m.deleteConfirm and'delete-deck'or self.m.archiveCopy and'archive-copy'
        or self.m.confirmConcede and'concede-confirm'or self.combatStopsOpen and'combat-step-stops'or self.tableOptionsOpen and'table-options'
        or completedDuel and'match-complete'
        or self.cardChoiceModal
        or self.m.page=='builder'and(self.builderPopup and'builder-choice-popup'or self.builderFiltersOpen and'simplified-more-filters')
    local Window=require('lib.Slab.Internal.UI.Window')
    if self.inputLock~=(lock or nil)then
        require('lib.Slab.Internal.UI.Region').ClearHotInstance();self.S.SetInputFocus(nil)
    end
    if lock then Window.SetStackLock(lock);self.inputLock=lock
    elseif self.inputLock then Window.SetStackLock(nil);self.inputLock=nil end
    self.S.PushFont(self.r.fonts[16])
    if self.m.page=='decks' then self:decks(w,h)
    elseif self.m.page=='builder' then self:builder(w,h)
    elseif self.m.page=='lobby' then self:lobby(w,h)
    elseif self.m.page=='table'and not self.m.settingsOpen then self:table(w,h)
    elseif self.m.page=='replays' then self:replays(w,h) end
    if self.m.page=='gallery' then self:gallery(w,h) end
    if self.m.page=='rooms' then self:rooms(w,h) end
    if self.m.page=='draft' then self:draft(w,h) end
    if self.m.page=='import' then require('app.library_ui').import(self,w,h)end
    if self.m.page=='history' then require('app.library_ui').history(self,w,h)end
    if self.m.page=='tokens' then require('app.library_ui').tokens(self,w,h)end
    if self.m.page=='profile'then require('app.profile_ui').build(self,w,h)end
    if self.m.page=='settings'and not self.m.storageFolderDialog and not self.m.imagePackFileDialog and not self.m.storageLocationConfirm then self:settings(w,h,{fullPage=true})end
    self:modals(w,h)
    require('app.navigation').build(self,w,h)
    self.r.blockBuilderDrop=self.setPicker or self.brandMenu or self.m.cardPrintingPicker or self.m.tokenPicker or self.builderPopup or self.builderFiltersOpen or self.deckSelection or self.m.settingsOpen or self.m.imagePackFileDialog or self.m.inspectCard or self.m.storagePurgePreview
    self.S.PopFont()
end
return View
