-- Actual Startup module/resource/graphics work with explicit synthetic health replies.
-- Launcher status is an owned temporary file; no user saves or native build runs.
local json=require('lib.json');local clock=0;local scenarioName='launcher-build';local ledger={};local queue={}
local function health(service)
 if service=='catalog'then
  if scenarioName=='metadata-missing'then return{status='ok',ready=false,apiVersion=15,index={state='error',error='Fixture: configured local card metadata is missing'},storage={dataDirectory='/tmp/isolated-startup-fixture'}},nil,200 end
  return{status='ok',ready=true,apiVersion=15,index={state='ready',cards=12},storage={dataDirectory='/tmp/isolated-startup-fixture'}},nil,200
 elseif service=='engine'then
  if scenarioName=='bridge-offline'then return nil,'Fixture: bridge unavailable',503 end
  return{engine='XMage',ok=true},nil,200
 elseif service=='room'then return{status='ok'},nil,200 end
 return nil,'Unexpected synthetic route',404
end
local function reply(item)
 if item.path=='/health'then return health(item.service)end
 if item.path=='/settings'then return{theme='Ember',accentColor='#33AAEE',skybox='Off',sfxEnabled=false,musicEnabled=false,resolution='1120x720',windowMode='Windowed'},nil,200 end
 if item.path=='/profile'then return{name='Startup Fixture'},nil,200 end
 if item.path=='/decks'then return{decks={{id='startup-fixture',name='Saved fixture',format='Modern',main={},sideboard={},commander={}}}},nil,200 end
 if item.path=='/ui-layout'then return{matchPrefs={}},nil,200 end
 return nil,'Unexpected synthetic route',404
end
package.preload['app.api']=function()return{escape=function(v)return tostring(v)end,new=function()return{
 request=function(_,service,method,path,body,callback)ledger[#ledger+1]={scenario=scenarioName,service=service,method=method,path=path};queue[#queue+1]={service=service,path=path,callback=callback,due=clock+.035}end,
 update=function()for i=#queue,1,-1 do local item=queue[i];if clock>=item.due then table.remove(queue,i);if item.callback then item.callback(reply(item))end end end end,
 quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local Preferences=require('app.preferences');local Startup=require('app.startup')
local m,r,p,current,runner;local panelBounds;local cursorDecodes=0;local wake=0;local checks,shots,captures,geometry={},{},{},{};local path=os.getenv('LOVE2GATHERING_STARTUP_STATUS')
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('STARTUP UI PASS '..label)end
local function wait(t)wake=clock+(t or .06);coroutine.yield()end
local function ready(fn,label)for _=1,800 do if fn()then return end;wait(.025)end;error('Timed out: '..label)end
local function status(state,stage,progress,message)
 local file=assert(io.open(path..'.tmp','wb'));file:write(json.encode({state=state,progress=progress,message=message,version='fixture-installed-revision',checks={{stage='dependencies',state='ready'},{stage='storage',state='ready'},{stage='version',state='ready'},{stage='assets',state='ready'},{stage=stage,state=state=='error'and'error'or state=='ready'and'ready'or'loading'}}}));file:close();assert(os.rename(path..'.tmp',path))
end
local function shot(name)shots[#shots+1]=name;wait(.16)end
local function fresh(name)
 scenarioName=name;queue={};m=Model.new();m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.animations=false;m.settings.particles=false
 r=Renderer.new(m);panelBounds=nil;local panel=r.assets.panel;r.assets.panel=function(self,x,y,w,h,...)panelBounds={x=x,y=y,w=w,h=h};return panel(self,x,y,w,h,...)end;p=Preferences.new(m,S,r);p:applyFont();p:applyCursor();current=Startup.new(m,r,p);return current
end
local function mode(w,h)
 love.window.setMode(w,h,{resizable=true,vsync=0});geometry[#geometry+1]={requested={w,h},physical={love.graphics.getDimensions()}}
end
local function noWrites()
 local allowed={['/health']=true,['/settings']=true,['/profile']=true,['/decks']=true,['/ui-layout']=true}
 for _,item in ipairs(ledger)do if item.method~='GET'or not allowed[item.path]then return false end end
 return true
end
local function scenario()
 mode(2560,1080);status('loading','build',.42,'Building pinned XMage and the local bridge · fixture status')
 local start=fresh('launcher-build');local modules,resources=#start.modules,#start.resources;local cursors=0;for _,resource in ipairs(start.resources)do if resource.family=='cursors'then cursors=cursors+1 end end;cursorDecodes=0
 check(modules>20 and resources>30,'Startup discovers actual application modules and curated resource identities')
 local previous=0;while start.phase~='services'do assert(start:progress()>=previous-.001,'Measured startup progress moved backwards');previous=start:progress();wait(.025)end
 check(true,'Measured progress stays monotonic through actual module and resource warming')
 check(start.checks.modules.state=='ready'and start.checks.assets.state=='ready'and start.checks.graphics.state=='ready','Real modules images sounds font atlases and graphics surface finish warming')
 check(start.moduleIndex>modules and start.resourceIndex>resources and cursors>0 and cursorDecodes==cursors,'Resource warming advances through the entire curated manifest and decodes every cursor PNG')
 check(not start.ready and#ledger==0,'An unfinished launcher build blocks all service polling and Model initialization')
 check(start.status.state=='loading'and start.status.progress==.42 and start.status.version=='fixture-installed-revision','Splash reads the actual owned launcher-status file and installed revision')
 shot('build-2560');mode(1120,720);shot('build-1120')
 status('ready','ready',1,'Local services ready · fixture status');ready(function()return start.ready end,'ready after owned launcher and three health replies')
 check(start.catalog.ready and start.engine.engine=='XMage'and start.room.status=='ok','Readiness requires catalog XMage and room health independently')
 check(start:progress()==1 and m.startupReport and m.startupReport.checks.ready.state=='ready','Successful gate retains its measured startup report')
 check(m.loaded and m.settingsLoaded and m.profileLoaded and m.playerName=='Startup Fixture'and p.appliedLoaded and start.finalGraphicsReady and noWrites(),'Actual Model saved data and applied personalized graphics finish before startup handoff without writes')
 shot('ready-1120')
 -- A failed shader/font warmup must restore the framebuffer before drawing its diagnostic.
 local graphics=fresh('graphics-failure');graphics.phase='graphics'
 local surface=r.assets.surface;r.assets.surface=function(self,name,...)if name=='spotlight'then error('Fixture: graphics warmup failed')end;return surface(self,name,...)end
 local canvas,font,shader=love.graphics.getCanvas(),love.graphics.getFont(),love.graphics.getShader();local color={love.graphics.getColor()};local depth=love.graphics.getStackDepth and love.graphics.getStackDepth()
 graphics:update(.01)
 local a,b,c,d=love.graphics.getColor()
 check(graphics.error and graphics.error:find('graphics warmup failed',1,true)and not graphics.ready,'A failed graphics warmup becomes a blocking startup diagnostic')
 check(love.graphics.getCanvas()==canvas and love.graphics.getFont()==font and love.graphics.getShader()==shader and math.abs(a-color[1])<.001 and math.abs(d-color[4])<.001 and(not depth or love.graphics.getStackDepth()==depth),'Graphics failure restores framebuffer font shader color and stack before drawing the error')
 r.assets.surface=surface;shot('graphics-failure-1120')
 -- Test the resource gate directly: one intentionally absent local image is fatal.
 local bad=fresh('missing-resource');bad.modules={};bad.resources={{family='icons',name='missing',path='assets/fixture-resource-does-not-exist.png'}};bad.phase='assets';wait(.1)
 check(bad.error and bad.error:find('Missing resource:',1,true)and not bad.ready,'An absent supplied resource produces a visible blocking diagnostic')
 shot('missing-resource-1120')
 -- Presence alone is insufficient: a corrupt cursor PNG must fail decoding.
 local filename=love.filesystem.getSource()..'/assets/fixture-corrupt-cursor.png';local file=assert(io.open(filename,'wb'));file:write('Fixture: not a PNG image');file:close()
 assert(love.filesystem.getInfo('assets/fixture-corrupt-cursor.png'),'Corrupt fixture must exist before decoding')
 local corrupt=fresh('corrupt-cursor');corrupt.modules={};corrupt.resources={{family='cursors',name='corrupt',path='assets/fixture-corrupt-cursor.png'}};corrupt.phase='assets';wait(.1)
 check(corrupt.error and not corrupt.ready and corrupt.resourceIndex==1,'A present but corrupt cursor PNG blocks readiness with a decoding diagnostic')
 shot('corrupt-cursor-1120')
 -- A source-index failure can still open the saved deck library explicitly.
 status('ready','ready',1,'Local services ready · fixture status');local missing=fresh('metadata-missing')
 ready(function()return missing.allowOffline and missing.error end,'missing metadata continuation')
 check(not missing.ready and missing.error:find('metadata is missing',1,true),'Missing metadata remains an explicit startup failure before continuation')
 ready(function()return missing.personalizationReady and missing.continueBounds end,'saved profile/preferences before offline continuation');check(missing.continueBounds and panelBounds and missing.continueBounds.y+missing.continueBounds.h<=panelBounds.y+panelBounds.h-2 and missing.continueBounds.y+missing.continueBounds.h<=select(2,love.graphics.getDimensions()),'Saved-library continuation remains padded inside the actual panel and viewport')
 shot('missing-metadata-1120')
 local b=missing.continueBounds;check(not missing:press(b.x+b.w/2,b.y+b.h/2,2)and not missing:press(1,1,1),'Only the visible left-click continuation target can leave the error gate')
 check(missing:press(b.x+b.w/2,b.y+b.h/2,1)and missing.ready and m.startupReport.offline and m.startupReport.error,'Explicit continuation preserves the error and opens saved-library mode')
 check(noWrites(),'Offline continuation sends no save or engine action')
 -- Direct love startup without a launcher may open a library when only XMage is down.
 local offline=fresh('bridge-offline');offline.path=nil;offline.time=9
 ready(function()return offline.allowOffline end,'unavailable bridge offline prompt')
 check(not offline.ready and offline.catalog.ready and not offline.engine,'An unavailable bridge cannot falsely complete readiness')
 shot('bridge-offline-1120')
 -- Launcher failures cannot accidentally unblock the normal Model.
 status('error','build',.42,'Fixture: compilation failed');local failed=fresh('launcher-error');failed.phase='services';wait(.25)
 check(failed.error=='Fixture: compilation failed'and not failed.ready,'Launcher build errors remain visible and block the startup gate')
 shot('launcher-error-1120')
 local file=assert(io.open(path,'wb'));file:write(string.rep('x',65537));file:close();local invalid=fresh('invalid-status');invalid.phase='services';wait(.25)
 check(invalid.error=='Startup status is invalid'and not invalid.ready,'Oversized launcher status is rejected without loading unbounded data')
 check(noWrites(),'Every startup scenario remains limited to read-only health and saved-data requests')
 local report={passed=true,checks=checks,captures=captures,geometry=geometry,requests=ledger,moduleCount=modules,resourceCount=resources,scope='Actual LÖVE Startup/Model hydrates saved data and applies supplied graphics; launcher status and health/settings/profile/deck/layout replies are explicit isolated fixtures. No native build, real service initialization, WAN check, image download or user-data write claim.'}
 local f=assert(io.open('/tmp/love2gathering-startup-ui-report.json','w'));f:write(json.encode(report));f:close();print('STARTUP UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.errorhandler(err)io.stderr:write('STARTUP UI FAILED '..tostring(err)..'\n'..debug.traceback()..'\n');return function()return 1 end end
function love.load()
 assert(path and path:find('/tmp/love2gathering%-startup%-ui%.'),'Use the owned temporary launcher fixture');local decode=love.image.newImageData;love.image.newImageData=function(value,...)if current and current.phase=='assets'and type(value)=='string'and value:find('/cursors/',1,true)then cursorDecodes=cursorDecodes+1 end;return decode(value,...)end;S.SetINIStatePath(nil);S.Initialize({},true);runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<100,'Startup acceptance timed out')
 if current and not current.ready then current:update(dt)end
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
end
function love.draw()
 if current then current:draw();p:endFrame()end
 if#shots>0 then local name=table.remove(shots,1);local capture='/tmp/love2gathering-startup-'..name..'.png';captures[#captures+1]=capture;love.graphics.captureScreenshot(function(data)local f=assert(io.open(capture,'wb'));f:write(data:encode('png'):getString());f:close()end)end
 love.timer.sleep(.012)
end
function love.quit()if m then m.api:quit()end;if p then p:quit()end;S.OnQuit()end
