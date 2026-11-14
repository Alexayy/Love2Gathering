-- Actual LÖVE/Slab input/rendering with an explicitly synthetic catalog ledger.
-- This does not purge files or download images and does not assert game rules.
local json=require('lib.json');local clock=0;local pending={};local requests={};local operationDue,scanDue
local function clone(t)return json.decode(json.encode(t))end
local fixture={dataDirectory='/mnt/test-volume/.local/share/love2gathering',scanning=false,stats={
 full_cards={count=24,bytes=2400000,mirrorCount=4,mirrorBytes=400000},art_crops={count=12,bytes=1200000,mirrorCount=2,mirrorBytes=200000},export_duplicates={count=6,bytes=600000,estimated=true},
 replays={count=3,bytes=6000000,protectedCount=1},database={bytes=25000000,reusableBytes=5000000,freeBytes=100000000000,compactRequiredBytes=50000000,canCompact=true}}}
local download={state='idle',downloaded=0,bytesDownloaded=0,rateBytesPerSecond=0,reserveBytes=3221225472,progress=0};local nextJob=0
local function route(method,path,body)
 if path=='/storage/status'or path=='/storage/status?refresh=1'then return clone(fixture)end
 if path=='/downloads/status'then return clone(download)end
 if path=='/storage/purge'then
  fixture.operation={id='purge-'..tostring(clock),kind='purge',state='running',categories=clone(body.categories),message='Removing selected local data…'};operationDue=clock+.25
  return clone(fixture)
 end
 if path=='/storage/compact'then fixture.operation={id='compact',kind='compact',state='running',message='Compacting database…'};operationDue=clock+.25;return clone(fixture)end
 if path=='/downloads/scan'then
  nextJob=nextJob+1;download={state='scanning',jobId='scan-'..nextJob,reserveBytes=3221225472,progress=0,downloaded=0,bytesDownloaded=0,scanValid=true,scan={fullSize=body.fullSize,kinds=clone(body.kinds),mirrors=body.mirrors,total=120,cached=20,missing=100,estimatedDownloadBytes=12000000,estimatedStorageBytes=12000000,estimatedMirrorBytes=body.mirrors and 12000000 or 0,estimatedMinBytes=7000000,estimatedMaxBytes=20000000,estimateBasis='Estimate from cached image means; actual sizes vary.',byKind={normal={total=60,cached=10,missing=50,estimatedBytes=7000000},art_crop={total=60,cached=10,missing=50,estimatedBytes=5000000}}}}
  scanDue=clock+.25;return clone(download)
 end
 if path=='/downloads/control'then
  if body.command=='start'or body.command=='resume'then download.state='downloading';download.downloaded=12;download.processed=32;download.progress=.32;download.bytesDownloaded=1400000;download.rateBytesPerSecond=512000
  elseif body.command=='pause'then download.state='paused';download.rateBytesPerSecond=0
  elseif body.command=='cancel'then download.state='cancelled';download.rateBytesPerSecond=0 end
  return clone(download)
 end
 if path:match('^/replays')then return{replays={},total=0}end
 return{}
end
package.preload['app.api']=function()return{escape=function(s)return tostring(s)end,new=function()return{
 request=function(_,service,method,path,body,cb)requests[#requests+1]={service=service,method=method,path=path,body=body and clone(body)};pending[#pending+1]={cb=cb,path=path,method=method,body=body,due=clock+.04}end,
 update=function()
  if operationDue and clock>=operationDue then operationDue=nil;local op=fixture.operation
   if op.kind=='purge'then for _,category in ipairs(op.categories)do fixture.stats[category].count=0;fixture.stats[category].bytes=0;fixture.stats[category].mirrorCount=0;fixture.stats[category].mirrorBytes=0 end;op.result={categories=clone(op.categories)}
   else fixture.stats.database.reusableBytes=0 end;op.state='completed';op.message='Storage maintenance complete'
  end
  if scanDue and clock>=scanDue then scanDue=nil;download.state='ready'end
  for i=#pending,1,-1 do local p=pending[i];if clock>=p.due then table.remove(pending,i);p.cb(route(p.method,p.path,p.body),nil,200)end end
 end,quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Storage=require('app.storage')
local m,r,v,p,runner,Cursor,Region;local wake=0;local mouse={x=2,y=2};local down=false
local buttons,controls,regions,windows,texts={},{},{},{},{};local checks,shots,captures,geometry={},{},{},{}
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('STORAGE UI PASS '..label)end
local function wait(t)wake=clock+(t or .1);coroutine.yield()end
local function ready(fn,label)for _=1,100 do if fn()then return end;wait(.1)end;error('Timed out: '..label)end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy);r:mousemoved(x,y)end
local function click(box)
 assert(box,'Missing actual Storage control');move(box.x+box.w/2,box.y+box.h/2);wait(.05);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1)
 if not r:inputBlocked()and not Storage.press(r,mouse.x/Layout.scale,mouse.y/Layout.scale,1)and S.IsVoidHovered()then r:mousepressed(mouse.x/Layout.scale,mouse.y/Layout.scale,1,1)end
 wait(.05);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);r:mousereleased(mouse.x/Layout.scale,mouse.y/Layout.scale,1);wait(.15)
end
local function visible(box)
 local region=regions['settings-content'];return box and region and box.y>=region.y and box.y+box.h<=region.y+region.h
end
local function scrollTo(label,up)
 for _=1,32 do
  local box=buttons[label]or controls[label];if visible(box)then return box end
  local region=assert(regions['settings-content']);move(region.x+region.w*.88,region.y+region.h*.55);S.OnWheelMoved(0,up and 4 or-4);wait(.08)
 end
 error('Control did not become visible: '..label)
end
local function shot(name)move(2,2);shots[#shots+1]=name;wait(.16)end
local function mode(width,height,scale)
 m.settings.resolution=width..'x'..height;m.settings.windowMode='Windowed';m.settings.uiScale=scale or 1;m.settings.vsync=false;p:apply(true);wait(.2)
 geometry[#geometry+1]={requested={width,height},physical={love.graphics.getDimensions()},logical={Layout.dimensions()},scale=Layout.scale}
end
local function count(path)local n=0;for _,call in ipairs(requests)do if call.path==path then n=n+1 end end;return n end
local function scenario()
 mode(2560,1080,1);m:showStorage();ready(function()return m.storageStatus and m.downloadStatus end,'storage status');wait(.2)
 check(v.settingsTab=='Storage'and m.page=='settings','Storage opens as a real full Settings tab')
 check(texts[fixture.dataDirectory],'Actual backend data-directory text is displayed')
 check(buttons['Apply and save'].y+buttons['Apply and save'].h<select(2,Layout.dimensions()),'Settings save/close footer stays above the viewport bottom')
 shot('overview-2560')
 local purgeBefore=count('/storage/purge');click(scrollTo('Purge duplicate exports'))
 check(m.storagePurgePreview and m.storagePurgePreview.stats.count==6,'Actual Purge click opens a scoped count/size confirmation')
 check(r:inputBlocked()and windows['storage-purge-confirm'],'Purge confirmation blocks background custom input')
 local page=m.page;local nav;for _,hit in ipairs(r.hits)do if hit.tooltip=='Decks'and hit.y==16 then nav=hit end end
 click(assert(nav));check(m.page==page and count('/storage/purge')==purgeBefore,'Clicking behind a purge dialog cannot navigate or delete data')
 shot('purge-confirm-2560');click(assert(buttons['Keep data']));check(not m.storagePurgePreview and count('/storage/purge')==purgeBefore,'Keep data cancels without a destructive request')
 click(scrollTo('Purge duplicate exports'));click(assert(buttons['Purge now']));wait(.4);m:refreshStorage(true);wait(.2)
 check(m.storageStatus.stats.export_duplicates.count==0 and count('/storage/purge')==purgeBefore+1,'Confirm sends one exact duplicate-export purge and adopts completion')
 local image=love.graphics.newImage(love.image.newImageData(4,4));m.art={keep={image=image}}
 click(scrollTo('Purge full-card image cache'));click(assert(buttons['Purge now']));wait(.4);m:refreshStorage(true);wait(.2)
 check(next(m.art)==nil,'Completed full-card purge invalidates previously rendered image caches')
 click(scrollTo('Compact database',true));check(m.storagePurgePreview and m.storagePurgePreview.category=='compact','Compaction has a separate explicit confirmation')
 shot('compact-confirm');click(assert(buttons['Keep data']));click(assert(buttons.Downloads))
 click(scrollTo('Scan download size'));ready(function()return m.downloadStatus and m.downloadStatus.state=='ready'end,'download scan');wait(.1)
 check(download.scan.missing==100 and download.scan.estimatedMirrorBytes==0,'Actual scan choice adopts counts and the cache-only size estimate')
 check(Storage.scanMatches(m),'Ready scan corresponds to the actual selected options')
 shot('download-estimate-2560')
 click(scrollTo('download-full-size'));wait(.1);local large=buttons['Large (672 × 936)']or controls['Large (672 × 936)'];click(assert(large));wait(.1)
 check(not m.storageDownloadOptions.mirrors,'Selecting an image size does not toggle the export checkbox underneath')
 check(not Storage.scanMatches(m)and buttons['Start download'].disabled,'Changing image size disables Start until a fresh scan')
 click(scrollTo('Scan download size',true));ready(function()return m.downloadStatus.state=='ready'and m.downloadStatus.scan.fullSize=='large'end,'large scan')
 click(scrollTo('Start download'));ready(function()return m.downloadStatus.state=='downloading'end,'Start download');wait(.1)
 check(r.storageProgressRect and r.storageProgressRect.y==66 and r.storageProgressRect.y+r.storageProgressRect.h<=82,'Floating download progress fits inside the existing navbar height')
 check(download.bytesDownloaded==1400000 and download.rateBytesPerSecond==512000,'Progress carries actual downloaded bytes and rate from the service')
 shot('download-progress-2560')
 click(scrollTo('Pause download'));ready(function()return m.downloadStatus.state=='paused'end,'Pause download');check(download.downloaded==12,'Pause retains the already downloaded image count')
 m:closeSettings();wait(.1);check(m.page=='decks'and r.storageProgressRect,'Paused download remains discoverable outside Settings')
 click(assert(r.storageProgressRect));wait(.1);check(m.page=='settings'and v.settingsTab=='Storage'and m.storageSection=='downloads','Clicking the navbar ribbon returns to Storage controls')
 click(scrollTo('Resume download'));ready(function()return m.downloadStatus.state=='downloading'end,'Resume download')
 mode(1120,760,.85);wait(.2);shot('settings-1120-scaled')
 check(buttons['Apply and save'].y+buttons['Apply and save'].h<=select(2,Layout.dimensions()),'Scaled Storage keeps its footer reachable')
 m.page='table';m.settingsOpen=false;m.game={gameId='STORAGE-UI-FIXTURE',format='Modern',turn=1,step='PRECOMBAT_MAIN',phase='PRECOMBAT_MAIN',running=true,players={{id='human',name='You',human=true,life=20,battlefield={},hand={},graveyard={},exile={},command={},libraryCount=60},{id='bot',name='Bot',human=false,life=20,battlefield={},hand={},graveyard={},exile={},command={},libraryCount=60}}};m.pollTimer=1e9;wait(.2)
 check(r.storageProgressRect and r.storageProgressRect.h==3 and r.storageProgressRect.y==46 and r.storageProgressRect.y+r.storageProgressRect.h<=49,'In-match progress stays inside the toolbar edge and out of battlefield choices')
 shot('table-progress-1120-scaled');move(r.storageProgressRect.x+20,r.storageProgressRect.y+1.5);wait(.1)
 check(r.hover and r.hover.kind=='download-progress'and r.hover.tooltip:find('downloaded',1,true),'In-match ribbon exposes its actual service progress tooltip')
 click(assert(r.storageProgressRect));wait(.2)
 check(not windows['floating-log'],'Settings popup keeps floating game panels underneath its readable controls')
 check(m.page=='table'and m.settingsOpen and v.settingsTab=='Storage','A running match opens Storage in the existing Settings popup')
 shot('table-storage-popup');m.settingsOpen=false;m.game=nil;m.page='settings';v.settingsTab='Storage';wait(.1)
 click(scrollTo('Cancel download'));ready(function()return m.downloadStatus.state=='cancelled'end,'Cancel download');check(download.downloaded==12,'Cancel keeps cached images and stops further download progress')
 check(not r.storageProgressRect,'Cancelled job removes the navbar loading strip')
 local actualPath=os.getenv('LOVE2GATHERING_STORAGE_STATUS_FIXTURE')
 if actualPath then
  local actualFile=assert(io.open(actualPath,'r'));local actual=json.decode(actualFile:read('*a'));actualFile:close();m.storageStatus=actual;m.storageSection='cleanup';wait(.2)
  for _=1,5 do local region=assert(regions['settings-content']);move(region.x+region.w*.8,region.y+region.h*.5);S.OnWheelMoved(0,8);wait(.06)end
  shot('mounted-usage-readonly-1120')
  check(texts[actual.dataDirectory],'Read-only mounted-data snapshot displays its full actual data folder')
 end
 local f=assert(io.open('/tmp/love2gathering-storage-ui-report.json','w'));f:write(json.encode({passed=true,checks=checks,captures=captures,geometry=geometry,scope='Actual LÖVE/Slab Model/View/Renderer controls with an explicit synthetic asynchronous storage/download ledger; no file deletion, network image download or native gameplay assertion',requests=requests,readOnlyStatusFixture=actualPath}));f:close();print('STORAGE UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.errorhandler(err)io.stderr:write('STORAGE UI FAILED '..tostring(err)..'\n'..debug.traceback()..'\n');return function()return 1 end end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down end
 m=Model.new();Storage.install(Model);m.loaded=true;m.settingsLoaded=true;m.catalogHealth={ready=true,apiVersion=8};m.healthTimer=1e9;m.searchTimer=nil;m.settings.sfxEnabled=false;m.settings.particles=false;m.settings.animations=false
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p.appliedLoaded=true
 local function bounds()local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();return{x=x+dx,y=y+dy,w=w,h=h}end
 for _,name in ipairs({'Button','BeginComboBox','TextSelectable','CheckBox'})do local original=S[name];S[name]=function(id,opts,extra)
  local result=original(id,opts,extra);local b=bounds();b.disabled=type(opts)=='table'and opts.Disabled or type(extra)=='table'and extra.Disabled
  local target=name=='Button'and buttons or controls;target[tostring(id)]=b;return result
 end end
 local original=S.BeginListBox;S.BeginListBox=function(id,opts)local x,y=S.GetCursorPos({Absolute=true});local dx,dy=Region.Transform(nil,0,0);local result=original(id,opts);regions[id]={x=x+dx,y=y+dy,w=opts.W,h=opts.H};if id:match('^settings%-storage%-')then regions['settings-content']=regions[id]end;return result end
 local text=S.Textf;S.Textf=function(value,opts)texts[tostring(value)]=true;return text(value,opts)end
 local window=v.window;function v:window(id,x,y,w,h,title,opts)window(self,id,x,y,w,h,title,opts);windows[id]={x=x,y=y,w=w,h=h}end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<120,'Storage UI acceptance timed out');S.OnMouseMoved(mouse.x,mouse.y,0,0);p:update();m:update(dt);S.Update(dt);r:update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 buttons={};controls={};regions={};windows={};texts={};v:build();r.uiHovered=not S.IsVoidHovered()
end
function love.draw()
 p:beginFrame();r:draw();p:endScene();S.Draw();p:endFrame()
 if#shots>0 then local name=table.remove(shots,1);local path='/tmp/love2gathering-storage-'..name..'.png';captures[#captures+1]=path
  love.graphics.captureScreenshot(function(data)local f=assert(io.open(path,'wb'));f:write(data:encode('png'):getString());f:close()end)
 end
 love.timer.sleep(.034)
end
function love.quit()m.game=nil;m.uiLayoutTimer=nil;m.api:quit();p:quit();S.OnQuit()end
