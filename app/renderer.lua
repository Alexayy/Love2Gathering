local Layout=require('app.layout')
local Assets=require('app.assets')
local Table=require('app.table')
local RichText=require('app.richtext')
local Text=require('app.utf8_text')
local Board=require('app.board_fx')
local Presentation=require('app.card_presentation')
local Actions=require('app.card_actions')
local utf8=require('utf8')
local Renderer={};Renderer.__index=Renderer
local C={bg={.026,.036,.060},panel={.055,.073,.106},line={.15,.21,.28},text={.90,.94,.98},muted={.46,.56,.66},accent={.28,.89,.72},purple={.62,.48,.96},red={1,.39,.40},gold={.98,.74,.34}}
Renderer.colors=C
local function color(c,a) love.graphics.setColor(c[1],c[2],c[3],a or c[4] or 1) end
local function rect(x,y,w,h,c,r) color(c);love.graphics.rectangle('fill',x,y,w,h,r or 10,r or 10) end
local function inside(hit,x,y)
    local clip=hit.clip
    if clip and (x<clip.x or y<clip.y or x>clip.x+clip.w or y>clip.y+clip.h) then return false end
    local cx,cy=hit.x+hit.w/2,hit.y+hit.h/2
    local a=-(hit.angle or 0);local dx,dy=x-cx,y-cy
    dx,dy=dx*math.cos(a)-dy*math.sin(a),dx*math.sin(a)+dy*math.cos(a)
    return math.abs(dx)<=hit.w/2 and math.abs(dy)<=hit.h/2
end
function Renderer.new(model)
    local self=setmetatable({model=model,hits={},hover=nil,drag=nil,fonts={},assets=Assets.new(),poses={},cardRects={},ghosts={},dt=1/60},Renderer)
    local Fonts=require('app.fonts');self.fonts,self.bold=Fonts.createSet(Fonts.default,{10,11,12,13,14,16,18,20,22,24,28,32,36,44,52})
    if self.assets.setSettings then self.assets:setSettings(model.settings)end
    return self
end
function Renderer:font(size)
    size=math.max(8,math.min(96,math.floor((tonumber(size)or 14)+.5)))
    if not self.fonts[size]then self.fonts[size]=require('app.fonts').font(size)end
    return self.fonts[size]
end
function Renderer:text(text,x,y,size,tint,width,align)
    text=Text.clean(text)
    love.graphics.setFont(self:font(size));color(tint or C.text)
    if width then love.graphics.printf(text,x,y,width,align or 'left') else love.graphics.print(text,x,y) end
end
function Renderer:strong(text,x,y,size,tint,width,align)
    text=Text.clean(text)
    love.graphics.push();love.graphics.translate(x,y)
    love.graphics.setFont(self.assets.titleFont and self.assets:titleFont(size or 22,self.model.settings)or self.bold);color(tint or C.text)
    if width then love.graphics.printf(text,0,0,width,align or'left')else love.graphics.print(text,0,0)end
    love.graphics.pop()
end
function Renderer:outlinedStrong(text,x,y,size,tint,outline,width)
    for _,offset in ipairs({{-2,0},{2,0},{0,-2},{0,2},{-1.5,-1.5},{1.5,-1.5},{-1.5,1.5},{1.5,1.5}})do
        self:strong(text,x+offset[1],y+offset[2],size,outline,width,'center')
    end
    self:strong(text,x,y,size,tint,width,'center')
end
function Renderer:playerColor(player)return Board.color(self,player)end
function Renderer:drawPermanent(card,x,y,w,h,options)return Board.layers(self,card,x,y,w,h,options)end
function Renderer:priorityBadge(player,x,y,w,height)return Board.priority(self,player,x,y,w,height)end
function Renderer:commanderSummary(player,x,y,w,size)
    local enabled=(self.model.game or{}).commanderDamageEnabled
    local commanders=player.commanders or{}
    local summary=#commanders>0 and(#commanders>1 and(#commanders..' commanders · details')or((commanders[1].name or'Commander')..' · '..Presentation.commanderLabel(commanders[1])))or Presentation.commanderDamageSummary(player,enabled)
    if not summary then return end
    local tint=enabled and C.gold or C.muted
    self.assets:iconSymbol('commander',x,y+1,14,tint)
    self:strong(self:fit(summary,w-19,size or 11,1),x+19,y,size or 11,tint,w-19)
    self:hit({x=x,y=y-2,w=w,h=20,kind='player',card={id=player.id,name=player.name},
        tooltip=Presentation.playerTooltip(player,enabled),commanderDetails=true,
        action=function()self.model.commanderDetails=player.id end})
end
function Renderer:drawAvatar(player,x,y,size)
    local m=self.model;local profile=player and m.profileForPlayer and m:profileForPlayer(player)or m.profile or{}
    local density=Layout.scale*(Layout.renderScale or 1)*(self.worldTransform and self.worldTransform.scale or 1)*(love.window and love.window.getDPIScale and love.window.getDPIScale()or 1)
    local options={variant=size*density<=256 and'thumb'or nil}
    local art=m.profileArt and m:profileArt(profile.avatar,nil,options)
    if not art and player and player.avatarCard then art=m:getArt(player.avatarCard,true,'art_crop',options)end
    local tint=player and self:playerColor(player)or C.accent
    self:panel(x,y,size,size,'dark')
    if art then
        local scale=math.max((size-4)/art:getWidth(),(size-4)/art:getHeight())
        love.graphics.push('all')
        local box=self:screenRect({x=x+2,y=y+2,w=size-4,h=size-4});local factor=Layout.scale*(Layout.renderScale or 1)
        local sx,sy,sw,sh=box.x*factor,box.y*factor,box.w*factor,box.h*factor
        local ox,oy,ow,oh=love.graphics.getScissor();if ox then local right,bottom=math.min(sx+sw,ox+ow),math.min(sy+sh,oy+oh);sx,sy=math.max(sx,ox),math.max(sy,oy);sw,sh=math.max(0,right-sx),math.max(0,bottom-sy)end
        love.graphics.setScissor(sx,sy,sw,sh);color({1,1,1});love.graphics.draw(art,x+(size-art:getWidth()*scale)/2,y+(size-art:getHeight()*scale)/2,0,scale,scale);love.graphics.pop()
    else self.assets:iconSymbol('player',x+size*.15,y+size*.15,size*.7,tint)end
end
function Renderer:drawPlaymat(player,x,y,w,h)
    if w<=0 or h<=0 then return end
    local m=self.model;local profile=m.profileForPlayer and m:profileForPlayer(player)or{}
    local art=m.profileArt and m:profileArt(profile.playmat)
    if not art and m.botPlaymatArt and player and not player.human then art=m:botPlaymatArt(player)end
    if not art then
        if player and not player.human and self.assets.surface then local c=self:playerColor(player);self.assets:surface('hex-pattern',x,y,w,h,{c[1],c[2],c[3],.035})end
        return
    end
    local opacity=m.settings.playmatOpacity or .88;if opacity<=0 then return end
    love.graphics.push('all')
    local box=self:screenRect({x=x,y=y,w=w,h=h});local factor=Layout.scale*(Layout.renderScale or 1)
    local sx,sy,sw,sh=box.x*factor,box.y*factor,box.w*factor,box.h*factor
    local ox,oy,ow,oh=love.graphics.getScissor();if ox then local right,bottom=math.min(sx+sw,ox+ow),math.min(sy+sh,oy+oh);sx,sy=math.max(sx,ox),math.max(sy,oy);sw,sh=math.max(0,right-sx),math.max(0,bottom-sy)end
    love.graphics.setScissor(sx,sy,sw,sh)
    local scale=math.max(w/art:getWidth(),h/art:getHeight());color({1,1,1},opacity)
    love.graphics.draw(art,x+(w-art:getWidth()*scale)/2,y+(h-art:getHeight()*scale)/2,0,scale,scale)
    rect(x,y,w,h,{.018,.029,.045,m.settings.highContrast and .78 or .57},0)
    love.graphics.pop()
end
function Renderer:sound(kind)
    local s=self.model.settings
    if s.sfxEnabled~=false then self.assets:playSound(kind,s.sfxVolume or .45) end
end
function Renderer:burst(kind,x,y,count)
    local s=self.model.settings
    if s.particles~=false and not s.reducedMotion then self.assets:particle(kind,x,y,count) end
end
function Renderer:update(dt)
    self.dt=math.min(dt,.075);self.assets:update(dt)
    local s=self.model.settings
    if self.assets.setSettings then self.assets:setSettings(s)end
    if Assets.palette then for key,value in pairs(Assets.palette(s))do C[key]=value end end
    local accessible={Deuteranopia={.98,.80,.33},Protanopia={.49,.78,1},Tritanopia={1,.57,.78}}
    C.accent=accessible[s.colorblindMode] or C.accent
    if s.highContrast then C.muted={.72,.80,.89}end
    if self.drag then
        local x,y=Layout.mouse();self.dragPos=self.dragPos or {x=x,y=y}
        local ease=s.reducedMotion and 1 or 1-math.exp(-dt*25)
        self.dragPos.x=self.dragPos.x+(x-self.dragPos.x)*ease;self.dragPos.y=self.dragPos.y+(y-self.dragPos.y)*ease
    end
    for i=#self.ghosts,1,-1 do local g=self.ghosts[i];g.time=g.time+dt;if g.time>=g.duration then table.remove(self.ghosts,i) end end
    Board.update(self,dt)
end
function Renderer:fit(text,width,size,lines)
    local font=self:font(size);local _,wrapped=font:getWrap(Text.clean(text),width)
    if #wrapped<=lines then return table.concat(wrapped,'\n') end
    local out={};for i=1,lines do out[i]=wrapped[i] end
    while #out[lines]>0 and font:getWidth(out[lines]..'…')>width do
        local last=utf8.offset(out[lines],-1);out[lines]=out[lines]:sub(1,last-1)
    end
    out[lines]=out[lines]..'…';return table.concat(out,'\n')
end
function Renderer:screenRect(box)
    local t=self.worldTransform
    if not t then return box end
    return {x=t.x+box.x*t.scale,y=t.y+box.y*t.scale,w=box.w*t.scale,h=box.h*t.scale,angle=box.angle,clip=t.clip}
end
function Renderer:zoneAnchor(playerId,zone,box)
    self.zoneRects=self.zoneRects or{};self.zoneRects[playerId]=self.zoneRects[playerId]or{}
    local screen=self:screenRect(box);self.zoneRects[playerId][zone]=screen
    local native=({library='LIBRARY',hand='HAND',graveyard='GRAVEYARD',exile='EXILED',command='COMMAND',battlefield='BATTLEFIELD'})[zone]
    if native then self.zoneRects[playerId][native]=screen end
end
function Renderer:hit(hit)
    if self.worldTransform then
        local projected=self:screenRect(hit)
        for _,k in ipairs({'x','y','w','h','clip'}) do hit[k]=projected[k] end
        local c=hit.clip;local a=hit.angle or 0
        local halfW=(math.abs(math.cos(a))*hit.w+math.abs(math.sin(a))*hit.h)/2
        local halfH=(math.abs(math.sin(a))*hit.w+math.abs(math.cos(a))*hit.h)/2
        local cx,cy=hit.x+hit.w/2,hit.y+hit.h/2
        if cx+halfW<c.x or cy+halfH<c.y or cx-halfW>c.x+c.w or cy-halfH>c.y+c.h then return hit end
    end
    self.hits[#self.hits+1]=hit;return hit
end
function Renderer:panel(x,y,w,h,style) self.assets:panel(x,y,w,h,style) end
function Renderer:button(label,x,y,w,h,action,active,options)
    label=Text.clean(label)
    options=options or{}
    local mx,my=Layout.mouse();local hot=mx>=x and mx<=x+w and my>=y and my<=y+h
    self.assets:control(x,y,w,h,active and 'accent' or 'dark')
    if hot then rect(x+2,y+2,w-4,h-4,{.14,.27,.31,.35},7) end
    if active then rect(x,y+h-3,w,3,C.accent,1) end
    local size=options.size or 14;local font=self:font(size)
    if options.icon then
        local image=self.assets:buttonImage(options.icon,label,w,h,{font=font,iconSize=20,color=active and C.accent or C.text})
        color({1,1,1});love.graphics.draw(image,x,y,0,w/image:getWidth(),h/image:getHeight())
    else self:text(label,x,y+(h-font:getHeight())/2+require('app.fonts').textOffset(font,label),size,active and C.accent or C.text,w,'center')end
    self:hit({x=x,y=y,w=w,h=h,action=action,tooltip=options.tooltip or label})
end
function Renderer:iconLabel(icon,label,x,y,w,h,size,tint,iconSize)
    label=Text.clean(label)
    size=size or 16;local font=self:font(size);iconSize=iconSize or size+3;tint=tint or C.text
    self.assets:iconSymbol(icon,x,y+(h-iconSize)/2,iconSize,tint)
    self:text(label,x+iconSize+8,y+(h-font:getHeight())/2+require('app.fonts').textOffset(font,label),size,tint,w-iconSize-8)
end
function Renderer:cardHeader(card,data,x,y,w,h)
    local cost=Presentation.manaCost(card,data);local iconSize=w<100 and 13 or 16
    local layout=RichText.layout(self,cost,4096,{size=12,iconSize=iconSize,iconGap=1})
    local costW=0;for _,run in ipairs(layout.runs)do costW=math.max(costW,run.x+run.w)end
    local damageReserve=(tonumber(card.damage)or 0)>0 and w<100 and 17 or 0
    local inline=costW==0 or costW<=w-16-damageReserve-math.min(60,w*.38)
    local compact=h<100;local headerH=inline and 24 or(compact and 36 or 42)
    rect(x+1,y+1,w-2,headerH,{.015,.023,.04,.96},4)
    local nameW=w-12-damageReserve-(inline and costW>0 and costW+5 or 0)
    self:strong(self:fit(card.name or data.name or'Card',nameW,14,1),x+6,y+4,14,C.text,nameW)
    if costW>0 then
        local scale=inline and 1 or math.min(1,(w-10)/costW)
        local costX=inline and(x+w-6-damageReserve-costW)or(x+(w-costW*scale)/2)
        local costY=inline and(y+(24-iconSize)/2+1)or(y+(compact and 21 or 24))
        love.graphics.push();love.graphics.translate(costX,costY);love.graphics.scale(scale)
        RichText.draw(self,cost,0,0,costW,{layout=layout});love.graphics.pop()
    end
    return headerH
end
function Renderer:drawCard(card,x,y,w,h,options)
    options=options or {};options.back=options.back or card.hidden or card.faceDown
    local boardCard=options.kind=='permanent'or options.kind=='attachment'or options.kind=='command'
    local publicFaceDown=card.faceDown==true and(boardCard or options.fullImage==true)
    local angle=options.angle or (card.tapped and math.pi/2 or 0)
    if options.animate and card.id then
        local key=(self.worldTransform and 'world:' or 'screen:')..card.id;local target={x=x,y=y,w=w,h=h,angle=angle};local pose=self.poses[key]
        if not pose then pose={x=x,y=y,w=w,h=h,angle=angle};self.poses[key]=pose end
        pose.seenFrame=self.poseFrame or 0
        local ease=(self.model.settings.reducedMotion or self.model.settings.animations==false) and 1 or 1-math.exp(-self.dt*15)
        for k,v in pairs(target) do pose[k]=pose[k]+(v-pose[k])*ease end
        x,y,w,h,angle=pose.x,pose.y,pose.w,pose.h,pose.angle
    end
    if not options.noHit and(options.kind=='permanent'or options.kind=='attachment')and self.model.settings.animations~=false and not self.model.settings.reducedMotion then local dx,dy,tilt=Board.offset(self,card);x=x+dx;y=y+dy;angle=angle+(tilt or 0)end
    if card.id and not options.noHit then
        local box=self:screenRect({x=x,y=y,w=w,h=h,angle=angle});box.kind=options.kind;self.cardRects[card.id]=box
    end
    if self.drag and self.drag.card and self.drag.card.id==card.id and not options.noHit then return end
    local hitW,hitH=w,h
    love.graphics.push();love.graphics.translate(x+w/2,y+h/2);love.graphics.rotate(angle)
    local bx,by=-w/2,-h/2
    local headerH=24
    local depth=options.hovered and self.model.settings.parallax~=false and 9 or 4
    rect(bx+depth,by+depth+3,w,h,{.005,.009,.016,.64},7)
    if Board.cardUnderlay then Board.cardUnderlay(self,card,bx,by,w,h,options)end
    if options.back then
        if not self.assets.cardBack or not self.assets:cardBack(bx,by,w,h,self.model.settings.cardBackStyle)then
            rect(bx,by,w,h,{.07,.075,.14},7);color({.32,.29,.55});love.graphics.rectangle('line',bx+5,by+5,w-10,h-10,5,5)
        end
    else
        local data=self.model:cardData(card) or card
        local density=Layout.scale*(Layout.renderScale or 1)*(self.worldTransform and self.worldTransform.scale or 1)*(love.window and love.window.getDPIScale and love.window.getDPIScale()or 1)
        local variant=not options.fullImage and w*density<=256 and'thumb'or nil
        local img=self.model:getArt(data,options.imageOnly,nil,{variant=variant})
        local selectable=options.selectable or self.model:canSelect(card.id)
        if selectable then
            rect(bx-5,by-5,w+10,h+10,{C.accent[1],C.accent[2],C.accent[3],.17},9)
        end
        rect(bx-2,by-2,w+4,h+4,selectable and C.accent or { .21,.25,.32 },7)
        if img then color({1,1,1});love.graphics.draw(img,bx,by,0,w/img:getWidth(),h/img:getHeight())
            if boardCard then headerH=self:cardHeader(card,data,bx,by,w,h)end
        elseif options.imageOnly then
            rect(bx,by,w,h,{.075,.095,.13},6)
            local size=h<180 and 10 or 12;local icon=math.min(w*.32,36)
            self.assets:iconSymbol('image',-icon/2,by+h*.14,icon,C.muted)
            local status=self.model.artworkLabel and self.model:artworkLabel(data,nil,{variant=variant})or'Artwork unavailable'
            self:text(self:fit(status,w-14,size,2),bx+7,by+h*.46,size,C.muted,w-14,'center')
            self:text(self:fit(data.name or'',w-14,size,2),bx+7,by+h-size*2-12,size,C.text,w-14,'center')
        else
            rect(bx,by,w,h,{.10,.125,.17},6)
            local colors=card.colors or data.colors or {};local tint={.53,.60,.68}
            if colors[1]=='G' then tint=C.accent elseif colors[1]=='R' then tint=C.red elseif colors[1]=='U' then tint={.28,.58,.94} elseif colors[1]=='W' then tint=C.gold end
            rect(bx+5,by+26,w-10,h*.39,{tint[1]*.33,tint[2]*.33,tint[3]*.33},3)
            if self.assets.surfaces then self.assets:surface('hex-pattern',bx+7,by+30,w-14,h*.35,{tint[1],tint[2],tint[3],.10})end
            local kind=tostring(card.type_line or card.type or data.type_line or''):lower()
            local symbol=kind:find('land',1,true)and'land'or kind:find('creature',1,true)and'creature'or kind:find('instant',1,true)and'instant'or kind:find('sorcery',1,true)and'sorcery'or kind:find('artifact',1,true)and'artifact'or'card'
            self.assets:iconSymbol(symbol,-w*.14,by+34+h*.075,w*.28,{tint[1],tint[2],tint[3],.6})
            local nameSize=boardCard and 14 or(w<100 and 10 or 12)
            if boardCard then headerH=self:cardHeader(card,data,bx,by,w,h)
            else self:strong(self:fit(data.name or card.name or'Unknown',w-14,nameSize,2),bx+7,by+6,nameSize,C.text,w-14)end
            self:text(self:fit(data.type_line or card.type or '',w-12,10,2),bx+6,by+h*.57,10,C.muted,w-12)
            if w>=180 then
                local text=data.oracle_text or card.rules or ''
                if type(text)=='table' then text=table.concat(text,'\n') end
                text=tostring(text):gsub('<[^>]+>','')
                -- maxLines clips complete text/mana runs; a byte prefix can
                -- split native punctuation or a multibyte translated name.
                RichText.draw(self,text,bx+7,by+h*.68,w-14,{size=10,iconSize=11,color=C.text,maxLines=3})
            end
                local cost=data.mana_cost or card.manaCost or '';if cost~=''and not boardCard then self.assets:mana(cost,bx+7,by+h-19,13) end
        end
    end
    -- Tapped art rotates while names, counters and action markers stay upright.
    if boardCard and math.abs(angle)>.01 then
        love.graphics.rotate(-angle)
        w,h=math.abs(math.cos(angle))*hitW+math.abs(math.sin(angle))*hitH,math.abs(math.sin(angle))*hitW+math.abs(math.cos(angle))*hitH
        bx,by=-w/2,-h/2
        if not options.back then headerH=self:cardHeader(card,self.model:cardData(card)or card,bx,by,w,h)end
    end
    -- Only native public battlefield fields may decorate an anonymous back.
    -- Hidden hands/piles do not gain overlays from mere card visibility.
    if not options.back or publicFaceDown then
        if card.attacking then
            color(C.red);love.graphics.setLineWidth(3);love.graphics.rectangle('line',bx-3,by-3,w+6,h+6,6,6)
            self.assets:iconSymbol('attack',bx+w-22,by+5,20,C.red)
        end
        local traits=require('app.card_traits').entries(card)
        local hasCounters=false;for _,value in pairs(type(card.counters)=='table'and card.counters or{})do if(type(value)=='table'and tonumber(value.count or value.amount)or tonumber(value)or 0)~=0 then hasCounters=true;break end end
        if#traits>0 and not(Board.mechanicBadges and(type(card.currentKeywords)=='table'or type(card.mechanicCapabilities)=='table'))and not options.imageOnly and(h>=170 or not hasCounters)then
            local icon=h<170 and 16 or math.max(16,math.min(26,w*.20));local capacity=math.max(1,math.floor((w-10)/(icon+4)));local count=math.min(capacity,#traits)
            local ty=by+(h<170 and headerH+3 or math.max(headerH+26,h*.26))
            rect(bx+3,ty-2,count*(icon+3)+4,icon+4,{.018,.03,.05,.94},3)
            for i=1,count do local entry=traits[i];local tx=bx+5+(i-1)*(icon+3)
                if entry.icon then self.assets:iconSymbol(entry.icon,tx,ty,icon,entry.gained and C.gold or C.text)end
            end
            if(traits[1].gained or not traits[1].icon)and w>=96 and h>=170 then
                local size=w>=180 and 16 or 14
                rect(bx+3,ty+icon+4,w-6,size+7,{.10,.065,.02,.97},3)
                self:strong(self:fit(traits[1].label,w-12,size,1),bx+6,ty+icon+7,size,C.gold,w-12)
            end
        end
        if type(card.counters)=='table' then
            local labels={};for k,v in pairs(card.counters) do
                local name,count=k,v;if type(v)=='table'then name=v.name or v.type or k;count=v.count or v.amount or 0 end
                if tonumber(count)and tonumber(count)~=0 then labels[#labels+1]={name=tostring(name),count=count}end
            end
            table.sort(labels,function(a,b)return a.name<b.name end)
            if #labels>0 then
                local compact=h<170;local tight=h<100 and headerH>24;local rowH=compact and(tight and 16 or 20)or 26;local count=math.min(compact and 1 or 2,#labels);local counterY=compact and headerH+1 or h*.47
                rect(bx,by+counterY,w,rowH*count,{.10,.055,.18,.98},3)
                for i=1,count do
                    local entry=labels[i];local cy=by+counterY+(i-1)*rowH+1;local size=compact and(tight and 11 or 12)or 14
                    if self.model.settings.counterStyle=='Dice'and self.assets.counterBadge then
                        self.assets:counterBadge(entry.count,bx+3,cy,compact and(tight and 14 or 18)or 23,'Dice',C.gold)
                        local tx=compact and(tight and 20 or 24)or 30
                        self:strong(self:fit(entry.name,w-tx-3,size,1),bx+tx,cy+2,size,C.gold,w-tx-3)
                    else self:strong(self:fit(tostring(entry.count)..': '..entry.name,w-8,size,1),bx+4,cy+2,size,C.gold,w-8)end
                end
            end
        end
    end
    local stats=not options.imageOnly and Presentation.stats(card)
    if stats and(not card.hidden or publicFaceDown)then
        local badgeW=math.min(w-4,math.max(51,w*.39));local size=w>=100 and 20 or 16
        local tight=h<100 and headerH>24;local badgeH=tight and 26 or 30;local statsY=by+h-badgeH+2
        rect(bx+w-badgeW-1,by+h-badgeH-1,badgeW,badgeH,{.015,.025,.045,.98},4)
        if stats.damage>0 and stats.remaining~=nil then
            local prefix=tostring(card.power)..'/'
            local defense=tostring(stats.remaining)
            local font=self.assets.titleFont and self.assets:titleFont(size,self.model.settings)or self.bold
            local start=bx+w-badgeW+((badgeW-2)-font:getWidth(prefix..defense))/2
            self:strong(prefix,start,statsY,size,C.text)
            self:strong(defense,start+font:getWidth(prefix),statsY,size,C.red)
        else self:strong(stats.shown,bx+w-badgeW,statsY,size,C.text,badgeW-2,'center')end
        if stats.damage>0 then
            if w>=100 then
                rect(bx+1,by+h-31,39,30,{.23,.035,.045,.98},4)
                self:strong(tostring(stats.damage),bx+2,by+h-27,18,C.red,37,'center')
            else
                rect(bx+w-19,by+2,17,21,{.23,.035,.045,.98},3)
                self:strong(tostring(stats.damage),bx+w-18,by+5,12,C.red,15,'center')
            end
        end
    end
    local commander=boardCard and(self.boardCommanders or{})[card.id]
    if commander and not card.hidden and w>=105 and h>=145 then
        rect(bx+1,by+h-55,w-2,23,{.09,.055,.025,.98},3)
        self.assets:iconSymbol('commander',bx+4,by+h-52,17,C.gold)
        local cost=type(commander.additionalTax)=='table'and commander.additionalTax.manaCost
        local showCost=w>=100 and type(cost)=='string'and cost~=''
        self:strong('Casts '..tostring(commander.commandZonePlays or 0)..(showCost and' · Tax'or''),bx+24,by+h-52,12,C.gold,w-(showCost and 53 or 27),'center')
        if showCost then RichText.draw(self,cost,bx+w-27,by+h-52,24,{size=14,iconSize=17,color=C.gold,maxLines=1})end
    end
    local status=boardCard and Board.cardStatus and Board.cardStatus(self,card)
    if status then
        color(status.confirmed and C.accent or C.gold);love.graphics.setLineWidth(4)
        love.graphics.rectangle('line',bx-4,by-4,w+8,h+8,6,6)
        if h>=170 then
            local sy=by+math.max(27,headerH+2)
            rect(bx+2,sy,w-4,22,{.025,.035,.045,.98},3)
            self:strong(self:fit(status.label,w-9,12,1),bx+4,sy+3,12,status.confirmed and C.accent or C.gold,w-8,'center')
        else self.assets:iconSymbol('block',bx+3,by+3,16,status.confirmed and C.accent or C.gold)end
    end
    if Board.cardOverlay and not options.imageOnly then Board.cardOverlay(self,card,bx,by,w,h,options)end
    love.graphics.pop()
    if not options.noHit then self:hit({x=x,y=y,w=hitW,h=hitH,angle=angle,card=card,kind=options.kind or 'card',section=options.section,index=options.index,clip=options.clip,tooltip=(stats and stats.label or'')..(Board.mechanicTooltip and('\n'..Board.mechanicTooltip(card))or'')}) end
end
function Renderer:drawNav(w)
    rect(0,0,w,82,{.042,.054,.080},0);color(C.line);love.graphics.line(0,82,w,82)
    self.assets:divider(24,78,w-48,{.22,.35,.40,.60})
    require('app.navigation').draw(self,w)
end
function Renderer:drawDecks(w,h)require('app.collection_ui').draw(self,w,h)end
function Renderer:inputBlocked()
    local m,v=self.model,self.view
    local outcome=require('app.outcome').state(m)
    if outcome and outcome.mode=='duel'and outcome.terminal then return true end
    local dice=package.loaded['app.dice']
    return m.updateApplying or(dice and dice.busy(self))or m.cardActionSheet or m.commanderDetails or m.storageLocationConfirm or m.storageFolderDialog or m.imagePackFileDialog or m.settingsOpen or m.zoneView or m.deleteConfirm or m.inspectCard or m.galleryInspect or m.confirmConcede or m.archiveCopy or m.storagePurgePreview or m.cardPrintingPicker or m.tokenPicker
        or v and(v.tableOptionsOpen or v.cardChoiceModal or v.setPicker or v.brandMenu or v.deckSelection or v.themeColorEdit or v.combatStopsOpen or m.page=='builder'and(v.builderPopup or v.builderFiltersOpen))
        or not v and self.blockBuilderDrop
end
function Renderer:drawBuilder(w,h)
    require('app.builder').draw(self,w,h)
end
local function isLand(card)
    local t=card.type_line or card.type or card.cardType or ''
    if type(t)=='table' then t=table.concat(t,' ') end
    return tostring(t):lower():find('land',1,true)~=nil
end
function Renderer:field(player,x,y,w,opponent,rowGap)
    local lands,others={},{}
    for _,card in ipairs(player.battlefield or {}) do local list=isLand(card) and lands or others;list[#list+1]=card end
    for row,cards in ipairs({lands,others}) do
        local cw=math.min(78,(rowGap or 125)/1.50,(w-50)/math.max(1,#cards)-8);cw=math.max(28,cw);local ch=cw*1.39
        local dy=y+(opponent and (row-1) or (2-row))*(rowGap or 125)
        local start=x+(w-(#cards*(cw+12)-12))/2
        for i,card in ipairs(cards) do self:drawCard(card,start+(i-1)*(cw+12),dy,cw,ch,{kind='permanent'}) end
    end
end
function Renderer:pile(label,count,cards,x,y,back)
    local card=cards and cards[#cards]
    self:drawCard(card or {name=label},x,y,60,84,{back=back or not card,kind='pile'})
    self:text(label..'  '..tostring(count or #(cards or {})),x-11,y+89,10,C.muted,82,'center')
    self:hit({x=x,y=y,w=60,h=84,kind='zone',cards=cards or {},label=label})
end
function Renderer:drawTable(w,h) Table.draw(self,w,h) end
function Renderer:drawOutcome(w,h)
    local state=require('app.outcome').state(self.model)
    if not state or state.mode~='duel'or not state.terminal then return end
    local tint=state.outcome=='win'and C.accent or state.outcome=='loss'and C.red or C.gold
    rect(0,0,w,h,{.009,.016,.028,.94},0)
    self:panel(math.max(20,w*.14),math.max(90,h*.22),w-math.max(20,w*.14)*2,h*.55,{tint[1]*.08,tint[2]*.08,tint[3]*.08,.92})
    self.assets:iconSymbol(state.outcome=='win'and'commander'or state.outcome=='loss'and'concede'or'replay',w/2-28,h*.5-146,56,tint)
    self:strong(state.title or'Match ended',30,h*.5-70,52,tint,w-60,'center')
    if state.detail then self:text(self:fit(state.detail,w-100,16,2),50,h*.5-1,16,C.muted,w-100,'center')end
end
function Renderer:drawOrdering(w,h,prompt)
    local choices=self.model.promptOrder;local bw=Layout.table(w,h).board.w;local panelW=math.min(bw-80,math.max(350,#choices*151+24))
    if self.lastOrderPrompt~=prompt.id then self.lastOrderPrompt=prompt.id;self.orderScroll=0 end
    rect((bw-panelW)/2,h/2-115,panelW,233,{.075,.09,.16,.99},12)
    self:text('RESOLVE FIRST  →  RESOLVE LAST',(bw-panelW)/2+18,h/2-99,12,C.accent)
    self:text('Drag abilities left to right, then confirm in the action panel.',(bw-panelW)/2+18,h/2-76,11,C.muted)
    local cw=141;local left=(bw-panelW)/2+16;local right=(bw+panelW)/2-16
    self.orderScrollMax=math.max(0,#choices*151-(panelW-32));self.orderScroll=math.min(self.orderScroll or 0,self.orderScrollMax)
    Layout.clip(left,h/2-44,panelW-32,137)
    for i,c in ipairs(choices) do
        local x=left+(i-1)*(cw+10)-(self.orderScroll or 0);local y=h/2-43
        rect(x,y,cw,134,{.12,.14,.24},8);self:text(i,x+10,y+9,18,C.gold)
        self:text(self:fit(c.label or c.name or tostring(c.id),cw-20,12,5),x+10,y+39,12,C.text,cw-20)
        if x+cw>left and x<right then self:hit({x=math.max(left,x),y=y,w=math.min(right,x+cw)-math.max(left,x),h=134,kind='order',index=i,choice=c}) end
    end
    Layout.clip()
    if self.orderScrollMax>0 then self:text('Mouse wheel scrolls the ability row.',left,h/2+97,10,C.gold) end
    if self.drag and self.drag.kind=='order' then
        local mx,my=Layout.mouse();rect(mx-55,my-30,110,75,{.20,.25,.36,.95},8);self:text(self.drag.choice.label or '',mx-48,my-22,11,C.text,96)
    end
end
function Renderer:drawPreview(w,h)
    local hit=self.model.stackHover or self.model.logHover or self.model.choiceHover or self.hover
    if hit and hit.kind=='library-top'and not self.model:libraryTopCurrent(hit.libraryPlayerId,hit.card.id,hit.libraryGameId)then return end
    if hit and hit.sourceCard and not hit.card then hit={card=hit.sourceCard,kind='stack'}end
    if self.model.settings.showTooltips==false then return end
    if self.uiHovered and not(self.model.stackHover or self.model.logHover or self.model.choiceHover)then return end
    if love.mouse.isDown(1)and(self.model.choiceHover or self.model.stackHover or self.model.logHover)then return end
    if hit and hit.tooltip and (not hit.card or hit.kind=='player' or hit.kind=='seat-focus')and not self.drag then
        local tooltip=Text.clean(hit.tooltip)
        local x,y=Layout.mouse();local width=math.min(380,self.fonts[13]:getWidth(tooltip)+24)
        local _,lines=self.fonts[13]:getWrap(tooltip,width-24);local height=math.min(hit.commanderDetails and h-16 or 160,#lines*18+18)
        x=math.max(8,math.min(w-width-8,x+16));y=math.max(8,math.min(h-height-8,y+20))
        self:panel(x,y,width,height,'dark')
        love.graphics.push('all');Layout.clip(x+4,y+4,width-8,height-8);self:text(tooltip,x+12,y+8,13,C.text,width-24);love.graphics.pop();return
    end
    if self.drag or self.panGesture or not hit or not hit.card or hit.kind=='pile' or hit.kind=='player' or hit.kind=='hand' then return end
    if self.model.page=='builder'and self.model.settings.builderLayout~='Simplified'then return end
    local card=self.model:cardData(hit.card);if not card then return end
    local mx,my=Layout.mouse();local pw=math.min(320,math.max(280,w*.165));local ph=pw*1.4
    local x=mx> w/2 and math.max(15,mx-pw-20) or math.min(w-pw-20,mx+25);local y=math.max(85,math.min(h-ph-140,my-ph/2))
    self:drawCard(Presentation.peek(hit.card),x,y,pw,ph,{noHit=true,angle=0,fullImage=true})
    local owner=(self.boardPlayers or{})[hit.card.ownerId];local controller=(self.boardPlayers or{})[hit.card.controllerId]
    local stats=Presentation.stats(hit.card);local commander=(self.boardCommanders or{})[hit.card.id]
    if owner or controller or stats or commander then
        self:panel(x,y+ph+3,pw,commander and 128 or(stats and 94 or 70),'dark')
        self:text('Owner · '..(owner and owner.name or'Unknown'),x+7,y+ph+8,12,owner and self:playerColor(owner)or C.muted,pw-14)
        if controller and controller~=owner then self:text('Controller · '..controller.name,x+7,y+ph+27,12,self:playerColor(controller),pw-14)end
        if stats then self:text(self:fit(stats.label,pw-14,14,2),x+7,y+ph+46,14,stats.damage>0 and C.red or C.muted,pw-14)end
        if commander then RichText.draw(self,Presentation.commanderLabel(commander),x+7,y+ph+(stats and 77 or 45),pw-14,{size=12,iconSize=14,color=C.gold,maxLines=2})end
    end
    local attached=(self.boardAttached or{})[hit.card.id]or{}
    local linked=hit.card.linkedExile or{}
    if #attached+#linked>0 then
        local side=x>pw+170 and x-164 or x+pw+8
        local entries={}
        for _,entry in ipairs(attached)do entries[#entries+1]={card=entry,label=entry.name or'Attachment'}end
        for _,entry in ipairs(linked)do entries[#entries+1]={card=entry,label='Exiled · '..(entry.hidden and'Hidden card'or entry.name or'Card')}end
        local rows=math.min(4,#entries);local overflow=#entries>rows
        self:panel(side,y,156,38+rows*65+(overflow and 20 or 0),'dark')
        self:strong('Attached / linked',side+8,y+8,13,C.gold,140)
        for i=1,rows do
            local entry=entries[i]
            self:drawCard(entry.card,side+8,y+34+(i-1)*65,44,62,{noHit=true,angle=0,back=entry.card.hidden or entry.card.faceDown})
            self:text(self:fit(entry.label,90,12,3),side+56,y+36+(i-1)*65,12,C.text,90)
        end
        if overflow then self:text('+'..(#entries-rows)..' more · right-click',side+8,y+38+rows*65,12,C.muted,140)end
    end
end
function Renderer:drawToasts(w,h)
    for i,t in ipairs(self.model.toasts) do
        local width=math.min(650,w-40);local y=h-52-(#self.model.toasts-i)*48
        rect((w-width)/2,y,width,40,{.10,.15,.20,.98},7);rect((w-width)/2,y,4,40,t.bad and C.red or C.accent,2)
        self:text(t.message,(w-width)/2+16,y+12,12,t.bad and {1,.65,.65} or C.text,width-30)
    end
end
function Renderer:draw()
    self.poseFrame=(self.poseFrame or 0)+1
    self.previousCardRects=self.cardRects;self.previousPlayerRects=self.playerRects;self.previousZoneRects=self.zoneRects
    self.zoneRects={}
    self.hits={};self.cardRects={};self.multiplayerView=nil;Board.prepare(self);local w,h=Layout.dimensions();rect(0,0,w,h,C.bg,0)
    if self.assets.background then self.assets:background(w,h,self.model.settings)end
    if self.model.page~='table' then self:drawNav(w) end
    if self.model.page=='decks' then self:drawDecks(w,h)
    elseif self.model.page=='builder' then self:drawBuilder(w,h)
    elseif self.model.page=='table' then self:drawTable(w,h)end
    Board.links(self);require('app.storage').drawProgress(self,w,h)
    if self.model.page=='table'then self:drawOutcome(w,h)end
    -- Positions are a presentation cache, not an archive of every native
    -- object ever created. Keep current poses and a short transition grace.
    for key,pose in pairs(self.poses)do if(self.poseFrame-(pose.seenFrame or 0))>2 then self.poses[key]=nil end end
end
function Renderer:mousemoved(x,y)
    if self.builderResize and(self.model.page~='builder'or self.model.settings.builderLayout~='Simplified'or self:inputBlocked())then self.builderResize=nil end
    if self.builderResize then
        local _,h=Layout.dimensions();local Simple=require('app.builder_simplified')
        self.model.simpleBuilderSplitRatio=Simple.splitRatio(h,y-self.builderResize.offset)
        self.model.simpleDeckScroll=0
    end
    local pan=self.panGesture
    if pan then
        local distance=math.abs(x-pan.startX)+math.abs(y-pan.startY)
        if pan.moved or distance>6 then
            if not pan.moved then self.tableCamera:pan(x-pan.startX,y-pan.startY)
            else self.tableCamera:pan(x-pan.x,y-pan.y) end
            pan.moved=true
        end
        pan.x=x;pan.y=y
    end
    self.hover=nil
    for i=#self.hits,1,-1 do if inside(self.hits[i],x,y) then self.hover=self.hits[i];break end end
end
function Renderer:mousepressed(x,y,button,clicks)
    self:mousemoved(x,y)
    local hit=self.hover;if self:inputBlocked()then return end
    if hit and hit.kind=='library-top'and not self.model:libraryTopCurrent(hit.libraryPlayerId,hit.card.id,hit.libraryGameId)then return end
    if button==2 and self.model.page=='table' and (not hit or hit.kind~='hand') and require('app.multiplayer_table').within(self.multiplayerView,x,y) then
        self.panGesture={startX=x,startY=y,x=x,y=y,hit=hit};return
    end
    if not hit then return end
    if button==2 and hit.card then self:inspectHitCard(hit);return end
    if button~=1 then return end
    if hit.kind=='builder-divider'then self.builderResize={offset=y-hit.split};return end
    if hit.action then
        self:sound('click');hit.action()
        if clicks==2 and hit.deck then self.model:openDeck(hit.deck) end
    elseif self.model.replay and hit.card and hit.kind~='player' then self:inspectHitCard(hit)
    elseif hit.kind=='library-top'and not self.model:canSelect(hit.card.id)then self:inspectHitCard(hit)
    elseif hit.kind=='builder-card'then
        self:selectPreviewCard(hit.card)
        if clicks==2 then self.model:addCard(hit.card,hit.section or self.model.selectedSection,-1)end
    elseif hit.kind=='search' or hit.kind=='hand' or hit.kind=='exile-hand' or hit.kind=='permanent' or hit.kind=='command' or hit.kind=='order'or hit.kind=='library-top' then
        if hit.kind=='search' and clicks==2 then self.model:addCard(hit.card);return end
        self.drag=hit;self.dragStart={x,y};self.dragPos={x=x,y=y};self.dragPage=self.model.page;self.dragEditorGeneration=self.model.editGeneration
    elseif hit.kind=='player' then
        if self.model:canSelect(hit.card.id) then self.model:selectCard(hit.card)
        elseif hit.focusIndex and self.tableCamera then self.tableCamera:focus(hit.focusIndex) end
    elseif hit.kind=='zone' then
        if hit.playerId and hit.zone then self.model:openZone(hit.playerId,hit.zone,hit.label)
        else self.model.zoneView={label=hit.label,cards=hit.cards,gameId=self.model.game and self.model.game.gameId}end
    end
end
function Renderer:inspectHitCard(hit)
    if hit.kind=='library-top'then return self.model:inspectLibraryTop(hit.libraryPlayerId,hit.card.id,hit.libraryGameId)end
    local card=Presentation.peek(hit.card)
    self:selectPreviewCard(card);self.model.inspectCard=card;return true
end
function Renderer:selectPreviewCard(card)
    if self.model.page=='builder'and self.model.selectBuilderArtwork then self.model:selectBuilderArtwork(card)
    else self.model.previewCard=card end
end
function Renderer:mousereleased(x,y,button)
    if button==1 and self.builderResize then self:mousemoved(x,y);self.builderResize=nil;return end
    if button==2 and self.panGesture then
        self:mousemoved(x,y)
        local pan=self.panGesture;self.panGesture=nil
        if not pan.moved and pan.hit and pan.hit.card and pan.hit.kind~='player' then
            self:inspectHitCard(pan.hit)
        end
        return
    end
    if button~=1 or not self.drag then return end
    local d=self.drag;self.drag=nil
    if d.kind=='library-top'and not self.model:libraryTopCurrent(d.libraryPlayerId,d.card.id,d.libraryGameId)then self.dragPos=nil;return end
    local distance=math.abs(x-self.dragStart[1])+math.abs(y-self.dragStart[2]);local w,h=Layout.dimensions()
    local accepted=false
    if d.kind=='search' then
        local drop=self.builderDrop or require('app.builder').layout(w,h,self.model.settings.builderLayout,self.model.simpleBuilderSplitRatio).list
        local current=self.model.page=='builder'and(not self.dragEditorGeneration or self.dragEditorGeneration==self.model.editGeneration)
        if current and not self:inputBlocked()and distance>8 and drop and x>=drop.x and x<=drop.x+drop.w and y>=drop.y and y<=drop.y+drop.h then
            self.model:addCard(d.card);accepted=true
            self:burst('click',drop.x+drop.w/2,math.min(y,drop.y+80),9)
        elseif current then self:selectPreviewCard(d.card)end
    elseif d.kind=='order'and not self:inputBlocked()and(not self.dragPage or self.dragPage==self.model.page)then
        local target
        for _,hit in ipairs(self.hits) do if hit.kind=='order' and inside(hit,x,y) then target=hit.index end end
        if target and target~=d.index then local choice=table.remove(self.model.promptOrder,d.index);table.insert(self.model.promptOrder,target,choice) end
    elseif d.card and not self:inputBlocked()and(not self.dragPage or self.dragPage==self.model.page)then
        local L=Layout.table(w,h,self.model)
        local tableDrop=not self.uiHovered and(self.multiplayerView and require('app.multiplayer_table').within(self.multiplayerView,x,y) or (not self.multiplayerView and x<L.board.x+L.board.w and y>200 and y<h-135))
        if distance<8 or tableDrop then
            self.lastSelected={x=d.x,y=d.y,w=d.w,h=d.h}
            accepted=Actions.select(self.model,d.card)
        end
    end
    if d.card and distance>8 and not self.model.settings.reducedMotion and self.model.settings.animations~=false then
        local target=accepted and d.kind~='search' and {x=x,y=y} or {x=d.x+d.w/2,y=d.y+d.h/2}
        self.ghosts[#self.ghosts+1]={card=d.card,from={x=x,y=y},target=target,time=0,duration=accepted and .22 or .28,accepted=accepted}
    end
    self.dragPos=nil
end
function Renderer:drawForeground()
    local outcome=require('app.outcome').state(self.model)
    if outcome and outcome.mode=='duel'and outcome.terminal then return end
    Board.foreground(self)
    if self.drag and self.drag.card and self.dragPos then
        self:drawCard(self.drag.card,self.dragPos.x-77,self.dragPos.y-108,154,216,{noHit=true,imageOnly=self.drag.kind=='search'})
    end
    for _,g in ipairs(self.ghosts) do
        local t=math.min(1,g.time/g.duration);local ease=1-(1-t)^3
        local x=g.from.x+(g.target.x-g.from.x)*ease;local y=g.from.y+(g.target.y-g.from.y)*ease
        local size=g.accepted and 154*(1-t*.35) or 154
        self:drawCard(g.card,x-size/2,y-size*.7,size,size*1.4,{noHit=true,imageOnly=true})
    end
    if self.model.settings.particles~=false and not self.model.settings.reducedMotion then self.assets:drawParticles() end
    if not self:inputBlocked()then local w,h=Layout.dimensions();self:drawPreview(w,h)end
    local state=self.model.activityState and self.model:activityState()
    if state and state.busy==true then
        local w,h=Layout.dimensions();local mx,my=Layout.mouse();local x,y=math.min(w-26,mx+19),math.min(h-26,my+20)
        self.assets:loadingCircle(x,y,20,love.timer.getTime(),C.gold,self.model.settings.reducedMotion or self.model.settings.animations==false)
        if(tonumber(state.elapsed)or 0)>=.8 then
            local label=tostring(state.label or'Waiting for a response')..' · '..string.format('%.1fs',tonumber(state.elapsed)or 0)
            local width=math.min(350,self.fonts[12]:getWidth(label)+22);local tx=math.max(8,math.min(w-width-8,x+26));local ty=math.max(8,math.min(h-36,y))
            self:panel(tx,ty,width,32,'dark');self:text(self:fit(label,width-18,12,1),tx+9,ty+9,12,C.gold,width-18)
        end
    end
end
function Renderer:wheelmoved(dx,dy)
    if self.uiHovered or self:inputBlocked()then return end
    local x,y=Layout.mouse();local w,h=Layout.dimensions();local p=self.model:prompt()
    if self.model.page=='table'and self.handBounds and y>=self.handBounds.y and x>=self.handBounds.x and x<=self.handBounds.x+self.handBounds.w then self.handScroll=math.max(0,math.min(self.handScrollMax or 0,(self.handScroll or 0)-dy*3))
    elseif self.model.page=='decks' and x<w-350 and y>180 then self.deckScroll=math.max(0,math.min(self.deckScrollMax or 0,(self.deckScroll or 0)-dy*50))
    elseif self.model.page=='builder'and self.model.settings.builderLayout=='Simplified'then require('app.builder_simplified').wheel(self.model,self.simpleBuilderLayout or require('app.builder').layout(w,h,'Simplified',self.model.simpleBuilderSplitRatio),x,y,dy)
    elseif self.model.page=='table' and p and p.type=='order' and x<w-348 then self.orderScroll=math.max(0,math.min(self.orderScrollMax or 0,(self.orderScroll or 0)-(dy+dx)*90))
    elseif self.model.page=='table' and self.tableCamera and require('app.multiplayer_table').within(self.multiplayerView,x,y) and not (self.hover and self.hover.kind=='hand') then
        self.tableCamera:zoomAt(math.exp(dy*.12),x,y)
    end
end
return Renderer
