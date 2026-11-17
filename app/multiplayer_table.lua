local Layout=require('app.layout')
local Camera=require('app.table_camera')
local Presentation=require('app.card_presentation')
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
    for _,p in ipairs(game.players or {}) do if p.human then human=p else bots[#bots+1]=p end end
    -- Retain the familiar human lower field while giving every bot a full seat.
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
local function seat(r,player,index,c,Table)
    local C=r.colors;local m=r.model;local selected=m:canSelect(player.id)
    local active=m.game.activePlayerId==player.id;local tint=r:playerColor(player)
    r:panel(c.x,c.y,c.w,c.h,selected and'accent'or'dark')
    r:drawPlaymat(player,c.x+4,c.y+4,c.w-8,c.h-8)
    love.graphics.push('all');love.graphics.setColor(tint[1],tint[2],tint[3],active and .85 or .25)
    love.graphics.setLineWidth(active and 2 or 1);love.graphics.rectangle('line',c.x+2,c.y+2,c.w-4,c.h-4,6,6);love.graphics.pop()
    r:drawAvatar(player,c.x+12,c.y+12,32)
    r:strong(r:fit(player.name or'Player',c.w-290,18,1),c.x+52,c.y+12,18,tint,c.w-290)
    r.assets:iconSymbol('life',c.x+c.w-102,c.y+19,22,tint);r:strong(player.life,c.x+c.w-73,c.y+10,32,tint,64,'center')
    local playerBox=r:screenRect({x=c.x+10,y=c.y+8,w=c.w-20,h=42})
    if within(r.multiplayerView,playerBox.x+playerBox.w/2,playerBox.y+playerBox.h/2)then r.playerRects[player.id]=playerBox end
    r:hit({x=c.x+10,y=c.y+8,w=c.w-20,h=42,kind='player',card={id=player.id,name=player.name},focusIndex=index,
        tooltip=Presentation.playerTooltip(player,m.game.commanderDamageEnabled)..(selected and' · legal target'or' · click to focus'),commanderDetails=true})
    r:priorityBadge(player,c.x+12,c.y+51,166,21)
    r.assets:iconSymbol('hand',c.x+c.w-168,c.y+17,18,tint)
    r:text(player.handCount or #(player.hand or{}),c.x+c.w-144,c.y+18,14,C.text)
    if active then r.assets:iconSymbol('turn',c.x+c.w-199,c.y+17,18,C.gold)end
    local top=m:libraryTop(player)
    if top then
        r:drawCard(top,c.x+202,c.y+48,30,42,{kind='library-top',animate=true})
        local hit=r.hits[#r.hits];if hit and hit.card==top then hit.libraryPlayerId=player.id;hit.libraryGameId=m.game.gameId end
        r:zoneAnchor(player.id,'library',{x=c.x+202,y=c.y+48,w=30,h=42})
    else
        r:button('Library '..tostring(player.libraryCount or 0),c.x+192,c.y+51,106,34,function()m:openLibrary(player.id)end,false,{size=12})
        r:zoneAnchor(player.id,'library',{x=c.x+192,y=c.y+51,w=106,h=34})
    end
    local HUD=require('app.table_hud')
    HUD.zone(r,player,'graveyard',c.x+c.w-300,c.y+49,90,true)
    HUD.zone(r,player,'exile',c.x+c.w-200,c.y+49,90,true)
    HUD.zone(r,player,'command',c.x+c.w-100,c.y+49,90,true)
    r:commanderSummary(player,c.x+12,c.y+88,c.w-24,12)
    Table.field(r,player,c.x+14,c.y+119,c.w-28,c.h-134,not player.human)
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
    camera:configure(view,#seats)
    if not camera.opened then
        local index=1;for i,p in ipairs(seats) do if p.human then index=i;break end end
        camera:overview(true);camera.opened=true
    end
    camera:followTurn(game.activePlayerId,game.turn,seats,m.settings.autoFollowTurn,m.settings.reducedMotion or m.settings.animations==false,require('app.table_presentation').freeze(r))
    camera:update(r.dt,m.settings.reducedMotion or m.settings.animations==false)
    r.multiplayerView=view;r.multiplayerSeats=seats
    -- Keep seat navigation left of the existing floating log/actions defaults.
    local stripX=L.viewport.x+6;local stripW=L.viewport.w-12
    local controlW=34;local gap=5;local playerW=math.min(194,(stripW-controlW*4-gap*(#seats+3))/#seats)
    for i,p in ipairs(seats) do
        local x=stripX+(i-1)*(playerW+gap);local target=m:canSelect(p.id)
        local label=p.name
        if playerW<155 then label=p.human and 'You' or ((p.isHuman or p.bot==false) and p.name or ('Bot '..(p.seat or p.name:match('(%d+)$') or i))) end
        iconButton(r,(p.human or p.isHuman or p.bot==false) and 'player' or 'bot',r:fit(label,playerW-36,12,1),x,L.navY,playerW,function()
            if target then m:selectCard({id=p.id,name=p.name}) else camera:focus(i) end
        end,camera.focusIndex==i or target)
        local hit=r.hits[#r.hits];hit.kind='seat-focus';hit.playerId=p.id;hit.focusIndex=i
        r.playerRects[p.id]={x=x,y=L.navY,w=playerW,h=28}
        hit.tooltip=p.name..' · '..tostring(p.life)..' life\n'..tostring(p.handCount or 0)..' in hand · '..tostring(p.libraryCount or 0)..' in library'..(target and' · legal target'or' · click to focus')
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
    local ownIndex=1;for i,p in ipairs(seats)do if p.human then ownIndex=i;break end end
    iconButton(r,'player',nil,x,L.navY,controlW,function()camera:focus(ownIndex)end,camera.focusIndex==ownIndex)
    r.hits[#r.hits].tooltip='My Battlefield';r.hits[#r.hits].kind='table-own';x=x+controlW+gap
    iconButton(r,'overview',nil,x,L.navY,controlW,function() camera:overview() end,camera.mode=='overview')
    r.hits[#r.hits].tooltip='Fit Table · four-player overview';r.hits[#r.hits].kind='table-overview'
    r.assets:iconSymbol('mouse-right',x+controlW+gap+7,L.navY+5,18,r.colors.muted)
    r:hit({x=x+controlW+gap,y=L.navY,w=controlW,h=28,tooltip='Right-drag to move across the table. Scroll to zoom. Right-click a card to inspect.'})
    r.assets:iconSymbol('mouse-scroll',x+2*(controlW+gap)+7,L.navY+5,18,r.colors.muted)
    r:hit({x=x+2*(controlW+gap),y=L.navY,w=controlW,h=28,tooltip='Scroll over the table to zoom. Scrolling a floating panel stays inside that panel.'})
    local visible={}
    for _,group in ipairs(game.revealed or {}) do for _,card in ipairs(group.cards or {}) do visible[#visible+1]=card end end
    for _,group in ipairs(game.lookedAt or {}) do for _,card in ipairs(group.cards or {}) do visible[#visible+1]=card end end
    if #visible>0 then
        local x=w-350
        r.assets:iconSymbol('search',x,L.navY+5,18,r.colors.gold)
        r:text(#visible,x+25,L.navY+5,12,r.colors.text)
        r:hit({x=x-5,y=L.navY,w=54,h=28,kind='zone',cards=visible,label='Revealed / looked at',tooltip='Inspect revealed cards'})
    end
    r:panel(view.x,view.y,view.w,view.h,'dark')
    Layout.clip(view.x,view.y,view.w,view.h)
    local base=camera:transform();local dx,dy=require('app.board_fx').worldOffset(r)
    local t={x=base.x+dx,y=base.y+dy,scale=base.scale,clip=base.clip};r.worldTransform=t
    love.graphics.push();love.graphics.translate(t.x,t.y);love.graphics.scale(t.scale)
    for i,p in ipairs(seats) do seat(r,p,i,camera:cell(i),Table) end
    love.graphics.pop();r.worldTransform=nil;Layout.clip()
    -- The human's hand and prompt controls remain fixed in the familiar locations.
    if human then Table.hand(r,human,L,w,h) end
end
return Multi
