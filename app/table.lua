local Layout=require('app.layout')
local Table={}
local Board=require('app.board_fx')
local Presentation=require('app.card_presentation')
local handScale,fieldScale=1.05,1.21
local function terrain(r,view,draw)
    local dx,dy=Board.worldOffset(r)
    r.worldTransform={x=dx,y=dy,scale=1,clip=view,shakeOnly=true}
    love.graphics.push();love.graphics.translate(dx,dy);Layout.clip(view.x,view.y,view.w,view.h)
    draw()
    love.graphics.pop();r.worldTransform=nil;Layout.clip()
end
local function land(c) return tostring(c.type_line or c.type or ''):lower():find('land',1,true)~=nil end
local phases=require('app.priority').groups
local function activePhase(game,key)
    return Presentation.phaseKey(game)==key
end
function Table.players(game)
    local human,bot
    for _,p in ipairs(game.players or {}) do if p.human then human=p else bot=p end end
    return human,bot
end
function Table.field(r,player,x,y,w,rowH,foe)
    local C=r.colors;local lands,permanents={},{}
    for _,card in ipairs(player.battlefield or {}) do
        local target=type(card.attachedToId)=='string'and card.attachedToId
        local attached=(type(card.attachedToPlayerId)=='string'and card.attachedToPlayerId)or(target and((r.boardCards or{})[target]or(r.boardPlayers or{})[target]))
        if not attached then local group=land(card) and lands or permanents;group[#group+1]=card end
    end
    local _,height=Layout.dimensions();local available=math.max(58,rowH-14)
    local inWorld=r.worldTransform~=nil and not r.worldTransform.shakeOnly
    -- Duel rows share a bounded height. A smaller land target leaves the same
    -- visible growth for creatures near the transition to full-size rows.
    local landScale=inWorld and fieldScale or 1.177
    local landTarget=(inWorld and 154 or 128)*landScale
    local permanentTarget=(inWorld and 196 or 157)*fieldScale
    local landH=math.min(landTarget,math.max(66,(inWorld and 154 or height*.12)*landScale),available)
    local permanentH=math.min(permanentTarget,available)
    if #lands>0 and #permanents>0 then
        landH=math.min(landH,math.max(64,available*.38))
        permanentH=math.min(permanentTarget,available-landH-12)
    end
    local function drawRow(cards,cardH,rowY,mana)
        if #cards==0 then return end
        local P=require('app.table_presentation')
        local groups=P.groups(cards,r.model.settings.groupEquivalent~=false,function(id)return r.model:canSelect(id)end)
        local shown={};for _,group in ipairs(groups)do shown[#shown+1]=group.card end
        if #shown<=7 then
            local factor=0;for _,card in ipairs(shown)do factor=factor+(card.tapped and 1 or 1/1.4)end
            cardH=math.min(cardH,math.max(42,(w-20-(#shown-1)*13)/math.max(.1,factor)))
        end
        local cardW=cardH/1.4
        local rows=Layout.cardRow(#shown,x,rowY,w,cardW,cardH,mana,shown)
        r.fieldRows=r.fieldRows or{};local key=tostring((r.model.game or{}).gameId)..':'..tostring(player.id)..':'..tostring(mana)
        local old=r.fieldRows[key]or{};local freeze=P.freeze(r);local nextRows={}
        for i,group in ipairs(groups)do
            local card=group.card;local box=freeze and old[card.id]or rows[i];nextRows[card.id]=box
            r:drawPermanent(card,box.x,box.y,box.w,box.h,{kind='permanent',animate=true})
            if #group.cards>1 then
                local anchor=r.cardRects[card.id]
                if anchor then
                    for _,member in ipairs(group.cards)do r.cardRects[member.id]=anchor end
                    r:panel(box.x+box.w-22,box.y-8,37,25,'dark');r:strong('×'..#group.cards,box.x+box.w-21,box.y-5,14,r.colors.gold,35,'center')
                    local hit=r.hits[#r.hits]
                    if hit and hit.card==card then
                        hit.kind='group';hit.tooltip=tostring(#group.cards)..' equivalent objects · choose an individual card'
                        hit.action=function()r.model.zoneView={cards=group.cards,label='Equivalent '..(mana and'basic lands'or'tokens'),groupIds=true,gameId=r.model.game.gameId}end
                    end
                end
            end
        end
        r.fieldRows[key]=nextRows
        r:hit({x=x-22,y=rowY+cardH/2-15,w=22,h=30,kind='zone',cards=cards,label=(player.name or'Player')..(mana and' · Mana sources'or' · Battlefield'),tooltip='Inspect every native permanent in this row'})
    end
    if foe then
        drawRow(lands,landH,y,true)
        drawRow(permanents,permanentH,y+available-permanentH,false)
    else
        drawRow(permanents,permanentH,y,false)
        drawRow(lands,landH,y+available-landH,true)
    end
end
function Table.pile(r,label,count,cards,x,y,cw,back)
    local card=cards and cards[#cards];local ch=cw*1.4
    r:drawCard(card or {name=label},x,y,cw,ch,{back=back or not card,kind='pile'})
    r.assets:iconSymbol(label:lower(),x+cw/2-11,y+ch+6,22,r.colors.muted)
    r:panel(x+cw-21,y-9,31,27,'dark');r:text(count or #(cards or {}),x+cw-21,y-7,16,r.colors.text,31,'center')
    r:hit({x=x-8,y=y-9,w=cw+18,h=ch+38,kind='zone',cards=cards or {},label=label,tooltip=label})
end
function Table.library(r,player,x,y,cw,compact)
    local m,C=r.model,r.colors;local top=m:libraryTop(player);local ch=cw*1.4
    if r.zoneAnchor then r:zoneAnchor(player.id,'library',{x=x,y=y,w=cw,h=ch})end
    local before=#r.hits
    r:drawCard(top or{name='Library'},x,y,cw,ch,{back=not top,noHit=not top,kind='library-top'})
    if top and #r.hits>before and r.hits[#r.hits].card==top and r.hits[#r.hits].kind=='library-top'then
        local hit=r.hits[#r.hits]
        hit.libraryPlayerId=player.id;hit.libraryGameId=m.game.gameId
        local visibility=player.libraryTopVisibility=='public'and'Revealed top card'or'Known top card'
        hit.tooltip=visibility..' · '..(top.name or'Card')..(m:canSelect(top.id)and' · click or drag to choose this card'or' · click to inspect')
    end
    if compact then
        r:panel(x+cw-23,y+ch-19,25,20,'dark');r:text(player.libraryCount or 0,x+cw-23,y+ch-18,12,C.text,25,'center')
    else r:panel(x+cw-21,y-9,31,27,'dark');r:text(player.libraryCount or 0,x+cw-21,y-7,16,C.text,31,'center')end
    local labelY=y+ch+4
    if not compact then r.assets:iconSymbol('library',x+cw/2-11,labelY+2,22,top and C.gold or C.muted)end
    -- Leave the card itself actionable; the count and zone icon open inspection.
    local function open()m:openLibrary(player.id)end
    if not compact then r:hit({x=x-7,y=labelY,w=cw+14,h=30,kind='library-zone',libraryPlayerId=player.id,action=open,tooltip=(player.name or'Player')..' · Library · inspect the entitled top card'})end
    r:hit({x=x+cw-23,y=compact and y+ch-19 or y-11,w=compact and 25 or 35,h=compact and 20 or 31,kind='library-zone',libraryPlayerId=player.id,action=open,tooltip='Library · '..tostring(player.libraryCount or 0)..' cards'})
    if not top then r:hit({x=x,y=y,w=cw,h=ch,kind='library-zone',libraryPlayerId=player.id,action=open,tooltip='Library · top card is not visible'})end
end
function Table.hand(r,player,layout,w,h)
    local cards=player.hand or{};local n=#cards;local safe=layout.safe
    if r.zoneAnchor then r:zoneAnchor(player.id,'hand',{x=safe.handLeft,y=safe.handY,w=math.max(100,safe.handRight-safe.handLeft),h=safe.handH})end
    if n==0 then r.handBounds=nil;return end
    local mx,my=Layout.mouse();local left,right=safe.handLeft,math.max(safe.handLeft+240,safe.handRight)
    local width=right-left;local cw=math.min(138,math.max(95,safe.handH/1.4));local ch=cw*1.4
    local visible=math.max(3,math.floor(width/(cw*.54)));local offset=math.max(0,math.min(math.max(0,n-visible),r.handScroll or 0))
    r.handScroll=offset;r.handScrollMax=math.max(0,n-visible)
    local last=math.min(n,offset+visible);local count=last-offset
    local spacing=math.min(cw*.76,(width-cw)/math.max(1,count-1));local start=left+(width-cw-(count-1)*spacing)/2
    local y=safe.handBottom-ch-8;local bounds={x=left-8,y=y-16,w=width+16,h=ch+30}
    local hot=mx>=bounds.x and mx<=bounds.x+bounds.w and my>=bounds.y and my<=safe.handBottom+12
    local hoverIndex
    if hot and not r:inputBlocked()and not r.drag then
        hoverIndex=math.max(offset+1,math.min(last,offset+math.floor((mx-start)/math.max(1,spacing))+1))
        local old=r.handHoverIndex
        if old and old>=offset+1 and old<=last then
            local center=start+(old-offset-1)*spacing+cw/2
            if math.abs(mx-center)<spacing*.58 then hoverIndex=old end
        end
    end
    r.handHoverIndex=hoverIndex;r.handExpansion=hot and 1 or 0;r.handBounds=bounds
    local function draw(index,focused)
        local normal=count<=1 and 0 or(index-offset-1)/(count-1)-.5
        local angle=focused and 0 or normal*.16
        local x=start+(index-offset-1)*spacing;local cy=y+math.abs(normal)*5
        local dw,dh=cw,ch
        if focused then
            dh=math.min(272,math.max(216,h*.245))*safe.cardScale;dw=dh/1.4
            x=math.max(left,math.min(right-dw,x+(cw-dw)/2));cy=safe.handBottom-dh-22
        elseif hoverIndex then
            x=x+(index<hoverIndex and-8 or index>hoverIndex and 8 or 0)
        end
        r:drawCard(cards[index],x,cy,dw,dh,{angle=angle,kind='hand',index=index,animate=true,hovered=focused})
    end
    for i=offset+1,last do if i~=hoverIndex then draw(i,false)end end
    if hoverIndex then draw(hoverIndex,true)end
    if n>visible then
        r:button('‹',left-30,safe.handBottom-64,30,42,function()r.handScroll=math.max(0,offset-3)end,false,{size=20,tooltip='Earlier cards · scroll the hand'})
        r:button('›',right+2,safe.handBottom-64,30,42,function()r.handScroll=math.min(r.handScrollMax,offset+3)end,false,{size=20,tooltip='Later cards · scroll the hand'})
        r:text(tostring(offset+1)..'–'..last..' / '..n,left,safe.handBottom+3,12,r.colors.muted,width,'center')
    end
end
function Table.draw(r,w,h)
    local m=r.model;local game=m.game;if not game then return end
    local identity=m.replay or game.gameId or game
    if r.fieldRowIdentity~=identity then r.fieldRows={};r.fieldRowIdentity=identity end
    local L=Layout.table(w,h,m);r.tableLayout=L;local V=L.viewport;local C=r.colors
    require('app.table_hud').draw(r,L,w,h)
    local human,enemy=Table.players(game)
    if #(game.players or{})>2 then require('app.multiplayer_table').draw(r,L,w,h,Table)
    elseif human and enemy then
        local compact=h<850;local summary=compact and 118 or 148
        local areaX=V.x+summary;local areaW=V.w-summary-110
        local top=V.y+28;local half=V.h/2
        terrain(r,V,function()
            r:drawPlaymat(enemy,V.x,V.y,V.w,half-3)
            r:drawPlaymat(human,V.x,V.y+half+3,V.w,half-3)
            Table.field(r,enemy,areaX,top,areaW,half-46,true)
            Table.field(r,human,areaX,top+half,areaW,half-46,false)
            love.graphics.setColor(C.line);love.graphics.line(V.x+8,V.y+half,V.x+V.w-8,V.y+half)
        end)
        for i,p in ipairs({enemy,human})do
            local y=V.y+(i-1)*half+8;local tight=half<165
            r:drawAvatar(p,V.x+10,y,tight and 28 or 36)
            r:strong(r:fit(p.name or'Player',summary-18,16,1),V.x+9,y+(tight and 31 or 43),16,r:playerColor(p),summary-18)
            r:strong(p.life,V.x+11,y+(tight and 51 or 65),tight and 32 or 36,r:playerColor(p))
            r.playerRects[p.id]={x=V.x+8,y=y,w=summary-14,h=106}
            r:priorityBadge(p,V.x+8,y+math.min(123,half-32),summary-16,20)
            r:hit({x=V.x+8,y=y,w=summary-14,h=106,kind='player',card={id=p.id,name=p.name},tooltip=Presentation.playerTooltip(p,game.commanderDamageEnabled),commanderDetails=true})
            -- The library remains an actual target even when an exile hand
            -- shortens the battlefield. Entitled top cards retain their UUID.
            Table.library(r,p,V.x+summary-50,y+(tight and 43 or 65),tight and 32 or 36,true)
            local zx=V.x+V.w-98
            local zh=math.min(38,(half-22)/3)
            require('app.table_hud').zone(r,p,'graveyard',zx,y+2,90,true,zh)
            require('app.table_hud').zone(r,p,'exile',zx,y+6+zh,90,true,zh)
            require('app.table_hud').zone(r,p,'command',zx,y+10+zh*2,90,true,zh)
            if #(p.commanders or{})>0 then r:commanderSummary(p,areaX,y+2,areaW,12)end
            local manaX=areaX
            for _,symbol in ipairs({'W','U','B','R','G','C'})do
                local amount=(p.mana or{})[symbol]or 0
                if amount>0 then r.assets:mana(symbol,manaX,y+half-27,15);r:text(amount,manaX+18,y+half-27,13,C.text);manaX=manaX+43 end
            end
        end
        Table.hand(r,human,L,w,h)
    end
    if human and package.loaded['app.card_actions']then Table.exileHand(r,human,L,w,h)end
    local prompt=m:prompt()
    if prompt and prompt.type=='order'then r:drawOrdering(w,h,prompt)end
    if prompt and prompt.manaWheel then Table.manaWheel(r,w,h,prompt)end
    if type(game.error)=='string'then r:text(game.error,V.x+12,V.y+12,16,C.red,V.w-24)end
    if m.replay then r:text('REPLAY · VIEW ONLY',30,116,14,C.gold)end
end
function Table.exileHand(r,player,L,w,h)
    local Actions=require('app.card_actions');if not Actions.extension then return end
    local cards=Actions.extension(r.model);if not cards or#cards==0 then return end
    local safe=L.safe;local ch=h<850 and 76 or 96;local cw=ch/1.4;local width=math.min(safe.handRight-safe.handLeft,math.max(210,#cards*(cw+9)+84))
    local x=safe.handLeft;local y=safe.handY-(ch+14)
    r:panel(x,y,width,ch+10,{.075,.045,.13,.96});r:text('EXILE',x+8,y+8,12,r.colors.purple)
    local shown=math.min(#cards,math.max(1,math.floor((width-76)/(cw+9))))
    for i=1,shown do r:drawCard(cards[i],x+69+(i-1)*(cw+9),y+4,cw,ch,{kind='exile-hand',animate=true})end
    if #cards>shown then r:button('+'..(#cards-shown),x+width-40,y+43,36,28,function()r.model.zoneView={label='Playable exile',cards=cards,gameId=r.model.game.gameId,groupIds=true}end)end
end
function Table.manaWheel(r,w,h,prompt)
    local C=r.colors;local L=r.tableLayout or Layout.table(w,h);local source=prompt.manaWheel.sourceId
    local anchor=r.cardRects[source] or r.lastSelected or {x=L.board.w/2,y=L.humanY,w=70,h=90}
    local x=math.max(173,math.min(L.board.w-173,anchor.x+anchor.w/2));local y=math.max(285,math.min(h-235,anchor.y-82))
    r:panel(x-160,y-139,320,282,'dark')
    r:text('CHOOSE MANA',x-145,y-124,16,C.accent,290,'center')
    local choices=prompt.choices or {};local n=#choices;local radius=n>1 and 76 or 0
    for i,choice in ipairs(choices) do
        local angle=-math.pi/2+(i-1)*2*math.pi/math.max(1,n)
        local cx,cy=x+math.cos(angle)*radius,y+math.sin(angle)*radius+5
        love.graphics.setColor(.12,.21,.26,1);love.graphics.circle('fill',cx,cy,30)
        love.graphics.setColor(C.accent);love.graphics.circle('line',cx,cy,30)
        local symbols=choice.manaColors or {};local symbol=symbols[1] or 'T'
        r.assets:mana(symbol,cx-15,cy-15,30)
        r:hit({x=cx-31,y=cy-31,w=62,h=62,kind='mana',choice=choice,action=function() r.model:answerChoice(choice) end})
        if r.hover and r.hover.choice==choice then r:text(r:fit(choice.label,290,13,2),x-145,y+106,13,C.text,290,'center') end
    end
end
return Table
