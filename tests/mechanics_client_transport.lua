-- Actual LÖVE workers against an owned HTTP fault server, not a native game.
local API=require('app.api');local json=require('lib.json');local api,runner,wake= nil,nil,0;local checks={};local elapsed=0
local out=assert(os.getenv('L2G_MECHANICS_CLIENT_OUTPUT'));local port=assert(tonumber(os.getenv('L2G_MECHANICS_CLIENT_HTTP_PORT')))
local function check(v,label)assert(v,label);checks[#checks+1]=label end
local function wait(s)wake=love.timer.getTime()+(s or .02);coroutine.yield()end
local function ready(f,label,seconds)local deadline=love.timer.getTime()+(seconds or 5);while not f()and love.timer.getTime()<deadline do wait(.01)end;assert(f(),label)end
local function scenario()
 if api.setNativeSession then api:setNativeSession('game-old')end
 local stateDone=false;api:request('engine','GET','/session/state',nil,function()stateDone=true end)
 wait(.12);local began=love.timer.getTime();local concede
 api:request('engine','POST','/session/action',{type='concede',value=true,expectedGameId='game-old'},function(data,err)concede={data=data,err=err,elapsed=love.timer.getTime()-began}end)
 ready(function()return concede end,'Concede stuck behind slow state read')
 local latency=assert(io.open(out..'/control-latency.json','w'));latency:write(json.encode({seconds=concede.elapsed,ordinaryStateCompleted=stateDone,expectedMaximumSeconds=.7}));latency:close()
 check(concede.data and concede.data.expectedGameId=='game-old'and concede.elapsed<.7 and not stateDone,'Native concession lane responds while the ordinary state socket is still blocked (latency '..concede.elapsed..'s)')
 ready(function()return stateDone end,'Slow state did not complete');check(concede.data.type=='concede','Control lane retains the actual native concession payload')
 local oldDone,oldError;api:request('engine','GET','/session/state',nil,function(data,err)oldDone=true;oldError=err;check(data==nil,'A delayed old projection is not adopted')end)
 wait(.1);api:setNativeSession('game-new');ready(function()return oldDone end,'Old state request did not finish')
 check(oldError=='Match connection changed','A practice rematch invalidates the prior in-flight native projection')
 local body={type='concede',value=true};api:setRoomSession({connectionId='test-connection',gameId='room-game'})
 local room;api:request('engine','POST','/session/action',body,function(data)room=data end)
 ready(function()return room end,'Seat concession did not reach its private route')
 check(room.path=='/client/rooms/test-connection/game/action'and room.expectedGameId=='room-game','Room concession uses only its authenticated seat route and native round identity')
 check(body.expectedGameId==nil,'Control routing never mutates caller input')
 local staleRefusal;local staleId=api:request('engine','POST','/session/action',{type='boolean',value=true,promptId=1,expectedGameId='previous-round'},function(_,err)staleRefusal=err end)
 check(staleId==false and staleRefusal=='Match connection changed','A stale room action cannot be relabeled with the new round game identity')
 local refused;local id=api:request('engine','POST','/session/stop',{},function(_,err)refused=err end)
 check(id==false and refused and refused:find('room seat',1,true),'A room client cannot use the practice stop route')
 api:setRoomSession(nil)
 api:setNativeSession('game-new')
 local stopped;api:request('engine','POST','/session/stop',{},function(data)stopped=data end);ready(function()return stopped end,'Practice stop did not respond')
 check(stopped.expectedGameId=='game-new','Practice stop fills the exact native game identity without changing the caller')
 local ordinaryDone=false;api:request('engine','POST','/session/action',{type='string',value='slow-action'},function()ordinaryDone=true end)
 wait(.1);began=love.timer.getTime();local interrupted
 api:request('engine','POST','/session/action',{type='concede',value=true},function(data)interrupted=data;interrupted.elapsed=love.timer.getTime()-began end)
 ready(function()return interrupted end,'Concession was held behind an ordinary action')
 check(interrupted.elapsed<.7 and not ordinaryDone and interrupted.expectedGameId=='game-new','Concession is not queued behind a slow ordinary action response')
 ready(function()return ordinaryDone end,'Slow ordinary action did not settle')
 local failed;api:request('engine','GET','/invalid-json',nil,function(_,err)failed=err end);ready(function()return failed end,'Invalid JSON request did not settle')
 check(failed:find('Invalid response:',1,true),'Invalid transport JSON is an explicit error rather than a fabricated game state')
 local lost;api:request('engine','POST','/accepted-then-lost',{type='string',value='native-offered'},function(data,err)lost={data=data,err=err}end)
 ready(function()return lost end,'Dropped response never settled');check(lost.data==nil and lost.err,'A lost response remains uncertain and is not locally retried or converted into an outcome')
 local count;api:request('engine','GET','/accepted-count',nil,function(data)count=data end);ready(function()return count end,'Acceptance count request failed')
 check(count.accepted==1,'A transport error does not silently resubmit an already accepted action')
 local status=api:status();check(status.pending==0,'All completed requests release their pending diagnostics')
 local f=assert(io.open(out..'/transport.json','w'));f:write(json.encode({status='pass',scenarioId='client-http-delayed-state-and-seat-controls',evidenceType='client_transport',checks=checks,attempts=api.nextId,acceptedNativeActions=0,nativeEvents=0,sandboxHttpAccepted=count.accepted,controlLatencySeconds=concede.elapsed,scope='Actual asynchronous LÖVE LuaSocket workers and isolated synthetic HTTP faults; no native game'}));f:close()
 print('MECHANICS CLIENT TRANSPORT COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()api=API.new({enginePort=port,catalogPort=port,roomPort=port});runner=coroutine.create(scenario)end
function love.update(dt)
 elapsed=elapsed+dt;assert(elapsed<25,'Transport test deadline exceeded');api:update()
 if love.timer.getTime()>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 love.timer.sleep(.003)
end
function love.quit()if api then api:quit()end end
function love.errorhandler(message)io.stderr:write(tostring(message)..'\n'..debug.traceback()..'\n');return function()return 1 end end
