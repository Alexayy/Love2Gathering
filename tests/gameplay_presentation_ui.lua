-- Actual LÖVE/Slab drawing/input with explicit synthetic public game states.
local requests={};package.preload['app.api']=function()return{escape=function(x)return tostring(x)end,new=function()return{catalogPort=17499,update=function()end,quit=function()end,request=function(_,service,method,path,body,callback)requests[#requests+1]={path=path,body=body};if path=='/session/start'then callback({gameId='intercepted',running=true,revision=1,players={}})end end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Layout=require('app.layout');local Preferences=require('app.preferences');local Board=require('app.board_fx');local Dice=require('app.dice');local json=require('lib.json')
local m,r,v,p,runner,Cursor,Region;local frame=0;local mouse={x=1,y=1};local down=false;local buttons,items,combos={},{},{};local checks,captures,geometry={},{},{};local shot
local function check(ok,message)assert(ok,message);checks[#checks+1]=message;print('GAME PRESENTATION UI PASS '..message)end
local function wait(count)for _=1,count or 3 do coroutine.yield()end end
local function move(box)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=(box.x+box.w/2)*Layout.scale,(box.y+box.h/2)*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy);r:mousemoved(mouse.x/Layout.scale,mouse.y/Layout.scale)end
local function click(box)assert(box,'Missing actual UI control');move(box);wait(2);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(2);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(4)end
local function capture(name)shot='/tmp/love2gathering-game-presentation-'..name..'.png';wait(3)end
local function card(id,name)return{id=id,name=name or id,type='Creature',manaCost='{2}{G}',power='3',toughness='3'}end
local function game()
 local h1,h2,b1,b2=card('h1','Grizzly Bears'),card('h2','Colossal Dreadmaw'),card('b1','Angel of Vitality'),card('b2','Giada, Font of Hope');h1.controllerId='human';h2.controllerId='human';b1.controllerId='bot';b2.controllerId='bot'
 return{gameId='opening-public-fixture',running=true,revision=1,format='Commander',turn=1,phase='COMBAT',step='DECLARE_BLOCKERS',activePlayerId='bot',players={{id='human',seat=0,human=true,name='Aleksa',life=40,hand={card('hand')},battlefield={h1,h2},libraryCount=94,handCount=1,graveyard={},exile={},command={}},{id='bot',seat=1,human=false,name='XMage Bot',life=40,hand={},handCount=6,battlefield={b1,b2},libraryCount=91,graveyard={},exile={},command={}}},stack={{id='trigger1',sourceId='b1',controllerId='bot',name='First public ability',rules='Target creature gets +1/+1.',targetIds={'h1'}},{id='trigger2',sourceId='b2',controllerId='bot',name='Second public ability',rules='Another public target.',targetIds={'h2'}}},combat={groups={{attackerId='b1',attackingPlayerId='bot',defenderId='human',blockerIds={}},{attackerId='b2',attackingPlayerId='bot',defenderId='human',blockerIds={}}}},openingRoll={mode='2d6',winnerId='bot',rounds={{rolls={{playerId='human',seat=0,name='Aleksa',dice={2,3},total=5},{playerId='bot',seat=1,name='XMage Bot',dice={5,6},total=11}},highest=11}},createdAt=0}}
end
local function scenario()
 wait(8);check(combos['practice-starting-player']and combos['practice-starting-player'].selected=='Roll 2d6','Practice lobby defaults to actual 2d6 selector')
 capture('lobby-1440')
 click(combos['practice-starting-player']);check(items['Bot 1 goes first']~=nil,'Actual starter dropdown offers existing bot seats');click(items['Bot 1 goes first']);check(m.practiceStartingSeatId=='bot-1','Actual starter selection chooses first bot')
 click(buttons['Start match']);local body=requests[#requests].body;check(body and body.startingSeatId=='bot-1','Actual Start sends selected practice seat to native request')
 m.page='lobby';m:setLobbyPlayers(6);m.practiceStartingSeatId='bot-5';wait(3);m:setLobbyPlayers(2);wait(3);check(m.practiceStartingSeatId=='dice','Removing a selected seat resets the lobby to 2d6')
 m.page='table';m.game=game();m.logOpen=false;m.stackOpen=false;m.settings.animations=true;m.settings.reducedMotion=false;wait(4)
 check(Dice.busy(r)and r.diceOpening.roll.winnerId=='bot','Displayed roll uses native-projected winner without generating a winner locally')
 capture('dice-rolling');wait(48);capture('dice-settled')
 check(r.diceOpening and r.diceOpening.roll.rounds[1].rolls[2].dice[2]==6,'Settled dice retain exact supplied d6 faces');wait(130)
 check(not Dice.busy(r),'Opening animation finishes and restores unobstructed game controls')
 local old=r.cardRects.h1;check(old~=nil,'Battlefield geometry is available for actual terrain checks')
 m.game.revision=2;m.game.animationEvents={{id='actual-native-shaped-impact',type='impact',sourceId='b2',playerId='bot',commander=true,manaValue=2}};wait(9)
 local dx,dy=Board.worldOffset(r);check(math.abs(dx)+math.abs(dy)>0,'Native-shaped resolution event animates actual terrain displacement')
 check(r.cardRects.h1 and r.cardRects.h1.angle~=r.cardRects.h2.angle,'Permanent cards draw independent rotation impulses')
 capture('impact-arrows-1440');wait(75);check(r.boardImpact==nil,'Actual board animation returns completely to rest')
 m.settings.reducedMotion=true;m.game.revision=3;m.game.animationEvents[2]={id='reduced-motion-impact',type='impact',sourceId='b2',commander=true,manaValue=2};wait(5);check(not r.boardImpact,'Reduced-motion setting prevents a new table impulse')
 m.settings.resolution='1120x720';m.settings.uiScale=1.25;p:apply(true);wait(8);capture('scaled-table-1120');geometry[#geometry+1]={physical={love.graphics.getDimensions()},logical={Layout.dimensions()},scale=Layout.scale}
 check(r.handBounds and r.handBounds.y+r.handBounds.h<=select(2,Layout.dimensions())+.1,'Fixed hand stays inside viewport after scaled terrain rendering')
 local report={passed=true,checks=checks,captures=captures,geometry=geometry,scope='Actual LÖVE/Slab lobby input, supplied dice rendering, public synthetic target/combat indicators and resolution-shaped animation. Native rules/dice/X-value behavior verified separately by StartingPresentationFixture. No user services or saves used.'}
 local f=assert(io.open('/tmp/love2gathering-gameplay-presentation-ui-report.json','w'));f:write(json.encode(report));f:close();print('GAME PRESENTATION UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.errorhandler(message)io.stderr:write('GAME PRESENTATION UI FAILED '..tostring(message)..'\n'..debug.traceback()..'\n');return function()return 1 end end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down or false end
 m=Model.new();m.decks={{id='commander-a',name='Ayara',format='Commander',main={},sideboard={},commander={}},{id='commander-b',name='Giada',format='Commander',main={},sideboard={},commander={}}};m:setLobbyFormat('Commander');m.engineHealth={ok=true};m.catalogHealth={ready=false};m.settings.showCardArt=false;m.settings.sfxEnabled=false;m.settings.resolution='1440x900';m.settings.windowMode='Windowed';m.settings.uiScale=1;m.settings.vsync=false
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p:apply(true);m.page='lobby'
 local original=S.Button;S.Button=function(label,options)local result=original(label,options);local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();buttons[label]={x=x+dx,y=y+dy,w=w,h=h};return result end
 local combo=S.BeginComboBox;S.BeginComboBox=function(id,options)local result=combo(id,options);local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();combos[id]={x=x+dx,y=y+dy,w=w,h=h,selected=options.Selected};return result end
 local selectable=S.TextSelectable;S.TextSelectable=function(label,options)local result=selectable(label,options);local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();items[label]={x=x+dx,y=y+dy,w=w,h=h};return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 frame=frame+1;S.Update(dt);r:update(1/60);v:build();r.uiHovered=not S.IsVoidHovered()
 local ok,err=coroutine.resume(runner);if not ok then error(err)end
 if frame>1000 then error('Game presentation fixture timed out')end
end
function love.draw()
 p:beginFrame();r:draw();p:endScene();S.Draw();love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();love.graphics.pop();p:endFrame()
 if shot then local name=shot;shot=nil;love.graphics.captureScreenshot(function(data)local f=assert(io.open(name,'wb'));f:write(data:encode('png'):getString());f:close();captures[#captures+1]=name end)end
end
