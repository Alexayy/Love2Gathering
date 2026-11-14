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
check(options.autoPass and #options.stops.own==0 and #options.stops.opponent==0,'Automatic priority defaults have no invented stops')
m.uiLayout={matchPrefs={phaseMarkers={END='WAIT',COMBAT='SKIP'}}}
options=m:priorityOptions()
check(options.stops.own[1]=='END_TURN' and options.stops.opponent[1]=='END_TURN' and #options.stops.own==1,'Only explicit legacy WAIT intentions migrate to real native stops')
m.uiLayout={};m:togglePhaseStop(Priority.groups[6],'opponent')
check(#calls==0 and m:phaseStop(Priority.groups[6],'opponent') and not m:phaseStop(Priority.groups[6],'own'),'Own and opponent stops stay separate and can be saved before a game')
local encoded=json.encode(m:priorityOptions());check(encoded:find('"own":[]',1,true),'Empty stop lists remain JSON arrays')
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
check(command.body.autoPass==false,'Full control is an explicit native configuration')
m:setGame(game('new'));m:cancelYield();local current=calls[#calls]
command.callback(game('g'))
check(m.game.gameId=='new' and m.priorityBusy,'Late command replies cannot replace a new match or release its controls')
current.callback(game('new'));check(not m.priorityBusy,'Current match acknowledgement is accepted')
print('Priority model checks: '..n..' passed')
