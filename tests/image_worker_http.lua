-- Actual production HTTP/decode workers with native allocation auditing.
local API=require('app.api');local json=require('lib.json')
local output=assert(os.getenv('L2G_IMAGE_WORKER_OUTPUT'))
local port=assert(tonumber(os.getenv('L2G_IMAGE_WORKER_PORT')))
local jpegBytes=assert(tonumber(os.getenv('L2G_IMAGE_WORKER_JPEG_BYTES')))
local expectedJPEG=assert(love.filesystem.read('fixture.jpg'))
local api,runner,wake;local checks,failures=json.array(),json.array();local elapsed=0
local allocations=json.array();local audit=love.thread.getChannel('image_worker_allocation_audit')
local mainDecoderCalls=0;local closed=false
local function check(value,message)
 checks[#checks+1]={passed=not not value,message=message}
 if not value then failures[#failures+1]=message end
end
local function wait(seconds)wake=love.timer.getTime()+(seconds or .003);coroutine.yield()end
local function untilReady(fn,message,seconds)
 local deadline=love.timer.getTime()+(seconds or 5)
 while not fn()and love.timer.getTime()<deadline do wait()end
 assert(fn(),message)
end
local function drain()
 local item=audit:pop()
 while item do allocations[#allocations+1]=item;item=audit:pop()end
 return #allocations
end
local function live(data)
 if not data then return false end
 local ok,w,h=pcall(data.getDimensions,data)
 return ok and w==32 and h==32
end
local function released(data)return data and not pcall(data.getWidth,data)end
local function scenario()
 local started=love.timer.getTime();local received={};local references={}
 local path='/art/tiny.jpg?coalesced=1'
 local function decoded(label)
  return function(body,err,code,data)
   received[label]={body=body,error=err,code=code,alive=live(data)};references[label]=data
  end
 end
 local first=api:request('art','GET',path,nil,decoded('first'),'image')
 local second=api:request('art','GET',path,nil,decoded('second'),'image')
 local raw=api:request('art','GET',path,nil,function(body,err,code,data)received.raw={body=body,error=err,code=code,imageData=data}end,true)
 check(first==second,'Two decoded-image consumers coalesce into one production HTTP request')
 check(raw~=first,'Raw binary and decoded-image requests for the same path keep separate identities')
 untilReady(function()return received.first and received.second and received.raw end,'Image/raw callbacks did not complete')
 for _,label in ipairs({'first','second'})do
  local item=received[label]
  check(item.code==200 and not item.error and item.body==nil and item.alive,label..' callback receives live ImageData as argument four and no compressed body')
 end
 check(references.first==references.second,'Both coalesced callbacks share the live decoded buffer')
 check(released(references.first)and released(references.second),'API releases the decoded buffer only after both callbacks finish')
 check(received.raw.code==200 and not received.raw.error and received.raw.body==expectedJPEG and#received.raw.body==jpegBytes and not received.raw.imageData,'The separate raw request still returns exact JPEG bytes without ImageData')
 check(drain()==1,'Only the decoded request invokes the worker native decoder')

 local bad={
  {path='/art/corrupt-header.png',native=0},
  {path='/art/corrupt-header.jpg',native=0},
  {path='/art/corrupt-pixels.png',native=1,problem='Image decode failed'},
  {path='/art/oversized.png',native=0,problem='decoded pixel bound'},
  {path='/art/oversized.jpg',native=0,problem='decoded pixel bound'},
  {path='/art/oversized-compressed.jpg',native=0,problem='compressed size bound'},
 }
 local invalidResults=json.array()
 for index,item in ipairs(bad)do
  local before=drain();local reply;local began=love.timer.getTime()
  local id=api:request('art','GET',item.path,nil,function(body,err,code,data)reply={body=body,error=err,code=code,imageData=data}end,'image')
  local lane=api.pendingDetails[id].worker
  untilReady(function()return reply end,'Malformed image request hung: '..item.path)
  local attempts=drain()-before
  check((reply.code==200 or item.path:find('oversized%-compressed')and reply.code==0)and type(reply.error)=='string'and reply.error~=''and reply.body==nil and reply.imageData==nil,item.path..' fails cleanly without a decoded buffer')
  check(attempts==item.native,item.path..' native allocation count respects the header bound')
  if item.problem then check(reply.error:find(item.problem,1,true),item.path..' reports its precise decoder/bound failure')end
  invalidResults[#invalidResults+1]={path=item.path,error=reply.error,allocationAttempts=attempts,seconds=love.timer.getTime()-began}
  local recovery;local recoveryId=api:request('art','GET','/art/recovery.jpg?case='..index,nil,function(body,err,code,data)recovery={code=code,error=err,alive=live(data)}end,'image')
  check(api.pendingDetails[recoveryId].worker==lane,'Recovery request returns to the same worker after '..item.path)
  untilReady(function()return recovery end,'A decoder error killed its worker')
  check(recovery.code==200 and not recovery.error and recovery.alive and api.workers[lane].thread:isRunning(),'The real HTTP worker remains usable after '..item.path)
 end

 local slowA,slowB=false,false
 api:request('catalog','GET','/cards?q=hold-a',nil,function()slowA=true end)
 api:request('catalog','GET','/cards?q=hold-b',nil,function()slowB=true end)
 wait(.08)
 local fast={};local fastStarted=love.timer.getTime()
 for _,item in ipairs({{'metadata','/cards/by-name?name=Swamp'},{'choices','/printings?name=Swamp'},{'profile','/profile'}})do
  local label,route=item[1],item[2]
  api:request('catalog','GET',route,nil,function(body,err,code)fast[label]={body=body,error=err,code=code,seconds=love.timer.getTime()-fastStarted,bothSearchesPending=not slowA and not slowB}end)
 end
 untilReady(function()return fast.metadata and fast.choices and fast.profile end,'Metadata/edition lanes did not respond')
 for _,label in ipairs({'metadata','choices','profile'})do
  local value=fast[label]
  check(value.code==200 and not value.error and value.body.name=='Swamp'and value.body.heldSearches==2,label..' reaches the fixture while both search workers are held')
  check(value.seconds<.5 and value.bothSearchesPending,label..' is independent of the two 1.2-second searches')
 end
 untilReady(function()return slowA and slowB end,'Held search requests never settled')

 local selection='a';local selectedA,selectedB;local selectedStarted=love.timer.getTime()
 local aid=api:request('art','GET','/art/selected-a.jpg?network=1&priority=selected',nil,function(body,err,code,data)selectedA={code=code,data=data}end,'image',{priority='selected',selectionToken='a',isCurrent=function()return selection=='a'end})
 wait(.06);selection='b';local bStarted=love.timer.getTime()
 local bid=api:request('art','GET','/art/selected-b.jpg?network=1&priority=selected',nil,function(body,err,code,data,timings,meta)selectedB={code=code,alive=live(data),seconds=love.timer.getTime()-bStarted,timings=timings,meta=meta}end,'image',{priority='selected',selectionToken='b',isCurrent=function()return selection=='b'end})
 check(api.pendingDetails[aid].worker~=api.pendingDetails[bid].worker,'A second actual selected socket bypasses an obsolete slow fetch')
 untilReady(function()return selectedB end,'The new selected image did not complete')
 check(selectedB.code==200 and selectedB.alive and selectedB.seconds<.5 and not selectedA,'The current selection loads before the old 1.2-second image request finishes')
 check(selectedB.timings.httpSeconds>=0 and selectedB.timings.decodeSeconds>=0 and selectedB.meta.variant=='original','Actual worker callbacks preserve bounded stage timings and image variant headers')
 untilReady(function()return selectedA end,'The obsolete selected request never settled')
 check(selectedA.code==499 and not selectedA.data,'An obsolete HTTP/decode completion releases its pixels instead of delivering stale selected artwork')

 local rotation={};local complete=0;local rotationStarted=love.timer.getTime()
 for index=1,50 do
  api:request('art','GET','/art/rotation.png?image='..index,nil,function(body,err,code,data)
   rotation[index]={body=body,error=err,code=code,alive=live(data),data=data};complete=complete+1
  end,'image')
 end
 untilReady(function()return complete==50 end,'Fifty real decoded HTTP requests did not complete')
 local allLive,allReleased=true,true
 for _,value in pairs(rotation)do
  allLive=allLive and value.code==200 and not value.error and value.body==nil and value.alive
  allReleased=allReleased and released(value.data)
 end
 check(allLive,'Fifty queued PNG requests deliver genuine decoded pixels without decoding on the main thread')
 check(allReleased,'All fifty API-owned decoded buffers are released after their callbacks')
 check(api:status().pending==0,'Every queued image/metadata/search request leaves the API pending set')
 check(mainDecoderCalls==0,'The main-thread decoder override was never invoked')
 local counters;api:request('catalog','GET','/probe/state',nil,function(body)counters=body end)
 untilReady(function()return counters end,'Final fixture request counters did not respond')
 check(counters.requests[path]==2,'Coalesced image plus raw mode makes exactly two real HTTP requests')
 drain();check(#allocations==60,'Only valid buffers and the bounded corrupt-pixel decode invoke native allocation')
 api:quit();closed=true
 untilReady(function()for _,worker in pairs(api.workers)do if worker.thread:isRunning()then return false end end;return true end,'Owned HTTP workers did not stop',2)
 check(true,'All actual HTTP threads stop after their owned queues finish')
 local timings={};for label,value in pairs(fast)do timings[label]={seconds=value.seconds,bothSearchesPending=value.bothSearchesPending}end
 local result={status=#failures==0 and'pass'or'fail',checks=checks,failures=failures,invalidImages=invalidResults,fastLanes=timings,selectedCurrentSeconds=selectedB.seconds,imageDiagnostics=api:imageDiagnostics(),mainThreadDecodeCalls=mainDecoderCalls,nativeDecodeAttempts=#allocations,rotationRequests=50,rotationSeconds=love.timer.getTime()-rotationStarted,durationSeconds=love.timer.getTime()-started,allWorkerThreadsTerminated=true,allocations=allocations,nativeGame=false}
 local file=assert(io.open(output..'/result.json','w'));file:write(json.encode(result));file:close()
 print('IMAGE WORKER HTTP '..result.status..' '..#checks..' checks');love.event.quit(#failures==0 and 0 or 1)
end
function love.load()
 -- Each real worker loads the unchanged production file. The wrapper records
 -- native decode calls, so oversized headers must reject before any allocation.
 local nativeThread=love.thread.newThread
 love.thread.newThread=function(file)
  if file~='app/http_worker.lua'then return nativeThread(file)end
  return nativeThread([[
local args={...}
require('love.image');require('love.filesystem')
local native=love.image.newImageData
local audit=love.thread.getChannel('image_worker_allocation_audit')
love.image.newImageData=function(file,...)
 audit:push({bytes=file:getSize(),worker=args[1]})
 return native(file,...)
end
assert(love.filesystem.load('app/http_worker.lua'))(unpack(args))
]])
 end
 love.image.newImageData=function()mainDecoderCalls=mainDecoderCalls+1;error('Image decoding reached the main thread')end
 api=API.new({catalogPort=port,enginePort=port,roomPort=port});runner=coroutine.create(scenario)
end
function love.update(dt)
 elapsed=elapsed+dt;assert(elapsed<18,'Image worker fixture exceeded eighteen seconds')
 for _,worker in pairs(api.workers)do assert(not worker.thread:getError(),worker.thread:getError())end
 api:update()
 if not wake or love.timer.getTime()>=wake then
  if coroutine.status(runner)~='dead'then local ok,problem=coroutine.resume(runner);assert(ok,problem)end
 end
 love.timer.sleep(.002)
end
function love.quit()if api and not closed then api:quit()end end
function love.errorhandler(message)
 io.stderr:write(tostring(message)..'\n'..debug.traceback()..'\n');return function()return 1 end
end
