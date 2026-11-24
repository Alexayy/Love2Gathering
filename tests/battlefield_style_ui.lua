-- Real LÖVE rendering and production pointer routes; the card pack is the local art transport.
local json=require('lib.json')
local byName,byPrint,actions={},{},{}
local function copy(value)return json.decode(json.encode(value))end
package.preload['app.api']=function()
    local function request(_,service,method,path,body,callback)
        if service=='engine' and method=='POST' then actions[#actions+1]={path=path,body=copy(body)}
        elseif service=='art' and method=='GET' then
            local print=byPrint[path:match('[?&]printing=([^&]+)')]
            local file=print and print[path:match('[?&]kind=([^&]+)')]
            if file then callback(assert(love.filesystem.read((print.directory or 'printing-pack/')..file)),nil,200,nil,nil,{variant='original'})
            else callback(nil,'Missing fixture image',404) end
        end
        return true
    end
    return {escape=tostring,new=function()return {escape=tostring,request=request,routeGeneration=0,update=function()end,quit=function()end,setNativeSession=function()end}end}
end
package.preload['app.startup']=function()return {new=function()return {ready=true}end}end
local Slab=require('lib.Slab')
local Layout=require('app.layout')
local Cursor=require('lib.Slab.Internal.Core.Cursor')
local Window=require('lib.Slab.Internal.UI.Window')
local Model,Renderer,Preferences=require('app.model'),require('app.renderer'),require('app.preferences')
local model,renderer,preferences
local newModel,newRenderer,newPrefs=Model.new,Renderer.new,Preferences.new
function Model.new(...)
    model=newModel(...)
    model.settingsLoaded=true;model.loaded=true;model.profileLoaded=true;model.uiLayout={}
    local s=model.settings
    s.windowMode='Windowed';s.resolution='1440x900';s.uiScale=1;s.renderScale=1
    s.skybox='Off';s.showCardArt=true;s.localArtworkOnly=true;s.groupEquivalent=true
    s.animations=false;s.reducedMotion=true;s.particles=false;s.sfxEnabled=false;s.musicEnabled=false;s.vsync=false;s.autoFollowTurn=false
    return model
end
function Renderer.new(...)renderer=newRenderer(...);return renderer end
function Preferences.new(...)preferences=newPrefs(...);return preferences end
assert(love.filesystem.load('application-main.lua'))()
local app={load=love.load,update=love.update,draw=love.draw}
for _,name in ipairs({'mousemoved','mousepressed','mousereleased','keypressed','keyreleased'})do app[name]=love[name];love[name]=function()end end
local output=assert(os.getenv('L2G_STYLE_OUTPUT'))
local checks,shots,displays={}, {}, {}
local boxes,drawn,images={},{},{}
local faces,activeFace={}
local previewRows,activePreview={}
local faceBand
local opponentHands,activeOpponent={},nil
local privateArtReads=0
local function screenAngle()
    local x,y=love.graphics.transformPoint(0,0)
    local xx,yy=love.graphics.transformPoint(40,0)
    return math.atan2(yy-y,xx-x)
end
local function corners(x,y,w,h)
    local g=love.graphics
    return {{g.transformPoint(x,y)},{g.transformPoint(x+w,y)},{g.transformPoint(x+w,y+h)},{g.transformPoint(x,y+h)}}
end
local function visibleBounds(x,y,w,h)
    local points=corners(x,y,w,h)
    local left,top,right,bottom=math.huge,math.huge,-math.huge,-math.huge
    for _,p in ipairs(points) do
        left,top=math.min(left,p[1]),math.min(top,p[2])
        right,bottom=math.max(right,p[1]),math.max(bottom,p[2])
    end
    local cx,cy,cw,ch=love.graphics.getScissor()
    if cx then
        left,top=math.max(cx,left),math.max(cy,top)
        right,bottom=math.min(cx+cw,right),math.min(cy+ch,bottom)
    end
    return {left=left,top=top,right=right,bottom=bottom}
end
local function insideTile(points,hit)
    if not points then return false end
    local cos,sin=math.cos(hit.angle),math.sin(hit.angle)
    for _,p in ipairs(points)do
        local dx,dy=p[1]-hit.x-hit.w/2,p[2]-hit.y-hit.h/2
        if math.abs(dx*cos+dy*sin)>hit.w/2+1 or math.abs(-dx*sin+dy*cos)>hit.h/2+1 then return false end
    end
    return true
end
local mx,my,down=0,0,{}
local clock,wake,runner=0,0
local function wait(seconds)wake=clock+(seconds or .1);coroutine.yield()end
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('BATTLEFIELD PASS '..label);io.stdout:flush()end
local function move(x,y)
    local ox,oy=mx,my;mx,my=x*Layout.scale,y*Layout.scale
    app.mousemoved(mx,my,mx-ox,my-oy,false)
end
local function click(button)
    down[button]=true;app.mousepressed(mx,my,button,false,1);wait(.06)
    down[button]=nil;app.mousereleased(mx,my,button,false,1);wait(.08)
end
local function cardHit(id)
    for _,hit in ipairs(renderer.hits)do if hit.card and hit.card.id==id and (hit.kind=='permanent' or hit.kind=='hand') then return hit end end
    error('Missing individual table hit '..id)
end
local function point(id)
    local hit=cardHit(id);move(hit.x+hit.w*.5,hit.y+hit.h*.5);wait(.12)
    check(renderer.hover and renderer.hover.card and renderer.hover.card.id==id,'Pointer reaches exact '..id)
end
local function button(label)
    local b=assert(boxes[label],'Missing button '..label)
    move(b.x+b.w*.5,b.y+b.h*.5);wait(.08);click(1)
end
local function shot(file)
    love.graphics.captureScreenshot(function(data)
        local f=assert(io.open(output..'/'..file..'.png','wb'));local png=data:encode('png')
        f:write(png:getString());f:close();png:release();data:release()
    end)
    shots[#shots+1]=file..'.png';wait(.14)
end
-- Each battlefield/hand object has an independent identity even when the same printing repeats.
local strategies={
    {name='Rowan',life=17,creatures={'Scavenging Ooze','Llanowar Elves','Tarmogoyf'},lands={'Forest','Forest','Stomping Ground','Mountain'}},
    {name='Mira',life=14,creatures={'Goblin Guide','Monastery Swiftspear'},lands={'Mountain','Sacred Foundry','Mountain'}},
    {name='Vesper',life=24,creatures={'Blood Artist','Dusk Legion Zealot'},lands={'Swamp','Blood Crypt','Swamp'}},
    {name='Arden',life=21,creatures={'Serra Angel','Righteous Valkyrie'},lands={'Plains','Plains','Sacred Foundry'}}
}
local hands={'Lightning Bolt','Cultivate','Sakura-Tribe Elder','Forest','Scavenging Ooze'}
local creatures={
    ['Scavenging Ooze']={'{1}{G}','Ooze',2,2,'{G}: Exile target card from a graveyard. If it was a creature card, put a +1/+1 counter on this creature and you gain 1 life.'},
    ['Llanowar Elves']={'{G}','Elf Druid',1,1,'{T}: Add {G}.'},
    Tarmogoyf={'{1}{G}','Lhurgoyf',3,4},['Goblin Guide']={'{R}','Goblin Scout',2,2,'Haste'},
    ['Monastery Swiftspear']={'{R}','Human Monk',1,2,'Haste\nProwess'},
    ['Blood Artist']={'{1}{B}','Vampire',0,1},['Dusk Legion Zealot']={'{1}{B}','Vampire Soldier',1,1},
    ['Serra Angel']={'{3}{W}{W}','Angel',4,4,'Flying\nVigilance'},['Righteous Valkyrie']={'{2}{W}','Angel Cleric',2,4,'Flying'},
    ['Sakura-Tribe Elder']={'{1}{G}','Snake Shaman',1,1}
}
local lands={
    Forest='Basic Land — Forest',Mountain='Basic Land — Mountain',Plains='Basic Land — Plains',Swamp='Basic Land — Swamp',
    ['Stomping Ground']='Land — Mountain Forest',['Blood Crypt']='Land — Swamp Mountain',['Sacred Foundry']='Land — Mountain Plains'
}
local spells={
    ['Lightning Bolt']={'{R}','Instant','Lightning Bolt deals 3 damage to any target.'},
    Cultivate={'{2}{G}','Sorcery','Search your library for up to two basic land cards, reveal those cards, put one onto the battlefield tapped and the other into your hand, then shuffle.'}
}
local permanents={
    ['Sandwurm Convergence']={'{6}{G}{G}','Enchantment','Creatures with flying can’t attack you or planeswalkers you control.\nAt the beginning of your end step, create a 5/5 green Wurm creature token.'},
    Opalescence={'{2}{W}{W}','Enchantment','Each other non-Aura enchantment is a creature in addition to its other types and has base power and base toughness each equal to its mana value.'},
    ['Garruk Wildspeaker']={'{2}{G}{G}','Planeswalker','+1: Untap two target lands.'},
    ['Sol Ring']={'{1}','Artifact','{T}: Add {C}{C}.'},
    ['Invasion of Gobakhan']={'{1}{W}','Battle','Siege'}
}
local optionalPrints={
    ['Sandwurm Convergence']={id='18c3358a-96d2-4b7c-85e8-e641ef86cedc',oracle='429eff2b-635b-43f6-b20f-82e25992c0b9'},
    Opalescence={id='1a2f4972-8987-4349-953d-1e5c71368b08',oracle='59489b46-9d02-4f3c-bcd0-884e7605e9a5'},
    ['Invasion of Gobakhan']={id='11798730-6788-4e0b-a828-b46cab1a4fa7',oracle='86c32a56-3272-4738-b0b3-a8aa49a17ce4'}
}
local function card(name,id,owner,zone)
    local print=assert(byName[name],'Unavailable scan '..name)
    local c={id=id,name=name,selectedPrintingId=print.id,ownerId=owner,controllerId=owner,zone=zone,counters={},tapped=false}
    local creature,land,spell=creatures[name],lands[name],spells[name] or permanents[name]
    if creature then
        c.type='Creature';c.subtypes={};for subtype in creature[2]:gmatch('%S+')do c.subtypes[#c.subtypes+1]=subtype end
        c.type_line='Creature — '..creature[2];c.manaCost=creature[1];c.power=tostring(creature[3]);c.toughness=tostring(creature[4]);c.rules=creature[5]
        c.printing={name=name,type_line=c.type_line,power=c.power,toughness=c.toughness}
    elseif land then c.type='Land';c.type_line=land;c.manaCost='';c.supertypes=land:match('^Basic') and {'Basic'} or {}
    else
        c.manaCost,c.type,c.rules=unpack(spell);c.type_line=c.type
        c.printing={name=name,type_line=c.type}
    end
    c.currentRules=c.rules
    return c
end
local function scene(count,id)
    local players={}
    for seat=1,count do
        local spec=strategies[seat];local owner='seat-'..seat
        local player={id=owner,name=spec.name,seat=seat-1,human=seat==1,isLocal=seat==1,life=spec.life,battlefield={},hand={},handCount=4,libraryCount=49-seat,
            graveyard={},exile={},command={},mana={}}
        for i,name in ipairs(spec.creatures) do player.battlefield[#player.battlefield+1]=card(name,owner..'-creature-'..i,owner,'BATTLEFIELD') end
        for i,name in ipairs(spec.lands) do
            local c=card(name,owner..'-land-'..i,owner,'BATTLEFIELD');c.tapped=i==#spec.lands
            player.battlefield[#player.battlefield+1]=c
        end
        player.avatarCard=player.battlefield[1]
        if seat==1 then
            local ooze=player.battlefield[1];ooze.counters={['+1/+1']=2};ooze.power='4';ooze.toughness='4'
            for i,name in ipairs(hands) do player.hand[i]=card(name,'hand-'..i,owner,'HAND') end
            player.handCount=#player.hand
        end
        players[seat]=player
    end
    return {gameId=id,revision=1,running=true,turn=5,activePlayerId='seat-1',priorityPlayerId='seat-1',
        phase='Precombat Main',step='PRECOMBAT_MAIN',players=players,stack={},log={},localPlayerId='seat-1',
        prompt={id=51,type='select',priority=true,message='Choose a spell or ability',actionable={'hand-1','hand-2','seat-1-creature-1'},
            choices={{id='done',label='Pass',responseType='boolean',value=true}}},
        priority={canEndTurn=true,pending=false,autoPass=false,stops={own={},opponent={}}}}
end
local function update(frame,prompt)
    move(1,1);model:clearTablePreview();model:closeTableInspection()
    model.page='table';model.logOpen=false;model.stackOpen=false;model.actionBusy=false;model.answeredPrompt=nil
    if prompt then frame=copy(frame);frame.revision=frame.revision+1;frame.prompt=prompt end
    model:setGame(frame);wait(.2);return frame
end
local function payment()
    return {id=54,type='play_mana',message='Pay {2}{G} for Cultivate',pendingAction={kind='cast',sourceId='hand-2',canCancel=true},
        actionable={'seat-1-land-1','seat-1-land-2','seat-1-land-3'},choices={
            {id='mana-G',label='Pay {G} from pool (1)',responseType='mana',value='GREEN',manaCount=1,manaSymbol='G'},
            {id='seat-1-land-1',label='Forest',responseType='uuid'},
            {id='forest-one-green',sourceId='seat-1-land-1',label='{T}: Add {G}.',responseType='mana_source',manaColors={'G'}},
            {id='seat-1-land-2',label='Forest',responseType='uuid'},
            {id='forest-two-green',sourceId='seat-1-land-2',label='{T}: Add {G}.',responseType='mana_source',manaColors={'G'}},
            {id='seat-1-land-3',label='Stomping Ground',responseType='uuid'},
            {id='ground-red',sourceId='seat-1-land-3',label='{T}: Add {R}.',responseType='mana_source',manaColors={'R'}},
            {id='ground-green',sourceId='seat-1-land-3',label='{T}: Add {G}.',responseType='mana_source',manaColors={'G'}},
            {id='cancel',label='Cancel payment',responseType='boolean',value=true}}}
end
local function submitted(index,prompt,value,kind)
    local a=actions[index]
    local matched=#actions==index and a and a.path=='/session/action' and a.body.promptId==prompt.id and a.body.expectedGameId==model.game.gameId
        and a.body.type==kind and a.body.value==value
    if not matched then print('Action mismatch '..json.encode({sent=a,expected={index,prompt.id,value,kind},pointer={mx,my},hot=require('lib.Slab.Internal.UI.Region').GetHotInstanceId(),lock=renderer.view.inputLock,blocked=renderer:inputBlocked(),actions=#actions})) end
    return matched
end
local function publicHands(display)
    local w,h=Layout.dimensions()
    local before=#actions
    local function redacted(player,count)
        player.handCount=count
        -- Deliberately inconsistent with the count. This array must never
        -- supply a name, an image, a hit target, or an inferred public count.
        player.hand={{id='private-hand-'..player.id,name='Undisclosed hand card',hidden=true,zone='HAND'}}
    end
    local function expect(player,limit)
        local trace=assert(opponentHands[player.id],'No public hand render for '..player.id)
        local count=player.handCount
        local total=count and tostring(count) or '?'
        check(#trace.backs==math.min(count or 0,limit) and trace.labels[total],
            player.name..' shows '..total..' as the public count with the corresponding anonymous sleeves at '..display)
        for _,back in ipairs(trace.backs)do
            assert(back.left>=0 and back.right<=w and back.top>=0 and back.bottom<=h and
                back.right>back.left and back.bottom>back.top,'Opponent sleeve is not visible in the viewport')
        end
        check(not renderer.cardRects[player.hand[1].id] and not trace.interactive and not trace.requestedArt,
            player.name..' sleeves create no object, art request or click target at '..display)
        return trace
    end
    local duel=scene(2,'hidden-duel-'..display)
    -- Both are human players in a room; only the near seat belongs to this client.
    duel.players[2].human=true;duel.players[2].isLocal=false
    for _,count in ipairs({0,1,7,17})do
        redacted(duel.players[2],count);duel.revision=duel.revision+1;update(duel)
        local trace=expect(duel.players[2],9)
        if count==7 then
            shot('opponent-hand-duel-'..display)
            local sleeve=trace.backs[#trace.backs]
            move((sleeve.left+sleeve.right)/2,(sleeve.top+sleeve.bottom)/2);wait(.08);click(2);click(3)
            check(not model.inspectCard and not model:pinnedTableCard() and #actions==before,
                'Pointer gestures over a concealed opponent sleeve cannot inspect or select it at '..display)
        end
    end
    redacted(duel.players[2],nil);duel.revision=duel.revision+1;update(duel);expect(duel.players[2],9)
    local commander=scene(2,'hidden-commander-duel-'..display)
    commander.format='Commander';commander.commanderDamageEnabled=true
    commander.players[2].commanders={{id='krenko',name='Krenko, Mob Boss',commandZonePlays=1,deaths=1,additionalTax={manaCost='{2}'}}}
    redacted(commander.players[2],17);update(commander);expect(commander.players[2],5)
    local four=scene(4,'hidden-four-'..display)
    four.players[3].isHuman=true;four.players[3].bot=false
    for index,count in ipairs({1,7,17})do redacted(four.players[index+1],count)end
    update(four)
    for index=2,4 do expect(four.players[index],5) end
    check(not opponentHands[four.players[1].id] and cardHit('hand-1').card.name=='Lightning Bolt' and privateArtReads==0 and #actions==before,
        'Local faces remain interactive while the three other seats use only their independent public counts at '..display)
    shot('opponent-hands-four-players-'..display)
    local sleeve=opponentHands[four.players[4].id].backs[1]
    local x,y=Layout.toLogical((sleeve.left+sleeve.right)/2,(sleeve.top+sleeve.bottom)/2)
    move(x,y);wait(.12);click(1);click(2);click(3)
    check(renderer.tableCamera.mode=='overview' and not model.commanderDetails and not model.inspectCard and not model:pinnedTableCard() and #actions==before,
        'All three mouse buttons keep the multiplayer sleeve passive without choosing a seat or a card at '..display)
end
local function complexBoard(display)
    local frame=scene(2,'complex-field-'..display)
    local owner,foe=frame.players[1],frame.players[2]
    local function add(player,name,id)
        local item=card(name,id,player.id,'BATTLEFIELD')
        player.battlefield[#player.battlefield+1]=item
        return item
    end
    local convergence=add(owner,'Sandwurm Convergence','sandwurm')
    local garruk=add(owner,'Garruk Wildspeaker','garruk');garruk.counters.loyalty=5
    local ring=add(owner,'Sol Ring','ring')
    local invasion=add(foe,'Invasion of Gobakhan','invasion');invasion.counters.defense=2
    owner.battlefield[2].tapped=true
    frame=update(frame)
    local old=cardHit(convergence.id)
    check(old.battlefieldRole=='support' and cardHit(garruk.id).battlefieldRole=='walkers' and cardHit(ring.id).battlefieldRole=='support',
        'Unanimated enchantment, artifact and planeswalker occupy their current type groups at '..display)
    local labels=faces.sandwurm.labels
    local enchantmentLabel=false
    for label in pairs(labels) do if label:match('^Ench') then enchantmentLabel=true end end
    check(faces.sandwurm.types=='Enchantment' and enchantmentLabel and not labels['8/8'],'Unanimated Sandwurm displays its enchantment type without creature stats at '..display)
    local before=#actions
    point(convergence.id);click(2);move(1,1);wait(.12)
    local nextFrame=copy(frame);nextFrame.revision=frame.revision+1
    local nextOwner=nextFrame.players[1];local changed
    for _,item in ipairs(nextOwner.battlefield)do if item.id==convergence.id then changed=item end end
    changed.type='[Enchantment, Creature]';changed.power='8';changed.toughness='8'
    changed.keywords={'menace'};changed.printing.keywords={}
    add(nextFrame.players[2],'Opalescence','opalescence')
    model:setGame(nextFrame);wait(.18)
    local pin=model:pinnedTableCard()
    check(pin and pin.id==changed.id and pin.power=='8' and #actions==before,
        'Pinned Sandwurm follows the same object into its current 8/8 state without an action at '..display)
    model:clearTablePreview();move(1,1);wait(.1)
    local animated=cardHit(changed.id);local walker,artifact=cardHit(garruk.id),cardHit(ring.id)
    local land=cardHit('seat-1-land-3');local tappedLand=cardHit('seat-1-land-4');local elf=cardHit('seat-1-creature-2')
    check(animated.battlefieldRole=='creatures' and animated.y<artifact.y and walker.x<animated.x and artifact.x<land.x,
        'Animated Sandwurm moves forward, walker stays left of creatures and support stays left of lands at '..display)
    check(faces.sandwurm.types=='Enchantment Creature' and faces.sandwurm.labels['8/8'] and faces.opalescence.types=='Enchantment',
        'Terrain draws both current Sandwurm types and its 8/8 despite the enchantment-only printing at '..display)
    check(faces.garruk.labels['Loyalty 5'] and faces.invasion.labels['Defense 2'],
        'Face badges show current planeswalker loyalty and battle defense at '..display)
    local tapped,creature,untapped=faces[tappedLand.card.id],faces[elf.card.id],faces[land.card.id]
    check(tapped.shader and not creature.shader and not untapped.shader and tapped.tapSize>=12 and creature.tapSize>=20 and not untapped.tapSize,
        'Only the tapped noncreature land loses saturation and both tapped objects show tap symbols at '..display)
    local landTilt=math.abs(tappedLand.angle or 0)
    check(landTilt>=math.rad(12)-.001 and landTilt<=math.rad(15)+.001 and math.abs(landTilt-math.abs(elf.angle or 0))<.001,
        'Tapped land and creature retain their interactive tilted bounds at '..display)
    for _,band in ipairs({'header','footer'}) do
        local plate=tapped[band]
        check(plate and plate.textAngle and math.abs(plate.textAngle-tappedLand.angle)<.001
            and math.abs(plate.angle-tapped.artAngle)<.001 and insideTile(plate.points,tappedLand),
            'Tapped Mountain '..band..' text and black band rotate with the scan and stay inside its hit shape at '..display)
    end
    if optionalPrints['Sandwurm Convergence'].art_crop then
        check(faces.sandwurm.art=='Sandwurm Convergence:art_crop' and faces.invasion.art=='Invasion of Gobakhan:art_crop',
            'Animated permanent and battle retain their own original front illustrations at '..display)
    end
    shot('complex-battlefield-'..display)
    point(changed.id)
    local preview=renderer.tablePreviewRect
    check(preview and preview.card.id==changed.id and previewRows['Enchantment Creature'] and previewRows['Granted · Menace'] and previewRows['Native P/T 8/8'],
        'Full preview prints current types, 8/8 and granted Menace for the animated Sandwurm at '..display)
    if optionalPrints['Sandwurm Convergence'].normal then
        check(drawn['Sandwurm Convergence:normal'],'Hover draws the original full enchantment scan while showing current creature characteristics at '..display)
    end
    if display=='1440x900' then shot('animated-sandwurm-preview-'..display) end
    click(3)
    check(model.inspectCard and model.inspectCard.id==changed.id and model.inspectCard.selectedPrintingId==convergence.selectedPrintingId and #actions==before,
        'Middle-click still identifies the animated permanent and its original printing at '..display)
    button('Close details')
    local four=scene(4,'complex-four-'..display)
    four.players[1],four.players[2]=nextFrame.players[1],nextFrame.players[2]
    update(four)
    local remoteSupport,remoteLand=cardHit('invasion'),cardHit('seat-2-land-2')
    check(cardHit('sandwurm').battlefieldRole=='creatures' and cardHit('garruk').x<cardHit('sandwurm').x and
        remoteSupport.battlefieldRole=='support' and remoteSupport.x<remoteLand.x and remoteSupport.y<cardHit('seat-2-creature-1').y,
        'Four seats keep animated creatures and walkers forward, with opponent support left of its own lands at '..display)
    if display=='1440x900' then shot('four-player-complex-'..display) end
end
local function recordedPayment()
    if not love.filesystem.getInfo('duplicate-islands-before.json') then return false end
    local original=json.decode(assert(love.filesystem.read('duplicate-islands-before.json')))
    local paid=json.decode(assert(love.filesystem.read('duplicate-islands-after-tap.json')))
    local function islands(frame)
        local rows={}
        for _,player in ipairs(frame.players)do
            if player.human then for _,c in ipairs(player.battlefield)do if c.name=='Island' then rows[c.id]=c end end end
        end
        return rows
    end
    local prior,later=islands(original),islands(paid)
    local chosen,sibling
    for id,c in pairs(prior)do
        local after=assert(later[id])
        if not c.tapped and after.tapped then chosen=id elseif not c.tapped and not after.tapped then sibling=id end
    end
    assert(chosen and sibling,'Expected before/after captures with individually tapped native Islands')
    local before=#actions;update(original)
    while require('app.dice').busy(renderer) do wait(.1) end
    check(model:canSelect(chosen) and model:canSelect(sibling) and cardHit(chosen).x~=cardHit(sibling).x,'Native payment exposes the distinct offered UUIDs of both untapped Islands')
    check(boxes['Island (1)'] and boxes['Island (2)'],'Both native Islands have individual payment row labels')
    point(chosen);click(1)
    check(submitted(before+1,original.prompt,chosen,'uuid'),'Click sends only the Island UUID that tapped in the subsequent XMage projection')
    update(paid)
    check(not model:canSelect(chosen) and model:canSelect(sibling) and #actions==before+1,'Native update retires the tapped Island while keeping its exact sibling available')
    check(boxes['Island (1)'] and not boxes['Island (2)'],'The first Island keeps its ordinal after the second taps')
    return true
end
local function scenario()
    for _,mode in ipairs({{1440,900},{1120,720}})do
        local display=mode[1]..'x'..mode[2];model.settings.resolution=display;preferences:apply(true);wait(.12)
        local w,h=Layout.dimensions();displays[#displays+1]={width=w,height=h};local before=#actions
        local frame=update(scene(2,'style-duel-'..display))
        local ooze=cardHit('seat-1-creature-1');local land=cardHit('seat-1-land-3');local tapped=cardHit('seat-1-land-4')
        check(ooze.w>ooze.h and land.w/land.h>ooze.w/ooze.h,'Creatures and lands use distinct landscape proportions at '..display)
        check(drawn.courtyard,'The packaged courtyard texture covers the duel battlefield at '..display)
        check(drawn['Scavenging Ooze:art_crop'] and drawn['Stomping Ground:art_crop'] and drawn['Lightning Bolt:normal'],'Original creature and land crops and a complete hand scan reach the graphics draw at '..display)
        local first,last=cardHit('hand-1'),cardHit('hand-5')
        check(first.angle<0 and last.angle>0 and first.y~=cardHit('hand-3').y and first.h>first.w,'Hand scans arc and turn in opposite directions at '..display)
        check(ooze.card.counters['+1/+1']==2 and math.abs(tapped.angle)>.01 and land.y>ooze.y,'Tapped land, two native counters and distinct owner rows at '..display)
        shot('duel-'..display)
        point(ooze.card.id)
        local hover=renderer.tablePreviewRect
        if not hover then
            print('Missing hover at '..display..' '..json.encode({mouse={Layout.mouse()},hot=require('lib.Slab.Internal.UI.Region').GetHotInstanceId(),slab=renderer.uiHovered,lock=renderer.view.inputLock,stack=Window.GetStackDebug(),blocked=renderer:inputBlocked(true)}))
        end
        check(hover and hover.card.id==ooze.card.id and not model.inspectCard,'Battlefield hover previews the exact counter-bearing creature at '..display)
        if mode[1]==1440 then shot('duel-hover-'..display) end
        click(2);move(1,1);wait(.12);check(model:pinnedTableCard().id==ooze.card.id,'Right-click pins its scan at '..display)
        point(ooze.card.id);click(3);check(model.inspectCard and model.inspectCard.id==ooze.card.id and boxes['Close details'],'Middle-click opens its complete details at '..display)
        if mode[1]==1440 then shot('card-details-'..display) end
        button('Close details');check(#actions==before,'Inspecting and closing never sends a game action at '..display)
        local targets={'seat-1-land-1','seat-1-land-2'};local chosen=targets[2]
        local prompt={id=53,type='pick_target',message='Choose target land',actionable=targets,targets=targets,choices={{id=targets[1],responseType='uuid'},{id=chosen,responseType='uuid'}}}
        frame=update(frame,prompt)
        check(cardHit(targets[1]).x~=cardHit(chosen).x,'Both otherwise identical offered basic lands have separate targets at '..display)
        point(chosen);click(1)
        check(submitted(before+1,prompt,chosen,'uuid'),'Board target submits exactly the chosen second Forest once at '..display)
        before=#actions;prompt=payment();frame=update(frame,prompt)
        check(#actions==before,'Opening the manual payment panel leaves every source and pool untouched at '..display)
        check(boxes['Forest (1)'] and boxes['Forest (2)'],'Payment rows distinguish identical Forest sources at '..display)
        if mode[1]==1440 then shot('manual-mana-'..display) end
        point(chosen);click(1)
        check(submitted(before+1,prompt,chosen,'uuid'),'Manual payment can explicitly select the second Forest on the board at '..display)
        before=#actions;prompt=copy(prompt);prompt.id=55;frame=update(frame,prompt)
        button('{T}: Add {R}.')
        check(submitted(before+1,prompt,'ground-red','mana_source'),'Only the selected red Stomping Ground ability is sent at '..display)
        before=#actions;frame=update(scene(4,'style-multiplayer-'..display))
        for i=1,4 do
            local c=cardHit('seat-'..i..'-creature-1')
            check(c.w>c.h and c.y+c.h<=renderer.handBounds.y,'Four-seat overview keeps seat '..i..' landscape artwork above the hand at '..display)
        end
        check(#actions==before and renderer.tableCamera and renderer.multiplayerView,'Four-player overview opens without a native action at '..display)
        shot('four-player-'..display)
        complexBoard(display)
        publicHands(display)
    end
    local native=recordedPayment()
    local f=assert(io.open(output..'/report.json','w'));f:write(json.encode({checks=checks,displays=displays,screenshots=shots,actions=actions,nativeCaptureTested=native,scope='Production desktop callbacks and local Starter print scans on controlled game snapshots. Optional paired XMage projections verify native source identity.'}));f:close()
    print('BATTLEFIELD STYLE COMPLETE '..#checks..' checks');love.event.quit()
end
function love.load()
    local pack=assert(love.filesystem.newFileData('scans.zip'))
    assert(love.filesystem.mount(pack,'printing-pack'),'Cannot mount local Starter print scans')
    local manifest=json.decode(assert(love.filesystem.read('printing-pack/manifest.json')))
    for _,entry in ipairs(manifest.images)do
        if entry.face==0 then
            local print=byPrint[entry.printingId] or {name=entry.name,id=entry.printingId,oracle=entry.oracleId}
            print[entry.kind]=entry.path;byPrint[entry.printingId]=print
            if print.normal and print.art_crop and not byName[print.name] then byName[print.name]=print end
        end
    end
    for name,print in pairs(optionalPrints)do
        print.name=name;print.directory=''
        byName[name]=byName[name] or print;byPrint[print.id]=print
    end
    if love.filesystem.getInfo('extra-prints.json') then
        for _,entry in ipairs(json.decode(assert(love.filesystem.read('extra-prints.json'))))do
            optionalPrints[entry.name][entry.kind]=entry.path
        end
    end
    local newImage=love.graphics.newImage
    love.graphics.newImage=function(file,...)
        local img=newImage(file,...)
        if file=='assets/battlefield/courtyard.jpg' then images[img]='courtyard' end
        return img
    end
    app.load({})
    model.printingMetadata={}
    local function remember(name)
        local p=assert(byName[name],'Missing both scans for '..name)
        local data={id=p.oracle,printing_id=p.id,name=name,image_uris={}}
        if permanents[name] then data.mana_cost,data.type_line,data.oracle_text=unpack(permanents[name]) end
        if name=='Garruk Wildspeaker' then data.loyalty='3' end
        if name=='Invasion of Gobakhan' then data.defense='3' end
        -- Metadata for the specific Starter scan used in the inspection capture.
        if p.id=='0a91920a-7de3-4e9b-9cce-ff43ce0157b8' then
            data.set='m21';data.set_name='Core Set 2021';data.collector_number='318';data.artist='Sam Rowan'
            data.type_line='Creature — Ooze';data.oracle_text=creatures[name][5]
        end
        model:rememberCard(data);model.printingMetadata[p.id]={card=data}
    end
    for _,spec in ipairs(strategies)do for _,names in ipairs({spec.creatures,spec.lands})do for _,name in ipairs(names)do remember(name)end end end
    for _,name in ipairs(hands)do remember(name)end
    for name in pairs(permanents)do remember(name)end
    if love.filesystem.getInfo('duplicate-islands-before.json') then remember('Island');remember('Shivan Reef') end
    local art=model.getArt
    function model:getArt(card,force,kind,opts)
        if activeOpponent then activeOpponent.requestedArt=true end
        if card and (card.name=='Undisclosed hand card' or tostring(card.objectId or card.id):match('^private%-hand%-')) then privateArtReads=privateArtReads+1 end
        local image,status=art(self,card,force,kind,opts)
        if image then images[image]=card.name..':'..(kind or 'normal') end
        return image,status
    end
    local draw=love.graphics.draw
    love.graphics.draw=function(image,...)
        local source=images[image];if source then
            drawn[source]=true
            if activeFace and source:match(':art_crop$') then
                activeFace.art=source;activeFace.shader=love.graphics.getShader()~=nil
                activeFace.artAngle=screenAngle()
            end
        end
        return draw(image,...)
    end
    local drawPermanent=renderer.drawPermanent
    function renderer:drawPermanent(c,...)
        local previous=activeFace;activeFace={labels={}};faces[c.id]=activeFace
        drawPermanent(self,c,...);activeFace=previous
    end
    for _,method in ipairs({'text','strong'})do
        local drawText=renderer[method]
        renderer[method]=function(self,label,...)
            if activeOpponent then activeOpponent.labels[tostring(label)]=true end
            if activeFace then
                activeFace.labels[tostring(label)]=true
                if faceBand and activeFace[faceBand] then activeFace[faceBand].textAngle=screenAngle() end
            end
            return drawText(self,label,...)
        end
    end
    local hud=require('app.table_hud');local opponentHand=assert(hud.opponentHand,'Missing public hand renderer')
    hud.opponentHand=function(r,player,...)
        local old=activeOpponent;activeOpponent={backs={},labels={}};opponentHands[player.id]=activeOpponent
        local result=opponentHand(r,player,...)
        activeOpponent=old;return result
    end
    local back=renderer.assets.cardBack
    function renderer.assets:cardBack(x,y,w,h,...)
        local result=back(self,x,y,w,h,...)
        if result and activeOpponent then activeOpponent.backs[#activeOpponent.backs+1]=visibleBounds(x,y,w,h) end
        return result
    end
    local hit=renderer.hit
    function renderer:hit(box)
        if activeOpponent then activeOpponent.interactive=true end
        return hit(self,box)
    end
    local face=require('app.battlefield_face')
    for _,name in ipairs({'header','footer'}) do
        local render=face[name]
        face[name]=function(r,first,...)
            if name=='footer' and activeFace then activeFace.types=table.concat(first,' ') end
            faceBand=name;local result=render(r,first,...);faceBand=nil
            return result
        end
    end
    local rectangle=love.graphics.rectangle
    love.graphics.rectangle=function(mode,x,y,w,h,...)
        if activeFace and faceBand and not activeFace[faceBand] and mode=='fill' then
            local red,green,blue=love.graphics.getColor()
            if math.max(red,green,blue)<.15 then activeFace[faceBand]={points=corners(x,y,w,h),angle=screenAngle()} end
        end
        return rectangle(mode,x,y,w,h,...)
    end
    local preview=require('app.table_preview');local drawPreview=preview.draw
    preview.draw=function(r,c,...)
        activePreview=true;local result=drawPreview(r,c,...);activePreview=nil
        return result
    end
    local rich=require('app.richtext');local drawRich=rich.draw
    rich.draw=function(r,label,...)
        if activePreview then previewRows[label]=true end
        return drawRich(r,label,...)
    end
    local mana=renderer.assets.mana
    function renderer.assets:mana(symbol,x,y,size,...)
        if activeFace and symbol=='T' then activeFace.tapSize=size end
        return mana(self,symbol,x,y,size,...)
    end
    local oldButton=Slab.Button
    Slab.Button=function(label,opts)
        local result=oldButton(label,opts);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y)
        boxes[label]={x=x,y=y,w=w,h=h};return result
    end
    love.mouse.getPosition=function()return mx,my end;love.mouse.isDown=function(b)return down[b]==true end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    clock=clock+dt;assert(clock<75,'Battlefield style fixture deadline')
    boxes={};app.update(dt)
    if clock>=wake then local ok,message=coroutine.resume(runner);assert(ok,debug.traceback(runner,tostring(message)))end
end
function love.draw()drawn={};faces={};previewRows={};opponentHands={};app.draw()end
function love.errorhandler(message)io.stderr:write(debug.traceback(tostring(message),2)..'\n');return function()return 1 end end
