local API=require('app.api')
local json=require('lib.json')
local Model={};Model.__index=Model
local defaults={manualTriggers=false,autoMana=true,showCardArt=true,localArtworkOnly=true,artworkMemoryMiB=256,resolution='Desktop',windowMode='Borderless',vsync=true,msaa=0,renderScale=1,textureFilter='linear',frameLimit=0,uiScale=1,animations=true,particles=true,musicEnabled=false,musicVolume=.25,sfxEnabled=true,sfxVolume=.45,masterVolume=.7,reducedMotion=false,highContrast=false,colorblindMode='Off',showTooltips=true,titleFontFamily='Beleren',skybox='Galaxy',skyboxBrightness=.32,playmatOpacity=.88,counterStyle='Dice',cursorStyle='Kenney',keywordReminders=true,fontFamily='Beleren',panelOpacity=.65,theme='Midnight',accentColor='',opponentColor='',autoFollowTurn=false,builderLayout='Classic',presentationVersion=2,fontQuality='High',cursorScale=.55,boardImpactIntensity=.55,cardBackStyle='Arcane',vfxIntensity=.65,ambientKeywordFX=true,presentationPacing='Standard',cameraShake=true,parallax=true,distortion=true,cardScale=1,groupEquivalent=true}
local function copy(t) return json.decode(json.encode(t)) end
local function errorText(body,err,code)
    if err then return err end
    if code and code>=400 then return type(body)=='table' and tostring(body.error or body.message or ('HTTP '..code)) or ('HTTP '..code) end
end
function Model.new()
    local self=setmetatable({api=API.new(),page='decks',decks={},format='Modern',selectedDeck=nil,search='',searchFormat='All',searchColor='All',searchColors={},searchColorExact=false,searchType='',cards={},total=0,offset=0,searchTimer=0.1,
        settings=copy(defaults),catalogHealth={},engineHealth={},healthTimer=0,pollTimer=0,searchSort='Name',searchSet='All',sets={},searchLimit=12,deckSort='Name',validation=nil,
        art={},byName={},lookupPending={},artPending=0,toasts={},botDeckId=nil,botDeckIds={},commanderPlayers=4,commanderDamage=true,playerDeckId=nil,playerName='Planeswalker',game=nil,gameBusy=false,selectedSection='main',promptOrder={},orderPrompt=nil},Model)
    return self
end
function Model:toast(message,bad)
    self.toasts[#self.toasts+1]={message=tostring(message),bad=bad,ttl=7}
    if #self.toasts>4 then table.remove(self.toasts,1) end
end
function Model:request(service,method,path,body,callback,quiet)
    if self.storageLocationBlocked and service=='catalog'and method~='GET'and not path:find('^/storage/locations')then
        local message='Storage is paused. Restart or cancel the prepared location change before saving.'
        if not quiet then self:toast(message,true)end;if callback then callback(nil,message)end;return false
    end
    return self.api:request(service,method,path,body,function(data,err,code)
        local problem=errorText(data,err,code)
        if problem then if not quiet then self:toast(problem,true) end; if callback then callback(nil,problem,data) end
        elseif callback then callback(data) end
    end)
end
function Model:refreshDecks(callback)
    local version=(self.deckRefreshVersion or 0)+1;self.deckRefreshVersion=version
    self:request('catalog','GET','/decks',nil,function(data,err)
        if version~=self.deckRefreshVersion then return end
        if not data then if callback then callback(nil,err)end;return end
        self.decks=data.decks or data
        for _,deck in ipairs(self.decks) do for _,zone in ipairs({'main','sideboard','commander'}) do deck[zone]=json.array(deck[zone] or {}) end end
        self:syncLobbyDecks()
        if callback then callback(data)end
    end,true)
end
function Model:update(dt)
    self.api:update()
    self:updateReplays(dt);self:updateUILayout(dt);self:updateGallery(dt);self:updateRooms(dt);self:updateLibrary(dt);self:updateCollection(dt);self:updateProfile(dt);self:updateStorage(dt);self:updateImagePacks(dt);self:updateCardPrintings(dt)
    if self.validationTimer then self.validationTimer=self.validationTimer-dt;if self.validationTimer<=0 then self.validationTimer=nil;self:validateDeck() end end
    for i=#self.toasts,1,-1 do self.toasts[i].ttl=self.toasts[i].ttl-dt;if self.toasts[i].ttl<=0 then table.remove(self.toasts,i) end end
    self.healthTimer=self.healthTimer-dt
    if self.healthTimer<=0 then
        self.healthTimer=3
        self:request('catalog','GET','/health',nil,function(data,err)
            local wasReady=self.catalogHealth.ready
            self.catalogHealth=data or {error=err}
            if data then self:beginStartupHydration()end
            if data and data.ready and not wasReady then self.searchTimer=0 end
        end,true)
        self:request('engine','GET','/health',nil,function(data,err) self.engineHealth=data or {error=err} end,true)
    end
    if self.searchTimer then
        self.searchTimer=self.searchTimer-dt
        if self.searchTimer<=0 then self.searchTimer=nil;if self.catalogHealth.ready then self:searchCards() end end
    end
    if self.game and not self.replay and (not self.roomGameActive or (self.room and self.room.phase=='playing')) then
        self.pollTimer=self.pollTimer-dt
        if self.pollTimer<=0 and not self.polling then
            self.pollTimer=.22;self.polling=true
            self.pollRequest=(self.pollRequest or 0)+1;local request=self.pollRequest
            local generation=self.api.routeGeneration
            self:request('engine','GET','/session/state',nil,function(data,err)
                if request~=self.pollRequest then return end
                self.polling=false
                if generation~=self.api.routeGeneration or self.gameBusy then return end
                if data then self:setGame(data) elseif err and not self.gameConnectionError then self.gameConnectionError=true;self:toast('Engine connection: '..err,true) end
            end,true)
        end
    end
end
function Model:searchChanged() self.offset=0;self.searchTimer=.23 end
function Model:rememberCard(card)
    if not card or not card.name then return end
    self.nameCacheAge=self.nameCacheAge or{};self.nameCacheTick=(self.nameCacheTick or 0)+1
    self.byName[card.name]=card;self.nameCacheAge[card.name]=self.nameCacheTick
    local count=0;for _ in pairs(self.byName)do count=count+1 end
    while count>512 do
        local oldest,age
        for name in pairs(self.byName)do local used=self.nameCacheAge[name]or 0;if name~=card.name and(not age or used<age)then oldest,age=name,used end end
        if not oldest then break end
        self.byName[oldest]=nil;self.nameCacheAge[oldest]=nil;count=count-1
    end
end
function Model:searchCards()
    local version=(self.searchVersion or 0)+1;self.searchVersion=version;self.searchBusy=true;self.searchError=nil
    local path='/cards?q='..API.escape(self.search)..'&limit='..self.searchLimit..'&offset='..self.offset..'&sort='..API.escape(self.searchSort:lower())
    if self.searchFormat~='All' then path=path..'&format='..API.escape(self.searchFormat:lower()) end
    if self.settings.builderLayout=='Simplified'then
        local colors=require('app.builder_colors').symbols(self)
        if colors~=''then path=path..'&color='..colors..'&colorMode='..(self.searchColorExact and'exact'or'any')end
    elseif self.searchColor~='All'then path=path..'&color='..API.escape(self.searchColor)end
    if self.searchType~='' then path=path..'&type='..API.escape(self.searchType) end
    if self.searchSet~='All' then path=path..'&set='..API.escape(self.searchSet) end
    self:request('catalog','GET',path,nil,function(data,err)
        if version~=self.searchVersion then return end
        self.searchBusy=false;self.searchError=err
        if data then self.cards=data.cards or {};self.total=data.total or #self.cards;self.searchFilterInfo={formatId=data.formatId,snapshotFilterAvailable=data.snapshotFilterAvailable,snapshotLegalityChecked=data.snapshotLegalityChecked,nativeValidationRequired=data.nativeValidationRequired};for _,card in ipairs(self.cards) do self:rememberCard(card)end end
    end)
end
function Model:refreshSets()
    self.setsVersion=(self.setsVersion or 0)+1;local version=self.setsVersion
    local format,generation=self.searchFormat,self.editGeneration
    if self.setsFormat~=format then self.sets={}end
    self.setsBusy=true;self.setsError=nil
    local path='/sets';if format~='All'then path=path..'?format='..API.escape(format:lower())end
    self:request('catalog','GET',path,nil,function(data,err)
        if version~=self.setsVersion then return end
        self.setsBusy=false
        if format~=self.searchFormat or generation~=self.editGeneration then return end
        self.setsError=err
        if data then self.sets=data.sets or{};self.setsFormat=format end
    end,true)
end
function Model:setSearchLimit(limit)
    limit=math.max(1,math.floor(limit));if limit~=self.searchLimit then self.searchLimit=limit;self:searchChanged() end
end
function Model:cardData(card)
    if not card then return nil end
    if card.hidden or card.faceDown then return card end
    if card.oracle_text or card.image_uris then return card end
    local name=card.name or card.displayName
    if not name then return card end
    if self.byName[name] then
        self.nameCacheAge=self.nameCacheAge or{};self.nameCacheTick=(self.nameCacheTick or 0)+1;self.nameCacheAge[name]=self.nameCacheTick
        local data=copy(self.byName[name])
        -- Catalog IDs select images; native IDs select game objects. Keep both.
        data.objectId=card.id
        for _,key in ipairs({'power','toughness','damage','counters','printing','currentRules','currentKeywords','mechanicCapabilities','zone','zoneName','keywords','abilityIcons','permanent','ownerId','controllerId','token','isToken','colors','subtypes','supertypes','tokenSourceId','tokenSourceName','tokenTemplate','copySourceCard','mutate','attachedToId','attachedToPlayerId','attachmentIds','linkedExile','attacking','blocking'})do
            if card[key]~=nil then data[key]=card[key]end
        end
        return data
    end
    if (not self.lookupPending[name] or self.lookupPending[name]<love.timer.getTime()) and self.catalogHealth.ready then
        self.lookupPending[name]=love.timer.getTime()+30
        self:request('catalog','GET','/cards/by-name?name='..API.escape(name),nil,function(data)
            if data then self:rememberCard(data.card or data);self.lookupPending[name]=nil end
        end,true)
    end
    return card
end
function Model:getArt(card,force,kind,options)
    return require('app.artwork').get(self,card,force,kind,nil,options)
end
function Model:selectBuilderArtwork(card)
    self.previewCard=card
    self.builderArtSequence=(self.builderArtSequence or 0)+1
    self.builderArtSelection={card=card,editor=self.editGeneration,token=self.builderArtSequence}
    self:getBuilderPreviewArt(card)
end
function Model:getBuilderPreviewArt(card)
    if self.cardPrintingPicker then return require('app.artwork').cached(self,card)end
    local selection=self.builderArtSelection
    if not selection or self.page~='builder'or selection.editor~=self.editGeneration or self.previewCard~=selection.card or card~=selection.card then return self:getArt(card,true)end
    -- A selected name-only deck entry must not wait behind the ordinary card
    -- list's lookups. Resolve its saved exact printing before asking for art.
    local choice=not card.printingExact and self.cardPrintingSelection and self:cardPrintingSelection(card,nil,self.editDeck)
    local printing=card.selectedPrintingId or choice and choice.printingId
    local function active()
        if self.cardPrintingPicker or self.page~='builder'or self.builderArtSelection~=selection or self.editGeneration~=selection.editor or self.previewCard~=selection.card then return false end
        local chosen=not card.printingExact and self.cardPrintingSelection and self:cardPrintingSelection(card,nil,self.editDeck)
        return(card.selectedPrintingId or chosen and chosen.printingId)==printing
    end
    local path,entry,cache
    if printing and not(card.printingExact and card.printing_id==printing)then
        self.printingMetadata=self.printingMetadata or{};cache=self.printingMetadata;entry=cache[printing]
        if not(entry and entry.card)then path='/cards/'..API.escape(printing)..'?printing='..API.escape(printing)end
    elseif not card.oracle_text and not card.image_uris and not self.byName[card.name]then
        path='/cards/by-name?name='..API.escape(card.name);entry=selection.metadata
    end
    if path then
        if not entry or entry.selectionToken~=selection.token or not entry.pending and(entry.retryAt or 0)<=love.timer.getTime()then
            entry={pending=true,selectionToken=selection.token,isCurrent=active};if cache then cache[printing]=entry else selection.metadata=entry end
            self.api:request('catalog','GET',path,nil,function(data,err,code)
                if cache and cache[printing]~=entry then return end
                if code==499 then if cache then cache[printing]=nil end;return end
                entry.pending=false;entry.retryAt=love.timer.getTime()+30;entry.error=err or(code~=200 and'Card metadata unavailable'or nil)
                if not err and code==200 and data then
                    if cache then entry.card=data else self:rememberCard(data.card or data)end
                end
            end,false,{priority='selectedMetadata',selectionToken=selection.token..':'..(printing or card.name),isCurrent=active})
        end
        return nil,'catalog'
    end
    local Artwork=require('app.artwork');local chosen=card;if self.artworkCard then chosen=self:artworkCard(card)end
    local key=chosen and Artwork.identity(self,chosen)
    if not key then return nil,'catalog'end
    local function current()
        if self.cardPrintingPicker or self.page~='builder'or self.builderArtSelection~=selection or self.editGeneration~=selection.editor or self.previewCard~=selection.card then return false end
        local value=selection.card;if self.artworkCard then value=self:artworkCard(value)end
        return value and Artwork.identity(self,value)==key
    end
    return self:getArt(card,true,nil,{priority='selected',network=true,selectionToken=selection.token..':'..key,isCurrent=current})
end
function Model:findDeck(id) for _,d in ipairs(self.decks) do if d.id==id then return d end end end
function Model:lobbyPlayerCount()
    return self.format:lower()=='commander' and self.commanderPlayers or 2
end
function Model:setLobbyPlayers(count)
    if count==2 or count==4 or count==5 or count==6 then self.commanderPlayers=count;self:syncLobbyDecks() end
end
function Model:syncLobbyDecks()
    local matching={};local format=self.format:lower()
    for _,deck in ipairs(self.decks) do if deck.format:lower()==format then matching[#matching+1]=deck.id end end
    local function matches(id)local deck=self:findDeck(id);return deck and deck.format:lower()==format end
    if not matches(self.playerDeckId) then self.playerDeckId=matching[1] end
    self.botDeckIds=self.botDeckIds or {}
    -- Keep the existing first-opponent selection compatible with duel callers.
    if matches(self.botDeckId) then self.botDeckIds[1]=self.botDeckId end
    for i=1,5 do
        if not matches(self.botDeckIds[i]) then self.botDeckIds[i]=matching[i+1] or matching[i%math.max(1,#matching)+1] end
    end
    self.botDeckId=self.botDeckIds[1]
end
function Model:setLobbyFormat(format)
    self.format=format;self:syncLobbyDecks()
end
function Model:setBotDeck(index,id)
    if index<1 or index>5 then return end
    self.botDeckIds[index]=id;if index==1 then self.botDeckId=id end
end
function Model:openDeck(deck)
    if self.closeCardPrintings then self:closeCardPrintings()end
    self.editGeneration=(self.editGeneration or 0)+1;self.deckRevision=0;self.mutationQueue={};self.mutationBusy=false;self.saveAfterMutations=false;self.lastBuilderError=nil
    self.editDeck=copy(deck)
    for _,zone in ipairs({'main','sideboard','commander'}) do self.editDeck[zone]=json.array(self.editDeck[zone] or {}) end
    self.page='builder';self.dirty=false;self.selectedSection='main';self.searchFormat=deck.format;self.search='';self.searchSet='All';self.searchColor='All';self.searchColors={};self.searchColorExact=false;self.searchType='';self.validation=nil;self.previewCard=nil;self:searchChanged();self:refreshSets();self:validateDeck()
end
function Model:newDeck()
    self:openDeck({id='custom-'..os.time()..'-'..love.math.random(1000,9999),name='New '..self.format..' deck',format=self.format,description='',main=json.array(),sideboard=json.array(),commander=json.array()})
    self.dirty=true;self.validation=nil
end
function Model:changeDeckFormat(format)
    if not self.editDeck then return end
    self.editDeck.format=format;self.searchFormat=format;self.searchSet='All';self.selectedSection='main';self.dirty=true
    self.deckRevision=(self.deckRevision or 0)+1
    self:searchChanged();self:refreshSets();self:validateDeck()
end
function Model:setDeckCover(card)
    if not self.editDeck or not card or not card.name then return end
    self.editDeck.coverCard=card.name;self.dirty=true;self:toast('Deck cover selected')
end
function Model:deckCoverCard(deck)
    local name=deck and (deck.coverCard or (deck.commander and deck.commander[1] and deck.commander[1].name) or (deck.main and deck.main[1] and deck.main[1].name))
    return name and {name=name} or nil
end
function Model:validateDeck(callback)
    if not self.editDeck then return end
    local version=(self.validationVersion or 0)+1;self.validationVersion=version
    self:request('catalog','POST','/decks/validate',self.editDeck,function(data)
        if version~=self.validationVersion then return end
        if data then self.validation=data end
        if callback then callback(data) end
    end,true)
end
local function changeCard(deck,name,section,delta)
    local entries=deck[section];local found
    for i,e in ipairs(entries) do if e.name==name then e.count=e.count+delta;if e.count<=0 then table.remove(entries,i) end;found=true;break end end
    if not found and delta>0 then entries[#entries+1]={name=name,count=delta} end
    table.sort(entries,function(a,b) return a.name<b.name end)
end
function Model:commitCard(name,section,delta)
    changeCard(self.editDeck,name,section,delta);self.deckRevision=(self.deckRevision or 0)+1
    if self.syncCardPrintings then self:syncCardPrintings()end
    self.dirty=true;self.validation=nil;self.validationVersion=(self.validationVersion or 0)+1;self.validationTimer=.35
end
function Model:processCardQueue()
    if self.mutationBusy or not self.editDeck or not self.mutationQueue or #self.mutationQueue==0 then return end
    local operation=self.mutationQueue[1];local candidate=copy(self.editDeck)
    changeCard(candidate,operation.name,operation.section,operation.delta)
    if self.syncCardPrintings then self:syncCardPrintings(candidate)end
    local revision,generation=self.deckRevision or 0,self.editGeneration or 0
    self.mutationBusy=true
    self:request('catalog','POST','/decks/validate',candidate,function(result,err)
        if generation~=(self.editGeneration or 0) then return end
        self.mutationBusy=false
        if revision~=(self.deckRevision or 0) then self:processCardQueue();return end
        local blocked
        if result then
            for _,issue in ipairs(result.errors or {}) do
                local relevant=false
                for _,name in ipairs(issue.cards or {}) do if name==operation.name then relevant=true end end
                if issue.code=='commander_size' or (issue.code=='sideboard_size' and operation.section=='sideboard')
                    or ((issue.code=='unexpected_commander' or issue.code=='commander_count') and operation.section=='commander') then relevant=true end
                if relevant then blocked=issue.message;break end
            end
            if not blocked then self:commitCard(operation.name,operation.section,operation.delta);self.validation=result;self.validationTimer=nil;self.lastBuilderError=nil
            else self.lastBuilderError=blocked;self:toast(blocked,true);self:validateDeck() end
        else self:toast(err or 'Could not validate this card addition',true) end
        table.remove(self.mutationQueue,1);self:processCardQueue()
        if #self.mutationQueue==0 and self.saveAfterMutations then self.saveAfterMutations=false;self:saveDeck() end
    end,true)
end
function Model:addCard(card,section,delta)
    if not self.editDeck or not card or not card.name then return end
    section=section or self.selectedSection;delta=delta or 1
    if not self.editDeck[section] then return end
    if delta<=0 then self:commitCard(card.name,section,delta);return end
    self.mutationQueue=self.mutationQueue or {}
    self.mutationQueue[#self.mutationQueue+1]={name=card.name,section=section,delta=delta}
    self:processCardQueue()
end
function Model:saveDeck()
    if self.mutationBusy or (self.mutationQueue and #self.mutationQueue>0) then self.saveAfterMutations=true;self:toast('Waiting for card validation…');return end
    local deck=copy(self.editDeck);deck.origin=nil
    local generation,revision,identifier=self.editGeneration or 0,self.deckRevision or 0,self.editDeck.id
    local function unchanged()
        return self.editDeck and revision==(self.deckRevision or 0)and self.editDeck.name==deck.name and self.editDeck.coverCard==deck.coverCard and self.editDeck.description==deck.description and self.editDeck.format==deck.format
    end
    self:request('catalog','POST','/decks',deck,function(data,err,failed)
        if data then
            local saved=data.deck or data
            self:refreshDecks();self:toast((saved.draft and'Draft saved: 'or'Deck saved: ')..deck.name)
            if generation~=(self.editGeneration or 0)or not self.editDeck or self.editDeck.id~=identifier then return end
            self.editDeck.id=saved.id or self.editDeck.id;self.editDeck.origin='user';self.selectedDeck=self.editDeck.id
            if unchanged()then self.dirty=false;self.editDeck.draft=saved.draft;self.validation=data.validation end
        elseif failed and failed.validation and generation==(self.editGeneration or 0)and unchanged()then self.validation=failed.validation end
    end)
end
function Model:duplicateDeck(deck)
    local d=copy(deck);d.id='custom-'..os.time()..'-'..love.math.random(1000,9999);d.name=d.name..' copy';d.origin=nil
    local page,selection,generation,revision=self.page,self.selectedDeck,self.editGeneration or 0,self.deckRevision or 0
    local submitted=self.editDeck and copy(self.editDeck)
    self:request('catalog','POST','/decks',d,function(data)
        if not data then return end
        local unchanged=self.page==page and self.selectedDeck==selection and(self.editGeneration or 0)==generation and(self.deckRevision or 0)==revision
        if submitted then unchanged=unchanged and self.editDeck~=nil and self.editDeck.name==submitted.name and self.editDeck.coverCard==submitted.coverCard and self.editDeck.description==submitted.description and self.editDeck.format==submitted.format end
        self:refreshDecks()
        if unchanged then
            local saved=data.deck or data;if not saved.id then saved=d end;saved.origin='user'
            for _,zone in ipairs({'main','sideboard','commander'})do saved[zone]=json.array(saved[zone]or{})end
            self.selectedDeck=saved.id;self:openDeck(saved)
        end
        self:toast('Deck duplicated')
    end)
end
function Model:deleteDeck(deck)
    self:request('catalog','DELETE','/decks/'..API.escape(deck.id),nil,function(data) if data then self:refreshDecks();self.selectedDeck=nil;self:toast('Deck removed') end end)
end
function Model:saveSettings()
    self:request('catalog','PUT','/settings',self.settings,function(data) if data then self:toast('Settings saved') end end)
end
function Model:setBuilderLayout(value)
    if value~='Classic'and value~='Simplified'then return end
    self.settings.builderLayout=value;self.simpleDeckScroll=0;self.searchTimer=0
    self:request('catalog','PUT','/settings',{builderLayout=value},function()end,true)
end
function Model:openSettings()
    if self.page=='table'then self.settingsOpen=true;return end
    if self.page~='settings'then self.settingsReturnPage=self.page end
    self.settingsOpen=false;self.page='settings'
end
function Model:closeSettings()
    self.settingsOpen=false
    if self.page=='settings'then self.page=self.settingsReturnPage or'decks';self.settingsReturnPage=nil end
end
function Model:startGame()
    if self.storageLocationBlocked then self:toast('Restart the client to use the prepared storage locations.',true);return end
    if self.roomConnectionId then self:toast('Leave your multiplayer room before starting a practice match',true);return end
    if self.gameBusy then return end
    local deck=self:findDeck(self.playerDeckId)
    if not deck then self:toast('Choose your deck first',true);return end
    local bots=json.array();local count=self:lobbyPlayerCount()-1
    for i=1,count do
        local bot=self:findDeck(i==1 and self.botDeckId or self.botDeckIds[i])
        if not bot then self:toast('Choose a deck for bot '..i,true);return end
        if deck.format:lower()~=bot.format:lower() then self:toast('Bot '..i..' must use the same format as your deck',true);return end
        bots[#bots+1]={name=count==1 and 'XMage Bot' or 'XMage Bot '..i,deck=bot}
    end
    if deck.format:lower()~=self.format:lower() then self:toast('Your deck must use the selected format',true);return end
    if self.replay then self:closeReplay() end
    self.gameBusy=true;self.answeredPrompt=nil;self.orderPrompt=nil;self.promptOrder={};self.actionBusy=false
    if self.api.setNativeSession then self.api:setNativeSession(nil)end
    local body={format=deck.format,playerName=self.playerName,deck=deck,settings=self.settings,commanderDamage=self.commanderDamage~=false,priority=self:priorityOptions(),startingSeatId=self.practiceStartingSeatId or'dice',recordingPort=self.api.catalogPort or tonumber(os.getenv('LOVE2GATHERING_CATALOG_PORT')) or 17370}
    body.profile=self:profileOptions();body.profile.name=body.playerName
    if count==1 then body.botDeck=bots[1].deck else body.bots=bots end
    self:request('engine','POST','/session/start',body,function(data)
        self.gameBusy=false
        if data then
            self.lastMatchRequest=copy(body);self.lastMatchDeckId=deck.id;self.activeDeckId=deck.id
            self:setGame(data);self.page='table';self:toast('XMage match started')
        end
    end)
end
function Model:canRematch()
    if self.replay or self.storageLocationBlocked or not self.game or self.game.running~=false or self.gameBusy then return false end
    if self.roomConnectionId then
        return self.room and self.room.phase=='playing' and self.room.config.kind=='constructed' and self.room.canRematch==true and not self.room.rematchRequest
    end
    return self.lastMatchRequest~=nil
end
function Model:rematch()
    if not self:canRematch()then return false end
    if self.roomConnectionId then return self:roomMutation('/rematch',{})end
    self.gameBusy=true
    if self.api.setNativeSession then self.api:setNativeSession(nil)end
    self:request('engine','POST','/session/start',copy(self.lastMatchRequest),function(data)
        self.gameBusy=false;if data then self:setGame(data);self.page='table'end
    end)
    return true
end
function Model:goMain()
    if self.replay then self:closeReplay()end
    self.page='decks';self:refreshDecks()
end
function Model:lobbyDeck(deck)
    self.playerDeckId=deck.id;self.format=deck.format;self.page='lobby'
    self:syncLobbyDecks()
end
function Model:setGame(data)
    if self.game and data.gameId==self.game.gameId and data.revision and self.game.revision and data.revision<self.game.revision then return end
    if not self.game or data.gameId and self.game.gameId and data.gameId~=self.game.gameId then
        self.answeredPrompt=nil;self.orderPrompt=nil;self.promptOrder={};self.actionBusy=false;self.concedePending=false
        self.zoneView=nil;self.inspectCard=nil;self.cardActionSheet=nil;self.commanderDetails=nil;self.confirmConcede=false
        self.pollRequest=(self.pollRequest or 0)+1;self.polling=false
        self.priorityBusy=false;self.priorityRequest=(self.priorityRequest or 0)+1
    end
    if self.api.setNativeSession then self.api:setNativeSession(data.gameId)end
    self.game=data;self.gameConnectionError=nil
    self:refreshLibraryViews()
    self:refreshZoneView()
    local prompt=data.prompt
    if type(prompt)=='table' and prompt~=json.null and self.orderPrompt~=prompt.id then
        self.orderPrompt=prompt.id;self.promptOrder={}
        for _,c in ipairs(prompt.choices or {}) do self.promptOrder[#self.promptOrder+1]=c end
    end
end
function Model:libraryTop(player)
    if type(player)~='table'then
        local id=player;player=nil
        for _,candidate in ipairs(self.game and self.game.players or{})do if candidate.id==id then player=candidate;break end end
    end
    local card=player and player.libraryTop
    -- Only an explicitly entitled native projection can expose a library card.
    -- Owning the library, remembered artwork and Oracle text confer no access.
    if type(card)~='table'or card==json.null or not card.id or card.hidden or card.faceDown then return nil end
    return card
end
function Model:libraryTopCurrent(playerId,cardId,gameId)
    local card=self:libraryTop(playerId)
    return self.game~=nil and self.game.gameId==gameId and card~=nil and card.id==cardId
end
function Model:openLibrary(playerId)
    local player
    for _,candidate in ipairs(self.game and self.game.players or{})do if candidate.id==playerId then player=candidate;break end end
    if not player then return false end
    self.zoneView={label=(player.name or'Player')..' · Library',libraryPlayerId=playerId,libraryGameId=self.game.gameId,cards={}}
    self:refreshLibraryViews();return true
end
function Model:inspectLibraryTop(playerId,cardId,gameId)
    if not self:libraryTopCurrent(playerId,cardId,gameId)then return false end
    local card=self:libraryTop(playerId)
    self.inspectCard=card;self.libraryTopInspect={playerId=playerId,cardId=cardId,gameId=gameId,card=card}
    return true
end
function Model:openZone(playerId,zoneName,label)
    if not self.game then return false end
    for _,player in ipairs(self.game.players or{})do if player.id==playerId then
        self.zoneView={label=label or((player.name or'Player')..' · '..zoneName),playerId=playerId,zoneName=zoneName,gameId=self.game.gameId,cards=player[zoneName]or{}}
        return true
    end end
    return false
end
function Model:refreshZoneView()
    local zone=self.zoneView;if not zone or zone.libraryPlayerId then return end
    if zone.gameId and(not self.game or self.game.gameId~=zone.gameId)then self.zoneView=nil;return end
    if zone.playerId and zone.zoneName then
        for _,player in ipairs(self.game and self.game.players or{})do if player.id==zone.playerId then zone.cards=player[zone.zoneName]or{};return end end
        self.zoneView=nil;return
    end
    -- Legacy/group openings retain only exact current entitled object IDs.
    local ids={};for _,card in ipairs(zone.cards or{})do if card.id then ids[card.id]=true end end
    local current={}
    for _,player in ipairs(self.game and self.game.players or{})do
        for _,name in ipairs({'battlefield','hand','graveyard','exile','command'})do
            for _,card in ipairs(player[name]or{})do if ids[card.id]then current[#current+1]=card end end
        end
    end
    if next(ids)then zone.cards=current end
end
function Model:refreshLibraryViews()
    local zone=self.zoneView
    if zone and zone.libraryPlayerId then
        local card=self.game and self.game.gameId==zone.libraryGameId and self:libraryTop(zone.libraryPlayerId)
        zone.cards=card and{card}or{}
    end
    local inspect=self.libraryTopInspect
    if inspect then
        if self.inspectCard~=inspect.card then self.libraryTopInspect=nil
        elseif not self:libraryTopCurrent(inspect.playerId,inspect.cardId,inspect.gameId)then self.inspectCard=nil;self.libraryTopInspect=nil
        else local card=self:libraryTop(inspect.playerId);self.inspectCard=card;inspect.card=card end
    end
end
function Model:concede()
    if self.replay or self.concedePending or not self.game or self.game.running==false or not self.game.gameId then return end
    local gameId=self.game.gameId;local generation=self.api.routeGeneration
    self.concedePending=true
    self:request('engine','POST','/session/action',{type='concede',value=true,expectedGameId=gameId},function(data)
        if not self.game or self.game.gameId~=gameId or generation~=self.api.routeGeneration then return end
        self.concedePending=false
        if data then self:setGame(data)end;self.pollTimer=0
    end)
end
function Model:prompt()
    if self.game and self.game.running==false then return nil end
    if self.replay or self.gameBusy or self.concedePending then return nil end
    if self.game and self.game.execution and(self.game.execution.stopRequested or self.game.execution.concedeRequested)then return nil end
    local p=self.game and self.game.prompt
    -- A control command can be acknowledged before the GAME thread replaces
    -- its old projection. That priority ID must not be submitted a second time.
    if type(p)=='table' and p.priority and self.game.priority and (self.game.priority.pending or self.game.priority.canEndTurn==false) then return nil end
    return type(p)=='table' and p~=json.null and p.id and p.id~=self.answeredPrompt and p or nil
end
function Model:answer(kind,value)
    if self.roomGameActive and self.roomDisconnected then return false end
    local p=self:prompt();if not p or self.actionBusy or self.priorityBusy then return end
    self.actionBusy=true;self.answeredPrompt=p.id
    local gameId=self.game and self.game.gameId;local generation=self.api.routeGeneration
    self:request('engine','POST','/session/action',{promptId=p.id,type=kind,value=value,expectedGameId=gameId},function(data)
        if not self.game or self.game.gameId~=gameId or generation~=self.api.routeGeneration then return end
        self.actionBusy=false;if data then self:setGame(data) else self.answeredPrompt=nil end;self.pollTimer=0
    end)
    return true
end
function Model:answerChoice(choice)
    local value=choice.value;if value==nil then value=choice.id end
    self:answer(choice.responseType or 'string',value)
end
function Model:canSelect(id)
    if self.roomGameActive and self.roomDisconnected then return false end
    local p=self:prompt();if not p then return false end
    if type(p.actionable)=='table' then
        for _,candidate in ipairs(p.actionable) do if tostring(candidate)==tostring(id) then return true end end
        return false
    end
    for _,target in ipairs(p.targets or {}) do if tostring(type(target)=='table' and target.id or target)==tostring(id) then return true end end
    for _,choice in ipairs(p.choices or {}) do if tostring(choice.value or choice.id)==tostring(id) and choice.responseType=='uuid' then return true end end
    return false
end
function Model:selectCard(card)
    if self:canSelect(card.id) then return self:answer('uuid',card.id)==true end
    local p=self:prompt()
    if p and p.combat then
        self:toast('Choose a highlighted legal blocker or attacker. '..(p.combat.message or''),true)
        self.toasts[#self.toasts].ttl=3
    end
    return false
end
function Model:submitOrder()
    local values=json.array();for _,c in ipairs(self.promptOrder) do values[#values+1]=c.id end
    self:answer('order',values)
end
function Model.count(deck,section)
    local count=0;for _,e in ipairs(deck[section] or {}) do count=count+(e.count or 0) end;return count
end
function Model:quit()
    if self.uiLayoutTimer then self.api:request('catalog','PUT','/ui-layout',self.uiLayout,function() end) end
    self.api:quit()
end
require('app.replays').install(Model)
require('app.priority').install(Model)
require('app.gallery').install(Model)
require('app.rooms').install(Model)
require('app.library').install(Model)
require('app.collection').install(Model)
require('app.profile').install(Model)
require('app.bootstrap').install(Model)
require('app.artwork').install(Model)
require('app.storage').install(Model)
require('app.storage_locations').install(Model)
require('app.image_packs').install(Model)
require('app.playmats').install(Model)
require('app.builder_colors').install(Model)
require('app.card_printings').install(Model)
require('app.game_art').install(Model)
require('app.activity').install(Model)
require('app.outcome').install(Model)
require('app.native_capabilities').install(Model)
require('app.bot_draft').install(Model)
require('app.deck_support').install(Model)
require('app.input_delivery').install(Model)
return Model
