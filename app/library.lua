-- Imports, artwork preferences and recorded match summaries. No game rules.
local API=require('app.api')
local json=require('lib.json')
local Library={}
local function clone(value)return json.decode(json.encode(value))end
local function clock()return love and love.timer and love.timer.getTime()or os.clock()end
local function adoptTokenPreferences(model,preferences)
    preferences=preferences or{};model.tokenMode=preferences.mode or'default';model.tokenSelected={}
    for _,id in ipairs(preferences.selected or{})do model.tokenSelected[id]=true end
    model.tokenOverrides=clone(preferences.overrides or{})
end
function Library.install(Model)
    if Model.libraryInstalled then return end;Model.libraryInstalled=true
    function Model:showImport(text)
        self.libraryOpening=(self.libraryOpening or 0)+1;self.importRevision=(self.importRevision or 0)+1
        self.importText=text or self.importText or '';self.importFormat=self.importFormat or self.format or'Commander'
        self.importPreview=nil;self.importError=nil;self.importBusy=false;self.page='import'
    end
    function Model:setImportText(text)
        self.importText=text;self.importRevision=(self.importRevision or 0)+1;self.importPreview=nil;self.importError=nil;self.importBusy=false
    end
    function Model:importDeckFile(file)
        self:showImport()
        local name=file and file.getFilename and file:getFilename()or''
        if not name:lower():match('%.txt$')and not name:lower():match('%.dec$')and not name:lower():match('%.cod$')and not name:lower():match('%.json$')and not name:lower():match('%.csv$')then self.importError='Drop a TXT, DEC, COD, CSV or JSON deck export';return false end
        local ok,text=pcall(function()
            if file.getSize and file:getSize()>1024*1024 then error('Deck export exceeds 1 MiB')end
            assert(file:open('r'));local body=file:read(1024*1024+1);file:close()
            assert(type(body)=='string'and#body<=1024*1024,'Deck export exceeds 1 MiB');return body
        end)
        if not ok then self.importError=tostring(text);return false end
        self:setImportText(text);self:previewDeckImport();return true
    end
    function Model:previewDeckImport()
        if self.importBusy then return false end
        local text=(self.importText or''):match('^%s*(.-)%s*$')
        if #text==0 or#text>1024*1024 then self.importError='Paste a deck export or public deck URL up to 1 MiB';return false end
        local opening,revision=self.libraryOpening,self.importRevision
        self.importBusy=true;self.importError=nil
        local body={format=self.importFormat,name=self.importName and self.importName~=''and self.importName or nil}
        if text:match('^https?://')then body.url=text else body.text=text end
        self:request('catalog','POST','/imports/preview',body,function(data,err)
            if opening~=self.libraryOpening or revision~=self.importRevision then return end
            self.importBusy=false;self.importPreview=data;self.importPreviewRevision=revision;self.importError=not data and(err or'Could not preview this deck')or nil
        end,true);return true
    end
    function Model:saveImportedDeck()
        local preview=self.importPreview
        if self.importBusy or not preview or self.importPreviewRevision~=self.importRevision or not(preview.validation or{}).saveAllowed then return false end
        local opening,revision=self.libraryOpening,self.importRevision
        self.importBusy=true;self.importError=nil
        self:request('catalog','POST','/decks',clone(preview.deck),function(data,err)
            if opening~=self.libraryOpening or revision~=self.importRevision then return end
            self.importBusy=false
            if data then self.importSavedDeck=data;self.importPreview=nil;if self.refreshDecks then self:refreshDecks()end
                if self.toast then self:toast((data.draft and'Draft saved: 'or'Deck saved: ')..data.name)end
                self.page='decks'
            else self.importError=err or'Deck could not be saved'end
        end);return true
    end
    function Model:showHistory()
        self.historyOpening=(self.historyOpening or 0)+1;self.historyOffset=0;self.historyItems={};self.page='history';self:refreshHistory()
    end
    function Model:refreshHistory()
        self.historyVersion=(self.historyVersion or 0)+1;local version,opening=self.historyVersion,self.historyOpening
        self.historyBusy=true;self.historyError=nil
        self:request('catalog','GET','/history?limit=12&offset='..tostring(self.historyOffset or 0),nil,function(data,err)
            if opening~=self.historyOpening or version~=self.historyVersion then return end
            self.historyBusy=false;self.historyItems=data and data.matches or{};self.historyTotal=data and data.total or 0;self.historyError=not data and(err or'History is unavailable')or nil
        end,true)
    end
    function Model:showTokenSettings(deckId)
        if self.closeTokenPicker then self:closeTokenPicker()end
        self.tokenOpening=(self.tokenOpening or 0)+1;self.tokenDeckId=deckId;self.tokenOffset=0;self.tokenQuery='';self.tokenItems={};self.tokenSelected={};self.tokenDirty=false;self.tokenMode='default';self.tokenOverrides={};self.tokenKnownArt={};self.tokenPicker=nil;self.tokenTimer=nil;self.tokenEditRevision=0;self.tokenSaving=false;self.page='tokens';self:refreshTokenSettings()
    end
    function Model:refreshTokenSettings()
        if not self.tokenDeckId then self.tokenError='Save this deck before choosing its token artwork';return end
        self.tokenVersion=(self.tokenVersion or 0)+1;local opening,version=self.tokenOpening,self.tokenVersion
        self.tokenBusy=true;self.tokenError=nil
        local path='/tokens?groups=1&deckId='..API.escape(self.tokenDeckId)..'&q='..API.escape(self.tokenQuery or'')..'&limit=12&offset='..tostring(self.tokenOffset or 0)
        self:request('catalog','GET',path,nil,function(data,err)
            if opening~=self.tokenOpening or version~=self.tokenVersion then return end
            self.tokenBusy=false
            if data then
                self.tokenItems=data.items or{};self.tokenTotal=data.total or 0
                for _,item in ipairs(self.tokenItems)do
                    for _,card in ipairs({item.defaultCard,item.activeCard,item.tokenImageId and item or nil})do if card then self.tokenKnownArt[card.tokenImageId]=card end end
                end
                if not self.tokenDirty then adoptTokenPreferences(self,data.preferences)end
            else self.tokenError=err or'Token metadata is unavailable'end
        end,true)
    end
    function Model:setTokenMode(mode)
        if mode~='default'and mode~='selected'and mode~='randomSelected'and mode~='randomAll'then return false end
        self.tokenMode=mode;self.tokenDirty=true;self.tokenEditRevision=(self.tokenEditRevision or 0)+1;return true
    end
    function Model:toggleTokenArt(id)
        for _,item in ipairs(self.tokenItems or{})do if item.tokenImageId==id then self.tokenSelected[id]=not self.tokenSelected[id]or nil;self.tokenDirty=true;self.tokenEditRevision=(self.tokenEditRevision or 0)+1;return true end end
        return false
    end
    function Model:tokenGroupPresentation(group)
        local pref=(self.tokenOverrides or{})[group.tokenIdentity]
        local mode=pref and pref.mode or self.tokenMode or'default'
        local selected=pref and pref.selected or{};if not pref then for id,on in pairs(self.tokenSelected or{})do if on then selected[#selected+1]=id end end end
        local card=group.defaultCard or group.activeCard or group
        local count=0
        if mode=='selected'or mode=='randomSelected'then
            local activeIds={};for _,id in ipairs(group.activeImageIds or{})do activeIds[id]=true end
            for _,id in ipairs(selected)do local art=(self.tokenKnownArt or{})[id];if(art and art.tokenIdentity==group.tokenIdentity)or activeIds[id]then count=count+1;if count==1 then card=art or group.activeCard or card end end end
            if count==0 then card=group.activeCard or card;count=#(group.activeImageIds or{})end
        elseif mode=='randomAll'then count=group.variantCount or 0
        else count=1 end
        return {mode=mode,card=card,count=count}
    end
    function Model:openTokenPicker(group)
        if not group or not group.tokenIdentity or self.tokenSaving then return false end
        local presentation=self:tokenGroupPresentation(group)
        local pref=(self.tokenOverrides or{})[group.tokenIdentity]
        local selected={};for _,id in ipairs(pref and pref.selected or group.activeImageIds or{})do selected[id]=true end
        self.tokenPicker={identity=group.tokenIdentity,group=group,mode=presentation.mode,selected=selected,items={},offset=0,total=group.variantCount or 0,query='',version=0}
        self:refreshTokenPicker();return true
    end
    function Model:refreshTokenPicker()
        local picker=self.tokenPicker;if not picker then return false end
        picker.version=picker.version+1;local version,opening=picker.version,self.tokenOpening;picker.busy=true;picker.error=nil
        local path='/tokens?deckId='..API.escape(self.tokenDeckId)..'&identity='..API.escape(picker.identity)..'&q='..API.escape(picker.query or'')..'&limit=12&offset='..picker.offset
        self:request('catalog','GET',path,nil,function(data,err)
            if self.tokenPicker~=picker or opening~=self.tokenOpening or version~=picker.version then return end
            picker.busy=false
            if data then picker.items=data.items or{};picker.total=data.total or 0;for _,item in ipairs(picker.items)do self.tokenKnownArt[item.tokenImageId]=item end
            else picker.error=err or'Token illustrations are unavailable'end
        end,true);return true
    end
    function Model:setTokenPickerMode(mode)
        local picker=self.tokenPicker;if not picker or(mode~='default'and mode~='selected'and mode~='randomSelected'and mode~='randomAll')then return false end
        picker.mode=mode;picker.error=nil
        if mode=='selected'then
            local first;for id,on in pairs(picker.selected)do if on and(not first or id<first)then first=id end end
            picker.selected={};if first then picker.selected[first]=true end
        end
        return true
    end
    function Model:toggleTokenPickerArt(id)
        local picker=self.tokenPicker;if not picker then return false end
        local found=false;for _,item in ipairs(picker.items)do if item.tokenImageId==id and item.tokenIdentity==picker.identity then found=true;break end end
        if not found then return false end
        if picker.mode=='randomSelected'then picker.selected[id]=not picker.selected[id]or nil
        else picker.mode='selected';picker.selected={[id]=true}end
        picker.error=nil;return true
    end
    function Model:applyTokenPicker()
        local picker=self.tokenPicker;if not picker then return false end
        local selected=json.array();for id,on in pairs(picker.selected)do if on then selected[#selected+1]=id end end;table.sort(selected)
        if(picker.mode=='selected'and#selected~=1)or(picker.mode=='randomSelected'and#selected==0)then picker.error='Select '..(picker.mode=='selected'and'one illustration'or'at least one illustration')..' before applying';return false end
        self.tokenOverrides[picker.identity]={mode=picker.mode,selected=selected};self.tokenDirty=true;self.tokenEditRevision=self.tokenEditRevision+1;self:closeTokenPicker();return true
    end
    function Model:closeTokenPicker()
        self.tokenPicker=nil;self.tokenPickerTimer=nil
        if self.tokenPickerLocked then require('lib.Slab.Internal.UI.Window').SetStackLock(nil);self.tokenPickerLocked=false end
    end
    function Model:saveTokenSettings()
        if self.tokenBusy or self.tokenSaving or self.tokenPicker or not self.tokenDeckId then return false end
        local selected=json.array();for id,on in pairs(self.tokenSelected or{})do if on then selected[#selected+1]=id end end;table.sort(selected)
        local opening,revision=self.tokenOpening,self.tokenEditRevision;self.tokenSaving=true;self.tokenError=nil
        local body={mode=self.tokenMode,selected=selected};if next(self.tokenOverrides or{})then body.overrides=clone(self.tokenOverrides)end
        self:request('catalog','PUT','/decks/'..API.escape(self.tokenDeckId)..'/token-art',body,function(data,err)
            if data then self.tokenArtGeneration=(self.tokenArtGeneration or 0)+1;self.tokenArtCache={}end
            if opening~=self.tokenOpening then return end;self.tokenSaving=false
            if data then if revision==self.tokenEditRevision then adoptTokenPreferences(self,data);self.tokenDirty=false end;if self.toast then self:toast('Token artwork saved')end
            else self.tokenError=err or'Token artwork could not be saved'end
        end);return true
    end
    function Model:artworkCard(card)
        -- These are native visual identities only. Never replace the host's
        -- token status, live values or targetable object ID with a component.
        local seen={}
        while type(card)=='table'and card~=json.null do
            if card.hidden or card.faceDown or card.metadataUnavailable or seen[card]then return nil end
            seen[card]=true
            local merged=card.mutate
            if type(merged)=='table'and merged~=json.null then
                if merged.topId==nil then return nil end
                local top
                for _,component in ipairs(merged.components or{})do
                    if component.id==merged.topId then top=component;break end
                end
                if not top then return nil end
                card=top
            elseif(card.token or card.isToken)and type(card.copySourceCard)=='table'and card.copySourceCard~=json.null then
                card=card.copySourceCard
            else return card end
        end
    end
    function Model:resolveTokenCard(card)
        if not card or not(card.token or card.isToken)or card.hidden then return nil end
        self.tokenArtCache=self.tokenArtCache or{}
        local deckId
        if self.roomConnectionId then
            if self.room and self.room.config and self.room.config.kind~='draft'then deckId=self.roomDeckId end
        else deckId=self.activeDeckId or self.lastMatchDeckId end
        local template=type(card.tokenTemplate)=='table'and card.tokenTemplate~=json.null and card.tokenTemplate or nil
        local printed=template and(template.printing or template)or card.printing
        local descriptor={name=template and(template.name or template.displayName)or card.name or card.displayName,type=template and template.type or card.type,type_line=template and template.type_line or card.type_line,power=card.power,toughness=card.toughness,colors=card.colors,printing=printed}
        local nativeId=tostring(card.objectId or card.nativeId or card.id or descriptor.name)
        local key=tostring(deckId or'')..':'..nativeId..':'..json.encode(descriptor)
        local cached=self.tokenArtCache[key];local time=clock()
        if cached then cached.used=time;if cached.card then return cached.card end;if cached.pending or(cached.retryAt or 0)>time then return nil end end
        if(self.tokenResolvePending or 0)>=4 then return nil end
        cached={pending=true,used=time};self.tokenArtCache[key]=cached;self.tokenResolvePending=(self.tokenResolvePending or 0)+1
        local generation=self.tokenArtGeneration or 0
        self:request('catalog','POST','/tokens/resolve',{deckId=deckId,token=descriptor,seed=nativeId},function(data)
            self.tokenResolvePending=math.max(0,(self.tokenResolvePending or 1)-1)
            if generation~=(self.tokenArtGeneration or 0)or self.tokenArtCache[key]~=cached then return end
            cached.pending=false;cached.retryAt=clock()+30;cached.card=data and data.card~=json.null and data.card or nil
            local count=0;for _ in pairs(self.tokenArtCache)do count=count+1 end
            if count>128 then local oldest,used;for candidate,item in pairs(self.tokenArtCache)do if candidate~=key and not item.pending and(not used or item.used<used)then oldest,used=candidate,item.used end end;if oldest then self.tokenArtCache[oldest]=nil end end
        end,true)
        return nil
    end
    local baseGetArt=Model.getArt
    if baseGetArt then function Model:getArt(card,force,kind,options)
        if not force and self.settings and self.settings.showCardArt==false then return nil end
        card=self:artworkCard(card);if not card then return nil end
        if card and(card.token or card.isToken)and not card.tokenImageId then
            local resolved=self:resolveTokenCard(card);if not resolved then return nil end
            return baseGetArt(self,resolved,force,kind,options)
        end
        return baseGetArt(self,card,force,kind,options)
    end end
    function Model:updateLibrary(dt)
        if self.page=='history'then self.historyTimer=(self.historyTimer or 5)-dt;if self.historyTimer<=0 then self.historyTimer=5;if not self.historyBusy then self:refreshHistory()end end end
        if self.tokenTimer then self.tokenTimer=self.tokenTimer-dt;if self.tokenTimer<=0 then self.tokenTimer=nil;self:refreshTokenSettings()end end
        if self.tokenPickerTimer then self.tokenPickerTimer=self.tokenPickerTimer-dt;if self.tokenPickerTimer<=0 then self.tokenPickerTimer=nil;self:refreshTokenPicker()end end
    end
end
return Library
