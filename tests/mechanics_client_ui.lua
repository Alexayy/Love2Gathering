-- Real LÖVE/Slab input and rendering of explicitly synthetic stress states.
local json=require('lib.json');local calls={}
package.preload['app.api']=function()
 local API={escape=function(v)return tostring(v)end}
 function API.new()return{escape=API.escape,routeGeneration=0,request=function(_,service,method,path,body,callback)calls[#calls+1]={service=service,path=path,body=body,callback=callback}end,update=function()end,quit=function()end,setNativeSession=function()end,status=function()return{oldestSeconds=0}end}end
 return API
end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Table=require('app.table')
local out=assert(os.getenv('L2G_MECHANICS_CLIENT_OUTPUT'));local count=tonumber(os.getenv('L2G_MECHANICS_CLIENT_COUNT'))or 10
local variant=os.getenv('L2G_MECHANICS_CLIENT_VARIANT')or'equal';local stackCount=tonumber(os.getenv('L2G_MECHANICS_CLIENT_STACK'))or 0
local m,r,v,p,runner,Cursor,Window,Region;local wake,clock,frame=0,0,0;local mouse={x=1,y=1};local down={};local keys={};local buttons,inputs,choices,choiceRegions={},{},{},{}
local checks,shots,captures,metrics={},{},{},{};local phase='warm';local frameTimes,fieldTimes,drawTimes,hitTimes={},{},{},{};local drawTotal,fieldTotal=0,0;local evidenceType='synthetic_rendering_fixture'
local function check(ok,label)assert(ok,label);checks[#checks+1]=label end
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(json.encode(value));f:close()end
local function wait(s)wake=clock+(s or .07);coroutine.yield()end
local function bounds()local x,y,w,h=Cursor.GetItemBounds();local dx,dy=Region.Transform(nil,0,0);return{x=x+dx,y=y+dy,w=w,h=h}end
local function move(box)local ox,oy=mouse.x,mouse.y;mouse.x=(box.x+box.w/2)*Layout.scale;mouse.y=(box.y+box.h/2)*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy);r:mousemoved(mouse.x/Layout.scale,mouse.y/Layout.scale)end
local function click(box,button)
 button=button or 1;assert(box,'Actual UI target absent');move(box);wait(.05);down[button]=true;S.OnMousePressed(mouse.x,mouse.y,button,false,1)
 if S.IsVoidHovered()then r:mousepressed(mouse.x/Layout.scale,mouse.y/Layout.scale,button,1)end
 wait(.05);down[button]=false;S.OnMouseReleased(mouse.x,mouse.y,button,false,1);r:mousereleased(mouse.x/Layout.scale,mouse.y/Layout.scale,button);wait(.14)
end
local function scrollSelectable(label)
 for _=1,40 do
  local box,region=choices[label],choiceRegions[label]
  assert(box and region,'Native component control/scroll region absent')
  if box.y>=region.y and box.y+box.h<=region.y+region.h then return box end
  move({x=region.x+region.w*.8,y=region.y+region.h*.5,w=0,h=0});wait(.04)
  S.OnWheelMoved(0,box.y<region.y and 4 or-4);wait(.08)
 end
 error('Native component row is not reachable by inspector scrolling')
end
local function snapshot(name)shots[#shots+1]=name;wait(.08)end
local function benchmark(values)local copy={};for _,n in ipairs(values)do copy[#copy+1]=n end;table.sort(copy);local total=0;for _,n in ipairs(copy)do total=total+n end;return{samples=#copy,meanMs=#copy>0 and total/#copy*1000 or 0,p95Ms=copy[math.max(1,math.ceil(#copy*.95))]and copy[math.max(1,math.ceil(#copy*.95))]*1000 or 0,maxMs=(copy[#copy]or 0)*1000}end
local function fixture()
 local field=json.array();for i=1,count do field[i]={id='token-'..i,name='Rat',token=true,ownerId='human',controllerId='human',power=variant=='varied'and tostring(i%7+1)or'1',toughness=variant=='varied'and tostring(i%9+1)or'1',damage=variant=='varied'and i%3 or 0,tapped=variant=='varied'and i%5==0 or false,counters=variant=='varied'and{['+1/+1']=i%4}or{},colors=variant=='varied'and(i%2==0 and{'B'}or{'R'})or{'B'},keywords=variant=='varied'and(i%3==0 and{'Flying'}or{'Deathtouch'})or{},printing={name='Rat',power='1',toughness='1',colors={'B'},type_line='Token Creature — Rat'},type='Creature',type_line='Token Creature — Rat',rules='This fixture carries native-shaped values; it executes no Magic rules.'}end
 local players=json.array({{id='human',name='Synthetic Human',human=true,life=40,hand=json.array(),battlefield=field,graveyard=json.array(),exile=json.array(),command=json.array(),libraryCount=70,handCount=0,mana={}},{id='bot',name='Synthetic Opponent',human=false,life=40,hand=json.array(),battlefield=json.array(),graveyard=json.array(),exile=json.array(),command=json.array(),libraryCount=70,handCount=7,mana={}}})
 if variant=='mutate'then
  field[1].name='Gemrazer';field[1].power='5';field[1].toughness='5';field[1].counters={['+1/+1']=1};field[1].keywords={'Reach','Trample'};field[1].printing={name='Gemrazer',power='4',toughness='4',colors={'G'},type_line='Creature — Beast'}
  field[1].mutate={count=2,topId='gemrazer-component',originalObjectId='original-rat',components={{id='original-rat',name='Rat',power='1',toughness='1',token=true,printing={name='Rat',power='1',toughness='1'}},{id='gemrazer-component',name='Gemrazer',power='4',toughness='4',printing={name='Gemrazer',power='4',toughness='4'}}}}
 end
 local stack=json.array();for i=1,stackCount do stack[i]={id='stack-'..i,sourceId='token-1',sourceName='Repeated native-shaped trigger '..i,sourceCard=field[1],rules='Target creature gets +1/+1 until end of turn. '..string.rep('Long stack presentation. ',i%3+1),targets=json.array({{id='token-'..count}})}end
 local log=json.array();if stackCount>0 then for i=1,80 do log[i]={category='cast',actor='human',text='Native-shaped recorded action '..i..': Rat triggered a deliberately long presentation entry.',sourceId=field[(i-1)%#field+1].id,sourceCard=field[(i-1)%#field+1]}end end
 return{gameId='SYNTHETIC-MECHANICS-'..count..'-'..variant,revision=1,running=true,format='Commander',turn=8,step='PRECOMBAT_MAIN',phase='PRECOMBAT_MAIN',activePlayerId='human',priorityPlayerId='human',players=players,stack=stack,log=log,revealed=json.array(),lookedAt=json.array(),prompt={id=1,type='pick_target',message='Synthetic transport fixture: choose the exact offered object',actionable=json.array({'token-'..count}),choices=json.array({{id='token-'..count,responseType='uuid'}})}}
end
local function scenario()
 wait(.22)
 local generate=love.timer.getTime();local game=fixture();metrics.fixtureGenerationMs=(love.timer.getTime()-generate)*1000
 local native=os.getenv('L2G_MECHANICS_CLIENT_NATIVE')
 if native and native~=''then local f=assert(io.open(native,'rb'));game=json.decode(f:read('*a'));f:close();evidenceType='native_projection_client_render';count=0;for _,player in ipairs(game.players or{})do count=count+#(player.battlefield or{})end;stackCount=#(game.stack or{})end
 metrics.objects=count;metrics.stackObjects=stackCount
 local start=love.timer.getTime();local encoded=json.encode(game);metrics.jsonEncodeMs=(love.timer.getTime()-start)*1000;metrics.jsonBytes=#encoded
 start=love.timer.getTime();local decoded=json.decode(encoded);metrics.jsonDecodeMs=(love.timer.getTime()-start)*1000
 m:setGame(decoded);m.stackOpen=stackCount>0;m.logOpen=stackCount>0;m.page='table';wait(.25)
 if native and native~=''then
  local deadline=clock+12;while require('app.dice').busy(r)and clock<deadline do wait(.05)end
  check(not require('app.dice').busy(r),'Native starting-roll presentation completes before measuring the battlefield')
 end
 if stackCount>0 then m.game.prompt=nil end
 phase='measure';wait(.5);phase='inspect'
 metrics.frameCpu=benchmark(frameTimes);metrics.fieldCpu=benchmark(fieldTimes);metrics.cardDrawCpu=benchmark(drawTimes);metrics.hitTestCpu=benchmark(hitTimes)
 local seen={};for id in pairs(r.cardRects)do if id:find('token-',1,true)==1 then seen[id]=true end end
 local n=0;for _ in pairs(seen)do n=n+1 end
 if evidenceType=='synthetic_rendering_fixture'then check(n==count,'Every native-shaped token retains its exact individual rectangle without a count cap')end
 if evidenceType=='native_projection_client_render'then
  local represented=0;for _,player in ipairs(m.game.players or{})do for _,card in ipairs(player.battlefield or{})do if r.cardRects[card.id]then represented=represented+1 end end end
  check(represented==count,'Every separately captured native battlefield object retains its exact rendering identity')
 end
 check(not next(down),'No held synthetic pointer remains during measurement')
 snapshot('board-'..count..'-'..variant..'-stack'..stackCount)
 if evidenceType=='native_projection_client_render'and count>0 then
  metrics.nativeInstanceSelections={}
  for playerIndex,player in ipairs(m.game.players or{})do
   local field=player.battlefield or{};local last=field[#field]
   if last then
    local zone;for _,hit in ipairs(r.hits)do if hit.kind=='zone'and#(hit.cards or{})==#field and hit.cards[#field].id==last.id and hit.label:find('Battlefield',1,true)then zone=hit;break end end
    check(zone~=nil,'Captured native battlefield exposes its exact-instance browser')
    click(zone);check(m.zoneView and#m.zoneView.cards==#field,'Captured native browser retains every controller-owned battlefield instance')
    click(inputs['zone-search']);S.OnTextInput(last.id);wait(.15)
    local selected;local prefix='#'..#field..' '..last.name
    for label,box in pairs(choices)do if label:find(prefix,1,true)==1 then selected=box;break end end
    check(selected~=nil,'Actual UUID search reaches the final captured native instance')
    snapshot('native-last-instance-'..playerIndex)
    local before=#calls;local offered=m:canSelect(last.id);click(selected)
    if offered then
     check(#calls==before+1 and calls[#calls].body.type=='uuid'and calls[#calls].body.value==last.id,'Captured native offered instance forwards only its exact UUID')
     m.actionBusy=false;m.answeredPrompt=nil
    else
     check(m.inspectCard and m.inspectCard.id==last.id and#calls==before,'Without an offered native target, selecting the final instance only inspects that exact object')
     snapshot('native-last-inspection-'..playerIndex);click(buttons['Close details'])
    end
    metrics.nativeInstanceSelections[#metrics.nativeInstanceSelections+1]={playerId=player.id,objectId=last.id,battlefieldCount=#field}
    if m.zoneView then click(buttons['Close zone'])end
   end
  end
 end
 if evidenceType=='synthetic_rendering_fixture'and variant=='churn'then
  local prototype=m.game.players[1].battlefield;local peaks,retained={},0
  for wave=1,20 do
   local field=json.array();for index,original in ipairs(prototype)do local card={};for key,value in pairs(original)do card[key]=value end;card.id='wave-'..wave..'-token-'..index;field[#field+1]=card end
   m.game.players[1].battlefield=field;m.game.revision=m.game.revision+1;wait(.07)
   local poses=0;for _ in pairs(r.poses)do poses=poses+1 end;retained=math.max(retained,poses);peaks[#peaks+1]=poses
  end
  metrics.poseCacheByWave=peaks;metrics.maximumRetainedPoses=retained
  check(retained<=count*3,'Token churn retains current presentation poses plus only a short transition grace')
  m.game.players[1].battlefield=json.array();m.game.revision=m.game.revision+1;wait(.25)
  local remaining=0;for _ in pairs(r.poses)do remaining=remaining+1 end;metrics.poseCacheAfterClear=remaining
  check(remaining==0,'Removed token presentation poses are released without dropping current native objects')
  snapshot('churn-recovered')
 elseif evidenceType=='synthetic_rendering_fixture'and stackCount==0 then
  local zone;for _,hit in ipairs(r.hits)do if hit.kind=='zone'and#(hit.cards or{})==count and hit.label:find('Battlefield',1,true)then zone=hit;break end end
  check(zone~=nil,'Crowded battlefield has an exact-instance browser entry')
  click(zone);check(m.zoneView and#m.zoneView.cards==count,'Opening the battlefield browser retains every object')
  snapshot('zone-'..count..'-'..variant)
  click(inputs['zone-search']);S.OnTextInput('token-'..count);wait(.15)
  local selected;for label,box in pairs(choices)do if label:find('#'..count..' Rat',1,true)==1 then selected=box end end
  check(selected~=nil,'Search reaches the last overlapped token by its native object identity')
  snapshot('exact-token-'..count..'-'..variant)
  local before=#calls;click(selected)
  check(#calls==before+1 and calls[#calls].body.type=='uuid'and calls[#calls].body.value=='token-'..count,'Actual browser click submits exactly the offered native token ID')
  local answer=calls[#calls];m:setGame({gameId='replacement-game',revision=1,running=false,players=m.game.players,stack=json.array(),log=json.array(),prompt={id=1,type='ask',choices=json.array({{id='new',responseType='boolean',value=false}})}})
  m.actionBusy=true;m.answeredPrompt=1;answer.callback(nil,'Late synthetic response',0)
  check(m.game.gameId=='replacement-game'and m.actionBusy and m.answeredPrompt==1,'A delayed failed response cannot unlatch a replacement game with reused prompt ID')
 end
 if evidenceType=='synthetic_rendering_fixture'and count==10 and stackCount==0 then
  local sequence=100
  local function offered(prompt,label,kind,value)
   sequence=sequence+1;prompt.id=sequence;m.game.prompt=prompt;m.game.running=true;m.game.revision=m.game.revision+1;m.actionBusy=false;m.answeredPrompt=nil;m.zoneView=nil;m.inspectCard=nil;m:setGame(m.game)
   wait(.16);local before=#calls;click(buttons[label])
   check(#calls==before+1 and calls[#calls].body.type==kind and json.encode(calls[#calls].body.value)==json.encode(value),'Actual '..kind..' UI control forwards only its offered response')
  end
  offered({type='ask',message='Offered boolean',choices={{id='false-native',label='Native false',responseType='boolean',value=false}}},'Native false','boolean',false)
  offered({type='choice',message='Offered string',choices={{id='native-label',label='Native string',responseType='string',value='native-value'}}},'Native string','string','native-value')
  offered({type='amount',message='Offered bounded amount',min=2,max=4,choices={}},'Confirm amount','integer',2)
  offered({type='multi_amount',message='Offered distribution',amountMessages={{message='First',min=1,max=3,defaultValue=1},{message='Second',min=1,max=3,defaultValue=2}},choices={}},'Confirm distribution','multi_amount',json.array({1,2}))
  offered({type='choose_mode',message='Offered mode',choices={{id='11111111-2222-3333-4444-555555555555',label='Native mode',responseType='uuid',value='11111111-2222-3333-4444-555555555555'}}},'Native mode','uuid','11111111-2222-3333-4444-555555555555')
  offered({type='order',message='Resolution order',choices={{id='trigger-b',label='Trigger B'},{id='trigger-a',label='Trigger A'}}},'Confirm order','order',json.array({'trigger-b','trigger-a'}))
  local source=m.game.players[1].battlefield[1]
  offered({type='pile',message='Offered piles',pile1={source},pile2={source},choices={{id='pile-one',label='Native pile one',responseType='boolean',value=true},{id='pile-two',label='Native pile two',responseType='boolean',value=false}}},'Native pile two','boolean',false)
  m.actionBusy=false;m.answeredPrompt=nil;sequence=sequence+1
  m.game.prompt={id=sequence,type='select',message='Offered mana choices',manaWheel={sourceId=source.id},choices={{id='offered-r',label='Native red mana',responseType='string',value='native-r',manaColors={'R'}},{id='offered-g',label='Native green mana',responseType='string',value='native-g',manaColors={'G'}}}}
  wait(.2);local mana={};for _,hit in ipairs(r.hits)do if hit.kind=='mana'then mana[#mana+1]=hit end end
  check(#mana==2,'Mana wheel contains only the two engine-offered choices')
  local before=#calls;click(mana[2]);check(#calls==before+1 and calls[#calls].body.type=='string'and calls[#calls].body.value=='native-g','Actual mana-wheel click forwards its offered ability value')
  m.actionBusy=false;m.answeredPrompt=nil;m.game.prompt={id=sequence+1,type='uncovered_fixture',message='Unknown native-shaped prompt stays unanswered',choices={}}
  before=#calls;wait(.15);check(#calls==before,'Unknown prompt is never answered by choosing a guessed fallback')
  m.api.status=function()return{oldestSeconds=3,pending=1,controlPending=true}end;m.concedePending=true
  wait(.15);snapshot('waiting-diagnostic');click(buttons.Settings);check(m.settingsOpen,'Settings input remains responsive while a synthetic engine response is pending')
  snapshot('waiting-settings');click(buttons.Close);check(not m.settingsOpen and m.game.running,'Closing Settings does not fabricate a native game outcome')
  m.concedePending=false;m.api.status=function()return{oldestSeconds=0,pending=0}end
  m.game.execution={stopRequested=true,terminationConfirmed=false,threadAlive=true,status='stop_requested'};wait(.2)
  local stopping=false;for _,name in ipairs(Window.GetStackDebug())do if name:find('engine-transport-status',1,true)then stopping=true end end
  check(stopping and not m:prompt(),'Unconfirmed native stop remains visible and suppresses obsolete input after HTTP completion')
  snapshot('native-stop-unconfirmed');m.game.execution.terminationConfirmed=true;m.game.execution.threadAlive=false;wait(.2)
  stopping=false;for _,name in ipairs(Window.GetStackDebug())do if name:find('engine-transport-status',1,true)then stopping=true end end
  check(not stopping and m.game.running,'Thread termination metadata retires waiting UI without inventing a game result')
 end
 local mutateHosts={}
 for _,player in ipairs(m.game and m.game.players or{})do for _,card in ipairs(player.battlefield or{})do if card.mutate and#(card.mutate.components or{})>0 then mutateHosts[#mutateHosts+1]=card end end end
 for hostIndex,mutateHost in ipairs(mutateHosts)do
  if evidenceType=='synthetic_rendering_fixture'then m.game.execution=nil;m.game.prompt=nil end
  m.actionBusy=false;m.zoneView=nil;m.settingsOpen=false;m.inspectCard=nil;wait(.15)
  local hit;for _,entry in ipairs(r.hits)do if entry.card and entry.card.id==mutateHost.id and entry.kind=='permanent'then hit=entry;break end end
  click(hit,2);check(m.inspectCard and m.inspectCard.id==mutateHost.id,'Merged permanent opens its actual host inspector')
  local top;for _,component in ipairs(mutateHost.mutate.components)do if component.id==mutateHost.mutate.topId then top=component end end;top=top or mutateHost.mutate.components[1]
  local label=(top.id==mutateHost.mutate.topId and'Top · 'or'Component · ')..top.name;local control=scrollSelectable(label);local before=#calls;click(control)
  check(v.inspectMutateComponentId==top.id and m.inspectCard.id==mutateHost.id and#calls==before,'Inspecting a mutate component keeps one host object and sends no independent target action')
  local region=choiceRegions[label];move({x=region.x+region.w*.8,y=region.y+region.h*.5,w=0,h=0});S.OnWheelMoved(0,-100);wait(.16)
  snapshot('mutate-component-inspection'..(#mutateHosts>1 and'-'..hostIndex or''))
  S.OnWheelMoved(0,100);wait(.16);click(buttons['Close details']);check(not m.inspectCard,'Merged host details close through the actual inspector control')
 end
 local stats=love.graphics.getStats();metrics.textureMemoryBytes=stats.texturememory;metrics.luaMemoryKiB=collectgarbage('count');metrics.drawCalls=stats.drawcalls
 local save=love.filesystem.getSaveDirectory();check(save:find(assert(os.getenv('XDG_DATA_HOME')),1,true)==1,'Actual LÖVE preference/save directory remains inside the owned temporary XDG root')
 local trace={};for _,call in ipairs(calls)do trace[#trace+1]={service=call.service,path=call.path,body=call.body}end
 write('result.json',{status='pass',scenarioId=evidenceType=='native_projection_client_render'and'client-native-projection'or'client-'..count..'-'..variant..'-stack'..stackCount,evidenceType=evidenceType,checks=checks,attempts=#calls,acceptedNativeActions=0,nativeEvents=0,gameId=m.game and m.game.gameId,lastPrompt=m:prompt(),actionTrace=trace,metrics=metrics,captures=captures,physical={love.graphics.getDimensions()},logical={Layout.dimensions()},rendererInfo={love.graphics.getRendererInfo()},scope='Actual LÖVE/Slab input and rendering; synthetic native-shaped projections unless an explicit independently captured native frame is supplied. No native rules execute here; no network or user saves.'})
 print('MECHANICS CLIENT UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Window=require('lib.Slab.Internal.UI.Window');Region=require('lib.Slab.Internal.UI.Region')
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(b)return down[b]==true end;love.keyboard.isDown=function(k)return keys[k]==true end
 m=Model.new();m.loaded=true;m.settingsLoaded=true;m.catalogHealth={ready=false};m.settings.showCardArt=false;m.settings.skybox='Off';m.settings.sfxEnabled=false;m.settings.particles=false;m.settings.animations=false;m.settings.showTooltips=true;m.settings.windowMode='Windowed';m.settings.resolution='1440x900';m.settings.uiScale=1;m.settings.renderScale=1;m.settings.vsync=false;m.settings.frameLimit=0
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p.appliedLoaded=true;p:apply(true)
 for _,name in ipairs({'Button','Input','TextSelectable'})do local old=S[name];S[name]=function(label,options)local result=old(label,options);(name=='Input'and inputs or name=='TextSelectable'and choices or buttons)[label]=bounds();if name=='TextSelectable'then local x,y,w,h=Region.GetBounds();choiceRegions[label]={x=x,y=y,w=w,h=h}end;return result end end
 local oldField=Table.field;Table.field=function(...)local began=love.timer.getTime();oldField(...);fieldTotal=fieldTotal+love.timer.getTime()-began end
 local oldDraw=r.drawPermanent;r.drawPermanent=function(self,...)local began=love.timer.getTime();local value=oldDraw(self,...);drawTotal=drawTotal+love.timer.getTime()-began;return value end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;frame=frame+1;assert(clock<50,'UI fixture deadline exceeded');p:update();S.Update(dt);r:update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 buttons={};inputs={};choices={};choiceRegions={};v:build();r.uiHovered=not S.IsVoidHovered()
end
function love.draw()
 drawTotal=0;fieldTotal=0;local began=love.timer.getTime();p:beginFrame();r:draw();p:endScene();S.Draw({DeferOverlays=true})
 love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();love.graphics.pop();S.DrawOverlays();p:endFrame();love.graphics.flushBatch()
 if phase=='measure'then
  frameTimes[#frameTimes+1]=love.timer.getTime()-began;fieldTimes[#fieldTimes+1]=fieldTotal;drawTimes[#drawTimes+1]=drawTotal
  local hit=love.timer.getTime();for i=1,20 do r:mousemoved(-20,-20)end;hitTimes[#hitTimes+1]=(love.timer.getTime()-hit)/20
 end
 if#shots>0 then local name=table.remove(shots,1);local path=out..'/'..name..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local f=assert(io.open(path,'wb'));f:write(data:encode('png'):getString());f:close()end)end
 love.timer.sleep(.008)
end
function love.quit()if p then p:quit()end;S.OnQuit()end
function love.errorhandler(message)write('failure.json',{status='fail',error=tostring(message),trace=debug.traceback(),metrics=metrics});io.stderr:write(tostring(message)..'\n'..debug.traceback()..'\n');return function()return 1 end end
