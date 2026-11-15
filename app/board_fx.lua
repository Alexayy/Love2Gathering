-- Presentation of authoritative projections only. No legality or combat rules.
local Board={}
local Dice=require('app.dice')
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
function Board.worldOffset(r)
    local e=r.boardImpact
    if not e or r.model.settings.reducedMotion or r.model.settings.animations==false then return 0,0 end
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
    r.playerRects={};r.boardLinks={}
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
function Board.playerAuras(r,player,x,y)
    for i,card in ipairs((r.boardCurses or{})[player.id]or{})do
        r:drawCard(card,x+(i-1)*32,y,66,92,{kind='attachment'})
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
    for _,hit in ipairs(r.model.stackHits or{})do if hit.id==key or hit.sourceId==key then return hit end end
end
local function add(r,e)r.pendingBoardFX=r.pendingBoardFX or{};r.pendingBoardFX[#r.pendingBoardFX+1]=e end
local function particles(r,e)
    if r.sound then
        local sound=e.kind=='cast'and'cast'or(e.kind=='resolve'or e.kind=='life_gain')and'resolve'or'impact'
        r.boardSoundTimes=r.boardSoundTimes or{};local previous=r.boardSoundTimes[sound]
        if not previous or(r.fxClock or 0)-previous>.08 then r:sound(sound);r.boardSoundTimes[sound]=r.fxClock or 0 end
    end
    if not r.model.settings.reducedMotion and r.model.settings.animations~=false then
        local kind=e.kind=='cast'and'cast'or e.kind=='resolve'and'resolve'or e.kind=='life_gain'and'resolve'or'impact'
        r:burst(kind,e.x,e.y,e.kind=='death'and 26 or 12)
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
    for key,e in pairs(r.cardMotions)do e.age=e.age+dt;if e.age>e.duration then r.cardMotions[key]=nil end end
    for i=#r.boardEffects,1,-1 do local e=r.boardEffects[i];e.age=e.age+dt;if e.age>=0 and not e.spawned then particles(r,e)end;if e.age>e.duration then table.remove(r.boardEffects,i)end end
    local game=r.model.game;if not game then return end
    local identity=r.model.replay or game.gameId
    local seeking=r.model.replay and r.fxReplayIndex and r.model.replay.index~=r.fxReplayIndex and r.model.replay.index~=r.fxReplayIndex+1
    if r.fxIdentity~=identity or seeking then
        r.fxIdentity=identity;r.fxRevision=nil;r.oldBoardLife=nil;r.oldBoardCards=nil;r.oldCombatKey=nil;r.seenVisualEvents={};r.boardEffects={};r.cardMotions={};r.pendingBoardFX={}
        r.combatAnimationStep=nil;r.combatAnimationStart=nil;r.combatAnimationUntil=nil
        r.visualStepEpoch=nil;r.boardImpact=nil
    end
    r.fxReplayIndex=r.model.replay and r.model.replay.index
    if r.fxRevision==game.revision and not r.model.replay then return end
    local cards,players=Board.index(game)
    local deathTargets={}
    if r.oldBoardLife then
        for key,p in pairs(players)do
            local old=r.oldBoardLife[key]
            if old and p.life and p.life~=old then add(r,{kind=p.life>old and'life_gain'or'life_loss',targetId=key,amount=p.life-old})end
        end
        local grave={};for _,p in pairs(players)do for _,card in ipairs(list(p.graveyard))do grave[card.id]=true end end
        for key,old in pairs(r.oldBoardCards or{})do if grave[key]and not(r.oldBoardGrave or{})[key]then add(r,{kind='death',targetId=key,card=old});deathTargets[key]=true end end
        local before=r.oldStackIds or{}
        for _,stack in ipairs(list(game.stack))do if not before[stack.id]then add(r,{kind='cast',sourceId=stack.sourceId or stack.id,ownerId=stack.controllerId,card=stack.sourceCard})end end
        local current={};for _,stack in ipairs(list(game.stack))do current[stack.id]=true end
        for key,old in pairs(before)do if not current[key]then add(r,{kind='resolve',sourceId=old.sourceId or old.id,ownerId=old.controllerId})end end
    end
    local retainedEvents={}
    for _,event in ipairs(list(game.animationEvents))do
        local key=event.id or event.sequence
        if key then retainedEvents[key]=true end
        if key and not r.seenVisualEvents[key]then
            if event.type=='step'then r.visualStepEpoch=key end
            if r.oldBoardLife and event.type=='impact'and(event.commander==true or(tonumber(event.manaValue)or 0)>5)and not r.model.settings.reducedMotion and r.model.settings.animations~=false then
                local level=math.max(0,math.min(1,tonumber(r.model.settings.boardImpactIntensity)or .55))
                r.boardImpact={age=0,duration=.92,seed=hash(key),intensity=level*2*(event.commander and 1.15 or math.min(1.4,.8+(tonumber(event.manaValue)or 6)/20))}
                if r.sound then r:sound('table-impact')end
            end
            if r.oldBoardLife and event.type=='zone'and event.fromZone=='BATTLEFIELD'and event.toZone=='GRAVEYARD'and type(event.targetId)=='string'and not deathTargets[event.targetId]then
                add(r,{kind='death',targetId=event.targetId,card=(r.oldBoardCards or{})[event.targetId]or cards[event.targetId]});deathTargets[event.targetId]=true
            end
            if r.oldBoardLife and(event.type=='damage'or event.type=='dies'or event.type=='destroy')then
                add(r,{kind=event.type=='damage'and'damage'or'death',sourceId=event.sourceId,targetId=event.targetId,amount=event.amount,card=cards[event.targetId]})
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
    if r.model.settings.animations==false or r.model.settings.reducedMotion then return 0,0,0 end
    local scale=r.worldTransform and r.worldTransform.scale or 1
    local dx,dy,angle=0,0,0
    local motion=r.cardMotions and r.cardMotions[card.id]
    if motion and motion.age>=0 then
        local progress=math.sin(math.pi*math.min(1,motion.age/motion.duration));dx,dy=motion.dx*progress/scale,motion.dy*progress/scale
    end
    local e=r.boardImpact
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
            e.age=-(e.delay or 0);e.duration=(e.kind=='life_gain'or e.kind=='life_loss')and 1.7 or .65;e.x=at.x;e.y=at.y;e.from=from;e.target=target
            r.boardEffects[#r.boardEffects+1]=e
            if e.age>=0 then particles(r,e)end
        end
    end
    r.pendingBoardFX={}
end
local function line(r,a,b,c,dashed,outline,attack)
    if not a or not b then return end
    local dx,dy=b.x-a.x,b.y-a.y;local length=math.sqrt(dx*dx+dy*dy);if length<1 then return end
    local ux,uy=dx/length,dy/length
    local function stroke(color,width,tip)
        tint(color,.94);love.graphics.setLineWidth(width)
        if dashed then for distance=0,length,attack and 26 or 16 do local finish=math.min(length,distance+(attack and 18 or 10));love.graphics.line(a.x+ux*distance,a.y+uy*distance,a.x+ux*finish,a.y+uy*finish)end
        else love.graphics.line(a.x,a.y,b.x,b.y)end
        local tipX,tipY=b.x-ux*(tip*2),b.y-uy*(tip*2)
        love.graphics.polygon('fill',b.x,b.y,tipX-uy*tip,tipY+ux*tip,tipX+uy*tip,tipY-ux*tip)
    end
    if outline then stroke(outline,attack and 11 or 6.5,attack and 14 or 7.5)end
    stroke(c,attack and 6 or 2.5,attack and 10 or 4.5)
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
        line(r,a,b,Board.linkColor(index),true,Board.color(r,owner),true)
        for _,blocker in ipairs(list(group.blockerIds))do line(r,point(Board.anchor(r,blocker)),a,r.colors.gold,false)end
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
    local stackHits={};for _,hit in ipairs(r.model.stackHits or{})do stackHits[hit.id]=hit end
    local hovered=r.model.stackHover
    for index,item in ipairs(list(game.stack))do
        local start=point(stackHits[item.id])or point(Board.anchor(r,item.sourceId))
        local targets=item.targetIds or item.targets or{}
        for _,target in ipairs(list(targets))do
            local box=Board.anchor(r,id(target))
            if not hovered or hovered.id==item.id then line(r,start,point(box),Board.linkColor(index+#list((game.combat or{}).groups)),false,Board.color(r,item.controllerId))end
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
            local c=e.kind=='life_gain'and r.colors.accent or r.colors.red
            tint(c,alpha);r:strong((e.amount>0 and'+'or'')..tostring(e.amount),e.x-45,e.y-25-(moving and t*48 or 0),28,{c[1],c[2],c[3],alpha},90,'center')
        elseif e.kind=='damage'then
            line(r,e.from,e.target or{x=e.x,y=e.y},r.colors.red,false)
        elseif e.kind=='death'then
            tint(r.colors.red,alpha);love.graphics.setLineWidth(2)
            for i=1,7 do local a=i*math.pi*2/7;local d=8+(moving and t*42 or 0);love.graphics.rectangle('line',e.x+math.cos(a)*d,e.y+math.sin(a)*d,9*(1-t),13*(1-t),2,2)end
        elseif e.kind=='clash'or e.kind=='strike'then
            local at=e.from and e.target and{x=(e.from.x+e.target.x)/2,y=(e.from.y+e.target.y)/2}or{x=e.x,y=e.y}
            tint(r.colors.gold,alpha);love.graphics.setLineWidth(3);love.graphics.circle('line',at.x,at.y,7+t*34)
        end
        end
    end
    Dice.draw(r)
end
return Board
