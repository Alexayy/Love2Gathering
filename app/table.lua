local Layout=require('app.layout')
local Table={}
local Board=require('app.board_fx')
local HUD=require('app.table_hud')
local Cards=require('app.card_presentation')
local TablePresentation=require('app.table_presentation')
local BattlefieldSurface=require('app.battlefield_surface')
local lanes={
    creatures={label='Creatures',aspect=1.24,minimum=94,align=.5},
    walkers={label='Planeswalkers',aspect=1.24,minimum=81,align=0},
    support={label='Support permanents',aspect=1.24,minimum=64,align=0},
    lands={label='Lands',aspect=1.6,minimum=57,align=1}
}
local laneGap=24
local function terrain(r,view,draw)
    local dx,dy=Board.worldOffset(r)
    r.worldTransform={x=dx,y=dy,scale=1,clip=view,shakeOnly=true}
    love.graphics.push();love.graphics.translate(dx,dy);Layout.clip(view.x,view.y,view.w,view.h)
    draw()
    love.graphics.pop();r.worldTransform=nil;Layout.clip()
end
function Table.players(game)
    local human,bot
    for _,p in ipairs(game.players or {}) do
        if TablePresentation.isLocalSeat(game,p) then human=p else bot=p end
    end
    return human,bot
end
function Table.battlefieldRows(r,player)
    local rows={}
    for role in pairs(lanes)do rows[role]={cards={},shown={}}end
    for _,card in ipairs(player.battlefield or {}) do
        local target=type(card.attachedToId)=='string'and card.attachedToId
        local attached=(type(card.attachedToPlayerId)=='string'and card.attachedToPlayerId)or(target and((r.boardCards or{})[target]or(r.boardPlayers or{})[target]))
        if not attached then
            local row=rows[Cards.battlefieldRole(card)]
            row.cards[#row.cards+1]=card
        end
    end
    local prompt=r.model:prompt()
    local separateOffered=prompt and not prompt.priority and not prompt.mulligan
    local function prepare(row)
        row.groups=TablePresentation.groups(row.cards,r.model.settings.groupEquivalent~=false,function(id)return r.model:canSelect(id)end,separateOffered)
        for _,group in ipairs(row.groups)do row.shown[#row.shown+1]=group.card end
    end
    for _,row in pairs(rows)do prepare(row)end
    return rows
end
local function laneWidth(rows,role)
    local lane=lanes[role]
    return Layout.battlefieldRowWidth(rows[role].shown,lane.minimum,lane.aspect)
end
local function pairedWidth(left,right)
    return left+right+(left>0 and right>0 and laneGap or 0)
end
function Table.multiplayerFieldWidth(rows)
    return math.max(pairedWidth(laneWidth(rows,'walkers'),laneWidth(rows,'creatures')),
        pairedWidth(laneWidth(rows,'support'),laneWidth(rows,'lands')))
end
function Table.field(r,player,x,y,w,rowH,foe,rows)
    rows=rows or Table.battlefieldRows(r,player)
    local inWorld=r.worldTransform~=nil and not r.worldTransform.shakeOnly
    local scale=math.max(.8,math.min(1.3,tonumber(r.model.settings.cardScale) or 1))
    local frontFilled=#rows.creatures.shown+#rows.walkers.shown>0
    local backFilled=#rows.support.shown+#rows.lands.shown>0
    local gap=math.min(16,math.max(8,rowH*.07))
    local backLimit=#rows.support.shown>0 and 97 or 85
    local backDepth=math.min(backLimit*scale,frontFilled and (rowH-gap)*.39 or rowH)
    local frontDepth=math.min(138*scale,backFilled and rowH-backDepth-gap or rowH)
    local freeze=TablePresentation.freeze(r)
    local function drawRow(role,laneX,width,depth,centerY)
        local row,lane=rows[role],lanes[role]
        if #row.shown==0 then return end
        local height=depth
        for _,card in ipairs(row.shown)do
            if card.tapped then
                local _,extent=Layout.rotatedSize(lane.aspect,1,Layout.battlefieldAngle(card))
                height=depth/extent;break
            end
        end
        local minimum=inWorld and lane.minimum or (role=='lands' and 38 or 46)
        local boxes=Layout.battlefieldRow(row.shown,laneX,centerY,width,height,minimum,lane.aspect,lane.align)
        r.fieldRows=r.fieldRows or{}
        local key=tostring((r.model.game or{}).gameId)..':'..tostring(player.id)..':'..role
        local old=r.fieldRows[key]or{}
        local nextRows={x=laneX,y=centerY,w=width,h=height,count=#boxes}
        local keep=freeze and old.x==laneX and old.y==centerY and old.w==width and old.h==height and old.count==#boxes
        if keep then
            for _,card in ipairs(row.shown)do
                if not old[card.id] or old[card.id].angle~=Layout.battlefieldAngle(card) then keep=false;break end
            end
        end
        for i,group in ipairs(row.groups)do
            local card=group.card;local box=keep and old[card.id]or boxes[i]
            box.angle=Layout.battlefieldAngle(card);nextRows[card.id]=box
            r:drawPermanent(card,box.x,box.y,box.w,box.h,{kind='permanent',angle=box.angle,animate=true,
                groupCount=#group.cards>1 and #group.cards or nil})
            local hit=r.hits[#r.hits]
            if hit and hit.card==card then hit.battlefieldRole=role end
            if #group.cards>1 then
                local anchor=r.cardRects[card.id]
                if anchor then
                    for _,member in ipairs(group.cards)do r.cardRects[member.id]=anchor end
                    if hit and hit.card==card then
                        hit.kind='group';hit.tooltip=tostring(#group.cards)..' equivalent objects · choose an individual card'
                        hit.action=function()
                            r.model:openZone(player.id,'battlefield','Equivalent '..(role=='lands'and'basic lands'or'tokens'),group.cards)
                        end
                    end
                end
            end
        end
        r.fieldRows[key]=nextRows
        if #boxes>1 and Layout.battlefieldRowWidth(row.shown,boxes[1].h,lane.aspect)>width+1 then
            r.assets:iconSymbol('search',laneX-20,centerY-8,16,r.colors.muted)
        end
        r:hit({x=laneX-22,y=centerY-15,w=22,h=30,kind='zone',playerId=player.id,zone='battlefield',battlefieldRole=role,
            members=row.cards,cards=row.cards,label=(player.name or 'Player')..' · '..lane.label,tooltip='Inspect all '..lane.label:lower()})
    end
    local function drawRank(left,right,depth,centerY)
        if #rows[left].shown==0 then drawRow(right,x,w,depth,centerY);return end
        if #rows[right].shown==0 then drawRow(left,x,w,depth,centerY);return end
        local clear=math.min(laneGap,w*.1)
        local usable=w-clear
        local leftW
        if left=='walkers' then
            -- A lone walker starts with one eighth of the combat rank.
            -- Additional walkers grow the strip while creatures retain space.
            local extra=(#rows.walkers.shown-1)*(lanes.walkers.minimum*lanes.walkers.aspect+10)
            leftW=math.min(usable*.78,math.max(68,usable/8)+extra)
        else
            local leftNeed,rightNeed=laneWidth(rows,left),laneWidth(rows,right)
            leftW=usable*math.max(.16,math.min(.84,leftNeed/(leftNeed+rightNeed)))
        end
        drawRow(left,x,leftW,depth,centerY)
        drawRow(right,x+leftW+clear,usable-leftW,depth,centerY)
    end
    local front=foe and y+rowH or y
    local direction=foe and -1 or 1
    local back=foe and y or y+rowH
    drawRank('support','lands',backDepth,back-direction*backDepth/2)
    drawRank('walkers','creatures',frontDepth,front+direction*frontDepth/2)
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
    if n==0 then
        r.handBounds=nil;r.handHoverIndex=nil;r.handExpansion=0;r.handScroll=0;r.handScrollMax=0
        return
    end
    local mx,my=Layout.mouse();local left,right=safe.handLeft,math.max(safe.handLeft+240,safe.handRight)
    local width=right-left;local ch=safe.handH;local cw=ch/1.4
    local visible=math.max(3,math.floor(width/(cw*.54)))
    r.handScrollMax=math.max(0,n-visible)
    r.handScroll=math.max(0,math.min(r.handScrollMax,r.handScroll or 0))
    -- Touchpads deliver fractional wheel deltas. Keep the remainder for the
    -- next event, but index the native hand only with whole card positions.
    local offset=math.floor(r.handScroll)
    local last=math.min(n,offset+visible);local count=last-offset
    local spacing=math.min(cw*.82,(width-cw-24)/math.max(1,count-1));local start=left+(width-cw-(count-1)*spacing)/2
    local y=safe.handY
    local bounds={x=start-12,y=y,w=cw+(count-1)*spacing+24,h=safe.handBottom-y}
    local hot=mx>=bounds.x and mx<=bounds.x+bounds.w and my>=bounds.y and my<=bounds.y+bounds.h
    local raisedH=math.min(272,math.max(216,h*.245))*safe.cardScale
    local raisedW=raisedH/1.4
    local raisedY=safe.handBottom-raisedH-22
    local function raisedX(index)
        return math.max(left,math.min(right-raisedW,start+(index-offset-1)*spacing+(cw-raisedW)/2))
    end
    local function resting(index)
        local normal=count<=1 and 0 or 2*(index-offset-1)/(count-1)-1
        local spread=math.min(1,(count-1)/5)
        return start+(index-offset-1)*spacing,y+ch*.15*spread*normal*normal,normal*.235*spread
    end
    local prompt=r.model:prompt()
    local hoverIndex
    if not r.drag and not r:inputBlocked() and not(prompt and prompt.type=='play_mana') then
        if hot then
            for index=last,offset+1,-1 do
                local x,cy,angle=resting(index)
                local dx,dy=mx-x-cw/2,my-cy-ch/2
                local cos,sin=math.cos(angle),math.sin(angle)
                if math.abs(dx*cos+dy*sin)<=cw/2 and math.abs(dy*cos-dx*sin)<=ch/2 then
                    hoverIndex=index;break
                end
            end
        end
        local old=r.handHoverIndex
        if old and old>=offset+1 and old<=last then
            local center=start+(old-offset-1)*spacing+cw/2
            local x=raisedX(old)
            if hot and math.abs(mx-center)<spacing*.58
                or my>=raisedY and my<bounds.y and mx>=x and mx<=x+raisedW then hoverIndex=old end
        end
    end
    r.handHoverIndex=hoverIndex;r.handExpansion=hoverIndex and 1 or 0;r.handBounds=bounds
    local function draw(index,focused)
        local x,cy,angle=resting(index)
        local dw,dh=cw,ch
        if focused then
            dw,dh=raisedW,raisedH;x,cy,angle=raisedX(index),raisedY,0
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
    if r.fieldRowIdentity~=identity then
        r.fieldRows={};r.fieldRowIdentity=identity;r.handScroll=0;r.handHoverIndex=nil
        r.tableCamera=nil;r.cameraIdentity=nil;r.multiplayerSeats=nil;r.panGesture=nil
    end
    local extension=package.loaded['app.card_actions'] and require('app.card_actions').extension(m) or {}
    local L=Layout.table(w,h,m,extension);r.tableLayout=L;local V=L.viewport;local C=r.colors
    HUD.draw(r,L,w,h)
    local human,enemy=Table.players(game)
    if #(game.players or{})>2 then require('app.multiplayer_table').draw(r,L,w,h,Table)
    elseif human and enemy then
        local compact=h<850;local summary=compact and 118 or 148
        local areaX,areaW=L.fieldX,L.fieldW
        local center=L.divider
        local half=V.h/2
        terrain(r,V,function()
            BattlefieldSurface.draw(m.settings,V.x,V.y,V.w,V.h)
            r:drawPlaymat(enemy,V.x,V.y,V.w,center-V.y-3)
            r:drawPlaymat(human,V.x,center+3,V.w,V.y+V.h-center-3)
            Table.field(r,enemy,areaX,L.enemyY,areaW,L.rowH,true)
            Table.field(r,human,areaX,L.humanY,areaW,L.rowH,false)
            love.graphics.setColor(C.line);love.graphics.line(V.x+8,center,V.x+V.w-8,center)
        end)
        for i,p in ipairs({enemy,human})do
            local y=V.y+(i-1)*half+8;local tight=half<165
            local near=p==human
            local besideTransport=near and m.replay~=nil
            local cx=besideTransport and 50 or V.x+V.w/2
            local cy=near and h-30 or V.y-13
            HUD.duelSeat(r,p,cx,cy,near and 'near' or 'far',besideTransport)
            if besideTransport then
                r:priorityBadge(p,V.x+8,y+math.min(123,half-32),summary-16,20)
            else
                r:priorityBadge(p,cx+35,cy-9,111,19)
            end
            Board.playerAuras(r,p,V.x+52,y,tight and 28 or 38,summary-60)
            -- The library remains an actual target even when an exile hand
            -- shortens the battlefield. Entitled top cards retain their UUID.
            Table.library(r,p,V.x+summary-50,y+(tight and 43 or 65),tight and 32 or 36,true)
            local zx=V.x+V.w-98
            local zh=math.min(38,(half-22)/3)
            HUD.zone(r,p,'graveyard',zx,y+2,90,true,zh)
            HUD.zone(r,p,'exile',zx,y+6+zh,90,true,zh)
            HUD.zone(r,p,'command',zx,y+10+zh*2,90,true,zh)
            if #(p.commanders or{})>0 then r:commanderSummary(p,areaX,y+2,areaW,12)end
            local manaX=areaX
            for _,symbol in ipairs({'W','U','B','R','G','C'})do
                local amount=(p.mana or{})[symbol]or 0
                if amount>0 then r.assets:mana(symbol,manaX,y+half-27,15);r:text(amount,manaX+18,y+half-27,13,C.text);manaX=manaX+43 end
            end
        end
        Table.hand(r,human,L,w,h)
    end
    if #extension>0 then Table.exileHand(r,human,L,w,h)end
    local prompt=m:prompt()
    if prompt and prompt.type=='order'then r:drawOrdering(w,h,prompt)end
    if prompt and prompt.manaWheel then Table.manaWheel(r,w,h,prompt)end
    if type(game.error)=='string'then r:text(game.error,V.x+12,V.y+12,16,C.red,V.w-24)end
    if m.replay then r:text('REPLAY · VIEW ONLY',30,116,14,C.gold)end
end
function Table.exileHand(r,player,L,w,h)
    local cards=L.exileCards
    local safe=L.safe;local ch=L.exileCardH;local cw=ch/1.4;local width=math.min(safe.handRight-safe.handLeft,math.max(210,#cards*(cw+9)+84))
    local x=safe.handLeft;local y=safe.handY-(ch+14)
    r:panel(x,y,width,ch+10,{.075,.045,.13,.96});r:text('EXILE',x+8,y+8,12,r.colors.purple)
    local shown=math.min(#cards,math.max(1,math.floor((width-76)/(cw+9))))
    for i=1,shown do r:drawCard(cards[i],x+69+(i-1)*(cw+9),y+4,cw,ch,{kind='exile-hand',animate=true})end
    if #cards>shown then r:button('+'..(#cards-shown),x+width-40,y+43,36,28,function()r.model.zoneView={label='Playable exile',cards=cards,gameId=r.model.game.gameId,playableExile=true}end)end
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
