-- Transport and presentation-state contracts. No files are deleted or fetched.
package.path='./?.lua;'..package.path
local calls={}
package.preload['app.api']=function()return{escape=function(s)return tostring(s)end,new=function()return{request=function(_,service,method,path,body,cb)calls[#calls+1]={service=service,method=method,path=path,body=body,callback=cb}end,update=function()end,quit=function()end}end}end
love={math={random=function()return 1 end}}
local Model=require('app.model');local Storage=require('app.storage');Storage.install(Model)
local json=require('lib.json')
local checks=0
local function check(ok,label)assert(ok,label);checks=checks+1;print('STORAGE MODEL PASS '..label)end
local function last(path)for i=#calls,1,-1 do if calls[i].path==path then return calls[i]end end;error('Missing request '..path)end
local function respond(call,data,code)call.callback(data,nil,code or 200)end
local function stats()
 return{dataDirectory='/tmp/owned-storage',stats={full_cards={count=10,bytes=1000,mirrorCount=2,mirrorBytes=200},art_crops={count=5,bytes=500},export_duplicates={count=2,bytes=200,estimated=true},replays={count=3,bytes=900,protectedCount=1},database={bytes=4000,reusableBytes=1000,freeBytes=9000,canCompact=true,compactRequiredBytes=8000}},scanning=false}
end
local m=Model.new();m:refreshStorage(true);local old=last('/storage/status');m:refreshStorage(true);local current=last('/storage/status')
respond(current,stats());respond(old,{dataDirectory='/wrong'})
check(m.storageStatus.dataDirectory=='/tmp/owned-storage','A late storage response cannot overwrite the newest data-directory snapshot')
check(not m:previewStoragePurge('decks'),'Only explicit cache/replay categories can enter a destructive confirmation')
check(m:previewStoragePurge('full_cards')and m.storagePurgePreview.stats.count==10,'Purge previews capture the actual category count without deleting anything')
local initial=#calls;m.storagePurgePreview=nil;check(#calls==initial,'Cancelling a purge issues no destructive request')
m:previewStoragePurge('full_cards');m.art={ready={image='ready'},pending={pending=true}};m.profileImages={ready={image='portrait'}};m.galleryArt={ready={image='crop'}};m.artPending=2
check(m:confirmStoragePurge(),'An explicit confirmation submits one purge')
local purge=last('/storage/purge');check(purge.method=='POST'and purge.body.categories[1]=='full_cards','Purge sends its exact category through the local catalog')
check(m.art.ready.image=='ready','Starting asynchronous deletion does not prematurely hide cached images')
respond(purge,{operation={id='delete-one',kind='purge',state='running',categories={'full_cards'}}})
local done=stats();done.operation={id='delete-one',kind='purge',state='completed',result={categories={'full_cards'}}};respond(last('/storage/status'),done)
check(next(m.art)==nil and next(m.profileImages)==nil and next(m.galleryArt)==nil and m.artPending==2,'Successful image deletion invalidates GPU caches without corrupting in-flight request counts')
local cached={image='keep'};m.art={ready=cached};m:previewStoragePurge('export_duplicates');m:confirmStoragePurge();respond(last('/storage/purge'),{operation={id='exports',kind='purge',state='running',categories={'export_duplicates'}}})
done=stats();done.operation={id='exports',kind='purge',state='completed',result={categories={'export_duplicates'}}};respond(last('/storage/status'),done)
check(m.art.ready==cached,'Deleting duplicate exports retains the app image cache')
m:previewStoragePurge('full_cards');m:confirmStoragePurge();respond(last('/storage/purge'),{operation={id='tiny-fast-purge',kind='purge',state='completed',result={categories={'full_cards'}}}})
check(next(m.art)==nil,'A purge completed before its POST response still invalidates the deleted cache')
respond(last('/storage/status'),stats())
m.page='settings';m.replay={id='finished'};local closed=false;function m:closeReplay()closed=true;self.replay=nil;self.page='replays'end
m:previewStoragePurge('replays');m:confirmStoragePurge();respond(last('/storage/purge'),{operation={id='replays',kind='purge',state='running',categories={'replays'}}})
done=stats();done.operation={id='replays',kind='purge',state='completed',result={categories={'replays'}}};respond(last('/storage/status'),done)
check(closed and m.page=='settings'and last('/replays?limit=100&offset=0')and last('/history?limit=12&offset=0'),'Deleting timelines refreshes replay availability in history and closes stale playback without changing the Settings page')
m.downloadStatus={state='downloading'};check(not m:previewStoragePurge('art_crops'),'An active download blocks conflicting maintenance in the UI')
m.downloadStatus={state='idle'};check(m:compactStorage(),'Database compaction requires its own confirmation')
m:confirmStorageCompact();check(last('/storage/compact').body and last('/storage/compact').method=='POST','Compaction is an explicit separate action')
respond(last('/storage/compact'),{operation={id='compact',kind='compact',state='completed'}});respond(last('/storage/status'),stats())
m.storagePurgePreview=nil;m:scanImageLibrary();local scan=last('/downloads/scan')
check(scan.body.fullSize=='normal'and scan.body.kinds[1]=='normal'and scan.body.kinds[2]=='art_crop'and scan.body.mirrors==false,'The scan requests both image kinds with space-saving app-cache-only defaults')
local scanResult={fullSize='normal',kinds={'normal','art_crop'},mirrors=false,total=20,cached=5,missing=15,estimatedDownloadBytes=15000,estimatedStorageBytes=15000,estimatedMirrorBytes=0}
respond(scan,{state='ready',jobId='one',scan=scanResult,downloaded=0});check(Storage.scanMatches(m),'An explicit ready scan matches the chosen image options')
m.storageDownloadOptions.fullSize='large';check(not m:imageDownloadCommand('start'),'Changing image options requires a new scan before Start')
m.storageDownloadOptions.fullSize='normal';m:refreshDownloadStatus(true);old=last('/downloads/status');m:imageDownloadCommand('start');local start=last('/downloads/control')
respond(old,{state='idle'});check(m.downloadStatus.state=='ready'and m.downloadActionBusy,'A stale status cannot replace a pending Start action')
respond(start,{state='downloading',jobId='one',scan=scanResult,downloaded=0});check(m.downloadStatus.state=='downloading','Start adopts the actual managed job state')
m.art={missing={state='missing'},ready=cached,pending={pending=true}};m:refreshDownloadStatus(true);respond(last('/downloads/status'),{state='downloading',jobId='one',scan=scanResult,downloaded=1})
check(not m.art.missing and m.art.ready==cached and m.art.pending.pending,'New downloads retry only missing images, preserving ready and pending assets')
m.art={missing={state='missing'}};m:refreshDownloadStatus(true);respond(last('/downloads/status'),{state='downloading',jobId='one',scan=scanResult,downloaded=1,imagesAdded=2})
check(not m.art.missing,'Local mirror imports retry missing images without requiring another HTTP transfer')
m:imageDownloadCommand('pause');local pause=last('/downloads/control');local n=#calls;check(not m:imageDownloadCommand('pause')and#calls==n,'A pending command cannot be sent twice')
respond(pause,{state='paused',jobId='one',scan=scanResult,downloaded=1});m:imageDownloadCommand('resume');check(last('/downloads/control').body.command=='resume','A paused job resumes by explicit action')
respond(last('/downloads/control'),{state='downloading',jobId='one',scan=scanResult,downloaded=1});m:imageDownloadCommand('cancel');check(last('/downloads/control').body.command=='cancel','Cancel stops the job while its already cached images remain')
respond(last('/downloads/control'),{state='cancelled',jobId='one',scan=scanResult,downloaded=1})
m.downloadStatus={state='paused',jobId='one',scan=scanResult,scanValid=false};initial=#calls
check(not m:imageDownloadCommand('resume')and not Storage.scanMatches(m)and#calls==initial,'A cache purge invalidates the old plan and requires a fresh scan before Resume')
m.downloadStatus={state='paused',jobId='partial',scanComplete=false,scanValid=false,canResume=true};check(m:imageDownloadCommand('resume'),'A paused incomplete scan can resume the backend local scan without a valid finished download plan')
respond(last('/downloads/control'),{state='scanning',jobId='partial',scanComplete=false,scanValid=false,canResume=false})
local fresh=Model.new();fresh.storageDownloadOptions={fullSize='normal',fullCards=true,artCrops=true,mirrors=false};fresh.catalogHealth={ready=true,apiVersion=8};fresh:updateStorage(.1);respond(last('/downloads/status'),{state='paused',jobId='persisted',scan={fullSize='large',kinds={'normal'},mirrors=true},downloaded=4})
check(fresh.downloadStatus.jobId=='persisted'and fresh.storageDownloadOptions.fullSize=='large'and fresh.storageDownloadOptions.mirrors,'A fresh frontend rehydrates a persisted job and its actual options')
fresh.catalogHealth={error='Storage maintenance is running'};calls={};fresh:updateStorage(20);check(#calls>0,'Progress polling continues after acknowledged API support despite transient health errors')
local legacy=Model.new();legacy.catalogHealth={ready=true,apiVersion=7};calls={};legacy:updateStorage(20);check(#calls==0,'Older catalogs do not receive unsupported storage endpoints')
local idle=Model.new();idle:refreshDownloadStatus();respond(last('/downloads/status'),{state='idle',scan=json.null});idle:scanImageLibrary()
check(#last('/downloads/scan').body.kinds==2,'A JSON-null idle plan retains both recommended image types by default')
check(Storage.bytes(0)=='0 B'and Storage.bytes(1024)=='1.00 KiB','Byte summaries retain explicit units and zero values')
local importing=Model.new();importing.imagePackStatus={state='importing'};importing.downloadStatus={state='paused',canResume=true};local before=#calls
check(Storage.maintenanceBusy(importing)and not importing:imageDownloadCommand('resume')and#calls==before,'An active pack import blocks conflicting bulk resume and maintenance before sending HTTP')
print('Storage model checks: '..checks..' passed')
