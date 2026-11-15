-- Outcome, native capability, bot-draft orchestration and rematch DTO contracts.
-- No HTTP, native game, image download or user store is used here.
package.path='./?.lua;'..package.path
local json=require('lib.json');local Outcome=require('app.outcome')
local checks=0;local function check(ok,label)assert(ok,label);checks=checks+1;print('CLIENT FEATURES PASS '..label)end
local game={gameId='native-ended',running=false,error=json.null,players={{id='me',human=true,won=true},{id='other',lost=true}}}
local m={game=game};check(Outcome.state(m).outcome=='win','Old native won flags remain authoritative with JSON-null error')
game.players[1].won=false;game.players[1].life=0;check(Outcome.state(m)==nil,'Zero life never invents an outcome')
game.result={gameId=game.gameId,completed=true,outcome='draw'};check(Outcome.state(m).title=='DRAW','A draw requires a completed native draw result')
game.result.completed=false;check(Outcome.state(m)==nil,'An aborted native result never becomes a draw')
game.result={gameId='another-game',completed=true,outcome='win'};check(Outcome.state(m)==nil,'A result cannot migrate from another game')
game.result={gameId=game.gameId,completed=true,outcome='loss'};game.error='Native failure';check(Outcome.state(m)==nil,'Native errors suppress victory presentation')
game.error=nil;m.replay={};check(Outcome.state(m)==nil,'Replay does not open live rematch presentation');m.replay=nil
game.players[3]={id='third'};check(Outcome.state(m).mode=='multiplayer','Completed multiplayer uses its own presentation mode')
local Model={};Model.__index=Model;function Model:update()end
function Model:request(service,method,path,body,callback)self.calls[#self.calls+1]={service=service,method=method,path=path,body=body,callback=callback}end
function Model:toast(message)self.toasts[#self.toasts+1]=message end
function Model:setGame(data)self.game=data end
require('app.rooms').install(Model);require('app.native_capabilities').install(Model);require('app.bot_draft').install(Model);require('app.input_delivery').install(Model)
local function client()return setmetatable({playerName='Draft Player',format='Modern',settings={},calls={},toasts={},api={enginePort=17491},engineHealth={ok=true,instanceId='engine-one'}},Model)end
local n=client();n:update(.1);local old=n.calls[1]
check(old.path=='/capabilities','Installed format discovery uses the native endpoint')
old.callback({formatDetails={{id='Vintage',supported=true,construction='constructed'},{id='Limited',supported=true,construction='limited'},{id='MissingPlugin',supported=false}}})
check(table.concat(n:playFormats(),',')=='Vintage','Editable choices include supported native formats, excluding draft/unsupported setups')
n.nativeCapabilitiesRetry=0;n:update(.1);local stale=n.calls[#n.calls]
n.engineHealth.instanceId='engine-two';n:update(.1);local fresh=n.calls[#n.calls]
stale.callback({formatDetails={{id='Old format',supported=true}}})
check(n.nativeCapabilities==nil and n.nativeCapabilitiesPending,'An old engine capability callback cannot populate a replacement instance')
fresh.callback({formatDetails={{id='Legacy',supported=true}}});check(n:playFormats()[1]=='Legacy','Replacement engine capabilities hydrate independently')
n.searchFormat='Legacy';check(not n:snapshotFilterAvailable()and n:catalogSearchHint():find('Full catalog',1,true),'Extra native formats do not claim unavailable snapshot filtering')
n.searchFormat='Modern';n.searchFilterInfo={formatId='Legacy',snapshotFilterAvailable=false};check(n:snapshotFilterAvailable(),'A prior format response cannot remove the current indexed filter')
n.searchFilterInfo={formatId='Modern',snapshotFilterAvailable=false};check(not n:snapshotFilterAvailable(),'The actual catalog response can explicitly withhold preflight filtering')
local delivery=client();delivery.answeredPrompt=42;delivery.actionBusy=true;delivery.pollTimer=9
local failedDelivery={gameId='delivery-game',running=true,prompt={id=42},inputDelivery={id='delivery-one',pending=false,promptId=42,error='Native response rejected'}}
delivery:setGame(failedDelivery)
check(delivery.answeredPrompt==nil and not delivery.actionBusy and delivery.pollTimer==0 and#delivery.toasts==1,'Only a failed delivery of the exact still-open choice restores its controls')
delivery.answeredPrompt=42;delivery:setGame(failedDelivery);check(delivery.answeredPrompt==42 and#delivery.toasts==1,'Repeated state polling cannot repeatedly restore or notify a failed delivery')
delivery:setGame({gameId='delivery-game',prompt={id=43},inputDelivery={id='delivery-two',promptId=42,error='Old question'}})
check(delivery.answeredPrompt==42 and#delivery.toasts==1,'A newer native question is never restored using an old delivery error')
delivery:setGame({gameId='delivery-game',prompt={id=42},inputDelivery={id='delivery-three',promptId=42,error=json.null}})
check(delivery.answeredPrompt==42 and#delivery.toasts==1,'A JSON-null delivery error is not a native rejection')
delivery.replay={};delivery:setGame({gameId='delivery-game',prompt={id=42},inputDelivery={id='delivery-four',promptId=42,error='Replay row'}})
check(delivery.answeredPrompt==42 and#delivery.toasts==1,'Replay state never restores a live native choice')
local Accepted={setGame=function()end};require('app.input_delivery').install(Accepted)
local rejected=setmetatable({game={gameId='accepted'},answeredPrompt=42,toasts={},toast=Model.toast},{__index=Accepted});rejected:setGame(failedDelivery)
check(rejected.game.gameId=='accepted'and rejected.answeredPrompt==42,'A projection rejected by the model cannot restore controls through delivery metadata')
local priorLove=love;love={timer={getTime=function()return 10 end}};require('app.activity').install(Model)
local activity=client();activity.page='table';activity.game={running=true,inputDelivery={pending=true}}
check(activity:activityState().busy and activity:activityState().label:find('receive your action',1,true),'Queued native delivery has an explicit busy indicator')
function activity:prompt()return nil end
activity.game.inputDelivery.pending=false;check(not activity:activityState().busy,'An ordinary opponent wait does not display busy work');love=priorLove
local caps={game={formats={{id='Modern',minPlayers=2,maxPlayers=2}}},draft={botSupport=true,modes={{id='booster',minPlayers=4,maxPlayers=16,packCount=3}},profiles={{id='Limited'}},pairings={{id='swiss'}},timings={{id='REGULAR'}},sets={{code='M21',name='Core Set 2021'}}}}
local d=client();d.roomCapabilities=caps;d:openBotDraft()
check(d.lobbyMode=='draft'and d.roomSetup.kind=='draft'and d.roomSetup.maxPlayers==8,'Lobby opens native bot drafting with eight default seats')
check(d.roomSetup.draft.mode=='booster'and d.roomSetup.draft.sets[3]=='M21','Native procedures and supported boosters populate the draft form')
check(d:startBotDraft()and d.calls[1].path=='/client/rooms'and d.calls[1].body.kind=='draft','Bot draft creates an ordinary private native draft room, not a constructed session')
local function response(phase,revision)
 return{connectionId='isolated-draft-connection',participantId='host',room={id='draft-room',revision=revision,hostId='host',phase=phase,config={kind='draft',maxPlayers=8},members={{id='host',name='Draft Player',ready=true}}}}
end
d.calls[1].callback(response('lobby',1));check(d.calls[2].path:match('/bots$')and d.calls[2].body.count==7,'Only after creation is acknowledged are the seven native bot seats requested')
d.calls[2].callback(response('lobby',2));check(d.calls[3].path:match('/ready$')and d.calls[3].body.ready,'Native human readiness follows acknowledged bot setup')
d.calls[3].callback(response('lobby',3));check(d.calls[4].path:match('/start$'),'Start follows native room setup acknowledgements in order')
d.calls[4].callback(response('starting',4));check(not d.botDraftBusy and d.roomPollTimer==0,'Accepted start returns to asynchronous native draft polling')
check(not d:startBotDraft(),'An existing private room is never overwritten by another bot draft')
local failed=client();failed.roomCapabilities=caps;failed:openBotDraft();failed:startBotDraft();failed.calls[1].callback(nil,'Synthetic start error')
check(not failed.botDraftBusy and failed.botDraftError=='Synthetic start error','A failed native room creation releases the draft controls')
local missing=client();missing.roomCapabilities={game=caps.game,draft={botSupport=false}};missing:openBotDraft();check(not missing:startBotDraft()and#missing.calls==0,'Unconfirmed bot support cannot start an invented local draft')
local late=client();late.roomCapabilities=caps;late:openBotDraft();late:startBotDraft();late.botDraftGeneration=late.botDraftGeneration+1;late.calls[1].callback(response('lobby',1))
check(#late.calls==1,'A superseded draft opening cannot continue the setup chain')
local room=client();room.roomConnectionId='fixture-connection';room.roomParticipantId='guest';room.game={gameId='finished',running=false};room.room={phase='playing',rematchRequest={id='request',gameId='finished',requesterId='host',requesterName='Other player',approvedSeatIds={'host'}}}
check(not room:respondRematch(true,'stale'),'A stale request ID cannot respond to the current offer')
check(room:respondRematch(false,'request')and room.calls[1].body.accept==false and room.calls[1].path:match('/rematch%-response$'),'Decline uses only the active authenticated room/request identity')
room.roomBusy=false;room.roomParticipantId='host';check(room:cancelRematch('request')and room.calls[2].path:match('/rematch%-cancel$'),'The requester can cancel the exact current offer')
room.roomBusy=false;room.roomParticipantId='guest';room.game.gameId='next-game';check(not room:respondRematch(true,'request'),'A previous game offer cannot accept into a new game')
local Picker=require('app.set_picker');local view={S={SetInputFocus=function()end},m={}};local chosen
Picker.open(view,{allowAll=false,items={{code='M21',name='Core Set 2021'}},onSelect=function(code)chosen=code end})
check(#Picker.items(view)==1 and not Picker.select(view,''),'Native booster selection omits the browsing-only All sets choice')
check(Picker.select(view,'m21')and chosen=='m21','An exact native booster code remains selectable')
print('Client feature checks: '..checks)
