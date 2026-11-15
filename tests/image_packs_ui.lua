-- Actual Slab Browse/preview/install controls with a delayed local-service ledger.
-- Archive validation and cache writes are backend acceptance scopes, not fixtures here.
local json=require('lib.json');local clock=0;local pending,requests={},{}
local status={state='idle'};local inspectDue,installStarted;local jobs=0
local root=assert(os.getenv('LOVE2GATHERING_IMAGE_PACK_UI_OUTPUT'))
local archive=root..'/fixtures/starter.zip'
local download={state='downloading',progress=.1,downloaded=12,bytesDownloaded=12000,rateBytesPerSecond=1000}
local function copy(v)return json.decode(json.encode(v))end
local function route(method,path,body)
 if path=='/storage/image-packs/status'then return copy(status)end
 if path=='/storage/image-packs/inspect'then
  jobs=jobs+1;status={state='inspecting',jobId='fixture-'..jobs,path=body.path,images=6,totalBytes=3600000,cached=2,missing=4,complete=false,missingEntries=2,processed=0,progress=0};inspectDue=clock+.35;return copy(status)
 end
 if path=='/storage/image-packs/install'then assert(body.jobId==status.jobId,'Install must use reviewed archive');status.state='importing';status.progress=0;installStarted=clock;return copy(status)end
 if path=='/downloads/control'then assert(body.command=='pause','Only explicit Pause expected');download.state='paused';return copy(download)end
 if path=='/storage/status'or path=='/storage/status?refresh=1'then return{dataDirectory='/tmp/isolated-pack-ui',stats={}}end
 if path=='/downloads/status'then return copy(download)end
 error('Unexpected fixture route: '..path)
end
package.preload['app.api']=function()return{escape=function(s)return tostring(s)end,new=function()return{
 request=function(_,service,method,path,body,callback)requests[#requests+1]={service=service,method=method,path=path,body=body and copy(body)};pending[#pending+1]={method=method,path=path,body=body,callback=callback,due=clock+.03}end,
 update=function()
  if inspectDue and clock>=inspectDue then inspectDue=nil;if status.path:find('broken.zip',1,true)then status.state='error';status.error='Fixture: archive checksum does not match'else status.state='ready';status.progress=1 end end
  if installStarted then status.progress=math.min(1,(clock-installStarted)/2);status.processed=math.floor(status.progress*6);if status.progress==1 then installStarted=nil;status.state='completed';status.installed=4;status.skipped=2 end end
  for i=#pending,1,-1 do local call=pending[i];if clock>=call.due then table.remove(pending,i);call.callback(route(call.method,call.path,call.body),nil,200)end end
 end,quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout')
assert(love.filesystem.load('application-main.lua'))() -- Production Escape, bound below.
local m,r,v,p,runner;local wake=0;local mouse={x=2,y=2};local down=false
local controls,regions,texts,shots,captures,checks={},{},{},{},{},{}
local packCircle=false
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('IMAGE PACK UI PASS '..label)end
local function wait(seconds)wake=clock+(seconds or .08);coroutine.yield()end
local function untilReady(fn,label)for _=1,100 do if fn()then return end;wait(.06)end;error('Timed out: '..label)end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x,y;S.OnMouseMoved(x,y,x-ox,y-oy);r:mousemoved(x,y)end
local function click(box)assert(box,'Missing real control');move(box.x+box.w/2,box.y+box.h/2);wait(.04);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.04);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.12)end
local function scrollTo(id)
 for _=1,80 do local box,region=controls[id],assert(regions['settings-storage-downloads']);if box and box.y>=region.y and box.y+box.h<=region.y+region.h then return box end
  move(region.x+region.w*.85,region.y+region.h*.55);S.OnWheelMoved(0,box and box.y<region.y and 8 or-8);wait(.04)
 end;error('Control did not become visible: '..id)
end
local function shot(name)move(2,2);shots[#shots+1]=name;wait(.12)end
local function count(path)local n=0;for _,call in ipairs(requests)do if call.path==path then n=n+1 end end;return n end
local function scenario()
 wait(.2);m:setImagePackPath(root..'/fixtures/previous.zip');click(scrollTo('Browse'))
 check(m.imagePackFileDialog and r:inputBlocked(),'Native file picker blocks background client interactions')
 untilReady(function()return controls['file:starter.zip']end,'Starter ZIP in native file picker')
 shot('native-pack-browser');love.keypressed('escape','escape',false);wait(.15)
 check(not m.imagePackFileDialog and not m.imagePackCancelRequested and m.page=='settings'and not r:inputBlocked(),'Production Escape closes only the file picker and releases its native modal lock')
 click(scrollTo('Browse'));check(m.imagePackFileDialog,'The Settings Browse button remains interactive after Escape closes the picker')
 untilReady(function()return controls['file:starter.zip']end,'reopened native file picker');click(controls['file:starter.zip']);click(controls['OK'])
 check(not m.imagePackFileDialog and m.imagePackPath==archive,'The real file picker selects a local ZIP path')
 check(count('/storage/image-packs/inspect')==0 and count('/storage/image-packs/install')==0,'Browse neither inspects nor imports automatically')
 click(scrollTo('Inspect pack'));untilReady(function()return m.imagePackStatus.state=='ready'end,'read-only archive preview')
 check(count('/storage/image-packs/install')==0,'Inspect and asynchronous preview perform no install request')
 scrollTo('Install 4 images');shot('review-while-downloading')
 check(controls['Install 4 images'].disabled and download.state=='downloading','Preview stays available during bulk downloading while Install requires Pause')
 check(texts['This pack is incomplete: 2 expected Starter images are absent. Available images can still be installed.'],'The preview clearly identifies incomplete Starter coverage')
 click(controls['Install 4 images']);check(count('/storage/image-packs/install')==0,'Clicking the disabled Install control does not submit a write')
 click(scrollTo('Pause download'));untilReady(function()return m.downloadStatus.state=='paused'end,'paused bulk downloader')
 scrollTo('Install 4 images');shot('review-before-install')
 m.art={ready={image={fixture=true}},missing={state='missing'}}
 click(controls['Install 4 images']);untilReady(function()return m.imagePackStatus.state=='importing'end,'explicit pack installation')
 check(count('/storage/image-packs/install')==1,'Only the explicit reviewed Install action starts the import')
 wait(.12);check(controls['Resume download'].disabled,'Bulk download Resume is disabled while pack images are being installed')
 local packRibbon=false;for _,hit in ipairs(r.hits)do if hit.kind=='download-progress'and hit.tooltip:find('local image pack',1,true)then packRibbon=true end end
 check(r.storageProgressRect and packCircle and packRibbon,'The navbar loading circle and progress strip identify a local pack import')
 shot('pack-import-progress');untilReady(function()return m.imagePackStatus.state=='completed'end,'completed pack import')
 check(m.art.ready and not m.art.missing,'Completion keeps ready art and clears missing-image placeholders')
 shot('pack-installed')
 m.art={};m:setImagePackPath(root..'/fixtures/broken.zip');wait(.15);click(scrollTo('Inspect pack'));untilReady(function()return m.imagePackStatus.state=='error'end,'invalid archive diagnostic')
 scrollTo('text:Fixture: archive checksum does not match');shot('pack-inspection-error');check(count('/storage/image-packs/install')==1 and texts['Fixture: archive checksum does not match'],'Invalid archive diagnostics remain visible without a second install')
 check(m.settings.fontFamily=='Beleren','Pack controls retain the supplied Beleren presentation')
 local file=assert(io.open(root..'/report.json','w'));file:write(json.encode({checks=checks,requests=requests,captures=captures,scope='Actual LÖVE/Slab native ZIP picker and input on delayed explicit pack previews/import/status; no user archive/cache writes; backend validation is separate'}));file:close();love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down end
 m=Model.new();m.page='settings';m.loaded=true;m.settingsLoaded=true;m.profileLoaded=true;m.storageSection='downloads';m.settings.skybox='Off';m.settings.windowMode='Windowed';m.settings.resolution='1440x900';m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.vsync=false
 m.storageStatus={dataDirectory='/tmp/isolated-pack-ui',stats={}};m.downloadStatus=copy(download)
 r=Renderer.new(m);v=View.new(S,m,r);v.settingsTab='Storage';p=Preferences.new(m,S,r);v.preferences=p;p:apply(true);p.appliedLoaded=true
 for index=1,30 do local name=debug.getupvalue(love.keypressed,index);if not name then break end;if name=='model'then debug.setupvalue(love.keypressed,index,m)elseif name=='renderer'then debug.setupvalue(love.keypressed,index,r)elseif name=='view'then debug.setupvalue(love.keypressed,index,v)end end
 local circle=r.assets.loadingCircle;r.assets.loadingCircle=function(self,...)if m.imagePackStatus and m.imagePackStatus.state=='importing'then packCircle=true end;return circle(self,...)end
 local Cursor=require('lib.Slab.Internal.Core.Cursor');local Region=require('lib.Slab.Internal.UI.Region')
 local function bounds()local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();return{x=x+dx,y=y+dy,w=w,h=h}end
 for _,name in ipairs({'Button','Input'})do local original=S[name];S[name]=function(id,options)local result=original(id,options);controls[id]=bounds();controls[id].disabled=options and options.Disabled;return result end end
 local begin=S.BeginListBox;S.BeginListBox=function(id,options)local x,y=S.GetCursorPos({Absolute=true});local dx,dy=Region.Transform(nil,0,0);local result=begin(id,options);regions[id]={x=x+dx,y=y+dy,w=options.W,h=options.H};return result end
 local Button=require('lib.Slab.Internal.UI.Button');local button=Button.Begin;Button.Begin=function(label,options)local result=button(label,options);if label=='OK'or label=='Cancel'then controls[label]=bounds()end;return result end
 local Text=require('lib.Slab.Internal.UI.Text');local text=Text.Begin;Text.Begin=function(label,options)local result=text(label,options);texts[label]=true;if label=='starter.zip'then controls['file:'..label]=bounds()end;return result end
 local textf=S.Textf;S.Textf=function(label,options)local result=textf(label,options);texts[label]=true;controls['text:'..label]=bounds();return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<60,'Image pack UI timed out');m.api:update();m:updateImagePacks(dt);S.Update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,problem=coroutine.resume(runner);assert(ok,problem)end
 controls={};regions={};texts={};v:build()
end
function love.draw()
 love.graphics.clear(.025,.035,.06,1);r.hits={};require('app.storage').drawProgress(r,Layout.dimensions());S.Draw()
 if#shots>0 then local path=root..'/'..table.remove(shots,1)..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local file=assert(io.open(path,'wb'));file:write(data:encode('png'):getString());file:close()end)end
end
function love.quit()if p then p:quit()end;S.OnQuit()end
function love.errorhandler(message)local problem=debug.traceback(tostring(message),2);print(problem);local file=assert(io.open(root..'/failure.txt','w'));file:write(problem);file:close();return function()return 1 end end
