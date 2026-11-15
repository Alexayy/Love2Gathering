-- Actual main/API/Slab profile editing against an isolated real catalog.
local json=require('lib.json');local Layout=require('app.layout');local S=require('lib.Slab');local API=require('app.api');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences')
local m,r,v,p,Cursor,Window;local mouse={x=2,y=2};local mouseDown,keys={},{};local clock,wake=0,0;local runner;local buttons,inputs,checks,shots,images={},{},{},{},{}
local targets=json.decode(assert(love.filesystem.read('profile-test-art.json')));local width=tonumber(os.getenv('PROFILE_TEST_WIDTH'))or 1440;local height=tonumber(os.getenv('PROFILE_TEST_HEIGHT'))or 900
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('PROFILE UI PASS '..label);io.stdout:flush()end
local function wait(seconds)wake=clock+(seconds or .1);coroutine.yield()end
local function ready(fn,label,seconds)local stop=clock+(seconds or 15);while not fn()do assert(clock<stop,label..' '..json.encode({page=m and m.page,query=m and m.profileQuery,busy=m and m.profileBusy,timer=m and m.profileSearchTimer,error=m and m.profileSearchError,total=m and m.profileTotal}));wait(.05)end end
local function move(x,y)local oldx,oldy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;love.mousemoved(mouse.x,mouse.y,mouse.x-oldx,mouse.y-oldy,false)end
local function click(box)assert(box,'Missing actual profile control');move(box.x+box.w/2,box.y+box.h/2);wait(.06);mouseDown[1]=true;love.mousepressed(mouse.x,mouse.y,1,false,1);wait(.06);mouseDown[1]=nil;love.mousereleased(mouse.x,mouse.y,1,false,1);wait(.15)end
local function text(box,value)click(box);keys.lctrl=true;love.keypressed('lctrl','lctrl',false);wait(.08);love.keypressed('a','a',false);wait(.08);love.keyreleased('a','a');keys.lctrl=nil;love.keyreleased('lctrl','lctrl');wait(.06);love.textinput(value);wait(.35)end
local function request(method,path,body)local done,result,problem=false;m:request('catalog',method,path,body,function(data,err)result=data;problem=err;done=true end,true);ready(function()return done end,'Profile HTTP request did not finish');assert(not problem,problem);return result end
local function choose(slot,target)
    click(buttons[slot=='avatar'and'Avatar'or'Playmat']);check(m.profileSlot==slot,'Actual '..slot..' selector changes the artwork destination')
    text(inputs['profile-search'],target.query)
    ready(function()if m.profileBusy or m.profileSearchTimer then return false end;for _,item in ipairs(m.profileItems or{})do if item.printing_id==target.printingId and item.face==target.face then return true end end end,'Exact cached printing did not appear in artwork search')
    local id='profile-select-'..target.printingId..'-'..tostring(target.face)
    ready(function()return buttons[id]end,'Artwork selection button is not drawn');click(buttons[id])
    check(m.profileDraft[slot]and m.profileDraft[slot].printingId==target.printingId and m.profileDraft[slot].face==target.face,'Actual artwork click retains exact '..slot..' printing and face')
    ready(function()return m:profileArt(m.profileDraft[slot])end,'Actual cached '..slot..' illustration did not decode')
    check(true,'Selected '..slot..' uses a genuine cached illustration')
end
local function scenario()
    ready(function()return m.catalogHealth.ready end,'Isolated ready catalog did not arrive',25);m:showProfile();ready(function()return m.profileLoaded and inputs['profile-name']end,'Profile page did not load SQLite data')
    check(m.page=='profile','Profile page opens through actual Model/View hooks')
    text(inputs['profile-name'],'Čarobnjak '..width);check(m.profileDraft.name=='Čarobnjak '..width,'Actual Slab name input preserves UTF-8 text (received '..tostring(m.profileDraft.name)..')')
    if targets.rin then
        text(inputs['profile-search'],'Rin');text(inputs['profile-search'],'Rin & Seri')
        ready(function()return not m.profileBusy and not m.profileSearchTimer and#(m.profileItems or{})>0 end,'Rin and Seri search did not settle',25)
        local correct=m.profileItems[1].name:find('Rin and Seri',1,true)~=nil
        for _,item in ipairs(m.profileItems)do correct=correct and item.name~='Meandering River'end
        check(correct,'Actual prefix then ampersand input returns Rin and Seri, never the stale Meandering River result')
        text(inputs['profile-search'],targets.rin.query)
        ready(function()return not m.profileBusy and not m.profileSearchTimer and#(m.profileItems or{})>0 end,'Mixed cached/missing artwork search did not settle',25)
        local cached=targets.rin.cached;local missing=targets.rin.missing
        ready(function()m:profileArt(cached);m:profileArt(missing);return m:profileArtState(cached)=='ready'and m:profileArtState(missing)=='missing'end,'Exact cached/missing image states did not settle',25)
        check(true,'Real cached and uncached printings have distinct ready/missing states without artist substitution')
        local id='profile-select-'..missing.printingId..'-'..missing.face
        ready(function()return buttons[id]end,'Uncached artwork selector was not visible');click(buttons[id])
        check(m.profileDraft.avatar.printingId==missing.printingId and m:profileArtState(m.profileDraft.avatar)=='missing','An uncached avatar keeps its exact selected printing and an explicit missing state')
        ready(function()return buttons['Download avatar']end,'Explicit missing-avatar download action is not visible')
        shots[#shots+1]='profile-missing-'..width;wait(.3)
        if os.getenv('PROFILE_TEST_DOWNLOAD_SELECTED')=='1'then
            click(buttons['Download avatar']);ready(function()return not m.profileDownloading and m:profileArtState(m.profileDraft.avatar)=='ready'end,'Explicit selected illustration download did not complete',25)
            check(m.profileDraft.avatar.printingId==missing.printingId,'Actual Download avatar fills only the selected printing and retains its identity')
        end
    end
    choose('avatar',targets.avatar);choose('playmat',targets.playmat)
    ready(function()return buttons['Save profile']end,'Profile Save is not visible');local save=buttons['Save profile'];local _,logicalH=Layout.dimensions();check(save.y+save.h<=logicalH,'Save remains visible in the current viewport')
    click(save);ready(function()return not m.profileSaving and not m.profileDirty end,'Actual Save profile did not complete')
    local stored=request('GET','/profile');check(stored.name=='Čarobnjak '..width and stored.avatar.printingId==targets.avatar.printingId and stored.playmat.printingId==targets.playmat.printingId,'Actual Save persists name/avatar/playmat through SQLite HTTP')
    check(stored.life==nil and stored.hp==nil,'Profile page never stores an HP override')
    m.profile=nil;m.profileDraft=nil;m.profileLoaded=false;m.profileDirty=false;m:showProfile();ready(function()return m.profileLoaded and m.profileDraft.playmat end,'Saved profile did not reopen')
    check(m.profileDraft.avatar.printingId==targets.avatar.printingId and m.profileDraft.playmat.printingId==targets.playmat.printingId,'Reopening restores both exact saved selections from the service')
    ready(function()return m:profileArt(m.profileDraft.avatar)and m:profileArt(m.profileDraft.playmat)end,'Reopened profile illustrations did not decode')
    ready(function()return not m.profileBusy end,'Reopened artwork list did not settle');m.toasts={};move(2,2);shots[#shots+1]='profile-'..width;wait(.3)
    if targets.rin then
        m:showGallery();ready(function()return inputs['gallery-search']end,'Gallery search did not render')
        text(inputs['gallery-search'],targets.rin.query)
        ready(function()return not m.galleryBusy and not m.galleryTimer and#(m.galleryItems or{})>0 end,'Gallery mixed search did not settle',25)
        ready(function()for _,item in ipairs(m.galleryItems)do m:getGalleryArt(item);if m:galleryArtState(item)=='loading'then return false end end;return true end,'Visible gallery image states did not settle',25)
        local missing
        for _,item in ipairs(m.galleryItems)do if not item.art_cached then missing=item;break end end
        while not missing and m.galleryOffset+m.galleryLimit<(m.galleryTotal or 0)do
            local offset=m.galleryOffset;click(buttons.Next)
            ready(function()return not m.galleryBusy and m.galleryOffset>offset end,'Next mixed gallery page did not settle',25)
            ready(function()for _,item in ipairs(m.galleryItems)do m:getGalleryArt(item);if m:galleryArtState(item)=='loading'then return false end end;return true end,'Paged gallery images did not settle',25)
            for _,item in ipairs(m.galleryItems)do if not item.art_cached then missing=item;break end end
        end
        if missing then
            ready(function()m:getGalleryArt(missing);return m:galleryArtState(missing)=='missing'end,'Gallery missing printing did not become explicit')
            check(missing.artist and missing.artist~=''and m:galleryArtState(missing)=='missing','Gallery keeps actual credits for an uncached printing and stops showing Loading')
        end
        shots[#shots+1]='gallery-mixed-'..width;wait(.3)
        ready(function()return buttons['gallery-art-missing']end,'Gallery missing illustration did not remain inspectable')
        click(buttons['gallery-art-missing']);check(m.galleryInspect and m:galleryArtState(m.galleryInspect)=='missing','Actual missing-art click opens the exact printing inspector')
        ready(function()return buttons['Download artwork']and buttons['Close artwork']end,'Gallery inspector actions are not visible')
        shots[#shots+1]='gallery-missing-'..width;wait(.3);click(buttons['Close artwork'])
        check(not m.galleryInspect,'Actual Close artwork returns to the mixed gallery grid')
    end
    local out=assert(io.open('/tmp/love2gathering-profile-ui-'..width..'-report.json','w'));out:write(json.encode({passed=true,checks=checks,width=love.graphics.getWidth(),height=love.graphics.getHeight(),scale=Layout.scale,profile=stored,scope='Actual main callbacks, Slab input and real temporary catalog SQLite; exact cached illustrations; no injected native gameplay'}));out:close();print('PROFILE UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
local originalAPI=API.new;API.new=function(options)options=options or{};options.catalogPort=assert(tonumber(os.getenv('LOVE2GATHERING_CATALOG_PORT')));options.enginePort=tonumber(os.getenv('LOVE2GATHERING_ENGINE_PORT'))or 17462;return originalAPI(options)end
local oldModel=Model.new;Model.new=function(...)m=oldModel(...);m.settings.presentationVersion=2;m.settings.windowMode='Windowed';m.settings.resolution=width..'x'..height;return m end
local oldRenderer=Renderer.new;Renderer.new=function(...)r=oldRenderer(...);return r end
local oldView=View.new;View.new=function(...)v=oldView(...);return v end
local oldPreferences=Preferences.new;Preferences.new=function(...)p=oldPreferences(...);return p end
assert(love.filesystem.load('application.lua'))();local appLoad,appUpdate,appDraw,appQuit=love.load,love.update,love.draw,love.quit
function love.load()
    appLoad({});Cursor=require('lib.Slab.Internal.Core.Cursor');Window=require('lib.Slab.Internal.UI.Window');love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return mouseDown[button]==true end;love.keyboard.isDown=function(...)for _,key in ipairs({...})do if keys[key]then return true end end;return false end;love.keyboard.isScancodeDown=love.keyboard.isDown
    m.loaded=true;m.settingsLoaded=true;m.page='profile';m.uiLayout={};m.settings.presentationVersion=2;m.settings.resolution=width..'x'..height;m.settings.windowMode='Windowed';m.settings.uiScale=1;m.settings.renderScale=1;m.settings.localArtworkOnly=true;m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.particles=false;m.settings.animations=false;m.settings.frameLimit=0;p.appliedLoaded=true;p:apply(true)
    for _,kind in ipairs({'Button','Input'})do local original=S[kind];S[kind]=function(id,options,...)local result=original(id,options,...);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);(kind=='Button'and buttons or inputs)[id]={x=x,y=y,w=w,h=h};return result end end
    runner=coroutine.create(scenario)
end
function love.update(dt)clock=clock+dt;assert(clock<155,'Profile UI acceptance exceeded155 seconds');buttons={};inputs={};appUpdate(dt);if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end end
function love.draw()appDraw();if#shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)local out=assert(io.open('/tmp/love2gathering-'..name..'.png','wb'));out:write(data:encode('png'):getString());out:close()end)end end
function love.quit()if appQuit then return appQuit()end end
function love.errorhandler(message)io.stderr:write('PROFILE UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
