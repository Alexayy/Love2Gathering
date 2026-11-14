function love.errorhandler(message)
    io.stderr:write('GALLERY UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Gallery=require('app.gallery');local json=require('lib.json')
local m,r,v,prefs,Cursor,Region,runner
local elapsed,wake=0,0;local buttons,combos,selections,images={},{},{},{};local opened={};local checks={};local shots={}
local mouse={x=0,y=0};local down=false
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('GALLERY UI PASS '..label)end
local function wait(seconds)wake=elapsed+(seconds or .08);coroutine.yield()end
local function untilReady(fn,seconds,message)
    local deadline=elapsed+(seconds or 15);while not fn()do assert(elapsed<deadline,message);wait(.08)end
end
local function move(x,y)
    local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy)
end
local function click(box)
    assert(box,'Expected gallery control was not rendered');move(box.x+box.w/2,box.y+box.h/2);wait(.04)
    down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.04)
    down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.12)
end
local function screenshot(name)shots[#shots+1]=name;wait(.15)end
local function imageCount()local count=0;for _,entry in ipairs(images)do if entry.id=='gallery-art'then count=count+1 end end;return count end
local function hasImage(id)for _,entry in ipairs(images)do if entry.id==id then return true end end end
local function scenario()
    local unavailable=os.getenv('LOVE2GATHERING_GALLERY_EXPECT_UNAVAILABLE')
    untilReady(function()return m.settingsLoaded and (unavailable or m.catalogHealth.ready)end,20,'Fixture metadata/settings did not load')
    m.settings.resolution='1440x900';m.settings.uiScale=1;m.settings.renderScale=1;m.settings.vsync=false;m.settings.sfxEnabled=false;prefs:apply(true)
    m:showGallery()
    if unavailable then
        untilReady(function()return not m.galleryBusy and m.galleryError end,10,'Missing-source error did not load')
        check(#m.galleryItems==0 and m.galleryError:find('index',1,true),'Missing metadata shows an explicit indexing error without invented artwork')
        check(#opened==0,'Unavailable-source view opens no artist links')
        screenshot('unavailable')
        local output=assert(io.open('/tmp/love2gathering-gallery-unavailable-ui-report.json','w'));output:write(json.encode({checks=checks,error=m.galleryError}));output:close()
        print('GALLERY UNAVAILABLE UI COMPLETE '..#checks..' checks');love.event.quit(0);return
    end
    untilReady(function()return not m.galleryBusy and #(m.galleryItems or {})>0 and imageCount()==#m.galleryItems end,20,'Gallery art did not decode from SQLite')
    check(m.page=='gallery' and #m.galleryItems>0,'Actual model loads per-printing gallery metadata')
    check(imageCount()==#m.galleryItems,'Every visible artwork decodes through the actual HTTP image worker')
    for _,entry in ipairs(images)do if entry.id=='gallery-art'then
        check(math.abs(entry.w/entry.h-entry.image:getWidth()/entry.image:getHeight())<.001,'Art crop retains its original aspect ratio')
    end end
    check(#opened==0,'Artist websites never open during browsing')
    screenshot('1440-grid')
    if buttons.Shop then click(buttons.Shop);check(opened[1]=='https://www.inprnt.com/gallery/rpancoast/','Actual shop button opens its verified artist destination')end
    local first;for _,entry in ipairs(images)do if entry.id=='gallery-art'then first=entry;break end end
    click(first);check(m.galleryInspect and hasImage('gallery-full-art'),'Clicking artwork opens an art-only enlarged view')
    screenshot('1440-enlarged');click(buttons['Close artwork']);check(not m.galleryInspect,'Enlarged artwork closes through its actual button')
    m.settings.resolution='1120x720';m.settings.uiScale=1.25;prefs:apply(true);wait(.2)
    untilReady(function()return not m.galleryBusy and imageCount()==#m.galleryItems end,10,'Smaller gallery page did not settle')
    if m.galleryTotal>m.galleryLimit then
        click(buttons.Next);untilReady(function()return not m.galleryBusy and m.galleryOffset>0 and imageCount()==#m.galleryItems end,10,'Next gallery page did not load')
        check(m.galleryOffset==m.galleryLimit,'Actual Next button loads a bounded next page')
        click(buttons.Previous);untilReady(function()return not m.galleryBusy and m.galleryOffset==0 end,10,'Previous gallery page did not load')
        check(m.galleryOffset==0,'Actual Previous button restores the first page')
    end
    screenshot('1120-grid')
    click(combos['gallery-variant']);untilReady(function()return selections['Extended art']~=nil end,3,'Variant dropdown did not open')
    click(selections['Extended art']);untilReady(function()return m.galleryVariant=='extended' and not m.galleryBusy and #m.galleryItems>0 end,10,'Extended-art filter did not load')
    local extended=true;for _,item in ipairs(m.galleryItems)do
        local present=false;for _,effect in ipairs(item.frame_effects or {})do if effect=='extendedart'then present=true end end
        extended=extended and present
    end
    check(extended,'Actual variant dropdown loads only real extended-art printing metadata')
    m.settings.resolution='1440x900';m.settings.uiScale=1;prefs:apply(true);wait(.2)
    untilReady(function()return not m.galleryBusy and imageCount()==#m.galleryItems end,10,'Extended gallery did not settle')
    screenshot('1440-extended')
    m.settings.resolution='1120x720';m.settings.uiScale=1.25;prefs:apply(true);wait(.2)
    untilReady(function()return not m.galleryBusy and imageCount()==#m.galleryItems end,10,'Responsive gallery page did not settle')
    local w,h=Layout.dimensions()
    for _,entry in ipairs(images)do if entry.id=='gallery-art'then check(entry.x>=0 and entry.y>=0 and entry.x+entry.w<=w and entry.y+entry.h<=h,'Artwork stays inside the smaller logical viewport')end end
    screenshot('1120-extended')
    local output=assert(io.open('/tmp/love2gathering-gallery-ui-report.json','w'));output:write(json.encode({checks=checks,scope='Actual LÖVE/Slab, real catalog HTTP and SQLite JPEG artwork; prepared Scryfall metadata/crops; artist URL launch intercepted only to avoid opening a test browser',logical={Layout.dimensions()},physical={love.graphics.getDimensions()}}));output:close()
    print('GALLERY UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down end
    love.system.openURL=function(url)opened[#opened+1]=url;return true end
    m=Model.new();r=Renderer.new(m);v=View.new(S,m,r);prefs=Preferences.new(m,S,r);v.preferences=prefs
    local originalButton=S.Button;S.Button=function(label,options)
        local dx,dy=Region.Transform(nil,0,0);local result=originalButton(label,options);local x,y,w,h=Cursor.GetItemBounds();buttons[label]={x=x+dx,y=y+dy,w=w,h=h};return result
    end
    local originalCombo=S.BeginComboBox;S.BeginComboBox=function(id,options)
        local dx,dy=Region.Transform(nil,0,0);local result=originalCombo(id,options);local x,y,w,h=Cursor.GetItemBounds();combos[id]={x=x+dx,y=y+dy,w=w,h=h};return result
    end
    local originalSelectable=S.TextSelectable;S.TextSelectable=function(label,options)
        local result=originalSelectable(label,options);local x,y,w,h=Cursor.GetItemBounds();selections[label]={x=x,y=y,w=w,h=h};return result
    end
    local originalImage=S.Image;S.Image=function(id,options)
        local result=originalImage(id,options);local x,y,w,h=Cursor.GetItemBounds();images[#images+1]={id=id,x=x,y=y,w=w,h=h,image=options.Image};return result
    end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    elapsed=elapsed+dt;assert(elapsed<65,'Gallery acceptance exceeded 65 seconds')
    m:update(dt);prefs:update();S.Update(dt);r:update(dt)
    if elapsed>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
    images={};v:build()
end
function love.draw()
    prefs:beginFrame();r:draw();prefs:endScene();S.Draw()
    if #shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)
        local output=assert(io.open('/tmp/love2gathering-gallery-'..name..'.png','wb'));output:write(data:encode('png'):getString());output:close()
    end)end
end
function love.quit()m:quit();S.OnQuit()end
