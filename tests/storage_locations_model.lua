package.path='./?.lua;./?/init.lua;'..package.path
local Model={};Model.__index=Model;require('app.storage_locations').install(Model)
local pending,checks={},0
local m=setmetatable({request=function(_,service,method,path,body,callback)pending[#pending+1]={service=service,method=method,path=path,body=body,callback=callback}end,toast=function(self,msg)self.lastToast=msg end},Model)
local function check(ok,label)assert(ok,label);checks=checks+1;print('LOCATIONS MODEL PASS '..label)end
m:refreshStorageLocations();pending[#pending].callback({active={databaseDirectory='/tmp/saves',cacheDirectory='/tmp/cache'},restartRequired=false})
check(m.storageLocationDraft.cacheDirectory=='/tmp/cache','Resolved image location is independent of saves')
m:setStorageLocation('databaseDirectory','/tmp/new-saves');m:validateStorageLocations();local stale=pending[#pending]
m:setStorageLocation('cacheDirectory','/tmp/new-cache');stale.callback({valid=true,databaseDirectory='/tmp/stale',cacheDirectory='/tmp/stale'})
check(m.storageLocationPlan==nil,'Editing a path fences older validation')
check(not m:prepareStorageLocations(),'Preparing without an explicit confirmed plan is rejected')
m:validateStorageLocations();local call=pending[#pending]
check(call.path=='/storage/locations/validate'and call.body.cacheDirectory=='/tmp/new-cache','Validation sends both explicit directories without writing configuration')
call.callback({valid=true,databaseDirectory='/tmp/new-saves',cacheDirectory='/tmp/new-cache'})
check(m:previewStorageLocations()and m.storageLocationConfirm,'Validating only opens a reviewable confirmation')
local before=#pending;m.storageLocationConfirm=nil
check(#pending==before and not m.storageLocationBlocked,'Dismissing confirmation keeps the active installation writable')
m.game={running=true};check(not m:previewStorageLocations()and m.lastToast,'A running match blocks storage preparation')
m.game=nil;m:refreshStorageLocations();local lateStatus=pending[#pending]
assert(m:previewStorageLocations());assert(m:prepareStorageLocations())
lateStatus.callback({active={databaseDirectory='/tmp/saves',cacheDirectory='/tmp/cache'},restartRequired=false})
check(m.storageLocationBlocked,'An older status cannot unpause a new preparation request')
call=pending[#pending];check(call.method=='POST'and call.path=='/storage/locations'and m.storageLocationBlocked,'Confirmed preparation pauses new matches immediately')
call.callback({active={databaseDirectory='/tmp/saves',cacheDirectory='/tmp/cache'},operation={state='preparing'},restartRequired=false})
check(m.storageLocationBlocked,'Background preparation keeps new matches paused')
m:refreshStorageLocations();pending[#pending].callback({active={databaseDirectory='/tmp/saves',cacheDirectory='/tmp/cache'},configured={databaseDirectory='/tmp/new-saves',cacheDirectory='/tmp/new-cache'},operation={state='prepared'},restartRequired=true})
check(m.storageLocationBlocked,'Prepared copies await restart instead of adopting paths during a live process')
m:cancelStorageLocations();call=pending[#pending]
check(call.path=='/storage/locations/cancel'and call.body and next(call.body)==nil,'Cancellation uses the explicit backend control')
call.callback({active={databaseDirectory='/tmp/saves',cacheDirectory='/tmp/cache'},operation={state='cancelled'},restartRequired=false})
check(not m.storageLocationBlocked,'Confirmed cancellation restores normal use of original storage')
print('Storage locations model checks: '..checks..' passed')
