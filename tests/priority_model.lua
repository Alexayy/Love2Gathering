-- Transport and UI intentions only; PriorityFixture exercises native legality.
package.path='./?.lua;'..package.path
local calls={}
package.preload['app.api']=function() return {escape=tostring,new=function()return {
    request=function(_,service,method,path,body,callback) calls[#calls+1]={service=service,path=path,body=body,callback=callback} end,
    update=function()end,quit=function()end}end}end
love={math={random=function()return 1 end}}
local Model=require('app.model');local Priority=require('app.priority');local json=require('lib.json')
local n=0;local function check(ok,text)assert(ok,text);n=n+1;print('PRIORITY MODEL PASS '..text)end
local function game(id,prompt) return {gameId=id or 'g',revision=1,running=true,prompt=prompt or {id=3,type='select',priority=true,choices={}}}end
local m=Model.new();local options=m:priorityOptions()
check(not options.autoPass and not options.passWithOnlyMana and #options.stops.own==0 and #options.stops.opponent==0,'New players retain manual control and no invented stops')
m.uiLayout={matchPrefs={priority={autoPass=true,stops={own={},opponent={}}}}}
check(m:priorityOptions().autoPass and not m:priorityOptions().passWithOnlyMana,'Existing automatic preference is preserved while mana-only passing remains explicit')
m.uiLayout={matchPrefs={phaseMarkers={END='WAIT',COMBAT='SKIP'}}}
options=m:priorityOptions()
check(options.stops.own[1]=='END_TURN' and options.stops.opponent[1]=='END_TURN' and #options.stops.own==1,'Only explicit legacy WAIT intentions migrate to real native stops')
m.uiLayout={};m:togglePhaseStop(Priority.groups[6],'opponent')
check(#calls==0 and m:phaseStop(Priority.groups[6],'opponent') and not m:phaseStop(Priority.groups[6],'own'),'Own and opponent stops stay separate and can be saved before a game')
local encoded=json.encode(m:priorityOptions());check(encoded:find('"own":[]',1,true),'Empty stop lists remain JSON arrays')
m:togglePhaseStop(Priority.beforeDamage,'opponent')
check(m:phaseStop(Priority.beforeDamage,'opponent')and m:priorityOptions().stops.opponent[2]=='DECLARE_BLOCKERS','Before damage sends native after-blocker step independently from beginning of combat')
local nativeSteps={BEGIN_COMBAT=true,DECLARE_ATTACKERS=true,DECLARE_BLOCKERS=true,FIRST_COMBAT_DAMAGE=true,COMBAT_DAMAGE=true,END_COMBAT=true}
for _,group in ipairs(Priority.combatSteps)do check(nativeSteps[group.steps[1]],'Combat picker uses actual native priority step '..group.steps[1])end
m:setGame(game());m:togglePhaseStop(Priority.groups[1],'own')
local command=calls[#calls]
check(command.path=='/session/priority' and command.body.command=='configure' and command.body.stops.own[1]=='UPKEEP','Stop control sends canonical native step names')
local count=#calls;m:answer('uuid','card');m:endTurn()
check(#calls==count,'A pending priority update blocks stale card and End Turn answers')
command.callback(game())
check(not m.priorityBusy,'Native acknowledgement releases pending priority controls')
m:endTurn();command=calls[#calls]
check(command.body.command=='end_turn' and command.body.promptId==3,'End Turn identifies the current native priority prompt')
local pending=game();pending.priority={pending=true,yielding=true};command.callback(pending)
count=#calls;m:answer('boolean',true)
check(not m:prompt() and #calls==count,'Pending GAME acknowledgement hides the obsolete priority prompt after HTTP completes')
m.game.priority={pending=false,canEndTurn=false};m:answer('boolean',true)
check(not m:prompt() and #calls==count,'Auto-advance cannot revive an old snapshot prompt after pending clears')
m.game.priority={pending=false,canEndTurn=true}
m.game.prompt={id=4,type='pick_target',targets={'x'}};count=#calls
check(not m:endTurn() and #calls==count,'End Turn cannot answer targets or other game choices')
m.replay={id='r'};m:toggleAutoPass();m:togglePhaseStop(Priority.groups[6],'own');m:cancelYield()
check(#calls==count,'Replay cannot configure stops or submit priority commands')
m.game.priority={stops={own={'DRAW'},opponent={}}}
local savedStops=m:phaseStop(Priority.groups[2],'own') and not m:phaseStop(Priority.groups[6],'opponent');m.game.priority=nil
check(savedStops and not m:phaseStop(Priority.groups[6],'opponent'),'Replay stop indicators use saved native configuration and never invent legacy stops')
m.replay=nil;m.game.prompt={id=5,type='select',priority=true};m:toggleAutoPass();command=calls[#calls]
check(command.body.autoPass==true and command.body.passWithOnlyMana==false,'Automatic empty priority is an explicit native configuration')
m:setGame(game('new'));m:cancelYield();local current=calls[#calls]
command.callback(game('g'))
check(m.game.gameId=='new' and m.priorityBusy,'Late command replies cannot replace a new match or release its controls')
current.callback(game('new'));check(not m.priorityBusy,'Current match acknowledgement is accepted')
m:toggleManaOnlyPass();command=calls[#calls]
check(command.body.passWithOnlyMana==true and command.body.autoPass==true,'Mana-only preference travels with the complete native stop policy')
command.callback(game('new'));m.replay={id='recording'};count=#calls;m:toggleManaOnlyPass()
check(#calls==count,'A recording cannot change the live mana-only preference')
m.replay=nil;m.roomGameActive=true;m.roomDisconnected=true
local saved=json.encode(m:priorityOptions());local prompt=m:prompt()
check(not m:toggleAutoPass()and not m:toggleManaOnlyPass()and not m:togglePhaseStop(Priority.groups[1],'own'),
    'Disconnected room rejects policy changes without replacing saved player preferences')
check(not m:endTurn()and not m:cancelYield()and not m:priorityCommand('configure',{autoPass=true})and#calls==count,
    'Disconnected room cannot dispatch priority commands or consume a retained native prompt')
check(json.encode(m:priorityOptions())==saved and m:prompt()==prompt and not m.priorityBusy,
    'Disconnected priority controls preserve the unanswered prompt and local policy')
m.roomDisconnected=false;check(m:toggleAutoPass()and#calls==count+1,'Reconnected room can explicitly configure priority again')
print('Priority model checks: '..n..' passed')
