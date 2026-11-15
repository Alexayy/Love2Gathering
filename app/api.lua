local API = {}; API.__index=API
local json=require('lib.json')
local instanceSequence=0
local function worker(self,name,port)
    local prefix='l2g_'..self.instanceId..'_'..name
    local value={input=love.thread.getChannel(prefix..'_in'),output=love.thread.getChannel(prefix..'_out'),thread=love.thread.newThread('app/http_worker.lua')}
    value.thread:start(prefix..'_in',prefix..'_out',port);self.workers[name]=value
    return value
end
function API.new(options)
    options=options or {}
    instanceSequence=instanceSequence+1
    local self=setmetatable({nextId=0,pending={},pendingService={},pendingDetails={},workers={},instanceId=tostring(love.timer.getTime())..'_'..instanceSequence},API)
    local catalogPort=tonumber(options.catalogPort or os.getenv('LOVE2GATHERING_CATALOG_PORT')) or 17370
    local enginePort=tonumber(options.enginePort or os.getenv('LOVE2GATHERING_ENGINE_PORT')) or 17371
    local roomPort=tonumber(options.roomPort or os.getenv('LOVE2GATHERING_ROOM_PORT')) or 17380
    self.catalogPort=catalogPort;self.enginePort=enginePort;self.roomPort=roomPort;self.routeGeneration=0;self.routes={}
    for name,port in pairs({catalog=catalogPort,engine=enginePort,room=roomPort,art=catalogPort}) do
        worker(self,name,port)
    end
    return self
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
function API:request(service,method,path,body,callback,binary)
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
    local active=self.workers[lane]or worker(self,lane,service=='room'and self.roomPort or self.enginePort)
    self.nextId=self.nextId+1
    self.pending[self.nextId]=callback or function() end
    self.pendingService[self.nextId]=service
    self.pendingDetails[self.nextId]={worker=lane,service=service,started=love.timer.getTime(),control=control}
    self.routes[self.nextId]=guarded and self.routeGeneration or nil
    -- Channel tables do not preserve metatables, so serialize arrays here.
    active.input:push({id=self.nextId,method=method,path=path,bodyJson=body and json.encode(body),binary=binary})
    return self.nextId
end
function API:update()
    for _,worker in pairs(self.workers) do
        local result=worker.output:pop()
        while result do
            local cb=self.pending[result.id];self.pending[result.id]=nil;self.pendingService[result.id]=nil;self.pendingDetails[result.id]=nil
            local generation=self.routes[result.id];self.routes[result.id]=nil
            if cb then
                local otherGame=generation~=nil and self.roomSession and self.roomSession.gameId and type(result.body)=='table' and result.body.gameId and result.body.gameId~=self.roomSession.gameId
                if generation~=nil and (generation~=self.routeGeneration or otherGame) then cb(nil,'Match connection changed',0)
                else cb(result.body,result.error,result.code) end
            end
            result=worker.output:pop()
        end
    end
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
    for name,w in pairs(self.workers) do if name=='art' then w.input:clear() end;w.input:push({quit=true}) end
    -- Finish queued SQLite writes before the launcher closes owned services.
    deadline=love.timer.getTime()+2
    while love.timer.getTime()<deadline do
        local waiting=false;for name,w in pairs(self.workers)do if name~='art'and w.thread:isRunning()then waiting=true;break end end
        if not waiting then break end
        love.timer.sleep(.005)
    end
end
function API.escape(s) return tostring(s or ''):gsub('([^%w%-_%.~])',function(c) return string.format('%%%02X',c:byte()) end) end
return API
