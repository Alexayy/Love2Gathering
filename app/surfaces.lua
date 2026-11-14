-- Curated Kenney surfaces and separately attributed user-supplied card backs.
local manifest=require('assets.kenney.runtime.manifest')
local Surfaces={};Surfaces.__index=Surfaces
local suppliedBacks={
    ['Classic Magic']={path='assets/card-backs/classic-magic.jpg',fit=true},
    ['Mystic Eye']={path='assets/card-backs/mystic-eye.png',fit=true},
}
Surfaces.cardBackNames={'Arcane','Azure','Verdant','Crimson','Classic Magic','Mystic Eye'}
function Surfaces.cardBackSpec(style)
    local specs=manifest.cardBacks or{}
    return suppliedBacks[style]or specs[style or'Arcane']or specs.Arcane
end
function Surfaces.new()return setmetatable({images={},quads={},stats={}},Surfaces)end
function Surfaces:load(spec)
    if not spec then return end
    local entry=self.images[spec.path]
    if entry==nil then
        local ok,value=pcall(love.graphics.newImage,spec.path);entry=ok and value or false
        if entry then entry:setFilter('linear','linear')end
        self.images[spec.path]=entry
    end
    return entry or nil
end
function Surfaces:mask(name,x,y,w,h,tint,tiled)
    local spec=manifest.surfaces and manifest.surfaces[name];local img=self:load(spec)
    if not img or w<=0 or h<=0 then return false end
    if not self.maskShader then self.maskShader=love.graphics.newShader([[
        vec4 effect(vec4 tint, Image texture, vec2 uv, vec2 pixel) {
            vec4 source=Texel(texture,uv);
            return vec4(tint.rgb,tint.a*source.r*source.a);
        }
    ]])end
    love.graphics.push('all');love.graphics.setColor(tint or{1,1,1,1});love.graphics.setShader(self.maskShader)
    if tiled then
        img:setWrap('repeat','repeat');local iw,ih=img:getDimensions()
        local key=name..':'..math.ceil(w)..':'..math.ceil(h)
        if not self.quads[key]then
            self.quadOrder=self.quadOrder or{};self.quadOrder[#self.quadOrder+1]=key
            self.quads[key]=love.graphics.newQuad(0,0,w,h,iw,ih)
            if#self.quadOrder>32 then self.quads[table.remove(self.quadOrder,1)]=nil end
        end
        love.graphics.draw(img,self.quads[key],x,y)
    else love.graphics.draw(img,x,y,0,w/img:getWidth(),h/img:getHeight())end
    love.graphics.pop();self.stats[name]=(self.stats[name]or 0)+1;return true
end
local function caps(img,x,y,w,h,tint)
    local iw,ih=img:getDimensions();local edge=math.min(iw/2,ih/2);local scale=h/ih;local target=math.min(w/2,edge*scale)
    love.graphics.setColor(tint)
    for i,part in ipairs({{0,edge,target},{edge,iw-2*edge,math.max(0,w-2*target)},{iw-edge,edge,target}})do
        if part[3]>0 and part[2]>0 then
            local quad=love.graphics.newQuad(part[1],0,part[2],ih,iw,ih)
            love.graphics.draw(img,quad,x+(i==1 and 0 or i==2 and target or w-target),y,0,part[3]/part[2],h/ih)
        end
    end
end
function Surfaces:slider(x,y,w,h,value,colors)
    local track=self:load(manifest.surfaces['slider-track']);local thumb=self:load(manifest.surfaces['slider-thumb'])
    if not track or not thumb then return false end
    value=math.max(0,math.min(1,value or 0));local accent=colors.accent;local size=math.min(24,h-6)
    local left=x+size/2;local width=math.max(1,w-size)
    love.graphics.push('all');caps(track,left,y+h/2-5,width,10,{.12,.19,.23,1})
    if value>0 then caps(track,left,y+h/2-5,math.max(2,width*value),10,{accent[1],accent[2],accent[3],.9})end
    local tx=x+width*value;love.graphics.setColor(.95,.98,1,1);love.graphics.draw(thumb,tx,y+(h-size)/2,0,size/thumb:getWidth(),size/thumb:getHeight())
    love.graphics.pop();self.stats.slider=(self.stats.slider or 0)+1;return true
end
function Surfaces:cardBack(x,y,w,h,style,colors)
    local spec=Surfaces.cardBackSpec(style);local img=self:load(spec)
    if not img then return false end
    love.graphics.push('all');love.graphics.setColor(style=='Arcane'and .40 or 1,style=='Arcane'and .46 or 1,style=='Arcane'and .70 or 1,1)
    if spec.fit then
        local scale=math.min(w/img:getWidth(),h/img:getHeight())
        love.graphics.draw(img,x+(w-img:getWidth()*scale)/2,y+(h-img:getHeight()*scale)/2,0,scale,scale)
    else love.graphics.draw(img,x,y,0,w/img:getWidth(),h/img:getHeight())end
    if not style or style=='Arcane'then
        self:mask('hex-pattern',x+w*.09,y+h*.07,w*.82,h*.86,{.62,.68,.93,.18})
        self:mask('spotlight',x+w*.13,y+h*.24,w*.74,h*.52,{.18,.56,.63,.28})
        local cx,cy=x+w/2,y+h/2;love.graphics.setColor(colors and colors.accent or{.45,.88,.80,1});love.graphics.setLineWidth(math.max(1,w*.012))
        love.graphics.polygon('line',cx,cy-h*.13,cx+w*.18,cy,cx,cy+h*.13,cx-w*.18,cy)
    end
    love.graphics.pop();self.stats.cardBack=(self.stats.cardBack or 0)+1;return true
end
return Surfaces
