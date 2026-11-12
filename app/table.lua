local Layout=require('app.layout')
local Table={}
local function land(c) return tostring(c.type_line or c.type or ''):lower():find('land',1,true)~=nil end
local phases={{'Upkeep','UPKEEP'},{'Draw','DRAW'},{'Main 1','PRECOMBAT'},{'Combat','COMBAT'},{'Main 2','POSTCOMBAT'},{'End','END'}}
local function activePhase(game,key)
    local value=(tostring(game.step)..' '..tostring(game.phase)):upper():gsub(' ','_')
    if key=='COMBAT' then return value:find('COMBAT',1,true) and not value:find('PRECOMBAT',1,true) and not value:find('POSTCOMBAT',1,true) end
    return value:find(key,1,true)~=nil
end
function Table.players(game)
    local human,bot
    for _,p in ipairs(game.players or {}) do if p.human then human=p else bot=p end end
    return human,bot
end
function Table.field(r,player,x,y,w,rowH,foe)
    local C=r.colors;local lands,permanents={},{}
    for _,card in ipairs(player.battlefield or {}) do local group=land(card) and lands or permanents;group[#group+1]=card end
    local _,height=Layout.dimensions();local available=math.max(58,rowH-14)
    local landH=math.min(128,math.max(66,height*.12),available)
    local permanentH=math.min(157,available)
    if #lands>0 and #permanents>0 then
        landH=math.min(landH,(available-12)/2)
        permanentH=math.min(157,available-landH-12)
    end
    local function drawRow(cards,cardH,rowY,mana)
        if #cards==0 then return end
        local cardW=cardH/1.4
        local rows=Layout.cardRow(#cards,x,rowY,w,cardW,cardH,mana)
        for i,card in ipairs(cards) do local box=rows[i];r:drawCard(card,box.x,box.y,box.w,box.h,{kind='permanent',animate=true}) end
        local first=rows[1];r.assets:iconSymbol(mana and 'land' or 'creature',first.x-28,rowY+cardH/2-10,20,C.muted)
        r:hit({x=first.x-30,y=rowY+cardH/2-15,w=25,h=30,tooltip=mana and 'Mana sources' or 'Battlefield'})
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
function Table.hand(r,player,layout,w,h)
    local cards=player.hand or {};local n=#cards;local board=layout.board
    local cw=math.min(182,layout.handH/1.4,(board.w-190)/math.max(1,math.min(n,5)));local ch=cw*1.4
    local spacing=math.min(cw*.68,(board.w-260-cw)/math.max(1,n-1));local start=board.x+(board.w-(n-1)*spacing-cw)/2
    local hoverIndex=r.hover and r.hover.kind=='hand' and r.hover.index
    for i,c in ipairs(cards) do
        local normal=n<=1 and 0 or (i-1)/(n-1)-.5;local angle=normal*math.min(.45,n*.055)
        local y=h-ch-30+math.abs(normal)*13
        if i~=hoverIndex then r:drawCard(c,start+(i-1)*spacing,y,cw,ch,{angle=angle,kind='hand',index=i,animate=true}) end
    end
    if hoverIndex and cards[hoverIndex] then r:drawCard(cards[hoverIndex],start+(hoverIndex-1)*spacing,h-ch-67,cw,ch,{kind='hand',index=hoverIndex,animate=true}) end
    r:text(n..' cards in hand',board.x+board.w/2-100,h-23,13,r.colors.muted,200,'center')
end
function Table.draw(r,w,h)
    local m=r.model;local game=m.game;if not game then return end
    local L=Layout.table(w,h);r.tableLayout=L;local B=L.board;local C=r.colors
    local human,enemy=Table.players(game)
    r:panel(B.x,B.y,B.w,B.h,'dark')
    love.graphics.setColor(C.accent[1],C.accent[2],C.accent[3],.05)
    love.graphics.circle('line',B.x+B.w/2,B.y+B.h*.48,math.min(220,B.w*.24))
    local yours=human and game.activePlayerId==human.id
    r:text('TURN '..tostring(game.turn or 1),B.x+20,B.y+13,14,C.muted)
    r:text(yours and 'YOUR TURN' or (game.phase=='' and 'OPENING HAND' or 'BOT TURN'),B.x+122,B.y+7,28,yours and C.accent or C.purple)
    local phase=game.step and game.step~='null' and game.step or 'Pregame'
    local phaseX=B.x+B.w*.39;local phaseW=math.max(100,w-392-phaseX)
    r:text(phase,phaseX,B.y+15,22,C.text,phaseW,'center')
    r.phaseMarkers=r.phaseMarkers or ((m.uiLayout or {}).matchPrefs or {}).phaseMarkers or {}
    local chipW=(B.w-40-5*7)/6
    for i,item in ipairs(phases) do
        local label=item[1];local mark=r.phaseMarkers[item[2]]
        if mark then label=label..' · '..mark end
        r:button(label,B.x+20+(i-1)*(chipW+7),L.phaseY,chipW,36,function()
            local current=r.phaseMarkers[item[2]]
            r.phaseMarkers[item[2]]=not current and 'WAIT' or current=='WAIT' and 'SKIP' or nil
            m:setUIOption('phaseMarkers',r.phaseMarkers)
        end,activePhase(game,item[2]))
    end
    r:text('Phase markers: click to mark WAIT / SKIP · preview only',B.x+20,L.phaseY+41,11,C.muted)
    if human and enemy then
        local hx=B.x+20;local right=B.x+B.w-L.zoneW-18
        r:text(r:fit(enemy.name or 'XMage Bot',122,16,1),hx,140,16,C.text,122)
        r:text(enemy.life, hx,165,36,C.purple)
        r:hit({x=hx,y=140,w=112,h=75,kind='player',card={id=enemy.id,name=enemy.name}})
        local backs=math.min(enemy.handCount or 0,16);local ew=math.min(87,(B.w-320)/math.max(1,math.min(backs,7)));local eh=ew*1.4
        local es=math.min(ew*.55,(B.w-340-ew)/math.max(1,backs-1));local start=B.x+(B.w-(backs-1)*es-ew)/2
        for i=1,backs do r:drawCard({},start+(i-1)*es,124,ew,eh,{back=true,noHit=true}) end
        Table.field(r,enemy,L.fieldX,L.enemyY,L.fieldW,L.rowH,true)
        Table.field(r,human,L.fieldX,L.humanY,L.fieldW,L.rowH,false)
        love.graphics.setColor(C.line);love.graphics.line(L.fieldX,L.divider,B.x+B.w-132,L.divider)
        local zoneW=L.zoneW;local zoneH=zoneW*1.4+34
        local enemyZone=math.max(330,L.enemyY+5);local ownZone=math.max(enemyZone+zoneH+15,L.humanY+10)
        local enemyLibrary=250;local humanLibrary=math.max(enemyLibrary+zoneH+14,L.humanY-10)
        Table.pile(r,'Library',enemy.libraryCount,nil,hx,enemyLibrary,zoneW,true)
        Table.pile(r,'Library',human.libraryCount,nil,hx,humanLibrary,zoneW,true)
        local playerY=math.max(h-L.handH-15,humanLibrary+zoneW*1.4+40)
        r:text(r:fit(human.name or 'You',112,16,1),hx,playerY,16,C.text)
        r:text(human.life,hx,playerY+22,36,C.accent)
        r:hit({x=hx,y=playerY,w=112,h=76,kind='player',card={id=human.id,name=human.name}})
        -- Graveyard/exile share a large clickable zone at shorter window heights.
        Table.pile(r,'Graveyard',nil,enemy.graveyard,right,enemyZone,zoneW)
        Table.pile(r,'Graveyard',nil,human.graveyard,right,ownZone,zoneW)
        local exileY=ownZone+zoneH+14
        if exileY+zoneH<h-98 then
            Table.pile(r,'Exile',nil,human.exile,right,exileY,zoneW)
        else
            r:button('Exile '..#(human.exile or {}),right,ownZone+zoneW*1.4+37,zoneW,30,function() m.zoneView={label='Your exile',cards=human.exile or {}} end)
        end
        r:button('Exile '..#(enemy.exile or {}),right,enemyZone-39,zoneW,30,function() m.zoneView={label='Opponent exile',cards=enemy.exile or {}} end)
        if h<840 and #(human.command or {})>0 then
            local command=human.command
            r:button('Commander',hx,h-49,103,32,function() m.zoneView={label='Your command zone',cards=command} end,m:canSelect(command[1].id))
        else for i,c in ipairs(human.command or {}) do r:drawCard(c,hx+(i-1)*78,h-127,76,106,{kind='command',animate=true}) end end
        for i,c in ipairs(enemy.command or {}) do r:drawCard(c,L.fieldX+(i-1)*78,127,76,106,{kind='command',animate=true}) end
        local manaEntries={}
        for _,symbol in ipairs({'W','U','B','R','G','C'}) do local amount=(human.mana or {})[symbol] or 0;if amount>0 then manaEntries[#manaEntries+1]={symbol=symbol,amount=amount} end end
        local mx=B.x+(B.w-#manaEntries*42)/2;local my=h-L.handH-54
        for _,entry in ipairs(manaEntries) do r.assets:mana(entry.symbol,mx,my,20);r:text(entry.amount,mx+23,my+1,14,C.text);mx=mx+42 end
        Table.hand(r,human,L,w,h)
    end
    if type(game.error)=='string' then r:text(game.error,L.fieldX,L.divider,16,C.red,L.fieldW) end
    if game.running==false then
        local x=B.x+B.w/2-235;local y=h/2-70
        r:panel(x,y,470,131,'accent');r:text('MATCH ENDED',x+20,y+21,28,C.accent,430,'center')
        r:text(human and (human.won and 'Victory' or human.lost and 'Defeat') or 'See the match log',x+20,y+73,22,C.text,430,'center')
    end
    local prompt=m:prompt()
    if prompt and prompt.type=='order' then r:drawOrdering(w,h,prompt) end
    if prompt and prompt.manaWheel then Table.manaWheel(r,w,h,prompt) end
    if prompt and prompt.type=='select' then
        require('app.richtext').draw(r,prompt.message or '',B.x+20,214,math.min(440,B.w*.35),{size=13,color=C.muted,maxLines=1})
    end
    if m.replay then r:text('REPLAY · VIEW ONLY',B.x+20,B.y+48,12,C.gold) end
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
