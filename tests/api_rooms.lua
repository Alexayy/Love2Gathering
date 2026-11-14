-- Transport fencing across local practice, remote seats and native draft rounds.
package.path='./?.lua;'..package.path
local channels={};local now=0
love={timer={getTime=function()now=now+.001;return now end},thread={}}
function love.thread.getChannel(name)
    if not channels[name] then
        local channel={}
        function channel:push(value)self[#self+1]=value end
        function channel:pop()return table.remove(self,1)end
        channels[name]=channel
    end
    return channels[name]
end
function love.thread.newThread()
    return {start=function()end,isRunning=function()return false end}
end
local API=require('app.api');local json=require('lib.json');local passed=0
local function check(value,label)assert(value,label);passed=passed+1;print('API ROOMS PASS '..label)end
local api=API.new({enginePort=17402,catalogPort=17400,roomPort=17421})
check(api.roomPort==17421 and api.enginePort==17402,'Isolated desktop workers keep distinct service ports')
local oldResult
local old=api:request('engine','GET','/session/state',nil,function(body,err)oldResult={body,err}end)
check(api.workers.engine.input:pop().path=='/session/state','Practice state uses the native local worker')
api:setRoomSession({connectionId='guest-code-token',gameId='round-one'})
api.workers.engine.output:push({id=old,body={gameId='practice'},code=200});api:update()
check(oldResult[1]==nil and oldResult[2]=='Match connection changed','A late practice response cannot replace an authenticated room game')
local body={promptId=7,type='boolean',value=true}
api:request('engine','POST','/session/action',body,function()end)
local action=api.workers.room.input:pop();local sent=json.decode(action.bodyJson)
check(action.path=='/client/rooms/guest-code-token/game/action'and sent.expectedGameId=='round-one'and sent.promptId==7,'Actions carry the authenticated connection and native round identity')
check(body.expectedGameId==nil,'Routing does not mutate the caller’s pending action')
api:request('engine','GET','/health',nil,function()end)
check(api.workers.engine.input:pop().path=='/health','Native health remains separate from private room gameplay')
local roundResult
local pending=api:request('engine','GET','/session/state',nil,function(value,err)roundResult={value,err}end)
api.workers.room.input:pop()
api:setRoomSession({connectionId='guest-code-token',gameId='round-two'})
api.workers.room.output:push({id=pending,body={gameId='round-one'},code=200});api:update()
check(roundResult[1]==nil and roundResult[2]=='Match connection changed','Switching rounds fences the old game even on the same room connection')
local currentResult
local current=api:request('engine','POST','/session/priority',{command='end-turn'},function(value)currentResult=value end)
action=api.workers.room.input:pop();sent=json.decode(action.bodyJson)
check(action.path:find('/game/priority',1,true)and sent.expectedGameId=='round-two','Priority commands follow the new native match')
api:setRoomSession({connectionId='guest-code-token',gameId='round-two'})
api.workers.room.output:push({id=current,body={gameId='round-two'},code=200});api:update()
check(currentResult.gameId=='round-two','Repeated snapshots for the same match do not invalidate valid replies')
local unexpectedResult
local unexpected=api:request('engine','GET','/session/state',nil,function(value,err)unexpectedResult={value,err}end)
api.workers.room.input:pop()
api.workers.room.output:push({id=unexpected,body={gameId='round-three'},code=200});api:update()
check(unexpectedResult[1]==nil and unexpectedResult[2]=='Match connection changed','An assignment changed on the server waits for its authenticated room snapshot before adoption')
api:setRoomSession(nil)
api:request('engine','GET','/session/state',nil,function()end)
check(api.workers.engine.input:pop().path=='/session/state','Leaving restores local practice routing')
print('API room checks: '..passed..' passed')
