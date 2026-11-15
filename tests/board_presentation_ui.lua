-- Actual LÖVE/Slab presentation. The Angel projection is native; attachments,
-- native-style damage events, targets, life changes and extra seats below are
-- explicit UI fixtures. They do not establish first/double-strike card rules.
function love.errorhandler(message)io.stderr:write('BOARD PRESENTATION FAILED '..tostring(message)..'\n'..debug.traceback()..'\n');return function()return 1 end end
package.preload['app.api']=function()return{new=function()return{request=function()end,update=function()end,quit=function()end}end,escape=function(v)return tostring(v)end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Board=require('app.board_fx');local json=require('lib.json')
local m,r,v,prefs,runner,Cursor,Region;local elapsed,wake=0,0
local checks,shots,buttons,inputs,windows,ledger={},{},{},{},{},{bursts={},effects={},wheels={},links={},strong={},mana={}}
local mouse={x=1,y=1};local down,keys={},{};local native,angel,own,enemy;local images={};local activeCardDraw
local function clone(t)return json.decode(json.encode(t))end
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('BOARD PRESENTATION PASS '..label)end
local function wait(t)wake=elapsed+(t or .1);coroutine.yield()end
local function shot(name)shots[#shots+1]=name;wait(.15)end
local function move(x,y)local px,py=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;love.mousemoved(mouse.x,mouse.y,mouse.x-px,mouse.y-py,false)end
local function click(box,b)
    assert(box,'Expected presentation control is missing');move(box.x+box.w/2,box.y+box.h/2);wait(.05);down[b or 1]=true;love.mousepressed(mouse.x,mouse.y,b or 1,false,1);wait(.05);down[b or 1]=false;love.mousereleased(mouse.x,mouse.y,b or 1,false,1);wait(.15)
end
local function hit(kind,id)for _,item in ipairs(r.hits)do if item.kind==kind and(not id or(item.card or{}).id==id or item.playerId==id)then return item end end end
local function contains(items,field,value)for _,item in ipairs(items)do if item[field]==value then return item end end end
local function lastDraw(id,kind,noHit)
    for index=#(ledger.cardDraws or{}),1,-1 do local draw=ledger.cardDraws[index]
        if draw.id==id and draw.kind==kind and draw.noHit==noHit then return draw end
    end
end
local function stationary(draw)return draw and draw.presentedX and math.abs(draw.x-draw.presentedX)<.01 and math.abs(draw.y-draw.presentedY)<.01 end
local function segment(a,b)
    for _,line in ipairs(ledger.links)do if#line==4 and math.abs(line[1]-(a.x+a.w/2))<.01 and math.abs(line[2]-(a.y+a.h/2))<.01 and math.abs(line[3]-(b.x+b.w/2))<.01 and math.abs(line[4]-(b.y+b.h/2))<.01 then return true end end
    return false
end
local function card(id,name,kind)
    local result={id=id,name=name,type=kind or'Creature — Soldier',rules='Explicit synthetic presentation fixture.',colors={'W'}}
    if not kind then result.power='2';result.toughness='2'end
    return result
end
local function mode(w,h,scale)
    m.settings.resolution=w..'x'..h;m.settings.uiScale=scale or 1;m.settings.renderScale=1;m.settings.vsync=false;m.settings.windowMode='Windowed';prefs:apply(true)
end
local function scenario()
    mode(1440,900,1);m.page='table';m.logOpen=false;m.stackOpen=false;m:setGame(clone(native));wait(.2)
    own=m.game.players[1];enemy=m.game.players[2];angel=enemy.battlefield[1]
    check(angel.power=='5'and angel.toughness=='5'and angel.counters['+1/+1']==1,'Supplied native Angel projection contains actual 5/5 and +1/+1 counter')
    local data=m:cardData(angel);check(data.power=='5'and data.toughness=='5'and m.byName['Angel of Vitality'].power=='2','Native live power/toughness overrides static card metadata without mutating the catalog')
    local field=hit('permanent',angel.id)
    if not field then for _,entry in ipairs(r.hits)do print('BOARD HIT',entry.kind,entry.card and entry.card.name,entry.card and entry.card.id)end end
    assert(field,'Missing native Angel battlefield hit; page='..tostring(m.page)..' hits='..#r.hits);check(field.h>=150,'Native battlefield permanent retains the enlarged duel card dimensions')
    move(field.x+field.w/2,field.y+field.h/2);wait(.2);check(contains(ledger.strong,'text','5/5'),'Both battlefield and hover renderer present the native live 5/5 badge')
    check(contains(ledger.strong,'text','+1/+1')and contains(ledger.counters or{},'value',1),'Actual supplied dice badge shows the native count separately from its counter type and live power/toughness')
    check(contains(ledger.strong,'text',enemy.name),'Player names render through the bold text path')
    shot('native-angel-5-5')
    -- Explicit enrichment of the native frame for attachment/FX presentation.
    m.game.gameId='UI-ENRICHED-NATIVE-ANGEL';m.game.revision=m.game.revision+1
    local blocker=card('fixture-blocker','Fixture Soldier');own.battlefield={blocker};own.hand={card('fixture-cast-source','Angel of Vitality')};own.handCount=1
    own.graveyard={card('fixture-grave','Angel of Vitality')};own.exile={};own.libraryCount=46
    local aura=card('fixture-aura','Fixture Aura','Enchantment — Aura');aura.attachedToId=angel.id;enemy.battlefield[#enemy.battlefield+1]=aura
    local curse=card('fixture-curse','Fixture Curse','Enchantment — Aura Curse');curse.attachedToPlayerId=own.id;enemy.battlefield[#enemy.battlefield+1]=curse
    angel.linkedExile={card('fixture-linked','Fixture Linked Card','Instant')}
    m.game.priorityPlayerId=own.id;m.game.priorityStartedAt=(os.time()-65)*1000;wait(.25)
    check(hit('attachment',aura.id)and hit('attachment',curse.id)and hit('linked-exile','fixture-linked'),'Actual layered draws expose attached Aura, player Curse and linked exile hit regions')
    local gy;for _,item in ipairs(r.hits)do if item.kind=='zone'and item.label=='Graveyard'and#(item.cards or{})>0 then gy=item end end
    check(gy and gy.w>=100 and hit('pile')and hit('pile').w>=90,'Graveyard and library piles retain enlarged clickable geometry')
    check(contains(ledger.text or{},'text','1:05')or contains(ledger.text or{},'text','1:06'),'Priority badge displays elapsed time from the projected native start timestamp')
    field=assert(hit('permanent',angel.id));move(field.x+field.w/2,field.y+field.h/2);wait(.15);shot('attachments-curse-linked')
    local hand=assert(hit('hand','fixture-cast-source'));move(hand.x+hand.w/2,hand.y+20);wait(.35)
    check(hit('hand','fixture-cast-source').w>=190,'Actual hand hover expands the card to readable size');shot('enlarged-hand')
    move(20,120);wait(.2)
    m.game.stack={{id='fixture-stack',sourceId='fixture-cast-source',controllerId=own.id,sourceName='Angel of Vitality',sourceCard=clone(own.hand[1]),targetIds={angel.id},rules='Explicit UI target fixture'}}
    m.game.revision=m.game.revision+1;m.stackOpen=true;wait(.15)
    local cast=contains(r.boardEffects or{},'kind','cast');local anchor=Board.anchor(r,'fixture-cast-source')
    check(cast and anchor and math.abs(cast.x-(anchor.x+anchor.w/2))<2 and math.abs(cast.y-(anchor.y+anchor.h/2))<2,'Cast effect anchors to its actual source card rather than the table center')
    check(#ledger.links>0 and#(m.stackHits or{})==1,'Actual stack-target links draw from the visible stack item to its board target')
    check(segment(m.stackHits[1],Board.anchor(r,angel.id)),'Stack target line endpoints match the actual stack and permanent centers')
    shot('cast-and-target-link')
    local oldOwn,oldEnemy=own.life,enemy.life;own.life=oldOwn+5;enemy.life=oldEnemy-3;m.game.revision=m.game.revision+1;wait(.15)
    check(contains(r.boardEffects or{},'kind','life_gain')and contains(r.boardEffects or{},'kind','life_loss'),'Snapshot life changes produce distinct gain and loss effects')
    check(contains(ledger.strong,'text','+5')and contains(ledger.strong,'text','-3'),'Foreground renders signed life-change labels after the Slab batch');shot('life-gain-loss')
    m.game.stack={};m.stackOpen=false;m.settings.animations=true
    m.game.combat={groups={{attackerId=angel.id,defenderId=own.id,blockerIds={blocker.id},blocked=true}},step='FIRST_COMBAT_DAMAGE',sequence=1};m.game.step='FIRST_COMBAT_DAMAGE';m.game.animationEvents={};m.game.revision=m.game.revision+1;wait(.1)
    check(not r.cardMotions[angel.id]and not r.cardMotions[blocker.id],'A combat damage step name without native-style damage events invents no motion')
    -- Deliberately synthetic damage receipts model one source dealing damage
    -- in both phases. This is not an assertion about Angel's printed abilities.
    m.game.animationEvents={{id='fixture-first-damage',sequence=1,type='damage',nativeType='DAMAGED_PERMANENT',combat=true,sourceId=angel.id,targetId=blocker.id,amount=5,step='FIRST_COMBAT_DAMAGE'}}
    m.game.revision=m.game.revision+1;wait(.12)
    local firstMotion=r.cardMotions[angel.id]
    check(contains(r.boardEffects or{},'step','FIRST_COMBAT_DAMAGE')and firstMotion and not r.cardMotions[blocker.id],'Only the explicitly supplied first-phase damage source lunges; its normal blocker does not retaliate');shot('first-strike-step')
    check(segment(Board.anchor(r,blocker.id),Board.anchor(r,angel.id)),'Combat blocker line endpoints follow their actual moving card geometry')
    m.game.combat.step='COMBAT_DAMAGE';m.game.step='COMBAT_DAMAGE';m.game.revision=m.game.revision+1;wait(.04)
    check(not contains(r.boardEffects or{},'step','COMBAT_DAMAGE')and not r.cardMotions[blocker.id],'The normal damage step label also waits for actual supplied damage sources')
    m.game.animationEvents[2]={id='fixture-normal-blocker-damage',sequence=2,type='damage',nativeType='DAMAGED_PERMANENT',combat=true,sourceId=blocker.id,targetId=angel.id,amount=2,step='COMBAT_DAMAGE'}
    m.game.animationEvents[3]={id='fixture-normal-double-damage',sequence=3,type='damage',nativeType='DAMAGED_PERMANENT',combat=true,sourceId=angel.id,targetId=blocker.id,amount=5,step='COMBAT_DAMAGE'}
    m.game.revision=m.game.revision+1;wait(.60)
    check(contains(r.boardEffects or{},'step','COMBAT_DAMAGE')and r.cardMotions[angel.id]and r.cardMotions[angel.id]~=firstMotion and r.cardMotions[blocker.id],'Separate normal-phase source events start their own delayed motions after first-phase presentation');shot('normal-strike-step')
    m.settings.animations=false;check(Board.offset(r,angel)==0 and Board.offset(r,blocker)==0,'Motion checks restore the disabled-animation preference for the rest of the UI acceptance')
    -- Native-shaped damage and death arrive in one post-SBA snapshot. The same
    -- source now appears in a graveyard and a genuine Slab stack-hover preview.
    move(20,120);wait(.65);local originalBF=clone(assert(r.cardRects[blocker.id]));m.settings.animations=true
    own.battlefield={};own.graveyard[#own.graveyard+1]=blocker;m.game.combat.groups[1].blockerIds={}
    m.game.stack={{id='fixture-dead-source-stack',sourceId=blocker.id,controllerId=own.id,sourceName=blocker.name,sourceCard=clone(blocker),rules='Explicit synthetic dead-source hover fixture'}};m.stackOpen=true
    m.game.animationEvents[4]={id='fixture-death-step',sequence=4,type='step',step='COMBAT_DAMAGE'}
    m.game.animationEvents[5]={id='fixture-dying-source-hit',sequence=5,type='damage',nativeType='DAMAGED_PERMANENT',combat=true,sourceId=blocker.id,targetId=angel.id,amount=2,step='COMBAT_DAMAGE'}
    m.game.animationEvents[6]={id='fixture-source-died',sequence=6,type='zone',nativeType='ZONE_CHANGE',targetId=blocker.id,fromZone='BATTLEFIELD',toZone='GRAVEYARD',step='COMBAT_DAMAGE'}
    m.game.revision=m.game.revision+1;wait(.10)
    local death;for _,effect in ipairs(r.boardEffects or{})do if effect.kind=='death'and effect.targetId==blocker.id then death=effect end end
    local pile=assert(r.cardRects[blocker.id]);local originalX,originalY=originalBF.x+originalBF.w/2,originalBF.y+originalBF.h/2
    if not(death and math.abs(death.x-originalX)<.1 and math.abs(death.y-originalY)<.1)then print('DEATH ORIGIN DEBUG '..json.encode({death=death,original=originalBF,pile=pile,previous=r.previousCardRects[blocker.id]}))end
    check(death and math.abs(death.x-originalX)<.1 and math.abs(death.y-originalY)<.1 and math.abs(death.x-(pile.x+pile.w/2))>100,'Same-snapshot damage and death shatter at the previous battlefield location instead of the graveyard pile')
    check(r.cardMotions[blocker.id]and stationary(lastDraw(blocker.id,'pile',false)),'A dying source can retain native-style motion without displacing its graveyard representation')
    shots[#shots+1]='death-original-battlefield';wait(.08)
    local source=assert(m.stackHits and m.stackHits[1]);move(source.x+source.w/2,source.y+22);wait(.10)
    local preview=lastDraw(blocker.id,'card',true)
    check(m.stackHover and m.stackHover.id=='fixture-dead-source-stack'and preview and preview.w>=180 and stationary(preview)and r.cardMotions[blocker.id],'Actual stack-source hover preview ignores the dead permanent’s still-active motion')
    check(stationary(lastDraw(blocker.id,'pile',false)),'The graveyard pile stays fixed while the same native ID is inspected in a hover preview')
    shots[#shots+1]='death-stationary-hover';wait(.08);move(20,120);m.settings.animations=false;m.stackOpen=false;m.game.stack={}
    m.game.combat=nil;m.game.log={};for i=1,120 do m.game.log[i]={id='fixture-log-'..i,sequence=i,text='Fixture log line '..i..' · actual scrolling over the match log',category='system',actor='system'}end
    for i=3,4 do m.game.players[i]={id='extra-player-'..i,seat=i-1,name='Fixture Bot '..i,human=false,life=40,hand={},handCount=7,libraryCount=90,battlefield={},graveyard={},exile={},command={},mana={}}end
    m.game.gameId='FOUR-SEAT-SCROLL-FIXTURE';m.game.revision=m.game.revision+1;m.game.format='Commander';m.logOpen=true;m.uiLayoutVersion=(m.uiLayoutVersion or 0)+1;m.uiLayout={['floating-log']={x=.67,y=.20,w=.29,h=.24}};wait(.3)
    local log=assert(windows['floating-log']);move(log.x+log.w*.45,log.y+80);wait(.15)
    local before=r.tableCamera.zoom;local _,scrollBefore=Region.Transform('floating-log',0,0)
    love.wheelmoved(0,-4);wait(.2);local _,scrollAfter=Region.Transform('floating-log',0,0)
    check(ledger.wheels[#ledger.wheels].void==false and r.tableCamera.zoom==before,'Actual main-style wheel routing scrolls Slab log without zooming the battlefield')
    check(scrollAfter~=scrollBefore,'Actual Slab log content transform changes under the wheel')
    move(r.multiplayerView.x+200,r.multiplayerView.y+300);wait(.12);love.wheelmoved(0,1);wait(.15)
    check(ledger.wheels[#ledger.wheels].void and r.tableCamera.zoom>before,'Wheel over unobstructed terrain still zooms the camera');shot('four-seat-scroll-gating')
    m.page='lobby';m.logOpen=false;m.stackOpen=false;m.game=nil;m.format='Commander';m.playerDeckId=nil;m.botDeckId=nil;m.botDeckIds={};wait(.2)
    click(assert(buttons.yourDeck));check(v.deckSelection and not v.deckSelection.selected,'Empty lobby selection opens the real deck tile popup without choosing a default')
    check(buttons['Angel Sky']and buttons['Goblin Company']and not buttons['Modern Merfolk'],'Deck popup displays only the selected format')
    local tile=buttons['Angel Sky'].image;wait(.12);check(buttons['Angel Sky'].image==tile,'Unchanged deck tile reuses its artwork raster cache')
    check(ledger.mana.W and ledger.mana.R,'Deck tiles draw supplied Mana symbols from catalog color identities');shot('deck-tiles')
    local input=assert(inputs['deck-tile-search']);click(input);keys.lctrl=true;S.OnKeyPressed('a','a',false);keys.lctrl=nil;S.OnKeyReleased('a','a');S.OnTextInput('Goblin');wait(.15)
    check(buttons['Goblin Company']and not buttons['Angel Sky'],'Actual deck search filters the popup grid')
    local choice=buttons['Goblin Company'];move(choice.x+choice.w/2,choice.y+choice.h/2);wait(.03);down[1]=true;love.mousepressed(mouse.x,mouse.y,1,false,1);wait(.05);move(1390,30);wait(.05);down[1]=false;love.mousereleased(mouse.x,mouse.y,1,false,1);wait(.12)
    check(not m.playerDeckId and v.deckSelection,'Dragging off a tile does not accidentally select a deck')
    click(assert(buttons['Goblin Company']));check(m.playerDeckId=='goblin'and not v.deckSelection,'Actual deck tile click applies the selected deck');shot('lobby-selected-tile')
    mode(1120,720,1.25);m.page='table';m.game=clone(native);m.logOpen=false;m.stackOpen=false;wait(.2);shot('native-angel-1120')
    local report={passed=true,checks=checks,scope='Actual LÖVE/Slab presentation and input. Unmodified native Angel projection proves live 5/5/counter display; labeled attachment/target/life/native-style combat-damage events/extra-seat fixtures exercise presentation only, not card first/double-strike rules. Genuine cached JPEGs copied from isolated catalog. Wheel/hover callback follows main.lua routing.',nativeGameId=native.gameId,nativeAngel={power=angel.power,toughness=angel.toughness},wheelLedger=ledger.wheels,physical={love.graphics.getDimensions()},logical={Layout.dimensions()}}
    local file=assert(io.open('/tmp/love2gathering-board-presentation-ui-report.json','w'));file:write(json.encode(report));file:close();print('BOARD PRESENTATION COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
    native=json.decode(love.filesystem.read('native-angel.json'));local metadata=json.decode(love.filesystem.read('card-metadata.json'))
    for name,kinds in pairs(metadata.images)do images[name]={};for kind,file in pairs(kinds)do images[name][kind]=love.graphics.newImage(file)end end
    m=Model.new();m.settingsLoaded=true;m.uiLayout={};m.engineHealth={ready=true};m.catalogHealth={ready=false};m.settings.sfxEnabled=false;m.settings.particles=false;m.settings.animations=false;m.settings.showCardArt=true
    m.byName=metadata.cards;m.decks={{id='angel',name='Angel Sky',format='Commander',colorIdentity={'W'},coverCard='Angel of Vitality',main={},commander={{name='Giada, Font of Hope',count=1}},sideboard={}},{id='goblin',name='Goblin Company',format='Commander',colorIdentity={'R'},coverCard='Krenko, Mob Boss',main={},commander={{name='Krenko, Mob Boss',count=1}},sideboard={}},{id='modern',name='Modern Merfolk',format='Modern',colorIdentity={'U'},main={},commander={},sideboard={}}}
    function m:request()end;function m:getArt(card,force,kind)return images[card.name]and(images[card.name][kind or'normal']or images[card.name].normal)end
    r=Renderer.new(m);v=View.new(S,m,r);prefs=Preferences.new(m,S,r);v.preferences=prefs;prefs.appliedLoaded=true
    local drawCard=r.drawCard;function r:drawCard(c,x,y,w,h,options)
        local draw={id=c.id,x=x,y=y,w=w,h=h,kind=options and options.kind or'card',noHit=options and options.noHit==true or false};local parent=activeCardDraw;activeCardDraw=draw
        drawCard(self,c,x,y,w,h,options);activeCardDraw=parent;ledger.cardDraws=ledger.cardDraws or{};ledger.cardDraws[#ledger.cardDraws+1]=draw
    end
    local translate=love.graphics.translate;love.graphics.translate=function(x,y)
        if activeCardDraw and not activeCardDraw.presentedX then activeCardDraw.presentedX=x-activeCardDraw.w/2;activeCardDraw.presentedY=y-activeCardDraw.h/2 end
        return translate(x,y)
    end
    local strong=r.strong;function r:strong(text,...)ledger.strong[#ledger.strong+1]={text=tostring(text)};return strong(self,text,...)end
    local text=r.text;function r:text(value,...)ledger.text=ledger.text or{};ledger.text[#ledger.text+1]={text=tostring(value)};return text(self,value,...)end
    local burst=r.burst;function r:burst(kind,x,y,count)ledger.bursts[#ledger.bursts+1]={kind=kind,x=x,y=y};return burst(self,kind,x,y,count)end
    local mana=r.assets.mana;function r.assets:mana(symbol,...)if m.page=='lobby'then ledger.mana[symbol]=true end;return mana(self,symbol,...)end
    ledger.counters={};local badge=r.assets.counterBadge;function r.assets:counterBadge(value,...)ledger.counters[#ledger.counters+1]={value=value};return badge(self,value,...)end
    local buildingLinks=false;local links=Board.links;Board.links=function(renderer)buildingLinks=true;links(renderer);buildingLinks=false end
    local line=love.graphics.line;love.graphics.line=function(...)if buildingLinks then ledger.links[#ledger.links+1]={...}end;return line(...)end
    local window=v.window;function v:window(id,...)window(self,id,...);local x,y=S.GetWindowPosition();local w,h=S.GetWindowSize();windows[id]={x=x,y=y,w=w,h=h}end
    local button=S.Button;S.Button=function(label,options)local dx,dy=Region.Transform(nil,0,0);local result=button(label,options);local x,y,w,h=Cursor.GetItemBounds();buttons[label]={x=x+dx,y=y+dy,w=w,h=h,image=options and options.Image and options.Image.Image};return result end
    local input=S.Input;S.Input=function(id,options)local dx,dy=Region.Transform(nil,0,0);local result=input(id,options);local x,y,w,h=Cursor.GetItemBounds();inputs[id]={x=x+dx,y=y+dy,w=w,h=h};return result end
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(b)return down[b]or false end;love.keyboard.isDown=function(...)for _,key in ipairs({...})do if keys[key]then return true end end;return false end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    elapsed=elapsed+dt;assert(elapsed<55,'Board presentation acceptance exceeded its bound');prefs:update();S.Update(dt)
    if elapsed>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
    -- Match main.lua: snapshot/model mutations precede the renderer FX update.
    r:update(dt)
    buttons={};inputs={};v:build();r.uiHovered=not S.IsVoidHovered();r:mousemoved(Layout.mouse())
end
function love.draw()
    ledger.links={};ledger.cardDraws={};prefs:beginFrame();r:draw();prefs:endScene();S.Draw();love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();love.graphics.pop()
    if#shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)local file=assert(io.open('/tmp/love2gathering-board-presentation-'..name..'.png','wb'));file:write(data:encode('png'):getString());file:close()end)end
end
function love.mousepressed(x,y,b,t,c)S.OnMousePressed(x,y,b,t,c);if not m.settingsOpen and not m.zoneView and not m.inspectCard and S.IsVoidHovered()then r:mousepressed(x/Layout.scale,y/Layout.scale,b,c)end end
function love.mousereleased(x,y,b,t,c)S.OnMouseReleased(x,y,b,t,c);r:mousereleased(x/Layout.scale,y/Layout.scale,b)end
function love.mousemoved(x,y,dx,dy,t)S.OnMouseMoved(x,y,dx,dy,t);r:mousemoved(x/Layout.scale,y/Layout.scale)end
function love.wheelmoved(...)
    local empty=S.IsVoidHovered();ledger.wheels[#ledger.wheels+1]={void=empty,zoom=r.tableCamera and r.tableCamera.zoom};S.OnWheelMoved(...);r.uiHovered=not empty;if empty then r:wheelmoved(...)end
end
function love.quit()S.OnQuit()end
