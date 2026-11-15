-- Client contracts, never evidence of native Magic execution.
local calls={}
package.preload['app.api']=function()
 local API={escape=function(v)return tostring(v)end}
 function API.new()return{routeGeneration=0,request=function(_,service,method,path,body,callback)calls[#calls+1]={service=service,method=method,path=path,body=body,callback=callback}end,update=function()end,quit=function()end,setNativeSession=function(self,id)if id~=self.nativeSessionId then self.nativeSessionId=id;self.routeGeneration=self.routeGeneration+1 end end}end
 return API
end
love={timer={getTime=function()return 0 end},math={random=function()return 1 end}}
local Model=require('app.model');local json=require('lib.json');local m=Model.new();local checks={}
local function check(v,label)assert(v,label);checks[#checks+1]=label end
local function state(id,prompt,revision)return{gameId=id,revision=revision or 1,running=true,players={},prompt=prompt}end
m:setGame(state('old',{id=1,type='select',actionable={},choices={{id='visible',responseType='uuid'}}}))
check(not m:canSelect('visible'),'Present empty native actionable list overrides a visible UUID choice')
m.game.prompt.actionable={'offered'};check(m:canSelect('offered')and not m:canSelect('visible'),'Only native offered object IDs are actionable')
m.byName.Angel={id='catalog',name='Angel',power='2',toughness='2',oracle_text='Printing'}
local native={id='native',name='Angel',power='5',toughness='-1',damage=3,counters={['+1/+1']=4},printing={power='2',toughness='2'},colors={'B'},controllerId='controller'}
local rendered=m:cardData(native)
check(rendered.power=='5'and rendered.toughness=='-1'and rendered.damage==3 and rendered.printing.power=='2','Catalog enrichment retains negative live toughness, damage and separate printing values')
check(rendered.objectId=='native'and rendered.controllerId=='controller'and rendered.counters['+1/+1']==4,'Native identity, controller and counters survive enrichment')
m.game.prompt={id=3,type='ask',choices={{id='no',responseType='boolean',value=false}}};m:answerChoice(m.game.prompt.choices[1]);local old=calls[#calls]
check(old.body.type=='boolean'and old.body.value==false and old.body.expectedGameId=='old','False offered response remains boolean false and retains its exact native game identity')
m:answerChoice(m.game.prompt.choices[1]);check(calls[#calls]==old,'Pending answer cannot be duplicated by another click')
m.zoneView={cards={{id='old-visible'}}};m.inspectCard={id='old-visible'};m.confirmConcede=true
m:setGame(state('new',{id=3,type='ask',choices={{id='yes',responseType='boolean',value=true}}}));m:answerChoice(m.game.prompt.choices[1]);local current=calls[#calls]
check(not m.zoneView and not m.inspectCard and not m.confirmConcede,'A replacement game clears old inspection and concession-confirmation context')
old.callback(nil,'Lost old response',0)
check(m.actionBusy and m.answeredPrompt==3 and m.game.gameId=='new','Old failed action cannot clear the newer rematch answer latch')
old.callback(state('old',nil,200))
check(m.game.gameId=='new','Old successful action cannot replace a newer native game')
current.callback(state('new',nil,2));check(not m.actionBusy,'Current response clears only its own busy state')
m:setGame(state('new',{id=4,type='ask',choices={}}));m:concede();local concession=calls[#calls]
check(concession.body.type=='concede'and concession.body.expectedGameId=='new'and m.concedePending,'Concession identifies its actual game and remains pending until acknowledged')
m:concede();check(calls[#calls]==concession,'Duplicate concession is not queued while the first is pending')
m:setGame(state('third',{id=4,type='ask',choices={}}));concession.callback(state('new',nil,100))
check(m.game.gameId=='third'and not m.concedePending,'Late concession acknowledgement cannot terminate a new game')
m.gameBusy=true;check(not m:prompt(),'Starting a replacement game hides obsolete live prompts');m.gameBusy=false
m.game.execution={stopRequested=true,terminationConfirmed=false,threadAlive=true};check(not m:prompt()and m.game.running,'Native stop-request metadata hides stale choices without pretending the game thread ended');m.game.execution=nil
m:setGame(state('third',{id=5,type='ask',choices={}},8));m:setGame(state('third',{id=6,type='ask',choices={}},7))
check(m.game.prompt.id==5,'Older native revisions cannot replace current state')
local types={{'uuid','target-id'},{'string','native-string'},{'integer',7},{'multi_amount',json.array({1,2})},{'order',json.array({'trigger-b','trigger-a'})}}
for i,choice in ipairs(types)do
 m:setGame(state('third',{id=10+i,type='test',choices={}},30+i*2));m.answeredPrompt=nil;m.actionBusy=false
 m:answerChoice({id='label-only',responseType=choice[1],value=choice[2]});local request=calls[#calls]
 check(request.body.type==choice[1]and json.encode(request.body.value)==json.encode(choice[2]),'Offered '..choice[1]..' payload forwards exact native value')
 request.callback(state('third',nil,31+i*2))
end
local trace={};for _,call in ipairs(calls)do trace[#trace+1]={service=call.service,path=call.path,body=call.body}end
local result={status='pass',scenarioId='client-model-session-and-response-contracts',evidenceType='client_model_transport',checks=checks,attempts=#calls,acceptedNativeActions=0,nativeEvents=0,actionTrace=trace,scope='Mocked transport; no native execution or rules inference'}
local path=os.getenv('L2G_MECHANICS_CLIENT_OUTPUT');if path then local f=assert(io.open(path..'/model.json','w'));f:write(json.encode(result));f:close()end
print('MECHANICS CLIENT MODEL COMPLETE '..#checks..' checks')
