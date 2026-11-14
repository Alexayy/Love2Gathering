-- Real LÖVE/Slab input against an owned temporary HTTP/SQLite catalog.
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Storage=require('app.storage');local json=require('lib.json')
local m,r,v,p,runner,Cursor,Region;local time,wake=0,0;local mouse={x=1,y=1};local down=false;local held={}
local checks,shots,captures,requests,geometry={},{},{},{},{};local buttons,inputs,regions,windows,texts={},{},{},{},{}
local root=assert(os.getenv('LOVE2GATHERING_LOCATIONS_FIXTURE'))
local destination=root..'/new database with padding';local cache=root..'/separate image cache';local foreign=root..'/foreign'
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('LOCATIONS UI PASS '..label)end
local function wait(t)wake=time+(t or .1);coroutine.yield()end
local function ready(fn,label,seconds)local stop=time+(seconds or 15);while not fn()do assert(time<stop,'Timed out: '..label);wait(.06)end end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy);r:mousemoved(x,y)end
local function click(box)
 assert(box,'Missing real Locations control');move(box.x+box.w/2,box.y+box.h/2);wait(.05);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1)
 local x,y=Layout.toLogical(mouse.x,mouse.y)
 if not r:inputBlocked()and not Storage.press(r,x,y,1)and S.IsVoidHovered()then r:mousepressed(x,y,1,1)end
 wait(.05);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);r:mousereleased(x,y,1);wait(.16)
end
local function visible(box)local region=regions['settings-content'];return box and region and box.y>=region.y and box.y+box.h<=region.y+region.h end
local function scrollTo(label,up)
 for _=1,40 do
  local box=buttons[label]or inputs[label];if visible(box)then return box end
  local region=assert(regions['settings-content'],'Settings scroll region unavailable');move(region.x+region.w*.82,region.y+region.h*.55);S.OnWheelMoved(0,up and 4 or-4);wait(.06)
 end
 error('Control is not reachable: '..label)
end
local function input(label,value)
 click(scrollTo(label,true));held.lctrl=true;S.OnKeyPressed('a','a',false);wait(.04);S.OnKeyReleased('a','a');held.lctrl=false;S.OnTextInput(value);wait(.18)
end
local function mode(w,h)
 m.settings.windowMode='Windowed';m.settings.resolution=w..'x'..h;m.settings.uiScale=1;m.settings.vsync=false;p:apply(true);wait(.25)
 local actualW,actualH=love.graphics.getDimensions();geometry[#geometry+1]={requested={w,h},physical={actualW,actualH},logical={Layout.dimensions()}}
end
local function shot(label)move(2,2);wait(.06);shots[#shots+1]=label;wait(.16)end
local function count(method,path)local n=0;for _,request in ipairs(requests)do if request.method==method and request.path==path then n=n+1 end end;return n end
local function scrollTop()for _=1,5 do local region=assert(regions['settings-content']);move(region.x+region.w*.8,region.y+region.h*.5);S.OnWheelMoved(0,8);wait(.06)end end
local function scenario()
 ready(function()return m.settingsLoaded and m.catalogHealth.ready and m.profileLoaded end,'owned catalog initial data',30)
 check(m.catalogHealth.apiVersion>=9 and m.catalogHealth.storage.dataDirectory==root..'/saves','Actual API9 catalog is fenced to temporary saves')
 m.settings.animations=false;m.settings.particles=false;m.settings.sfxEnabled=false;m.settings.musicEnabled=false
 mode(2560,1080);m:showStorage();ready(function()return buttons.Locations end,'Storage subsections');click(buttons.Locations)
 ready(function()return m.storageLocations and inputs['storage-location-databaseDirectory']end,'Actual active locations');wait(.2)
 check(m.page=='settings'and v.settingsTab=='Storage'and m.storageSection=='locations','Actual Locations tab opens inside Settings Storage')
 check(m.storageLocations.active.databaseFile==root..'/saves/app.sqlite'and not m.storageLocations.active.separateCache,'Active combined database is described honestly before an explicit split')
 local databaseBox=inputs['storage-location-databaseDirectory'];local cacheBox=inputs['storage-location-cacheDirectory']
 check(databaseBox.h>=40 and cacheBox.y>=databaseBox.y+databaseBox.h+14,'Database and cache path inputs retain vertical breathing room')
 check(buttons['Apply and save'].y+buttons['Apply and save'].h<=select(2,Layout.dimensions()),'Settings footer stays fully inside the viewport')
 local browse=assert(buttons['Browse:1']or buttons.Browse);click(browse);wait(.2)
 check(m.storageFolderDialog and m.storageFolderDialog.key=='databaseDirectory'and r:inputBlocked(),'Actual Browse opens the folder picker and blocks custom background input')
 shot('folder-picker-2560')
 local page=m.page;local nav;for _,hit in ipairs(r.hits)do if hit.tooltip=='Decks'and hit.y==16 then nav=hit end end
 click(assert(nav));check(m.page==page and m.storageFolderDialog,'Clicking navigation behind the folder picker cannot leave Settings')
 local cancel=buttons.FileDialogCancel or buttons.Cancel or buttons['Cancel:1'];click(assert(cancel,'Folder picker Cancel control missing'));wait(.2)
 check(not m.storageFolderDialog,'Folder picker Cancel restores the Locations form')
 input('storage-location-databaseDirectory',foreign);input('storage-location-cacheDirectory',cache)
 click(scrollTo('Check locations'));ready(function()return not m.storageLocationActionBusy and m.storageLocationError end,'Foreign database validation refusal')
 check(not m.storageLocationPlan and count('POST','/storage/locations')==0,'Existing foreign app.sqlite is rejected without preparing or overwriting it')
 input('storage-location-databaseDirectory',destination);input('storage-location-cacheDirectory',cache)
 check(m.storageLocationDraft.databaseDirectory==destination and m.storageLocationDraft.cacheDirectory==cache,'Actual UTF-8-safe text input retains two independent absolute paths')
 click(scrollTo('Check locations'));ready(function()return m.storageLocationPlan and m.storageLocationPlan.valid and not m.storageLocationActionBusy end,'Validated destination paths')
 check(m.storageLocationPlan.originalsPreserved and#m.storageLocationPlan.volumes>0,'Real validation reports temporary disk headroom and preserved originals')
 shot('validated-2560')
 click(scrollTo('Prepare and use after restart'));wait(.1)
 check(m.storageLocationConfirm and r:inputBlocked()and windows['storage-location-confirm'],'Explicit Prepare opens its own blocking confirmation')
 local preparedBefore=count('POST','/storage/locations');page=m.page;nav=nil;for _,hit in ipairs(r.hits)do if hit.tooltip=='Decks'and hit.y==16 then nav=hit end end
 click(assert(nav));check(m.page==page and count('POST','/storage/locations')==preparedBefore,'Clicking behind confirmation cannot navigate or start copying')
 shot('confirm-2560');click(assert(buttons['Keep current locations']));check(not m.storageLocationConfirm and count('POST','/storage/locations')==preparedBefore,'Keeping current locations performs no storage mutation')
 click(scrollTo('Prepare and use after restart'));click(assert(buttons['Prepare copies']))
 ready(function()return m.storageLocations.operation and m.storageLocations.operation.state=='preparing'end,'Real preparation started')
 check(m.storageLocationBlocked,'Real background preparation immediately pauses new application work')
 local gamesBefore=count('POST','/session/start');m:startGame();check(count('POST','/session/start')==gamesBefore,'A prepared/preparing store cannot start a native match')
 local settingsBefore=count('PUT','/settings');m:saveSettings();check(count('PUT','/settings')==settingsBefore,'Prepared storage blocks saves before the HTTP worker')
 click(scrollTo('Cancel location change'));ready(function()return not m.storageLocationBlocked and m.storageLocations.operation and m.storageLocations.operation.state=='cancelled'end,'Cancel running preparation',20)
 check(not m.storageLocations.restartRequired,'Actual Cancel stops the background copy and leaves the original store active')
 m:refreshStorageLocations();wait(.2);m:validateStorageLocations();ready(function()return not m.storageLocationActionBusy and m.storageLocationPlan and m.storageLocationPlan.valid end,'Validate again after cancellation')
 mode(1120,760);wait(.2);scrollTop();shot('paths-1120')
 check(buttons['Apply and save'].y+buttons['Apply and save'].h<=select(2,Layout.dimensions()),'Small-window Locations retains a reachable settings footer')
 click(scrollTo('Prepare and use after restart'));wait(.12);shot('confirm-1120')
 local dialog=assert(windows['storage-location-confirm']);local confirm=assert(buttons['Prepare copies'])
 check(confirm.x>=dialog.x and confirm.x+confirm.w<=dialog.x+dialog.w and confirm.y+confirm.h<=dialog.y+dialog.h+20,'Small-window confirmation buttons remain inside their dialog')
 click(confirm);ready(function()return m.storageLocations.restartRequired and m.storageLocations.operation and m.storageLocations.operation.state=='prepared'end,'Real verified copies ready',25)
 check(m.storageLocationBlocked and buttons['Apply and save'].disabled,'Completed copies stay paused until an explicit restart or cancel')
 scrollTo('Cancel location change');shot('prepared-1120')
 check(m.storageLocations.active.databaseDirectory==root..'/saves'and m.storageLocations.configured.databaseDirectory==destination and m.storageLocations.configured.cacheDirectory==cache,'Prepared paths stay separate from the active database until restart')
 click(scrollTo('Cancel location change'));ready(function()return not m.storageLocationBlocked and m.storageLocations.operation and m.storageLocations.operation.state=='cancelled'end,'Cancel prepared change',20)
 check(not m.storageLocations.restartRequired and not r:inputBlocked(),'Cancelling a fully prepared change restores normal input without activating copied data')
 local loaded,settings=false,nil;m:request('catalog','GET','/settings',nil,function(data)loaded=true;settings=data end,true);ready(function()return loaded end,'Original settings after cancellation')
 check(settings and settings.sfxVolume==.45,'Original SQL preferences remain readable after both cancellation paths')
 local warning='Another installation has a prepared location change; finish/cancel it there.'
 local statusError='Activation fixture: destination changed; original storage remains active.'
 local config=assert(io.open(root..'/config/storage-paths.json','w'));config:write(json.encode({version=1,lastError=statusError,pending={id='foreign-ui-fixture',sourceDirectory=root..'/another-store',databaseDirectory=root..'/another-target',cacheDirectory=root..'/another-cache'}}));config:close()
 m:refreshStorageLocations();ready(function()return m.storageLocations.foreignPending end,'Foreign installation pending metadata');scrollTo('Check locations');wait(.15);shot('foreign-warning-1120')
 check(visible(texts[warning])and visible(texts[statusError]),'Foreign installation warning and persisted activation error are visibly explained')
 check(buttons['Check locations'].disabled and inputs['storage-location-databaseDirectory'].readOnly,'Foreign pending metadata disables validation and path editing')
 local validations=count('POST','/storage/locations/validate');local before=m.storageLocationDraft.databaseDirectory
 click(buttons['Check locations']);input('storage-location-databaseDirectory',root..'/must-not-apply')
 check(count('POST','/storage/locations/validate')==validations and m.storageLocationDraft.databaseDirectory==before and not buttons['Cancel location change'],'The foreign store cannot be edited, validated or cancelled through this client')
 local config=assert(io.open(root..'/config/storage-paths.json','w'));config:write(json.encode({version=1}));config:close();m:refreshStorageLocations();ready(function()return not m.storageLocations.foreignPending end,'Foreign fixture cleanup')
 local f=assert(io.open('/tmp/love2gathering-storage-locations-ui-report.json','w'));f:write(json.encode({passed=true,checks=checks,captures=captures,geometry=geometry,requests=requests,scope='Actual LÖVE/Slab typed paths, folder picker, guarded confirmation, real temporary HTTP/SQLite validation/copy/cancel and visible progress. Copy is deliberately delayed only to exercise running cancellation; foreign-pending/error rendering uses an explicit owned bootstrap metadata fixture through the real HTTP service. No user storage, native game or Internet transfer claim.'}));f:close();print('LOCATIONS UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.errorhandler(e)io.stderr:write('LOCATIONS UI DEBUG '..json.encode({buttons=buttons,inputs=inputs,windows=windows,locations=m and m.storageLocations,error=m and m.storageLocationError,dialog=m and m.storageFolderDialog})..'\n');io.stderr:write('LOCATIONS UI FAILED '..tostring(e)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down end
 love.keyboard.isDown=function(...)for i=1,select('#',...)do if held[select(i,...)]then return true end end;return false end
 m=Model.new();r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p
 local request=m.api.request;m.api.request=function(self,service,method,path,body,cb,binary)requests[#requests+1]={service=service,method=method,path=path,body=body and json.decode(json.encode(body))};return request(self,service,method,path,body,cb,binary)end
 local function box()local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();return{x=x+dx,y=y+dy,w=w,h=h}end
 for _,name in ipairs({'Button','Input'})do local original=S[name];S[name]=function(label,options)local result=original(label,options);local b=box();b.disabled=options and options.Disabled;b.readOnly=options and options.ReadOnly
  local target=name=='Input'and inputs or buttons;local count=target[label..':count']or 0;count=count+1;target[label..':count']=count;target[label..':'..count]=b;target[label]=b;return result end end
 local internalButton=require('lib.Slab.Internal.UI.Button');local internalBegin=internalButton.Begin;internalButton.Begin=function(label,options)local result=internalBegin(label,options);if m.storageFolderDialog and(label=='Cancel'or label=='OK')then buttons['FileDialog'..label]=box()end;return result end
 local list=S.BeginListBox;S.BeginListBox=function(id,options)local x,y=S.GetCursorPos({Absolute=true});local dx,dy=Region.Transform(nil,0,0);local result=list(id,options);regions[id]={x=x+dx,y=y+dy,w=options.W,h=options.H};if id:match('^settings%-storage%-')then regions['settings-content']=regions[id]end;return result end
 local window=v.window;function v:window(id,x,y,w,h,title,opts)window(self,id,x,y,w,h,title,opts);windows[id]={x=x,y=y,w=w,h=h}end
 local text=S.Textf;S.Textf=function(value,options)local result=text(value,options);texts[tostring(value)]=box();return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 time=time+dt;assert(time<140,'Locations acceptance timed out');p:update();m:update(dt);S.Update(dt);r:update(dt)
 if time>=wake and coroutine.status(runner)~='dead'then local ok,e=coroutine.resume(runner);assert(ok,e)end
 buttons={};inputs={};regions={};windows={};texts={};v:build();r.uiHovered=not S.IsVoidHovered()
end
function love.draw()
 p:beginFrame();r:draw();p:endScene();S.Draw();p:endFrame()
 if#shots>0 then local name=table.remove(shots,1);local path='/tmp/love2gathering-locations-'..name..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local f=assert(io.open(path,'wb'));f:write(data:encode('png'):getString());f:close()end)end
 love.timer.sleep(.02)
end
function love.quit()m.game=nil;m.uiLayoutTimer=nil;m.api:quit();p:quit();S.OnQuit()end
