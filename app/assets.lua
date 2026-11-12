-- Runtime use of the curated Mana, Keyrune and Kenney assets.
local utf8=require('utf8')
local glyphs=require('assets.keyrune.glyphs')
local Assets={};Assets.__index=Assets
local unpack=unpack or table.unpack
local straightAlphaShader
local rasterWidth,rasterHeight
Assets.rasterEpoch=0
local colors={W={.98,.95,.78},U={.68,.83,.94},B={.67,.60,.64},R={.96,.57,.40},G={.55,.75,.60},C={.77,.77,.73}}
local aliases={WHITE='W',BLUE='U',BLACK='B',RED='R',GREEN='G',COLORLESS='C',TAP='T',UNTAP='Q',SNOW='S',ENERGY='E',PHYREXIAN='P',TK='TICKET',INFINITY='INFINITY',['∞']='INFINITY',['½']='1-2',HALF='1-2'}
local texturePaths={glow='assets/kenney/particles/circle_05.png',star='assets/kenney/particles/star_04.png'}
local schemes={cast={.43,.78,1},resolve={.55,1,.78},impact={1,.53,.32},click={.95,.85,.58}}
local function setcolor(c,a) love.graphics.setColor(c[1],c[2],c[3],a or c[4] or 1) end
local function image(path)
    local ok,result=pcall(love.graphics.newImage,path)
    if ok then result:setFilter('linear','linear');return result end
end
function Assets.new()
    local self=setmetatable({fonts={},textFonts={},particles={},sounds={},soundVoices={},maxParticles=180,iconCache={},iconClock=0,iconCacheLimit=96},Assets)
    self.panelImage=image('assets/kenney/ui/panel.png')
    self.textures={};for name,path in pairs(texturePaths) do self.textures[name]=image(path) end
    if self.panelImage then
        self.panelQuads={};local source=64;local border=8
        for row=1,3 do for col=1,3 do
            local x=col==1 and 0 or col==2 and border or source-border
            local y=row==1 and 0 or row==2 and border or source-border
            local w=col==2 and source-border*2 or border;local h=row==2 and source-border*2 or border
            self.panelQuads[#self.panelQuads+1]=love.graphics.newQuad(x,y,w,h,source,source)
        end end
    end
    self.ambient={path='assets/audio/music-loop-bundle-2026-q2/Week 19 - Dark Portents SHROUDED FUTURE.ogg',title='Dark Portents — Shrouded Future',artist='Abstraction',duration=33.423719}
    return self
end
function Assets:font(size,text)
    local cache=text and self.textFonts or self.fonts
    size=math.max(8,math.floor(size+.5))
    if not cache[size] then cache[size]=love.graphics.newFont(text and 'assets/fonts/DejaVuSans.ttf' or 'assets/keyrune/mana.ttf',size) end
    return cache[size]
end
function Assets:icon() return 'assets/icons/thb.png' end
function Assets:mana(symbol,x,y,size,tint)
    symbol=tostring(symbol or '')
    size=size or 18
    local tokens={};for token in symbol:gmatch('{([^}]+)}') do tokens[#tokens+1]=token end
    if #tokens>0 then
        local width=0
        for _,token in ipairs(tokens) do width=width+self:mana(token,x+width,y,size,tint)+2 end
        return math.max(0,width-2)
    end
    local code=symbol:upper():gsub('[{}%s]','');code=aliases[code] or code
    local first,second=code:match('^([^/]+)/([^/]+)$')
    local phyFirst,phySecond=code:match('^([^/]+)/([^/]+)/P$')
    local hybridPhyrexian=phyFirst~=nil
    if hybridPhyrexian then first,second=phyFirst,phySecond end
    local bg=colors[code] or (first and colors[first]) or {.78,.79,.79}
    love.graphics.push('all')
    setcolor(bg);love.graphics.circle('fill',x+size/2,y+size/2,size*.48)
    if second and second~='P' then
        setcolor(colors[second] or {.78,.79,.79})
        love.graphics.arc('fill','pie',x+size/2,y+size/2,size*.48,-math.pi/4,math.pi*.75,24)
    end
    setcolor({.04,.06,.07},.30);love.graphics.setLineWidth(1);love.graphics.circle('line',x+size/2,y+size/2,size*.48)
    local function drawGlyph(value,cx,cy,scale)
        local key=value:lower();if key=='t' then key='tap' elseif key=='q' then key='untap' end
        local point=glyphs[key];local font=self:font(size*scale,not point);love.graphics.setFont(font)
        local text=point and utf8.char(point) or value
        local fit=math.min(1,size*.82/math.max(1,font:getWidth(text)))
        setcolor(tint or {.055,.065,.07})
        love.graphics.print(text,cx-font:getWidth(text)*fit/2,cy-font:getHeight()*fit/2-size*.025,0,fit,fit)
    end
    if hybridPhyrexian then drawGlyph('P',x+size/2,y+size/2,.73)
    elseif first and second~='P' then
        drawGlyph(first,x+size*.33,y+size*.34,.47);drawGlyph(second,x+size*.67,y+size*.67,.47)
    else drawGlyph(second=='P' and 'P' or code,x+size/2,y+size/2,.73) end
    love.graphics.pop()
    return size
end
-- Canvas pixels are unpremultiplied once so Slab.Image's normal alpha blend
-- preserves antialiased edges instead of multiplying their alpha twice.
function Assets.rasterContext()
    local width,height=love.graphics.getDimensions()
    if width~=rasterWidth or height~=rasterHeight then
        Assets.rasterEpoch=Assets.rasterEpoch+1;rasterWidth,rasterHeight=width,height
    end
    return Assets.rasterEpoch,width,height
end
function Assets.invalidateRasterCaches()
    Assets.rasterEpoch=Assets.rasterEpoch+1
    rasterWidth,rasterHeight=love.graphics.getDimensions()
end
function Assets.rasterize(width,height,paint)
    width,height=math.max(1,math.ceil(width)),math.max(1,math.ceil(height))
    if not straightAlphaShader then
        straightAlphaShader=love.graphics.newShader([[
            vec4 effect(vec4 color, Image tex, vec2 uv, vec2 pixel) {
                vec4 value=Texel(tex,uv);
                if(value.a>0.00001) value.rgb/=value.a;
                return value*color;
            }
        ]])
    end
    local previous=love.graphics.getCanvas()
    local source=love.graphics.newCanvas(width,height)
    love.graphics.push('all');love.graphics.setCanvas(source);love.graphics.origin();love.graphics.setScissor();love.graphics.clear(0,0,0,0)
    love.graphics.setShader();love.graphics.setBlendMode('alpha','alphamultiply')
    local ok,err=pcall(paint)
    if not ok then love.graphics.setCanvas(previous);love.graphics.pop();error(err,0) end
    local output=love.graphics.newCanvas(width,height)
    love.graphics.setCanvas(output);love.graphics.clear(0,0,0,0);love.graphics.origin();love.graphics.setScissor()
    love.graphics.setBlendMode('replace','premultiplied');love.graphics.setShader(straightAlphaShader);love.graphics.setColor(1,1,1,1);love.graphics.draw(source)
    love.graphics.setCanvas(previous);love.graphics.pop();output:setFilter('linear','linear')
    return output
end
local iconAliases={command='commander',deck='library',lands='land',creatures='creature',artifacts='artifact',instants='instant',sorceries='sorcery',enchantments='enchantment',planeswalkers='planeswalker',flying='ability-flying',haste='ability-haste',trample='ability-trample',deathtouch='ability-deathtouch',lifelink='ability-lifelink',hexproof='ability-hexproof'}
local function vectorIcon(name)
    local g=love.graphics
    if name=='play' then g.polygon('fill',7,4,21,12,7,20)
    elseif name=='pause' then g.rectangle('fill',6,4,4,16,1,1);g.rectangle('fill',14,4,4,16,1,1)
    elseif name=='close' or name=='remove' then g.line(5,5,19,19);g.line(19,5,5,19)
    elseif name=='plus' or name=='add' then g.line(4,12,20,12);g.line(12,4,12,20)
    elseif name=='minus' then g.line(4,12,20,12)
    elseif name=='check' or name=='validate' then g.line(4,12,9,17,20,5)
    elseif name=='back' or name=='previous' or name=='arrow-left' then g.line(16,4,8,12,16,20)
    elseif name=='next' or name=='arrow-right' then g.line(8,4,16,12,8,20)
    elseif name=='search' then g.circle('line',10,10,6);g.line(14.5,14.5,21,21)
    elseif name=='settings' then
        local vertices={}
        for i=0,31 do local a=i*math.pi/16;local radius=(i%4==0 or i%4==3) and 10 or 8;vertices[#vertices+1]=12+math.cos(a)*radius;vertices[#vertices+1]=12+math.sin(a)*radius end
        g.polygon('line',unpack(vertices));g.circle('line',12,12,3.2)
    elseif name=='save' then
        g.polygon('line',3,3,18,3,21,6,21,21,3,21);g.rectangle('line',7,3,9,7);g.rectangle('line',7,15,10,6)
    elseif name=='edit' then g.polygon('line',5,15,15,5,19,9,9,19,4,20);g.line(13,7,17,11)
    elseif name=='filter' then g.polygon('line',3,4,21,4,14,12,14,20,10,18,10,12)
    elseif name=='sort' then g.line(4,5,20,5);g.line(7,11,17,11);g.line(10,17,14,17)
    elseif name=='lobby' then g.rectangle('line',5,3,14,18,2,2);g.circle('fill',15,12,1)
    elseif name=='home' then g.line(2,11,12,3,22,11);g.line(5,10,5,21,10,21,10,14,15,14,15,21,19,21,19,10)
    elseif name=='log' then g.rectangle('line',3,3,18,18,2,2);g.line(7,7,17,7);g.line(7,12,17,12);g.line(7,17,14,17)
    elseif name=='stack' then g.polygon('line',2,8,12,3,22,8,12,13);g.line(3,12,12,17,21,12);g.line(3,16,12,21,21,16)
    elseif name=='replay' then g.arc('line','open',12,12,8,math.pi*.3,math.pi*1.9,28);g.polygon('fill',19,2,22,10,14,8)
    elseif name=='concede' then g.line(5,22,5,3);g.polygon('line',5,3,19,3,16,8,19,13,5,13)
    elseif name=='ability' then g.polygon('line',12,2,14.5,9.5,22,12,14.5,14.5,12,22,9.5,14.5,2,12,9.5,9.5)
    elseif name=='damage' then g.polygon('fill',13,2,5,14,11,14,9,22,20,9,13,9)
    elseif name=='attack' then g.line(4,20,18,6);g.line(4,14,10,20);g.polygon('line',13,5,20,3,18,10);g.line(4,4,20,20);g.line(14,20,20,14)
    elseif name=='turn' then g.arc('line','open',12,12,8,math.pi*.2,math.pi*1.8,28);g.polygon('fill',17,2,22,9,14,8)
    elseif name=='draw' then g.rectangle('line',3,8,12,14,2,2);g.line(7,4,19,4,19,18);g.line(13,1,22,1,22,14)
    elseif name=='image' or name=='cover' then g.rectangle('line',3,3,18,18,2,2);g.circle('line',8,8,2);g.line(4,18,10,11,14,16,18,12,21,16)
    elseif name=='sideboard' or name=='copy' then g.rectangle('line',4,6,12,15,2,2);g.line(8,3,20,3,20,18)
    elseif name=='info' then g.circle('line',12,12,9);g.circle('fill',12,7,1);g.line(12,11,12,17)
    elseif name=='warning' then g.polygon('line',12,3,22,21,2,21);g.line(12,9,12,14);g.circle('fill',12,18,1)
    else return false end
    return true
end
function Assets:iconSymbol(name,x,y,size,tint)
    size=size or 20;name=tostring(name or ''):lower():gsub('_','-');name=iconAliases[name] or name
    if name:match('^{') or name:match('^[wubrgcxyzstqep]$') or name:match('^%d+$') or name:find('/',1,true) then return self:mana(name,x,y,size,tint) end
    love.graphics.push('all');setcolor(tint or {.86,.92,.98});love.graphics.setLineWidth(math.max(1,size/13))
    local point=glyphs[name]
    if point then
        local font=self:font(size*.90);local glyph=utf8.char(point);love.graphics.setFont(font)
        love.graphics.print(glyph,x+(size-font:getWidth(glyph))/2,y+(size-font:getHeight())/2)
    else
        love.graphics.translate(x,y);love.graphics.scale(size/24);love.graphics.setLineWidth(1.75)
        if not vectorIcon(name) then love.graphics.pop();return 0 end
    end
    love.graphics.pop();return size
end
local function trimIconCache(self)
    local count=0;for _ in pairs(self.iconCache)do count=count+1 end
    while count>self.iconCacheLimit do
        local oldest,oldestTime
        for key,entry in pairs(self.iconCache)do if not oldestTime or entry.used<oldestTime then oldest,oldestTime=key,entry.used end end
        self.iconCache[oldest]=nil;count=count-1
    end
end
function Assets:iconImage(symbol,size,tint)
    size=size or 20
    local layout=package.loaded['app.layout'];local scale=layout and layout.scale or 1
    local epoch=Assets.rasterContext()
    local color=tint or {.86,.92,.98,1};local key=table.concat({epoch,symbol,size,tint and 'tint' or 'auto',string.format('%.5f',scale),unpack(color)},'|')
    self.iconClock=self.iconClock+1
    local cached=self.iconCache[key];if cached then cached.used=self.iconClock;return cached.image end
    local canvas=Assets.rasterize(size*scale,size*scale,function()love.graphics.scale(scale);self:iconSymbol(symbol,0,0,size,tint)end)
    self.iconCache[key]={image=canvas,used=self.iconClock}
    trimIconCache(self)
    return canvas
end
function Assets:buttonImage(symbol,label,width,height,opts)
    opts=opts or {};local size=opts.size or 16;local font=opts.font or self:font(size,true)
    local iconSize=opts.iconSize or 20;local gap=opts.gap or 7;local text=tostring(label or '')
    local available=math.max(8,width-iconSize-gap-12)
    if font:getWidth(text)>available then
        while #text>0 and font:getWidth(text..'…')>available do local last=utf8.offset(text,-1);text=text:sub(1,last-1)end
        text=text..'…'
    end
    local layout=package.loaded['app.layout'];local scale=layout and layout.scale or 1
    local epoch=Assets.rasterContext()
    local tint=opts.color or {.9,.94,.98,1};local iconTint=opts.iconTint
    local key=table.concat({'button',epoch,symbol,label,width,height,tostring(font),iconSize,gap,string.format('%.5f',scale),table.concat(tint,','),iconTint and table.concat(iconTint,',') or 'auto'},'|')
    self.iconClock=self.iconClock+1;local cached=self.iconCache[key]
    if cached then cached.used=self.iconClock;return cached.image end
    local canvas=Assets.rasterize(width*scale,height*scale,function()
        love.graphics.scale(scale);local total=iconSize+gap+font:getWidth(text);local left=math.max(6,(width-total)/2)
        self:iconSymbol(symbol,left,(height-iconSize)/2,iconSize,iconTint)
        love.graphics.setFont(font);setcolor(tint);love.graphics.print(text,left+iconSize+gap,(height-font:getHeight())/2)
    end)
    self.iconCache[key]={image=canvas,used=self.iconClock}
    trimIconCache(self)
    return canvas
end
function Assets:panel(x,y,w,h,style)
    local tint=type(style)=='table' and style or style=='accent' and {.13,.29,.31,1} or {.09,.13,.19,1}
    love.graphics.push('all');setcolor(tint)
    if not self.panelImage then love.graphics.rectangle('fill',x,y,w,h,8,8);love.graphics.pop();return end
    local border=math.min(8,w/2,h/2);local widths={border,math.max(0,w-border*2),border};local heights={border,math.max(0,h-border*2),border}
    local dy=y;local index=0
    for row=1,3 do
        local dx=x
        for col=1,3 do
            index=index+1;local quad=self.panelQuads[index];local _,_,sw,sh=quad:getViewport()
            if widths[col]>0 and heights[row]>0 then love.graphics.draw(self.panelImage,quad,dx,dy,0,widths[col]/sw,heights[row]/sh) end
            dx=dx+widths[col]
        end
        dy=dy+heights[row]
    end
    love.graphics.pop()
end
function Assets:particle(kind,x,y,count)
    local scheme=schemes[kind] or schemes.resolve
    count=math.min(count or (kind=='impact' and 16 or 10),36)
    for i=1,count do
        if #self.particles>=self.maxParticles then table.remove(self.particles,1) end
        local angle=love.math.random()*math.pi*2;local speed=24+love.math.random()*74
        local life=.35+love.math.random()*.45
        self.particles[#self.particles+1]={x=x,y=y,vx=math.cos(angle)*speed,vy=math.sin(angle)*speed-14,life=life,maxLife=life,color=scheme,size=kind=='impact' and 22+love.math.random()*22 or 8+love.math.random()*18,rotation=love.math.random()*math.pi,texture=i%3==0 and 'star' or 'glow'}
    end
end
function Assets:update(dt)
    dt=math.min(dt,.1)
    for i=#self.particles,1,-1 do
        local p=self.particles[i];p.life=p.life-dt
        if p.life<=0 then table.remove(self.particles,i) else p.x=p.x+p.vx*dt;p.y=p.y+p.vy*dt;p.vy=p.vy+12*dt;p.rotation=p.rotation+dt*.6 end
    end
    for i=#self.soundVoices,1,-1 do if not self.soundVoices[i]:isPlaying() then table.remove(self.soundVoices,i) end end
end
function Assets:drawParticles()
    love.graphics.push('all');love.graphics.setBlendMode('add','alphamultiply')
    for _,p in ipairs(self.particles) do
        local texture=self.textures[p.texture];local alpha=(p.life/p.maxLife)^1.4
        setcolor(p.color,alpha*.75)
        if texture then
            local scale=p.size/texture:getWidth();love.graphics.draw(texture,p.x,p.y,p.rotation,scale,scale,texture:getWidth()/2,texture:getHeight()/2)
        else love.graphics.circle('fill',p.x,p.y,p.size*.12) end
    end
    love.graphics.pop()
end
function Assets:playSound(kind,volume)
    if not love.audio or (volume or 0.25)<=0 then return end
    local name=kind=='cast' and 'cast' or (kind=='resolve' or kind=='impact') and 'resolve' or 'click'
    if self.sounds[name]==false then return end
    if not self.sounds[name] then
        local ok,source=pcall(love.audio.newSource,'assets/kenney/sounds/'..name..'.ogg','static')
        if not ok then self.sounds[name]=false;return end
        self.sounds[name]=source
    end
    if #self.soundVoices>=12 then return end
    local source=self.sounds[name]:clone();source:setVolume(math.max(0,math.min(1,volume or .25)))
    local ok=pcall(source.play,source);if ok then self.soundVoices[#self.soundVoices+1]=source end
end
return Assets
