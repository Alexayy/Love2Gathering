-- The supplied Beleren face is the application's typeface. Missing glyphs use
-- DejaVu; Mana/Keyrune symbols are deliberately loaded separately by Assets.
local Fonts={default='Beleren',titleDefault='Beleren',limit=1,maxBytes=24*1024*1024,cacheLimit=48}
local cache,clock={},0
local metrics=setmetatable({},{__mode='k'})
local catalog={{name='Beleren'}}
function Fonts.available()return catalog end
function Fonts.names()return{'Beleren'}end
local function sizeOf(size)return math.max(8,math.min(96,math.floor((tonumber(size)or 16)+.5)))end
function Fonts.font(size)
    size=sizeOf(size);clock=clock+1
    local entry=cache[size]
    if entry then entry.used=clock;return entry.font,entry.family end
    local font,family,source
    if love.filesystem.getInfo('assets/fonts/Beleren2016-Bold.ttf')then
        local ok,result=pcall(love.graphics.newFont,'assets/fonts/Beleren2016-Bold.ttf',size)
        if ok then font=result;family='Beleren';source='assets/fonts/Beleren2016-Bold.ttf';font:setFallbacks(love.graphics.newFont('assets/fonts/DejaVuSans.ttf',size))end
    end
    if not font then source='assets/fonts/DejaVuSans.ttf';font=love.graphics.newFont(source,size);family='Built-in DejaVu Sans'end
    metrics[font]={source=source,size=size,offsets={},order={}}
    cache[size]={font=font,family=family,used=clock}
    local count=0;for _ in pairs(cache)do count=count+1 end
    if count>Fonts.cacheLimit then local oldest,when;for key,item in pairs(cache)do if not when or item.used<when then oldest,when=key,item.used end end;cache[oldest]=nil end
    return font,family
end
-- The family argument remains accepted for old callers/saves. The current
-- product choice is always Beleren, including body labels and table text.
function Fonts.createSet(_,sizes)
    local result,effective={}
    for _,size in ipairs(sizes)do result[size],effective=Fonts.font(size)end
    local bold=Fonts.font(22)
    return result,bold,nil,effective or Fonts.default
end
function Fonts.title(size)return Fonts.font(size or 22)end
-- Beleren's line box has generous space below its ink. Center controls by the
-- actual offered caption's glyph bearings, including UTF-8 fallback glyphs.
function Fonts.textOffset(font,text)
    local meta=metrics[font];if not meta then return 0 end
    text=tostring(text or'');if text:find('\n',1,true)then return 0 end
    if meta.offsets[text]then return meta.offsets[text]end
    meta.raster=meta.raster or love.font.newRasterizer(meta.source,meta.size)
    local top,bottom=math.huge,-math.huge
    for _,code in require('utf8').codes(text)do
        local char=require('utf8').char(code);local raster=meta.raster
        if not raster:hasGlyphs(char)then meta.fallback=meta.fallback or love.font.newRasterizer('assets/fonts/DejaVuSans.ttf',meta.size);raster=meta.fallback end
        local glyph=raster:getGlyphData(char)
        if glyph:getWidth()>0 and glyph:getHeight()>0 then
            local _,bearing=glyph:getBearing();local y=font:getAscent()-bearing
            top=math.min(top,y);bottom=math.max(bottom,y+glyph:getHeight())
        end
    end
    local offset=top<math.huge and(font:getHeight()-top-bottom)/2 or 0
    if #text<=1024 then
        meta.offsets[text]=offset;meta.order[#meta.order+1]=text
        if #meta.order>96 then meta.offsets[table.remove(meta.order,1)]=nil end
    end
    return offset
end
function Fonts.clearCache()cache={}end
return Fonts
