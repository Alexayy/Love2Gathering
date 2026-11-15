local API = {}; API.__index=API
local json=require('lib.json')
local instanceSequence=0
local function worker(self,name,port,service)
    local prefix='l2g_'..self.instanceId..'_'..name
    local value={input=love.thread.getChannel(prefix..'_in'),output=love.thread.getChannel(prefix..'_out'),thread=love.thread.newThread('app/http_worker.lua'),service=service or name}
    value.thread:start(prefix..'_in',prefix..'_out',port);self.workers[name]=value
    return value
end
function API.new(options)
    options=options or {}
    instanceSequence=instanceSequence+1
    local self=setmetatable({nextId=0,pending={},pendingService={},pendingDetails={},workers={},inflight={},waiters={},artQueue={},imageMetrics={count=0,queueSeconds=0,httpSeconds=0,decodeSeconds=0,callbackSeconds=0},readEpoch=0,instanceId=tostring(love.timer.getTime())..'_'..instanceSequence},API)
    local catalogPort=tonumber(options.catalogPort or os.getenv('LOVE2GATHERING_CATALOG_PORT')) or 17370
    local enginePort=tonumber(options.enginePort or os.getenv('LOVE2GATHERING_ENGINE_PORT')) or 17371
    local roomPort=tonumber(options.roomPort or os.getenv('LOVE2GATHERING_ROOM_PORT')) or 17380
    self.catalogPort=catalogPort;self.enginePort=enginePort;self.roomPort=roomPort;self.routeGeneration=0;self.routes={}
    for name,port in pairs({catalog=catalogPort,engine=enginePort,room=roomPort,art=catalogPort}) do
        worker(self,name,port)
    end
    return self
end
local function pool(self,names,service,port)
    local selected,load
    for _,name in ipairs(names)do
        local count=0;for _,detail in pairs(self.pendingDetails)do if detail.worker==name then count=count+1 end end
        if not load or count<load then selected,load=name,count end
    end
    if not self.workers[selected]then worker(self,selected,port,service)end
    return selected
end
local function current(detail)
    return not detail.isCurrent or detail.isCurrent()
end
local function cancelQueued(self,id,message)
    local detail=self.pendingDetails[id];if not detail then return end
    if detail.readKey and self.inflight[detail.readKey]==id then self.inflight[detail.readKey]=nil end
    local callback=self.pending[id];local waiters=self.waiters[id]or{}
    self.pending[id]=nil;self.pendingService[id]=nil;self.pendingDetails[id]=nil;self.waiters[id]=nil;self.routes[id]=nil
    if callback then callback(nil,message,499)end
    for _,waiting in ipairs(waiters)do waiting(nil,message,499)end
end
local function dispatchArt(self)
    for index=#self.artQueue,1,-1 do
        local item=self.artQueue[index];local detail=self.pendingDetails[item.id]
        if not detail or not current(detail)then
            table.remove(self.artQueue,index);cancelQueued(self,item.id,'Image selection changed')
        end
    end
    -- A worker keeps its slot until the main thread has consumed its decoded
    -- response. This bounds queued CPU images as well as simultaneous HDD reads.
    for _,lane in ipairs({'catalogSelectedMetadata','catalogSelectedMetadata2','artSelected','artSelected2','catalogHandMetadata','artHand','artHand2','art','art2'})do
        local busy=false;for _,detail in pairs(self.pendingDetails)do if detail.worker==lane then busy=true;break end end
        if not busy then
            for index,item in ipairs(self.artQueue)do
                local detail=self.pendingDetails[item.id]
                local priority=lane:match('^catalogSelected')and'selectedMetadata'or lane:match('^artSelected')and'selected'or lane=='catalogHandMetadata'and'handMetadata'or lane:match('^artHand')and'hand'or'visible'
                if detail and(detail.priority or'visible')==priority then
                    table.remove(self.artQueue,index)
                    detail.worker=lane;detail.dispatched=love.timer.getTime();detail.queued=false
                    local active=self.workers[lane]or worker(self,lane,self.catalogPort,detail.service)
                    active.input:push(item);break
                end
            end
        end
    end
end
function API:setNativeSession(gameId)
    if self.nativeSessionId~=gameId then self.nativeSessionId=gameId;self.routeGeneration=self.routeGeneration+1 end
end
function API:setRoomSession(session)
    local previous=self.roomSession and (self.roomSession.connectionId..':'..tostring(self.roomSession.gameId or ''))
    local current=session and (session.connectionId..':'..tostring(session.gameId or ''))
    if previous~=current then self.routeGeneration=self.routeGeneration+1 end
    self.roomSession=session
end
function API:request(service,method,path,body,callback,binary,options)
    options=options or{}
    local requestPath=path
    self.artQueue=self.artQueue or{};self.imageMetrics=self.imageMetrics or{count=0,queueSeconds=0,httpSeconds=0,decodeSeconds=0,callbackSeconds=0}
    assert(self.workers[service],'Unknown local service: '..tostring(service))
    local routes={['/session/state']='game/state',['/session/action']='game/action',['/session/priority']='game/priority',['/session/replay/save']='game/replay/save'}
    local stop=service=='engine'and path=='/session/stop'
    local guarded=service=='engine' and(routes[path]~=nil or stop)
    local control=service=='engine'and method=='POST'and(stop or path=='/session/action'and body and body.type=='concede')
    if stop and self.roomSession then
        if callback then callback(nil,'Use your room seat controls to leave a multiplayer game',0)end
        return false
    end
    if guarded and self.roomSession then
        if method=='POST'and self.roomSession.gameId and body and body.expectedGameId and body.expectedGameId~=self.roomSession.gameId then
            if callback then callback(nil,'Match connection changed',0)end
            return false
        end
        path='/client/rooms/'..API.escape(self.roomSession.connectionId)..'/'..routes[path];service='room'
        if method=='POST' and self.roomSession.gameId then
            local scoped={};for key,value in pairs(body or {}) do scoped[key]=value end
            scoped.expectedGameId=self.roomSession.gameId;body=scoped
        end
    elseif guarded and method=='POST'and self.nativeSessionId and not(body and body.expectedGameId)then
        local scoped={};for key,value in pairs(body or{})do scoped[key]=value end
        scoped.expectedGameId=self.nativeSessionId;body=scoped
    end
    -- A read blocked on the GAME thread must not hold that seat's concession
    -- behind the same socket. Ordinary game actions keep their ordered lane.
    local lane=control and(service..'Control')or service
    if service=='engine'and method=='GET'and path=='/session/state'then lane='engineState'
    elseif service=='engine'and method=='GET'and path=='/health'then lane='engineHealth'
    elseif service=='room'and method=='GET'and guarded and requestPath=='/session/state'then lane='roomState'
    elseif service=='engine'and method=='GET'and path:match('^/capabilities')then lane='engineMetadata'
    elseif service=='art'then lane=nil
    elseif service=='catalog'then
        if path:match('^/storage/')or path:match('^/downloads/')then lane='catalogMaintenance'
        elseif method=='POST'and path=='/art/download'then lane='catalogFetch'
        elseif method=='GET'and({['/health']=true,['/settings']=true,['/profile']=true,['/ui-layout']=true})[path]then lane='catalogFast'
        elseif method=='GET'and path:match('^/printings[?]?')then lane='catalogChoices'
        elseif method=='GET'and(path:match('^/cards/')or path:match('^/sets'))then lane='catalogMetadata'
        elseif method=='GET'or method=='POST'and path=='/tokens/resolve'then lane=pool(self,{'catalogRead1','catalogRead2'},'catalog',self.catalogPort)end
    end
    -- Reads of a resource with queued writes keep their FIFO position. This
    -- includes refreshes from an earlier save callback while a second save is
    -- still pending; coalescing must never adopt that earlier snapshot as new.
    local group=service=='catalog'and path:match('^/([^/?]+)')or nil
    if service=='catalog'and method=='GET'then
        for _,detail in pairs(self.pendingDetails)do
            if detail.orderedWrite and detail.group==group then lane='catalog';break end
        end
    end
    local readKey
    if service=='catalog'and method~='GET'and path~='/tokens/resolve'then self.readEpoch=self.readEpoch+1 end
    if method=='GET'and(service=='catalog'or service=='art')then
        readKey=service..':'..tostring(binary or false)..':'..self.readEpoch..':'..path..(options.selectionToken and':'..tostring(options.selectionToken)or'')
        local previous=self.inflight[readKey]
        if previous and self.pending[previous]then
            self.waiters[previous]=self.waiters[previous]or{};if callback then table.insert(self.waiters[previous],callback)end
            return previous
        end
    end
    local port=(service=='catalog'or service=='art')and self.catalogPort or service=='room'and self.roomPort or self.enginePort
    local queued=service=='art'or options.priority=='selectedMetadata'or options.priority=='handMetadata'
    local active=not queued and(self.workers[lane]or worker(self,lane,port,service))or nil
    self.nextId=self.nextId+1
    self.pending[self.nextId]=callback or function() end
    self.pendingService[self.nextId]=service
    local priority=options.priority or(path:find('priority=selected',1,true)and'selected'or nil)
    self.pendingDetails[self.nextId]={worker=not queued and lane or nil,service=service,path=requestPath,started=love.timer.getTime(),control=control,readKey=readKey,group=group,orderedWrite=service=='catalog'and lane=='catalog'and method~='GET',priority=priority,isCurrent=options.isCurrent,queued=queued}
    if readKey then self.inflight[readKey]=self.nextId end
    self.routes[self.nextId]=guarded and self.routeGeneration or nil
    -- Channel tables do not preserve metatables, so serialize arrays here.
    local id=self.nextId
    local item={id=id,method=method,path=path,bodyJson=body and json.encode(body),binary=binary,decodeImage=binary=='image',timeout=(lane=='catalogFetch'or service=='art'and path:find('network=1',1,true))and 20 or 8,retryRead=method=='GET'and(service=='catalog'or service=='art')}
    if queued then
        if priority=='selected'or priority=='selectedMetadata'then
            for index=#self.artQueue,1,-1 do local queued=self.artQueue[index]
                if self.pendingDetails[queued.id]and self.pendingDetails[queued.id].priority==priority then
                    table.remove(self.artQueue,index);cancelQueued(self,queued.id,'Image selection changed')
                end
            end
        elseif #self.artQueue>=64 then cancelQueued(self,id,'Visible image queue is full');return id end
        self.artQueue[#self.artQueue+1]=item;dispatchArt(self)
    else active.input:push(item)end
    return id
end
function API:update()
    local names={};for name in pairs(self.workers)do names[#names+1]=name end
    table.sort(names,function(a,b)if a==b then return false end;local ap,bp=a:match('^artSelected')and 0 or a:match('^artHand')and 1 or 2,b:match('^artSelected')and 0 or b:match('^artHand')and 1 or 2;if ap~=bp then return ap<bp end;return a<b end)
    local imageCount,imageBytes=0,0
    for _,name in ipairs(names)do local worker=self.workers[name]
        local result=worker.deferred or worker.output:pop();worker.deferred=nil
        while result do
            local detail=self.pendingDetails[result.id]
            local stale=detail and not current(detail)
            local size=result.imageData and(result.imageData.getSize and result.imageData:getSize()or 0)or 0
            if result.imageData and not stale and(imageCount>=2 or imageCount>0 and imageBytes+size>8*1024*1024)then worker.deferred=result;break end
            if result.imageData and not stale then imageCount=imageCount+1;imageBytes=imageBytes+size end
            if detail and detail.readKey and self.inflight[detail.readKey]==result.id then self.inflight[detail.readKey]=nil end
            local cb=self.pending[result.id];self.pending[result.id]=nil;self.pendingService[result.id]=nil;self.pendingDetails[result.id]=nil
            local waiters=self.waiters[result.id]or{};self.waiters[result.id]=nil
            local shared=type(result.body)=='table'and#waiters>0 and json.encode(result.body)
            local function body()return shared and json.decode(shared)or result.body end
            local generation=self.routes[result.id];self.routes[result.id]=nil
            local began=love.timer.getTime()
            if cb then
                local otherGame=generation~=nil and self.roomSession and self.roomSession.gameId and type(result.body)=='table' and result.body.gameId and result.body.gameId~=self.roomSession.gameId
                if stale then cb(nil,'Image selection changed',499)
                elseif generation~=nil and (generation~=self.routeGeneration or otherGame) then cb(nil,'Match connection changed',0)
                else cb(body(),result.error,result.code,result.imageData,result.timings,result.imageMeta) end
            end
            for _,waiting in ipairs(waiters)do if stale then waiting(nil,'Image selection changed',499)else waiting(body(),result.error,result.code,result.imageData,result.timings,result.imageMeta)end end
            if detail and detail.service=='art'then local metrics=self.imageMetrics;metrics.count=metrics.count+1
                metrics.queueSeconds=metrics.queueSeconds+math.max(0,(detail.dispatched or began)-detail.started)
                metrics.httpSeconds=metrics.httpSeconds+(result.timings and result.timings.httpSeconds or 0)
                metrics.decodeSeconds=metrics.decodeSeconds+(result.timings and result.timings.decodeSeconds or 0)
                metrics.callbackSeconds=metrics.callbackSeconds+love.timer.getTime()-began
            elseif detail and detail.priority=='selectedMetadata'then local metrics=self.imageMetrics
                metrics.metadataCount=(metrics.metadataCount or 0)+1
                metrics.metadataQueueSeconds=(metrics.metadataQueueSeconds or 0)+math.max(0,(detail.dispatched or began)-detail.started)
                metrics.metadataHttpSeconds=(metrics.metadataHttpSeconds or 0)+(result.timings and result.timings.httpSeconds or 0)
            end
            if result.imageData then result.imageData:release()end
            result=worker.output:pop()
        end
    end
    self.imageMetrics.lastFrameImages=imageCount;self.imageMetrics.lastFrameBytes=imageBytes
    dispatchArt(self)
end
function API:imageDiagnostics()
    local result={};for key,value in pairs(self.imageMetrics)do result[key]=value end
    result.queued=#self.artQueue;result.visibleInFlight=0;result.selectedInFlight=0;result.selectedMetadataInFlight=0;result.handInFlight=0;result.handMetadataInFlight=0
    for _,detail in pairs(self.pendingDetails)do if detail.service=='art'and not detail.queued then
        local key=detail.priority=='selected'and'selectedInFlight'or detail.priority=='hand'and'handInFlight'or'visibleInFlight';result[key]=result[key]+1
    end end
    for _,detail in pairs(self.pendingDetails)do if detail.priority=='selectedMetadata'and not detail.queued then result.selectedMetadataInFlight=result.selectedMetadataInFlight+1 end end
    for _,detail in pairs(self.pendingDetails)do if detail.priority=='handMetadata'and not detail.queued then result.handMetadataInFlight=result.handMetadataInFlight+1 end end
    return result
end
function API:status(service)
    local value={pending=0,oldestSeconds=0,controlPending=false};local now=love.timer.getTime()
    for _,detail in pairs(self.pendingDetails)do if not service or detail.service==service then
        value.pending=value.pending+1;value.oldestSeconds=math.max(value.oldestSeconds,now-detail.started)
        value.controlPending=value.controlPending or detail.control==true
    end end
    return value
end
function API:quit()
    -- A validation callback may enqueue the deck save the user already requested.
    -- Pump those callbacks before closing workers, including their chained writes.
    local deadline=love.timer.getTime()+3
    while love.timer.getTime()<deadline do
        self:update()
        local waiting=false
        for _,service in pairs(self.pendingService) do if service~='art' then waiting=true;break end end
        if not waiting then break end
        love.timer.sleep(.005)
    end
    for _,w in pairs(self.workers) do if w.service=='art' then w.input:clear() end;w.input:push({quit=true}) end
    -- Finish queued SQLite writes before the launcher closes owned services.
    deadline=love.timer.getTime()+2
    while love.timer.getTime()<deadline do
        local waiting=false;for _,w in pairs(self.workers)do if w.service~='art'and w.thread:isRunning()then waiting=true;break end end
        if not waiting then break end
        love.timer.sleep(.005)
    end
end
function API.escape(s) return tostring(s or ''):gsub('([^%w%-_%.~])',function(c) return string.format('%%%02X',c:byte()) end) end
return API
