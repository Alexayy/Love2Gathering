-- Frontend routing/lifecycle contracts; native outcomes are tested separately.
package.path='./?.lua;'..package.path
local calls={}
package.preload['app.api']=function()
 local API={escape=function(value)return tostring(value)end}
 function API.new()
  return{routeGeneration=0,request=function(_,service,method,path,body,callback)calls[#calls+1]={service=service,method=method,path=path,body=body,callback=callback}end,
   update=function()end,quit=function()end,setNativeSession=function(self,id)if self.nativeSessionId~=id then self.nativeSessionId=id;self.routeGeneration=self.routeGeneration+1 end end}
 end
 return API
end
love={timer={getTime=function()return 0 end},math={random=function()return 1 end}}
local Model=require('app.model');local count=0
local function check(ok,text)assert(ok,text);count=count+1;print('CONCESSION MODEL PASS '..text)end
local function state(id,revision,execution,running)
 return{gameId=id,revision=revision,running=running~=false,execution=execution,players={},prompt={id=revision,type='ask',choices={}}}
end
local m=Model.new();m:setGame(state('practice',1));m.lastMatchRequest={format='Commander'}
m:concede();local request=calls[#calls]
check(request.path=='/session/action'and request.body.type=='concede'and request.body.expectedGameId=='practice','Local practice uses the native fenced concession endpoint')
check(not m:prompt(),'A pending concession hides obsolete choices before acknowledgement')
local before=#calls;m:answer('boolean',true);m:concede();check(#calls==before,'Pending concession prevents competing answers and duplicate concessions')
request.callback(state('practice',2,{concedeRequested=true,threadAlive=true,terminationConfirmed=false}))
check(m.game.running and not m.concedePending and not m:prompt(),'Native pending termination hides choices without inventing a finished game')
check(not m:canRematch(),'A rematch waits for actual native termination')
m:setGame(state('practice',3,{concedeRequested=true,threadAlive=false,terminationConfirmed=true},false))
check(m:canRematch(),'A truly terminated local practice retains its normal rematch flow')
before=#calls;m:concede();check(#calls==before,'Finished games cannot queue another concession')
local room=Model.new();room.roomConnectionId='room';room:setGame(state('room-game',1));room:concede();request=calls[#calls]
check(request.path=='/session/action'and request.body.type=='concede'and not request.body.stop and not request.body.stopBots,'Room concession stays a seat action with no client-supplied global-stop policy')
request.callback(state('room-game',2,{threadAlive=true,stopRequested=false}))
check(room.game.running and not room:canRematch(),'A seat concession acknowledgement never fabricates a finished multiplayer game')
room:setGame(state('replacement',1));request.callback(state('room-game',99,{threadAlive=false},false))
check(room.game.gameId=='replacement'and room.game.running,'An old concession callback cannot terminate a replacement game')
room.replay={};before=#calls;room:concede();check(#calls==before,'Replay playback never submits concession')
print('Concession model checks: '..count..' passed')
