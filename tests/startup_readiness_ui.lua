-- Actual splash/resource/font/Slab drawing with explicitly delayed saved-data fixtures.
-- No real catalog, engine, image acquisition or application saves are used.
local json=require('lib.json')
local S=require('lib.Slab');local Renderer=require('app.renderer');local Preferences=require('app.preferences');local Startup=require('app.startup');local Assets=require('app.assets')
local clock,wake,current,m,r,p,runner=0,0
local checks,captures,shots,requests,geometry={},{},{},{},{}
local root=assert(os.getenv('LOVE2GATHERING_STARTUP_TEST_OUTPUT'))
local statusPath=assert(os.getenv('LOVE2GATHERING_STARTUP_STATUS'))
local function copy(v)return json.decode(json.encode(v))end
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('STARTUP READINESS PASS '..label)end
local function wait(t)wake=clock+(t or .04);coroutine.yield()end
local function untilReady(fn,label)for _=1,1400 do if fn()then return end;wait(.025)end;error('Timed out: '..label)end
local function shot(name)shots[#shots+1]=name;wait(.12)end
local function profile()return{name='Startup Guardian',avatar={name='Fixture Avatar',printingId='fixture-art',oracleId='fixture-oracle',face=0}}end
local function fixture(mode)
 local model={settings=copy(Preferences.defaults),settingsLoaded=false,profileLoaded=false,playerName='Planeswalker',toasts={},art={},phaseVersion=1}
 model.settings.skybox='Off';model.settings.sfxEnabled=false;model.settings.musicEnabled=false
 function model:toast(message,bad)self.toasts[#self.toasts+1]={message=message,bad=bad}end
 local queue={};local load={};local generation=1;model.hydrationRequests={};local profileAttempts=0
 local delay={settings=.3,profile=3.3,decks=.5,uiLayout=.7}
 local endpoints={settings='/settings',profile='/profile',decks='/decks',uiLayout='/ui-layout'}
 local settings={theme='Ember',accentColor='#33AAEE',opponentColor='#EE7744',skybox='Off',sfxEnabled=false,musicEnabled=false,reducedMotion=false,resolution='1120x720',windowMode='Windowed',fontQuality='High',panelOpacity=.81,uiScale=1}
 local function requestData(key)
  if load[key]and(load[key].pending or load[key].ready)then return end
  load[key]={pending=true};model.hydrationRequests[key]=(model.hydrationRequests[key]or 0)+1
  if key=='profile'then profileAttempts=profileAttempts+1 end
  queue[#queue+1]={due=clock+delay[key],key=key,generation=generation,fail=key=='profile'and mode=='profile-error'and profileAttempts==1}
  requests[#requests+1]={method='GET',path=endpoints[key],scenario=mode}
 end
 model.api={request=function(_,service,method,path,body,callback)
  assert(path=='/health'and method=='GET','Only explicit synthetic health routes allowed')
  requests[#requests+1]={service=service,method=method,path=path,scenario=mode};queue[#queue+1]={due=clock+.04,service=service,callback=callback}
 end,update=function()
  for i=#queue,1,-1 do local item=queue[i];if clock>=item.due then table.remove(queue,i)
   if item.callback then
    if item.service=='catalog'then item.callback({apiVersion=mode=='old-service'and 13 or 14,ready=mode~='metadata-missing',index={state=mode=='metadata-missing'and'error'or'ready',error=mode=='metadata-missing'and'Fixture: local metadata unavailable'or nil}},nil,200)
    elseif item.service=='engine'then item.callback({engine='XMage',ok=true},nil,200)else item.callback({status='ok'},nil,200)end
   elseif item.generation==generation then
    if item.fail then load[item.key]={error='Saved profile timed out · fixture'}
    else
     load[item.key]={ready=true}
     if item.key=='settings'then for key,value in pairs(settings)do model.settings[key]=value end;model.settingsLoaded=true
     elseif item.key=='profile'then model.profile=profile();model.playerName=model.profile.name;model.profileLoaded=true
     elseif item.key=='decks'then model.decks={{id='fixture-deck',name='Saved deck',main={}}}
     else model.uiLayout={matchPrefs={logOpen=true}}end
    end
   end
  end end
 end,quit=function()end}
 function model:beginStartupHydration()for _,key in ipairs({'settings','profile','decks','uiLayout'})do if not load[key]then requestData(key)end end end
 function model:startupHydrationState()
  local count,error=0
  for _,key in ipairs({'settings','profile','decks','uiLayout'})do local item=load[key]or{};if item.ready then count=count+1 elseif item.error then error=item.error end end
  return{ready=count==4,progress=count/4,error=error,retryable=error~=nil,message='Loading saved theme, profile and library · '..count..' / 4'}
 end
 function model:retryStartupHydration()model.retries=(model.retries or 0)+1;for _,key in ipairs({'settings','profile','decks','uiLayout'})do if load[key]and load[key].error then load[key]=nil;requestData(key)end end end
 model.startedAt=clock
 return model
end
local function fresh(mode)
 love.window.setMode(1440,900,{resizable=true,vsync=0});geometry[#geometry+1]={initial={love.graphics.getDimensions()}}
 m=fixture(mode);r=Renderer.new(m);p=Preferences.new(m,S,r);p:applyFont();p:applyCursor();current=Startup.new(m,r,p);return current
end
local function finalIconPixels()
 local canvas=r.assets:iconImage('settings',24);local data=canvas:newImageData();local maximum=0
 for y=0,data:getHeight()-1 do for x=0,data:getWidth()-1 do local _,_,_,a=data:getPixel(x,y);maximum=math.max(maximum,a)end end
 data:release();return maximum
end
local function spinnerDifference(still)
 local frames={}
 for _,time in ipairs({0,.23})do
  local canvas=love.graphics.newCanvas(40,40);local previous=love.graphics.getCanvas();love.graphics.push('all')
  love.graphics.setCanvas(canvas);love.graphics.clear(0,0,0,0);r.assets:loadingCircle(5,5,30,time,{1,1,1,1},still)
  love.graphics.setCanvas(previous);love.graphics.pop();frames[#frames+1]=canvas:newImageData();canvas:release()
 end
 local changed=0;for y=0,39 do for x=0,39 do local _,_,_,a=frames[1]:getPixel(x,y);local _,_,_,b=frames[2]:getPixel(x,y);if math.abs(a-b)>.05 then changed=changed+1 end end end
 frames[1]:release();frames[2]:release();return changed
end
local function mainHandoff()
 local names={'lib.Slab','app.model','app.renderer','app.view','app.layout','app.preferences','app.storage','app.startup'}
 local saved={};for _,name in ipairs(names)do saved[name]=package.loaded[name]end
 local callbackNames={'load','update','draw','mousepressed','mousereleased','mousemoved','wheelmoved','textinput','keypressed','keyreleased','filedropped','resize','quit'}
 local callbacks={};for _,name in ipairs(callbackNames)do callbacks[name]=love[name]end
 local title=love.window.getTitle();local trace={};local model={settings={},update=function()trace[#trace+1]='model'end}
 package.loaded['lib.Slab']={SetINIStatePath=function()end,Initialize=function()end,Update=function()trace[#trace+1]='slab'end,IsVoidHovered=function()return true end}
 package.loaded['app.model']={new=function()return model end}
 package.loaded['app.renderer']={new=function()return{assets={icon=function()return'assets/icons/thb.png'end},update=function()trace[#trace+1]='renderer'end,mousemoved=function()end}end}
 package.loaded['app.view']={new=function()return{build=function()trace[#trace+1]='view'end}end}
 package.loaded['app.layout']={mouse=function()return 0,0 end}
 package.loaded['app.preferences']={new=function()return{apply=function()end,update=function()trace[#trace+1]='preferences'end}end}
 package.loaded['app.storage']={}
 package.loaded['app.startup']={new=function()return{ready=false,update=function(self)trace[#trace+1]='startup';self.ready=true end}end}
 local ok,problem=pcall(function()assert(love.filesystem.load('application-main.lua'))();love.load({});love.update(.016)end)
 for _,name in ipairs(names)do package.loaded[name]=saved[name]end
 for _,name in ipairs(callbackNames)do love[name]=callbacks[name]end
 love.window.setTitle(title)
 check(ok and table.concat(trace,',')=='startup,model,preferences,slab,renderer,view','Main builds the personalized controls in the same update that releases the gate: '..tostring(problem or''))
end
local function scenario()
 local f=assert(io.open(statusPath,'w'));f:write(json.encode({state='ready',progress=1,message='Ready fixture launcher',checks={}}));f:close()
 mainHandoff()
 local start=fresh('delayed')
 untilReady(function()return start.catalog~=nil end,'three independent health replies')
 check(not start.ready and not m.settingsLoaded and not m.profileLoaded,'Healthy services alone cannot reveal the default application')
 untilReady(function()return m.settingsLoaded end,'saved settings')
 check(not start.ready and not m.profileLoaded,'Saved theme arriving before profile does not release the splash')
 check(p.appliedLoaded and math.abs(r.colors.accent[1]-51/255)<.001 and math.abs(S.GetStyle().ButtonPressedColor[1]-r.assets.theme.styles.ButtonPressedColor[1])<.001,'Saved colors and Slab skin are actually applied during the splash')
 check(select(1,love.graphics.getDimensions())==1120 and select(2,love.graphics.getDimensions())==720,'Saved native display mode is applied behind the startup gate')
 wait(.1);check(start.percentageText and start.percentageText:match('^%d+%%$')and tonumber(start.percentageText:sub(1,-2))<100,'Splash displays measured integer percentage below100 while profile is pending')
 local angle=start.spinnerAngle;wait(.18);check(start.spinnerAngle~=angle,'Supplied circular loading asset rotates while saved data is pending')
 check(spinnerDifference(false)>30,'Actual decoded Kenney loading-circle pixels rotate between timed frames')
 shot('saved-theme-pending-profile')
 m.settings.reducedMotion=true;wait(.07);check(start.spinnerAngle==0,'Reduced motion keeps the real loading sprite still');m.settings.reducedMotion=false
 check(spinnerDifference(true)==0,'Reduced-motion loading-circle pixels remain identical across timestamps')
 untilReady(function()return start.ready end,'personalized handoff')
 check(m.playerName=='Startup Guardian'and m.profile.avatar.printingId=='fixture-art'and#m.decks==1 and m.uiLayout.matchPrefs.logOpen,'Saved identity decks and layout are all ready before handoff')
 check(start.finalGraphicsReady and start.finalRasterEpoch==Assets.rasterContext()and finalIconPixels()>.9,'Post-preference raster generation has nonblank icon pixels after display invalidation')
 check(start:progress()==1 and p.appliedLoaded and start.personalizationReady,'100percent means saved data and applied graphics are complete')
 shot('personalized-ready')
 local retry=fresh('profile-error');untilReady(function()return retry.hydrationError~=nil end,'visible saved-profile failure');wait(.07)
 check(not retry.ready and retry.retryBounds and not retry.continueBounds,'A saved-profile failure stays blocked with Retry instead of opening defaults')
 local before={};for key,value in pairs(m.hydrationRequests)do before[key]=value end
 shot('saved-profile-error');local b=retry.retryBounds;love.mousepressed(b.x+b.w/2,b.y+b.h/2,1)
 untilReady(function()return retry.ready end,'successful explicit saved-data retry')
 check(m.retries==1 and m.hydrationRequests.profile==2 and m.hydrationRequests.settings==before.settings and m.hydrationRequests.decks==before.decks and m.hydrationRequests.uiLayout==before.uiLayout,'Retry re-fetches only failed saved data without duplicating completed hydration')
 check(m.playerName=='Startup Guardian'and p.appliedLoaded,'Retry completes with the saved profile and applied theme')
 local offline=fresh('metadata-missing');untilReady(function()return offline.error~=nil end,'missing source diagnostic');wait(.07)
 check(offline.allowOffline and not offline.continueBounds and not offline.ready,'Offline library cannot bypass pending saved identity and preferences')
 untilReady(function()return offline.personalizationReady end,'saved offline library hydration');wait(.07)
 check(offline.continueBounds and not offline.ready,'Only an explicitly personalized saved library offers offline continuation')
 local b=offline.continueBounds;love.mousepressed(b.x+b.w/2,b.y+b.h/2,1)
 check(offline.ready and m.startupReport.offline and m.playerName=='Startup Guardian','Offline continuation preserves diagnostic and saved identity')
 shot('personalized-offline')
 local old=fresh('old-service');untilReady(function()return old.errorKind=='incompatibleCatalog'end,'older catalog compatibility gate');wait(.07)
 check(not old.ready and not old.allowOffline and next(m.hydrationRequests)==nil,'An older catalog is rejected before loading saved data or offering default/offline entry')
 shot('older-catalog-service')
 local readOnly=true;for _,request in ipairs(requests)do if request.method~='GET'then readOnly=false end end
 check(readOnly,'All startup requests are read-only; no persistence or gameplay mutation occurs')
 local report={passed=true,checks=checks,requests=requests,captures=captures,geometry=geometry,scope='Actual LÖVE Startup, supplied PNG/Slab/Beleren and native display-mode application; delayed health/settings/profile/deck/layout responses are explicit isolated fixtures, not real-service throughput or native-game evidence.'}
 local file=assert(io.open(root..'/report.json','w'));file:write(json.encode(report));file:close();love.event.quit(0)
end
function love.load()
 assert(root:find('^/tmp/love2gathering%-startup%-readiness%-'),'Owned output required');S.SetINIStatePath(nil);S.Initialize({},true);runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<90,'Startup readiness fixture timed out')
 if current and not current.ready then current:update(dt)end
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,problem=coroutine.resume(runner);assert(ok,problem)end
end
function love.draw()
 if current then current:draw();p:endFrame()end
 if#shots>0 then local name=table.remove(shots,1);local filename=root..'/'..name..'.png';captures[#captures+1]=filename;love.graphics.captureScreenshot(function(data)local file=assert(io.open(filename,'wb'));file:write(data:encode('png'):getString());file:close()end)end
 love.timer.sleep(.012)
end
function love.mousepressed(x,y,button)if current and not current.ready then return current:press(x,y,button)end end
function love.quit()if p then p:quit()end;S.OnQuit()end
function love.errorhandler(problem)
 local file=assert(io.open(root..'/failure.txt','w'));file:write(tostring(problem)..'\n'..debug.traceback());file:close();io.stderr:write(tostring(problem)..'\n'..debug.traceback()..'\n');return function()return 1 end
end
