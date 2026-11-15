-- Catalog/image concurrency and epoch fences; actual worker sockets tested separately.
package.path='./?.lua;'..package.path
local channels={};local clock=0
love={timer={getTime=function()clock=clock+.001;return clock end},thread={}}
function love.thread.getChannel(name)
 if not channels[name]then local c={};function c:push(v)self[#self+1]=v end;function c:pop()return table.remove(self,1)end;function c:clear()for i=#self,1,-1 do self[i]=nil end end;channels[name]=c end
 return channels[name]
end
function love.thread.newThread()return{start=function()end,isRunning=function()return false end}end
local API=require('app.api');local api=API.new();local checks=0
local function check(ok,label)assert(ok,label);checks=checks+1;print('API LANES PASS '..label)end
local scan=api:request('catalog','GET','/storage/status',nil,function()end)
local settings=api:request('catalog','GET','/settings',nil,function()end)
local search=api:request('catalog','GET','/cards?q=Angel',nil,function()end)
check(api.pendingDetails[scan].worker=='catalogMaintenance'and api.pendingDetails[settings].worker=='catalogFast'and api.pendingDetails[search].worker=='catalogRead1','Slow maintenance cannot queue saved preferences or search behind its socket')
local art={};for i=1,5 do art[i]=api:request('art','GET','/art/'..i,nil,function()end,true)end
check(api.pendingDetails[art[1]].worker=='art'and api.pendingDetails[art[2]].worker=='art2'and api.pendingDetails[art[5]].queued and api:imageDiagnostics().visibleInFlight==2,'Visible artwork has two bounded independent lanes and a central pending queue')
local first,second
local a=api:request('catalog','GET','/cards/same',nil,function(v)first=v;v.name='modified by first consumer'end)
local b=api:request('catalog','GET','/cards/same',nil,function(v)second=v end)
check(a==b,'Identical concurrent metadata reads share one request')
local lane=api.pendingDetails[a].worker;api.workers[lane].output:push({id=a,code=200,body={name='Original'}});api:update()
check(first.name=='modified by first consumer'and second.name=='Original','Coalesced metadata consumers receive detached tables')
local old=api:request('catalog','GET','/decks',nil,function()end)
api:request('catalog','PUT','/decks/edit',{name='changed'},function()end)
local new=api:request('catalog','GET','/decks',nil,function()end)
check(old~=new,'A mutation fences reads that began before the write')
local fetch=api:request('catalog','POST','/art/download',{printingId='one'},function()end)
check(api.pendingDetails[fetch].worker=='catalogFetch','Explicit network image acquisition does not occupy preferences or save lanes')
local write=api:request('catalog','PUT','/settings',{theme='Midnight'},function()end)
check(api.pendingDetails[write].worker=='catalog','SQLite saves preserve their ordered lane')
local online=api:request('art','GET','/art/online?network=1',nil,function()end,true)
local value;for _,item in ipairs(api.artQueue)do if item.id==online then value=item end end
check(value.id==online and value.timeout==20,'Enabled online artwork has room for the remote read and bounded cache write')
local ordered=API.new();local firstRefresh,secondRefresh
local function refresh(set) return function()local id=ordered:request('catalog','GET','/decks',nil,function()end);set(id)end end
local saveA=ordered:request('catalog','POST','/decks',{name='A'},refresh(function(id)firstRefresh=id end))
local saveB=ordered:request('catalog','POST','/decks',{name='B'},refresh(function(id)secondRefresh=id end))
ordered.workers.catalog.output:push({id=saveA,code=200,body={name='A'}});ordered:update()
check(ordered.pendingDetails[firstRefresh].worker=='catalog','A save callback refresh waits behind another queued write of the same resource')
local independent=ordered:request('catalog','GET','/profile',nil,function()end)
check(ordered.pendingDetails[independent].worker=='catalogFast','Pending deck writes do not delay the independent saved profile')
ordered.workers.catalog.output:push({id=saveB,code=200,body={name='B'}});ordered:update()
check(secondRefresh==firstRefresh,'Coalesced post-save refreshes share only a request already ordered after both writes')
print('API lane checks: '..checks)
