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
  for j=1,3 do player.battlefield[#player.battlefield+1]={id='p'..i..'-creature-'..j,name='Synthetic creature',type='Creature',power='2',toughness='2'}end
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
   check(math.abs(resting-math.min(104,math.max(84,w*.073))*1.05)<.01,'Resting hand grows5percent at actual '..w..'x'..h..' / '..count..' seats')
   check(hand.y<h and hand.x>=0 and hand.x+hand.w<=w,'Resting hand remains visible and horizontally bounded')
   point(hand.x+hand.w/2,hand.y+25);wait(.12)
   hand=assert(hit('hand-4'));check(math.abs(hand.w-math.min(206,w*.16)*1.05)<.01,'Hover uses the uniformly enlarged card')
   check(math.abs(assert(hit('hand-3')).w-146*1.05)<.01,'Expanded neighboring hand cards also grow5percent')
   point(hand.x+hand.w/2,hand.y+hand.h/2);check(r.hover and r.hover.card.id=='hand-4','Hover hit follows actual enlarged ink')
   r:mousepressed(hand.x+hand.w/2,hand.y+hand.h/2,2,1);check(m.inspectCard and m.inspectCard.id=='hand-4','Right-click inspects the enlarged hand card');m.inspectCard=nil
   shots[#shots+1]=name..'-hover';wait(.08)
   point(0,0);wait(.12)
   if count>2 then
    r.tableCamera:focus(3,true);wait(.08)
    check(r.tableCamera.zoom==1,'Card growth does not change the camera zoom')
    local box=assert(hit('p1-creature-2'));check(math.abs(box.h-196*1.21)<.01,'World battlefield card grows10percent')
    point(box.x+box.w/2,box.y+box.h/2);check(r.hover and r.hover.card.id==box.card.id,'World enlarged card is hit in projected coordinates')
    r:mousepressed(box.x+box.w/2,box.y+box.h/2,2,1);r:mousereleased(box.x+box.w/2,box.y+box.h/2,2)
    check(m.inspectCard and m.inspectCard.id==box.card.id,'World enlarged card right-click preserves native object identity');m.inspectCard=nil
    local fixed=assert(hit('hand-4'));r.tableCamera:pan(100,50);wait(.08)
    local after=assert(hit('hand-4'));check(math.abs(fixed.x-after.x)<.01 and math.abs(fixed.y-after.y)<.01,'Panning terrain never moves the enlarged fixed hand')
   else
    local land=assert(r.cardRects['p1-land-7']);local creature=assert(r.cardRects['p1-creature-1']);local L=Layout.table(w,h)
    check(land.y>=creature.y+creature.h+12-.01,'Duel card rows retain separation')
    check(land.y+land.h+6<=L.fieldBottom-8+.01,'Mana pool clears enlarged duel lands')
   end
   shots[#shots+1]=name;wait(.1)
   reports[#reports+1]={name=name,actual={love.graphics.getDimensions()},logical={w,h},seats=count,handWidth=resting}
  end
 end
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
