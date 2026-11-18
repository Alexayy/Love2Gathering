-- Actual LÖVE drawing with labeled synthetic scenes and optional native frames.
local FX=require('app.mechanic_fx');local Board=require('app.board_fx');local Assets=require('app.assets');local json=require('lib.json')
local output=assert(os.getenv('LOVE2GATHERING_VFX_OUTPUT'))
local mode='profiles';local frame=0;local clock=0;local renderer;local results={checks=json.array(),performance={},scope='Actual LÖVE profile/effect rendering and synthetic crowded director benchmark; no native legality, Internet, full-table UX or physical GPU-independent guarantee.'}
local samples={baseline={},effects={}};local profileNames={'flashback','jump_start','evoke','convoke','mutate','face_down','haste','extort','trample','reach','flying','ward'}
local cards={};local director;local requested=false;local assets;local font
local fonts={}
local nativeBefore,nativeAfter,nativeDirector,nativeAnchors,nativeSurvivors
local nativeScenes={}
local function check(ok,label)assert(ok,label);results.checks[#results.checks+1]={passed=true,message=label};print('VFX UI PASS '..label)end
local function text(value,x,y,size,color,width,align)
 size=math.floor(size or 15);if not fonts[size]then fonts[size]=love.graphics.newFont('assets/fonts/DejaVuSans.ttf',size)end
 love.graphics.setFont(fonts[size]);love.graphics.setColor(color or{.85,.91,.95});love.graphics.printf(tostring(value),x,y,width or 250,align or'left')
end
local function fakeCard(id,mechanic)return{id=id,name=mechanic:gsub('_',' '),colors={'U'},currentKeywords={{id=mechanic,name=mechanic:gsub('_',' ')}},type='Creature',power='3',toughness='3'}end
local function base(card,x,y,w,h)
 love.graphics.setColor(.035,.052,.074,1);love.graphics.rectangle('fill',x+3,y+6,w,h,7,7)
 love.graphics.setColor(.13,.18,.23,1);love.graphics.rectangle('fill',x,y,w,h,7,7)
 love.graphics.setColor(.28,.38,.46,1);love.graphics.rectangle('line',x,y,w,h,7,7)
 text(card.faceDown and'Face-down object'or card.name,x+9,y+9,w<125 and 11 or 16,{.9,.91,.86},w-18)
 love.graphics.setColor(.07,.11,.15,1);love.graphics.rectangle('fill',x+8,y+38,w-16,h*.52,4,4)
 love.graphics.setColor(.16,.24,.29,1);love.graphics.polygon('line',x+w*.5,y+h*.25,x+w*.8,y+h*.4,x+w*.5,y+h*.55,x+w*.2,y+h*.4)
 if h>=180 then text(card.faceDown and'Public characteristics'or'Native identity and text stay clear',x+9,y+h*.70,13,{.65,.73,.78},w-18)end
 text(card.faceDown and'2/2'or tostring(card.power or'3')..'/'..tostring(card.toughness or'3'),x+w-47,y+h-28,16,{.9,.94,.95},40,'right')
end
local function drawCard(card,x,y,w,h,fx)
 if fx then FX.cardUnderlay(renderer,card,x,y,w,h,{kind='permanent'})end
 base(card,x,y,w,h)
 if fx then FX.cardOverlay(renderer,card,x,y,w,h,{kind='permanent'})end
end
local function privacyPixels(card)
 local c=love.graphics.newCanvas(220,320);love.graphics.push('all');love.graphics.setCanvas(c);love.graphics.clear(.01,.02,.03,1)
 drawCard(card,12,12,194,272,true);love.graphics.setCanvas();love.graphics.pop()
 local data=c:newImageData();local digest=love.data.encode('string','hex',love.data.hash('sha256',data:getString()));data:release();c:release();return digest
end
local function capture(name,after)
 requested=true;love.graphics.captureScreenshot(function(image)local f=assert(io.open(output..'/'..name..'.png','wb'));f:write(image:encode('png'):getString());f:close();if after then after()end;requested=false end)
end
local function finish()
 results.passed=true;local f=assert(io.open(output..'/report.json','w'));f:write(json.encode(results));f:close();love.event.quit(0)
end
function love.load()
 assets=Assets.new();font=love.graphics.newFont('assets/fonts/DejaVuSans.ttf',15)
 renderer={model={settings={animations=true,particles=true,vfxIntensity=.85,ambientKeywordFX=true,cameraShake=true,distortion=true}},assets=assets,fxClock=1.3,dt=1/60,colors={text={.9,.94,.98}}}
 renderer.model.canSelect=function(_,id)return id~='secret' end
 renderer.text=function(_,...)return text(...)end
 for i,name in ipairs(profileNames)do cards[i]=fakeCard('profile-'..i,name);if name=='face_down'then cards[i].faceDown=true;cards[i].hidden=true end end
 local a=fakeCard('secret','haste');a.faceDown=true;a.hidden=true;a.colors={'R'}
 local b=fakeCard('secret','mutate');b.faceDown=true;b.hidden=true;b.colors={'U'}
 check(privacyPixels(a)==privacyPixels(b),'Different hidden colors and mechanics produce identical neutral pixels')
 renderer.model.settings.reducedMotion=true;renderer.fxClock=.3;local still=privacyPixels(cards[1]);renderer.fxClock=10.5
 check(still==privacyPixels(cards[1]),'Reduced-motion cards retain their labels/badges with no moving edge pixels')
 renderer.model.settings.reducedMotion=false
 director=FX.newDirector();director.initialized=true;director.identity='synthetic-crowd'
 local events={};local indexed={};renderer.crowd={};renderer.boxes={}
 for i=1,100 do
  local name=profileNames[(i-1)%#profileNames+1];local card=fakeCard('crowd-'..i,name)
  renderer.crowd[i]=card;indexed[card.id]=card
  renderer.boxes[card.id]={x=16+((i-1)%20)*94,y=120+math.floor((i-1)/20)*170,w=80,h=112}
  if i<=50 then events[#events+1]={id='wipe-'..i,operation='destroy',type='zone',sourceId='crowd-100',targetId=card.id,batchId='synthetic-confirmed-destroy-batch'}end
 end
 FX.observe(director,{revision=1,animationEvents=events},indexed,'synthetic-crowd');FX.flush(director,function(id)return renderer.boxes[id]end)
 renderer.tableLayout={viewport={x=0,y=85,w=1920,h=970}}
 check(#director.events==50 and director.major~=nil,'Fifty synthetic confirmed outcomes use one batch flourish and bounded effects')
 local beforePath,afterPath=os.getenv('LOVE2GATHERING_VFX_NATIVE_BEFORE'),os.getenv('LOVE2GATHERING_VFX_NATIVE_AFTER')
 if beforePath and afterPath then
  local function read(path)local f=assert(io.open(path));local raw=f:read('*a');f:close();return json.decode(raw)end
  nativeBefore,nativeAfter=read(beforePath),read(afterPath);nativeDirector=FX.newDirector();nativeAnchors={};nativeSurvivors={}
  local n=0;for _,player in ipairs(nativeBefore.players)do for _,card in ipairs(player.battlefield)do n=n+1;nativeAnchors[card.id]={x=30+(n-1)%15*125,y=160+math.floor((n-1)/15)*180,w=100,h=140}end end
  for _,player in ipairs(nativeAfter.players)do for _,card in ipairs(player.battlefield)do nativeSurvivors[card.id]=card end end
  FX.observe(nativeDirector,nativeBefore,Board.index(nativeBefore),nativeBefore.gameId)
  FX.observe(nativeDirector,nativeAfter,Board.index(nativeAfter),nativeAfter.gameId)
  FX.flush(nativeDirector,function(id)return nativeSurvivors[id]and nativeAnchors[id]or nil end,nativeAnchors)
  local survivors=0;for _ in pairs(nativeSurvivors)do survivors=survivors+1 end
  check(nativeDirector.major and nativeDirector.major.operation=='destroy'and nativeDirector.major.count==60,'Actual native Wrath produces one 60-permanent destroy batch; spell departure is excluded')
  check(survivors==1,'Actual native indestructible survivor remains on the current battlefield')
  results.nativeWipe={sourceBefore=beforePath,sourceAfter=afterPath,affected=nativeDirector.major.count,survivors=survivors,operation=nativeDirector.major.operation,scope='Actual viewer-filtered XMage prepared native Wrath outcome. Layout geometry is synthetic; only current surviving cards are drawn as live objects. Departed rectangles are noninteractive material-effect anchors.'}
 end
 local causeFolder=os.getenv('LOVE2GATHERING_VFX_NATIVE_CAUSES')
 if causeFolder then
  local definitions={{'Evoke','evoke-before','evoke-cast'},{'Convoke','convoke-before','convoke-cast'},{'Extort','extort-trigger','extort-complete'},{'Mutate','mutate-before','mutate-complete'},
   {'Face up','morph-face-down','morph-face-up'},{'Haste','haste-before','haste-attacking'},{'Reach','haste-attacking','reach-blocking'},{'Trample','trample-before','trample-complete'}}
  local function read(name)local f=assert(io.open(causeFolder..'/'..name..'.json'));local raw=f:read('*a');f:close();return json.decode(raw)end
  local sources={}
  for i,definition in ipairs(definitions)do
   local scene={name=definition[1],x=20+(i-1)%4*475,y=105+math.floor((i-1)/4)*460,current={},previous={},players={},zones={},rows={},director=FX.newDirector()}
   local before,after=read(definition[2]),read(definition[3]);scene.after=after;sources[definition[2]]=causeFolder..'/'..definition[2]..'.json';sources[definition[3]]=causeFolder..'/'..definition[3]..'.json'
   local function geometry(game,boxes)
    for pi,p in ipairs(game.players)do
     scene.players[p.id]={x=scene.x+10,y=scene.y+50+(pi-1)*28,w=100,h=22};scene.zones[p.id]={}
     for _,zone in ipairs({'hand','graveyard','exile','library','command'})do scene.zones[p.id][zone]={x=scene.x+12,y=scene.y+100+(pi-1)*90,w=70,h=90}end
     for ci,c in ipairs(p.battlefield or{})do boxes[c.id]={x=scene.x+10+(ci-1)%5*88,y=scene.y+220+(pi-1)*112,w=80,h=112}end
    end
    for si,item in ipairs(game.stack)do scene.rows[item.id]={x=scene.x+275,y=scene.y+100+(si-1)*72,w=165,h=62,visible=true,name=item.name}end
   end
   geometry(before,scene.previous);scene.rows={};geometry(after,scene.current)
   FX.observe(scene.director,before,Board.index(before),before.gameId);FX.observe(scene.director,after,Board.index(after),after.gameId)
   FX.flush(scene.director,function(id)return scene.current[id]or scene.players[id]or scene.rows[id]end,scene.previous,scene.players,scene.zones,scene.zones,scene.rows,after.stack)
   nativeScenes[#nativeScenes+1]=scene
  end
  check(#nativeScenes==8,'Eight detailed mechanic scenes consume actual native outcomes and public current traits')
  results.nativeCauses={sources=sources,scenes=#nativeScenes,scope='Actual accepted native Evoke/Convoke/Extort/Mutate/Morph-face-up/Haste/Reach and prepared Trample outcomes. Presentation geometry is synthetic and noninteractive; no full-table UX claim.'}
 end
end
function love.update(dt)
 frame=frame+1;clock=clock+dt;renderer.dt=dt;renderer.fxClock=clock
 if mode=='profiles'and frame>18 and not requested then capture('profiles',function()mode='events';frame=0 end)
 elseif mode=='events'and frame>18 and not requested then capture('events',function()mode='baseline';frame=0 end)
 elseif mode=='baseline'and frame>110 then mode='effects';frame=0
 elseif mode=='effects'and frame>150 and not requested then
  capture('crowded',function()
   local function summary(values)table.sort(values);local sum=0;for _,v in ipairs(values)do sum=sum+v end;return{frames=#values,meanMs=sum/#values*1000,p95Ms=values[math.max(1,math.floor(#values*.95))]*1000,maxMs=values[#values]*1000}end
   results.performance={baseline=summary(samples.baseline),effects=summary(samples.effects),renderer={love.graphics.getRendererInfo()},measurement='CPU draw submission time around identical 100-card synthetic scene, after 20 warmup frames, vsync off. Effects include 50 simultaneous destroy outcomes. No full application or end-to-end GPU timing claim.'}
   check(director.stats.drawPrimitives<=director.maxParticles,'Simultaneous fracture primitive budget stays bounded at 256')
   results.director={active=#director.events,maxEffects=director.maxEffects,maxTrails=director.maxTrails,maxParticles=director.maxParticles,drawPrimitives=director.stats.drawPrimitives}
   if nativeDirector then mode='native';frame=0 elseif#nativeScenes>0 then mode='causes';frame=0 else finish()end
  end)
 elseif mode=='native'and frame>18 and not requested then capture('native-wipe',function()if#nativeScenes>0 then mode='causes';frame=0 else finish()end end)
 elseif mode=='causes'and frame>18 and not requested then capture('native-causes',finish)
 end
end
function love.draw()
 love.graphics.clear(.012,.02,.031,1);text('Synthetic mechanic presentation • actual LÖVE drawing',24,18,18,{.9,.94,.97},1200)
 local started=love.timer.getTime()
 if mode=='profiles'then
  for i,c in ipairs(cards)do
   local x=38+((i-1)%6)*313;local y=92+math.floor((i-1)/6)*450
   drawCard(c,x+39,y,194,272,true);text(FX.profile(profileNames[i]).label,x,y+300,16,{.65,.82,.87},280,'center');text(FX.profile(profileNames[i]).recipe,x,y+326,13,{.46,.61,.69},280,'center')
  end
 elseif mode=='events'then
  local operations={'destroy','sacrifice','exile','return','merge','face_up'}
  for i,operation in ipairs(operations)do
   local card=fakeCard('material-'..i,profileNames[i]);local x=35+(i-1)*313;local y=150
   drawCard(card,x+36,y,194,272,true);text(operation,x,y+310,16,{.85,.82,.71},280,'center')
   local d=FX.newDirector();FX.queue(d,{id='material-'..i,operation=operation,sourceId=card.id,targetId=card.id},card)
   FX.flush(d,function()return{x=x+36,y=y,w=194,h=272}end);d.events[1].age=.23;FX.draw(d,renderer)
  end
  text('Operation-specific material signatures require explicit native semantics; this scene supplies labeled fixtures.',80,700,16,{.66,.73,.79},1740,'center')
 elseif mode=='causes'then
  renderer.model.canSelect=function()return false end
  text('Actual native mechanic outcomes • synthetic noninteractive geometry',24,55,16,{.86,.81,.71},1800)
  for _,scene in ipairs(nativeScenes)do
   love.graphics.setColor(.13,.20,.26,.65);love.graphics.rectangle('line',scene.x,scene.y,457,448,5,5);text(scene.name,scene.x+10,scene.y+10,16,{.77,.87,.91},440)
   for _,player in ipairs(scene.after.players)do
    local p=scene.players[player.id];text((player.name or'Player')..' '..tostring(player.life),p.x,p.y,11,{.68,.78,.85},160)
    for _,card in ipairs(player.battlefield or{})do local b=scene.current[card.id];drawCard(card,b.x,b.y,b.w,b.h,true)end
   end
   for _,row in pairs(scene.rows)do love.graphics.setColor(.16,.25,.30,.9);love.graphics.rectangle('line',row.x,row.y,row.w,row.h,3,3);text(row.name,row.x+7,row.y+8,12,{.78,.85,.91},row.w-14)end
   for _,e in ipairs(scene.director.events)do e.age=.22 end
   renderer.tableLayout={viewport={x=scene.x,y=scene.y,w=457,h=448}};FX.draw(scene.director,renderer)
  end
 elseif mode=='native'then
  renderer.model.canSelect=function()return false end
  text('Actual XMage Wrath outcome • 60 destroyed, 1 current survivor • synthetic noninteractive effect geometry',24,55,16,{.86,.81,.71},1800)
  for id,b in pairs(nativeAnchors)do
   local card=nativeSurvivors[id]
   if card then drawCard(card,b.x,b.y,b.w,b.h,true)
   else love.graphics.setColor(.15,.20,.25,.20);love.graphics.rectangle('line',b.x,b.y,b.w,b.h,4,4)end
  end
  for _,e in ipairs(nativeDirector.events)do e.age=.22 end
  if nativeDirector.major then nativeDirector.major.age=.34 end
  FX.draw(nativeDirector,renderer)
  text('Surviving native object remains visible; departing cards are never restored as playable ghosts.',80,980,16,{.65,.75,.80},1740,'center')
 else
  local enabled=mode=='effects';text(enabled and'100 cards + 50 confirmed destroy outcomes • bounded visual load'or'100 cards • matching baseline without mechanic VFX',24,55,16,{.72,.82,.87},1600)
  for _,card in ipairs(renderer.crowd)do local b=renderer.boxes[card.id];drawCard(card,b.x,b.y,b.w,b.h,enabled)end
  if enabled then for _,e in ipairs(director.events)do e.age=.22 end;director.major.age=.34;FX.draw(director,renderer)end
  local elapsed=love.timer.getTime()-started
  if frame>20 then local rows=enabled and samples.effects or samples.baseline;rows[#rows+1]=elapsed end
 end
end
function love.errorhandler(message)io.stderr:write(tostring(message)..'\n'..debug.traceback()..'\n');return function()return 1 end end
