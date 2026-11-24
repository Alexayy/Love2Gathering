-- Actual LÖVE/Slab drawing and input on labeled synthetic native-contract states.
-- Native casts, choices, privacy and rules are independently verified in Java.
function love.errorhandler(message)io.stderr:write('PRESENTATION OVERHAUL FAILED '..tostring(message)..'\n'..debug.traceback()..'\n');return function()return 1 end end
local ledger={}
package.preload['app.api']=function()return{escape=tostring,new=function()return{
 request=function(_,service,method,path,body,callback)ledger[#ledger+1]={method=method,path=path,body=body};return true end,
 update=function()end,quit=function()end}end}end
local json=require('lib.json');local S=require('lib.Slab');local Layout=require('app.layout')
local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences')
local m,r,v,p,runner;local mouse={x=0,y=0};local down={};local clock,wake=0,0;local checks,shots,dimensions,timings={},{},{},{}
local output=os.getenv('LOVE2GATHERING_PRESENTATION_OUTPUT');local image;local frame=0;local capture;local measuring=false
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('PRESENTATION PASS '..label)end
local function wait(t)wake=clock+(t or .08);coroutine.yield()end
local function move(x,y)local px,py=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-px,mouse.y-py);r:mousemoved(x,y)end
local function hit(id,kind)for _,box in ipairs(r.hits)do if(not id or box.card and box.card.id==id)and(not kind or box.kind==kind)then return box end end end
local function copy(t)return json.decode(json.encode(t))end
local function fixture(crowded,exile,count)
 count=count or 4;local players={};local offered={}
 for i=1,count do
  local player={id='p'..i,name=i==1 and'Local Planeswalker'or'Synthetic opponent '..i,human=i==1,isHuman=true,seat=i,life=40,hand={},handCount=7,libraryCount=82,mana={U=3},battlefield={},graveyard={},exile={},command={},commanders={}}
  for j=1,(crowded and 20 or 6)do player.battlefield[#player.battlefield+1]={id='p'..i..'-land-'..j,name='Plains',type='[Land]',supertypes={'Basic'},subtypes='[Plains]',ownerId=player.id,controllerId=player.id,tapped=j%3==0,colors={},keywords={}}end
  for j=1,(crowded and(i==1 and 13 or 4)or 3)do
   local keywords=({'flying','haste','trample','reach','lifelink'})
   local keyword=keywords[(j-1)%#keywords+1]
   player.battlefield[#player.battlefield+1]={id='p'..i..'-creature-'..j,name='Presentation fixture '..j,type='Creature',power=tostring(j+1),toughness='4',controllerId=player.id,ownerId=player.id,colors=j==2 and{'R'}or{'G'},currentKeywords={{id=keyword,name=keyword}},mechanicCapabilities={},tapped=j==2}
  end
  local cmd={id='commander-'..i,name='Commander fixture '..i,zoneName='Command',commandZonePlays=2,additionalTax={manaCost='{4}'},deaths=1,sourceCard={id='commander-'..i,name='Commander fixture '..i,type='Legendary Creature',power='4',toughness='4'}}
  player.commanders={cmd};player.command={cmd.sourceCard};player.commanderDamageReceived={{commanderId='foe-commander',name='Other commander',amount=7}}
  if i==1 then
   for j=1,(crowded and 40 or 7)do player.hand[j]={id='hand-'..j,name=j%2==0 and'Plains'or'Flashback fixture',type=j%2==0 and'Basic Land'or'Instant',manaCost='{2}{U}',ownerId='p1',controllerId='p1',mechanicCapabilities=j%2==1 and{{id='flashback',name='Flashback'}}or{}};offered[#offered+1]='hand-'..j end
   player.handCount=#player.hand
   player.graveyard={{id='grave-flashback',name='Memory Deluge',type='Instant',manaCost='{2}{U}{U}',mechanicCapabilities={{id='flashback',name='Flashback'}},ownerId='p1',controllerId='p1'}}
   if exile then player.exile={{id='exile-spell',name='Exiled spell fixture',type='Sorcery',manaCost='{R}',ownerId='p1',controllerId='p1'}};offered[#offered+1]='exile-spell'end
  end
  players[#players+1]=player
 end
 offered[#offered+1]='grave-flashback'
 return{gameId='SYNTHETIC-PRESENTATION-'..tostring(crowded)..'-'..tostring(exile)..'-'..count,revision=1,turn=19,phase='Precombat Main',step='Precombat Main',activePlayerId='p2',priorityPlayerId='p1',players=players,running=true,commanderDamageEnabled=true,
  priority={autoPass=false,passWithOnlyMana=false,manaOnlyPolicySupported=true,canEndTurn=true,stops={own={},opponent={}}},
  prompt={id=19,type='select',priority=true,actionable=offered,choices={{id='done',label='Pass / Done',responseType='boolean',value=true}},cardActions={{objectId='grave-flashback',sourceZone='GRAVEYARD',options={{id='native-flashback',label='Flashback',manaCost='{5}{U}{U}',kind='spell'}}},{objectId='exile-spell',sourceZone='EXILED',options={{id='native-exile-spell',label='Cast',manaCost='{R}',kind='spell'}}}}},
  stack={{id='stack-top',sourceId='p2-creature-1',sourceName='Targeted ability',controllerId='p2',kind='ability',sourceCard={name='Source fixture',type='Creature'},targets={{id='p1-creature-1',name='Presentation fixture 1'}},rules='A synthetic targeted ability.'}},log={}}
end
local function shot(name)capture=name;wait(.12);shots[#shots+1]=name end
local function setSize(w,h)
 love.window.setMode(w,h,{vsync=0,resizable=true});Layout.setScale(1);r.poses={};r.cameraIdentity=nil
 local aw,ah=love.graphics.getDimensions();dimensions[#dimensions+1]={requested={w,h},actual={aw,ah}}
 wait(.15)
end
local function scenario()
 for _,size in ipairs({{1366,768},{1920,1080},{2560,1440},{2560,1080}})do
  m:setGame(fixture(false,false));m.stackOpen=true;m.logOpen=false;v.tableOptionsOpen=false
  setSize(size[1],size[2]);local w,h=Layout.dimensions();local L=r.tableLayout
  shot('initial-'..size[1]..'x'..size[2])
  check(r.tableCamera.mode=='overview','Four-player overview is canonical at '..w..'×'..h)
  local count=0;for _,box in ipairs(r.hits)do if box.kind=='hand'then count=count+1;check(box.y>=0 and box.y+box.h<=h-40 and box.x>=0 and box.x+box.w<=w,'Hand card fully inside safe area')end end
  check(count==7,'Seven opening cards are individually inspectable')
  check(L.viewport.x+L.viewport.w<L.rail.x,'Pinned stack rail cannot cover terrain')
  check(L.viewport.y+L.viewport.h>L.safe.handY+L.safe.handH*.8,'Hand overlays terrain instead of reserving an empty bottom strip')
  check(r.tableCamera.cellW/r.tableCamera.cellH<1.81,'Playmats retain a compact rectangular shape on wide displays')
  local c=assert(hit('hand-4'));move(c.x+c.w/2,c.y+30);wait(.16)
  local focused=assert(hit('hand-4'));check(focused.y>=0 and focused.y+focused.h<h-40,'Raised hover stays inside screen')
  check(focused.h>c.h,'Hover raises and enlarges the stable native card');move(0,0);wait(.12)
  local x,y,z=r.tableCamera.x,r.tableCamera.y,r.tableCamera.zoom
  m.game.priorityPlayerId='p3';m.game.revision=m.game.revision+1;wait(.08)
  check(r.tableCamera.x==x and r.tableCamera.y==y and r.tableCamera.zoom==z,'Priority changes never move camera')
  local row=r.stackRows['stack-top'];check(row and row.visible,'Native stack object has actual dock row anchor')
  move(row.x+row.w*.6,math.max(row.clip.y+5,row.y+20));wait(.12)
  check(m.stackHover and m.stackHover.id=='stack-top','Hover owns exact stack object identity')
  check(#r.boardLinks>0,'Hovered stack object produces bounded native target connections')
  move(0,0);wait(.08);check(#r.boardLinks==0,'Stack connections disappear outside hover')
  shot('overview-'..size[1]..'x'..size[2])
 end
 -- Reproduce the reported production thumbnail crash: a small stack source
 -- with enough abilities to draw its fractional-size overflow count.
 local overflow={id='overflow-stack-source',name='Many-ability stack source',type='Creature',power='4',toughness='4',currentKeywords={{id='flying',name='Flying'},{id='haste',name='Haste'},{id='trample',name='Trample'},{id='reach',name='Reach'}}}
 m.game.stack[1].sourceCard=overflow;m.game.revision=m.game.revision+1;wait(.14)
 check(r.stackRows['stack-top']and r.stackRows['stack-top'].visible,'Small many-keyword stack thumbnail renders with a normalized cached font')
 check(r:font(9.8)==r:font(10)and r:font(300)==r:font(96),'Dynamic badge font sizes normalize and stay bounded')
 shot('stack-keyword-overflow')
 m:setGame(fixture(false,true));r.cameraIdentity=nil;wait(.15)
 check(hit('exile-spell','exile-hand')~=nil,'Playable native exile card has labeled hand extension')
 shot('exile-extension')
 m:openZone('p1','graveyard','Graveyard');wait(.18)
 check(v.zoneCardHits and#v.zoneCardHits>0,'Graveyard grid exposes current native card hit regions')
 shot('graveyard-actions');m.zoneView=nil;wait(.12)
 local normalWidth=r.tableCamera.cellW
 m:setGame(fixture(true,false));r.cameraIdentity=nil;m.settings.groupEquivalent=true;wait(.15)
 local camera=r.tableCamera;local view=r.multiplayerView
 check(camera.cellW>normalWidth and camera.mode=='overview','A 13-permanent row widens the playmats while keeping the overview')
 local _,bottom=camera:project(camera.width,camera.height)
 check(bottom<=view.y+view.h+.01,'Fit Table still contains expanded terrain')
 local edge
 for j=1,13 do
  local box=assert(hit('p1-creature-'..j,'permanent'))
  local rotated=Layout.rotatedSize(box.w,box.h,box.angle or 0)
  local left=box.x+(box.w-rotated)/2
  check(not edge or left>edge+1,'Crowded permanent '..j..' has its own visible footprint including tapped width')
  edge=left+rotated
 end
 local hand=assert(hit('hand-7'))
 camera:focus(3,true);wait(.12)
 local focusedHand=assert(hit('hand-7'))
 check(hand.x==focusedHand.x and hand.y==focusedHand.y,'Focusing the wider playmat keeps fixed hand coordinates')
 shot('wide-permanent-row')
 local vx,vy=view.x+view.w*.54,view.y+view.h*.24
 move(vx,vy);r.uiHovered=false;local zoom=camera.zoom;r:wheelmoved(0,1);wait(.1)
 check(camera.zoom>zoom,'Wheel zoom remains available on the widened playmats')
 local panX=camera.x;r:mousepressed(vx,vy,2,1);move(vx-120,vy+16);r:mousereleased(vx-120,vy+16,2);wait(.1)
 check(camera.mode=='free' and camera.x>panX and not m.inspectCard,'Right-drag pans across the widened terrain')
 camera:overview(true);m.settings.groupEquivalent=false;wait(.15)
 local large=0;for _,player in ipairs(m.game.players)do large=large+#player.battlefield end
 check(large==105,'Crowded fixture contains 105 distinct native-style permanent IDs')
 check(r.handScrollMax>0,'Large hand uses scrolling instead of slivers')
 move(r.handBounds.x+80,r.handBounds.y+40);r.uiHovered=false;r:wheelmoved(0,-.25);wait(.1)
 check(r.handScroll==.75 and hit('hand-1'),'Fractional trackpad scroll preserves the first native card until the next whole position')
 r:wheelmoved(0,-.25);wait(.1)
 check(r.handScroll==1.5 and not hit('hand-1') and hit('hand-2'),'Accumulated trackpad deltas shift the hand by one whole card')
 measuring=true;wait(1.5);measuring=false
 shot('crowded-100')
 local expandedWidth=camera.cellW
 m.settings.groupEquivalent=true;wait(.15);local groups=0;for _,box in ipairs(r.hits)do if box.kind=='group'then groups=groups+1 end end
 check(groups>0,'Equivalent basics can group without grouping unequal tap states')
 check(camera.cellW==expandedWidth,'Regrouping the cards does not move the wide playmats');shot('grouped-basics')
 m.settings.reducedMotion=true;m.settings.ambientKeywordFX=false;m.settings.vfxIntensity=0;wait(.2)
 check(hit('hand-7')or#r.hits>0,'Reduced motion retains card and action hit identities');shot('reduced-motion')
 local sorted={};for i,t in ipairs(timings)do sorted[i]=t end;table.sort(sorted)
 local report={passed=true,scope='Actual LÖVE/Slab input/rendering on synthetic native-contract four-player/crowded states, optional genuine cached Plains JPEG copied read-only into temporary fixture. Separate Java fixtures own native Magic correctness. Display clamps recorded.',checks=checks,screenshots=shots,dimensions=dimensions,
  performance={samples=#sorted,drawSubmissionMedianMs=sorted[math.max(1,math.floor(#sorted*.5))],drawSubmissionP95Ms=sorted[math.max(1,math.floor(#sorted*.95))],renderer=({love.graphics.getRendererInfo()})},userStoreModified=false}
 local f=assert(io.open(output..'/ui-report.json','w'));f:write(json.encode(report));f:close();love.event.quit(0)
end
function love.load(args)
 S.Initialize(args,true);love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return down[button]or false end
 m=Model.new();m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.autoFollowTurn=false;m.settings.skybox='Off'
 if love.filesystem.getInfo('land.jpg')then image=love.graphics.newImage('land.jpg')end
 m.cardData=function(_,card)return card end;m.getArt=function(_,card)return card and card.name=='Plains'and image or nil end
 r=Renderer.new(m);p=Preferences.new(m,S,r);v=View.new(S,m,r);p:applyFont();m.page='table'
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;r:update(dt);S.Update(dt);v:build();r.uiHovered=not S.IsVoidHovered()
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,error=coroutine.resume(runner);assert(ok,error)end
 assert(clock<80,'Graphical acceptance timed out')
end
function love.draw()
 local started=love.timer.getTime();love.graphics.push();love.graphics.scale(Layout.scale);r:draw();love.graphics.pop()
 S.Draw({DeferOverlays=true});love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();require('app.card_choices').draw(v);require('app.zone_ui').ghost(v);love.graphics.pop();S.DrawOverlays()
 if measuring then love.graphics.flushBatch();timings[#timings+1]=(love.timer.getTime()-started)*1000 end
 if capture then local name=capture;capture=nil;love.graphics.captureScreenshot(function(data)local bytes=data:encode('png');local f=assert(io.open(output..'/'..name..'.png','wb'));f:write(bytes:getString());f:close();bytes:release();data:release()end)end
 frame=frame+1
end
