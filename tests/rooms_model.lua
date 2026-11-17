-- Invite-room/draft transport and local editing contracts. Synthetic backend;
-- native drafts and network authorization are separate acceptance gates.
package.path='./?.lua;'..package.path
local Rooms=require('app.rooms');local json=require('lib.json')
local Model={};Model.__index=Model;Rooms.install(Model)
local passed=0
local function check(value,label)assert(value,label);passed=passed+1;print('ROOMS MODEL PASS '..label)end
local function clone(value)return json.decode(json.encode(value))end
local function client(name)
    local m=setmetatable({playerName=name,format='Commander',settings={manualTriggers=true,autoMana=false},calls={},toasts={},routes={},decks={{id='mine',name=name..' deck',format='Commander',main={{name='Plains',count=99}},commander={{name='Commander',count=1}},sideboard={}}}},Model)
    m.api={setRoomSession=function(_,route)m.routes[#m.routes+1]=route and clone(route)or false end,request=function(_,service,method,path,body,callback)m.calls[#m.calls+1]={service=service,method=method,path=path,body=body,callback=callback}end}
    function m:request(service,method,path,body,callback)self.calls[#self.calls+1]={service=service,method=method,path=path,body=body and clone(body),callback=callback}end
    function m:findDeck(id)for _,deck in ipairs(self.decks)do if deck.id==id then return deck end end end
    function m:toast(message)self.toasts[#self.toasts+1]=message end
    function m:priorityOptions()return{autoPass=true,passWithOnlyMana=true,stops={own=json.array({'PRECOMBAT_MAIN'}),opponent=json.array()}}end
    function m:closeReplay()local live=self.liveGame;self.replay=nil;self.liveGame=nil;self.game=live;self.replayCloseCount=(self.replayCloseCount or 0)+1 end
    function m:setGame(game)if self.replay then self.liveGame=game;return end;if not self.game or self.game.gameId~=game.gameId or(game.revision or 0)>=(self.game.revision or 0)then self.game=game end end
    return m
end
local caps={game={formats={'Modern','Commander'},minPlayers=2,maxPlayers=10},draft={modes={{id='booster',minPlayers=4,maxPlayers=16,packCount=3},{id='random',minPlayers=4,maxPlayers=16},{id='cube',minPlayers=4,maxPlayers=16}},profiles={{id='Limited',minDeckSize=40}},pairings={{id='swiss'},{id='elimination'}},timings={{id='REGULAR'}},sets={{code='one',name='First set'},{code='two',name='Second set'}},cubes={{code='NativeCube',name='Native cube'}},basicLands={{name='Plains',manaSymbol='W'},{name='Island',manaSymbol='U'}}}}
local function snapshot(m,revision,phase,draft,game)
    return {connectionId=m.roomConnectionId or m.playerName..'-connection',participantId=m.playerName,
        room={id='private-room',revision=revision,hostId='Host',phase=phase or'lobby',inviteCode='L2G-only-this-code',config={kind='draft',maxPlayers=4},members={{id='Host',name='Host',ready=false,connected=true},{id='Guest',name='Guest',ready=false,connected=true}}},draft=draft,game=game}
end
local host,guest=client('Host'),client('Guest')
host:showRooms();check(host.page=='rooms'and host.calls[1].path=='/client/capabilities','Rooms load native capabilities without enumerating rooms')
host.calls[1].callback(clone(caps));host.roomSetup.kind='draft';host.roomSetup.maxPlayers=99;Rooms.fitSetup(host)
check(host.roomSetup.maxPlayers==16 and host.roomSetup.draft.sets[3]=='one','Native mode bounds and per-pack set choices populate setup')
local random=client('Random');random.roomCapabilities=clone(caps);Rooms.fitSetup(random)
random.roomSetup.kind='draft';random.roomSetup.draft.mode='random';random.roomSetup.draft.sets[2]='two';Rooms.fitSetup(random)
check(#random.roomSetup.draft.randomSets==0 and json.encode(random.roomSetup.draft.randomSets)=='[]','Random draft defaults to all supported booster sets with an explicit empty JSON array')
check(Rooms.setRandomSet(random,'two',true)and Rooms.setRandomSet(random,'one',true)and not Rooms.setRandomSet(random,'two',true)and not Rooms.setRandomSet(random,'unoffered',true),'An optional random pool contains unique native-offered set codes only')
random.roomSetup.draft.mode='cube';Rooms.fitSetup(random);random.roomSetup.draft.mode='booster';Rooms.fitSetup(random)
check(random.roomSetup.draft.sets[2]=='two'and table.concat(random.roomSetup.draft.randomSets,',')=='two,one','Traditional booster choices and the random eligible pool survive mode changes independently')
random.roomSetup.draft.mode='random';random:hostRoom();local randomCreate=random.calls[#random.calls]
check(randomCreate.body.draft.mode=='random'and json.encode(randomCreate.body.draft.randomSets)=='["two","one"]'and randomCreate.body.draft.sets[2]=='two','Random room creation sends its explicit eligible pool without deriving it from traditional packs')
random.roomBusy=false;check(Rooms.setRandomSet(random,'two',false)and Rooms.setRandomSet(random,'one',false)and not Rooms.setRandomSet(random,'one',false)and json.encode(random.roomSetup.draft.randomSets)=='[]','Removing the last eligible set restores all-supported random drafting')
random:hostRoom();check(json.encode(random.calls[#random.calls].body.draft.randomSets)=='[]','All-supported random pool remains an empty JSON array in the create payload')
host:hostRoom();local create=host.calls[#host.calls]
check(create.path=='/client/rooms'and create.body.kind=='draft'and create.body.draft.mode=='booster','Host creation uses only the local room gateway contract')
check(create.body.settings.manualTriggers and create.body.settings.autoMana==false and create.body.priority.passWithOnlyMana and create.body.priority.stops.own[1]=='PRECOMBAT_MAIN','Room membership receives the participant’s actual engine preferences, mana-only policy and priority stops')
create.callback(snapshot(host,1));check(host.roomParticipantId=='Host'and host.roomConnectionId=='Host-connection','Host receives its authenticated connection and public room')
guest:showRooms();guest.calls[1].callback(clone(caps));guest.roomInviteInput='  L2G-only-this-code  ';guest:joinRoom()
local join=guest.calls[#guest.calls];check(join.path=='/client/join'and join.body.code=='L2G-only-this-code'and join.body.name=='Guest'and not join.body.address,'Guests join with one invitation code and their name')
join.callback(snapshot(guest,1));check(guest.roomParticipantId=='Guest'and guest.roomConnectionId~=host.roomConnectionId,'Two clients retain distinct membership connections')
host:refreshRoom();local stale=host.calls[#host.calls];host:setRoomReady(true);local ready=host.calls[#host.calls]
ready.callback(snapshot(host,3));stale.callback(snapshot(host,999))
check(host.room.revision==3,'A poll started before a mutation cannot overwrite the acknowledged room')
host:refreshRoom();host.calls[#host.calls].callback(snapshot(host,2));check(host.room.revision==3,'Older room revisions are rejected even from a newer HTTP read')
host:selectRoomDeck('mine');local selected=host.calls[#host.calls]
check(selected.body.deck.main[1].count==99 and host.decks[1].main[1].count==99,'Seat deck submission preserves the saved deck composition')
selected.callback(snapshot(host,4))
local draft={id='native-draft',revision=2,status='drafting',packNumber=1,pickNumber=2,packCount=3,pickToken='native-pick-token',pack={{id='host-card',name='Host pack card'}},pool={{id='taken',name='Taken card'}}}
host:refreshRoom();host.calls[#host.calls].callback(snapshot(host,5,'drafting',clone(draft)))
local other=clone(draft);other.pack={{id='guest-card',name='Guest pack card'}};other.pickToken='guest-token'
guest:refreshRoom();guest.calls[#guest.calls].callback(snapshot(guest,5,'drafting',other))
check(host.roomDraft.pack[1].id=='host-card'and guest.roomDraft.pack[1].id=='guest-card','Each client renders only its personalized native pack')
check(not host:pickDraftCard('guest-card'),'Another seat’s pack card cannot be submitted locally')
check(host:pickDraftCard('host-card'),'An offered native card can be picked')
local pick=host.calls[#host.calls]
check(pick.body.pickToken=='native-pick-token'and pick.body.cardId=='host-card','Pick requests retain the native token and card instance ID')
check(not host:pickDraftCard('host-card'),'A pending pick cannot be submitted twice')
draft.revision=3;draft.pickToken='next-token';draft.pack={};pick.callback(snapshot(host,6,'drafting',clone(draft)))
draft.status='building';draft.revision=4;draft.pool={{id='copy-one',name='Same name'},{id='copy-two',name='Same name'},{id='sideboard',name='Sideboard card'}}
draft.selection={main={'copy-one'},basics={Plains=17}}
host:refreshRoom();host.calls[#host.calls].callback(snapshot(host,7,'building',clone(draft)))
check(host.roomDraftDeck and host.page=='draft','Native building phase opens a fresh local deck editor')
check(host.roomDraftDeck.mainIds['copy-one']and host.roomDraftDeck.basics.Plains==17,'A reopened builder restores the native accepted UUID/basic selection')
check(host:setDraftCard('copy-one',true)and host:setDraftCard('copy-two',true)and not host:setDraftCard('unknown',true),'Draft deck editing uses owned pool instance IDs and preserves duplicate names')
check(host:setDraftBasic('Plains',18)and not host:setDraftBasic('Wastes',1)and not host:setDraftBasic('Island',251),'Only native-offered basics are editable within the application resource bound')
host:submitDraftDeck();local submit=host.calls[#host.calls]
check(#submit.body.main==2 and submit.body.main[1]=='copy-one'and submit.body.main[2]=='copy-two'and submit.body.basics.Plains==18,'Draft deck payload contains exact chosen instances and basic quantities')
submit.callback(nil,'Deck too small',{errors={{message='The native Limited deck needs 40 cards'}}})
check(host.roomDraftDeck.mainIds['copy-two']and host.roomDraftValidation[1].message:find('40',1,true),'Native validation errors preserve the unsaved pool selection')
host:refreshRoom();local beforeReconnect=host.calls[#host.calls];host.roomDisconnected=true;host:rejoinRoom();local reconnect=host.calls[#host.calls]
beforeReconnect.callback(snapshot(host,900,'building',clone(draft)));reconnect.callback(snapshot(host,8,'building',clone(draft)))
check(host.room.revision==8 and not host.roomDisconnected,'Reconnect reuses the authenticated seat and rejects callbacks from its previous opening')
check(host.roomDraftDeck.mainIds['copy-two']and host.roomDraftDeck.basics.Plains==18,'A background accepted selection does not overwrite unsaved local deck edits')
local accepted=clone(draft);accepted.status='ready';accepted.revision=5;accepted.selection={main={'copy-one','copy-two'},basics={Plains=38}}
host:refreshRoom();host.calls[#host.calls].callback(snapshot(host,9,'building',accepted))
check(host:setDraftBasic('Plains',38)and host:setDraftCard('copy-two',true),'An accepted ready deck remains editable before the first native round')
host:submitDraftDeck();local resubmit=host.calls[#host.calls];resubmit.callback(snapshot(host,10,'building',accepted))
check(resubmit.body.basics.Plains==38 and #resubmit.body.main==2 and not host.roomDraftDeck.dirty,'Ready deck edits can be resubmitted with exact instance IDs and quantities')
host.replay={id='recording'}
host:refreshRoom();host.calls[#host.calls].callback(snapshot(host,11,'playing',nil,{gameId='native-room-game',revision=10,running=true,players={}}))
host:refreshRoom();host.calls[#host.calls].callback(snapshot(host,12,'playing',nil,{gameId='native-room-game',revision=11,running=true,players={}}))
check(host.page=='table'and host.game.revision==11 and #host.routes==1,'Playing routes engine actions once to the authenticated room connection')
check(not host.replay and host.replayCloseCount==1,'Adopting a native room game closes an open read-only replay first')
host.replay={id='current-room-recording'};host.liveGame=host.game
host:refreshRoom();host.calls[#host.calls].callback(snapshot(host,13,'playing',nil,{gameId='native-room-game',revision=12,running=true,players={}}))
check(host.replay and host.replayCloseCount==1 and host.liveGame.revision==12,'Polling the same active room game preserves read-only replay playback')
host.replay={id='second-recording'}
host:refreshRoom();host.calls[#host.calls].callback(snapshot(host,14,'playing',nil,{gameId='native-next-round',revision=1,running=true,players={}}))
check(host.routes[#host.routes].gameId=='native-next-round'and host.replayCloseCount==2,'A new native round updates the routing identity and closes the old replay')
local bye={id='native-draft',status='competing',pool={},tournament={round=2,matches={{bye=true,seatIds={'Host'}}},standings={{seatId='Host',name='Host',points=3}}}}
host.replay={id='saved-frame'};host.liveGame=host.game;local replayFrame={gameId='recorded-game',revision=100};host.game=replayFrame;host.page='table'
host:refreshRoom();host.calls[#host.calls].callback(snapshot(host,15,'playing',bye,nil))
check(host.game==replayFrame and host.replay and not host.liveGame and host.routes[#host.routes]==false and host.roomTournamentRole=='bye','A native bye clears live room state while preserving the displayed read-only replay')
host:refreshRoom();host.calls[#host.calls].callback(snapshot(host,16,'completed',bye,nil))
check(host.game==replayFrame and host.replay and not host.roomGameActive and not host.liveGame,'Tournament completion stops live polling without removing the replay frame')
host.liveGame={gameId='native-next-round',revision=2}
host:refreshRoom();local beforeLeave=host.calls[#host.calls];host:leaveRoom();local leave=host.calls[#host.calls];leave.callback({left=true});beforeLeave.callback(snapshot(host,999,'playing',nil,{gameId='stale-room-game',revision=99}))
check(not host.roomConnectionId and not host.game and not host.replay and host.routes[#host.routes]==false,'Leaving closes playback and cannot restore an old owned room game after a bye')
check(leave.path:find('/leave',1,true)and host.roomLastCode=='L2G-only-this-code','Leaving uses the room endpoint and retains only the shared invitation for later use')
for _,call in ipairs(host.calls)do assert(not call.path:find('/session/stop',1,true),'Room departure must not stop an engine match')end
check(true,'Room departure never sends a global engine stop command')
guest:quit();check(guest.calls[#guest.calls].path:find('/leave',1,true),'Application quit queues an explicit authenticated room departure')
local retry=client('Retry');retry.roomGeneration=1
local connecting=client('ConnectRetry');connecting.roomCapabilities=clone(caps);Rooms.fitSetup(connecting)
connecting:hostRoom();local firstConnect=connecting.calls[#connecting.calls]
firstConnect.callback(nil,'Reply lost')
connecting:hostRoom();local sameConnect=connecting.calls[#connecting.calls]
check(firstConnect.body.connectionRequestId==sameConnect.body.connectionRequestId,'A lost create acknowledgement keeps the same local operation identity for an explicit retry')
sameConnect.callback(nil,'Still waiting');connecting.roomSetup.playerName='Changed name';connecting:hostRoom()
check(connecting.calls[#connecting.calls].body.connectionRequestId~=firstConnect.body.connectionRequestId,'Changed connection payloads receive a new operation identity')
local pendingGame={gameId='retry-game',revision=20,running=true,prompt={id=91,type='pick_target',choices={{id='offered-target'}}},players={}}
retry:applyRoomSnapshot(snapshot(retry,1,'playing',nil,pendingGame),1,1)
retry:refreshRoom();local delayed=retry.calls[#retry.calls]
retry:updateRooms(3)
check(retry.roomTransport.state=='waiting'and retry.game.prompt.id==91,'A slow read is visible while the current native choice remains intact')
delayed.callback(nil,'Timed out',{retryable=true,kind='transport'})
check(retry.roomDisconnected and retry.roomTransport.state=='reconnecting'and retry.game.prompt.id==91 and retry.roomConnectionId=='Retry-connection','Transient transport errors preserve the same seat and unanswered choice')
local requests=#retry.calls;retry:updateRooms(.1)
check(#retry.calls==requests and retry.roomPollTimer>0,'Repeated room reads use bounded backoff instead of a timeout storm')
check(not retry:setRoomReady(true),'Mutations wait for a fresh room acknowledgement after transport loss')
retry:updateRooms(2);local refreshed=retry.calls[#retry.calls]
refreshed.callback(snapshot(retry,2,'playing',nil,pendingGame))
check(not retry.roomDisconnected and retry.roomTransport.state=='connected'and retry.roomPollFailures==0 and retry.game.prompt.id==91,'Automatic recovery retains the native prompt and resets read backoff')
retry:roomMutation('/game/action',{promptId=91,type='uuid',value='offered-target'});local lost=retry.calls[#retry.calls]
lost.callback(nil,'Connection closed',{kind='outcome_unknown',retryable=false})
requests=#retry.calls;retry:updateRooms(.01)
check(#retry.calls==requests+1 and retry.calls[#retry.calls].method=='GET'and retry.roomTransport.state=='reconciling','Lost mutation acknowledgement refreshes state and never replays the action')
retry.calls[#retry.calls].callback(snapshot(retry,3,'playing',nil,pendingGame))
retry:roomMutation('/deck',{});retry.calls[#retry.calls].callback(nil,'Invalid deck',{error='Invalid deck',retryable=false})
check(not retry.roomDisconnected and retry.roomError=='Invalid deck','A definite native validation rejection is not mislabeled as a room timeout')
retry:rejoinRoom();check(retry.roomDisconnected and retry.game.prompt.id==91,'An explicit reconnect temporarily fences new input while retaining the same native choice')
retry.calls[#retry.calls].callback(snapshot(retry,4,'playing',nil,pendingGame))
print('Rooms model checks: '..passed..' passed')
