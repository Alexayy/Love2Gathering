local Assets=require('app.assets');local Fonts=require('app.fonts');local Preferences=require('app.preferences')
local Theme=require('app.theme');local Settings=require('app.settings');local S=require('lib.Slab');local Layout=require('app.layout')
local Json=require('lib.json');local glyphs=require('assets.keyrune.glyphs');local utf8=require('utf8')
local m,r,v,prefs,frame= nil,nil,nil,nil,0
local uiSounds=0
local checks,labels=0,{};local controls,buttons,choices={},{},{};local mouse={x=2,y=2};local down=false
local function check(ok,label)assert(ok,label);checks=checks+1;labels[#labels+1]=label;print('ASSET PRESENTATION PASS '..label)end
local function save(path,data)local f=assert(io.open(path,'wb'));f:write(data);f:close()end
local function coverage(canvas)local d=canvas:newImageData();local n=0;for y=0,d:getHeight()-1 do for x=0,d:getWidth()-1 do local _,_,_,a=d:getPixel(x,y);if a>.1 then n=n+1 end end end;return n end
local function click(box,pressed)
    assert(box,'Missing actual settings control');mouse.x,mouse.y=(box.x+box.w/2)*Layout.scale,(box.y+box.h/2)*Layout.scale;down=pressed
    S.OnMouseMoved(mouse.x,mouse.y,0,0)
    if pressed then S.OnMousePressed(mouse.x,mouse.y,1,false,1)else S.OnMouseReleased(mouse.x,mouse.y,1,false,1)end
end
function love.errorhandler(message)
    io.stderr:write('ASSET PRESENTATION FAILED '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
function love.load()
    S.SetINIStatePath(nil);S.Initialize({},true)
    local fonts,bold=Fonts.createSet(Fonts.default,{10,11,12,13,14,16,18,20,22,24,28,32,36,44,52})
    r={assets=Assets.new(),fonts=fonts,bold=bold,colors={text={.90,.94,.98},muted={.56,.65,.73},accent={.28,.89,.72}}}
    m={settings={resolution='1440x900',windowMode='Windowed'},toasts={},toast=function(self,s)self.toasts[#self.toasts+1]=s end,saveSettings=function(self)self.saved=true end,showProfile=function(self)self.profileShown=true end}
    prefs=Preferences.new(m,S,r);prefs:applyFont();Theme.install(S,r.assets)
    check(m.settings.titleFontFamily=='Beleren'and m.settings.fontFamily=='Beleren','Beleren is the required body and heading typeface')
    local title,family=r.assets:titleFont(22,m.settings)
    check(family=='Beleren'and title==Fonts.title(22,'Beleren')and title==r.fonts[22],'The actual supplied Beleren font loads and is cached for titles')
    check(title:hasGlyphs('Magic Čarobna šuma 0123'),'Beleren titles retain UTF-8 via the bundled fallback')
    local custom=Fonts.names()[2]or Fonts.default;local appTitle,effective=Fonts.title(22,'Application font',custom)
    check(effective=='Beleren'and appTitle==title,'Legacy title-font choices retain the required Beleren typeface')
    local realInfo=love.filesystem.getInfo;love.filesystem.getInfo=function(path,...)if path=='assets/fonts/Beleren2016-Bold.ttf'then return nil end;return realInfo(path,...)end
    local _,fallback=Fonts.title(23,'Beleren');love.filesystem.getInfo=realInfo
    check(fallback=='Built-in DejaVu Sans','Missing display-font files fall back safely without affecting body copy')
    Fonts.clearCache()
    local n=0;for name,spec in pairs(Assets.runtime.icons)do
        local d=love.image.newImageData(spec.path);check(d:getWidth()==spec.width and d:getHeight()==spec.height and coverage(r.assets:iconImage(name,28))>40,'Supplied icon renders with source alpha: '..name);n=n+1
    end
    check(n==31,'The semantic icon selection is bounded and provenance-backed')
    local keywords={'flying','hexproof','trample','haste','deathtouch','lifelink','defender','double-strike','first-strike','flash','indestructible','menace','reach','surveil','vigilance','ward'}
    for _,name in ipairs(keywords)do check(r.assets:font(24):hasGlyphs(utf8.char(glyphs['ability-'..name]))and coverage(r.assets:iconImage(name,28))>15,'Verified existing Mana keyword glyph: '..name)end
    local function bg(name,brightness,w,h)return Assets.rasterize(w or 300,h or 170,function()r.assets:background(w or 300,h or 170,{skybox=name,skyboxBrightness=brightness})end)end
    local bright=bg('Galaxy',1):newImageData();local dim=bg('Galaxy',.25):newImageData();local br,bg_,bb=bright:getPixel(150,85);local dr,dg,db=dim:getPixel(150,85)
    check(math.abs(dr-br*.25)<.01 and math.abs(dg-bg_*.25)<.01 and math.abs(db-bb*.25)<.01,'Background brightness changes actual panorama pixels')
    for _,name in ipairs({'Nebula','Band','Dark','Day'})do check(coverage(bg(name,.4,180,300))==180*300,'Portrait panorama crop fills all pixels: '..name)end
    local count=0;for _ in pairs(r.assets.skyboxes)do count=count+1 end;check(count==2,'Decoded panorama cache retains only two images')
    check(coverage(bg('Off',1))==0,'Off leaves the existing background untouched')
    local one=Assets.rasterize(44,44,function()r.assets:counterBadge(1,0,0,44,'Dice')end)
    local seven=Assets.rasterize(44,44,function()r.assets:counterBadge(7,0,0,44,'Dice')end)
    check(one:newImageData():getString()~=seven:newImageData():getString(),'Counters above six display their actual number rather than wrapping dice')
    check(coverage(Assets.rasterize(44,44,function()r.assets:counterBadge(127,0,0,44,'Text')end))<coverage(seven),'Text counters omit the dice surface')
    for name,spec in pairs(Assets.runtime.sounds)do local data=love.sound.newSoundData(spec.path);check(data:getDuration()>0 and data:getDuration()<4 and data:getChannelCount()<=2,'Actual short supplied sound decodes: '..name)end
    for i=1,20 do r.assets:playSound(i%2==0 and'click'or'cast',.01)end
    check(#r.assets.soundVoices<=12 and r.assets.sounds.cast and r.assets.sounds.click,'Actual sound playback caches distinct effects and bounds voices')
    m.settings.cursorStyle='Kenney';love.mouse.setCursor(love.mouse.getSystemCursor('arrow'));prefs:endFrame()
    check(prefs.customCursorActive and love.mouse.getCursor():getType()=='image','Kenney pointer replaces the actual system arrow with its reviewed hotspot')
    love.mouse.setCursor(love.mouse.getSystemCursor('ibeam'));prefs:endFrame()
    check(love.mouse.getCursor():getType()=='ibeam','Text-entry cursor remains native')
    love.mouse.setCursor(love.mouse.getSystemCursor('hand'));prefs:endFrame();check(prefs.customCursorActive and love.mouse.getCursor():getType()=='image','Kenney pointing hand applies after Slab cursor selection')
    m.settings.cursorStyle='System';prefs:endFrame();check(love.mouse.getCursor():getType()=='hand','Returning to System restores the native cursor')
    local newCursor=love.mouse.newCursor;love.mouse.newCursor=function()error('Unsupported cursor fixture')end;prefs.cursors={};m.settings.cursorStyle='Kenney';love.mouse.setCursor(love.mouse.getSystemCursor('arrow'))
    local ok=pcall(prefs.applyCursor,prefs);love.mouse.newCursor=newCursor;m.settings.cursorStyle='System';check(ok and not prefs.customCursorActive,'Unsupported custom cursor falls back without a crash')
    local play=r.assets.playSound;r.assets.playSound=function(self,kind,volume)uiSounds=uiSounds+1;return play(self,kind,volume)end
    v={S=S,m=m,r=r,preferences=prefs,settingsTab='Accessibility'}
    function v:window(id,x,y,w,h,title)S.BeginWindow(id,{X=x,Y=y,W=w,H=h,Title=title,AutoSizeWindow=false,AllowMove=false,AllowResize=false})end
    function v:combo(id,selected,items,width,changed)if S.BeginComboBox(id,{Selected=tostring(selected),W=width})then for _,item in ipairs(items)do if S.TextSelectable(tostring(item),{Selected=item==selected})then changed(item)end end;S.EndComboBox()end end
    local Cursor=require('lib.Slab.Internal.Core.Cursor')
    for _,name in ipairs({'BeginComboBox','TextSelectable','Button'})do local original=S[name];S[name]=function(id,options)local result=original(id,options);local x,y,w,h=Cursor.GetItemBounds();local t=name=='BeginComboBox'and controls or name=='TextSelectable'and choices or buttons;t[id]={x=x,y=y,w=w,h=h};return result end end
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down or false end
end
function love.update(dt)
    frame=frame+1
    if frame==7 then click(controls['setting-cursorStyle'],true)
    elseif frame==8 then click(controls['setting-cursorStyle'],false)
    elseif frame==11 then click(choices.Kenney,true)
    elseif frame==12 then click(choices.Kenney,false)
    elseif frame==15 then check(m.settings.cursorStyle=='Kenney','Actual nested settings combo selects the supplied pointer style');click(controls['setting-uiScale'],true)
    elseif frame==16 then click(controls['setting-uiScale'],false)
    elseif frame==19 then click(choices['0.85'],true)
    elseif frame==20 then click(choices['0.85'],false)
    elseif frame==23 then check(m.settings.uiScale==.85,'Actual nested settings combo selects interface scale');click(buttons['Apply and save'],true)
    elseif frame==24 then click(buttons['Apply and save'],false)
    elseif frame==27 then check(m.saved and not m.settingsOpen,'Actual Apply dispatches presentation settings persistence')
    elseif frame==28 then mouse.x,mouse.y=1,1
    elseif frame==31 then
        check(uiSounds==3,'Themed controls play one sound per accepted selection or button activation')
        m.settings.sfxEnabled=false
    elseif frame==32 then click(buttons.Close,true)
    elseif frame==33 then
        click(buttons.Close,false);check(uiSounds==3,'Disabled sound setting suppresses actual themed button audio')
        local function entry()return{image=love.graphics.newImage(love.image.newImageData(2,2))}end
        m.art={card=entry()};m.profileImages={playmat=entry()};m.galleryArt={printing=entry()}
        local function filtered(value)for _,cache in ipairs({m.art,m.profileImages,m.galleryArt})do for _,item in pairs(cache)do local min,mag=item.image:getFilter();if min~=value or mag~=value then return false end end end;return true end
        m.settings.textureFilter='nearest';prefs:apply(false);check(filtered('nearest'),'Texture filtering updates actual cached card, profile/playmat and Gallery images')
        m.settings.textureFilter='linear';prefs:apply(false);check(filtered('linear'),'Returning to smooth filtering updates all existing artwork caches')
    elseif frame==34 then
        save('/tmp/love2gathering-assets-presentation-report.json',Json.encode({passed=checks,checks=labels,scope='Real LÖVE pixels/audio/cursors and Slab settings input; no engine game'}));print('ASSET PRESENTATION COMPLETE '..checks..' checks');love.event.quit(0)
    end
    S.Update(dt);if frame>=5 then Settings.build(v,Layout.dimensions())end
end
function love.draw()
    love.graphics.clear(.026,.036,.06,1);r.assets:background(1440,900,m.settings)
    if frame<5 then
        r.assets:panel(55,45,1330,810,'dark');love.graphics.setColor(.9,.94,.98);love.graphics.setFont(r.assets:titleFont(36,m.settings));love.graphics.print('Love: 2 Gathering · Beleren',90,70)
        love.graphics.setFont(r.fonts[16]);love.graphics.print('Supplied Kenney icons · dark mint and purple · native exact counter values',90,125)
        local names={};for name in pairs(Assets.runtime.icons)do names[#names+1]=name end;table.sort(names)
        for i,name in ipairs(names)do local x=90+(i-1)%8*155;local y=185+math.floor((i-1)/8)*105;r.assets:iconSymbol(name,x,y,38,{.4,.93,.78});love.graphics.setColor(.8,.86,.9);love.graphics.print(name,x,y+48)end
        for i,value in ipairs({1,2,3,4,5,6,7,13,127})do local x=100+(i-1)*130;r.assets:counterBadge(value,x,660,50,'Dice');love.graphics.setColor(.8,.86,.9);love.graphics.print(tostring(value),x+15,720)end
        if frame==3 then love.graphics.captureScreenshot(function(d)save('/tmp/love2gathering-assets-presentation.png',d:encode('png'):getString())end)end
    end
    S.Draw();prefs:endFrame()
    if frame==22 then love.graphics.captureScreenshot(function(d)save('/tmp/love2gathering-assets-settings.png',d:encode('png'):getString())end)end
end
function love.quit()prefs:quit();S.OnQuit()end
