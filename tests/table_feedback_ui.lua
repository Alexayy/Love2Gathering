-- Real LÖVE rendering/input geometry with synthetic native-shaped projections.
function love.errorhandler(error)
 io.stderr:write('TABLE FEEDBACK UI FAILED '..tostring(error)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end
end
package.preload['app.api']=function()return{new=function()return{request=function()end,update=function()end,quit=function()end}end}end
local Model=require('app.model');local Renderer=require('app.renderer');local Layout=require('app.layout');local json=require('lib.json')
local m,r,runner,clock,wake,checks,shots,ink,headers,context,mouse,image,landImage,reports
local function check(ok,label)assert(ok,label);checks=checks+1;print('TABLE FEEDBACK UI PASS '..label)end
local function wait(t)wake=clock+(t or .08);coroutine.yield()end
local function drawn(text)for _,entry in ipairs(ink)do if entry.text==text then return entry end end end
local function fixture(count)
 local players={}
 for i=1,count do players[i]={id='p'..i,name=i==1 and'Synthetic local player'or'Synthetic bot '..i,human=i==1,seat=i-1,life=i==3 and 0 or 40,hand={},handCount=0,libraryCount=60,command={},graveyard={},exile={},mana={},
  lost=i==2 and count>2,left=i==4,battlefield={{id='p'..i..'-creature',name='Native mana creature',type='Creature',manaCost='{2}{W}{B}{G}',power='3',toughness='3',damage=1,counters={['+1/+1']=1}}}}end
 for i,player in ipairs(players)do for j=1,7 do table.insert(player.battlefield,1,{id='p'..i..'-land-'..j,name='Plains',type='Land',manaCost=''})end end
 return{gameId='SYNTHETIC-FEEDBACK-'..count,running=true,revision=1,error=json.null,turn=2,phase='Combat',step='Declare Blockers',activePlayerId='p1',players=players,stack={},log={},commanderDamageEnabled=count>2,combat={groups={}}}
end
local function luminance(data,box)
 local sum,count=0,0
 for y=math.max(0,math.floor((box.y+box.h*.3)*Layout.scale)),math.min(data:getHeight()-1,math.floor((box.y+box.h*.4)*Layout.scale))do
  for x=math.max(0,math.floor((box.x+box.w*.2)*Layout.scale)),math.min(data:getWidth()-1,math.floor((box.x+box.w*.8)*Layout.scale))do
   local rr,gg,bb=data:getPixel(x,y);sum=sum+(rr+gg+bb)/3;count=count+1
  end
 end
 return sum/math.max(1,count)
end
local function scenario()
 for _,size in ipairs({{1120,720,1},{2560,1080,1},{2560,1080,1.25}})do
  love.window.setMode(size[1],size[2],{vsync=0,resizable=true});Layout.setScale(size[3]);require('app.assets').invalidateRasterCaches()
  local w,h=Layout.dimensions();local name=size[1]..'-ui'..Layout.scale
  m:setGame(fixture(2));r.cameraIdentity=nil;r.poses={};wait(.15)
  local header=assert(headers['p1-creature']);check(#header.mana==4,'Every supplied native cost symbol renders in the new card header '..name)
  for _,symbol in ipairs(header.mana)do
   check(symbol.x>=header.x-1 and symbol.x+symbol.size<=header.x+header.w+1 and symbol.y>=header.y and symbol.y+symbol.size<=header.y+header.h+2,'Actual mana glyph stays inside its measured header '..name)
  end
  local first=header.mana[1];local title=assert(header.title)
  check(title.y+title.h<=first.y+1 or title.x+title.w<=first.x-2,'Card name and complete mana cost have separate measured space '..name)
  check(drawn('Declare Blockers')and drawn('Combat'),'Actual native step and its active phase have strong text '..name)
  local stops={};for _,entry in ipairs(r.hits)do if entry.kind=='phase-stop'then stops[entry.phase..':'..entry.side]=entry end end
  for _,phase in ipairs({'BEGINNING','PRECOMBAT','COMBAT','POSTCOMBAT','END'})do
   check(stops[phase..':own']and stops[phase..':opponent'],'Own and opponent stop targets are present for '..phase..' '..name)
  end
  shots[#shots+1]={name=name..'-mana-phase',phase=true,header=header,stops=stops};wait(.1)
  m:setGame(fixture(4));r.cameraIdentity=nil;wait(.1);r.tableCamera:overview(true);wait(.1)
  check(drawn('ELIMINATED') and drawn('LEFT MATCH'),'Native lost and departed seats show their distinct labels '..name)
  local live=assert(r.cardRects['p3-creature']);local out=assert(r.cardRects['p2-creature']);check(m.game.players[3].life==0 and not m.game.players[3].lost,'A remaining zero-life seat is not declared out by the frontend '..name)
  shots[#shots+1]={name=name..'-eliminated',live=live,out=out};wait(.1)
  for _,kind in ipairs({'win','loss','draw'})do
   local frame=fixture(2);frame.running=false;frame.result={gameId=frame.gameId,completed=true,outcome=kind};frame.players[1].won=kind=='win';frame.players[1].lost=kind=='loss';m:setGame(frame);wait(.1)
   local title=kind=='win'and'YOU WON'or kind=='loss'and'YOU LOST'or'DRAW'
   check(drawn(title)and not drawn('MATCH ENDED'),'Native terminal '..kind..' gets one full-screen duel title '..name)
   check(r:inputBlocked(),'The terminal duel background cannot submit old battlefield actions '..name)
   shots[#shots+1]={name=name..'-'..kind};wait(.08)
  end
  reports[#reports+1]={name=name,physical={love.graphics.getDimensions()},logical={w,h},headerHeight=header.height}
 end
 local out=assert(io.open('/tmp/love2gathering-table-feedback-ui.json','w'));out:write(json.encode({checks=checks,cases=reports,scope='Actual LÖVE card-header/phase/elimination/outcome pixels using synthetic native-shaped states and local JPEGs. No game rules, network or user saves.'}));out:close()
 print('TABLE FEEDBACK UI COMPLETE '..checks..' checks');love.event.quit(0)
end
function love.load()
 checks,clock,wake=0,0,0;shots={};ink={};headers={};reports={};mouse={x=0,y=0};love.mouse.getPosition=function()return mouse.x,mouse.y end
 m=Model.new();m.page='table';m.settings.animations=false;m.settings.reducedMotion=true;m.settings.showTooltips=false;m.settings.particles=false;m.settings.sfxEnabled=false;m.settings.autoFollowTurn=false;m.settings.skyboxBrightness=0
 image=love.graphics.newImage('spell.jpg');landImage=love.graphics.newImage('land.jpg');m.cardData=function(self,card)return card end;m.getArt=function(self,card,force,kind)if kind~='art_crop'then return card.type=='Land'and landImage or image end end;m.profileArt=function()end;m.botPlaymatArt=function()return image end
 r=Renderer.new(m)
 local strong=r.strong;r.strong=function(self,text,x,y,size,tint,width,...)
  local sx,sy=love.graphics.transformPoint(x,y);local font=self.assets:titleFont(size,self.model.settings);local right,bottom=love.graphics.transformPoint(x+font:getWidth(tostring(text)),y+font:getHeight())
  local entry={text=tostring(text),x=sx,y=sy,w=right-sx,h=bottom-sy};ink[#ink+1]=entry;if context then context.title=entry end
  return strong(self,text,x,y,size,tint,width,...)
 end
 local mana=r.assets.mana;r.assets.mana=function(self,symbol,x,y,size,...)
  if context then local sx,sy=love.graphics.transformPoint(x,y);local right=love.graphics.transformPoint(x+size,y);context.mana[#context.mana+1]={symbol=symbol,x=sx,y=sy,size=right-sx}end
  return mana(self,symbol,x,y,size,...)
 end
 local header=r.cardHeader;r.cardHeader=function(self,card,data,x,y,w,h,...)
  local sx,sy=love.graphics.transformPoint(x,y);local right,bottom=love.graphics.transformPoint(x+w,y+h);local record={x=sx,y=sy,w=right-sx,h=bottom-sy,mana={}}
  context=record;local height=header(self,card,data,x,y,w,h,...);context=nil;record.height=height;record.h=height*record.w/w;headers[card.id]=record;return height
 end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<35,'Feedback fixture timed out');r:update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,error=coroutine.resume(runner);assert(ok,error)end
end
function love.draw()
 ink={};headers={};love.graphics.push();love.graphics.scale(Layout.scale);r:draw();r:drawForeground();love.graphics.pop()
 if #shots>0 then local job=table.remove(shots,1);love.graphics.captureScreenshot(function(data)
  if job.phase then
   local function green(phase)
    local box=job.stops[phase..':own'];local count=0
    local y=(box.y+box.h-5)*Layout.scale
    for py=math.ceil(y),math.floor(y+2*Layout.scale)do
     for px=math.ceil(box.x*Layout.scale),math.floor((box.x+box.w)*Layout.scale)-1 do
      local rr,gg=data:getPixel(px,py);if gg>.65 and gg>rr*1.4 then count=count+1 end
     end
    end
    return count
   end
   check(green('COMBAT')>green('PRECOMBAT')+25,'Actual active-phase border pixels are stronger than inactive phases '..job.name)
   local symbol=job.header.mana[2];local count=0
   for y=math.floor(symbol.y),math.ceil(symbol.y+symbol.size)-1 do for x=math.floor(symbol.x),math.ceil(symbol.x+symbol.size)-1 do local rr,gg,bb=data:getPixel(x,y);if rr>.55 and gg>.55 and bb>.4 then count=count+1 end end end
   check(count>5,'Actual white mana symbol remains visible over the card image '..job.name)
  elseif job.live then check(luminance(data,job.out)<luminance(data,job.live)*.45,'Only the eliminated seat card terrain is substantially dimmed '..job.name)end
  local out=assert(io.open('/tmp/love2gathering-table-feedback-'..job.name..'.png','wb'));out:write(data:encode('png'):getString());out:close()
 end)end
end
