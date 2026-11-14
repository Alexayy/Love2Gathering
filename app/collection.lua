local API=require('app.api')
local json=require('lib.json')
local Collection={formats={'All','Modern','Standard','Pioneer','Commander','Archive'}}
local playable={Modern=true,Standard=true,Pioneer=true,Commander=true}
function Collection.format(m)return m.collectionFormat or m.format or'All'end
function Collection.sections(m)
    m.uiLayout=m.uiLayout or{};m.uiLayout.collection=m.uiLayout.collection or{collapsed={starter=true}}
    m.uiLayout.collection.collapsed=m.uiLayout.collection.collapsed or{}
    return m.uiLayout.collection.collapsed
end
function Collection.install(Model)
    local find,open=Model.findDeck,Model.openDeck
    function Model:findDeck(id)
        local deck=find(self,id);if deck then return deck end
        for _,starter in ipairs(self.starterDecks or{})do if starter.id==id then return starter end end
    end
    function Model:toggleCollectionSection(key)
        local state=Collection.sections(self);state[key]=not state[key];self.uiLayoutTimer=.4
    end
    function Model:setCollectionFormat(value)
        self.collectionFormat=value;if playable[value]then self.format=value end
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
        if not playable[format or deck.format]or(auxiliary>0 and not confirmed)then
            self.archiveCopy={deck=deck,format=playable[format or deck.format]and(format or deck.format)or self.format,callback=callback,auxiliary=auxiliary>0};return
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
