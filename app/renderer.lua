local Layout=require('app.layout')
local Assets=require('app.assets')
local Table=require('app.table')
local RichText=require('app.richtext')
local Board=require('app.board_fx')
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
function Renderer:text(text,x,y,size,tint,width,align)
    love.graphics.setFont(self.fonts[size or 14]);color(tint or C.text)
    if width then love.graphics.printf(tostring(text or ''),x,y,width,align or 'left') else love.graphics.print(tostring(text or ''),x,y) end
end
function Renderer:strong(text,x,y,size,tint,width,align)
    local scale=(size or 22)/22
    love.graphics.push();love.graphics.translate(x,y);love.graphics.scale(scale)
    love.graphics.setFont(self.assets.titleFont and self.assets:titleFont(22,self.model.settings)or self.bold);color(tint or C.text)
    if width then love.graphics.printf(tostring(text or ''),0,0,width/scale,align or'left')else love.graphics.print(tostring(text or''),0,0)end
    love.graphics.pop()
end
function Renderer:playerColor(player)return Board.color(self,player)end
function Renderer:drawPermanent(card,x,y,w,h,options)return Board.layers(self,card,x,y,w,h,options)end
function Renderer:priorityBadge(player,x,y,w,height)return Board.priority(self,player,x,y,w,height)end
function Renderer:drawAvatar(player,x,y,size)
    local m=self.model;local profile=player and m.profileForPlayer and m:profileForPlayer(player)or m.profile or{}
    local art=m.profileArt and m:profileArt(profile.avatar)
    if not art and player and player.avatarCard then art=m:getArt(player.avatarCard,true,'art_crop')end
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
    local art=m.profileArt and m:profileArt(profile.playmat);if not art then return end
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
    local _,wrapped=self.fonts[size]:getWrap(tostring(text or ''),width)
    if #wrapped<=lines then return table.concat(wrapped,'\n') end
    local out={};for i=1,lines do out[i]=wrapped[i] end
    while #out[lines]>0 and self.fonts[size]:getWidth(out[lines]..'…')>width do
        local last=utf8.offset(out[lines],-1);out[lines]=out[lines]:sub(1,last-1)
    end
    out[lines]=out[lines]..'…';return table.concat(out,'\n')
end
function Renderer:screenRect(box)
    local t=self.worldTransform
    if not t then return box end
    return {x=t.x+box.x*t.scale,y=t.y+box.y*t.scale,w=box.w*t.scale,h=box.h*t.scale,angle=box.angle,clip=t.clip}
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
    options=options or{}
    local mx,my=Layout.mouse();local hot=mx>=x and mx<=x+w and my>=y and my<=y+h
    self.assets:control(x,y,w,h,active and 'accent' or 'dark')
    if hot then rect(x+2,y+2,w-4,h-4,{.14,.27,.31,.35},7) end
    if active then rect(x,y+h-3,w,3,C.accent,1) end
    local size=options.size or 14
    self:text(label,x,y+(h-self.fonts[size]:getHeight())/2+require('app.fonts').textOffset(self.fonts[size],label),size,active and C.accent or C.text,w,'center')
    self:hit({x=x,y=y,w=w,h=h,action=action,tooltip=options.tooltip or label})
end
function Renderer:drawCard(card,x,y,w,h,options)
    options=options or {};options.back=options.back or card.hidden
    local angle=options.angle or (card.tapped and math.pi/2 or 0)
    if options.animate and card.id then
        local key=(self.worldTransform and 'world:' or 'screen:')..card.id;local target={x=x,y=y,w=w,h=h,angle=angle};local pose=self.poses[key]
        if not pose then pose={x=x,y=y+38,w=w,h=h,angle=angle};self.poses[key]=pose end
        local ease=(self.model.settings.reducedMotion or self.model.settings.animations==false) and 1 or 1-math.exp(-self.dt*15)
        for k,v in pairs(target) do pose[k]=pose[k]+(v-pose[k])*ease end
        x,y,w,h,angle=pose.x,pose.y,pose.w,pose.h,pose.angle
    end
    if not options.noHit and(options.kind=='permanent'or options.kind=='attachment')and self.model.settings.animations~=false and not self.model.settings.reducedMotion then local dx,dy=Board.offset(self,card);x=x+dx;y=y+dy end
    if card.id and not options.noHit then
        local box=self:screenRect({x=x,y=y,w=w,h=h,angle=angle});box.kind=options.kind;self.cardRects[card.id]=box
    end
    if self.drag and self.drag.card and self.drag.card.id==card.id and not options.noHit then return end
    love.graphics.push();love.graphics.translate(x+w/2,y+h/2);love.graphics.rotate(angle)
    local bx,by=-w/2,-h/2
    rect(bx+3,by+5,w,h,{.005,.009,.016,.6},7)
    if options.back then
        rect(bx,by,w,h,{.07,.075,.14},7);color({.32,.29,.55});love.graphics.rectangle('line',bx+5,by+5,w-10,h-10,5,5)
        color(C.purple,.5);love.graphics.circle('line',0,0,w*.28);love.graphics.polygon('line',0,-w*.25,w*.20,0,0,w*.25,-w*.20,0)
    else
        local data=self.model:cardData(card) or card
        local img=self.model:getArt(data,options.imageOnly)
        local selectable=options.selectable or self.model:canSelect(card.id)
        if selectable then
            rect(bx-5,by-5,w+10,h+10,{C.accent[1],C.accent[2],C.accent[3],.17},9)
        end
        rect(bx-2,by-2,w+4,h+4,selectable and C.accent or { .21,.25,.32 },7)
        if img then color({1,1,1});love.graphics.draw(img,bx,by,0,w/img:getWidth(),h/img:getHeight())
        elseif options.imageOnly then
            rect(bx,by,w,h,{.075,.095,.13},6)
            local size=h<180 and 10 or 12;local icon=math.min(w*.32,36)
            self.assets:iconSymbol('image',-icon/2,by+h*.14,icon,C.muted)
            local status=self.model.artworkLabel and self.model:artworkLabel(data)or'Artwork unavailable'
            self:text(self:fit(status,w-14,size,2),bx+7,by+h*.46,size,C.muted,w-14,'center')
            self:text(self:fit(data.name or'',w-14,size,2),bx+7,by+h-size*2-12,size,C.text,w-14,'center')
        else
            rect(bx,by,w,h,{.10,.125,.17},6)
            local colors=data.colors or data.color_identity or {};local tint=C.purple
            if colors[1]=='G' then tint=C.accent elseif colors[1]=='R' then tint=C.red elseif colors[1]=='U' then tint={.28,.58,.94} elseif colors[1]=='W' then tint=C.gold end
            rect(bx+5,by+26,w-10,h*.39,{tint[1]*.33,tint[2]*.33,tint[3]*.33},3)
            color(tint,.5);love.graphics.circle('line',0,by+26+h*.20,w*.21)
            local nameSize=w<100 and 10 or 12
            self:strong(self:fit(data.name or card.name or'Unknown',w-14,nameSize,2),bx+7,by+6,nameSize,C.text,w-14)
            self:text(self:fit(data.type_line or card.type or '',w-12,10,2),bx+6,by+h*.57,10,C.muted,w-12)
            if w>=180 then
                local text=data.oracle_text or card.rules or ''
                if type(text)=='table' then text=table.concat(text,'\n') end
                text=tostring(text):gsub('<[^>]+>','')
                if #text>100 then text=text:sub(1,97)..'...' end
                RichText.draw(self,text,bx+7,by+h*.68,w-14,{size=10,iconSize=11,color=C.text,maxLines=3})
            end
                local cost=data.mana_cost or card.manaCost or '';if cost~='' then self.assets:mana(cost,bx+7,by+h-19,13) end
        end
        if not options.imageOnly and card.power and card.toughness and (tostring(data.type_line or card.type or ''):lower():find('creature',1,true) or card.power~='0' or card.toughness~='0') then
            local badgeW=math.min(w-4,math.max(45,w*.32));local size=w>=100 and 16 or 13
            rect(bx+w-badgeW-1,by+h-27,badgeW,26,{.025,.045,.075,.98},4)
            self:strong(tostring(card.power)..'/'..tostring(card.toughness),bx+w-badgeW,by+h-24,size,C.text,badgeW-2,'center')
        end
        if card.damage and tonumber(card.damage) and tonumber(card.damage)>0 then rect(bx,by+h-22,28,21,C.red,4);self:text(card.damage,bx,by+h-20,12,C.text,28,'center') end
        if card.attacking then
            color(C.red);love.graphics.setLineWidth(3);love.graphics.rectangle('line',bx-3,by-3,w+6,h+6,6,6)
            self.assets:iconSymbol('attack',bx+w-22,by+5,20,C.red)
        end
        local traits=require('app.card_traits').entries(card)
        if#traits>0 and not options.imageOnly then
            local icon=math.max(12,math.min(21,w*.16));local capacity=math.max(1,math.floor((w-10)/(icon+3)));local count=math.min(capacity,#traits)
            local ty=by+h*.26
            rect(bx+3,ty-2,count*(icon+3)+4,icon+4,{.018,.03,.05,.94},3)
            for i=1,count do local entry=traits[i];local tx=bx+5+(i-1)*(icon+3)
                if entry.icon then self.assets:iconSymbol(entry.icon,tx,ty,icon,entry.gained and C.gold or C.text)end
            end
            if(traits[1].gained or not traits[1].icon)and w>=96 then
                local size=w>=180 and 14 or 11
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
                local bh=math.min(40,20*#labels);rect(bx,by+h*.47,w,bh,{.10,.055,.18,.98},3)
                for i=1,math.min(2,#labels)do
                    local entry=labels[i];local cy=by+h*.47+(i-1)*20+1
                    if self.model.settings.counterStyle=='Dice'and self.assets.counterBadge then
                        self.assets:counterBadge(entry.count,bx+3,cy,18,'Dice',C.gold)
                        self:strong(self:fit(entry.name,w-29,12,1),bx+26,cy+2,12,C.gold,w-29)
                    else self:strong(self:fit(tostring(entry.count)..': '..entry.name,w-8,12,1),bx+4,cy+2,12,C.gold,w-8)end
                end
            end
        end
    end
    love.graphics.pop()
    if not options.noHit then self:hit({x=x,y=y,w=w,h=h,angle=angle,card=card,kind=options.kind or 'card',section=options.section,index=options.index,clip=options.clip}) end
end
function Renderer:drawNav(w)
    rect(0,0,w,82,{.042,.054,.080},0);color(C.line);love.graphics.line(0,82,w,82)
    self.assets:divider(24,78,w-48,{.22,.35,.40,.60})
    if not self.brandIcon then self.brandIcon=love.graphics.newImage(self.assets:icon()) end
    color(C.gold);love.graphics.draw(self.brandIcon,24,18,0,44/self.brandIcon:getWidth(),44/self.brandIcon:getHeight())
    self:strong(w<1250 and'Love: 2G'or'Love: 2 Gathering',81,27,20,C.text)
    local pages={{'Decks','decks'},{'Builder','builder'},{'Lobby','lobby'},{'Rooms','rooms'},{'Replays','replays'},{'Gallery','gallery'}}
    if self.model.game then pages[#pages+1]={'Match','table'} end
    local navX=w<1250 and 198 or 292;local gap=w<1250 and 5 or 8
    local px=w-346;local navW=math.min(200,math.floor((px-18-navX-(#pages-1)*gap)/#pages))
    for i,item in ipairs(pages) do self:button(item[1],navX+(i-1)*(navW+gap),16,navW,50,function()
        if item[2]=='builder' and not self.model.editDeck then self.model:newDeck()
        elseif item[2]=='replays' then self.model:showReplays()
        elseif item[2]=='gallery' then self.model:showGallery() else self.model.page=item[2] end
        if item[2]=='rooms' then self.model:showRooms() end
    end,self.model.page==item[2],{size=w<1250 and 16 or 18}) end
    self:button('Settings',w-150,16,126,50,function() self.model:openSettings()end,self.model.page=='settings',{size=18})
    local m=self.model;local profile=m.profile or{name=m.playerName}
    self.assets:control(px,16,184,50,m.page=='profile'and'accent'or'dark')
    self:drawAvatar(nil,px+6,22,38);self:strong(self:fit(profile.name or'Profile',126,16,1),px+51,22,16,C.text,126)
    local life;for _,p in ipairs(m.game and m.game.players or{})do if p.human or p.isLocal then life=p.life end end
    self:text(life and tostring(life)..' life'or'Profile',px+51,44,12,C.muted,126)
    local ready=m.engineHealth.ok or m.engineHealth.status=='ok'or m.engineHealth.ready
    color(ready and C.accent or C.gold);love.graphics.circle('fill',px+176,20,3)
    self:hit({x=px,y=16,w=184,h=50,action=function()m:showProfile()end,tooltip=(profile.name or'Profile')..' · '..(ready and'XMage connected'or'XMage starting')})
end
function Renderer:drawDecks(w,h)require('app.collection_ui').draw(self,w,h)end
function Renderer:inputBlocked()
    local m,v=self.model,self.view
    return m.settingsOpen or m.zoneView or m.deleteConfirm or m.inspectCard or m.galleryInspect or m.confirmConcede or m.archiveCopy or m.storagePurgePreview
        or v and(v.deckSelection or v.themeColorEdit or v.combatStopsOpen or m.page=='builder'and(v.builderPopup or v.builderFiltersOpen))
        or not v and self.blockBuilderDrop
end
function Renderer:drawBuilder(w,h)
    require('app.builder').draw(self,w,h)
    local mode=self.model.settings.builderLayout or'Classic'
    for i,value in ipairs({'Classic','Simplified'})do self:button(value,w-258+(i-1)*118,102,110,34,function()self.model:setBuilderLayout(value)end,mode==value,{tooltip=value..' deck builder layout'})end
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
    if hit and hit.sourceCard and not hit.card then hit={card=hit.sourceCard,kind='stack'}end
    if self.model.settings.showTooltips==false then return end
    if self.uiHovered and not(self.model.stackHover or self.model.logHover or self.model.choiceHover)then return end
    if love.mouse.isDown(1)and(self.model.choiceHover or self.model.stackHover or self.model.logHover)then return end
    if hit and hit.tooltip and (not hit.card or hit.kind=='player' or hit.kind=='seat-focus')and not self.drag then
        local x,y=Layout.mouse();local width=math.min(380,self.fonts[13]:getWidth(hit.tooltip)+24)
        local _,lines=self.fonts[13]:getWrap(hit.tooltip,width-24);local height=math.min(160,#lines*18+18)
        x=math.max(8,math.min(w-width-8,x+16));y=math.max(8,math.min(h-height-8,y+20))
        self:panel(x,y,width,height,'dark');self:text(hit.tooltip,x+12,y+8,13,C.text,width-24);return
    end
    if self.drag or self.panGesture or not hit or not hit.card or hit.kind=='pile' or hit.kind=='player' or hit.kind=='hand' then return end
    if self.model.page=='builder'and self.model.settings.builderLayout~='Simplified'then return end
    local card=self.model:cardData(hit.card);if not card then return end
    local mx,my=Layout.mouse();local pw=244;local ph=342
    local x=mx> w/2 and math.max(15,mx-pw-20) or math.min(w-pw-20,mx+25);local y=math.max(85,math.min(h-ph-70,my-ph/2))
    self:drawCard(hit.card,x,y,pw,ph,{noHit=true,angle=0})
    local owner=(self.boardPlayers or{})[hit.card.ownerId];local controller=(self.boardPlayers or{})[hit.card.controllerId]
    if owner or controller then
        self:panel(x,y+ph+3,pw,50,'dark')
        self:text('Owner · '..(owner and owner.name or'Unknown'),x+7,y+ph+8,12,owner and self:playerColor(owner)or C.muted,pw-14)
        if controller and controller~=owner then self:text('Controller · '..controller.name,x+7,y+ph+27,12,self:playerColor(controller),pw-14)end
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
    self.previousCardRects=self.cardRects;self.previousPlayerRects=self.playerRects
    self.hits={};self.cardRects={};self.multiplayerView=nil;Board.prepare(self);local w,h=Layout.dimensions();rect(0,0,w,h,C.bg,0)
    if self.assets.background then self.assets:background(w,h,self.model.settings)end
    if self.model.page~='table' then self:drawNav(w) end
    if self.model.page=='decks' then self:drawDecks(w,h)
    elseif self.model.page=='builder' then self:drawBuilder(w,h)
    elseif self.model.page=='table' then self:drawTable(w,h)
    elseif self.model.page=='replays' then
        self:strong('Replays',28,101,28,C.text)
    elseif self.model.page=='lobby' then
        self:strong('Lobby',28,103,28,C.text)
    end
    Board.links(self);self:drawPreview(w,h);require('app.storage').drawProgress(self,w,h)
end
function Renderer:mousemoved(x,y)
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
    if button==2 and self.model.page=='table' and (not hit or hit.kind~='hand') and require('app.multiplayer_table').within(self.multiplayerView,x,y) then
        self.panGesture={startX=x,startY=y,x=x,y=y,hit=hit};return
    end
    if not hit then return end
    if button==2 and hit.card then self.model.previewCard=hit.card;self.model.inspectCard=hit.card;return end
    if button~=1 then return end
    if hit.action then
        self:sound('click');hit.action()
        if clicks==2 and hit.deck then self.model:openDeck(hit.deck) end
    elseif self.model.replay and hit.card and hit.kind~='player' then self.model.inspectCard=hit.card
    elseif hit.kind=='builder-card'then
        self.model.previewCard=hit.card
        if clicks==2 then self.model:addCard(hit.card,hit.section or self.model.selectedSection,-1)end
    elseif hit.kind=='search' or hit.kind=='hand' or hit.kind=='permanent' or hit.kind=='command' or hit.kind=='order' then
        if hit.kind=='search' and clicks==2 then self.model:addCard(hit.card);return end
        self.drag=hit;self.dragStart={x,y};self.dragPos={x=x,y=y};self.dragPage=self.model.page;self.dragEditorGeneration=self.model.editGeneration
    elseif hit.kind=='player' then
        if self.model:canSelect(hit.card.id) then self.model:selectCard(hit.card)
        elseif hit.focusIndex and self.tableCamera then self.tableCamera:focus(hit.focusIndex) end
    elseif hit.kind=='zone' then self.model.zoneView={label=hit.label,cards=hit.cards} end
end
function Renderer:mousereleased(x,y,button)
    if button==2 and self.panGesture then
        self:mousemoved(x,y)
        local pan=self.panGesture;self.panGesture=nil
        if not pan.moved and pan.hit and pan.hit.card and pan.hit.kind~='player' then
            self.model.previewCard=pan.hit.card;self.model.inspectCard=pan.hit.card
        end
        return
    end
    if button~=1 or not self.drag then return end
    local d=self.drag;self.drag=nil
    local distance=math.abs(x-self.dragStart[1])+math.abs(y-self.dragStart[2]);local w,h=Layout.dimensions()
    local accepted=false
    if d.kind=='search' then
        local drop=self.builderDrop or require('app.builder').layout(w,h).list
        local current=self.model.page=='builder'and(not self.dragEditorGeneration or self.dragEditorGeneration==self.model.editGeneration)
        if current and not self:inputBlocked()and distance>8 and drop and x>=drop.x and x<=drop.x+drop.w and y>=drop.y and y<=drop.y+drop.h then
            self.model:addCard(d.card);accepted=true
            self:burst('click',drop.x+drop.w/2,math.min(y,drop.y+80),9)
        else self.model.previewCard=d.card end
    elseif d.kind=='order'and not self:inputBlocked()and(not self.dragPage or self.dragPage==self.model.page)then
        local target
        for _,hit in ipairs(self.hits) do if hit.kind=='order' and inside(hit,x,y) then target=hit.index end end
        if target and target~=d.index then local choice=table.remove(self.model.promptOrder,d.index);table.insert(self.model.promptOrder,target,choice) end
    elseif d.card and not self:inputBlocked()and(not self.dragPage or self.dragPage==self.model.page)then
        local L=Layout.table(w,h)
        local tableDrop=not self.uiHovered and(self.multiplayerView and require('app.multiplayer_table').within(self.multiplayerView,x,y) or (not self.multiplayerView and x<L.board.x+L.board.w and y>200 and y<h-135))
        if distance<8 or tableDrop then
            self.lastSelected={x=d.x,y=d.y,w=d.w,h=d.h}
            accepted=self.model:selectCard(d.card)
        end
    end
    if d.card and distance>8 and not self.model.settings.reducedMotion and self.model.settings.animations~=false then
        local target=accepted and d.kind~='search' and {x=x,y=y} or {x=d.x+d.w/2,y=d.y+d.h/2}
        self.ghosts[#self.ghosts+1]={card=d.card,from={x=x,y=y},target=target,time=0,duration=accepted and .22 or .28,accepted=accepted}
    end
    self.dragPos=nil
end
function Renderer:drawForeground()
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
    if self.model.stackHover or self.model.logHover or self.model.choiceHover then local w,h=Layout.dimensions();self:drawPreview(w,h)end
end
function Renderer:wheelmoved(dx,dy)
    if self.uiHovered or self.model.settingsOpen or self.model.zoneView or self.model.inspectCard then return end
    local x,y=Layout.mouse();local w,h=Layout.dimensions();local p=self.model:prompt()
    if self.model.page=='decks' and x<w-350 and y>230 then self.deckScroll=math.max(0,math.min(self.deckScrollMax or 0,(self.deckScroll or 0)-dy*50))
    elseif self.model.page=='builder'and self.model.settings.builderLayout=='Simplified'then require('app.builder_simplified').wheel(self.model,self.simpleBuilderLayout or require('app.builder').layout(w,h,'Simplified'),x,y,dy)
    elseif self.model.page=='table' and p and p.type=='order' and x<w-348 then self.orderScroll=math.max(0,math.min(self.orderScrollMax or 0,(self.orderScroll or 0)-(dy+dx)*90))
    elseif self.model.page=='table' and self.tableCamera and require('app.multiplayer_table').within(self.multiplayerView,x,y) and not (self.hover and self.hover.kind=='hand') then
        self.tableCamera:zoomAt(math.exp(dy*.12),x,y)
    end
end
return Renderer
