-- Consume actual prepared native outcome frames. Geometry here is synthetic.
local FX=require('app.mechanic_fx');local Board=require('app.board_fx');local json=require('lib.json')
local folder=assert(arg[1],'Pass the native MechanicCauseFixture output folder; this test never silently substitutes synthetic events')
local count=0
local function check(value,label)assert(value,label);count=count+1;print('NATIVE FX PASS '..label)end
local function read(name)local f=assert(io.open(folder..'/'..name..'.json'));local raw=f:read('*a');f:close();return json.decode(raw)end
local function scene(beforeName,afterName)
    local before,after=read(beforeName),read(afterName);local d=FX.newDirector();local current,previous,players,zones,rows={},{},{},{},{}
    local function geometry(game,boxes)
        for pi,p in ipairs(game.players)do
            players[p.id]={x=20,y=30+pi*300,w=100,h=80};zones[p.id]={}
            for zi,zone in ipairs({'graveyard','exile','library','hand','command'})do zones[p.id][zone]={x=1650+zi*30,y=pi*300,w=80,h=100}end
            for ci,card in ipairs(p.battlefield or{})do boxes[card.id]={x=180+ci*110,y=pi*300,w=100,h=140}end
        end
        for i,item in ipairs(game.stack)do rows[item.id]={x=1300,y=90+i*100,w=220,h=80,visible=true}end
    end
    geometry(before,previous);rows={};geometry(after,current)
    FX.observe(d,before,Board.index(before),before.gameId);FX.observe(d,after,Board.index(after),after.gameId)
    FX.flush(d,function(id)return current[id]or players[id]or rows[id]end,previous,players,zones,zones,rows,after.stack)
    return d,after,current,players,rows
end
local function effects(d,op,mechanic)
    local out={};for _,e in ipairs(d.events)do if e.operation==op and(not mechanic or e.profile and e.profile.id==mechanic)then out[#out+1]=e end end;return out
end
local evo=scene('evoke-before','evoke-cast');local cast=effects(evo,'cast','evoke');check(#cast==1,'Actual accepted Evoke cost reaches the named transient cast recipe')
check(cast[1].fromZone=='HAND'and cast[1].from and cast[1].to and cast[1].from.x~=cast[1].to.x,'Actual stack UUID and original card UUID preserve the native hand-to-stack origin')
local sacrifice=scene('evoke-entered','evoke-complete');check(#effects(sacrifice,'sacrifice','evoke')==1,'Actual later Evoke sacrifice reaches a separate material treatment')
check(#effects(sacrifice,'entry')==0,'Resolving Evoke sacrifice never invents another arrival')
local extort=scene('extort-trigger','extort-complete');local lost,gained=effects(extort,'life_loss','extort'),effects(extort,'life_gain','extort')
check(#lost==1 and# gained==1,'Actual paid Extort provides both named native transfer outcomes')
check(lost[1].from and lost[1].to and lost[1].from.y~=lost[1].to.y,'Actual Extort loss travels from victim to its real source')
check(gained[1].from and gained[1].to and gained[1].from.x~=gained[1].to.x,'Actual Extort gain travels from its source toward its controller frame')
local convoke,_,_,_,stackRows=scene('convoke-before','convoke-cast');local contributors=effects(convoke,'tap','convoke')
check(#contributors==5,'Five actually accepted Convoke contributors reach five distinct strands')
local row;for _,r in pairs(stackRows)do row=r end
local unique={};for _,e in ipairs(contributors)do unique[e.targetId]=true;check(e.from and e.to and e.to.x==row.x+row.w/2 and e.from.x~=e.to.x,'Accepted contributor strand ends at the exact real native spell row')end
local n=0;for _ in pairs(unique)do n=n+1 end;check(n==5,'Convoke never borrows an unselected contributor')
local mutate=scene('mutate-before','mutate-complete');check(#effects(mutate,'merge')==1 and#effects(mutate,'entry')==0,'Actual native Mutate uses one merge with no arrival slam')
local face=scene('morph-face-down','morph-face-up');check(#effects(face,'face_up')==1 and#effects(face,'entry')==0,'Actual native face-up unfolds a shell without a new entry')
local haste,_,boxes=scene('haste-before','haste-attacking');local attacks=effects(haste,'attack','haste');check(#attacks==1,'Actual declared Haste attack reaches its current-native-trait accent')
local attacker=boxes[attacks[1].sourceId];check(attacks[1].to.x==attacker.x+attacker.w/2,'Actual Haste streak is anchored to the attacking object')
local reach=scene('haste-attacking','reach-blocking');check(#effects(reach,'block','reach')==1,'Actual accepted Reach interception uses the real blocking source')
local trample=scene('trample-before','trample-complete');local damage=effects(trample,'damage','trample');local amount=0;for _,e in ipairs(damage)do amount=amount+e.amount end
check(#damage==2 and amount==6,'Actual Trample accents only the exact two positive native combat damage outcomes')
print('Actual native mechanic director: '..count..' checks passed (synthetic geometry only)')
