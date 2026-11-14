local Layout=require('app.layout')
local Fonts=require('app.fonts')
local Preferences={};Preferences.__index=Preferences
local defaults={resolution='Desktop',windowMode='Borderless',vsync=true,msaa=0,renderScale=1,textureFilter='linear',frameLimit=0,uiScale=1,
    animations=true,particles=true,localArtworkOnly=true,musicEnabled=false,musicVolume=.25,sfxEnabled=true,sfxVolume=.45,masterVolume=.7,
    reducedMotion=false,highContrast=false,colorblindMode='Off',showTooltips=true,fontFamily=Fonts.default,titleFontFamily='Beleren',
    skybox='Galaxy',skyboxBrightness=.32,playmatOpacity=.88,counterStyle='Dice',cursorStyle='Kenney',keywordReminders=true,
    panelOpacity=.65,theme='Midnight',accentColor='',opponentColor='',autoFollowTurn=true,builderLayout='Classic',presentationVersion=2}
Preferences.defaults=defaults
function Preferences.new(model,S,renderer)
    for k,v in pairs(defaults) do if model.settings[k]==nil then model.settings[k]=v end end
    if renderer and renderer.assets then renderer.assets:setSettings(model.settings)end
    return setmetatable({m=model,S=S,r=renderer},Preferences)
end
function Preferences:applyFont()
    local family=Fonts.default
    self.m.settings.fontFamily=family;self.m.settings.titleFontFamily=family
    if not self.r then return end
    self.r.assets:setSettings(self.m.settings)
    local titles=self.m.settings.titleFontFamily or Fonts.titleDefault
    if self.titleSignature~=titles then self.titleSignature=titles;require('app.assets').invalidateRasterCaches() end
    if family==self.fontSignature then return end
    self.fontSignature=family
    local sizes={};for size in pairs(self.r.fonts) do sizes[#sizes+1]=size end;table.sort(sizes)
    local fonts,bold,problem,effective=Fonts.createSet(family,sizes)
    self.r.fonts,self.r.bold=fonts,bold
    self.S.GetStyle().Font=fonts[16]
    self.r.assets.textFonts=fonts
    require('app.assets').invalidateRasterCaches()
    self.appliedFontFamily=effective
    if problem then self.m:toast(problem,true) end
end
function Preferences:applyCursor()
    if not love.mouse or not love.mouse.getCursor or not love.mouse.setCursor then return end
    local enabled=self.m.settings.cursorStyle=='Kenney'
    if not enabled then
        if self.customCursorActive then
            pcall(function()love.mouse.setCursor(love.mouse.getSystemCursor(self.cursorNativeType or 'arrow'))end)
            self.customCursorActive=false
        end
        return
    end
    local ok,current=pcall(love.mouse.getCursor);if not ok then return end
    local kind=current and current:getType()or 'arrow'
    if kind=='image' then kind=self.cursorNativeType or 'arrow'else self.cursorNativeType=kind end
    if self.r and not self.r.uiHovered then
        local state=self.r.assets.cursorState
        if self.r.drag or self.r.panGesture or state=='drag'then kind='drag'
        elseif state=='pan'then kind='pan'
        elseif self.r.hover and(self.r.hover.action or self.r.hover.kind=='player')then kind='hand'end
    end
    self.cursorType=kind;self.cursors=self.cursors or {}
    local have,manifest=pcall(require,'assets.kenney.runtime.manifest')
    if not have or not manifest.cursors[kind]then self.customCursorActive=false;return end
    if self.cursors[kind]==nil then
        local success,cursor=pcall(function()
            local spec=require('assets.kenney.runtime.manifest').cursors[kind]
            return love.mouse.newCursor(spec.path,spec.hotspot[1],spec.hotspot[2])
        end)
        self.cursors[kind]=success and cursor or false
    end
    if self.cursors[kind] then
        local success=pcall(love.mouse.setCursor,self.cursors[kind]);self.customCursorActive=success
    end
end
function Preferences:apply(force)
    local s=self.m.settings
    for k,v in pairs(defaults) do if s[k]==nil then s[k]=v end end
    local signature=table.concat({s.resolution,s.windowMode,tostring(s.vsync),s.msaa},'|')
    if signature~=self.windowSignature then
        self.windowSignature=signature
        if force or s.resolution~='1440x900' or s.windowMode~='Windowed' or not s.vsync or s.msaa~=0 then
            local width,height=tostring(s.resolution):match('^(%d+)x(%d+)$');width,height=tonumber(width),tonumber(height)
            local _,_,flags=love.window.getMode();local _,_,currentDisplay=love.window.getPosition()
            local display=flags.display or currentDisplay or 1
            if s.resolution=='Desktop'then width,height=love.window.getDesktopDimensions(display)end
            if width and height then
                local ok,message=love.window.setMode(width,height,{resizable=true,minwidth=1120,minheight=720,vsync=s.vsync and 1 or 0,msaa=s.msaa,
                    fullscreen=s.windowMode~='Windowed',fullscreentype=s.windowMode=='Borderless' and 'desktop' or 'exclusive',display=display})
                if ok then require('app.assets').invalidateRasterCaches()
                else self.m:toast('Could not apply display mode: '..tostring(message),true) end
            end
        end
    end
    love.graphics.setDefaultFilter(s.textureFilter,s.textureFilter)
    for _,cache in ipairs({self.m.art or{},self.m.profileImages or{},self.m.galleryArt or{}})do
        for _,entry in pairs(cache)do if entry.image then entry.image:setFilter(s.textureFilter,s.textureFilter)end end
    end
    self.S.SetScale(Layout.setScale(s.uiScale))
    if self.r then require('app.theme').apply(self.S,self.r.assets,s)end
    self:applyFont()
    self:applyCursor()
    if love.audio then love.audio.setVolume(s.masterVolume) end
    self:updateMusic()
end
function Preferences:updateMusic()
    if not love.audio then return end
    local s=self.m.settings
    if s.musicEnabled and not self.music then
        local path='assets/audio/music-loop-bundle-2026-q2/Week 19 - Dark Portents SHROUDED FUTURE.ogg'
        if love.filesystem.getInfo(path) then
            local ok,source=pcall(love.audio.newSource,path,'stream')
            if ok then self.music=source;source:setLooping(true) else self.musicFailed=true end
        end
    end
    if self.music then
        self.music:setVolume(s.musicVolume)
        if s.musicEnabled and not self.music:isPlaying() then self.music:play() elseif not s.musicEnabled then self.music:pause() end
    end
end
function Preferences:update()
    local s=self.m.settings
    self.S.SetScale(Layout.setScale(s.uiScale or 1))
    if self.r then require('app.theme').apply(self.S,self.r.assets,s)end
    if not self.appliedLoaded and self.m.settingsLoaded then self.appliedLoaded=true;self:apply(true) end
end
function Preferences:beginFrame()
    local w,h=love.graphics.getDimensions();local scale=self.m.settings.renderScale or 1
    if math.abs(scale-1)>.01 then
        local cw,ch=math.floor(w*scale),math.floor(h*scale)
        if not self.canvas or self.canvas:getWidth()~=cw or self.canvas:getHeight()~=ch then self.canvas=love.graphics.newCanvas(cw,ch) end
        love.graphics.setCanvas(self.canvas);love.graphics.clear(.026,.036,.06,1);love.graphics.push();love.graphics.scale(scale)
        Layout.renderScale=scale
    else Layout.renderScale=1 end
    love.graphics.push();love.graphics.scale(Layout.scale)
end
function Preferences:endScene()
    love.graphics.pop()
    if Layout.renderScale~=1 then
        love.graphics.pop();love.graphics.setCanvas();love.graphics.setColor(1,1,1,1)
        love.graphics.draw(self.canvas,0,0,0,1/Layout.renderScale,1/Layout.renderScale)
    end
    Layout.renderScale=1
end
-- Slab may select a system hand/text/resize cursor during Draw. Replace only
-- its arrow/hand afterwards, preserving all native text and resize feedback.
function Preferences:endFrame()self:applyCursor()end
function Preferences:limitFrame(start)
    local cap=self.m.settings.frameLimit or 0
    if cap>0 then local remaining=1/cap-(love.timer.getTime()-start);if remaining>0 then love.timer.sleep(remaining) end end
end
function Preferences:quit()
    if self.music then self.music:stop() end
    if self.customCursorActive and love.mouse then pcall(love.mouse.setCursor)end
end
return Preferences
