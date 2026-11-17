local Layout=require('app.layout')
local Presentation=require('app.card_presentation')
local HUD={}
HUD.groups={
 {key='BEGINNING',label='Beginning',steps={'UNTAP','UPKEEP','DRAW'},matches={UPKEEP=true,DRAW=true}},
 {key='PRECOMBAT',label='Main 1',steps={'PRECOMBAT_MAIN'}},
 {key='COMBAT',label='Combat',steps={'BEGIN_COMBAT'}},
 {key='POSTCOMBAT',label='Main 2',steps={'POSTCOMBAT_MAIN'}},
 {key='END',label='Ending',steps={'END_TURN'}}}
function HUD.draw(r,L,w,h)
    local m,C=r.model,r.colors;local game=m.game or{};local active,holder
    for _,p in ipairs(game.players or{})do if p.id==game.activePlayerId then active=p end;if p.id==game.priorityPlayerId then holder=p end end
    local accent=active and r:playerColor(active)or C.muted
    r:panel(16,14,w-32,94,{.018,.029,.047,.96})
    if active then r:drawAvatar(active,27,21,36)end
    r:strong(r:fit((active and active.name or'Opening hand')..' · Turn '..tostring(game.turn or 1),w*.34-80,20,1),74,21,20,accent,w*.34-80)
    local step=tostring(game.step or'Pregame'):gsub('_',' ')
    local cx=w*.36;local cw=math.min(490,w*.37)
    r:strong(r:fit(step,cw,20,1),cx,20,20,C.text,cw,'center')
    local priority=holder and(holder.human and'You'or holder.name)or'Engine'
    if game.priority and game.priority.autoPass==false then priority=priority..' · Full Control'end
    local prompt=m:prompt()
    r:text('PRIORITY · '..priority,28,57,16,holder and r:playerColor(holder)or C.muted,w*.32)
    local primary=require('app.table_presentation').primary(prompt,game)
    local execution=game.execution or{}
    if execution.stopRequested==true and execution.terminationConfirmed~=true then primary='Stopping game · waiting for engine confirmation'
    elseif m.api and m.api.status and not m.replay then
        local pending=m.api:status(m.roomConnectionId and'room'or'engine')
        if pending and(pending.oldestSeconds or 0)>=2 then primary=string.format('Waiting for engine response · %.1fs',pending.oldestSeconds)end
    end
    if m.roomTransport and m.roomTransport.state~='connected' then primary=m.roomTransport.message or'Reconnecting · current choices preserved'end
    r:strong(r:fit(primary,w*.48,16,1),w*.35,56,16,prompt and C.gold or C.muted,w*.48,'center')
    local key=Presentation.phaseKey(game);local gap=6;local width=(w-48-gap*4)/5
    local current
    for i,group in ipairs(HUD.groups)do if key==group.key or group.matches and group.matches[key]then current=i end end
    r.phaseAccent=r.phaseAccent or current or 1
    local ease=m.settings.reducedMotion and 1 or 1-math.exp(-(r.dt or 1/60)*18)
    r.phaseAccent=r.phaseAccent+((current or r.phaseAccent)-r.phaseAccent)*ease
    for i,group in ipairs(HUD.groups)do
        local x=24+(i-1)*(width+gap);local selected=i==current
        r:panel(x,78,width,30,selected and'accent'or'dark')
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
