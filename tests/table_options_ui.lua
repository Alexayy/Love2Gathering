-- Actual LÖVE/Slab table-options input with delayed, controlled transport replies.
-- Native legality and separate human policies are accepted in PriorityFixture /
-- room HTTP tests. This fixture never opens a native game or a user data store.
function love.errorhandler(message)
 io.stderr:write('TABLE OPTIONS FAILED '..tostring(message)..'\n'..debug.traceback()..'\n')
 return function()return 1 end
end
local ledger,pending={},{ }
package.preload['app.api']=function()return{escape=tostring,new=function()return{
 request=function(_,service,method,path,body,callback)
  local json=require('lib.json');local entry={service=service,method=method,path=path,body=body and json.decode(json.encode(body)),callback=callback}
  ledger[#ledger+1]=entry
  if path=='/session/priority'or path=='/session/action'then pending[#pending+1]=entry elseif callback then callback({saved=true})end
  return true
 end,update=function()end,quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences')
local Layout=require('app.layout');local Window=require('lib.Slab.Internal.UI.Window');local Cursor=require('lib.Slab.Internal.Core.Cursor');local json=require('lib.json')
local output=assert(os.getenv('LOVE2GATHERING_TABLE_OPTIONS_OUTPUT'))
local m,r,v,p,runner;local mouse={x=2,y=2};local down=false;local clock,wake=0,0;local controls={};local checks,shots={},{};local capture
local auto='Auto-pass empty priority';local mana='Include mana-only windows'
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('TABLE OPTIONS PASS '..label)end
local function wait(seconds)wake=clock+(seconds or .08);coroutine.yield()end
local function count(path)local n=0;for _,entry in ipairs(ledger)do if entry.path==path then n=n+1 end end;return n end
local function copy(value)return json.decode(json.encode(value))end
local function click(label)
 local box=assert(controls[label],'Missing actual Slab control '..label)
 local x,y=mouse.x,mouse.y;mouse.x=(box.x+math.min(box.w/2,12))*Layout.scale;mouse.y=(box.y+box.h/2)*Layout.scale
 S.OnMouseMoved(mouse.x,mouse.y,mouse.x-x,mouse.y-y);wait(.06)
 down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.06)
 down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.14)
end
local function shot(name)capture=name;wait(.1);shots[#shots+1]=name end
local function latest(path)for i=#ledger,1,-1 do if ledger[i].path==path then return ledger[i]end end end
local function cardHit(id,kind)
 for _,box in ipairs(r.hits)do if box.card and box.card.id==id and(not kind or box.kind==kind)then return box end end
end
local function compactTargets(label)
 local top=assert(cardHit('library-top-native','library-top'),label..' lacks native library-top target')
 local exile=assert(cardHit('exile-native','exile-hand'),label..' lacks native exile extension')
 local w,h=Layout.dimensions()
 check(top.x>=0 and top.y>=0 and top.x+top.w<=w and top.y+top.h<=h and m:canSelect(top.card.id),label..' keeps the offered library card visible and actionable beside the exile extension')
 check(exile.x>=0 and exile.y>=r.tableLayout.viewport.y and exile.y+exile.h<h-40 and exile.y+exile.h<=r.tableLayout.safe.handY,label..' keeps the native exile extension above the hand while overlaying terrain')
end
local function acknowledge(entry)
 local state=copy(m.game);state.revision=state.revision+1;state.prompt.id=state.prompt.id+1
 for _,key in ipairs({'autoPass','passWithOnlyMana','stops'})do state.priority[key]=copy(entry.body[key])end
 entry.callback(state);wait(.12)
end
local function fixture()
 local players={}
 for i=1,2 do players[i]={id='p'..i,name=i==1 and'Options fixture'or'Opponent fixture',human=i==1,isHuman=true,life=20,hand={},battlefield={},graveyard={},exile={},command={},commanders={},libraryCount=53,mana={}}end
 players[1].libraryTop={id='library-top-native',name='Forest',type='Basic Land — Forest',ownerId='p1'};players[1].libraryTopVisibility='public'
 players[1].exile={{id='exile-native',name='Native exile fixture',type='Instant',ownerId='p1'}}
 players[1].hand={{id='hand-native',name='Plains',type='Basic Land — Plains',ownerId='p1'}}
 return{gameId='SYNTHETIC-TABLE-OPTIONS',revision=1,running=true,turn=3,phase='Precombat Main',step='PRECOMBAT_MAIN',activePlayerId='p1',priorityPlayerId='p1',players=players,stack={},log={},
  priority={autoPass=false,passWithOnlyMana=false,manaOnlyPolicySupported=true,canEndTurn=true,stops={own={'UPKEEP'},opponent={'DECLARE_BLOCKERS'}}},
  prompt={id=10,type='select',priority=true,actionable={'library-top-native','exile-native'},choices={{id='done',label='Done',responseType='boolean',value=true}},
   cardActions={{objectId='exile-native',sourceZone='EXILED',options={{id='native-exile-cast',label='Cast',kind='spell'}}}}}}
end
local function scenario()
 wait(.2);check(not v.tableOptionsOpen and not m:priorityOptions().autoPass,'New player opens the table with manual priority')
 compactTargets('1366×768 compact duel');shot('duel-exile-library-1366')
 click('Table options');check(v.tableOptionsOpen and controls[auto]and controls[mana],'Actual Table options button exposes both native priority policies')
 local w,h=Layout.dimensions();for _,label in ipairs({auto,mana})do local b=controls[label];check(b.x>=0 and b.y>=0 and b.x+b.w<=w and b.y+b.h<=h,label..' stays inside the supported table viewport')end
 click(auto);local first=assert(latest('/session/priority'))
 check(first.method=='POST'and first.body.command=='configure'and first.body.autoPass==true and first.body.passWithOnlyMana==false,'Actual automatic-priority checkbox sends complete native configure policy')
 check(first.body.stops.own[1]=='UPKEEP'and first.body.stops.opponent[1]=='DECLARE_BLOCKERS','Configuring automatic passing preserves separate explicit native stops')
 check(m.priorityBusy and controls[auto].disabled and controls[mana].disabled,'Delayed native acknowledgement disables both policy controls')
 local before=count('/session/priority');click(auto);click(mana)
 check(count('/session/priority')==before,'Clicking disabled policy controls cannot enqueue duplicate native commands')
 local saved=assert(latest('/ui-layout'))
 check(saved.method=='PUT'and saved.body.matchPrefs.priority.autoPass==true and saved.body.matchPrefs.priority.passWithOnlyMana==false,'Automatic passing is persisted in this player’s saved UI preference')
 acknowledge(first);check(not m.priorityBusy and m.game.priority.autoPass==true,'Only the controlled native acknowledgement releases the policy controls')
 click(mana);local second=assert(latest('/session/priority'))
 check(count('/session/priority')==before+1 and second.body.autoPass==true and second.body.passWithOnlyMana==true,'Actual mana-only checkbox explicitly opts into ignoring only native mana abilities')
 acknowledge(second);wait(.45);saved=assert(latest('/ui-layout'))
 check(saved.body.matchPrefs.priority.passWithOnlyMana==true and m:priorityOptions().passWithOnlyMana,'Mana-only opt-in survives this player’s save operation')
 shot('table-options-opted-in')
 m.roomGameActive=true;m.roomDisconnected=true;m.roomTransport={state='reconnecting',message='Reconnecting · current choices preserved'};wait(.15)
 local prompt=m:prompt();local policy=json.encode(m:priorityOptions());before=count('/session/priority');local saves=count('/ui-layout')
 check(controls[auto].disabled and controls[mana].disabled,'Room reconnect leaves both preference controls visibly disabled')
 click(auto);click(mana);wait(.45)
 check(count('/session/priority')==before and count('/ui-layout')==saves and json.encode(m:priorityOptions())==policy,'Actual offline checkbox clicks neither send commands nor replace saved player preferences')
 check(m:prompt()==prompt and not m.priorityBusy,'The unanswered native choice remains readable during reconnect')
 shot('table-options-reconnecting')
 m.roomDisconnected=false;m.roomTransport={state='connected'};wait(.12);click(auto);local manual=assert(latest('/session/priority'))
 check(manual.body.autoPass==false and manual.body.passWithOnlyMana==true,'Reconnect allows explicit Full Control while retaining the separate mana-only preference')
 acknowledge(manual);wait(.45)
 m.game.priority.manaOnlyPolicySupported=false;wait(.12);before=count('/session/priority');click(mana)
 check(controls[mana].disabled and count('/session/priority')==before,'An unsupported native policy is disabled instead of guessed by the client')
 m.game.priority.manaOnlyPolicySupported=true;wait(.1);click('Close options');check(not v.tableOptionsOpen,'Actual Close options button returns to the same match')
 check(m.game.gameId=='SYNTHETIC-TABLE-OPTIONS'and m.game.prompt.id==13,'Policy controls retain match and current native prompt identity')
 love.window.setMode(1120,720,{vsync=0});Layout.setScale(1);wait(.2)
 compactTargets('1120×720 compact duel');shot('duel-exile-library-1120')
 local top=assert(cardHit('library-top-native','library-top'));local x,y=top.x+top.w/2,top.y+8
 mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,0,0);r:mousemoved(x,y);wait(.08)
 down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);r:mousepressed(x,y,1,1);wait(.07)
 down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);r:mousereleased(x,y,1);wait(.1)
 local action=latest('/session/action')
 check(action and action.body.type=='uuid'and action.body.value=='library-top-native'and action.body.promptId==13,'Actual compact library-card click routes its current offered UUID and prompt')
 local refreshed=copy(m.game);refreshed.revision=refreshed.revision+1;refreshed.prompt.id=14
 refreshed.prompt.undoChoice={id='undo-native',label='Undo last mana action',responseType='string',value='undo-native-value'}
 action.callback(refreshed);wait(.15)
 check(controls['Undo last mana action']and not controls['Undo last mana action'].disabled,'A native offered mana-undo action remains available in the compact toolbar')
 before=count('/session/action');m.roomDisconnected=true;wait(.12);click('Undo last mana action')
 check(controls['Undo last mana action'].disabled and count('/session/action')==before,'Offline mana-undo control is visibly disabled and cannot consume a native choice')
 m.roomDisconnected=false;wait(.12);click('Undo last mana action');local undo=latest('/session/action')
 check(count('/session/action')==before+1 and undo.body.promptId==14 and undo.body.type=='string'and undo.body.value=='undo-native-value','Actual mana-undo click uses only the current offered native response')
 local afterUndo=copy(m.game);afterUndo.revision=afterUndo.revision+1;afterUndo.prompt.id=15;afterUndo.prompt.undoChoice=nil;undo.callback(afterUndo);wait(.15)
 click('Table options');check(v.tableOptionsOpen,'Actual Table options opens immediately before a remote terminal result')
 local ended=copy(m.game);ended.revision=ended.revision+1;ended.running=false;ended.prompt=json.null;ended.players[1].won=true;ended.players[2].lost=true
 ended.result={gameId=ended.gameId,completed=true,outcome='win'};m:setGame(ended);wait(.2)
 check(not v.tableOptionsOpen and v.inputLock=='match-complete','A completed duel retires its hidden options window and transfers input to the result')
 shot('terminal-options-lock-cleared')
 local menu=false;m.goMain=function(self)menu=true;self.page='decks'end;click('Main menu')
 check(menu and m.page=='decks'and v.inputLock==nil,'Actual Main menu button remains clickable after completion with Table options previously open')
 local log={};for _,entry in ipairs(ledger)do log[#log+1]={service=entry.service,method=entry.method,path=entry.path,body=entry.body}end
 local report={passed=true,scope='Actual LÖVE11.5/Slab Table options and checkbox mouse input with controlled delayed native transport acknowledgements, real model/persistence requests and isolated VFS. Synthetic native-contract duel; no native game, network or user store writes.',checks=checks,screenshots=shots,logicalSize={Layout.dimensions()},physicalSize={love.graphics.getDimensions()},ledger=log,userStoreModified=false}
 local file=assert(io.open(output..'/ui-report.json','w'));file:write(json.encode(report));file:close();love.event.quit(0)
end
function love.load(args)
 S.Initialize(args,true);love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down end
 for _,kind in ipairs({'Button','CheckBox'})do local original=S[kind];S[kind]=function(a,b,c)
  local result=original(a,b,c);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y)
  local options=kind=='CheckBox'and c or b;controls[kind=='CheckBox'and b or a]={x=x,y=y,w=w,h=h,disabled=options and options.Disabled==true}
  return result
 end end
 m=Model.new();m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.skybox='Off';m.settings.reducedMotion=true
 m.uiLayout={matchPrefs={priority={autoPass=false,passWithOnlyMana=false,stops={own={'UPKEEP'},opponent={'DECLARE_BLOCKERS'}}}}}
 m.cardData=function(_,card)return card end;m.getArt=function()return nil end
 m:setGame(fixture());m.page='table';r=Renderer.new(m);p=Preferences.new(m,S,r);p:applyFont();v=View.new(S,m,r)
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;m:updateUILayout(dt);r:update(dt);S.Update(dt);v:build();r.uiHovered=not S.IsVoidHovered()
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,message=coroutine.resume(runner);assert(ok,message)end
 assert(clock<25,'Table options acceptance timed out')
end
function love.draw()
 love.graphics.push();love.graphics.scale(Layout.scale);r:draw();love.graphics.pop();S.Draw({DeferOverlays=true})
 love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();require('app.card_choices').draw(v);require('app.zone_ui').ghost(v);love.graphics.pop();S.DrawOverlays()
 if capture then local name=capture;capture=nil;love.graphics.captureScreenshot(function(data)local bytes=data:encode('png');local file=assert(io.open(output..'/'..name..'.png','wb'));file:write(bytes:getString());file:close();bytes:release();data:release()end)end
end
