-- Optional, bounded preparation of illustrations visible on the opening page.
-- This reads the local image cache only; a miss never starts a download.
local Artwork=require('app.artwork')
local json=require('lib.json')
local Warm={};Warm.__index=Warm
local function clock()return love.timer.getTime()end
local function matches(m,deck)
    local format=m.collectionFormat or m.format or'All'
    if format~='All'and tostring(deck.format):lower()~=format:lower()then return false end
    local query=(m.collectionSearch or''):lower()
    return query==''or table.concat({deck.name or'',deck.description or'',deck.expansion or'',deck.faceCommander or''},' '):lower():find(query,1,true)~=nil
end
local function collapsed(m)
    local collection=m.uiLayout and m.uiLayout.collection
    return collection and(collection.collapsed or{})or{starter=true}
end
function Warm.new(options)
    options=options or{}
    return setmetatable({clock=options.clock or clock,timeout=math.max(.05,math.min(5,options.timeout or 2)),maxCovers=math.max(0,math.min(8,options.maxCovers or 8)),items={},state={ready=false,progress=0,optional=true}},Warm)
end
function Warm:select(m)
    if self.selected then return end
    local folds=collapsed(m);local users,starters={},{}
    if m.page=='decks'then
        for _,deck in ipairs(m.decks or{})do if matches(m,deck)then
            if deck.origin=='user'then users[#users+1]=deck
            elseif not m.starterDecks then starters[#starters+1]=deck end
        end end
        -- Explicit Starter templates take precedence over legacy owned overrides,
        -- exactly as in the collection view. Do not fetch historical products.
        local userCount=folds.user and 0 or#users
        if not folds.starter and userCount<self.maxCovers and not m.starterDecks and not m.startersLoaded and not self.startersRequested then
            self.startersRequested=true;self.startersPending=true
            m.startersBusy=true
            m:request('catalog','GET','/decks?origin=starter',nil,function(data,err)
                self.startersPending=false;m.startersBusy=false
                if data then
                    m.starterDecks=data.decks or data
                    for _,deck in ipairs(m.starterDecks)do for _,zone in ipairs({'main','sideboard','commander'})do deck[zone]=json.array(deck[zone]or{})end end
                    m.startersLoaded=true
                else self.startersError=err or'Starter templates could not be read'end
            end,true)
        end
        if self.startersPending then return end
        if m.starterDecks then starters={};for _,deck in ipairs(m.starterDecks)do if matches(m,deck)then starters[#starters+1]=deck end end end
        local count=0
        local function add(decks)
            for _,deck in ipairs(decks)do
                if count>=self.maxCovers then return end
                local cover=deck.cover or(m.deckCoverCard and m:deckCoverCard(deck))
                if type(cover)=='string'then cover={name=cover}end
                if cover then self.items[#self.items+1]={card=cover,label=deck.name or cover.name or'Deck cover'};count=count+1 end
            end
        end
        if not folds.user then add(users)end
        if not folds.starter then add(starters)end
        if not folds.preconstructed then
            local visible={};for _,deck in ipairs(m.precons or{})do
                local expansion=deck.expansion or deck.setName or deck.set or'Other products'
                if not folds['set:'..expansion]then visible[#visible+1]=deck end
            end;add(visible)
        end
    end
    self.selected=true
end
function Warm:update(m)
    if self.state.ready then return self.state end
    self.started=self.started or self.clock()
    if not self.avatarAdded then
        self.avatarAdded=true
        local avatar=m.profile and m.profile.avatar
        if avatar and avatar.printingId and m.profileArt then self.items[#self.items+1]={avatar=avatar,label='Profile avatar'}end
    end
    self:select(m)
    local cached,missing,pending,errors=0,0,0,{}
    for _,item in ipairs(self.items)do
        if not item.status or item.status=='loading'or item.status=='catalog'then
            local image,status
            if item.avatar then image,status=m:profileArt(item.avatar,true)
            else image,status=Artwork.get(m,item.card,true,'art_crop',true)end
            item.status=image and'ready'or status or'catalog'
        end
        if item.status=='ready'then cached=cached+1
        elseif item.status=='missing'then missing=missing+1
        elseif item.status=='error'then errors[#errors+1]='Could not read cached artwork: '..item.label
        else pending=pending+1 end
    end
    if self.startersError then errors[#errors+1]=self.startersError end
    if self.startersPending then pending=pending+1 end
    local total=#self.items+(self.startersRequested and 1 or 0)
    local completed=total-pending
    local timedOut=pending>0 and self.clock()-self.started>=self.timeout
    local ready=self.selected and pending==0 or timedOut
    local message=string.format('Local artwork · %d cached · %d not cached',cached,missing)
    if timedOut then message=message..string.format(' · %d still pending; continuing in background',pending)
    elseif not ready then message='Preparing local artwork · '..completed..' / '..total end
    self.state={ready=ready,progress=ready and 1 or(total>0 and completed/total or 0),optional=true,total=total,completed=completed,cached=cached,missing=missing,pending=pending,failed=#errors,error=errors[1],timedOut=timedOut,message=message}
    return self.state
end
return Warm
