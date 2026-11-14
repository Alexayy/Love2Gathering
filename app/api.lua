local API = {}; API.__index=API
local json=require('lib.json')
function API.new(options)
    options=options or {}
    local self=setmetatable({nextId=0,pending={},pendingService={},workers={}},API)
    local catalogPort=tonumber(options.catalogPort or os.getenv('LOVE2GATHERING_CATALOG_PORT')) or 17370
    local enginePort=tonumber(options.enginePort or os.getenv('LOVE2GATHERING_ENGINE_PORT')) or 17371
    local roomPort=tonumber(options.roomPort or os.getenv('LOVE2GATHERING_ROOM_PORT')) or 17380
    self.catalogPort=catalogPort;self.enginePort=enginePort;self.roomPort=roomPort;self.routeGeneration=0;self.routes={}
    for name,port in pairs({catalog=catalogPort,engine=enginePort,room=roomPort,art=catalogPort}) do
        local prefix='l2g_'..name..'_'..tostring(love.timer.getTime())
        local worker={input=love.thread.getChannel(prefix..'_in'),output=love.thread.getChannel(prefix..'_out'),thread=love.thread.newThread('app/http_worker.lua')}
        worker.thread:start(prefix..'_in',prefix..'_out',port);self.workers[name]=worker
    end
    return self
end
function API:setRoomSession(session)
    local previous=self.roomSession and (self.roomSession.connectionId..':'..tostring(self.roomSession.gameId or ''))
    local current=session and (session.connectionId..':'..tostring(session.gameId or ''))
    if previous~=current then self.routeGeneration=self.routeGeneration+1 end
    self.roomSession=session
end
function API:request(service,method,path,body,callback,binary)
    local routes={['/session/state']='game/state',['/session/action']='game/action',['/session/priority']='game/priority',['/session/replay/save']='game/replay/save'}
    local guarded=service=='engine' and routes[path]~=nil
    if guarded and self.roomSession then
        path='/client/rooms/'..API.escape(self.roomSession.connectionId)..'/'..routes[path];service='room'
        if method=='POST' and self.roomSession.gameId then
            local scoped={};for key,value in pairs(body or {}) do scoped[key]=value end
            scoped.expectedGameId=self.roomSession.gameId;body=scoped
        end
    end
    self.nextId=self.nextId+1
    self.pending[self.nextId]=callback or function() end
    self.pendingService[self.nextId]=service
    self.routes[self.nextId]=guarded and self.routeGeneration or nil
    -- Channel tables do not preserve metatables, so serialize arrays here.
    self.workers[service].input:push({id=self.nextId,method=method,path=path,bodyJson=body and json.encode(body),binary=binary})
    return self.nextId
end
function API:update()
    for _,worker in pairs(self.workers) do
        local result=worker.output:pop()
        while result do
            local cb=self.pending[result.id];self.pending[result.id]=nil;self.pendingService[result.id]=nil
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
        if not self.workers.catalog.thread:isRunning() and not self.workers.engine.thread:isRunning() and not self.workers.room.thread:isRunning() then break end
        love.timer.sleep(.005)
    end
end
function API.escape(s) return tostring(s or ''):gsub('([^%w%-_%.~])',function(c) return string.format('%%%02X',c:byte()) end) end
return API
