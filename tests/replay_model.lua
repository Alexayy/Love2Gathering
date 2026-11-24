-- Client replay contracts only. No game engine or SQLite durability is simulated
-- as evidence here; those have separate real HTTP and XMage acceptance checks.
package.path='./?.lua;./?/init.lua;'..package.path
local calls={}
package.preload['app.api']=function()
    return {new=function()return {
        request=function(_,service,method,path,body,callback)
            calls[#calls+1]={service=service,method=method,path=path,body=body,callback=callback};return #calls
        end,update=function()end,quit=function()end,
    }end,escape=function(value)return tostring(value)end}
end
love={math={random=function()return 1234 end},timer={getTime=function()return 1 end}}
local Model=require('app.model')
local Log=require('app.log')
local passed,failed=0,0
local function test(name,fn)
    calls={};local ok,error=pcall(fn)
    if ok then passed=passed+1;print('PASS '..name)else failed=failed+1;print('FAIL '..name..': '..tostring(error))end
end
local function pending(path)
    for _,call in ipairs(calls)do if not call.done and call.path==path then return call end end
    error('No pending request for '..path)
end
local function respond(call,data,code)
    call.done=true;call.callback(data,nil,code or 200)
end
local function live(revision,prompt)
    return {gameId='live',revision=revision,turn=4,players={{id='human',name='You',human=true},{id='bot',name='Bot',human=false}},prompt=prompt}
end
local function frame(index,timestamp)
    return {sequence=index-1,type='frame',timestamp=timestamp or tostring(index*100),data={gameId='archived',revision=index,turn=index,
        players={{id='human',name='You',human=true},{id='bot',name='Bot',human=false}},
        prompt={id=900+index,type='select',actionable={'card'},choices={{id='card',responseType='uuid'}}}}}
end
local function frames(first,last)
    local result={};for i=first,last do result[#result+1]=frame(i)end;return result
end
local function openOne(model,id)
    id=id or 'recording';model:openReplay(id)
    respond(pending('/replays/'..id),{id=id,title='Recorded game'})
    respond(pending('/replays/'..id..'/frames?offset=0&limit=50'),{frames=frames(1,3),total=3})
end

test('asynchronous 501-frame pagination preserves order and live game',function()
    local m=Model.new();local before=live(10);m:setGame(before);m:openReplay('long')
    respond(pending('/replays/long/frames?offset=0&limit=50'),{frames=frames(1,50),total=501})
    assert(m.replayLoading and m.game==before and #m.replay.frames==50,'First page replaced live state before load completed')
    respond(pending('/replays/long'),{id='long',title='Long recording',frameCount=501})
    for offset=50,450,50 do
        respond(pending('/replays/long/frames?offset='..offset..'&limit=50'),{frames=frames(offset+1,offset+50),total=501})
    end
    respond(pending('/replays/long/frames?offset=500&limit=50'),{frames=frames(501,501),total=501})
    assert(not m.replayLoading and #m.replay.frames==501 and m.replay.frames[501].sequence==500)
    assert(m.liveGame==before and m.game.turn==1 and m.replay.metadata.title=='Long recording')
end)

test('closing a load ignores late frame and metadata responses',function()
    local m=Model.new();local before=live(10);m:setGame(before);m:openReplay('closing')
    local metadata=pending('/replays/closing');local page=pending('/replays/closing/frames?offset=0&limit=50')
    m:closeReplay();respond(page,{frames=frames(1,3),total=3});respond(metadata,{id='closing',title='Too late'})
    assert(not m.replay and not m.replayLoading and m.game==before and m.page=='replays')
end)

test('out-of-order browser refresh cannot replace newer recordings',function()
    local m=Model.new();m:refreshReplays();local first=calls[#calls]
    m:refreshReplays();local second=calls[#calls]
    respond(second,{replays={{id='new',title='Newest recording'}},total=1})
    respond(first,{replays={{id='old',title='Old response'}},total=1})
    assert(m.replays[1].id=='new','A stale browser response replaced the newest recording list')
end)

test('reopening the same ID ignores callbacks from the previous load',function()
    local m=Model.new();m:setGame(live(10));m:openReplay('same')
    local oldMetadata=pending('/replays/same');local oldPage=pending('/replays/same/frames?offset=0&limit=50')
    m:closeReplay();m:openReplay('same')
    local newMetadata,newPage
    for i=#calls,1,-1 do local c=calls[i];if c.path=='/replays/same' and not newMetadata then newMetadata=c elseif c.path=='/replays/same/frames?offset=0&limit=50' and not newPage then newPage=c end end
    respond(newMetadata,{id='same',title='New load'});respond(newPage,{frames={frame(9)},total=1})
    respond(oldMetadata,{id='same',title='Old load'});respond(oldPage,{frames={frame(1)},total=1})
    assert(#m.replay.frames==1 and m.game.turn==9 and m.replay.metadata.title=='New load','Old same-ID responses contaminated the reopened replay')
end)

test('step seek autoplay and restart use saved timestamps',function()
    local m=Model.new();openOne(m)
    m:stepReplay(1);assert(m.replay.index==2 and m.game.turn==2)
    m:stepReplay(-20);assert(m.replay.index==1)
    m:seekReplay(999);assert(m.replay.index==3 and not m.replay.playing)
    m:toggleReplay();assert(m.replay.index==1 and m.replay.playing)
    m:updateReplays(.11);assert(m.replay.index==2)
    m:updateReplays(.11);assert(m.replay.index==3 and not m.replay.playing)
    m:seekReplay(1.5);assert(m.replay.index%1==0,'Timeline seek retained a fractional array index')
end)

test('viewing replay cannot send engine actions',function()
    local m=Model.new();m:setGame(live(10));openOne(m)
    calls={}
    assert(m:prompt()==nil and not m:canSelect('card') and not m:selectCard({id='card'}))
    m:answer('uuid','card');m:answerChoice({id='card',responseType='uuid'});m:submitOrder();m:concede();m:saveReplay()
    for _,call in ipairs(calls)do assert(call.service~='engine','Read-only playback sent an engine action')end
end)

test('open zones follow the selected frame in both directions',function()
    local m=Model.new()
    local first,second=frame(1),frame(2)
    local bear,token,other={id='bear'},{id='token'},{id='other'}
    local marked={id='bear',damage=1}
    first.data.players[1].battlefield={bear,token}
    second.data.players[1].battlefield={other,marked}
    second.data.players[1].graveyard={token}
    m:openReplay('zones')
    respond(pending('/replays/zones/frames?offset=0&limit=50'),{frames={first,second},total=2})
    m:openZone('human','battlefield','Group',{bear,token})
    m.zoneView.inspectedCard=token;m.inspectCard=token
    m:stepReplay(1)
    assert(#m.zoneView.cards==1 and m.zoneView.cards[1]==marked,'Group followed a departed card or kept old damage')
    assert(not m.inspectCard,'Inspection kept a member that left the battlefield')
    m:stepReplay(-1)
    assert(#m.zoneView.cards==2 and m.zoneView.cards[2]==token,'Rewinding failed to restore the original group members')
    m:openZone('human','graveyard')
    m:stepReplay(1)
    assert(#m.zoneView.cards==1 and m.zoneView.cards[1]==token)
    m:stepReplay(-1)
    assert(#m.zoneView.cards==0,'Graveyard retained a card from a later replay frame')
    m:closeReplay();assert(not m.zoneView,'A replay popup leaked into the recording browser')
end)

test('reveal and playable exile popups track current native offers',function()
    local m=Model.new()
    local exile={id='exiled',name='Exiled spell',zone='EXILED'}
    local seen={id='looked',name='Looked-at card'}
    local first=live(1,{id=1,actionable={exile.id},cardActions={{objectId=exile.id,sourceZone='EXILED'}}})
    first.players[1].exile={exile}
    first.revealed={{cards={seen}}};first.lookedAt={{cards={seen,exile}}}
    m:setGame(first)
    m.zoneView={revealed=true,gameId=first.gameId};m:refreshZoneView()
    assert(#m.zoneView.cards==2 and m.zoneView.cards[1]==seen and m.zoneView.cards[2]==exile)
    local second=live(2,first.prompt);second.players[1].exile={exile};m:setGame(second)
    assert(#m.zoneView.cards==0,'Ended reveal followed its card into a different zone')
    m.zoneView={playableExile=true,gameId=first.gameId};m:refreshZoneView()
    assert(#m.zoneView.cards==1 and m.zoneView.cards[1].id==exile.id)
    local expired=live(3,{id=2,actionable={},cardActions={}});expired.players[1].exile={exile};m:setGame(expired)
    assert(#m.zoneView.cards==0,'Expired play permission remained in the exile hand popup')
end)

test('pin and detail follow current native traits and close at the original zone boundary',function()
    local m=Model.new()
    local first=live(1)
    local bear={id='object-a',name='Bear',power='2',zone='BATTLEFIELD'}
    first.players[1].battlefield={bear};m:setGame(first)
    assert(m:pinTableCard(bear,{kind='permanent'}))
    local selected,context=m:pinnedTableCard()
    assert(selected==bear and m:inspectTableCard(selected,context))
    local second=live(2)
    local changed={id=bear.id,name='Bear',power='5',damage=1,zone='BATTLEFIELD'}
    second.players[1].battlefield={changed};m:setGame(second)
    assert(m.inspectCard==changed and m:pinnedTableCard()==changed,'Live details retained an old card snapshot')
    local third=live(3)
    third.players[1].graveyard={{id=bear.id,name='Bear',zone='GRAVEYARD'}}
    third.log={{id='log1',sourceCard=bear}}
    m:setGame(third)
    assert(not m.inspectCard and not m:pinnedTableCard() and not m:resolveTableCard(selected,context),
        'A moved card survived by matching its UUID in a different zone or the log')
    assert(not m:resolveTableCard({name='Bear'},{}),'A catalog name was accepted as a native ID')
end)

test('inspection drops private prompt and library identities even when the same object remains visible elsewhere',function()
    local m=Model.new()
    local top={id='top',name='Private face'}
    local p={id=19,type='pick_target',cardPanel={cards={top}}}
    local a=live(1,p);a.players[1].libraryTop=top;m:setGame(a)
    assert(m:pinTableCard(top,{libraryPlayerId='human',gameId='live'}))
    local _,oldRef=m:pinnedTableCard()
    assert(m:inspectTableCard(top,{choice=p}))
    local b=live(2,{id=20,type='pick_target',cardPanel={cards={top}}})
    b.players[1].hand={top};m:setGame(b)
    assert(not m:resolveTableCard(top,oldRef) and not m.inspectCard and not m:pinnedTableCard())
    assert(not m:inspectTableCard(top,{choice=p}),'Stale choice was accepted into another prompt')
end)

test('face-down inspection uses only permission and current public battlefield data',function()
    local m=Model.new()
    local card={id='face',hidden=true,faceDown=true,name='Redacted',rules='must not be shown',power='2',toughness='2',
        damage=1,counters={charge=2},faceDownIdentity={id='face',name='Secret'}}
    local a=live(1);a.players[1].battlefield={card};m:setGame(a)
    assert(not m:pinTableCard(card) and not m:resolveTableCard(card))
    assert(m:inspectTableCard(card,{kind='permanent'}))
    assert(m.inspectCard.name=='Face-down card' and not m.inspectCard.rules and not m.inspectCard.faceDownIdentity
        and m.inspectCard.damage==1 and m.inspectCard.counters.charge==2)
    local b=live(2);b.players[1].hand={card};m:setGame(b)
    assert(not m.inspectCard and not m:inspectTableCard(card,{kind='hand'}))
    local owned={id='face',faceDown=true,power='2',toughness='2',faceDownIdentity={id='face',name='My actual card'}}
    local c=live(3);c.players[1].battlefield={owned};m:setGame(c)
    assert(m:inspectTableCard(owned) and m.inspectCard.name=='My actual card' and m.inspectCard.faceDownContext.nativePT=='2/2')
    m:setGame(a);assert(m.inspectCard,'An older frame replaced entitled data')
    a.revision=4;m:setGame(a);assert(not m.inspectCard and not m:pinnedTableCard(),'A revoked private peek stayed visible')
end)

test('replay inspection is scoped to the recorded stack item, log entry and opening',function()
    local m=Model.new()
    local first,second=frame(1),frame(2)
    local spell={id='spell',name='Played card',zone='STACK'}
    local entry={id='log-1',sourceId='spell',sourceCard=spell}
    first.data.stack={{id='s1',sourceCard=spell}};first.data.log={entry}
    second.data.stack={};second.data.log={entry}
    m:openReplay('inspection')
    respond(pending('/replays/inspection/frames?offset=0&limit=50'),{frames={first,second},total=2})
    assert(m:inspectTableCard(spell,{stackId='s1'}));m:stepReplay(1)
    assert(not m:pinnedTableCard() and not m.inspectCard)
    assert(m:pinTableCard(spell,{history=true,entry=entry}))
    local _,context=m:pinnedTableCard()
    m:stepReplay(-1);assert(m:pinnedTableCard()==spell)
    m:closeReplay();assert(not m:pinnedTableCard())
    m:openReplay('inspection')
    respond(pending('/replays/inspection/frames?offset=0&limit=50'),{frames={first},total=1})
    assert(not m:resolveTableCard(spell,context),'A previous opening supplied provenance for the same recording')
end)

test('host links, commander details and old log entries retain only their projected sources',function()
    local m=Model.new()
    local linked={id='exited',name='Exiled spell',zone='EXILED'}
    local host={id='host',name='Host',linkedExile={linked}}
    local leader={id='leader',name='Commander',zone='COMMAND'}
    local function state(revision)
        local game=live(revision)
        game.players[1].battlefield={host}
        game.players[1].commanders={{id=leader.id,name=leader.name,sourceCard=leader,zone='COMMAND'}}
        game.log={{text='This spell resolved',sourceId=linked.id,sourceCard=linked,timestamp=1234,category='resolve'}}
        return game
    end
    local a=state(1);m:setGame(a)
    assert(m:inspectTableCard(linked,{linkedHostId=host.id}) and m.inspectCard==linked)
    local b=state(2);b.players[1].battlefield={{id=host.id,linkedExile={}}};b.players[1].exile={linked};m:setGame(b)
    assert(not m.inspectCard and not m:pinnedTableCard(),'A removed link survived through an unrelated zone')
    assert(m:inspectTableCard(leader,{commanderPlayerId='human'}))
    assert(not m:inspectTableCard(leader,{commanderPlayerId='bot'}),'Commander metadata crossed seats')
    assert(m:inspectTableCard(linked,{history=true,entry=b.log[1]}))
    local c=state(3);m:setGame(c);assert(m.inspectCard==linked,'Decoding another frame closed the same legacy log entry')
    local d=state(4);d.log[1].timestamp=1235;m:setGame(d)
    assert(not m.inspectCard,'A replaced historical row inherited the previous row selection')
    d.log[1].sequence=40;assert(m:pinTableCard(linked,{history=true,entry=d.log[1]}))
    local e=state(5);e.log[1].sequence=40;table.insert(e.log,1,{text='Earlier entry'});m:setGame(e)
    assert(m:pinnedTableCard()==linked,'A stable native log sequence should survive changes to the row number')
    m.roomConnectionId='other-connection';m:refreshTableInspection()
    assert(not m:pinnedTableCard(),'A pin survived a room routing change with a reused game ID')
end)

test('out-of-order live callbacks preserve latest game and trigger order',function()
    local m=Model.new();m:setGame(live(10));openOne(m)
    local prompt={id=50,type='order',choices={{id='first',label='First'},{id='second',label='Second'}}}
    local latest=live(12,prompt);m:setGame(latest);m:setGame(live(11))
    assert(m.game.gameId=='archived','Live callback replaced playback frame')
    m:closeReplay()
    assert(m.game==latest and m.game.revision==12,'Out-of-order callback replaced latest live state')
    assert(m:prompt().id==50 and #m.promptOrder==2 and m.promptOrder[1].id=='first','Closing replay did not restore live trigger choices')
end)

test('actor colors distinguish human bot and system log entries',function()
    local players={{id='h',name='Human',human=true},{id='b',name='Bot',human=false}}
    local human=Log.present({text='Human casts a spell',actor='human',category='cast'},players)
    local bot=Log.present({text='Bot draws a card',actor='bot',category='draw'},players)
    local system=Log.present({text='Game started',actor='system',category='system'},players)
    assert(human.actor=='human' and bot.actor=='bot' and system.actor=='system')
    assert(human.actorColor[1]~=bot.actorColor[1] and bot.actorColor[1]~=system.actorColor[1])
    assert(Log.present('Human plays Forest',players).actor=='human')
end)

print(('Replay model checks: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
