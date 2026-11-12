-- One coordinate system for Slab and the custom table, including input and clips.
local Layout={scale=1}
function Layout.setScale(requested)
    local w,h=love.graphics.getDimensions()
    Layout.scale=math.max(.75,math.min(tonumber(requested) or 1,w/1120,h/720))
    return Layout.scale
end
function Layout.dimensions() local w,h=love.graphics.getDimensions();return w/Layout.scale,h/Layout.scale end
function Layout.toLogical(x,y) return x/Layout.scale,y/Layout.scale end
function Layout.mouse() return Layout.toLogical(love.mouse.getPosition()) end
function Layout.clip(x,y,w,h)
    if x==nil then love.graphics.setScissor();return end
    -- Account for both UI scale and an optional lower/higher resolution scene canvas.
    local scale=Layout.scale*(Layout.renderScale or 1)
    love.graphics.setScissor(x*scale,y*scale,math.max(0,w*scale),math.max(0,h*scale))
end
function Layout.table(w,h)
    local board={x=16,y=16,w=w-32,h=h-32}
    local handH=math.max(176,math.min(252,h*.245))
    local fieldTop=260
    local fieldBottom=h-handH-46
    local rowH=(fieldBottom-fieldTop)/2
    local logW=math.min(400,w*.27)
    return {board=board,actions={x=w-334,y=132,w=318,h=146},log={x=w-logW-16,y=140,w=logW,h=170},
        handH=handH,handY=h-handH-15,fieldTop=fieldTop,rowH=rowH,
        fieldX=board.x+132,fieldW=board.w-264,enemyY=fieldTop,humanY=fieldTop+rowH,
        fieldBottom=fieldBottom,divider=fieldTop+rowH-5,zoneW=math.max(78,math.min(102,h*.108)),phaseY=78}
end
-- Center short rows; move a crowded mana row toward the left before overlap.
function Layout.cardRow(count,x,y,width,cardWidth,cardHeight,shiftCrowded)
    if count<=0 then return {} end
    local edge=math.max(16,(cardHeight-cardWidth)/2+9)
    local usable=math.max(cardWidth,width-edge*2)
    local spacing=math.min(cardWidth+13,(usable-cardWidth)/math.max(1,count-1))
    local span=cardWidth+(count-1)*spacing
    local shift=shiftCrowded and math.min(width*.20,math.max(0,count-6)*cardWidth*.32) or 0
    local start=x+width/2-span/2-shift
    start=math.max(x+edge,math.min(x+width-edge-span,start))
    local out={}
    for i=1,count do out[i]={x=start+(i-1)*spacing,y=y,w=cardWidth,h=cardHeight} end
    return out
end
return Layout
