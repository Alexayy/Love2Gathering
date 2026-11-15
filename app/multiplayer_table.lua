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
    r:panel(c.x,c.y,c.w,c.h,selected and 'accent' or 'dark')
    r:drawPlaymat(player,c.x+8,c.y+8,c.w-16,c.h-16)
    love.graphics.setColor(tint[1],tint[2],tint[3],active and 1 or .65)
    love.graphics.rectangle('fill',c.x+8,c.y+9,6,c.h-18,2,2)
    love.graphics.setLineWidth(2);love.graphics.rectangle('line',c.x+2,c.y+2,c.w-4,c.h-4,6,6)
    r:drawAvatar(player,c.x+18,c.y+15,34)
    r:strong(r:fit(player.name or 'Player',350,24,1),c.x+60,c.y+15,24,tint,350)
    r:priorityBadge(player,c.x+c.w-310,c.y+67,180,22)
    if active then r.assets:iconSymbol('turn',c.x+420,c.y+22,20,C.gold) end
    r.assets:iconSymbol('life',c.x+c.w-108,c.y+19,23,tint)
    r:strong(player.life,c.x+c.w-82,c.y+5,44,tint,74,'center')
    local playerBox=r:screenRect({x=c.x+18,y=c.y+12,w=c.w-36,h=60})
    if within(r.multiplayerView,playerBox.x+playerBox.w/2,playerBox.y+playerBox.h/2)then r.playerRects[player.id]=playerBox end
    r:hit({x=c.x+18,y=c.y+12,w=c.w-36,h=44,kind='player',card={id=player.id,name=player.name},focusIndex=index,
        tooltip=Presentation.playerTooltip(player,m.game.commanderDamageEnabled)..(selected and' · legal target'or' · click to focus'),commanderDetails=true})
    r.assets:iconSymbol('library',c.x+24,c.y+66,28,tint)
    r:strong(player.libraryCount or 0,c.x+58,c.y+66,20,C.text)
    r:hit({x=c.x+22,y=c.y+62,w=78,h=38,kind='library-zone',libraryPlayerId=player.id,action=function()m:openLibrary(player.id)end,tooltip=player.name..' · library: '..tostring(player.libraryCount or 0)..' · inspect the entitled top card'})
    r.assets:iconSymbol('hand',c.x+116,c.y+66,28,tint)
    r:strong(player.handCount or #(player.hand or {}),c.x+150,c.y+66,20,C.text)
    r:hit({x=c.x+114,y=c.y+62,w=78,h=38,tooltip=player.name..' · hand: '..tostring(player.handCount or 0)})
    -- Only count/back faces are drawn for opponents; no private card is inspected.
    if not player.human then
        for i=1,math.min(player.handCount or 0,10) do r:drawCard({},c.x+208+(i-1)*17,c.y+66,24,34,{back=true,noHit=true}) end
    end
    local commands=player.command or {}
    for i,card in ipairs(commands) do
        r:drawCard(card,c.x+24,c.y+142+(i-1)*183,118.8,166.32,{kind='command',animate=true})
    end
    r.assets:iconSymbol('commander',c.x+43,c.y+91,19,C.gold)
    Table.field(r,player,c.x+168,c.y+140,c.w-334,c.h-190-(player.human and 108 or 0),not player.human)
    local zx=c.x+c.w-144
    zone(r,player,'graveyard','graveyard',zx,c.y+142,122)
    zone(r,player,'exile','exile',zx,c.y+202,122)
    if m:libraryTop(player)then Table.library(r,player,zx,c.y+270,122)end
    require('app.board_fx').playerAuras(r,player,c.x+174,c.y+104)
    r:commanderSummary(player,c.x+410,c.y+104,c.w-440,14)
    local mx=c.x+410
    for _,symbol in ipairs({'W','U','B','R','G','C'}) do
        local n=(player.mana or {})[symbol] or 0
        if n>0 then r.assets:mana(symbol,mx,c.y+69,18);r:text(n,mx+21,c.y+70,12,C.text);mx=mx+48 end
    end
    if Presentation.eliminated(player)then
        love.graphics.push('all');love.graphics.setColor(.005,.009,.015,.76);love.graphics.rectangle('fill',c.x+3,c.y+3,c.w-6,c.h-6,6,6)
        r:strong('OUT',c.x+30,c.y+c.h*.41,52,C.muted,c.w-60,'center')
        r:strong(player.left==true and'LEFT MATCH'or'ELIMINATED',c.x+30,c.y+c.h*.41+62,22,C.muted,c.w-60,'center')
        love.graphics.pop()
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
        camera:focus(index,true);camera.opened=true
    end
    camera:followTurn(game.activePlayerId,game.turn,seats,m.settings.autoFollowTurn,m.settings.reducedMotion or m.settings.animations==false)
    camera:update(r.dt,m.settings.reducedMotion or m.settings.animations==false)
    r.multiplayerView=view;r.multiplayerSeats=seats
    -- Keep seat navigation left of the existing floating log/actions defaults.
    local stripX=L.board.x+12;local stripW=L.board.w-380
    local controlW=32;local gap=5;local playerW=math.min(194,(stripW-controlW*3-gap*(#seats+2))/#seats)
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
    iconButton(r,'overview',nil,x,L.navY,controlW,function() camera:overview() end,camera.mode=='overview')
    r.hits[#r.hits].tooltip='Whole table';r.hits[#r.hits].kind='table-overview'
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
