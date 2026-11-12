local Layout=require('app.layout')
local Assets=require('app.assets')
local Table=require('app.table')
local RichText=require('app.richtext')
local utf8=require('utf8')
local Renderer={};Renderer.__index=Renderer
local C={bg={.026,.036,.060},panel={.055,.073,.106},line={.15,.21,.28},text={.90,.94,.98},muted={.46,.56,.66},accent={.28,.89,.72},purple={.62,.48,.96},red={1,.39,.40},gold={.98,.74,.34}}
Renderer.colors=C
local function color(c,a) love.graphics.setColor(c[1],c[2],c[3],a or c[4] or 1) end
local function rect(x,y,w,h,c,r) color(c);love.graphics.rectangle('fill',x,y,w,h,r or 10,r or 10) end
local function inside(hit,x,y)
    local cx,cy=hit.x+hit.w/2,hit.y+hit.h/2
    local a=-(hit.angle or 0);local dx,dy=x-cx,y-cy
    dx,dy=dx*math.cos(a)-dy*math.sin(a),dx*math.sin(a)+dy*math.cos(a)
    return math.abs(dx)<=hit.w/2 and math.abs(dy)<=hit.h/2
end
function Renderer.new(model)
    local self=setmetatable({model=model,hits={},hover=nil,drag=nil,fonts={},assets=Assets.new(),poses={},cardRects={},ghosts={},dt=1/60},Renderer)
    for _,size in ipairs({10,11,12,13,14,16,18,20,22,24,28,32,36,44,52}) do self.fonts[size]=love.graphics.newFont('assets/fonts/DejaVuSans.ttf',size) end
    self.bold=love.graphics.newFont('assets/fonts/DejaVuSans-Bold.ttf',22)
    return self
end
function Renderer:text(text,x,y,size,tint,width,align)
    love.graphics.setFont(self.fonts[size or 14]);color(tint or C.text)
    if width then love.graphics.printf(tostring(text or ''),x,y,width,align or 'left') else love.graphics.print(tostring(text or ''),x,y) end
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
    local accessible={Deuteranopia={.98,.80,.33},Protanopia={.49,.78,1},Tritanopia={1,.57,.78}}
    C.accent=accessible[s.colorblindMode] or {.28,.89,.72}
    C.muted=s.highContrast and {.72,.80,.89} or {.46,.56,.66}
    if self.drag then
        local x,y=Layout.mouse();self.dragPos=self.dragPos or {x=x,y=y}
        local ease=s.reducedMotion and 1 or 1-math.exp(-dt*25)
        self.dragPos.x=self.dragPos.x+(x-self.dragPos.x)*ease;self.dragPos.y=self.dragPos.y+(y-self.dragPos.y)*ease
    end
    for i=#self.ghosts,1,-1 do local g=self.ghosts[i];g.time=g.time+dt;if g.time>=g.duration then table.remove(self.ghosts,i) end end
    local game=self.model.game
    if game and game.revision~=self.effectRevision then
        local w,h=Layout.dimensions();local L=Layout.table(w,h)
        if self.effectGame==game.gameId then
            local stack=#(game.stack or {})
            if stack>(self.oldStack or 0) then self:burst('cast',L.board.w/2,L.divider,14);self:sound('cast')
            elseif stack<(self.oldStack or 0) then self:burst('resolve',L.board.w/2,L.divider,19);self:sound('resolve') end
            for _,p in ipairs(game.players or {}) do
                if self.oldLife and self.oldLife[p.id] and p.life<self.oldLife[p.id] then self:burst('impact',54,p.human and h-L.handH or 178,14) end
            end
        end
        self.effectGame=game.gameId;self.effectRevision=game.revision;self.oldStack=#(game.stack or {});self.oldLife={}
        for _,p in ipairs(game.players or {}) do self.oldLife[p.id]=p.life end
    end
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
function Renderer:hit(hit) self.hits[#self.hits+1]=hit;return hit end
function Renderer:panel(x,y,w,h,style) self.assets:panel(x,y,w,h,style) end
function Renderer:button(label,x,y,w,h,action,active)
    local mx,my=Layout.mouse();local hot=mx>=x and mx<=x+w and my>=y and my<=y+h
    self:panel(x,y,w,h,active and 'accent' or 'dark')
    if hot then rect(x+2,y+2,w-4,h-4,{.14,.27,.31,.35},7) end
    if active then rect(x,y+h-3,w,3,C.accent,1) end
    self:text(label,x,y+(h-20)/2,14,active and C.accent or C.text,w,'center')
    self:hit({x=x,y=y,w=w,h=h,action=action})
end
function Renderer:drawCard(card,x,y,w,h,options)
    options=options or {};local angle=options.angle or (card.tapped and math.pi/2 or 0)
    if options.animate and card.id then
        local key=card.id;local target={x=x,y=y,w=w,h=h,angle=angle};local pose=self.poses[key]
        if not pose then pose={x=x,y=y+38,w=w,h=h,angle=angle};self.poses[key]=pose end
        local ease=(self.model.settings.reducedMotion or self.model.settings.animations==false) and 1 or 1-math.exp(-self.dt*15)
        for k,v in pairs(target) do pose[k]=pose[k]+(v-pose[k])*ease end
        x,y,w,h,angle=pose.x,pose.y,pose.w,pose.h,pose.angle
    end
    if card.id and not options.noHit then self.cardRects[card.id]={x=x,y=y,w=w,h=h,angle=angle} end
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
            color(C.muted,.35);love.graphics.circle('line',0,-h*.05,math.min(w*.18,26))
            self:text('Loading artwork…',bx+7,by+h*.57,12,C.muted,w-14,'center')
            self:text(self:fit(data.name or '',w-14,12,2),bx+7,by+h-44,12,C.text,w-14,'center')
        else
            rect(bx,by,w,h,{.10,.125,.17},6)
            local colors=data.colors or data.color_identity or {};local tint=C.purple
            if colors[1]=='G' then tint=C.accent elseif colors[1]=='R' then tint=C.red elseif colors[1]=='U' then tint={.28,.58,.94} elseif colors[1]=='W' then tint=C.gold end
            rect(bx+5,by+26,w-10,h*.39,{tint[1]*.33,tint[2]*.33,tint[3]*.33},3)
            color(tint,.5);love.graphics.circle('line',0,by+26+h*.20,w*.21)
            local nameSize=w<100 and 10 or 12
            self:text(self:fit(data.name or card.name or 'Unknown',w-14,nameSize,2),bx+7,by+6,nameSize,C.text,w-14)
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
            rect(bx+w-37,by+h-21,35,20,{.04,.07,.10},4);self:text(tostring(card.power)..'/'..tostring(card.toughness),bx+w-36,by+h-19,12,C.text,34,'center')
        end
        if card.damage and tonumber(card.damage) and tonumber(card.damage)>0 then rect(bx,by+h-22,28,21,C.red,4);self:text(card.damage,bx,by+h-20,12,C.text,28,'center') end
        if card.attacking then rect(bx,by-17,w,17,{.47,.12,.16},3);self:text('ATTACKING',bx,by-15,10,C.text,w,'center') end
        if type(card.counters)=='table' then
            local labels={};for k,v in pairs(card.counters) do labels[#labels+1]=tostring(k)..':'..tostring(v) end
            if #labels>0 then rect(bx,by+h*.47,w,18,{.12,.08,.22},2);self:text(table.concat(labels,' '),bx+2,by+h*.47+2,10,C.text,w-4) end
        end
    end
    love.graphics.pop()
    if not options.noHit then self:hit({x=x,y=y,w=w,h=h,angle=angle,card=card,kind=options.kind or 'card',section=options.section,index=options.index}) end
end
function Renderer:drawNav(w)
    rect(0,0,w,82,{.042,.054,.080},0);color(C.line);love.graphics.line(0,82,w,82)
    if not self.brandIcon then self.brandIcon=love.graphics.newImage(self.assets:icon()) end
    color(C.gold);love.graphics.draw(self.brandIcon,24,18,0,44/self.brandIcon:getWidth(),44/self.brandIcon:getHeight())
    self:text('Love: 2 Gathering',81,18,18,C.text);self:text('XMAGE CLIENT',82,44,11,C.muted)
    local pages={{'Decks','decks'},{'Builder','builder'},{'Lobby','lobby'},{'Replays','replays'}}
    if self.model.game then pages[#pages+1]={'Match','table'} end
    for i,item in ipairs(pages) do self:button(item[1],292+(i-1)*104,20,96,42,function()
        if item[2]=='builder' and not self.model.editDeck then self.model:newDeck()
        elseif item[2]=='replays' then self.model:showReplays() else self.model.page=item[2] end
    end,self.model.page==item[2]) end
    self:button('Settings',w-136,20,112,42,function() self.model.settingsOpen=not self.model.settingsOpen end,self.model.settingsOpen)
    local ready=self.model.engineHealth.ok or self.model.engineHealth.status=='ok' or self.model.engineHealth.ready
    color(ready and C.accent or C.gold);love.graphics.circle('fill',w-281,39,4)
    self:text(ready and 'XMage connected' or 'XMage starting',w-264,30,12,C.muted)
end
function Renderer:drawDecks(w,h)
    local m=self.model
    self:text('Your next game starts here.',28,96,28,C.text)
    self:text('Your collection · Modern, Standard, Pioneer and Commander',29,137,16,C.muted)
    local formats={'Modern','Standard','Pioneer','Commander'}
    for i,f in ipairs(formats) do
        local n=0;for _,d in ipairs(m.decks) do if d.format:lower()==f:lower() then n=n+1 end end
        self:button(f..'  '..n,28+(i-1)*146,177,136,38,function() m.format=f;m.selectedDeck=nil end,m.format==f)
    end
    self:button('+ New deck',w-175,177,147,38,function() m:newDeck() end)
    local sidebar=330;local area=w-sidebar-74;local gap=18;local columns=math.max(1,math.min(4,math.floor(area/330)))
    local cw=(area-(columns-1)*gap)/columns;local tileH=186;local pitch=tileH+18;local y=242-(self.deckScroll or 0);local idx=0
    Layout.clip(24,234,area+12,h-250)
    for _,deck in ipairs(m.decks) do
        if deck.format:lower()==m.format:lower() then
            local x=28+(idx%columns)*(cw+gap);local dy=y+math.floor(idx/columns)*pitch
            if dy+tileH>234 and dy<h-16 then
                local selected=m.selectedDeck==deck.id
                self:panel(x,dy,cw,tileH,selected and 'accent' or 'dark')
                local cover=m.deckCoverCard and m:deckCoverCard(deck) or (deck.commander or {})[1] or (deck.main or {})[1]
                local art=cover and m:getArt(cover,true,'art_crop')
                if art then
                    local clipY=math.max(234,dy+3);local clipBottom=math.min(h-16,dy+tileH-3)
                    Layout.clip(x+3,clipY,cw-6,clipBottom-clipY)
                    local scale=math.max(cw/art:getWidth(),tileH/art:getHeight())
                    color({1,1,1},.78);love.graphics.draw(art,x+(cw-art:getWidth()*scale)/2,dy+(tileH-art:getHeight()*scale)/2,0,scale,scale)
                    rect(x+3,dy+3,cw-6,tileH-6,{.015,.025,.045,.37},5)
                    rect(x+3,dy+tileH-77,cw-6,74,{.015,.025,.045,.88},3)
                    Layout.clip(24,234,area+12,h-250)
                end
                rect(x,dy,4,tileH,selected and C.accent or C.purple,2)
                self:text(deck.format:upper(),x+18,dy+15,12,C.accent)
                self:text(self:fit(deck.name,cw-36,22,1),x+18,dy+tileH-68,22,C.text,cw-36)
                self:text(tostring(m.count(deck,'main')+m.count(deck,'commander'))..' cards  ·  '..m.count(deck,'sideboard')..' sideboard'..(deck.draft and '  ·  DRAFT' or ''),x+18,dy+tileH-32,13,C.muted)
                local hitY=math.max(234,dy);local hitBottom=math.min(h-16,dy+tileH)
                self:hit({x=x,y=hitY,w=cw,h=hitBottom-hitY,kind='deck',deck=deck,action=function() m.selectedDeck=deck.id end})
            end
            idx=idx+1
        end
    end
    Layout.clip()
    self.deckScrollMax=math.max(0,math.ceil(idx/columns)*pitch-(h-254))
    self.deckScroll=math.min(self.deckScroll or 0,self.deckScrollMax)
    local d=m:findDeck(m.selectedDeck)
    local x=w-sidebar-28
    rect(x,242,sidebar,h-270,C.panel,12)
    self:text(d and d.name or 'Choose a deck',x+20,263,22,C.text,sidebar-40)
    self:text(d and (d.description or '') or 'Select a deck to inspect its list, edit cards, duplicate it or bring it to the lobby.',x+20,324,13,C.muted,sidebar-40)
    if not d then self:text('THE COLLECTION',x+20,h-110,10,C.accent);self:text(tostring(#m.decks)..' decks available',x+20,h-86,18,C.text) end
    if #m.decks==0 then
        self:text('Loading deck library…',34,265,18,C.muted)
        self:text('Start with ./run.sh to launch the catalog and XMage bridge.',34,300,13,C.muted)
    end
end
function Renderer:drawBuilder(w,h) require('app.builder').draw(self,w,h) end
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
    local hit=self.hover
    if self.model.settings.showTooltips==false then return end
    if hit and hit.tooltip and not hit.card and not self.drag then
        local x,y=Layout.mouse();local width=self.fonts[13]:getWidth(hit.tooltip)+24
        x=math.max(8,math.min(w-width-8,x+16));y=math.max(8,math.min(h-45,y+20))
        self:panel(x,y,width,34,'dark');self:text(hit.tooltip,x+12,y+8,13,C.text);return
    end
    if self.drag or not hit or not hit.card or hit.kind=='pile' then return end
    if self.model.page=='builder' then return end
    local card=self.model:cardData(hit.card);if not card then return end
    local mx,my=Layout.mouse();local pw=244;local ph=342
    local x=mx> w/2 and math.max(15,mx-pw-20) or math.min(w-pw-20,mx+25);local y=math.max(85,math.min(h-ph-12,my-ph/2))
    self:drawCard(card,x,y,pw,ph,{noHit=true})
end
function Renderer:drawToasts(w,h)
    for i,t in ipairs(self.model.toasts) do
        local width=math.min(650,w-40);local y=h-52-(#self.model.toasts-i)*48
        rect((w-width)/2,y,width,40,{.10,.15,.20,.98},7);rect((w-width)/2,y,4,40,t.bad and C.red or C.accent,2)
        self:text(t.message,(w-width)/2+16,y+12,12,t.bad and {1,.65,.65} or C.text,width-30)
    end
end
function Renderer:draw()
    self.hits={};local w,h=Layout.dimensions();rect(0,0,w,h,C.bg,0)
    if self.model.page~='table' then self:drawNav(w) end
    if self.model.page=='decks' then self:drawDecks(w,h)
    elseif self.model.page=='builder' then self:drawBuilder(w,h)
    elseif self.model.page=='table' then self:drawTable(w,h)
    elseif self.model.page=='replays' then
        self:text('Your saved matches',28,101,28,C.text)
        self:text('Open a recording to play, pause or step through the engine’s saved frames.',29,142,16,C.muted)
    elseif self.model.page=='lobby' then
        self:text('A seat at the table.',32,102,28,C.text)
        self:text('Choose your deck and the XMage bot’s deck. The engine handles the match.',33,146,13,C.muted)
        local cx=w*.73;local cy=h*.48;color(C.accent,.15)
        love.graphics.circle('line',cx,cy,157);love.graphics.circle('line',cx,cy,135);love.graphics.polygon('line',cx,cy-110,cx+95,cy+55,cx-95,cy+55)
        self:text('1  vs  1',cx-120,cy-27,36,C.text,240,'center');self:text('HUMAN  ×  XMAGE AI',cx-130,cy+32,12,C.accent,260,'center')
    end
    self:drawPreview(w,h)
end
function Renderer:mousemoved(x,y)
    self.hover=nil
    for i=#self.hits,1,-1 do if inside(self.hits[i],x,y) then self.hover=self.hits[i];break end end
end
function Renderer:mousepressed(x,y,button,clicks)
    self:mousemoved(x,y)
    local hit=self.hover;if not hit or self.model.settingsOpen then return end
    if button==2 and hit.card then self.model.previewCard=hit.card;self.model.inspectCard=hit.card;return end
    if button~=1 then return end
    if hit.action then
        self:sound('click');hit.action()
        if clicks==2 and hit.deck then self.model:openDeck(hit.deck) end
    elseif self.model.replay and hit.card then self.model.inspectCard=hit.card
    elseif hit.kind=='search' or hit.kind=='hand' or hit.kind=='permanent' or hit.kind=='command' or hit.kind=='order' then
        if hit.kind=='search' and clicks==2 then self.model:addCard(hit.card);return end
        self.drag=hit;self.dragStart={x,y};self.dragPos={x=x,y=y}
    elseif hit.kind=='player' then self.model:selectCard(hit.card)
    elseif hit.kind=='zone' then self.model.zoneView={label=hit.label,cards=hit.cards} end
end
function Renderer:mousereleased(x,y,button)
    if button~=1 or not self.drag then return end
    local d=self.drag;self.drag=nil
    local distance=math.abs(x-self.dragStart[1])+math.abs(y-self.dragStart[2]);local w,h=Layout.dimensions()
    local accepted=false
    if d.kind=='search' then
        local drop=self.builderDrop or require('app.builder').layout(w,h).list
        if distance>8 and drop and x>=drop.x and x<=drop.x+drop.w and y>=drop.y and y<=drop.y+drop.h then
            self.model:addCard(d.card);accepted=true
            self:burst('click',drop.x+drop.w/2,math.min(y,drop.y+80),9)
        else self.model.previewCard=d.card end
    elseif d.kind=='order' then
        local target
        for _,hit in ipairs(self.hits) do if hit.kind=='order' and inside(hit,x,y) then target=hit.index end end
        if target and target~=d.index then local choice=table.remove(self.model.promptOrder,d.index);table.insert(self.model.promptOrder,target,choice) end
    elseif d.card then
        local L=Layout.table(w,h)
        if distance<8 or (x<L.board.x+L.board.w and y>200 and y<h-135) then
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
end
function Renderer:wheelmoved(dx,dy)
    if self.model.settingsOpen or self.model.zoneView or self.model.inspectCard then return end
    local x,y=Layout.mouse();local w=select(1,Layout.dimensions());local p=self.model:prompt()
    if self.model.page=='decks' and x<w-350 and y>230 then self.deckScroll=math.max(0,math.min(self.deckScrollMax or 0,(self.deckScroll or 0)-dy*50))
    elseif self.model.page=='table' and p and p.type=='order' and x<w-348 then self.orderScroll=math.max(0,math.min(self.orderScrollMax or 0,(self.orderScroll or 0)-(dy+dx)*90)) end
end
return Renderer
