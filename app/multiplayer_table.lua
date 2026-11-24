local Layout=require('app.layout')
local Camera=require('app.table_camera')
local Presentation=require('app.card_presentation')
local TablePresentation=require('app.table_presentation')
local BattlefieldSurface=require('app.battlefield_surface')
local HUD=require('app.table_hud')
local fieldPadding=28
local Multi={}
local function within(v,x,y) return v and x>=v.x and y>=v.y and x<=v.x+v.w and y<=v.y+v.h end
Multi.within=within
local function iconButton(r,icon,label,x,y,w,action,active)
    r:panel(x,y,w,28,active and 'accent' or 'dark')
    if label then r:iconLabel(icon,label,x+7,y,w-14,28,12,active and r.colors.accent or r.colors.text,18)
    else r.assets:iconSymbol(icon,x+(w-18)/2,y+5,18,active and r.colors.accent or r.colors.muted)end
    r:hit({x=x,y=y,w=w,h=28,action=action,tooltip=label})
end
local function ordered(game)
    local human,bots=nil,{}
    for _,p in ipairs(game.players or {}) do
        if TablePresentation.isLocalSeat(game,p) then human=p else bots[#bots+1]=p end
    end
    if not human then return bots,nil end
    -- The local seat occupies the lower left of the overview.
    local seats={bots[1],bots[2],human,bots[3]}
    for i=4,#bots do seats[#seats+1]=bots[i] end
    return seats,human
end
local function zone(r,player,name,icon,x,y,w)
    local cards=player[name] or {};local actionable=false
    for _,card in ipairs(cards) do if r.model:canSelect(card.id) then actionable=true;break end end
    r:panel(x,y,w,48,actionable and 'accent' or 'dark')
    r.assets:iconSymbol(icon,x+9,y+9,29,actionable and r.colors.accent or r.colors.muted)
    r:strong(#cards,x+43,y+10,22,r.colors.text,w-48,'center')
    r:hit({x=x,y=y,w=w,h=48,kind='zone',cards=cards,label=player.name..' · '..icon,tooltip=player.name..' · '..icon..' · '..#cards..' cards'})
end
local function seat(r,player,index,c,Table,rows,localSeat)
    local C=r.colors;local m=r.model;local selected=m:canSelect(player.id)
    local active=m.game.activePlayerId==player.id;local tint=r:playerColor(player)
    r:panel(c.x,c.y,c.w,c.h,selected and'accent'or'dark')
    BattlefieldSurface.draw(m.settings,c.x+4,c.y+4,c.w-8,c.h-8)
    r:drawPlaymat(player,c.x+4,c.y+4,c.w-8,c.h-8)
    love.graphics.push('all');love.graphics.setColor(tint[1],tint[2],tint[3],active and .85 or .25)
    love.graphics.setLineWidth(active and 2 or 1);love.graphics.rectangle('line',c.x+2,c.y+2,c.w-4,c.h-4,6,6);love.graphics.pop()
    local lifeX=c.x+c.w-137
    local handW=208
    local handX=lifeX-handW-8
    local nameWidth=localSeat and c.w-290 or handX-c.x-60
    r:drawAvatar(player,c.x+12,c.y+12,32)
    r:strong(r:fit(player.name or'Player',nameWidth,18,1),c.x+52,c.y+12,18,tint,nameWidth)
    r.assets:iconSymbol('life',c.x+c.w-102,c.y+19,22,tint);r:strong(player.life,c.x+c.w-73,c.y+10,32,tint,64,'center')
    local nameHitWidth=localSeat and c.w-20 or handX-c.x-18
    local playerBox=r:screenRect({x=c.x+10,y=c.y+8,w=nameHitWidth,h=42})
    if within(r.multiplayerView,playerBox.x+playerBox.w/2,playerBox.y+playerBox.h/2)then r.playerRects[player.id]=playerBox end
    local tooltip=Presentation.playerTooltip(player,m.game.commanderDamageEnabled)..(selected and' · legal target'or' · click to focus')
    local function playerTarget(x,width)
        r:hit({x=x,y=c.y+8,w=width,h=42,kind='player',card={id=player.id,name=player.name},focusIndex=index,
            tooltip=tooltip,commanderDetails=true})
    end
    playerTarget(c.x+10,nameHitWidth)
    r:priorityBadge(player,c.x+12,c.y+51,166,21)
    if localSeat then
        r.assets:iconSymbol('hand',c.x+c.w-168,c.y+17,18,tint)
        r:text(player.handCount or #(player.hand or{}),c.x+c.w-144,c.y+18,14,C.text)
    else
        HUD.opponentHand(r,player,handX,c.y+5,handW,43,true)
        playerTarget(lifeX,c.x+c.w-10-lifeX)
    end
    if active then r.assets:iconSymbol('turn',localSeat and c.x+c.w-199 or lifeX+4,c.y+17,18,C.gold)end
    local top=m:libraryTop(player)
    local libraryX=c.x+192
    if top then
        local before=#r.hits
        r:drawCard(top,libraryX,c.y+47,28,39,{kind='library-top',animate=true})
        if #r.hits>before then
            local hit=r.hits[#r.hits];hit.libraryPlayerId=player.id;hit.libraryGameId=m.game.gameId
        end
        r:zoneAnchor(player.id,'library',{x=libraryX,y=c.y+47,w=28,h=39})
        libraryX=libraryX+34
    else
        r:zoneAnchor(player.id,'library',{x=libraryX,y=c.y+51,w=106,h=34})
    end
    local before=#r.hits
    r:button('Library '..tostring(player.libraryCount or 0),libraryX,c.y+51,106,34,function()m:openLibrary(player.id)end,false,{size=12})
    if #r.hits>before then
        local hit=r.hits[#r.hits];hit.kind='library-zone';hit.libraryPlayerId=player.id
    end
    HUD.zone(r,player,'graveyard',c.x+c.w-300,c.y+49,90,true)
    HUD.zone(r,player,'exile',c.x+c.w-200,c.y+49,90,true)
    HUD.zone(r,player,'command',c.x+c.w-100,c.y+49,90,true)
    r:commanderSummary(player,c.x+12,c.y+88,c.w-24,12)
    Table.field(r,player,c.x+fieldPadding/2,c.y+119,c.w-fieldPadding,c.h-134,index<=2,rows)
    require('app.board_fx').playerAuras(r,player,c.x+177,c.y+72)
    local mx=c.x+14
    for _,symbol in ipairs({'W','U','B','R','G','C'})do
        local n=(player.mana or{})[symbol]or 0
        if n>0 then r.assets:mana(symbol,mx,c.y+c.h-17,14);r:text(n,mx+17,c.y+c.h-17,12,C.text);mx=mx+36 end
    end
    if Presentation.eliminated(player)then
        love.graphics.push('all');love.graphics.setColor(.005,.009,.015,.70);love.graphics.rectangle('fill',c.x+3,c.y+3,c.w-6,c.h-6,6,6)
        r:strong(player.left and'LEFT MATCH'or'ELIMINATED',c.x+30,c.y+c.h*.48,24,C.muted,c.w-60,'center');love.graphics.pop()
    end
end
function Multi.draw(r,L,w,h,Table)
    local m=r.model;local game=m.game;local seats,human=ordered(game)
    local identity=m.replay or game.gameId or game
    if r.cameraIdentity~=identity then r.tableCamera=Camera.new();r.cameraIdentity=identity;r.panGesture=nil;r.poses={};r.handExpansion=0;r.handBounds=nil end
    local camera=r.tableCamera
    local view=L.viewport
    local frozen=TablePresentation.freeze(r)
    local battlefields={};local width=0
    for i,player in ipairs(seats)do
        battlefields[i]=Table.battlefieldRows(r,player)
        width=math.max(width,Table.multiplayerFieldWidth(battlefields[i])+fieldPadding)
    end
    -- Frame every field above fixed screen-space cards. The play surface
    -- still extends underneath the hand while panning or magnifying a seat.
    local frame={x=view.x,y=view.y,w=view.w,h=view.h}
    if human and (#(human.hand or{})>0 or #L.exileCards>0) then
        frame.h=math.max(120,L.handTop-view.y-12);frame.fitSeatHeight=true
    end
    if L.paymentEdge then frame.w=math.max(120,math.min(frame.w,L.paymentEdge-frame.x))end
    camera:configure(frame,#seats,(not frozen or not camera.ready) and width or nil)
    camera:followTurn(game.activePlayerId,game.turn,seats,m.settings.autoFollowTurn,m.settings.reducedMotion or m.settings.animations==false,frozen)
    camera:update(r.dt,m.settings.reducedMotion or m.settings.animations==false)
    r.multiplayerView=view;r.multiplayerSeats=seats
    -- The navigation sits above the docks. Reserve the stop window and the
    -- reveal control before distributing the remaining space among seats.
    local visible=m:revealedCards()
    local stripX=m.replay and 180 or 22
    local gap,controlW=5,34
    local stripRight=m.replay and w-16 or Layout.beforeDamage(w).x-gap
    local revealW=#visible>0 and 54+gap or 0
    local playerW=math.min(194,(stripRight-stripX-revealW-controlW*4-gap*(#seats+3))/#seats)
    for i,p in ipairs(seats) do
        local x=stripX+(i-1)*(playerW+gap);local target=m:canSelect(p.id)
        local label=p.name
        if playerW<155 then label=p==human and 'You' or ((p.isHuman or p.bot==false) and p.name or ('Bot '..(p.seat or p.name:match('(%d+)$') or i))) end
        iconButton(r,(p==human or p.isHuman or p.bot==false) and 'player' or 'bot',r:fit(label,playerW-36,12,1),x,L.navY,playerW,function()
            if target then m:selectCard({id=p.id,name=p.name}) else camera:focus(i) end
        end,camera.focusIndex==i or target)
        local hit=r.hits[#r.hits];hit.kind='seat-focus';hit.playerId=p.id;hit.focusIndex=i
        r.playerRects[p.id]={x=x,y=L.navY,w=playerW,h=28}
        local count=tonumber(p.handCount) or (p==human and #(p.hand or {}) or '?')
        hit.tooltip=p.name..' · '..tostring(p.life)..' life\n'..tostring(count)..' in hand · '..tostring(p.libraryCount or 0)..' in library'..(target and' · legal target'or' · click to focus')
        love.graphics.setColor(game.activePlayerId==p.id and r.colors.gold or r.colors.line)
        love.graphics.rectangle('fill',x+8,L.navY+25,playerW-16,2)
        if game.priorityPlayerId==p.id and game.running~=false then
            local tint=r:playerColor(p);love.graphics.setColor(tint);love.graphics.setLineWidth(2)
            love.graphics.rectangle('line',x-1,L.navY-1,playerW+2,30,3,3)
            r.assets:iconSymbol('focus',x+playerW-16,L.navY+7,12,tint)
            hit.tooltip=hit.tooltip..' · holds priority'
        end
    end
    local x=stripX+#seats*(playerW+gap)
    local ownIndex=1;for i,p in ipairs(seats)do if p==human then ownIndex=i;break end end
    iconButton(r,'player',nil,x,L.navY,controlW,function()camera:focus(ownIndex)end,camera.focusIndex==ownIndex)
    r.hits[#r.hits].tooltip='My Battlefield';r.hits[#r.hits].kind='table-own';x=x+controlW+gap
    iconButton(r,'overview',nil,x,L.navY,controlW,function() camera:overview() end,camera.mode=='overview')
    r.hits[#r.hits].tooltip='Fit Table · all seats';r.hits[#r.hits].kind='table-overview'
    r.assets:iconSymbol('mouse-right',x+controlW+gap+7,L.navY+5,18,r.colors.muted)
    r:hit({x=x+controlW+gap,y=L.navY,w=controlW,h=28,tooltip='Right-drag to pan. Scroll to zoom. Right-click a card to pin its preview. Middle-click for details.'})
    r.assets:iconSymbol('mouse-scroll',x+2*(controlW+gap)+7,L.navY+5,18,r.colors.muted)
    r:hit({x=x+2*(controlW+gap),y=L.navY,w=controlW,h=28,tooltip='Scroll over the table to zoom. Scrolling a floating panel stays inside that panel.'})
    if #visible>0 then
        local revealX=x+3*(controlW+gap)
        r.assets:iconSymbol('search',revealX+5,L.navY+5,18,r.colors.gold)
        r:text(#visible,revealX+30,L.navY+5,12,r.colors.text)
        r:hit({x=revealX,y=L.navY,w=54,h=28,kind='zone',cards=visible,revealed=true,label='Revealed / looked at',tooltip='Inspect revealed cards'})
    end
    r:panel(view.x,view.y,view.w,view.h,'dark')
    Layout.clip(view.x,view.y,view.w,view.h)
    local base=camera:transform();local dx,dy=require('app.board_fx').worldOffset(r)
    local t={x=base.x+dx,y=base.y+dy,scale=base.scale,clip=view};r.worldTransform=t
    love.graphics.push();love.graphics.translate(t.x,t.y);love.graphics.scale(t.scale)
    for i,p in ipairs(seats) do seat(r,p,i,camera:cell(i),Table,battlefields[i],p==human) end
    love.graphics.pop();r.worldTransform=nil;Layout.clip()
    -- The human's hand and prompt controls remain fixed in the familiar locations.
    if human then Table.hand(r,human,L,w,h) end
end
return Multi
