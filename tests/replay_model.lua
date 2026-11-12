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
