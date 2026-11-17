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
function Layout.table(w,h,model)
    local safe=require('app.table_presentation')
    local view=model and safe.forModel(w,h,model)or safe.layout(w,h)
    local board={x=16,y=16,w=w-32,h=h-32}
    local handH=view.handH
    -- Reclaim the gaps below command cards and above the fixed hand before
    -- increasing card targets; compact duel rows must retain their separation.
    local fieldTop=view.viewport.y+94
    local fieldBottom=view.viewport.y+view.viewport.h
    local rowH=(fieldBottom-fieldTop)/2
    local logW=math.min(400,w*.27)
    return {board=board,actions={x=w-334,y=132,w=318,h=146},log={x=w-logW-16,y=140,w=logW,h=170},
        handH=handH,handY=h-handH-15,fieldTop=fieldTop,rowH=rowH,
        fieldX=view.viewport.x+132,fieldW=view.viewport.w-264,enemyY=fieldTop,humanY=fieldTop+rowH,
        fieldBottom=fieldBottom,divider=fieldTop+rowH-5,zoneW=math.max(60,math.min(94,h*.092)),phaseY=78,
        navY=108,viewport=view.viewport,headerH=146,safe=view,rail=view.rail}
end
-- Center short rows; move a crowded mana row toward the left before overlap.
function Layout.cardRow(count,x,y,width,cardWidth,cardHeight,shiftCrowded,cards)
    if count<=0 then return {} end
    local edge=cards and 10 or math.max(16,(cardHeight-cardWidth)/2+9)
    local usable=math.max(cardWidth,width-edge*2)
    local natural=0;local footprints={}
    for i=1,count do footprints[i]=cards and cards[i]and cards[i].tapped and cardHeight or cardWidth;natural=natural+footprints[i]+13 end
    natural=natural-13
    local last=footprints[count]
    local ratio=math.max(0,math.min(1,(usable-last)/math.max(1,natural-last)))
    local span=last+(natural-last)*ratio
    local shift=shiftCrowded and math.min(width*.20,math.max(0,count-6)*cardWidth*.32) or 0
    local start=x+width/2-span/2-shift
    start=math.max(x+edge,math.min(x+width-edge-span,start))
    local out={}
    local cursor=start
    for i=1,count do
        local footprint=footprints[i]
        out[i]={x=cursor+(footprint-cardWidth)/2,y=y,w=cardWidth,h=cardHeight}
        cursor=cursor+(footprint+13)*ratio
    end
    return out
end
return Layout
