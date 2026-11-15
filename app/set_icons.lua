-- Verified supplied Keyrune glyphs; unknown/new codes keep a generic icon.
local Assets=require('app.assets')
local Layout=require('app.layout')
local mapping=require('assets.keyrune.sets')
local utf8=require('utf8')
local Icons={mapping=mapping};local fonts={};local signature
function Icons.codepoint(code)return mapping[tostring(code or''):lower()]end
function Icons.draw(assets,code,x,y,size,color,settings)
    local cp=Icons.codepoint(code)
    if cp then
        local density=math.max(Layout.scale or 1,Assets.uiRasterScale(settings));local context=Assets.rasterContext()..':'..density
        if signature~=context then fonts={};signature=context end
        local font=fonts[size]
        if font==nil then local ok,value=pcall(love.graphics.newFont,'assets/keyrune/keyrune.ttf',size,'normal',density);font=ok and value or false;fonts[size]=font;if font then font:setFilter('linear','linear')end end
        local glyph=utf8.char(cp)
        if font and font:hasGlyphs(glyph)then
            love.graphics.push('all');love.graphics.setFont(font);love.graphics.setColor(color or{1,1,1,1})
            love.graphics.print(glyph,x+(size-font:getWidth(glyph))/2,y+(size-font:getHeight())/2);love.graphics.pop();return true
        end
    end
    assets:iconSymbol('collection',x,y,size,color);return false
end
return Icons
