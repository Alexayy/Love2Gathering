-- Image pack workflow/late-response contracts. No archive or user store is read.
package.path='./?.lua;'..package.path
local Packs=require('app.image_packs');local Model={};Model.__index=Model;Packs.install(Model)
local checks=0;local function check(value,label)assert(value,label);checks=checks+1;print('IMAGE PACK PASS '..label)end
local function fixture()
 local m=setmetatable({calls={},page='settings',storageSection='downloads',downloadStatus={state='idle'}},Model)
 function m:request(_,method,path,body,callback)self.calls[#self.calls+1]={method=method,path=path,body=body,callback=callback}end
 function m:showStorage(section)self.page='settings';self.storageSection=section;self.opened=true end
 return m
end
local function reply(m,index,data,err)local call=m.calls[index or#m.calls];call.callback(data,err);return call end
local function preview(m,job)
 m:setImagePackPath('/tmp/starter.zip');m:inspectImagePack();reply(m,nil,{state='ready',jobId=job or'job',path='/tmp/starter.zip',images=4,totalBytes=4000,cached=2,missing=2,complete=true})
end
local m=fixture();m:updateImagePacks(.01);m:updateImagePacks(.01)
check(#m.calls==1 and m.calls[1].method=='GET','Opening the pack section only requests read-only status and deduplicates pending polls')
reply(m,nil,{state='idle'});m:setImagePackPath('/tmp/starter.zip');m:inspectImagePack()
check(#m.calls==2 and m.calls[2].path=='/storage/image-packs/inspect'and m.calls[2].body.path=='/tmp/starter.zip','Inspect sends only the chosen local archive path')
reply(m,nil,{state='inspecting',jobId='job-one',path='/tmp/starter.zip'});m:updateImagePacks(1)
check(m.calls[#m.calls].method=='GET','Asynchronous archive validation polls its status without installing images')
reply(m,nil,{state='ready',jobId='job-one',images=4,totalBytes=4000,cached=2,missing=2,complete=false,missingEntries=1})
check(#m.calls==3,'A ready or incomplete preview never starts installation automatically')
check(m:installImagePack()and m.calls[4].path=='/storage/image-packs/install'and m.calls[4].body.jobId=='job-one','Only an explicit Install action sends the exact reviewed job ID')
check(not m:installImagePack()and#m.calls==4,'Repeated presses cannot duplicate an in-flight install action')
reply(m,nil,{state='importing',jobId='job-one',images=4,processed=1,progress=.25})
m.art={ready={image={retained=true}},missing={state='missing'},pending={pending=true}};m.profileImages={failed={state='error'}};m.downloadStatus.scan={};m:updateImagePacks(1)
reply(m,nil,{state='completed',jobId='job-one',images=4,installed=2,skipped=2,progress=1})
check(m.art.ready and not m.art.missing and not m.art.pending and not m.profileImages.failed,'Completed import preserves ready images and invalidates missing or stale pending lookups')
check(m.storageUsageStale and m.downloadStatus.scanValid==false,'New images invalidate a stale bulk estimate and request fresh storage usage')
m.art.after={state='missing'};m:refreshImagePacks();reply(m,nil,{state='completed',jobId='job-one',installed=2})
check(m.art.after,'Repeated completed polls do not repeatedly invalidate the image caches')

local edited=fixture();edited:setImagePackPath('/tmp/first.zip');edited:inspectImagePack();edited:setImagePackPath('/tmp/second.zip')
reply(edited,nil,{state='ready',jobId='old-preview',path='/tmp/first.zip',missing=2})
check(edited.imagePackPath=='/tmp/second.zip'and not edited:installImagePack(),'A late preview cannot replace an edited path or authorize the old archive')
local stale=fixture();stale:refreshImagePacks();stale:setImagePackPath('/tmp/new.zip');stale:inspectImagePack()
reply(stale,1,{state='ready',jobId='stale-status',path='/tmp/old.zip',missing=2});reply(stale,2,{state='ready',jobId='fresh',path='/tmp/new.zip',missing=1})
check(stale:installImagePack()and stale.calls[#stale.calls].body.jobId=='fresh','An old status response cannot revive a preview before the latest inspection')

local blocked=fixture();preview(blocked);blocked.downloadStatus.state='downloading';local before=#blocked.calls
check(not blocked:installImagePack()and#blocked.calls==before,'Active bulk downloading blocks only installation until paused')
check(blocked:browseImagePack()and blocked:inspectImagePack()and#blocked.calls==before+1,'Read-only Browse and Inspect remain available during a bulk download')
blocked.downloadStatus.state='idle';blocked.storageLocationBlocked=true
check(not blocked:installImagePack(),'A prepared storage location change also blocks archive installation')

local dropped=fixture();check(not dropped:dropImagePack({getFilename=function()return'/tmp/deck.txt'end})and#dropped.calls==0,'Ordinary deck files remain available to the existing deck importer')
check(dropped:dropImagePack({getFilename=function()return'/tmp/starter.ZIP'end})and dropped.opened and#dropped.calls==1 and dropped.calls[1].path:find('/inspect',1,true),'Dropping a ZIP opens the pack page and inspects only, without importing')
local browse=fixture();browse:setImagePackPath('/tmp/old.zip');browse:browseImagePack()
Packs.modal({m=browse,S={FileDialog=function(options)check(options.Type=='openfile'and options.AllowMultiSelect==false,'Browse uses the native single-file dialog with a ZIP filter');return{Button='OK',Files={'/tmp/selected.zip'}}end}})
check(browse.imagePackPath=='/tmp/selected.zip'and not browse.imagePackFileDialog and#browse.calls==0,'Choosing a ZIP updates the path without starting inspection or installation')
browse:browseImagePack();Packs.modal({m=browse,S={FileDialog=function()return{Button='Cancel'}end}})
check(browse.imagePackPath=='/tmp/selected.zip'and not browse.imagePackFileDialog,'Cancelling Browse preserves the previously selected path')
local cached=fixture();preview(cached);cached.imagePackStatus.missing=0;before=#cached.calls
check(not cached:installImagePack()and#cached.calls==before,'A fully cached archive needs no install write')
local failure=fixture();failure:setImagePackPath('/tmp/bad.zip');failure:inspectImagePack();reply(failure,nil,nil,'Fixture: invalid manifest')
check(failure.imagePackError:find('invalid manifest',1,true)and not failure:installImagePack(),'An inspection error stays visible and cannot authorize installation')
print('Image pack model checks: '..checks..' passed')
