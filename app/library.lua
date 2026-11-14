-- Imports, artwork preferences and recorded match summaries. No game rules.
local API=require('app.api')
local json=require('lib.json')
local Library={}
local function clone(value)return json.decode(json.encode(value))end
local function clock()return love and love.timer and love.timer.getTime()or os.clock()end
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
        self.tokenOpening=(self.tokenOpening or 0)+1;self.tokenDeckId=deckId;self.tokenOffset=0;self.tokenQuery='';self.tokenItems={};self.tokenSelected={};self.tokenDirty=false;self.tokenMode='default';self.page='tokens';self:refreshTokenSettings()
    end
    function Model:refreshTokenSettings()
        if not self.tokenDeckId then self.tokenError='Save this deck before choosing its token artwork';return end
        self.tokenVersion=(self.tokenVersion or 0)+1;local opening,version=self.tokenOpening,self.tokenVersion
        self.tokenBusy=true;self.tokenError=nil
        local path='/tokens?deckId='..API.escape(self.tokenDeckId)..'&q='..API.escape(self.tokenQuery or'')..'&limit=12&offset='..tostring(self.tokenOffset or 0)
        self:request('catalog','GET',path,nil,function(data,err)
            if opening~=self.tokenOpening or version~=self.tokenVersion then return end
            self.tokenBusy=false
            if data then
                self.tokenItems=data.items or{};self.tokenTotal=data.total or 0
                if not self.tokenDirty then self.tokenMode=(data.preferences or{}).mode or'default';self.tokenSelected={};for _,id in ipairs((data.preferences or{}).selected or{})do self.tokenSelected[id]=true end end
            else self.tokenError=err or'Token metadata is unavailable'end
        end,true)
    end
    function Model:setTokenMode(mode)
        if mode~='default'and mode~='randomSelected'and mode~='randomAll'then return false end
        self.tokenMode=mode;self.tokenDirty=true;return true
    end
    function Model:toggleTokenArt(id)
        for _,item in ipairs(self.tokenItems or{})do if item.tokenImageId==id then self.tokenSelected[id]=not self.tokenSelected[id]or nil;self.tokenDirty=true;return true end end
        return false
    end
    function Model:saveTokenSettings()
        if self.tokenBusy or not self.tokenDeckId then return false end
        local selected=json.array();for id,on in pairs(self.tokenSelected or{})do if on then selected[#selected+1]=id end end;table.sort(selected)
        local opening=self.tokenOpening;self.tokenBusy=true
        self:request('catalog','PUT','/decks/'..API.escape(self.tokenDeckId)..'/token-art',{mode=self.tokenMode,selected=selected},function(data,err)
            if opening~=self.tokenOpening then return end;self.tokenBusy=false
            if data then self.tokenDirty=false;self.tokenArtGeneration=(self.tokenArtGeneration or 0)+1;self.tokenArtCache={};if self.toast then self:toast('Token artwork saved')end
            else self.tokenError=err or'Token artwork could not be saved'end
        end);return true
    end
    function Model:resolveTokenCard(card)
        if not card or not(card.token or card.isToken)or card.hidden then return nil end
        self.tokenArtCache=self.tokenArtCache or{}
        local deckId
        if self.roomConnectionId then
            if self.room and self.room.config and self.room.config.kind~='draft'then deckId=self.roomDeckId end
        else deckId=self.activeDeckId or self.lastMatchDeckId end
        local descriptor={name=card.name or card.displayName,type=card.type,type_line=card.type_line,power=card.power,toughness=card.toughness,colors=card.colors,printing=card.printing}
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
    if baseGetArt then function Model:getArt(card,force,kind)
        if not force and self.settings and self.settings.showCardArt==false then return nil end
        if card and(card.token or card.isToken)and not card.tokenImageId then
            local resolved=self:resolveTokenCard(card);if not resolved then return nil end
            return baseGetArt(self,resolved,force,kind)
        end
        return baseGetArt(self,card,force,kind)
    end end
    function Model:updateLibrary(dt)
        if self.page=='history'then self.historyTimer=(self.historyTimer or 5)-dt;if self.historyTimer<=0 then self.historyTimer=5;if not self.historyBusy then self:refreshHistory()end end end
        if self.tokenTimer then self.tokenTimer=self.tokenTimer-dt;if self.tokenTimer<=0 then self.tokenTimer=nil;self:refreshTokenSettings()end end
    end
end
return Library
