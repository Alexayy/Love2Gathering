-- Actual worker/socket read independence and route generations, no native game.
local API=require('app.api');local json=require('lib.json')
local output=assert(os.getenv('L2G_READ_LANES_OUTPUT'));local port=assert(tonumber(os.getenv('L2G_READ_LANES_PORT')))
local api,runner,wake;local elapsed=0;local checks=json.array();local failures=json.array();local timings={};local closed=false
local function check(ok,label)checks[#checks+1]={passed=not not ok,message=label};if not ok then failures[#failures+1]=label end;print('READ LANES '..(ok and'PASS 'or'FAIL ')..label)end
local function wait(seconds)wake=love.timer.getTime()+(seconds or .004);coroutine.yield()end
local function ready(fn,message,timeout)local untilAt=love.timer.getTime()+(timeout or 4);while not fn()and love.timer.getTime()<untilAt do wait()end;assert(fn(),message)end
local function scenario()
 local started=love.timer.getTime()
 check(not api.workers.engineState and not api.workers.engineHealth and not api.workers.roomState,'State and health lanes are absent until first use')
 for _,phase in ipairs({'native','room'})do
  if phase=='native'then api:setNativeSession('native-live')else api:setRoomSession({connectionId='owned-live',gameId='room-live'})end
  local got={};local began=love.timer.getTime();local body={probe=phase..'-A',type='boolean',value=true}
  api:request('engine','POST','/session/action',body,function(data,err,code)got.A={data=data,error=err,code=code,seconds=love.timer.getTime()-began}end)
  api:request('engine','POST','/session/priority',{probe=phase..'-B'},function(data,err,code)got.B={data=data,error=err,code=code,seconds=love.timer.getTime()-began}end)
  wait(.06);local readStart=love.timer.getTime()
  api:request('engine','GET','/session/state',nil,function(data,err,code)got.state={data=data,error=err,code=code,seconds=love.timer.getTime()-readStart,actionStillPending=got.A==nil}end)
  api:request('engine','GET','/health',nil,function(data,err,code)got.health={data=data,error=err,code=code,seconds=love.timer.getTime()-readStart,actionStillPending=got.A==nil}end)
  ready(function()return got.state and got.health and got.A and got.B end,phase..' independent requests never settled')
  check(got.state.code==200 and got.state.data and got.state.data.gameId==phase..'-live'and not got.state.error,phase..' state responds through the actual HTTP worker')
  check(got.health.code==200 and got.health.data and got.health.data.ok and not got.health.error,phase..' health responds through the actual HTTP worker')
  check(got.state.seconds<1 and got.state.actionStillPending and got.state.data.actionStillHeld,phase..' state completes before a held ordinary mutation')
  check(got.health.seconds<1 and got.health.actionStillPending and got.health.data.actionStillHeld,phase..' health completes before a held ordinary mutation')
  check(got.A.code==200 and got.A.data.readsArrived and got.B.code==200 and got.B.data.firstMutationFinished,phase..' ordinary action and priority mutations retain FIFO order')
  check(got.A.data.expectedGameId==phase..'-live'and got.B.data.expectedGameId==phase..'-live',phase..' ordered mutations preserve their exact game guard')
  check(body.expectedGameId==nil,phase..' routing never mutates the caller action table')
  timings[phase]={stateSeconds=got.state.seconds,healthSeconds=got.health.seconds,heldMutationSeconds=got.A.seconds,secondMutationSeconds=got.B.seconds}
 end
 api:setRoomSession(nil);api:setNativeSession('native-old');local staleNative,freshNative
 api:request('engine','GET','/session/state',nil,function(data,err,code)staleNative={data=data,error=err,code=code}end)
 wait(.06);api:setNativeSession('native-new')
 api:request('engine','GET','/session/state',nil,function(data,err,code)freshNative={data=data,error=err,code=code}end)
 ready(function()return staleNative and freshNative end,'Native route generations never settled')
 check(staleNative.data==nil and staleNative.code==0 and staleNative.error=='Match connection changed','A real delayed old native state is rejected after session replacement')
 check(freshNative.code==200 and freshNative.data.gameId=='native-new'and not freshNative.error,'The new native session accepts only its own fresh state')
 api:setRoomSession({connectionId='owned-old',gameId='room-old'});local staleRoom,freshRoom
 api:request('engine','GET','/session/state',nil,function(data,err,code)staleRoom={data=data,error=err,code=code}end)
 wait(.06);api:setRoomSession({connectionId='owned-new',gameId='room-new'})
 api:request('engine','GET','/session/state',nil,function(data,err,code)freshRoom={data=data,error=err,code=code}end)
 ready(function()return staleRoom and freshRoom end,'Room route generations never settled')
 check(staleRoom.data==nil and staleRoom.code==0 and staleRoom.error=='Match connection changed','A real delayed old room state is rejected after connection replacement')
 check(freshRoom.code==200 and freshRoom.data.gameId=='room-new'and not freshRoom.error,'The new room seat accepts only its own routed state')
 local counters;api:request('catalog','GET','/probe/summary',nil,function(data)counters=data end);ready(function()return counters end,'Actual HTTP ledger did not arrive')
 check(table.concat(counters.mutationOrder,',')=='native-A,native-B,room-A,room-B','All four requested mutations reach HTTP once in the original per-service order')
 check(counters.nativeReads==3 and counters.roomReads==3 and counters.healthReads==2,'Exact read counts show no hidden mutation replay or polling storm')
 check(counters.orderViolations==0,'A second ordinary mutation never reaches the server before its predecessor finishes')
 api:quit();closed=true
 ready(function()for _,worker in pairs(api.workers)do if worker.thread:isRunning()then return false end end;return true end,'HTTP worker threads did not terminate',2)
 check(true,'Every actual HTTP worker exits after its bounded queue is drained')
 local workers=json.array();for name in pairs(api.workers)do workers[#workers+1]=name end;table.sort(workers)
 check(api.workers.engineState and api.workers.engineHealth and api.workers.roomState,'Read lanes are created lazily as distinct actual workers')
 local f=assert(io.open(output..'/result.json','w'));f:write(json.encode({status=#failures==0 and'pass'or'fail',checks=checks,failures=failures,timing=timings,httpLedger=counters,workers=workers,allWorkerThreadsTerminated=true,seconds=love.timer.getTime()-started,nativeGame=false}));f:close();love.event.quit(#failures==0 and 0 or 1)
end
function love.load()api=API.new({catalogPort=port,enginePort=port,roomPort=port});runner=coroutine.create(scenario)end
function love.update(dt)
 elapsed=elapsed+dt;assert(elapsed<16,'Read-lane socket acceptance exceeded16 seconds')
 for _,worker in pairs(api.workers)do assert(not worker.thread:getError(),worker.thread:getError())end
 api:update();if not wake or love.timer.getTime()>=wake then if coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end end;love.timer.sleep(.002)
end
function love.quit()if api and not closed then api:quit()end end
function love.errorhandler(message)io.stderr:write(tostring(message)..'\n'..debug.traceback()..'\n');return function()return 1 end end
