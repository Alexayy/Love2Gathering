local TablePresentation=require('app.table_presentation')
local Presentation=require('app.card_presentation')
local Layout=require('app.layout')
local HUD={}
HUD.groups={
 {key='BEGINNING',label='Beginning',steps={'UNTAP','UPKEEP','DRAW'},matches={UPKEEP=true,DRAW=true}},
 {key='PRECOMBAT',label='Main 1',steps={'PRECOMBAT_MAIN'}},
 {key='COMBAT',label='Combat',steps={'BEGIN_COMBAT'}},
 {key='POSTCOMBAT',label='Main 2',steps={'POSTCOMBAT_MAIN'}},
 {key='END',label='Ending',steps={'END_TURN'}}}
-- Opponent hands are a public count. A sleeve has no card identity, anchor or hit target.
function HUD.opponentHand(r,player,x,y,w,h,compact)
    local count=tonumber(player.handCount)
    local label=count and tostring(count) or '?'
    local shown=math.min(count or 0,compact and 5 or 9)
    local zoom=r.worldTransform and r.worldTransform.scale or 1
    local size=compact and math.min(h-6,math.max(15,math.ceil(12/zoom))) or 16
    local font=r.assets:titleFont(size,r.model.settings)
    local badgeW=math.max(size+6,font:getWidth(label)+10)
    local gap=5
    local space=w-badgeW-gap
    local ch=math.min(h*(compact and .78 or 1.48),space*.94)
    if ch<5 then return end
    local cw=ch/1.4
    local angle=(compact and .29 or .38)*math.min(1,math.max(0,shown-1)/4)
    local outer=cw*math.cos(angle)+ch*math.sin(angle)
    local spread=math.min(math.max(0,space-outer),math.max(0,shown-1)*cw*(compact and .40 or .52))
    local fanW=shown>0 and outer+spread or math.min(h*.5,20)
    local left=x+(w-fanW-gap-badgeW)/2
    local g=love.graphics
    g.push('all')
    local clipX,clipY=g.transformPoint(x,y)
    local clipR,clipB=g.transformPoint(x+w,y+h)
    g.intersectScissor(clipX,clipY,clipR-clipX,clipB-clipY)
    for i=1,shown do
        local t=shown>1 and (i-1)*2/(shown-1)-1 or 0
        local cx=left+fanW/2+t*spread/2
        local cy=(compact and y+h*.52 or y+h-2-ch*.5)-t*t*ch*.08
        g.push()
        g.translate(cx,cy)
        g.rotate(-t*angle)
        g.setColor(.08,.10,.14,1)
        g.rectangle('fill',-cw/2,-ch/2,cw,ch,2,2)
        r.assets:cardBack(-cw/2,-ch/2,cw,ch,r.model.settings.cardBackStyle)
        g.setColor(.70,.76,.84,.85)
        g.setLineWidth(1)
        g.rectangle('line',-cw/2,-ch/2,cw,ch,2,2)
        g.pop()
    end
    if shown==0 then r.assets:iconSymbol('hand',left,y+(h-fanW)/2,fanW,r.colors.muted)end
    local bx=left+fanW+gap
    local badgeH=font:getHeight()+2
    g.setColor(.029,.039,.052,.95)
    g.rectangle('fill',bx,y+(h-badgeH)/2,badgeW,badgeH,badgeH/2,badgeH/2)
    r:strong(label,bx,y+(h-font:getHeight())/2,size,r.colors.text,badgeW,'center')
    g.pop()
end
function HUD.duelSeat(r,p,cx,cy,slot,nameOnRight)
    local game,C=r.model.game,r.colors
    local tint=r:playerColor(p)
    local active=game.activePlayerId==p.id
    local offered=r.model:canSelect(p.id)
    local radius=24
    local name=p.name or 'Player'
    local width=math.max(86,math.min(163,r:font(16):getWidth(name)+22))
    local nameX=nameOnRight and cx+radius-4 or cx-radius+4-width
    local align=nameOnRight and 'left' or 'right'
    love.graphics.push('all')
    love.graphics.setColor(.035,.048,.061,.94)
    love.graphics.rectangle('fill',nameX,cy-15,width,32,5,5)
    local ring=offered and C.accent or active and C.gold or tint
    love.graphics.setColor(ring[1],ring[2],ring[3],.65)
    love.graphics.line(nameX+6,cy+17,nameX+width-6,cy+17)
    local opponent=slot=='far'
    r:strong(r:fit(name,width-20,16,1),nameX+10,opponent and cy-9 or cy-15,16,C.text,width-20,align)
    if opponent then
        local compact=game.format=='Commander'
        local maxWidth=compact and 110 or 190
        local leftEdge=r.model.replay and 174 or 16
        local fanW=math.min(maxWidth,nameX-6-leftEdge)
        local fanX=nameX-6-fanW
        if fanW<maxWidth then
            -- The replay transport and pinned panels can squeeze the name side.
            local screenW=Layout.dimensions()
            local right=cx+151
            local limit=r.model.replay and screenW-16 or Layout.beforeDamage(screenW).x-6
            if limit-right>fanW then fanW=math.min(maxWidth,limit-right);fanX=right end
        end
        HUD.opponentHand(r,p,fanX,cy-24,fanW,36,compact)
    elseif p.handCount~=nil then
        r:text(tostring(p.handCount)..' in hand',nameX+10,cy+4,11,C.muted,width-20,align)
    end
    love.graphics.setColor(.018,.024,.033,1)
    love.graphics.circle('fill',cx,cy,radius+2)
    r:drawAvatar(p,cx-radius+2,cy-radius+2,(radius-2)*2,slot)
    love.graphics.setColor(ring)
    love.graphics.setLineWidth(offered and 3 or 1.5)
    love.graphics.circle('line',cx,cy,radius)
    if active then
        love.graphics.setColor(C.gold)
        love.graphics.polygon('fill',cx-5,cy-radius-1,cx,cy-radius-6,cx+5,cy-radius-1)
    end
    local life=tostring(p.life or 0)
    local numberWidth=math.max(34,r:font(19):getWidth(life)+16)
    love.graphics.setColor(.032,.043,.055,1)
    love.graphics.rectangle('fill',cx-numberWidth/2,cy+5,numberWidth,22,9,9)
    love.graphics.setColor(ring)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle('line',cx-numberWidth/2,cy+5,numberWidth,22,9,9)
    r:strong(life,cx-numberWidth/2,cy+5,19,C.text,numberWidth,'center')
    love.graphics.pop()
    local seat={x=cx-radius-3,y=cy-radius-3,w=2*radius+6,h=2*radius+7}
    r.playerRects[p.id]=seat
    local info=Presentation.playerTooltip(p,game.commanderDamageEnabled)
    local left=math.min(nameX,seat.x)
    r:hit({x=left,y=seat.y,w=math.max(nameX+width,seat.x+seat.w)-left,h=seat.h,kind='player',
        card={id=p.id,name=name},commanderDetails=true,tooltip=offered and info..' · legal target' or info})
end
function HUD.draw(r,L,w,h)
    local m,C=r.model,r.colors;local game=m.game or{};local active,holder
    for _,p in ipairs(game.players or{})do if p.id==game.activePlayerId then active=p end;if p.id==game.priorityPlayerId then holder=p end end
    local accent=active and r:playerColor(active)or C.muted
    love.graphics.push('all')
    love.graphics.setColor(.022,.035,.050,m.settings.highContrast and 1 or .94)
    love.graphics.rectangle('fill',16,14,w-32,94,7,7)
    love.graphics.setColor(accent[1],accent[2],accent[3],.9)
    love.graphics.rectangle('fill',18,23,3,42,2,2)
    r:strong(r:fit((active and active.name or'Opening hand')..' · Turn '..tostring(game.turn or 1),w*.31-16,20,1),30,20,20,accent,w*.31-16)
    local step=tostring(game.step or'Pregame'):gsub('_',' ')
    local cx=w*.32;local cw=w-312-cx
    r:strong(r:fit(step,cw,20,1),cx,20,20,C.text,cw,'center')
    local priority=holder and(TablePresentation.isLocalSeat(game,holder) and 'You' or holder.name) or 'Engine'
    if game.priority and game.priority.autoPass==false then priority=priority..' · Full Control'end
    local prompt=m:prompt()
    r:text('PRIORITY · '..priority,28,57,16,holder and r:playerColor(holder)or C.muted,w*.32)
    local primary=TablePresentation.primary(prompt,game)
    local execution=game.execution or{}
    if execution.stopRequested==true and execution.terminationConfirmed~=true then primary='Stopping game · waiting for engine confirmation'
    elseif m.api and m.api.status and not m.replay then
        local pending=m.api:status(m.roomConnectionId and'room'or'engine')
        if pending and(pending.oldestSeconds or 0)>=2 then primary=string.format('Waiting for engine response · %.1fs',pending.oldestSeconds)end
    end
    if m.roomTransport and m.roomTransport.state~='connected' then primary=m.roomTransport.message or'Reconnecting · current choices preserved'end
    r:strong(r:fit(primary,cw,16,1),cx,53,16,prompt and C.gold or C.muted,cw,'center')
    local key=Presentation.phaseKey(game);local gap=6;local width=(w-48-gap*4)/5
    local current
    for i,group in ipairs(HUD.groups)do if key==group.key or group.matches and group.matches[key]then current=i end end
    r.phaseAccent=r.phaseAccent or current or 1
    local ease=m.settings.reducedMotion and 1 or 1-math.exp(-(r.dt or 1/60)*18)
    r.phaseAccent=r.phaseAccent+((current or r.phaseAccent)-r.phaseAccent)*ease
    for i,group in ipairs(HUD.groups)do
        local x=24+(i-1)*(width+gap);local selected=i==current
        if selected then
            love.graphics.setColor(accent[1],accent[2],accent[3],.18)
            love.graphics.rectangle('fill',x,77,width,29,3,3)
        elseif i>1 then
            love.graphics.setColor(.29,.34,.38,.65)
            love.graphics.line(x-3,81,x-3,102)
        end
        r:strong(group.label,x+8,84,16,selected and accent or C.muted,width-78,'center')
        for j,side in ipairs({'own','opponent'})do
            local enabled=m:phaseStop(group,side);local sx=x+width-66+(j-1)*32
            r.assets:iconSymbol(side=='own'and'player'or'players',sx+6,84,18,enabled and C.gold or C.muted)
            r:hit({x=sx,y=78,w=32,h=32,kind='phase-stop',side=side,phase=group.key,
                action=function()m:togglePhaseStop(group,side)end,
                tooltip=(enabled and'Remove'or'Set')..' '..group.label..' stop · '..(side=='own'and'your turns'or'opponents’ turns')})
        end
    end
    if current then
        love.graphics.push('all');love.graphics.setColor(accent);love.graphics.rectangle('fill',26+(r.phaseAccent-1)*(width+gap),105,width-4,3,2,2);love.graphics.pop()
    end
    love.graphics.pop()
end
function HUD.zone(r,player,name,x,y,w,compact,height)
    local cards=player[name]or{};local offered=0
    for _,card in ipairs(cards)do if r.model:canSelect(card.id)then offered=offered+1 end end
    local label=({graveyard='Graveyard',exile='Exile',command='Command'})[name]or name
    height=height or 38
    r:panel(x,y,w,height,offered>0 and'accent'or'dark')
    if r.zoneAnchor then r:zoneAnchor(player.id,name,{x=x,y=y,w=w,h=height})end
    r.assets:iconSymbol(name,x+7,y+9,20,offered>0 and r.colors.accent or r.colors.muted)
    r:text(label,x+30,y+5,10,r.colors.text,w-32)
    r:strong(#cards,x+30,y+19,14,r.colors.text,w-34)
    if offered>0 then
        if compact then r.assets:iconSymbol('play',x+w-20,y+20,12,r.colors.accent)
        else r:strong(offered..' playable',x+5,y+41,12,r.colors.accent,w-10,'center')end
    end
    r:hit({x=x,y=y,w=w,h=height,kind='zone',cards=cards,zone=name,playerId=player.id,
        action=function()r.model:openZone(player.id,name,player.name..' · '..label)end,
        tooltip=label..' · '..#cards..' cards'..(offered>0 and' · '..offered..' native actions available'or' · inspect')})
end
return HUD
