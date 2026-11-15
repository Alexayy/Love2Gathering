-- Real LÖVE LuaSocket workers against isolated catalog/storage plus explicit latency faults.
local API=require('app.api');local json=require('lib.json')
local api,runner,wake;local checks,failures=json.array(),json.array();local values={};local elapsed=0
local output=assert(os.getenv('L2G_LOADING_HTTP_OUTPUT'))
local port=assert(tonumber(os.getenv('L2G_LOADING_HTTP_PORT')))
local oracle=assert(os.getenv('L2G_LOADING_HTTP_ORACLE'))
local printing=assert(os.getenv('L2G_LOADING_HTTP_PRINTING'))
local function check(value,message)
 checks[#checks+1]={passed=not not value,message=message}
 if not value then failures[#failures+1]=message end
end
local function wait(seconds)wake=love.timer.getTime()+(seconds or .005);coroutine.yield()end
local function untilReady(fn,message,seconds)
 local deadline=love.timer.getTime()+(seconds or 5)
 while not fn()and love.timer.getTime()<deadline do wait()end
 assert(fn(),message)
end
local function scenario()
 local slowMaintenance,slowImage=false,false
 local art='/art/'..oracle..'?printing='..printing..'&kind=normal&exact=1&network=0'
 local began=love.timer.getTime()
 api:request('catalog','GET','/storage/status?probe=slow',nil,function()slowMaintenance=true end)
 api:request('art','GET',art..'&probe=slow',nil,function()slowImage=true end,true)
 wait(.07)
 local fastBegan=love.timer.getTime()
 local function received(name,data,err,code)
  values[name]={data=data,error=err,code=code,seconds=love.timer.getTime()-fastBegan,
   slowMaintenanceCompleted=slowMaintenance,slowImageCompleted=slowImage}
 end
 for _,item in ipairs({{'settings','/settings'},{'profile','/profile'},{'cards','/cards?q=Plains&limit=5'},{'decks','/decks'}})do
  local name,path=item[1],item[2]
  api:request('catalog','GET',path,nil,function(data,err,code)received(name,data,err,code)end)
 end
 api:request('art','GET',art,nil,function(data,err,code)received('cachedImage',data,err,code)end,true)
 untilReady(function()return values.settings and values.profile and values.cards and values.decks and values.cachedImage end,'Foreground catalog/image callbacks never completed')
 for _,name in ipairs({'settings','profile','cards','decks','cachedImage'})do
  local value=values[name]
  check(value.code==200 and not value.error,name..' responds successfully from the real local service')
  check(value.seconds<.7 and not value.slowMaintenanceCompleted and not value.slowImageCompleted,name..' is not queued behind either 1.4-second request')
 end
 check(values.settings.data.theme=='Ember'and values.settings.data.accentColor=='#d67b52','Saved theme and color arrive without default substitution')
 check(values.profile.data.name=='Loading Fixture','Saved profile name survives active image writes')
 check(values.cards.data.cards[1]and values.cards.data.cards[1].name=='Plains','Real catalog search returns the requested card')
 check(values.decks.data.decks[1]and values.decks.data.decks[1].id=='loading-deck','Saved deck remains available while its cached image is requested')
 local pixels=love.image.newImageData(love.filesystem.newFileData(values.cachedImage.data,'cached.jpg'))
 check(pixels:getWidth()==32 and pixels:getHeight()==32,'Cached binary response is a genuinely decoded 32×32 JPEG fixture')
 local active;api:request('catalog','GET','/probe/state',nil,function(data)active=data end)
 untilReady(function()return active end,'Background job state did not respond')
 check(active.download.state=='downloading'and active.download.processed>0,'Managed download remains active while foreground artwork takes priority')
 check(active.cachedDeckFetches==0,'Already-cached deck printing is never fetched by the managed downloader')
 untilReady(function()return slowMaintenance and slowImage end,'Injected slow requests never completed')
 local resumed
 for _=1,60 do
  api:request('catalog','GET','/probe/state',nil,function(data)resumed=data end)
  wait(.05)
  if resumed and resumed.download.downloaded>0 then break end
 end
 check(resumed and resumed.download.downloaded>0,'Managed download resumes real committed progress after foreground artwork completes')
 local retry;api:request('catalog','GET','/probe/retry',nil,function(data,err,code)retry={data=data,error=err,code=code}end)
 untilReady(function()return retry end,'Retryable GET never settled')
 check(retry.code==200 and retry.data and retry.data.attempt==2,'A retryable 503 GET is retried once and receives 200')
 local mutation;api:request('catalog','POST','/probe/mutation',{fixture=true},function(data,err,code)mutation={data=data,error=err,code=code}end)
 untilReady(function()return mutation end,'503 POST never settled')
 check(mutation.code==503,'A POST 503 is returned to its caller without a guessed success')
 local shared,first,second
 local coalesced='/cards?q=Plains&limit=5&probe=coalesced'
 first=api:request('catalog','GET',coalesced,nil,function(data)shared=shared or{};shared.first=data;data.testMutation=true end)
 second=api:request('catalog','GET',coalesced,nil,function(data)shared=shared or{};shared.second=data end)
 untilReady(function()return shared and shared.first and shared.second end,'Coalesced callbacks did not both complete')
 check(first==second,'Identical pending GETs share one request')
 check(shared.second.testMutation==nil,'Coalesced callback bodies remain independent')
 local writes,refreshes={},{}
 local function save(label,theme)
  api:request('catalog','PUT','/settings',{theme=theme},function(data,err,code)
   writes[label]={data=data,error=err,code=code}
   api:request('catalog','GET','/settings',nil,function(saved,readError,readCode)
    refreshes[label]={data=saved,error=readError,code=readCode}
   end)
  end)
 end
 save('A','Ocean');save('B','Ember')
 untilReady(function()return refreshes.A and refreshes.B end,'Queued settings writes and callback refreshes never settled')
 check(writes.A.code==200 and writes.B.code==200 and not writes.A.error and not writes.B.error,'Both queued real SQLite settings saves succeed')
 for _,label in ipairs({'A','B'})do
  check(refreshes[label].code==200 and not refreshes[label].error and refreshes[label].data.theme=='Ember',label..' save callback refresh observes final B theme')
 end
 local counters;api:request('catalog','GET','/probe/state',nil,function(data)counters=data end)
 untilReady(function()return counters end,'Final request counters did not settle')
 check(counters.retryGets==2,'GET 503 request count is exactly two')
 check(counters.mutationPosts==1,'POST 503 request count is exactly one; no mutation replay')
 check(counters.coalescedGets==1,'Coalesced duplicate GET reaches HTTP exactly once')
 check(counters.cachedDeckFetches==0,'Cached deck printing was not downloaded later either')
 check(counters.settingsPuts==2,'Two requested settings mutations reach HTTP exactly once each')
 check(counters.settingsRefreshGets==1 and counters.settingsReadSnapshots[1]=='Ember','Callback refreshes coalesce only after the final queued mutation commits')
 local timing={};for name,value in pairs(values)do timing[name]={seconds=value.seconds,code=value.code,slowMaintenanceCompleted=value.slowMaintenanceCompleted,slowImageCompleted=value.slowImageCompleted}end
 local result={status=#failures==0 and'pass'or'fail',checks=checks,failures=failures,timing=timing,durationSeconds=love.timer.getTime()-began,
  activeDownload={state=active.download.state,processed=active.download.processed,downloaded=active.download.downloaded},resumedDownload=resumed and resumed.download,
  requestCounts={retryGets=counters.retryGets,mutationPosts=counters.mutationPosts,coalescedGets=counters.coalescedGets,cachedDeckFetches=counters.cachedDeckFetches,settingsPuts=counters.settingsPuts,settingsRefreshGets=counters.settingsRefreshGets},
  orderedWriteRefreshes={A=refreshes.A.data.theme,B=refreshes.B.data.theme,snapshots=counters.settingsReadSnapshots},
  jpegBytes=#values.cachedImage.data,nativeGame=false,scope='Actual headless LÖVE LuaSocket workers and real isolated SQLite/catalog/download manager; generated JPEG fixture, synthetic HTTP latency/status faults; no native game or external image acquisition'}
 local f=assert(io.open(output..'/result.json','w'));f:write(json.encode(result));f:close()
 print('LOADING HTTP '..result.status..' '..#checks..' checks');love.event.quit(#failures==0 and 0 or 1)
end
function love.load()
 api=API.new({catalogPort=port,enginePort=port,roomPort=port});runner=coroutine.create(scenario)
end
function love.update(dt)
 elapsed=elapsed+dt;assert(elapsed<20,'HTTP loading fixture exceeded 20 seconds');api:update()
 if not wake or love.timer.getTime()>=wake then
  if coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 end
 love.timer.sleep(.002)
end
function love.quit()if api then api:quit()end end
function love.errorhandler(message)
 io.stderr:write(tostring(message)..'\n'..debug.traceback()..'\n');return function()return 1 end
end
