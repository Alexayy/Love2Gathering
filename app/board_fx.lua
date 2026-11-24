-- Presentation of authoritative projections only. No legality or combat rules.
local Board={}
local Dice=require('app.dice')
local Layout=require('app.layout')
local Mechanics=require('app.mechanic_fx')
function Board.mechanicTooltip(card)return Mechanics.tooltip(card)end
function Board.cardUnderlay(r,card,x,y,w,h,options)return Mechanics.cardUnderlay(r,card,x,y,w,h,options)end
function Board.cardOverlay(r,card,x,y,w,h,options,badgeRight,badgeBottom,headerH)
    return Mechanics.cardOverlay(r,card,x,y,w,h,options,badgeRight,badgeBottom,headerH)
end
local palette={{.70,.53,1},{.34,.69,1},{1,.64,.30},{1,.43,.64},{.67,.83,.34},{.45,.82,.88},{.88,.65,.91},{.84,.76,.48},{.55,.73,.98}}
local function list(value)return type(value)=='table'and value or{}end
local function id(value)return type(value)=='table'and(value.id or value.targetId or value.playerId)or value end
local function point(box)return box and{x=box.x+box.w/2,y=box.y+box.h/2}end
local function tint(c,a)love.graphics.setColor(c[1],c[2],c[3],a or 1)end
local function hash(value)
    local result=0;for i=1,#tostring(value or'')do result=(result*31+tostring(value):byte(i))%65521 end;return result
end
local function pulse(age,duration)
    if age<0 or age>=duration then return 0 end
    local t=age/duration;local attack=math.min(1,t/.14);attack=attack*attack*(3-2*attack)
    return math.sin(t*math.pi*2.2)*attack*(1-t)^2
end
local function interacting(r)
    local m=r.model
    if r.drag or r.panning or m.inspectCard or m.zoneView or m.cardActionSheet then return true end
    local prompt=m.prompt and m:prompt()
    return prompt and not prompt.priority
end
function Board.worldOffset(r)
    local e=r.boardImpact
    if not e or interacting(r)or r.model.settings.reducedMotion or r.model.settings.animations==false or r.model.settings.cameraShake==false or r.model.settings.presentationPacing=='Minimal' then return 0,0 end
    local amount=pulse(e.age,e.duration)*e.intensity
    return amount*5,amount*3
end
function Board.linkColor(index)
    local h=(index*.618033988749895)%1;local v=.96;local low=.34;local sector=h*6;local part=sector%1;local high=low+(v-low)*part;local down=v-(v-low)*part
    local colors={{v,high,low},{down,v,low},{low,v,high},{low,down,v},{high,low,v},{v,low,down}}
    return colors[math.floor(sector)+1]
end
function Board.color(r,player)
    if type(player)~='table'then player=(r.boardPlayers or{})[player]end
    if player and player.human then return r.colors.accent end
    return player and palette[(tonumber(player.seat)or 0)%#palette+1]or r.colors.purple
end
function Board.damageActor(r,cards,event)
    -- Damage event.playerId belongs to the damaged player/permanent controller.
    -- Attribute the outline only to an observed native source controller.
    if type(event.controllerId)=='string'then return event.controllerId end
    if type(event.sourceControllerId)=='string'then return event.sourceControllerId end
    return(cards[event.sourceId]or(r.oldBoardCards or{})[event.sourceId]or{}).controllerId
end
function Board.index(game)
    local cards,players,attached,curses={},{},{},{}
    for _,p in ipairs(list(game and game.players))do
        players[p.id]=p
        for _,zone in ipairs({'battlefield','hand','command','graveyard','exile'})do
            for _,card in ipairs(list(p[zone]))do
                if card.id then cards[card.id]=card end
                if zone=='battlefield'then
                    local target=id(card.attachedToId or card.attachedTo)
                    if type(target)=='string'then attached[target]=attached[target]or{};table.insert(attached[target],card)end
                    local targetPlayer=id(card.attachedToPlayerId)
                    if type(targetPlayer)=='string'then curses[targetPlayer]=curses[targetPlayer]or{};table.insert(curses[targetPlayer],card)end
                end
            end
        end
    end
    for _,item in ipairs(list(game and game.stack))do
        local card=item.sourceCard;local key=item.sourceId or(type(card)=='table'and card.id)
        if type(card)=='table'and type(key)=='string'and not cards[key]then cards[key]=card end
    end
    return cards,players,attached,curses
end
function Board.blockStatus(group)
    if not group or not group.blocked then return nil end
    if group.declarationConfirmed==true then return 'BLOCKED',true end
    if group.declarationConfirmed==false then return 'PROVISIONAL',false end
    return 'BLOCK ASSIGNED',false -- Older recordings have no acknowledgement.
end
function Board.prepare(r)
    r.boardCards,r.boardPlayers,r.boardAttached,r.boardCurses=Board.index(r.model.game)
    r.playerRects={};r.boardLinks={};r.previousStackRows=r.stackRows or r.previousStackRows;r.ambientParticleCount=0
    r.boardCommanders={}
    for _,player in pairs(r.boardPlayers)do for _,commander in ipairs(list(player.commanders))do
        if commander.id then r.boardCommanders[commander.id]=commander end
    end end
end
function Board.cardStatus(r,card)
    local game=r.model.game or{};local prompt=r.model.prompt and r.model:prompt()
    local combat=prompt and prompt.combat
    if combat and combat.blockerId==card.id then return{label='CHOOSE ATTACKER',confirmed=false}end
    for _,group in ipairs(list((game.combat or{}).groups))do for _,blocker in ipairs(list(group.blockerIds))do
        if blocker==card.id then return{label=group.declarationConfirmed==true and'BLOCK CONFIRMED'or'BLOCK ASSIGNED',confirmed=group.declarationConfirmed==true}end
    end end
    if card.attacking and combat and combat.role=='attackers'then return{label='ATTACK SELECTED',confirmed=false}end
end
function Board.priority(r,p,x,y,w,height)
    local game=r.model.game or{};local holder=game.priorityPlayerId
    if type(holder)=='table'then holder=holder.id end
    local c=Board.color(r,p)
    if holder==p.id and game.running~=false then
        height=height or 22
        -- The caller reserves this lane separately from name, avatar and HP.
        -- Every pixel, including the ember and elapsed label, stays inside it.
        r:panel(x,y,w,height,'dark')
        tint(c,.75);love.graphics.setLineWidth(1);love.graphics.rectangle('line',x+.5,y+.5,w-1,height-1,4,4)
        r.assets:iconSymbol('focus',x+4,y+(height-14)/2,14,c)
        local stamp=game.priorityStartedAt or game.decisionStartedAt
        r.priorityObserved=r.priorityObserved or{}
        if r.priorityObserved.holder~=holder then r.priorityObserved={holder=holder,started=love.timer.getTime()}end
        local replay=r.model.replay
        local frame=replay and(replay.frames or{})[replay.index or 1]
        local now=replay and(tonumber(frame and frame.timestamp)or tonumber(stamp)or 0)/1000 or os.time()
        local elapsed=tonumber(stamp)and math.max(0,now-tonumber(stamp)/1000)or(replay and 0 or math.max(0,love.timer.getTime()-(r.priorityObserved.started or love.timer.getTime())))
        local label=string.format('%d:%02d',math.floor(elapsed/60),math.floor(elapsed%60))
        local ropeX=x+25;local ropeY=y+height/2;local ropeW=math.max(12,w-85)
        tint(c,.35);love.graphics.setLineWidth(3);love.graphics.line(ropeX,ropeY,ropeX+ropeW,ropeY)
        -- An elapsed indicator, not a fabricated deadline or penalty.
        local still=r.model.settings.reducedMotion or r.model.settings.animations==false
        local ember=ropeX+(still and 1 or elapsed*.12%1)*ropeW;tint(r.colors.gold);love.graphics.circle('fill',ember,ropeY,3)
        r:text(label,x+w-56,y+(height-16)/2,12,c,50,'right')
        r:hit({x=x,y=y,w=w,h=height,tooltip='Holds priority · '..label..' elapsed. This match has no automatic time penalty.'})
    end
end
function Board.layers(r,card,x,y,w,h,options)
    local attachments=(r.boardAttached or{})[card.id]or{}
    for i=#attachments,1,-1 do
        local a=attachments[i]
        r:drawCard(a,x-12*i,y+18*i,w,h,{kind='attachment',animate=options and options.animate})
    end
    for i,exiled in ipairs(list(card.linkedExile))do
        if i<=5 then
            r:drawCard(exiled,x+w*.55+(i-1)*17,y+h*.40,w*.65,h*.65,{kind='linked-exile',angle=math.pi/2,back=exiled.hidden or exiled.faceDown})
        end
    end
    r:drawCard(card,x,y,w,h,options)
end
function Board.playerAuras(r,player,x,y,height,lane)
    local cards=(r.boardCurses or{})[player.id]or{}
    local h=height or 92;local w=h*66/92
    local step=lane and math.min(w*.65,(lane-w)/math.max(1,#cards-1))or 32
    for i,card in ipairs(cards)do
        r:drawCard(card,x+(i-1)*step,y,w,h,{kind='attachment'})
    end
end
function Board.anchor(r,key)
    key=id(key)
    if type(key)~='string'then return nil end
    local current=(r.cardRects or{})[key];local previous=(r.previousCardRects or{})[key]
    -- A death event belongs to the last battlefield position, not its new pile.
    if current and current.kind=='pile'and previous and(previous.kind=='permanent'or previous.kind=='attachment')then return previous end
    local box=current or(r.playerRects or{})[key]or previous or(r.previousPlayerRects or{})[key]
    if box then return box end
    local row=(r.stackRows and r.stackRows[key])or(r.previousStackRows and r.previousStackRows[key])
    if row and row.visible~=false then return row.box or row end
    for _,hit in ipairs(r.model.stackHits or{})do if hit.id==key then return hit end end
end
local function add(r,e)
    r.pendingBoardFX=r.pendingBoardFX or{}
    if#r.pendingBoardFX<96 then r.pendingBoardFX[#r.pendingBoardFX+1]=e end
end
local function particles(r,e)
    if r.sound then
        local sound=e.kind=='cast'and'cast'or(e.kind=='resolve'or e.kind=='life_gain')and'resolve'or'impact'
        r.boardSoundTimes=r.boardSoundTimes or{};local previous=r.boardSoundTimes[sound]
        if not previous or(r.fxClock or 0)-previous>.08 then r:sound(sound);r.boardSoundTimes[sound]=r.fxClock or 0 end
    end
    if not r.model.settings.reducedMotion and r.model.settings.animations~=false then
        local kind=e.kind=='cast'and'cast'or e.kind=='resolve'and'resolve'or e.kind=='life_gain'and'resolve'or'impact'
        if e.kind~='death'then r:burst(kind,e.x,e.y,12)end
        if(e.kind=='clash'or e.kind=='strike')and e.from and e.target then
            r.cardMotions[e.sourceId]={dx=(e.target.x-e.from.x)*.28,dy=(e.target.y-e.from.y)*.28,age=0,duration=.52}
        end
    end
    e.spawned=true
end
function Board.update(r,dt)
    Dice.update(r,dt)
    if r.boardImpact then r.boardImpact.age=r.boardImpact.age+dt;if r.boardImpact.age>=r.boardImpact.duration then r.boardImpact=nil end end
    r.boardEffects=r.boardEffects or{};r.cardMotions=r.cardMotions or{}
    if r.model.settings.reducedMotion or r.model.settings.animations==false then r.cardMotions={}end
    r.seenVisualEvents=r.seenVisualEvents or{}
    r.fxClock=(r.fxClock or 0)+dt
    r.mechanicDirector=r.mechanicDirector or Mechanics.newDirector()
    Mechanics.update(r.mechanicDirector,dt,r.model.settings)
    for key,e in pairs(r.cardMotions)do e.age=e.age+dt;if e.age>e.duration then r.cardMotions[key]=nil end end
    for i=#r.boardEffects,1,-1 do local e=r.boardEffects[i];e.age=e.age+dt;if e.age>=0 and not e.spawned then particles(r,e)end;if e.age>e.duration then table.remove(r.boardEffects,i)end end
    local game=r.model.game;if not game then return end
    local identity=r.model.replay or game.gameId
    local seeking=r.model.replay and r.fxReplayIndex and r.model.replay.index~=r.fxReplayIndex and r.model.replay.index~=r.fxReplayIndex+1
    local rollback=r.fxRevision and tonumber(game.revision)and tonumber(game.revision)<r.fxRevision
    if r.fxIdentity~=identity or seeking or rollback then
        r.fxIdentity=identity;r.fxRevision=nil;r.oldBoardLife=nil;r.oldBoardCards=nil;r.oldCombatKey=nil;r.seenVisualEvents={};r.boardEffects={};r.cardMotions={};r.pendingBoardFX={}
        r.combatAnimationStep=nil;r.combatAnimationStart=nil;r.combatAnimationUntil=nil
        r.visualStepEpoch=nil;r.boardImpact=nil
    end
    r.fxReplayIndex=r.model.replay and r.model.replay.index
    if r.fxRevision==game.revision and not r.model.replay then return end
    local cards,players=Board.index(game)
    Mechanics.observe(r.mechanicDirector,game,cards,identity,seeking or rollback)
    local deathTargets={}
    if r.oldBoardLife then
        for key,p in pairs(players)do
            local old=r.oldBoardLife[key]
            if old and p.life and p.life~=old then add(r,{kind=p.life>old and'life_gain'or'life_loss',targetId=key,ownerId=key,amount=p.life-old})end
        end
        local grave={};for _,p in pairs(players)do for _,card in ipairs(list(p.graveyard))do grave[card.id]=true end end
        for key,old in pairs(r.oldBoardCards or{})do if grave[key]and not(r.oldBoardGrave or{})[key]then add(r,{kind='death',targetId=key,card=old});deathTargets[key]=true end end
        local before=r.oldStackIds or{}
        for _,stack in ipairs(list(game.stack))do if not before[stack.id]then add(r,{kind='cast',sourceId=stack.sourceId or stack.id,ownerId=stack.controllerId,card=stack.sourceCard})end end
        -- Stack disappearance can mean countering, not successful resolution.
        -- A truthful native outcome supplies all resolution celebration.
    end
    local retainedEvents={}
    for _,event in ipairs(list(game.animationEvents))do
        local key=event.id or event.sequence
        if key then retainedEvents[key]=true end
        if key and not r.seenVisualEvents[key]then
            if event.type=='step'then r.visualStepEpoch=key end
            local actualEntry=event.entry==true or event.operation=='entry'or event.toZone=='BATTLEFIELD'
            local impactCard=cards[event.targetId]or cards[event.sourceId]
            local publicImpact=impactCard and not impactCard.hidden and not impactCard.faceDown and event.hidden~=true
            if r.oldBoardLife and event.type=='impact'and actualEntry and publicImpact and(event.commander==true or(tonumber(event.manaValue)or 0)>5)and not r.model.settings.reducedMotion and r.model.settings.animations~=false and r.model.settings.cameraShake~=false and r.model.settings.presentationPacing~='Minimal' then
                local level=math.max(0,math.min(1,tonumber(r.model.settings.boardImpactIntensity)or .55))
                r.boardImpact={age=0,duration=.92,seed=hash(key),intensity=level*2*(event.commander and 1.15 or math.min(1.4,.8+(tonumber(event.manaValue)or 6)/20))}
                if r.sound then r:sound('table-impact')end
            end
            if r.oldBoardLife and event.type=='zone'and event.fromZone=='BATTLEFIELD'and event.toZone=='GRAVEYARD'and type(event.targetId)=='string'and not deathTargets[event.targetId]then
                add(r,{kind='death',targetId=event.targetId,card=(r.oldBoardCards or{})[event.targetId]or cards[event.targetId]});deathTargets[event.targetId]=true
            end
            if r.oldBoardLife and(event.type=='damage'or event.type=='dies'or event.type=='destroy')then
                add(r,{kind=event.type=='damage'and'damage'or'death',sourceId=event.sourceId,targetId=event.targetId,ownerId=Board.damageActor(r,cards,event),amount=event.amount,card=cards[event.targetId]})
                if event.type=='damage'and event.combat==true and(tonumber(event.amount)or 0)>0 then
                    -- XMage selects first/double-strike participants and actual damage.
                    -- Only a source that dealt damage lunges; no inferred retaliation.
                    local phase=tostring(game.turn)..':'..tostring(event.step)..':'..tostring(r.visualStepEpoch)
                    if r.combatAnimationStep~=phase then
                        r.combatAnimationStep=phase
                        r.combatAnimationStart=math.max(r.fxClock,r.combatAnimationUntil or 0)
                        r.combatAnimationUntil=r.combatAnimationStart+.58
                    end
                    add(r,{kind=players[event.targetId]and'strike'or'clash',sourceId=event.sourceId,targetId=event.targetId,amount=event.amount,step=event.step,delay=math.max(0,(r.combatAnimationStart or r.fxClock)-r.fxClock)})
                end
            end
        end
    end
    r.seenVisualEvents=retainedEvents
    r.oldBoardLife={};r.oldBoardGrave={};r.oldStackIds={};r.oldBoardCards={}
    for key,p in pairs(players)do
        r.oldBoardLife[key]=p.life
        for _,card in ipairs(list(p.graveyard))do r.oldBoardGrave[card.id]=true end
        for _,card in ipairs(list(p.battlefield))do r.oldBoardCards[card.id]=card end
    end
    for _,stack in ipairs(list(game.stack))do r.oldStackIds[stack.id]=stack end
    r.fxRevision=game.revision
end
function Board.offset(r,card)
    if interacting(r)or r.model.settings.animations==false or r.model.settings.reducedMotion then return 0,0,0 end
    local scale=r.worldTransform and r.worldTransform.scale or 1
    local dx,dy,angle=0,0,0
    if r.mechanicDirector then
        local mx,my,ma=Mechanics.offset(r.mechanicDirector,card,r.model.settings);dx=dx+mx/scale;dy=dy+my/scale;angle=angle+ma
    end
    local motion=r.cardMotions and r.cardMotions[card.id]
    if motion and motion.age>=0 then
        local progress=math.sin(math.pi*math.min(1,motion.age/motion.duration));dx,dy=motion.dx*progress/scale,motion.dy*progress/scale
    end
    local e=r.model.settings.cameraShake~=false and r.boardImpact
    if e then
        local seed=hash(tostring(card.id)..':'..e.seed);local lag=(seed%7)*.009
        local amount=pulse(e.age-lag,e.duration-lag)*e.intensity
        local direction=(seed%360)*math.pi/180
        dx=dx+math.cos(direction)*amount*(2+seed%4)/scale
        dy=dy+math.sin(direction)*amount*(2+(seed%5))/scale
        angle=amount*((seed%2==0)and 1 or-1)*(.018+(seed%5)*.003)
    end
    return dx,dy,angle
end
function Board.flush(r)
    for _,e in ipairs(r.pendingBoardFX or{})do
        local from=point(Board.anchor(r,e.sourceId))or point(Board.anchor(r,e.ownerId))
        local target=point(Board.anchor(r,e.targetId))
        local at=target or from
        if at then
            e.age=-(e.delay or 0);e.duration=(e.kind=='life_gain'or e.kind=='life_loss')and 1.7 or(e.kind=='damage'and 1.25 or .65);e.x=at.x;e.y=at.y;e.from=from;e.target=target
            if#r.boardEffects>=96 then table.remove(r.boardEffects,1)end
            r.boardEffects[#r.boardEffects+1]=e
            if e.age>=0 then particles(r,e)end
        end
    end
    r.pendingBoardFX={}
    if r.mechanicDirector then Mechanics.flush(r.mechanicDirector,function(key)return Board.anchor(r,key)end,r.previousCardRects,r.playerRects,r.zoneRects,r.previousZoneRects,r.stackRows,r.model.game and r.model.game.stack)end
end
local function line(r,a,b,c,dashed,outline,attack,metadata)
    if not a or not b then return end
    local dx,dy=b.x-a.x,b.y-a.y;local length=math.sqrt(dx*dx+dy*dy);if length<1 then return end
    local ux,uy=dx/length,dy/length
    r.boardLinks=r.boardLinks or{}
    r.boardLinks[#r.boardLinks+1]={from={x=a.x,y=a.y},to={x=b.x,y=b.y},attack=not not attack,color=c,
        kind=metadata and metadata.kind or'effect',sourceId=metadata and metadata.sourceId,targetId=metadata and metadata.targetId}
    local function stroke(color,width,tip)
        tint(color,.94);love.graphics.setLineWidth(width)
        if dashed then for distance=0,length,attack and 26 or 16 do local finish=math.min(length,distance+(attack and 18 or 10));love.graphics.line(a.x+ux*distance,a.y+uy*distance,a.x+ux*finish,a.y+uy*finish)end
        else love.graphics.line(a.x,a.y,b.x,b.y)end
        local tipX,tipY=b.x-ux*(tip*2),b.y-uy*(tip*2)
        love.graphics.polygon('fill',b.x,b.y,tipX-uy*tip,tipY+ux*tip,tipX+uy*tip,tipY-ux*tip)
    end
    if outline then stroke(outline,attack and 8 or 4,attack and 12 or 6)end
    stroke(c,attack and 4 or 1.7,attack and 8 or 4)
    if attack then
        if outline then tint(outline);love.graphics.circle('fill',a.x,a.y,9)end
        tint(c);love.graphics.circle('fill',a.x,a.y,5.5)
    end
    local marker=attack and 22 or 18
    r.assets:iconSymbol('focus',b.x-marker/2,b.y-marker/2,marker,c)
end
function Board.links(r)
    if r.model.page~='table'then return end
    local game=r.model.game or{}
    for index,group in ipairs(list((game.combat or{}).groups))do
        local a=point(Board.anchor(r,group.attackerId));local b=point(Board.anchor(r,group.defenderId))
        local owner=group.attackingPlayerId or((r.boardCards or{})[group.attackerId]or{}).controllerId or game.activePlayerId
        line(r,a,b,Board.linkColor(index),true,Board.color(r,owner),true,{kind='attack',sourceId=group.attackerId,targetId=group.defenderId})
        for _,blocker in ipairs(list(group.blockerIds))do line(r,point(Board.anchor(r,blocker)),a,r.colors.gold,false,nil,nil,{kind='block',sourceId=blocker,targetId=group.attackerId})end
        local label,confirmed=Board.blockStatus(group)
        if label then
            local box=Board.anchor(r,group.attackerId)
            if box then
                local width=math.min(116,math.max(82,box.w));local x=box.x+(box.w-width)/2;local y=box.y-23
                local clip=box.clip
                if not clip or(x>=clip.x and x+width<=clip.x+clip.w and y>=clip.y and y+22<=clip.y+clip.h)then
                    r:panel(x,y,width,22,'dark');r.assets:iconSymbol('block',x+4,y+3,16,confirmed and r.colors.accent or r.colors.gold)
                    r:text(label,x+23,y+4,11,confirmed and r.colors.accent or r.colors.gold,width-27,'center')
                    r:hit({x=x,y=y,w=width,h=22,kind='permanent',card=(r.boardCards or{})[group.attackerId],tooltip=confirmed and'XMage confirmed this attacker is blocked. Removing its blockers does not remove that block.'or'Block assignment is provisional. Choose Done and wait for XMage confirmation.'})
                end
            end
        end
    end
    local hover=r.model.choiceHover
    local focus=hover and hover.combatId and (r.cardRects or {})[hover.combatId]
    if focus and (focus.kind=='permanent' or focus.kind=='attachment') then
        love.graphics.push('all')
        if focus.clip then Layout.clip(focus.clip.x,focus.clip.y,focus.clip.w,focus.clip.h) end
        love.graphics.translate(focus.x+focus.w/2,focus.y+focus.h/2)
        love.graphics.rotate(focus.angle or 0)
        tint(r.colors.accent);love.graphics.setLineWidth(3)
        love.graphics.rectangle('line',-focus.w/2-5,-focus.h/2-5,focus.w+10,focus.h+10,5,5)
        love.graphics.pop()
    end
    local stackHits={};for _,hit in ipairs(r.model.stackHits or{})do stackHits[hit.id]=hit end
    for key,row in pairs(r.stackRows or{})do stackHits[type(key)=='string'and key or row.id or row.stackId]=row end
    local hovered=r.hoverStackId or(r.model.stackHover and r.model.stackHover.id)or r.selectedStackId or r.model.selectedStackId
    local function bounded(box)
        if not box or box.visible==false then return nil end
        box=box.box or box
        local clip=box.clip
        if clip then
            local x,y=math.max(box.x,clip.x),math.max(box.y,clip.y);local right,bottom=math.min(box.x+box.w,clip.x+clip.w),math.min(box.y+box.h,clip.y+clip.h)
            if right<=x or bottom<=y then return nil end
            return{x=x,y=y,w=right-x,h=bottom-y}
        end
        return box
    end
    local function edge(box,toward)
        if not box or not toward then return nil end
        local cx,cy=box.x+box.w/2,box.y+box.h/2;local dx,dy=toward.x-cx,toward.y-cy
        local length=math.max(math.abs(dx)/math.max(1,box.w/2-1),math.abs(dy)/math.max(1,box.h/2-1),.0001)
        return{x=cx+dx/length,y=cy+dy/length}
    end
    for index,item in ipairs(list(game.stack))do
        if hovered==item.id then
            -- Exact stack object rows, not source-card previews or last-frame
            -- coordinates, define these screen-space connection origins.
            local row=bounded(stackHits[item.id]);local targets=item.targetIds or item.targets or{}
            local changed={};for _,target in ipairs(list(item.targets))do if type(target)=='table'and target.changedZones==true then changed[id(target)]=true end end
            if row then for _,target in ipairs(list(targets))do
                local targetId=id(target)
                -- A departed object's ghost/last-frame rectangle is an effect
                -- anchor only, never a current stack-target connection.
                local box=not changed[targetId]and not(type(target)=='table'and target.changedZones==true)and(bounded(stackHits[targetId])or bounded((r.cardRects or{})[targetId])or bounded((r.playerRects or{})[targetId]))or nil
                local center=point(box)
                if box and center then line(r,edge(row,center),edge(box,point(row)),Board.linkColor(index+#list((game.combat or{}).groups)),false,Board.color(r,item.controllerId),false,{kind='stack',sourceId=item.id,targetId=targetId})end
            end end
        end
    end
end
function Board.foreground(r)
    Board.flush(r)
    local moving=r.model.settings.animations~=false and not r.model.settings.reducedMotion
    for _,e in ipairs(r.boardEffects or{})do
        if e.age>=0 then
        local alpha=math.max(0,1-e.age/e.duration);local t=e.age/e.duration
        if e.kind=='life_gain'or e.kind=='life_loss'then
            local c=e.kind=='life_gain'and{.25,.95,.40}or r.colors.red
            local edge=Board.color(r,e.ownerId or e.targetId);edge={edge[1],edge[2],edge[3],alpha}
            local text=(e.amount>0 and'+'or'')..tostring(e.amount);local x,y=e.x-65,e.y-40-(moving and t*48 or 0)
            if r.outlinedStrong then r:outlinedStrong(text,x,y,44,{c[1],c[2],c[3],alpha},edge,130)
            else r:strong(text,x,y,44,{c[1],c[2],c[3],alpha},130,'center')end
        elseif e.kind=='damage'then
            local edge=e.ownerId and Board.color(r,e.ownerId)or r.colors.muted
            line(r,e.from,e.target or{x=e.x,y=e.y},r.colors.red,false,edge)
            if(tonumber(e.amount)or 0)>0 then
                local c=r.colors.red;local x,y=e.x-58,e.y+6-(moving and t*30 or 0)
                if r.outlinedStrong then r:outlinedStrong('−'..tostring(e.amount),x,y,36,{c[1],c[2],c[3],alpha},{edge[1],edge[2],edge[3],alpha},116)
                else r:strong('−'..tostring(e.amount),x,y,36,c,116,'center')end
            end
        elseif e.kind=='death'then
            -- This legacy snapshot observation knows only the destination.
            -- Fracture/offering effects require explicit native operations.
            tint(r.colors.muted or r.colors.purple,alpha);love.graphics.setLineWidth(1.5)
            love.graphics.arc('line','open',e.x,e.y+(moving and t*18 or 0),12*(1-t*.45),0,math.pi,20)
        elseif e.kind=='clash'or e.kind=='strike'then
            local at=e.from and e.target and{x=(e.from.x+e.target.x)/2,y=(e.from.y+e.target.y)/2}or{x=e.x,y=e.y}
            tint(r.colors.gold,alpha);love.graphics.setLineWidth(3);love.graphics.circle('line',at.x,at.y,7+t*34)
        end
        end
    end
    if r.mechanicDirector then Mechanics.draw(r.mechanicDirector,r)end
    Dice.draw(r)
end
return Board
