-- Real LÖVE textures, production byte eviction and Slab settings dispatch.
-- HTTP replies are explicit fixtures; no user cache, settings or engine is used.
local Artwork=require('app.artwork');local API=require('app.api');local Model=require('app.model')
local S=require('lib.Slab');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local json=require('lib.json')
local output=assert(os.getenv('LOVE2GATHERING_ARTWORK_BUDGET_OUTPUT'))
local MiB=1024*1024
local checks,metrics,requests,captures={},{},{},{}
local m,r,v,p,runner;local clock,wake=0,0;local mouse={x=2,y=2};local down=false
local controls,regions,shots={},{},{}
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('ARTWORK BUDGET PASS '..label)end
local function wait(seconds)wake=clock+(seconds or .06);coroutine.yield()end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x,y;S.OnMouseMoved(x,y,x-ox,y-oy)end
local function click(box)
 assert(box,'Missing real Slab control');move(box.x+box.w/2,box.y+box.h/2);wait(.05);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.05);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.1)
end
local function shot(name)shots[#shots+1]=name;wait(.12)end
local function scrollTo(id)
 for _=1,32 do
  local box,region=controls[id],assert(regions['settings-content'])
  if box and box.y>=region.y and box.y+box.h<=region.y+region.h then return box end
  move(region.x+region.w*.8,region.y+region.h*.6);S.OnWheelMoved(0,box and box.y<region.y and 4 or-4);wait(.1)
 end
 error('Control did not become visible: '..id)
end
local function fixture()
 local value={settings={artworkMemoryMiB=128,localArtworkOnly=false,showCardArt=true},art={},calls={}}
 value.api={request=function(_,service,method,path,body,callback,mode)value.calls[#value.calls+1]={path=path,callback=callback,mode=mode};requests[#requests+1]={service=service,method=method,path=path,mode=mode}end}
 return value
end
local function put(value,field,key,data)
 Artwork.image(value,field,field..'Pending',key,'/fixture/'..key..'?network=0',6)
 local call=value.calls[#value.calls];local callback=call.callback;call.callback=nil;callback(nil,nil,200,data)
end
local function channel()local q={};return{push=function(_,x)q[#q+1]=x end,pop=function()return table.remove(q,1)end}end
local function nativeChecks()
 local data=love.image.newImageData(2048,2048);local value=fixture()
 for i=1,8 do local field=i<=3 and'art'or i<=6 and'galleryArt'or'profileImages';put(value,field,'large-'..i,data)end
 local info=Artwork.cacheInfo(value)
 check(info.bytes==128*MiB and info.images==8,'Byte accounting uses real decoded dimensions across card, gallery and profile caches')
 value.profileImages.shared={image=value.art['large-1'].image,order=9}
 check(Artwork.cacheInfo(value).bytes==128*MiB and Artwork.cacheInfo(value).images==8,'A shared real GPU Image is charged once across multiple cache entries')
 local before=#value.calls;local image=Artwork.image(value,'art','artPending','large-1','/fixture/large-1?network=0',6)
 check(image and#value.calls==before,'An image cache hit reuses its texture without transport or decoding')
 put(value,'profileImages','large-9',data)
 check(value.art['large-1']and not value.art['large-2']and value.galleryArt['large-4']and Artwork.cacheInfo(value).bytes==128*MiB,'One shared byte LRU evicts the least recently used texture across all image views')
 value.settings.artworkMemoryMiB=256;put(value,'galleryArt','large-10',data)
 check(Artwork.cacheInfo(value).bytes==144*MiB,'A larger selected budget retains more decoded images')
 value.settings.artworkMemoryMiB=128;Artwork.trim(value)
 check(Artwork.cacheInfo(value).bytes<=128*MiB,'Reducing the budget evicts old textures immediately without changing disk images')
 check(data:getWidth()==2048,'Artwork never releases the API-owned decoded buffer during a consumer callback')
 data:release();data=nil;value=nil;image=nil;collectgarbage('collect')

 local wide=fixture();local precision=love.image.newImageData(32,32,'rgba16');put(wide,'art','precision',precision)
 check(Artwork.cacheInfo(wide).bytes==32*32*8,'Higher-precision cached PNG textures count their actual eight bytes per pixel')
 precision:release();precision=nil;wide=nil;collectgarbage('collect')

 local rotating=fixture();local small=love.image.newImageData(512,512);local baseline=love.graphics.getStats().texturememory
 metrics.rotation={};local maximum=baseline
 for i=1,1000 do
  put(rotating,({'art','galleryArt','profileImages'})[(i-1)%3+1],'rotate-'..i,small)
  if i%100==0 then local info=Artwork.cacheInfo(rotating);local native=love.graphics.getStats().texturememory;maximum=math.max(maximum,native);metrics.rotation[#metrics.rotation+1]={loaded=i,decodedBytes=info.bytes,nativeTextureBytes=native,images=info.images};check(info.bytes<=128*MiB,'Rotating '..i..' actual images stays inside the shared decoded budget');wait(.001)end
 end
 collectgarbage('collect');local retained=love.graphics.getStats().texturememory-baseline
 check(retained<=130*MiB,'Native texture allocation remains bounded after 1,000 rotating images and collection')
 check(maximum-baseline<=160*MiB,'Incremental collection bounds transient native texture growth while rotating the image working set')
 metrics.rotationPeakTextureBytes=maximum-baseline;metrics.rotationRetainedTextureBytes=retained
 small:release();small=nil;rotating=nil;collectgarbage('collect')

 local queue=channel();local api=setmetatable({nextId=0,pending={},pendingService={},pendingDetails={},workers={},inflight={},waiters={},readEpoch=0,routes={},routeGeneration=0,catalogPort=17999},API)
 for _,name in ipairs({'art','art2','art3','art4'})do api.workers[name]={input=channel(),output=queue}end
 local coalesced={settings={artworkMemoryMiB=128},api=api}
 Artwork.image(coalesced,'art','artPending','one','/art/exact?network=0',6)
 Artwork.image(coalesced,'profileImages','profileArtPending','two','/art/exact?network=0',4)
 check(api.nextId==1 and#api.waiters[1]==1,'Identical decoded-image requests coalesce while retaining separate consumer caches')
 local decoded=love.image.newImageData(love.filesystem.newFileData(assert(love.filesystem.read('assets/card-backs/classic-magic.jpg')),'fixture.jpg'))
 queue:push({id=1,code=200,imageData=decoded,timings={}});api:update()
 check(coalesced.art.one.image and coalesced.profileImages.two.image,'Both real texture consumers finish before the coalesced ImageData is released')
 check(coalesced.art.one.image==coalesced.profileImages.two.image and Artwork.cacheInfo(coalesced).images==1 and coalesced.artworkUploadMetrics.count==1,'Coalesced consumers share one actual GPU upload and decoded cache charge')
 check(not pcall(decoded.getWidth,decoded),'The API releases its decoded ImageData once all consumers finish')
 coalesced=nil;decoded=nil;collectgarbage('collect')

 local burst=setmetatable({nextId=0,pending={},pendingService={},pendingDetails={},workers={},inflight={},waiters={},readEpoch=0,routes={},routeGeneration=0,catalogPort=17999},API)
 for _,name in ipairs({'art','art2','artSelected'})do burst.workers[name]={input=channel(),output=channel()}end
 local consumers={settings={artworkMemoryMiB=128},api=burst};local buffers={}
 for index=1,3 do
  local selected=index==3
  Artwork.image(consumers,'art','artPending','burst-'..index,'/art/burst-'..index..'?network='..(selected and'1'or'0'),6,nil,not selected,selected and{priority='selected',selectionToken='current'}or nil)
  local id=burst.nextId;buffers[index]=love.image.newImageData(1024,1024)
  burst.workers[burst.pendingDetails[id].worker].output:push({id=id,code=200,imageData=buffers[index],timings={httpSeconds=0,decodeSeconds=0}})
 end
 burst:update()
 check(consumers.art['burst-3'].image and consumers.art['burst-1'].image and not consumers.art['burst-2'].image,'Actual GPU uploads prioritize the selected image and defer the third four-MiB completion')
 check(consumers.artworkUploadMetrics.count==2 and burst:imageDiagnostics().lastFrameBytes==8*MiB,'A real completion burst uploads at most two images and eight MiB in one update')
 check(not pcall(buffers[3].getWidth,buffers[3])and pcall(buffers[2].getWidth,buffers[2]),'Delivered pixels are released while the bounded deferred buffer remains alive')
 burst:update()
 check(consumers.art['burst-2'].image and consumers.artworkUploadMetrics.count==3 and not pcall(buffers[2].getWidth,buffers[2]),'The next update uploads and releases the deferred real image')
 consumers=nil;buffers=nil;burst=nil;collectgarbage('collect')

 local policy=fixture();policy.cardData=function(_,c)return c end
 local card={id='oracle-fixture',printing_id='exact-fixture',requested_face=1,image_uris={}}
 Artwork.get(policy,card,true);local call=policy.calls[#policy.calls]
 check(call.mode=='image'and call.path:find('network=1',1,true)and call.path:find('printing=exact-fixture',1,true),'On-demand mode requests threaded decoding of only the requested exact printing and face')
 call.callback(assert(love.filesystem.read('assets/card-backs/classic-magic.jpg')),nil,200)
 before=#policy.calls;check(Artwork.get(policy,card,true)~=nil and#policy.calls==before,'The acquired card is reused from the decoded cache on subsequent views')
 policy.settings.localArtworkOnly=true;Artwork.get(policy,{id='missing',printing_id='missing',image_uris={}},true)
 check(policy.calls[#policy.calls].path:find('network=0',1,true),'Cache-only mode forbids remote acquisition for missing cards')
end
local function scenario()
 wait(.15);nativeChecks();wait(.15)
 v.settingsTab='Storage';m.storageSection='downloads';wait(.2)
 check(controls['setting-artwork-source'],'The source selector is visible beside Storage download controls')
 click(controls['setting-artwork-source']);click(controls['Download as needed'])
 check(m.settings.localArtworkOnly==false,'Actual Slab selection enables persistent on-demand image behavior')
 shot('storage-on-demand')
 click(controls['setting-artwork-source']);click(controls['Cache only'])
 check(m.settings.localArtworkOnly==true,'Actual Slab selection restores strict cache-only behavior')
 shot('storage-cache-only')
 v.settingsTab='Graphics';wait(.15)
 scrollTo('setting-artworkMemoryMiB')
 check(controls['setting-artworkMemoryMiB'],'Graphics exposes the decoded-image budget control')
 shot('graphics-before-memory')
 click(controls['setting-artworkMemoryMiB']);click(controls['512'])
 check(m.settings.artworkMemoryMiB==512,'Actual Slab memory selection preserves a numeric validated setting')
 scrollTo('setting-frameLimit')
 shot('graphics-image-memory')
 click(controls['Apply and save'])
 check(m.stored.artworkMemoryMiB==512 and m.stored.localArtworkOnly==true,'Apply and save persists the selected image source and memory budget together')
 check(m.settings.fontFamily=='Beleren'and m.settings.titleFontFamily=='Beleren','Image preferences preserve the configured Beleren font behavior')
 wait(.1)
 local report=assert(io.open(output..'/report.json','w'));report:write(json.encode({checks=checks,metrics=metrics,requests=requests,captures=captures,scope='Actual LÖVE image allocations/byte LRU/coalesced decoded ownership and real Slab settings input; fixture image responses, no user storage or engine'}));report:close();love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true)
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down end
 m=setmetatable({settings=json.decode(json.encode(Preferences.defaults)),page='settings',profile={},uiLayout={},toasts={},art={},catalogHealth={},byName={},lookupPending={},storageApiSupported=true,imagePackLoaded=true,imagePackStatus={state='idle'},storageStatus={dataDirectory='/tmp/isolated-image-preference-fixture',stats={}},downloadStatus={state='idle',cacheDirectory='/tmp/isolated-image-preference-fixture'}},Model)
 m.settings.skybox='Off';m.settings.windowMode='Windowed';m.settings.resolution='1440x900';m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.vsync=false
 m.api={request=function()error('The isolated settings harness does not contact real services')end};m.saveSettings=function(self)self.stored=json.decode(json.encode(self.settings))end
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p:apply(true);p.appliedLoaded=true
 local Cursor=require('lib.Slab.Internal.Core.Cursor');local Region=require('lib.Slab.Internal.UI.Region')
 local function bounds()local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();return{x=x+dx,y=y+dy,w=w,h=h}end
 for _,name in ipairs({'Button','BeginComboBox','TextSelectable'})do local original=S[name];S[name]=function(id,options)local result=original(id,options);controls[id]=bounds();return result end end
 local begin=S.BeginListBox;S.BeginListBox=function(id,options)local x,y=S.GetCursorPos({Absolute=true});local dx,dy=Region.Transform(nil,0,0);local result=begin(id,options);regions[id]={x=x+dx,y=y+dy,w=options.W,h=options.H};return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<60,'Artwork budget acceptance timed out');S.Update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,problem=coroutine.resume(runner);if not ok then local file=assert(io.open(output..'/failure.txt','w'));file:write(problem);file:close();print(problem);love.event.quit(1);return end end
 controls={};regions={};v:settings(love.graphics.getDimensions())
end
function love.draw()
 love.graphics.clear(.025,.035,.06,1);S.Draw()
 if#shots>0 then local path=output..'/'..table.remove(shots,1)..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local file=assert(io.open(path,'wb'));file:write(data:encode('png'):getString());file:close()end)end
end
function love.quit()if p then p:quit()end;S.OnQuit()end
function love.errorhandler(message)
 local problem=debug.traceback(tostring(message),2);print(problem)
 local file=assert(io.open(output..'/failure.txt','w'));file:write(problem);file:close()
 return function()return 1 end
end
