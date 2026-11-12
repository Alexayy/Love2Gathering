local Layout=require('app.layout')
local Preferences={};Preferences.__index=Preferences
local defaults={resolution='1440x900',windowMode='Windowed',vsync=true,msaa=0,renderScale=1,textureFilter='linear',frameLimit=0,uiScale=1,
    animations=true,particles=true,musicEnabled=false,musicVolume=.25,sfxEnabled=true,sfxVolume=.45,masterVolume=.7,
    reducedMotion=false,highContrast=false,colorblindMode='Off',showTooltips=true}
Preferences.defaults=defaults
function Preferences.new(model,S)
    for k,v in pairs(defaults) do if model.settings[k]==nil then model.settings[k]=v end end
    return setmetatable({m=model,S=S},Preferences)
end
function Preferences:apply(force)
    local s=self.m.settings
    for k,v in pairs(defaults) do if s[k]==nil then s[k]=v end end
    local signature=table.concat({s.resolution,s.windowMode,tostring(s.vsync),s.msaa,s.textureFilter},'|')
    if signature~=self.windowSignature then
        self.windowSignature=signature
        if force or s.resolution~='1440x900' or s.windowMode~='Windowed' or not s.vsync or s.msaa~=0 then
            local width,height=s.resolution:match('^(%d+)x(%d+)$');width,height=tonumber(width),tonumber(height)
            if width and height then
                local ok,message=love.window.setMode(width,height,{resizable=true,minwidth=1120,minheight=720,vsync=s.vsync and 1 or 0,msaa=s.msaa,
                    fullscreen=s.windowMode~='Windowed',fullscreentype=s.windowMode=='Borderless' and 'desktop' or 'exclusive'})
                if ok then require('app.assets').invalidateRasterCaches()
                else self.m:toast('Could not apply display mode: '..tostring(message),true) end
            end
        end
    end
    love.graphics.setDefaultFilter(s.textureFilter,s.textureFilter)
    for _,entry in pairs(self.m.art or {}) do if entry.image then entry.image:setFilter(s.textureFilter,s.textureFilter) end end
    self.S.SetScale(Layout.setScale(s.uiScale))
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
function Preferences:endFrame() end
function Preferences:limitFrame(start)
    local cap=self.m.settings.frameLimit or 0
    if cap>0 then local remaining=1/cap-(love.timer.getTime()-start);if remaining>0 then love.timer.sleep(remaining) end end
end
function Preferences:quit() if self.music then self.music:stop() end end
return Preferences
