-- Installed implementation coverage is asynchronous metadata, never a native
-- legality verdict. Keep the large registry transient during one local transfer.
local json=require('lib.json')
local Support={}
local function identity(m)
    local health=m.engineHealth or{};local catalog=m.catalogHealth or{};local store=catalog.storage or{}
    if not(health.ok==true or health.ready==true or health.status=='ok')or type(health.instanceId)~='string'or not catalog.ready or not(catalog.deckSupport and catalog.deckSupport.available)then return nil end
    return table.concat({tostring(m.api.enginePort),health.instanceId,tostring(m.api.catalogPort),catalog.catalogSource or'',store.dataDirectory or''},'|')
end
local function current(m,state)return m.deckSupportState==state and identity(m)==state.key end
local function statusCurrent(state,value)return type(value)=='table'and value.registryRevision==state.registryRevision and value.generation==state.status.generation end
function Support.install(Model)
    function Model:deckSupport(deck)
        local state=self.deckSupportState
        if not state or not state.ready or not current(self,state)then return{state='unknown',missingNames={},legalityChecked=false}end
        local id=deck.sourceDeckId or deck.id;local saved=deck.engineSupport;local cached=state.byId[id]
        if statusCurrent(state,cached)and(not statusCurrent(state,saved)or not saved.fingerprint or cached.fingerprint==saved.fingerprint)then state.used[id]=state.clock;return cached end
        if statusCurrent(state,saved)and(saved.state=='ready'or saved.state=='unavailable')then return saved end
        if id then state.wanted[id]=true end
        return statusCurrent(state,saved)and saved or{state='checking',missingNames={},legalityChecked=false}
    end
    function Model:updateDeckSupport(dt)
        local key=identity(self);local state=self.deckSupportState
        if not key then return end
        if not state or state.key~=key then state={key=key,clock=0,nextRetry=0,nextPoll=0,wanted={},byId={},used={},sizes={},bytes=0};self.deckSupportState=state end
        state.clock=state.clock+dt
        if not state.ready then
            if state.pending or state.clock<state.nextRetry or self.storageLocationBlocked then return end
            state.pending=true;state.nextRetry=state.clock+30
            self:request('engine','GET','/capabilities/cards',nil,function(registry,problem)
                if not current(self,state)then return end
                if not registry or type(registry.names)~='table'or type(registry.registryRevision)~='string'then state.pending=false;state.error=problem or'Installed card registry is unavailable';return end
                local body={engineRevision=registry.engineRevision,registryRevision=registry.registryRevision,names=registry.names,splitNameFallback=registry.splitNameFallback==true,legalityChecked=false}
                self:request('catalog','POST','/engine-support/registry',body,function(value,err)
                    if not current(self,state)then return end
                    state.pending=false;state.error=err
                    if value and value.registryRevision==registry.registryRevision then state.registryRevision=value.registryRevision;state.status=value;state.ready=true;state.nextPoll=0 end
                end,true)
            end,true)
            return
        end
        if state.clock>=state.nextPoll and not state.statusBusy then
            state.statusBusy=true;state.nextPoll=state.clock+(state.status.state=='checking'and 1 or 15)
            self:request('catalog','GET','/engine-support/status',nil,function(value,problem)
                if not current(self,state)then return end
                state.statusBusy=false;state.error=problem
                if value and value.registryRevision==state.registryRevision then
                    if value.generation~=state.status.generation then state.byId={};state.used={};state.sizes={};state.bytes=0 end
                    state.status=value
                elseif value then state.ready=false;state.byId={};state.used={};state.sizes={};state.bytes=0;state.nextRetry=state.clock+2 end
            end,true)
        end
        if state.batchBusy or state.clock<(state.nextBatch or 0)then return end
        local ids={};for id in pairs(state.wanted)do ids[#ids+1]=id;if#ids>=60 then break end end
        if#ids==0 then return end
        for _,id in ipairs(ids)do state.wanted[id]=nil end
        state.batchBusy=true;state.nextBatch=state.clock+1
        self:request('catalog','POST','/engine-support/decks',{ids=ids},function(data,problem)
            if not current(self,state)then return end
            state.batchBusy=false;state.error=problem
            if data and data.status and data.status.registryRevision==state.registryRevision then
                if data.status.generation~=state.status.generation then state.byId={};state.used={};state.sizes={};state.bytes=0 end
                state.status=data.status
                for id,value in pairs(data.decks or{})do
                    state.bytes=state.bytes-(state.sizes[id]or 0);state.sizes[id]=#json.encode(value);state.bytes=state.bytes+state.sizes[id]
                    state.byId[id]=value;state.used[id]=state.clock;if value.state=='checking'then state.wanted[id]=true end
                end
                local count=0;for _ in pairs(state.byId)do count=count+1 end
                while count>512 or state.bytes>4*1024*1024 do
                    local oldest,at;for id in pairs(state.byId)do if not at or(state.used[id]or 0)<at then oldest,at=id,state.used[id]or 0 end end
                    if not oldest then break end;state.bytes=state.bytes-(state.sizes[oldest]or 0);state.byId[oldest]=nil;state.sizes[oldest]=nil;state.used[oldest]=nil;count=count-1
                end
            else for _,id in ipairs(ids)do state.wanted[id]=true end end
        end,true)
    end
    local update=Model.update
    function Model:update(dt)local result=update(self,dt);self:updateDeckSupport(dt);return result end
end
return Support
