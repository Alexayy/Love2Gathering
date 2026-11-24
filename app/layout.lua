-- One coordinate system for Slab and the custom table, including input and clips.
local Layout={scale=1}
function Layout.setScale(requested)
    local w,h=love.graphics.getDimensions()
    Layout.scale=math.max(.75,math.min(tonumber(requested) or 1,w/1120,h/720))
    return Layout.scale
end
function Layout.dimensions() local w,h=love.graphics.getDimensions();return w/Layout.scale,h/Layout.scale end
function Layout.toLogical(x,y) return x/Layout.scale,y/Layout.scale end
function Layout.manaDock(w)
    local width=math.min(520,w-32,math.max(400,w*.4))
    return w-width-20,width
end
function Layout.beforeDamage(w) return {x=w-238,y=112,w=222,h=34} end
function Layout.mouse() return Layout.toLogical(love.mouse.getPosition()) end
function Layout.clip(x,y,w,h)
    if x==nil then love.graphics.setScissor();return end
    -- Account for both UI scale and an optional lower/higher resolution scene canvas.
    local scale=Layout.scale*(Layout.renderScale or 1)
    love.graphics.setScissor(x*scale,y*scale,math.max(0,w*scale),math.max(0,h*scale))
end
function Layout.table(w,h,model,extension)
    local safe=require('app.table_presentation')
    local view=model and safe.forModel(w,h,model)or safe.layout(w,h)
    local board={x=16,y=16,w=w-32,h=h-32}
    local fieldTop=view.viewport.y+15
    local fieldBottom=view.viewport.y+view.viewport.h-16
    local handTop=view.handY
    local extensionH=h<850 and 76 or 96
    if extension and #extension>0 then
        handTop=handTop-extensionH-14
        fieldBottom=math.min(fieldBottom,handTop-9)
    elseif model and model.game then
        for _,player in ipairs(model.game.players or{})do
            if safe.isLocalSeat(model.game,player) and #(player.hand or{})>0 then
                fieldBottom=math.min(fieldBottom,handTop-11);break
            end
        end
    end
    local divider=(fieldTop+fieldBottom)/2
    local rowH=divider-fieldTop-9
    local sideWidth=h<850 and 118 or 148
    local fieldX=view.viewport.x+sideWidth
    local right=view.viewport.x+view.viewport.w-110
    local prompt=model and model.prompt and model:prompt()
    local paymentEdge
    if prompt and prompt.type=='play_mana' then
        paymentEdge=Layout.manaDock(w)-10
        right=math.min(right,paymentEdge)
    end
    local logW=math.min(400,w*.27)
    return {board=board,actions={x=w-334,y=132,w=318,h=146},log={x=w-logW-16,y=140,w=logW,h=170},
        handH=view.handH,handY=view.handY,handTop=handTop,exileCards=extension,exileCardH=extensionH,fieldTop=fieldTop,rowH=rowH,
        fieldX=fieldX,fieldW=math.max(60,right-fieldX),paymentEdge=paymentEdge,enemyY=fieldTop,humanY=divider+9,
        fieldBottom=fieldBottom,divider=divider,zoneW=math.max(60,math.min(94,h*.092)),phaseY=78,
        navY=108,viewport=view.viewport,headerH=146,safe=view,rail=view.rail}
end
-- Positions are specified around the actual rotated silhouette. The renderer
-- rotates the original face about its center and uses that same pose for input.
local cardGap,fieldInset=10,7
local tapAngle=math.rad(15)
function Layout.battlefieldAngle(card)
    return card.tapped and tapAngle or 0
end
function Layout.rotatedSize(w,h,angle)
    local cos,sin=math.abs(math.cos(angle)),math.abs(math.sin(angle))
    return w*cos+h*sin,h*cos+w*sin
end
local function footprint(card,aspect)
    return Layout.rotatedSize(aspect,1,Layout.battlefieldAngle(card))
end
function Layout.battlefieldRowWidth(cards,cardHeight,aspect)
    if #cards==0 then return 0 end
    local span=2*fieldInset+(#cards-1)*cardGap
    for _,card in ipairs(cards)do span=span+footprint(card,aspect)*cardHeight end
    return span
end
function Layout.battlefieldRow(cards,x,centerY,width,preferred,minimum,aspect,align)
    local count=#cards
    if count==0 then return {} end
    local inset=math.min(fieldInset,width*.2)
    local usable=width-2*inset
    local factors,total,widest={},0,0
    for i,card in ipairs(cards)do
        local factor=footprint(card,aspect)
        factors[i]=factor;total=total+factor;widest=math.max(widest,factor)
    end
    -- Keep even a very narrow, crowded lane staggered so each object still
    -- has an exposed edge. A single permanent can use the entire lane.
    local stagger=math.min(usable*.16,(count-1)*6)
    local floor=math.min(minimum,preferred,(usable-stagger)/widest)
    local ch=math.max(floor,math.min(preferred,(usable-(count-1)*cardGap)/total))
    local cw=ch*aspect
    -- All offsets use the same compression. Every rotated silhouette limits
    -- the fit, including a wide tapped card immediately before an upright one.
    local ratio,offset=1,0
    for _,factor in ipairs(factors)do
        local span=factor*ch
        if offset>0 then ratio=math.min(ratio,(usable-span)/offset)end
        offset=offset+span+cardGap
    end
    local out={}
    local occupied,cursor=0,0
    for i,factor in ipairs(factors)do
        local span=factor*ch
        out[i]={x=cursor+(span-cw)/2,y=centerY-ch/2,w=cw,h=ch}
        occupied=math.max(occupied,cursor+span)
        cursor=cursor+(span+cardGap)*ratio
    end
    local origin=x+inset+math.max(0,usable-occupied)*(align or .5)
    for _,box in ipairs(out)do box.x=box.x+origin end
    return out
end
return Layout
