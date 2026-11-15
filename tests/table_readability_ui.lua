-- Actual LÖVE drawing/hit testing; synthetic duel/multiplayer states, local JPEGs.
function love.errorhandler(error)
 io.stderr:write('TABLE READABILITY UI FAILED '..tostring(error)..'\n'..debug.traceback()..'\n');io.stderr:flush()
 return function()return 1 end
end
package.preload['app.api']=function()return{new=function()return{request=function()end,update=function()end,quit=function()end}end}end
local Model=require('app.model');local Renderer=require('app.renderer');local Layout=require('app.layout');local json=require('lib.json')
local m,r,runner,clock,wake,mouse,checks,shots,reports,landImage,spellImage
local ink,answers,artRequests={}, {}, {}
local P=require('app.card_presentation')
local function drawn(text)for _,entry in ipairs(ink)do if entry.text==text then return entry end end end
local function lastDrawn(text)for i=#ink,1,-1 do if ink[i].text==text then return ink[i]end end end
local function check(ok,label)assert(ok,label);checks=checks+1;print('TABLE READABILITY UI PASS '..label)end
local function wait(t)wake=clock+(t or .08);coroutine.yield()end
local function hit(id)
 for _,box in ipairs(r.hits)do if box.card and box.card.id==id then return box end end
end
local function fixture(count,lands)
 local players={}
 for i=1,count do
  local player={id='p'..i,name=i==1 and'Synthetic local player'or'Synthetic bot '..i,human=i==1,life=40,hand={},handCount=7,libraryCount=92,battlefield={},graveyard={},exile={},command={},mana={W=3},commanderDamageReceived={{name='First commander',amount=6},{name='Second commander',amount=4}}}
  for j=1,lands do player.battlefield[#player.battlefield+1]={id='p'..i..'-land-'..j,name='Plains',type='Land'}end
  for j=1,3 do player.battlefield[#player.battlefield+1]={id='p'..i..'-creature-'..j,name='Synthetic creature',type='Creature',power=j==1 and'3'or'2',toughness=j==1 and'3'or'2',damage=j==1 and 1 or 0,keywords={'flying'},counters={['+1/+1']=1}}end
  if i==1 then player.command={{id='commander',name='Native commander fixture',type='Creature',power='3',toughness='3'}};player.commanders={{id='commander',commandZonePlays=2,deaths=7,additionalTax={manaCost='{4}',otherCosts={}}}};for j=1,7 do player.hand[j]={id='hand-'..j,name=j%2==0 and'Lightning Bolt'or'Plains',type=j%2==0 and'Instant'or'Land'}end end
  players[i]=player
 end
 return{gameId='SYNTHETIC-SIZES-'..count..'-'..lands,revision=1,turn=1,phase='Precombat Main',step='Precombat Main',activePlayerId='p1',players=players,stack={},log={},commanderDamageEnabled=true}
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
   local power,defense=drawn('3/'),drawn('2');check(power and defense and defense.size>=16 and defense.tint[1]>defense.tint[2]*1.5 and power.tint[2]>.8,'Damaged defense alone is red and larger while power stays white')
   check(m.game.players[1].battlefield[8].toughness=='3'and m.game.players[1].battlefield[8].damage==1,'Displayedremainingdefense never changes native toughness or marked damage')
   check(drawn('C2 D7')~=nil,'Native command-cast and independent death counts render on commander')
   check(drawn('Max commander damage: 6')~=nil,'Duel/world header visibly tracks the highest single-commander damage rather than the6+4total')
   local details;for _,entry in ipairs(r.hits)do if entry.commanderDetails and entry.card.id=='p1'then details=entry.tooltip end end
   check(details and details:find('First commander · 6 damage received',1,true)and details:find('Second commander · 4 damage received',1,true),'Header hover details retain every actual commander ledger entry')
   if count==2 then
    local command=assert(hit('commander'));check(math.abs(command.w-83.6)<.01,'Duelcommandcard grows10percent')
    for j=1,3 do local permanent=assert(hit('p1-creature-'..j));check(permanent.x>=command.x+command.w,'Owncommander has reserved space beside actual permanent hitboxes')end
   end
   local prompt={id=100+count,type='select',priority=true,actionable={'p1-creature-1','p1-creature-2','p1-creature-3'},choices={}}
   m.game.prompt=prompt;m.game.priority={canEndTurn=true};m.answeredPrompt=nil
   local previous=#answers
   for j=1,3 do local box=assert(hit('p1-creature-'..j));local x,y=box.x+box.w/2,box.y+box.h/2;point(x,y);r:mousepressed(x,y,1,1);r:mousereleased(x,y,1)end
   check(#answers==previous+3 and answers[previous+1].value=='p1-creature-1'and answers[previous+2].value=='p1-creature-2'and answers[previous+3].value=='p1-creature-3','Each actual visible attacker hit routes its own offered native UUID')
   r.view={cardChoiceModal='select-card'};local box=assert(hit('p1-creature-1'));r:mousepressed(box.x+box.w/2,box.y+box.h/2,1,1);r:mousereleased(box.x+box.w/2,box.y+box.h/2,1)
   check(#answers==previous+3,'Active native choice modal blocks background battlefield actions');r.view=nil
   m.game.prompt=nil
   local cursorCalls=0;local originalCursor=love.mouse.setCursor;love.mouse.setCursor=function(...)cursorCalls=cursorCalls+1;return originalCursor(...)end
   m.activityState=function()return{kind='images',label='Loading hand images',busy=true,elapsed=1.2}end
   shots[#shots+1]=name..'-busy';wait(.08)
   check(cursorCalls==0,'Busy spinner draws without switching the underlying hand or text cursor');love.mouse.setCursor=originalCursor;m.activityState=function()end
   shots[#shots+1]=name;wait(.1)
   reports[#reports+1]={name=name,actual={love.graphics.getDimensions()},logical={w,h},seats=count,handWidth=resting}
  end
 end
 m:setGame(fixture(4,7));r.cameraIdentity=nil;point(0,0);wait(.15)
 r.boardEffects={{kind='life_gain',ownerId='p1',targetId='p1',amount=3,x=330,y=230,age=0,duration=1.7,spawned=true},
  {kind='damage',ownerId='p2',amount=2,x=520,y=230,from={x=430,y=230},target={x=520,y=230},age=0,duration=1.25,spawned=true}}
 shots[#shots+1]='outlined-life-and-damage';wait(.1)
 local gain,burn=lastDrawn('+3'),lastDrawn('−2')
 check(gain and gain.size==44 and gain.tint[2]>gain.tint[1]*2,'Life gain is larger green display text')
 check(burn and burn.size==36 and burn.tint[1]>burn.tint[2]*2,'Native damage amount is larger red display text')
 local gainOutline,burnOutline=drawn('+3'),drawn('−2');local human=r:playerColor('p1');local bot=r:playerColor('p2')
 check(gainOutline.tint[1]==human[1]and gainOutline.tint[2]==human[2]and burnOutline.tint[1]==bot[1]and burnOutline.tint[2]==bot[2],'Large gain and burn numbers retain the affected/source player outlines')
 r.boardEffects={}
 local publicFrame=fixture(4,7);publicFrame.commanderDamageEnabled=false;local publicBack=publicFrame.players[1].battlefield[9]
 publicBack.hidden=true;publicBack.faceDown=true;publicBack.name=nil;publicBack.printing=nil;publicBack.keywords={'flying'};publicBack.counters={charge=2};publicBack.attacking=true
 m:setGame(publicFrame);r.cameraIdentity=nil;point(0,0);wait(.15)
 check(drawn('charge')~=nil and drawn('2/2')~=nil,'An anonymous native face-down battlefield back keeps its public counter name and actual P/T')
 check(not publicBack.faceDownIdentity and not publicBack.name,'Drawing public face-down overlays never manufactures a hidden identity')
 check(drawn('Commander damage disabled')~=nil,'A disabled native commander damage option stays visibly disabled in the player header')
 r:drawCard({hidden=true,faceDown=true,power='9',toughness='9',counters={secret=1}},-600,-600,100,140,{kind='hand'})
 check(not drawn('secret')and not drawn('9/9'),'An anonymous hidden hand back cannot borrow the battlefield public-overlay exception')
 shots[#shots+1]='public-facedown-counters';wait(.1)
 for _,role in ipairs({'owner','opponent'})do
  if love.filesystem.getInfo('native-'..role..'.json')then
   local frame=json.decode(love.filesystem.read('native-'..role..'.json'));m:setGame(frame);r.cameraIdentity=nil;r.poses={};m.settings.showTooltips=true;wait(.1)
   local facedown
   for _,player in ipairs(frame.players)do for _,card in ipairs(player.battlefield)do if card.faceDown then facedown=card end end end
   assert(facedown,'Missing actual native facedown fixture');local index
   for i,player in ipairs(r.multiplayerSeats)do for _,card in ipairs(player.battlefield)do if card.id==facedown.id then index=i end end end
   while require('app.dice').busy(r)do wait(.1)end
   r.tableCamera:focus(index,true);wait(.08);local box=assert(hit(facedown.id));local _,h=Layout.dimensions()
   if box.y+box.h>h-20 then r.tableCamera:pan(0,h-20-box.y-box.h);wait(.08);box=assert(hit(facedown.id))end
   point(box.x+box.w/2,box.y+box.h/2);wait(.08)
   check(drawn('2/2')~=nil,'Actual native '..role..' face-down board preserves public2/2 stats')
   local peek=P.peek(facedown)
   check(role=='owner'and peek.name=='Willbender'or role=='opponent'and peek==facedown and not peek.faceDownIdentity,'Native '..role..' identity obeys exact peek entitlement')
   r:inspectHitCard(box)
   check(role=='owner'and m.inspectCard.name=='Willbender'and m.inspectCard.faceDownContext.nativePT=='2/2'or role=='opponent'and m.inspectCard.hidden,'Rightinspect uses native '..role..' permission with separate current face-down stats')
   m.inspectCard=nil;shots[#shots+1]='native-manifest-'..role;wait(.1)
  end
 end
 local file=assert(io.open('/tmp/love2gathering-table-readability-ui.json','w'));file:write(json.encode({checks=checks,scope='Actual LÖVE images/hit regions and synthetic native-shaped action states; optional genuine native manifest projections are read-only recordings. No live engine, network or user saves',cases=reports}));file:close()
 print('TABLE READABILITY UI COMPLETE '..checks..' checks');love.event.quit(0)
end
function love.load()
 clock,wake,checks=0,0,0;mouse={x=0,y=0};shots={};reports={}
 love.mouse.getPosition=function()return mouse.x,mouse.y end
 m=Model.new();m.settings.animations=false;m.settings.reducedMotion=true;m.settings.particles=false;m.settings.sfxEnabled=false;m.settings.showTooltips=false;m.settings.autoFollowTurn=false;m.settings.skyboxBrightness=0;m.page='table'
 landImage=love.graphics.newImage('land.jpg');spellImage=love.graphics.newImage('spell.jpg')
 m.cardData=function(self,card)return card end;m.getArt=function(self,card)assert(not card.hidden and not card.faceDown,'Privateboardbackrequestedimage');artRequests[#artRequests+1]=card.name;if card.name=='Willbender'then return nil end;return card and card.type=='Land'and landImage or spellImage end;m.profileArt=function()end
 m.answer=function(self,kind,value)answers[#answers+1]={type=kind,value=value}end
 r=Renderer.new(m);local strong=r.strong;r.strong=function(self,text,x,y,size,tint,...)
  local font=self.assets:titleFont(size,self.model.settings);local sx,sy=love.graphics.transformPoint(x,y);local right,bottom=love.graphics.transformPoint(x+font:getWidth(tostring(text)),y+font:getHeight())
  ink[#ink+1]={text=tostring(text),size=size,tint=tint,x=sx,y=sy,w=right-sx,h=bottom-sy};return strong(self,text,x,y,size,tint,...)
 end;runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<45,'Sizing fixture exceeded45seconds');r:update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,error=coroutine.resume(runner);assert(ok,error)end
 r:mousemoved(Layout.mouse())
end
function love.draw()
 love.graphics.push();love.graphics.scale(Layout.scale);ink={};r:draw();r:drawForeground();love.graphics.pop()
 if #shots>0 then local name=table.remove(shots,1);local prefix,defense=drawn('3/'),drawn('2');love.graphics.captureScreenshot(function(data)
  if name=='1120-ui1-seats2'then
   local function pixels(box,kind)
    local count=0
    for y=math.max(0,math.floor(box.y)),math.min(data:getHeight()-1,math.ceil(box.y+box.h))do for x=math.max(0,math.floor(box.x)),math.min(data:getWidth()-1,math.ceil(box.x+box.w)-1)do
     local red,green,blue=data:getPixel(x,y)
     if kind=='white'and red>.65 and green>.65 and blue>.65 or kind=='red'and red>.5 and red>green*1.5 and red>blue*1.5 then count=count+1 end
    end end
    return count
   end
   check(prefix and defense and pixels(prefix,'white')>5 and pixels(prefix,'white')>pixels(prefix,'red')*3 and pixels(defense,'red')>5,'Actual P/T pixels keep power white and color only the remaining defense red')
  end
  local out=assert(io.open('/tmp/love2gathering-table-readability-'..name..'.png','wb'));out:write(data:encode('png'):getString());out:close()
 end)end
end
