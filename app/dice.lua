-- Animate only server-supplied results. Visual face cycling never chooses a winner.
local Dice={}
local function object(t)return type(t)=='table'and t or nil end
function Dice.update(r,dt)
    local game=r.model.game;local roll=game and object(game.openingRoll)
    local key=game and game.gameId
    if r.diceGame~=key then
        r.diceGame=key;r.diceOpening=nil
        if game and(tonumber(game.turn)or 0)<=1 and not r.model.replay and roll and roll.mode=='2d6'and type(roll.rounds)=='table'and#roll.rounds>0 then
            local roundSeconds=math.min(1.25,8.5/#roll.rounds)
            r.diceOpening={roll=roll,age=0,roundSeconds=roundSeconds,round=1,duration=#roll.rounds*roundSeconds+1.5}
            if r.sound then r:sound('dice-roll')end
        end
    end
    local current=r.diceOpening
    if current then
        current.age=current.age+dt
        local round=math.min(#current.roll.rounds,math.floor(current.age/current.roundSeconds)+1)
        if round~=current.round then current.round=round;current.landed=false;if r.sound then r:sound('dice-roll')end end
        if not current.landed and current.age-(round-1)*current.roundSeconds>=current.roundSeconds*.672 then current.landed=true;if r.sound then r:sound('dice-land')end end
        if current.age>=current.duration or r.model.replay then r.diceOpening=nil end
    end
end
function Dice.busy(r)return r.diceOpening~=nil and r.model.page=='table'end
function Dice.draw(r)
    local current=r.diceOpening;if not current or r.model.page~='table'or r.model.settingsOpen then return end
    local roll=current.roll;local reduced=r.model.settings.reducedMotion or r.model.settings.animations==false
    local roundIndex=math.min(#roll.rounds,math.floor(current.age/current.roundSeconds)+1)
    local round=roll.rounds[roundIndex];if not round or type(round.rolls)~='table'then return end
    local w,h=require('app.layout').dimensions();local width=math.min(w-60,680);local rows=#round.rolls
    local rowH=rows>6 and 44 or 56;local height=94+rows*rowH
    local x,y=(w-width)/2,math.max(62,(h-height)/2)
    love.graphics.push('all');love.graphics.setColor(.015,.025,.04,.78);love.graphics.rectangle('fill',0,0,w,h)
    r:panel(x,y,width,height,'dark');r:strong(roundIndex>1 and'Tied leaders · roll again'or'Starting player · 2d6',x+20,y+15,22,r.colors.gold,width-40,'center')
    local phase=current.age-(roundIndex-1)*current.roundSeconds;local spinning=not reduced and phase<current.roundSeconds*.672
    for i,result in ipairs(round.rolls)do
        local color=(r.playerColor and r:playerColor(result.playerId))or r.colors.accent
        local rowY=y+54+(i-1)*rowH;local size=rowH-12
        r:text(result.name or'Player',x+22,rowY+9,16,color,width-200)
        for d=1,2 do
            local final=result.dice[d];local face=spinning and(1+(math.floor(phase*22)+i*3+d*2)%6)or final
            local settle=spinning and math.max(0,1-phase/(current.roundSeconds*.672))or 0
            local angle=math.sin(phase*12+i+d)*settle*.65
            local hop=math.sin(math.min(1,phase/(current.roundSeconds*.672))*math.pi)*settle*10
            local dx=x+width-144+(d-1)*(size+10);local dy=rowY-hop
            love.graphics.push();love.graphics.translate(dx+size/2,dy+size/2);love.graphics.rotate(angle)
            r.assets:runtimeIcon('dice-'..face,-size/2,-size/2,size,color);love.graphics.pop()
        end
        if not spinning then r:strong(tostring(result.total),x+width-45,rowY+5,22,color,36,'center')end
    end
    local winner
    for _,player in ipairs((r.model.game or{}).players or{})do if player.id==roll.winnerId then winner=player.name end end
    local caption=spinning and'Rolling…'or roundIndex<#roll.rounds and'Tie · highest players roll again'or(winner or'Highest roller')..' goes first'
    r:text(caption,x+20,y+height-29,14,r.colors.text,width-40,'center')
    love.graphics.pop()
end
return Dice
