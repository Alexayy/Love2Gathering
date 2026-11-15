local API=require('app.api')
local json=require('lib.json')
local Collection={formats={'All','Modern','Standard','Pioneer','Commander','Archive'}}
local function playable(m,format)
    if m.playFormats then for _,id in ipairs(m:playFormats())do if id==format then return true end end;return false end
    return format=='Modern'or format=='Standard'or format=='Pioneer'or format=='Commander'
end
local function cacheTime()return love and love.timer and love.timer.getTime()or os.clock()end
local function cachedProduct(m,key)
    local cache=m.lobbyProductCache;local entry=cache and cache.entries[key]
    if not entry or cacheTime()-entry.at>120 then return nil end
    cache.clock=cache.clock+1;entry.used=cache.clock
    return json.decode(entry.body)
end
local function rememberProduct(m,key,data)
    local body=json.encode(data);if #body>1024*1024 then return end
    local cache=m.lobbyProductCache or{entries={},clock=0};m.lobbyProductCache=cache
    cache.clock=cache.clock+1;cache.entries[key]={body=body,at=cacheTime(),used=cache.clock}
    local count,bytes=0,0;for _,entry in pairs(cache.entries)do count=count+1;bytes=bytes+#entry.body end
    while count>16 or bytes>4*1024*1024 do
        local oldest,used;for id,entry in pairs(cache.entries)do if not used or entry.used<used then oldest,used=id,entry.used end end
        bytes=bytes-#cache.entries[oldest].body;cache.entries[oldest]=nil;count=count-1
    end
end
function Collection.format(m)return m.collectionFormat or m.format or'All'end
function Collection.sections(m)
    m.uiLayout=m.uiLayout or{};m.uiLayout.collection=m.uiLayout.collection or{collapsed={starter=true}}
    m.uiLayout.collection.collapsed=m.uiLayout.collection.collapsed or{}
    return m.uiLayout.collection.collapsed
end
function Collection.install(Model)
    local find,open=Model.findDeck,Model.openDeck
    function Model:deckCoverArt(deck,options)
        local card=deck and(deck.cover or self:deckCoverCard(deck))
        if type(card)=='string'then card={name=card}end
        if not card or not card.name then return nil end
        if not(self.catalogHealth and self.catalogHealth.deckCovers)then
            return self:getArt(card,true,'art_crop',options)or self:getArt(card,true,'normal',options)
        end
        local store=self.catalogHealth.storage or{};local context=table.concat({tostring(self.api.catalogPort),self.catalogHealth.catalogSource or'',store.dataDirectory or''},'|')
        local printing=card.selectedPrintingId or(card.printingExact and card.printing_id)or''
        local source=deck.sourceDeckId or deck.id or'';local key=table.concat({context,source,card.name,printing},'\31')
        self.deckCoverMetadata=self.deckCoverMetadata or{};local cache=self.deckCoverMetadata;local entry=cache[key];local now=cacheTime()
        if entry and not entry.pending and now-(entry.at or 0)>60 then cache[key]=nil;entry=nil end
        if not entry and(self.deckCoverMetadataPending or 0)<4 then
            entry={pending=true,at=now};cache[key]=entry;self.deckCoverMetadataPending=(self.deckCoverMetadataPending or 0)+1
            local path='/deck-cover?name='..API.escape(card.name)..'&deckId='..API.escape(source)
            if printing~=''then path=path..'&printing='..API.escape(printing)end
            self:request('catalog','GET',path,nil,function(data,problem)
                self.deckCoverMetadataPending=math.max(0,(self.deckCoverMetadataPending or 1)-1)
                if cache[key]~=entry then return end
                entry.pending=false;entry.at=cacheTime();entry.data=data;entry.error=problem
            end,true)
            local count=0;for _ in pairs(cache)do count=count+1 end
            while count>64 do local oldest,at;for candidate,value in pairs(cache)do if candidate~=key and not value.pending and(not at or value.at<at)then oldest,at=candidate,value.at end end;if not oldest then break end;cache[oldest]=nil;count=count-1 end
        end
        if entry and entry.data and entry.data.card then return self:getArt(entry.data.card,true,entry.data.kind or'art_crop',options)end
        return nil
    end
    function Model:findDeck(id)
        local deck=find(self,id);if deck then return deck end
        for _,starter in ipairs(self.starterDecks or{})do if starter.id==id then return starter end end
        return self.lobbyPrecons and self.lobbyPrecons[id]
    end
    function Model:lobbyPickerCurrent(state)
        return state and not state.closed and self.lobbyDeckPicker==state and(not state.openPage or state.openPage==self.page)
    end
    function Model:loadLobbyStarters(state)
        if self.startersLoaded or state.startersBusy or not self:lobbyPickerCurrent(state)then return end
        state.startersBusy=true
        self:request('catalog','GET','/decks?origin=starter',nil,function(data,err)
            if not self:lobbyPickerCurrent(state)then return end
            state.startersBusy=false;state.startersError=err
            if data then
                self.starterDecks=data.decks or data
                for _,deck in ipairs(self.starterDecks)do for _,zone in ipairs({'main','sideboard','commander'})do deck[zone]=json.array(deck[zone]or{})end end
                self.startersLoaded=true
            end
        end,true)
    end
    function Model:queryLobbyPrecons(state,force)
        if not self:lobbyPickerCurrent(state)then return end
        state.queryVersion=(state.queryVersion or 0)+1;local version=state.queryVersion
        state.busy=true;state.error=nil;state.timer=nil
        local path='/precons?category=deck&format='..API.escape(state.format)..'&q='..API.escape(state.search or'')..'&limit=24&offset='..tostring(state.offset or 0)
        local cached=not force and cachedProduct(self,path)
        if cached then state.busy=false;state.precons=cached.decks or cached.items or{};state.total=cached.total or#state.precons;return end
        self:request('catalog','GET',path,nil,function(data,err)
            if not self:lobbyPickerCurrent(state)or state.queryVersion~=version then return end
            state.busy=false;state.error=err
            if data then rememberProduct(self,path,data);state.precons=data.decks or data.items or{};state.total=data.total or#state.precons end
        end,true)
    end
    function Model:searchLobbyPrecons(state)
        if not self:lobbyPickerCurrent(state)then return end
        state.queryVersion=(state.queryVersion or 0)+1;state.selectionVersion=(state.selectionVersion or 0)+1
        state.precons={};state.offset=0;state.busy=false;state.detailBusy=false;state.confirmAuxiliary=nil;state.timer=.25
    end
    function Model:cacheLobbyPrecon(state,source,confirmed)
        if not self:lobbyPickerCurrent(state)then return end
        local auxiliary=math.max(tonumber(source.counts and source.counts.planes)or 0,#(source.planes or{}))+math.max(tonumber(source.counts and source.counts.schemes)or 0,#(source.schemes or{}))
        if auxiliary>0 and not confirmed then state.confirmAuxiliary={source=source,count=auxiliary};return end
        local deck=json.decode(json.encode(source));deck.id='lobby-'..state.format:lower()..'-'..source.id
        deck.sourceDeckId=source.id;deck.historicalFormat=source.historicalFormat or source.format;deck.format=state.format
        deck.origin='lobby-preconstructed';deck.immutable=true;deck.nativeValidationRequired=true
        for _,zone in ipairs({'main','sideboard','commander'})do deck[zone]=json.array(deck[zone]or{})end
        if auxiliary>0 then deck.planes=nil;deck.schemes=nil;deck.excludedAuxiliary={count=auxiliary,confirmed=true}end
        self.lobbyPrecons=self.lobbyPrecons or{};self.lobbyPreconUsage=self.lobbyPreconUsage or{}
        self.lobbyPreconClock=(self.lobbyPreconClock or 0)+1;self.lobbyPrecons[deck.id]=deck;self.lobbyPreconUsage[deck.id]=self.lobbyPreconClock
        local protected={[deck.id]=true};for _,key in ipairs({'playerDeckId','botDeckId','roomDeckId'})do if self[key]then protected[self[key]]=true end end
        for _,key in pairs(self.botDeckIds or{})do protected[key]=true end
        local count,oldest,used=0,nil,math.huge
        for key in pairs(self.lobbyPrecons)do count=count+1;if not protected[key]and(self.lobbyPreconUsage[key]or 0)<used then oldest=key;used=self.lobbyPreconUsage[key]or 0 end end
        if count>16 and oldest then self.lobbyPrecons[oldest]=nil;self.lobbyPreconUsage[oldest]=nil end
        state.selected=deck.id;state.closed=true;if self.lobbyDeckPicker==state then self.lobbyDeckPicker=nil end;state.changed(deck.id)
        return deck
    end
    function Model:selectLobbyPrecon(state,summary)
        if not self:lobbyPickerCurrent(state)or state.detailBusy then return end
        state.selectionVersion=(state.selectionVersion or 0)+1;local version=state.selectionVersion;local query=state.queryVersion
        state.detailBusy=true;state.error=nil
        local path='/precons/'..API.escape(summary.id);local cached=cachedProduct(self,path)
        if cached then state.detailBusy=false;return self:cacheLobbyPrecon(state,cached.deck or cached,false)end
        self:request('catalog','GET',path,nil,function(data,err)
            if not self:lobbyPickerCurrent(state)or state.selectionVersion~=version or state.queryVersion~=query then return end
            state.detailBusy=false;state.error=err
            if data then rememberProduct(self,path,data);self:cacheLobbyPrecon(state,data.deck or data,false)end
        end)
    end
    function Model:toggleCollectionSection(key)
        local state=Collection.sections(self);state[key]=not state[key];self.uiLayoutTimer=.4
    end
    function Model:setCollectionFormat(value)
        self.collectionFormat=value;if playable(self,value)then self.format=value end
        self.preconVersion=(self.preconVersion or 0)+1;self.preconError=nil
        self.preconOffset=0;self.preconTimer=0;self.selectedDeck=nil;self.collectionScrollReset=true
    end
    function Model:collectionSearchChanged()
        self.preconVersion=(self.preconVersion or 0)+1;self.preconError=nil
        self.preconOffset=0;self.preconTimer=.25;self.selectedDeck=nil;self.collectionScrollReset=true
    end
    function Model:refreshPrecons()
        local version=(self.preconVersion or 0)+1;self.preconVersion=version;self.preconsBusy=true
        local path='/precons?limit=24&offset='..tostring(self.preconOffset or 0)..'&q='..API.escape(self.collectionSearch or'')..'&category='..(self.preconCategory or'deck')
        local format=Collection.format(self);if format~='All'then path=path..'&format='..API.escape(format)end
        self:request('catalog','GET',path,nil,function(data,err)
            if self.preconVersion~=version then return end
            self.preconsBusy=false;self.preconError=err
            if data then self.precons=data.decks or data.items or{};self.preconsTotal=data.total or#self.precons;self.preconFacets=data.facets;self.preconLoaded=true end
        end,true)
    end
    function Model:pagePrecons(delta)
        local offset=math.max(0,(self.preconOffset or 0)+delta*24)
        if offset>=(self.preconsTotal or 0)and delta>0 then return end
        self.preconOffset=offset;self.preconTimer=0;self.collectionScrollReset=true
        self.preconVersion=(self.preconVersion or 0)+1
    end
    function Model:updateCollection(dt)
        local picker=self.lobbyDeckPicker
        if picker and self:lobbyPickerCurrent(picker)and picker.timer then
            picker.timer=picker.timer-dt;if picker.timer<=0 then self:queryLobbyPrecons(picker)end
        end
        if self.page~='decks'or not self.catalogHealth.ready then return end
        self.collectionClock=(self.collectionClock or 0)+dt
        if not self.preconStats and not self.preconStatsBusy and self.collectionClock>=(self.nextStatsRetry or 0)then
            self.preconStatsBusy=true;self.nextStatsRetry=self.collectionClock+30
            self:request('catalog','GET','/precons/stats',nil,function(data)self.preconStatsBusy=false;if data then self.preconStats=data end end,true)
        end
        if not self.startersLoaded and not self.startersBusy and self.collectionClock>=(self.nextStarterRetry or 0)then
            self.startersBusy=true;self.nextStarterRetry=self.collectionClock+30
            self:request('catalog','GET','/decks?origin=starter',nil,function(data)
                self.startersBusy=false
                if data then
                    self.starterDecks=data.decks or data
                    for _,deck in ipairs(self.starterDecks)do for _,zone in ipairs({'main','sideboard','commander'})do deck[zone]=json.array(deck[zone]or{})end end
                    self.startersLoaded=true
                end
            end,true)
        end
        if not self.preconLoaded and not self.preconsBusy and not self.preconError then self.preconTimer=0 end
        if self.preconTimer then self.preconTimer=self.preconTimer-dt;if self.preconTimer<=0 then self.preconTimer=nil;self:refreshPrecons()end end
    end
    function Model:collectionDeck(id)
        local stored=self:findDeck(id);if stored then return stored end
        if self.preconDetails and self.preconDetails[id]then return self.preconDetails[id]end
        for _,deck in ipairs(self.precons or{})do if deck.id==id then return deck end end
    end
    function Model:selectCollectionDeck(deck)
        self.selectedDeck=deck.id
        self.preconDetailVersion=(self.preconDetailVersion or 0)+1;self.preconDetailBusy=false
        if deck.origin~='preconstructed'and not deck.preconstructed then return end
        self.preconDetailClock=(self.preconDetailClock or 0)+1;self.preconDetailUsage=self.preconDetailUsage or{}
        self.preconDetailUsage[deck.id]=self.preconDetailClock
        if self.preconDetails and self.preconDetails[deck.id]then return end
        self.preconDetails=self.preconDetails or{};local version=self.preconDetailVersion;self.preconDetailBusy=true
        self:request('catalog','GET','/precons/'..API.escape(deck.id),nil,function(data)
            if self.preconDetailVersion~=version then return end
            self.preconDetailBusy=false
            if data then
                self.preconDetails[deck.id]=data.deck or data
                local count,oldest,used=0,nil,math.huge
                for key in pairs(self.preconDetails)do
                    count=count+1
                    if key~=self.selectedDeck and(self.preconDetailUsage[key]or 0)<used then oldest=key;used=self.preconDetailUsage[key]or 0 end
                end
                if count>16 and oldest then self.preconDetails[oldest]=nil;self.preconDetailUsage[oldest]=nil end
            end
        end)
    end
    function Model:forkCollectionDeck(deck,format,callback,confirmed)
        if self.collectionForkBusy then return end
        local auxiliary=(deck.counts and((deck.counts.planes or 0)+(deck.counts.schemes or 0))or 0)+#(deck.planes or{})+#(deck.schemes or{})
        if not playable(self,format or deck.format)or(auxiliary>0 and not confirmed)then
            self.archiveCopy={deck=deck,format=playable(self,format or deck.format)and(format or deck.format)or self.format,callback=callback,auxiliary=auxiliary>0};return
        end
        self.collectionForkBusy=true
        local page,selection,generation,revision=self.page,self.selectedDeck,self.editGeneration or 0,self.deckRevision or 0
        local name,cover=self.editDeck and self.editDeck.name,self.editDeck and self.editDeck.coverCard
        self:request('catalog','POST','/decks/'..API.escape(deck.id)..'/fork',{format=format or deck.format},function(data,err,failed)
            self.collectionForkBusy=false
            local current=self.page==page and self.selectedDeck==selection and(self.editGeneration or 0)==generation and(self.deckRevision or 0)==revision and(self.editDeck and self.editDeck.name)==name and(self.editDeck and self.editDeck.coverCard)==cover
            if not data then
                if current and failed and failed.saved==false and failed.deck then
                    open(self,failed.deck);self.dirty=true;self.validation=failed.validation;self.lastBuilderError=err
                end
                return
            end
            local saved=data.deck or data
            if not saved.id then self:toast('The saved deck has no identity',true);return end
            saved.origin='user';for _,zone in ipairs({'main','sideboard','commander'})do saved[zone]=json.array(saved[zone]or{})end
            self.decks[#self.decks+1]=saved;Collection.sections(self).user=false
            self:refreshDecks()
            if current then self.selectedDeck=saved.id;if callback then callback(saved)end end
        end)
    end
    function Model:openDeck(deck)
        if deck and(deck.origin=='bundled'or deck.origin=='starter'or deck.origin=='preconstructed'or deck.preconstructed)then
            return self:forkCollectionDeck(deck,deck.format,function(saved)open(self,saved)end)
        end
        return open(self,deck)
    end
    function Model:useCollectionDeck(deck)
        if deck.origin=='user'and(deck.draft or deck.playable==false)then self:openDeck(deck);self:toast('Complete this saved deck before playing',true);return end
        if deck.origin=='preconstructed'or deck.preconstructed then
            self:forkCollectionDeck(deck,deck.format,function(saved)
                if saved.draft or saved.playable==false then self:openDeck(saved);self:toast('Complete this saved deck before playing',true)
                else self:lobbyDeck(saved)end
            end)
        else self:lobbyDeck(deck)end
    end
end
return Collection
