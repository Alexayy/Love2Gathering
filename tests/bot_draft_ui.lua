-- Actual Slab/main input over simulated native capabilities and room responses.
local json=require('lib.json');local requests={};local gateway
package.preload['app.api']=function()return{escape=function(value)return tostring(value)end,new=function()return{
 request=function(_,service,method,path,body,callback)
  if service=='room'and method=='POST'then
   requests[#requests+1]={service=service,method=method,path=path,body=json.decode(json.encode(body or{}))};local data=gateway(path,body or{});if callback then callback(data,nil,200)end
  elseif callback then callback(nil,nil,404)end
 end,update=function()end,quit=function()end,setNativeSession=function()end,setRoomSession=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout')
assert(love.filesystem.load('application-main.lua'))()
local output=assert(os.getenv('L2G_BOT_DRAFT_OUTPUT'));local m,r,v,p,runner
local clock,wake=0,0;local mouse={x=2,y=2};local down,dispatch,buttons,combos,selectables,texts,shots,checks,captures,modes={},{},{},{},{},{},{},{},{},{}
local popups={}
local wheelTrace={}
local function clone(value)return json.decode(json.encode(value))end
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('BOT DRAFT UI PASS '..label);io.stdout:flush()end
local function wait(t)wake=clock+(t or .08);coroutine.yield()end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;dispatch.mousemoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy,false)end
local function click(box)
 assert(box,'Missing actual Slab control');move(box.x+box.w/2,box.y+box.h/2);wait(.05);down[1]=true;dispatch.mousepressed(mouse.x,mouse.y,1,false,1);wait(.05);down[1]=nil;dispatch.mousereleased(mouse.x,mouse.y,1,false,1);wait(.12)
end
local wheel
local function pickOpen(id,label)
 for _=1,15 do
  local box=assert(selectables[label],label);local popup=assert(popups[id],id)
  if box.y>=popup.y+3 and box.y+box.h<=popup.y+popup.h-3 then click(box);return end
  move(popup.x+popup.w/2,popup.y+popup.h/2);wait(.04);dispatch.wheelmoved(0,box.y<popup.y and 5 or-5);wait(.1)
 end
 error('Could not scroll native menu option into view: '..label)
end
local function choose(id,label)
 if id:match('^bot%-draft%-')then
  local _,h=Layout.dimensions()
  for _=1,15 do local box=assert(combos[id],id);if box.y>=190 and box.y+box.h<=h-110 then break end;wheel(box.y<190 and 10 or-10)end
 end
 click(assert(combos[id],id));check(selectables[label]~=nil,'Native option is present in '..id..': '..label..(not selectables[label]and' / '..json.encode({combo=combos[id],popup=popups[id],mode=m.roomSetup and m.roomSetup.draft,hot=require('lib.Slab.Internal.UI.Region').GetHotInstanceId(),pointer=mouse,wheel=wheelTrace})or''))
 local offered={};for name in pairs(selectables)do offered[name]=true end;pickOpen(id,label);return offered
end
wheel=function(delta,box)
 local w,h=Layout.dimensions();move(box and box.x+20 or 200,box and box.y+box.h/2 or h-230);wait(.05);local Region=require('lib.Slab.Internal.UI.Region');local before=Region.GetHotInstanceId();dispatch.wheelmoved(0,delta);wait(.14)
 local data={before=before,after=Region.GetHotInstanceId(),delta=delta};for _,id in ipairs(Region.GetInstanceIds())do if id:find('bot-draft-fields',1,true)then data.region=Region.GetDebugInfo(id)end end
 wheelTrace[#wheelTrace+1]=data;if#wheelTrace>3 then table.remove(wheelTrace,1)end
end
local function buttonPrefix(prefix)for name,box in pairs(buttons)do if name:sub(1,#prefix)==prefix then return box,name end end end
local function reveal(prefix)
 local _,h=Layout.dimensions()
 for _=1,10 do local box=buttonPrefix(prefix);if box and box.y>=170 and box.y+box.h<h-100 then return box end;wheel(-8)end
 error('Could not expose form control '..prefix)
end
local function shot(name)shots[#shots+1]=name;wait(.1)end
local caps={game={formats={'Modern','Legacy','Vintage','Commander'},minPlayers=2,maxPlayers=6},draft={botSupport=true,minPlayers=4,maxPlayers=16,packCount=3,
 modes={{id='booster',label='Traditional booster draft',minPlayers=4,maxPlayers=16,packCount=3},{id='cube',label='Native cube draft',minPlayers=4,maxPlayers=16},{id='random',label='Random booster draft',minPlayers=4,maxPlayers=16}},
 profiles={{id='Limited',label='Native Limited 40'}},pairings={{id='swiss',label='Native Swiss'}},timings={{id='regular',label='Native regular clock'}},
 sets={{id='M21',name='Core Set 2021'},{id='THB',name='Theros Beyond Death'},{id='M20',name='Core Set 2020'}},cubes={{id='cube-one',label='Native cube one'},{id='cube-two',label='Native cube two'}}}}
local fakeRoom,roomRevision= nil,0
gateway=function(path,body)
 roomRevision=roomRevision+1
 if path=='/client/rooms'then fakeRoom={id='synthetic-room',name='Bot draft',hostId='local-seat',phase='lobby',config=clone(body),members={{id='local-seat',name='Synthetic drafter',ready=false}},revision=roomRevision}
 elseif path:match('/bots$')then for i=1,body.count do fakeRoom.members[#fakeRoom.members+1]={id='bot-'..i,name='Synthetic bot '..i,bot=true,ready=true}end
 elseif path:match('/ready$')then fakeRoom.members[1].ready=body.ready
 elseif path:match('/start$')then fakeRoom.phase='drafting'
 else error('Unexpected simulated room mutation '..path)end
 fakeRoom.revision=roomRevision
 local data={connectionId='synthetic-draft-connection',participantId='local-seat',room=clone(fakeRoom),capabilities=clone(caps)}
 if fakeRoom.phase=='drafting'then data.draft={id='synthetic-native-draft',status='drafting',revision=1,packNumber=1,packCount=3,pickNumber=1,pickToken='synthetic-pick',secondsRemaining=45,pool={},pack={{id='synthetic-card-1',name='Synthetic native pack card',type='Creature',manaCost='{1}{G}',rules='Native-shaped offered fixture',power='2',toughness='2'}}}end
 return data
end
local function reset()
 m.page='lobby';m.lobbyMode='constructed';m.game=nil;m.roomConnectionId=nil;m.room=nil;m.roomDraft=nil;m.roomBusy=false;m.botDraftBusy=false;m.botDraftInitialized=nil;m.roomSetup=nil;m.roomCapabilities=clone(caps);m.roomPhaseLast=nil;m.roomDraftStage=nil;m.roomParticipantId=nil;m.botDraftGeneration=(m.botDraftGeneration or 0)+1
 m.nativeCapabilities={formatDetails={{id='Modern',supported=true,construction='constructed'},{id='Legacy',supported=true,construction='constructed'},{id='Vintage',supported=true,construction='constructed'},{id='Limited',supported=true,construction='limited'},{id='Unavailable',supported=false}}};m:setLobbyFormat('Modern');requests={};fakeRoom=nil;roomRevision=0;move(2,2)
end
local function scenario()
 for _,mode in ipairs({{1120,720,1},{2560,1080,1},{2560,1080,1.25}})do
  m.settings.resolution=mode[1]..'x'..mode[2];m.settings.uiScale=mode[3];m.settings.renderScale=1;p:apply(true);reset();wait(.2)
  local w,h=Layout.dimensions();local suffix=mode[1]..'-ui'..Layout.scale;modes[#modes+1]={physical={love.graphics.getDimensions()},logical={w,h},uiScale=Layout.scale}
  choose('format','Legacy');check(m.format=='Legacy','Actual Constructed format selector accepts installed Legacy: '..suffix)
  local offered=choose('format','Vintage');check(m.format=='Vintage','Actual Constructed format selector accepts installed Vintage: '..suffix)
  check(not offered.Limited and not offered.Unavailable,'Constructed selector excludes Limited and unsupported native formats: '..suffix)
  click(buttons['Draft with bots']);check(m.lobbyMode=='draft'and m.roomSetup.maxPlayers==8,'The actual Draft with bots shortcut opens eight native seats by default: '..suffix)
  check(m.roomSetupMinPlayers==4 and m.roomSetupMaxPlayers==16,'Draft seat bounds come from the installed capability range: '..suffix)
  wheel(25);click(combos['bot-draft-count']);check(selectables['You + 3 bots']and selectables['You + 15 bots']and not selectables['You + 2 bots']and not selectables['You + 16 bots'],'Actual seat menu covers native4–16 seats only: '..suffix);pickOpen('bot-draft-count','You + 3 bots');check(m.roomSetup.maxPlayers==4,'Minimum native seat count is selectable: '..suffix)
  choose('bot-draft-count','You + 15 bots');check(m.roomSetup.maxPlayers==16,'Maximum native seat count is selectable: '..suffix);choose('bot-draft-count','You + 7 bots')
  choose('bot-draft-mode','Native cube draft');check(m.roomSetup.draft.mode=='cube','Actual procedure selector chooses the native cube mode: '..suffix)
  local beforeCube=combos['bot-draft-cube'].y;wheel(-12,combos['bot-draft-pairing'])
  if h<900 then check(combos['bot-draft-cube'].y<beforeCube-5,'A real wheel over the read-only combo scrolls the enclosing draft form: '..suffix)end
  check(not require('lib.Slab.Internal.UI.Region').GetHotInstanceId():find('_Input',1,true),'The ignored-scroll input preserves parent wheel ownership: '..suffix)
  choose('bot-draft-cube','Native cube two');check(m.roomSetup.draft.cubeId=='cube-two','Cube selector uses the offered exact native cube ID: '..suffix);shot('native-cube-'..suffix)
  wheel(30);choose('bot-draft-mode','Random booster draft');check(m.roomSetup.draft.mode=='random','Random draft remains an explicit native procedure: '..suffix);wheel(-12);check(texts['XMage chooses from its supported random booster pool.'],'Random mode explains the native eligible-set pool: '..suffix)
  wheel(30);choose('bot-draft-mode','Traditional booster draft');check(m.roomSetup.draft.mode=='booster','Traditional mode restores booster selection: '..suffix)
  local pack=reveal('Pack 1 · ');click(pack);check(v.setPicker and v.setPicker.allowAll==false,'Actual pack button opens the shared grid with All sets disabled: '..suffix)
  check(buttons['set-tile-m21']and buttons['set-tile-thb']and buttons['set-tile-m20']and not buttons['set-tile-all-sets'],'Pack grid contains exactly offered booster sets and no All sets tile: '..suffix)
  check(texts['3 matching sets'],'The no-All booster grid reports its true offered set count: '..suffix)
  for _,code in ipairs({'m21','thb','m20'})do local box=buttons['set-tile-'..code];check(box.x>=0 and box.y>=0 and box.x+box.w<=w and box.y+box.h<=h,'Actual booster tile stays within the scaled popup: '..suffix..' '..code)end
  shot('booster-grid-'..suffix);click(buttons['set-tile-thb']);check(not v.setPicker and m.roomSetup.draft.sets[1]=='THB','Selecting a booster tile preserves its exact native set code: '..suffix)
  m.roomConnectionId='existing-synthetic-room';wait(.1);local before=#requests;check(buttons['Start bot draft'].disabled,'An existing private room disables starting another bot draft: '..suffix);click(buttons['Start bot draft']);check(#requests==before,'Disabled Start cannot create a second room: '..suffix)
  m.roomConnectionId=nil;wheel(30);wait(.1);shot('draft-setup-'..suffix)
  local start=buttons['Start bot draft'];check(start and start.y>=h-70 and start.y+start.h<=h,'Draft Start has a separate visible footer with padding: '..suffix);click(start)
  check(#requests==4 and requests[1].path=='/client/rooms'and requests[2].path=='/client/rooms/synthetic-draft-connection/bots'and requests[3].path=='/client/rooms/synthetic-draft-connection/ready'and requests[4].path=='/client/rooms/synthetic-draft-connection/start','One actual Start chains create, bots, ready and native draft start in order: '..suffix)
  local body=requests[1].body;check(body.kind=='draft'and body.maxPlayers==8 and body.draft.mode=='booster'and body.draft.profile=='Limited'and body.draft.pairing=='swiss'and body.draft.timing=='regular'and body.draft.sets[1]=='THB','The created room carries the exact selected native draft options: '..suffix)
  check(requests[2].body.count==7 and requests[3].body.ready==true and next(requests[4].body)==nil,'The shortcut requests seven bots, readies only the local seat, then starts without inventing picks: '..suffix)
  wait(.15);check(m.page=='draft'and m.roomDraft.id=='synthetic-native-draft'and buttons['Synthetic native pack card']and texts['Your pack · pick 1'],'An actual native-shaped draft projection opens the existing offered-pack Draft UI: '..suffix);shot('native-pack-projection-'..suffix)
 end
 local report={checks=checks,captures=captures,modes=modes,requests=requests,scope='Actual production Slab/main clicks, scrolling, capability-driven setup and room request chain with simulated native capabilities/responses. No real boosters, native draft/game, network, saves or user cache.'}
 local out=assert(io.open(output..'/report.json','w'));out:write(json.encode(report));out:close();print('BOT DRAFT UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return down[button]==true end
 m=Model.new();m.loaded=true;m.settingsLoaded=true;m.profileLoaded=true;m.settings.windowMode='Windowed';m.settings.skybox='Off';m.settings.showCardArt=false;m.settings.animations=false;m.settings.reducedMotion=true;m.settings.particles=false;m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.vsync=false;m.settings.showTooltips=false;m.uiLayout={};m.catalogHealth={ready=false};m.engineHealth={ok=true};m.profile={};m.playerName='Synthetic drafter';m.logOpen=false;m.stackOpen=false
 m.decks={};for _,format in ipairs({'Modern','Legacy','Vintage'})do m.decks[#m.decks+1]={id='synthetic-'..format,name='Synthetic '..format,format=format,origin='user',main={},sideboard={},commander={}}end
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p.appliedLoaded=true
 for i=1,30 do local name=debug.getupvalue(love.keypressed,i);if not name then break end;if name=='model'then debug.setupvalue(love.keypressed,i,m)elseif name=='renderer'then debug.setupvalue(love.keypressed,i,r)elseif name=='view'then debug.setupvalue(love.keypressed,i,v)end end
 for _,name in ipairs({'mousemoved','mousepressed','mousereleased','wheelmoved','keypressed','keyreleased','textinput'})do dispatch[name]=love[name];love[name]=function()end end
 local Cursor=require('lib.Slab.Internal.Core.Cursor');local Window=require('lib.Slab.Internal.UI.Window');local function bounds()local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);return{x=x,y=y,w=w,h=h}end
 local button=S.Button;S.Button=function(label,options)local result=button(label,options);local record=bounds();record.disabled=options and options.Disabled;buttons[label]=record;return result end
 local combo=S.BeginComboBox;S.BeginComboBox=function(id,options)local result=combo(id,options);if not result then combos[id]=bounds()else local x,y,w,h=Window.GetBounds(true);popups[id]={x=x,y=y,w=w,h=h}end;return result end
 local selectable=S.TextSelectable;S.TextSelectable=function(label,options)local result=selectable(label,options);selectables[label]=bounds();return result end
 for _,kind in ipairs({'Text','Textf'})do local original=S[kind];S[kind]=function(label,options)texts[label]=true;return original(label,options)end end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<65,'Bot draft GUI timed out');S.Update(dt);r:update(dt);r.uiHovered=not S.IsVoidHovered()
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,error=coroutine.resume(runner);assert(ok,error)end
 buttons={};selectables={};texts={};v:build()
end
function love.draw()
 p:beginFrame();r:draw();p:endScene();S.Draw({DeferOverlays=true});love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();love.graphics.pop();S.DrawOverlays();p:endFrame()
 if#shots>0 then local path=output..'/'..table.remove(shots,1)..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local out=assert(io.open(path,'wb'));out:write(data:encode('png'):getString());out:close()end)end
end
function love.quit()if p then p:quit()end;S.OnQuit()end
function love.errorhandler(message)local problem=debug.traceback(tostring(message),2);io.stderr:write(problem..'\n');local out=assert(io.open(output..'/failure.txt','w'));out:write(problem);out:close();return function()return 1 end end
