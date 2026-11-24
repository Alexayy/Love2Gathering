-- The battlefield uses the illustration of the entitled face, cropped in source
-- coordinates so camera scaling and tapping never change the aspect ratio.
local Mechanics=require('app.mechanic_fx')
local Presentation=require('app.card_presentation')
local RichText=require('app.richtext')
local Text=require('app.utf8_text')
local utf8=require('utf8')
local json=require('lib.json')
local shortType={Enchantment='Ench.',Artifact='Art.',Creature='Cr.',Planeswalker='PW'}
local Face={}
local quad,spentLandShader

local function illustration(image,scan,data,x,y,w,h)
    local iw,ih=image:getDimensions()
    local sx,sy,sw,sh=0,0,iw,ih
    if scan then
        -- The portrait scan includes its printed name, frame and rules box.
        -- Sagas and Classes use a side panel in place of the upper art window.
        sx,sy,sw,sh=iw*.095,ih*.14,iw*.81,ih*.36
        local face=(data.card_faces or {})[(tonumber(data.requested_face) or 0)+1] or data
        local kind=face.type_line or face.type or ''
        if type(kind)=='table'then kind=table.concat(kind,' ')end
        if kind:find('Saga',1,true)then sx,sy,sw,sh=iw*.58,ih*.18,iw*.29,ih*.60
        elseif kind:find('Class',1,true)then sx,sy,sw,sh=iw*.095,ih*.18,iw*.29,ih*.60 end
    end
    local scale=math.max(w/sw,h/sh)
    local cw,ch=w/scale,h/scale
    sx,sy=sx+(sw-cw)*.5,sy+(sh-ch)*.42
    if not quad then quad=love.graphics.newQuad(sx,sy,cw,ch,iw,ih)
    else quad:setViewport(sx,sy,cw,ch,iw,ih)end
    love.graphics.draw(image,quad,x,y,0,scale,scale)
end

function Face.header(r,card,data,x,y,w,h,groupCount)
    local count=groupCount and groupCount>1 and ('×'..groupCount)
    local compact=w<40 or h<32
    if compact and not count then return 0 end
    local title=Text.clean(card.name or data.name or 'Card')
    local size=w<100 and 13 or w<145 and 14 or 16
    local font=r.assets:titleFont(size,r.model.settings)
    local top=math.max(font:getHeight()+2,math.floor(h*.15))
    local g=love.graphics
    g.setColor(.033,.031,.028,.91)
    g.rectangle('fill',x+2,y+2,w-4,top,2,2)

    -- Combat/action badges share the upper-right corner with some mana costs.
    local reserve=card.attacking and 20 or 0
    if w<100 and (tonumber(card.damage)or 0)>0 then reserve=math.max(reserve,19)end
    if count then
        local countSize=w<100 and 11 or 12
        local countFont=r.assets:titleFont(countSize,r.model.settings)
        local countW=countFont:getWidth(count)
        local cx=x+w-4-reserve-countW
        g.setColor(.5,.38,.21,.8);g.setLineWidth(1)
        g.line(cx-3,y+4,cx-3,y+top)
        r:strong(count,cx,y+2+(top-countFont:getHeight())/2,countSize,r.colors.gold)
        reserve=reserve+countW+4
        if compact then return top+2 end
    end
    local available=math.max(1,w-12-reserve)
    local cost=Presentation.manaCost(card,data)
    local icon=w<105 and 11 or 13
    local layout
    local costW=0
    if cost~=''then
        layout=RichText.layout(r,cost,4096,{size=11,iconSize=icon,iconGap=1})
        for _,run in ipairs(layout.runs)do costW=math.max(costW,run.x+run.w)end
    end
    local inline=costW==0 or costW+5+font:getWidth(title)<=available
    local nameW=math.max(1,available-(inline and costW>0 and costW+5 or 0))
    if font:getWidth(title)>nameW and size>11 then
        size=math.max(11,math.floor(size*nameW/font:getWidth(title)))
        font=r.assets:titleFont(size,r.model.settings)
    end
    local titleW=font:getWidth(title)
    local squeeze=math.min(1,nameW/math.max(1,titleW))
    local minimumScale=.78
    if squeeze<minimumScale then
        -- Keep as much of the second word as fits on compact lands and tokens.
        while #title>0 and font:getWidth(title..'…')*minimumScale>nameW do
            title=title:sub(1,utf8.offset(title,-1)-1)
        end
        title=title..'…'
        squeeze=math.min(1,nameW/math.max(1,font:getWidth(title)))
    end
    g.push();g.translate(x+6,y+2+(top-font:getHeight())/2);g.scale(squeeze,1)
    r:strong(title,0,0,size,r.colors.text);g.pop()
    if costW==0 then return top+2 end

    local scale=math.min(1,(w-10)/costW)
    local cx=inline and x+w-6-reserve-costW or x+5
    local cy=inline and y+(top-icon)/2+1 or y+top+2
    if not inline then
        g.setColor(.033,.031,.028,.89);g.rectangle('fill',cx-2,cy,costW*scale+4,layout.lineHeight*scale,2,2)
    end
    g.push();g.translate(cx,cy);g.scale(scale)
    RichText.draw(r,cost,0,0,costW,{layout=layout});g.pop()
    return inline and top+2 or top+2+layout.lineHeight*scale
end

function Face.draw(r,card,data,x,y,w,h,variant,selectable)
    local c=Mechanics.color(card)
    local g=love.graphics
    g.setColor(.035,.034,.032,1);g.rectangle('fill',x-2,y-2,w+4,h+4,4,4)
    g.setColor(c[1]*.52+.14,c[2]*.52+.13,c[3]*.52+.10,1)
    g.rectangle('fill',x,y,w,h,3,3)
    local options={variant=variant}
    local image=r.model:getArt(data,false,'art_crop',options)
    local scan=not image
    if scan then image=r.model:getArt(data,false,'normal',options)end
    if image then
        g.setColor(1,1,1,1)
        if card.tapped and Presentation.battlefieldRole(card)=='lands' then
            -- A public creature land is still a creature, even if its printed
            -- face is a land. Only the currently noncreature land art is muted.
            if not spentLandShader then
                spentLandShader=g.newShader([[
                    vec4 effect(vec4 tint, Image texture, vec2 uv, vec2 pixel) {
                        vec4 ink=Texel(texture,uv);
                        float gray=dot(ink.rgb,vec3(.299,.587,.114));
                        return vec4(mix(vec3(gray),ink.rgb,.6)*.83,ink.a)*tint;
                    }
                ]])
            end
            g.push('all');g.setShader(spentLandShader)
            illustration(image,scan,data,x+2,y+2,w-4,h-4)
            g.pop()
        else illustration(image,scan,data,x+2,y+2,w-4,h-4)end
    else
        g.setColor(c[1]*.22+.035,c[2]*.22+.028,c[3]*.22+.025,1)
        g.rectangle('fill',x+2,y+2,w-4,h-4)
        local types=Presentation.battlefieldTypes(card)
        local symbol=types[1] and types[1]:lower() or 'card'
        local size=math.min(w*.37,h*.50)
        r.assets:iconSymbol(symbol,x+(w-size)/2,y+(h-size)/2,size,{c[1],c[2],c[3],.6})
    end
    if selectable then
        g.setColor(r.colors.accent);g.setLineWidth(2)
        g.rectangle('line',x-2,y-2,w+4,h+4,4,4)
    end
end

function Face.primaryCounter(card,types)
    for _,kind in ipairs(types)do
        local key=kind=='Planeswalker' and 'Loyalty' or kind=='Battle' and 'Defense'
        if key then
            if type(card.counters)=='table' and card.counters~=json.null then
                for name,value in pairs(card.counters)do
                    if type(value)=='table'then name=value.name or value.type or name;value=value.count or value.amount end
                    if tostring(name):lower()==key:lower() and tonumber(value) then return key,tonumber(value)end
                end
                return key,0
            end
            local value=tonumber(card[key:lower()])
            if value then return key,value end
        end
    end
end

function Face.footer(r,types,x,y,w,h,statsWidth)
    if #types==0 or w<45 or h<35 then return end
    local label=table.concat(types,' ')
    local size=w>=125 and 12 or 10
    local height=r:font(size):getHeight()+2
    local available=w-(statsWidth or 0)-8
    local fits=r:font(size):getWidth(label)<=available
    local bottom=h-1
    if not fits and statsWidth then bottom=bottom-math.min(30,math.max(21,math.floor(h*.23)))end
    local width=fits and available+4 or w-4
    if #types>1 and r:font(size):getWidth(label)>width-5 then
        local names={}
        for _,kind in ipairs(types)do names[#names+1]=shortType[kind] or kind end
        label=table.concat(names,' ')
    end
    love.graphics.setColor(.025,.034,.045,.9)
    love.graphics.rectangle('fill',x+2,y+bottom-height,width,height,2,2)
    r:text(r:fit(label,width-5,size,1),x+5,y+bottom-height,size,{.9,.87,.79},width-5)
    -- A narrow multitype tile uses its full-width label over the stats lane.
    -- This leaves the mechanic badges beside P/T; wide tiles put them above it.
    if fits then return bottom-height-1 else return h-2 end
end

function Face.tap(r,x,y,w,h,headerH,footerReserve)
    -- The longer header may include a second row of mana pips at the left.
    -- Use the right side of the illustration so the tap disc stays legible on
    -- a small creature and still clears its name and bottom-right P/T badge.
    local titleH=math.min(headerH,math.max(17,r:font(w<100 and 13 or 15):getHeight()+2))
    local space=math.max(13,h-titleH-footerReserve)
    local size=math.max(13,math.min(42,w*.4,space))
    local cx=x+w*((footerReserve<=3 or headerH>titleH+3) and .68 or .56)
    local cy=y+titleH+space*.5
    local g=love.graphics
    g.setColor(.025,.023,.02,.93);g.circle('fill',cx,cy,size*.54+1)
    g.setColor(.95,.75,.39,1);g.setLineWidth(1.5);g.circle('line',cx,cy,size*.53)
    -- Use the standard dark tap arrow on its light mana disc.
    r.assets:mana('T',cx-size/2,cy-size/2,size)
end

return Face
