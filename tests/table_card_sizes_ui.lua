-- Actual LÖVE drawing/hit testing; synthetic duel/multiplayer states, local JPEGs.
function love.errorhandler(error)
 io.stderr:write('CARD SIZES UI FAILED '..tostring(error)..'\n'..debug.traceback()..'\n');io.stderr:flush()
 return function()return 1 end
end
package.preload['app.api']=function()return{new=function()return{request=function()end,update=function()end,quit=function()end}end}end
local Model=require('app.model');local Renderer=require('app.renderer');local Layout=require('app.layout');local json=require('lib.json')
local m,r,runner,clock,wake,mouse,checks,shots,reports,landImage,spellImage
local function check(ok,label)assert(ok,label);checks=checks+1;print('CARD SIZES UI PASS '..label)end
local function wait(t)wake=clock+(t or .08);coroutine.yield()end
local function hit(id)
 for _,box in ipairs(r.hits)do if box.card and box.card.id==id then return box end end
end
local function fixture(count,lands)
 local players={}
 for i=1,count do
  local player={id='p'..i,name=i==1 and'Synthetic local player'or'Synthetic bot '..i,human=i==1,life=40,hand={},handCount=7,libraryCount=92,battlefield={},graveyard={},exile={},command={},mana={W=3}}
  for j=1,lands do player.battlefield[#player.battlefield+1]={id='p'..i..'-land-'..j,name='Plains',type='Land'}end
  player.battlefield[2].tapped=true
  for j=1,3 do player.battlefield[#player.battlefield+1]={id='p'..i..'-creature-'..j,name='Synthetic creature',type='Creature',power='2',toughness='2'}end
  for _,pair in ipairs({{'relic','[Artifact]'}, {'aura','[Enchantment]'}, {'walker','[Planeswalker]'}})do
   player.battlefield[#player.battlefield+1]={id='p'..i..'-'..pair[1],name=pair[1],type=pair[2]}
  end
  if i==1 then for j=1,7 do player.hand[j]={id='hand-'..j,name=j%2==0 and'Lightning Bolt'or'Plains',type=j%2==0 and'Instant'or'Land'}end end
  players[i]=player
 end
 return{gameId='SYNTHETIC-SIZES-'..count..'-'..lands,revision=1,turn=1,phase='Precombat Main',step='Precombat Main',activePlayerId='p1',players=players,stack={},log={}}
end
local function point(x,y)mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;r:mousemoved(x,y)end
local function scenario()
 for _,size in ipairs({{1120,720,1},{2560,1080,1},{2560,1080,1.25}})do
  love.window.setMode(size[1],size[2],{vsync=0,resizable=true});Layout.setScale(size[3])
  for _,count in ipairs({2,4,6})do
   m:setGame(fixture(count,7));r.cameraIdentity=nil;r.handBounds=nil;r.hover=nil;r.poses={};point(0,0);wait(.15)
   local w,h=Layout.dimensions();local name=size[1]..'-ui'..Layout.scale..'-seats'..count
   local hand=assert(hit('hand-4'));local resting=hand.w
   local first,last=assert(hit('hand-1')),assert(hit('hand-7'))
   check(first.angle<-.2 and last.angle>.2 and math.abs(hand.angle)<.001 and first.y>hand.y+10 and last.y>hand.y+10,
       'Actual fixed hand rotates outward along a symmetric arc')
   local own=assert(hit('p1-land-2'));local enemy=assert(hit('p2-land-2'))
   local front=assert(hit('p1-creature-2'));local farFront=assert(hit('p2-creature-2'))
   for i=1,count do
    local prefix='p'..i..'-'
    local support,land=assert(hit(prefix..'aura')),assert(hit(prefix..'land-1'))
    local walker,creature=assert(hit(prefix..'walker')),assert(hit(prefix..'creature-1'))
    check(support.battlefieldRole=='support' and land.battlefieldRole=='lands' and support.x+support.w<land.x,
        'Rear support and mana have separate projected targets for player '..i)
    check(walker.battlefieldRole=='walkers' and creature.battlefieldRole=='creatures' and walker.x+walker.w<creature.x,
        'Planeswalker strip clears the projected creature rank for player '..i)
   end
   local _,landHeight=Layout.rotatedSize(own.w,own.h,own.angle)
   local landTop=own.y+(own.h-landHeight)/2
   check(landTop>front.y+front.h and enemy.y+enemy.h/2<farFront.y+farFront.h/2,
       'Lands are behind both ranks of nonland permanents')
   check(landTop+landHeight<r.handBounds.y and math.abs(own.angle-math.rad(15))<.001,
       'The tilted mana source clears the resting fan, including the multiplayer overview')
   if count>2 then
    local bottomSeat=assert(hit('p'..count..'-land-3'))
    check(bottomSeat.y+bottomSeat.h<r.handBounds.y,'Last player’s rear land remains visible above the fixed fan')
   end
   check(resting>=95 and resting<=138,'Resting hand retains readable card sizes at '..w..'x'..h..' / '..count..' seats')
   check(hand.y>=0 and hand.y+hand.h<h and hand.x>=0 and hand.x+hand.w<=w,'Resting card remains fully inside the window')
   point(hand.x+hand.w/2,hand.y+25);wait(.12)
   hand=assert(hit('hand-4'));check(hand.w>resting and hand.y>=0,'Hover enlarges the focused card')
   check(math.abs(assert(hit('hand-3')).w-resting)<.01,'Neighboring cards keep their resting size')
   point(hand.x+hand.w/2,hand.y+10);wait(.1)
   check(r.handHoverIndex==4 and r.hover and r.hover.card.id=='hand-4','Upper portion of the raised card stays hovered and clickable')
   r:mousepressed(hand.x+hand.w/2,hand.y+hand.h/2,3,1);check(m.inspectCard and m.inspectCard.id=='hand-4','Middle-click opens details for the enlarged hand card');m.inspectCard=nil
   shots[#shots+1]=name..'-hover';wait(.08)
   point(0,0);wait(.12)
   if count>2 then
    r.tableCamera:focus(3,true);wait(.08)
    check(r.tableCamera.zoom>r.tableCamera.overviewZoom,'Seat focus enlarges the battlefield')
    local box=assert(hit('p1-creature-2'));local land=assert(hit('p1-land-2'))
    check(box.w>box.h and box.w/r.tableCamera.zoom>=116 and land.w>land.h and box.h>land.h,'Focused landscape permanents are readable and taller than rear lands')
    point(box.x+box.w/2,box.y+box.h/2);check(r.hover and r.hover.card.id==box.card.id,'World enlarged card is hit in projected coordinates')
    r:mousepressed(box.x+box.w/2,box.y+box.h/2,3,1);r:mousereleased(box.x+box.w/2,box.y+box.h/2,3)
    check(m.inspectCard and m.inspectCard.id==box.card.id,'World enlarged card middle-click preserves native object identity');m.inspectCard=nil
    local fixed=assert(hit('hand-4'));r.tableCamera:pan(100,50);wait(.08)
    local after=assert(hit('hand-4'));check(math.abs(fixed.x-after.x)<.01 and math.abs(fixed.y-after.y)<.01,'Panning terrain never moves the enlarged fixed hand')
   else
    local land=assert(r.cardRects['p1-land-7']);local creature=assert(r.cardRects['p1-creature-1']);local L=r.tableLayout
    check(land.y>=creature.y+creature.h+8-.01,'Duel card rows retain separation')
    check(land.y+land.h<=L.fieldBottom+.01,'Rear lands stay inside their allocated terrain above the hand')
   end
   if count>2 then r.tableCamera:focus(3,true);wait(.05)end
   local mana=assert(hit('p1-land-2'))
   m.game.prompt={type='play_mana',id=74,actionable={mana.card.id},choices={}};wait(.1)
   mana=assert(hit('p1-land-2'))
   local bw,bh=Layout.rotatedSize(mana.w,mana.h,mana.angle)
   local cx,cy=mana.x+mana.w/2,mana.y+mana.h/2
   check(cx+bw/2<Layout.manaDock(w),'Whole tilted mana source remains exposed beside the payment rail')
   local cos,sin=math.cos(mana.angle),math.sin(mana.angle)
   local dx,dy=-mana.w*.47,mana.h*.44
   local cornerX,cornerY=cx+dx*cos-dy*sin,cy+dx*sin+dy*cos
   point(cornerX,cornerY);wait(.08)
   check(cornerX<mana.x and r.hover and r.hover.card and r.hover.card.id==mana.card.id,
       'Visible corner beyond the old upright boundary selects the exact tilted mana source')
   point(mana.x+mana.w*.01,mana.y+mana.h*.01);wait(.03)
   check(not r.hover or r.hover.card~=mana.card,'Vacated corner of the old upright rectangle no longer intercepts clicks')
   point(cx+bw/2-.05,cy-bh/2+.05);wait(.03)
   check(not r.hover or r.hover.card~=mana.card,'Empty corner of the rotated silhouette is excluded from input')
   m.game.prompt=nil;point(0,0);wait(.03)
   shots[#shots+1]=name;wait(.1)
   reports[#reports+1]={name=name,actual={love.graphics.getDimensions()},logical={w,h},seats=count,handWidth=resting}
  end
 end
 love.window.setMode(1120,720,{vsync=0});Layout.setScale(1)
 local frame=fixture(2,24);local field=frame.players[1].battlefield
 for _,role in ipairs({'Artifact','Planeswalker'})do
  for i=1,8 do field[#field+1]={id=role..i,name=role..' '..i,type=role}end
 end
 local offered={'p1-land-12','Artifact4','Planeswalker4','p1-creature-2'}
 frame.prompt={id=816,type='pick_target',actionable=offered,choices={}}
 m:setGame(frame);m.stackOpen=false;point(0,0);wait(.14)
 local submissions={};m.answer=function(_,kind,id)submissions[#submissions+1]={kind=kind,id=id};return true end
 for i,id in ipairs(offered)do
  local box=assert(hit(id));local cx,cy
  -- Probe the visible part of this exact object in a crowded group.
  for j=1,16 do
   cx,cy=box.x+box.w*(j/18),box.y+box.h/2;point(cx,cy)
   if r.hover and r.hover.card==box.card then break end
  end
  r:mousepressed(cx,cy,1,1);r:mousereleased(cx,cy,1)
  check(submissions[i] and submissions[i].kind=='uuid' and submissions[i].id==id,
      'Crowded '..box.battlefieldRole..' lane directly submits its exact offered UUID')
 end
 local lane
 for _,box in ipairs(r.hits)do
  if box.kind=='zone' and box.playerId=='p1' and box.battlefieldRole=='support' then lane=box end
 end
 assert(lane)
 r:mousepressed(lane.x+lane.w/2,lane.y+lane.h/2,1,1)
 check(m.zoneView and #m.zoneView.cards==10 and m.zoneView.memberIds.Artifact4 and not m.zoneView.memberIds.Planeswalker4,
     'Crowded support browser exposes only the represented native permanents')
 m.zoneView=nil;point(0,0);shots[#shots+1]='crowded-role-targets';wait(.1)
 local file=assert(io.open('/tmp/love2gathering-table-card-sizes-ui.json','w'));file:write(json.encode({checks=checks,scope='Actual LÖVE images/hit regions; synthetic presentation fixtures, no native game or network',cases=reports}));file:close()
 print('CARD SIZES UI COMPLETE '..checks..' checks');love.event.quit(0)
end
function love.load()
 clock,wake,checks=0,0,0;mouse={x=0,y=0};shots={};reports={}
 love.mouse.getPosition=function()return mouse.x,mouse.y end
 m=Model.new();m.settings.animations=false;m.settings.reducedMotion=true;m.settings.particles=false;m.settings.sfxEnabled=false;m.settings.showTooltips=false;m.settings.autoFollowTurn=false;m.settings.skyboxBrightness=0;m.page='table'
 landImage=love.graphics.newImage('land.jpg');spellImage=love.graphics.newImage('spell.jpg')
 m.cardData=function(self,card)return card end;m.getArt=function(self,card)return card and card.type=='Land'and landImage or spellImage end;m.profileArt=function()end
 r=Renderer.new(m);runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<45,'Sizing fixture exceeded45seconds');r:update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,error=coroutine.resume(runner);assert(ok,error)end
 r:mousemoved(Layout.mouse())
end
function love.draw()
 love.graphics.push();love.graphics.scale(Layout.scale);r:draw();love.graphics.pop()
 if #shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)
  local out=assert(io.open('/tmp/love2gathering-table-card-sizes-'..name..'.png','wb'));out:write(data:encode('png'):getString());out:close()
 end)end
end
