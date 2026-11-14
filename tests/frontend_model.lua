-- Frontend contract tests; no game rules or native window are mocked as evidence
-- of XMage behavior. Run from the project root with: lua tests/frontend_model.lua
package.path='./?.lua;./?/init.lua;'..package.path
local json=require('lib.json')
local calls,responders={},{}
package.loaded['app.api']=nil
package.preload['app.api']=function()
    local API={}
    function API.new()
        return {
            request=function(_,service,method,path,body,callback)
                local call={service=service,method=method,path=path,body=body,callback=callback}
                calls[#calls+1]=call
                local responder=responders[service..' '..method..' '..path]
                if responder then callback(responder()) end
                return #calls
            end,
            update=function() end,quit=function() end,
        }
    end
    function API.escape(value) return tostring(value):gsub('([^%w%-_%.~])',function(c)return string.format('%%%02X',c:byte())end) end
    return API
end
love={math={random=function()return 1234 end}}
local Model=require('app.model')
local passed,failed=0,0
local function check(name,fn)
    calls,responders={},{}
    local ok,err=pcall(fn)
    if ok then passed=passed+1;print('PASS '..name)
    else failed=failed+1;print('FAIL '..name..': '..tostring(err)) end
end
local function deck(id,format)
    return {id=id,name=id,format=format,description='',main=json.array(),sideboard=json.array(),commander=json.array()}
end
local function expect(value,message) assert(value,message) end

check('new deck and emptied zones retain JSON array contract',function()
    local model=Model.new();model:newDeck()
    local encoded=json.encode(model.editDeck)
    for _,section in ipairs({'main','sideboard','commander'}) do
        expect(encoded:find('"'..section..'":[]',1,true),'empty '..section..' serialized as object')
    end
    model:addCard({name='Forest'},'main',1);model:addCard({name='Forest'},'main',-1)
    expect(json.encode(model.editDeck):find('"main":[]',1,true),'removing last card erased array type')
end)

check('initial lobby selections match selected format',function()
    local model=Model.new()
    responders['catalog GET /decks']=function()return {decks={deck('commander-1','Commander'),deck('commander-2','Commander'),deck('modern-1','Modern'),deck('modern-2','Modern')}}end
    model:refreshDecks()
    expect(model:findDeck(model.playerDeckId).format==model.format,'player deck format differs from lobby')
    expect(model:findDeck(model.botDeckId).format==model.format,'bot deck format differs from lobby')
end)

local function commanderLobby()
    local model=Model.new();model.decks={deck('modern','Modern')}
    for i=1,6 do model.decks[#model.decks+1]=deck('commander-'..i,'Commander') end
    model:setLobbyFormat('Commander')
    return model
end

check('Commander defaults to four players with three separate bot selections',function()
    local model=commanderLobby()
    expect(model:lobbyPlayerCount()==4,'Commander did not offer four-player table')
    expect(model.playerDeckId=='commander-1','Human default deck changed')
    for i=1,3 do expect(model.botDeckIds[i]=='commander-'..(i+1),'Bot '..i..' lost its deck selection') end
    model:startGame();local body=calls[#calls].body
    expect(body.format=='Commander' and #body.bots==3,'Missing native multiplayer payload')
    expect(body.botDeck==nil,'Multiplayer payload also sent an ambiguous duel deck')
    for i=1,3 do expect(body.bots[i].name=='XMage Bot '..i and body.bots[i].deck.id==model.botDeckIds[i],'Bot name/deck order not stable') end
    expect(json.encode(body):find('"bots":[',1,true),'Bots did not serialize as JSON array')
end)

check('Commander supports five and six seats and preserves inactive bot decks',function()
    local model=commanderLobby();model:setLobbyPlayers(6);model:setBotDeck(5,'commander-2');model:setLobbyPlayers(4);model:setLobbyPlayers(6)
    expect(model.botDeckIds[5]=='commander-2','Shrinking table erased bot selection')
    model:startGame();expect(#calls[#calls].body.bots==5,'Six-player request lost a bot')
    model.gameBusy=false;model:setLobbyPlayers(5);model:startGame()
    expect(#calls[#calls].body.bots==4,'Five-player request lost a bot')
    model.gameBusy=false;model:setLobbyPlayers(3)
    expect(model:lobbyPlayerCount()==5,'Unsupported lobby count accepted')
end)

check('Constructed and Commander duels retain legacy request shape',function()
    local model=commanderLobby();model:setLobbyPlayers(2);model:startGame()
    expect(calls[#calls].body.botDeck.id==model.botDeckId and not calls[#calls].body.bots,'Commander duel changed transport shape')
    model.gameBusy=false;model:setLobbyFormat('Modern');model:startGame()
    expect(model:lobbyPlayerCount()==2 and calls[#calls].body.botDeck.id=='modern','Constructed match became multiplayer')
    expect(calls[#calls].body.deck.format=='Modern','Constructed match retained Commander deck')
end)

check('every multiplayer bot must have a deck in the selected format',function()
    local model=commanderLobby();model:setBotDeck(3,'missing');model:startGame()
    expect(#calls==0 and not model.gameBusy,'Missing bot deck reached engine')
    expect(model.toasts[#model.toasts].message:find('bot 3',1,true),'Missing seat not identified')
    model:setBotDeck(3,'modern');model:startGame()
    expect(#calls==0,'Mixed format multiplayer deck reached engine')
    expect(model.toasts[#model.toasts].message:find('Bot 3',1,true),'Wrong format seat not identified')
end)

check('deck refresh retains valid bot choices and replaces removed seats',function()
    local model=commanderLobby();model:setLobbyPlayers(6);model:setBotDeck(3,'commander-6')
    local refreshed={};for _,d in ipairs(model.decks) do if d.id~='commander-3' then refreshed[#refreshed+1]=d end end
    responders['catalog GET /decks']=function()return {decks=refreshed}end
    model:refreshDecks()
    expect(model.botDeckIds[3]=='commander-6','Valid bot selection changed after refresh')
    expect(model:findDeck(model.botDeckIds[2])~=nil,'Removed deck left a dangling seat')
    for i=1,5 do expect(model:findDeck(model.botDeckIds[i]).format=='Commander','Refresh selected wrong-format deck') end
end)

check('out-of-order collection refresh cannot restore removed lobby decks',function()
    local model=commanderLobby();model:refreshDecks();local older=calls[#calls];model:refreshDecks();local newer=calls[#calls]
    newer.callback({decks={deck('latest','Commander')}})
    older.callback({decks={deck('old','Commander')}})
    expect(#model.decks==1 and model.decks[1].id=='latest','Old collection response replaced latest list')
    expect(model.playerDeckId=='latest' and model.botDeckIds[3]=='latest','Seats no longer match current collection')
end)

check('opening a Commander deck fills all bot seats without changing its composition',function()
    local model=commanderLobby();local selected=model:findDeck('commander-5');selected.main=json.array({{name='Forest',count=99}})
    model:lobbyDeck(selected);model:startGame()
    expect(model.page=='lobby' and model.playerDeckId=='commander-5','Lobby lost selected player deck')
    expect(calls[#calls].body.deck.main[1].count==99,'Match setup changed deck quantities')
    expect(#calls[#calls].body.bots==3,'Use-in-lobby did not prepare all bot seats')
    local before=#calls;model:startGame();expect(#calls==before,'Starting twice queued a second game')
end)

check('negative boolean choices preserve JSON false',function()
    local model=Model.new();model:setGame({gameId='test',revision=1,prompt={id=7,type='boolean',choices={}}})
    model:answerChoice({id='no',responseType='boolean',value=false})
    expect(calls[#calls].body.value==false,'false response became '..tostring(calls[#calls].body.value))
    expect(calls[#calls].body.promptId==7,'answer lost prompt identity')
end)

check('older snapshots cannot replace a newer prompt',function()
    local model=Model.new()
    model:setGame({gameId='same-game',revision=10,prompt={id=8,type='string',choices={}}})
    model:setGame({gameId='same-game',revision=9,prompt={id=7,type='string',choices={}}})
    expect(model:prompt().id==8,'stale snapshot replaced newer prompt')
end)

check('JSON null prompt never creates an action',function()
    local model=Model.new();model:setGame(json.decode('{"gameId":"g","revision":1,"prompt":null}'))
    expect(model:prompt()==nil,'null prompt treated as playable choice')
    model:answer('boolean',true)
    expect(#calls==0,'answer sent without active prompt')
end)

check('saved false settings override true defaults',function()
    local model=Model.new()
    responders['catalog GET /health']=function()return {ready=true,index={state='ready'}}end
    responders['catalog GET /decks']=function()return {decks={}}end
    responders['catalog GET /settings']=function()return {manualTriggers=false,autoMana=false,showCardArt=false}end
    responders['engine GET /health']=function()return {ready=false}end
    model:update(0.01)
    expect(model.settings.autoMana==false,'autoMana false ignored')
    expect(model.settings.showCardArt==false,'showCardArt false ignored')
end)

check('trigger ordering sends stable left-to-right IDs',function()
    local model=Model.new()
    model:setGame({gameId='g',revision=1,prompt={id=11,type='order',choices={{id='a',label='first'},{id='b',label='second'}}}})
    model.promptOrder={model.promptOrder[2],model.promptOrder[1]};model:submitOrder()
    local body=calls[#calls].body
    expect(body.type=='order' and body.value[1]=='b' and body.value[2]=='a','drag order not preserved')
end)

check('practice rematch preserves its original deck payload and resets native prompt identity',function()
    local model=Model.new();model.game={gameId='finished',running=false};model.lastMatchRequest={format='Modern',deck=deck('original','Modern'),botDeck=deck('opponent','Modern')}
    model.answeredPrompt=5;model.actionBusy=true
    expect(model:rematch(),'finished practice match could not rematch')
    local call=calls[#calls]
    expect(call.path=='/session/start'and call.body.deck.id=='original','rematch changed original deck')
    call.body.deck.name='changed request copy'
    expect(model.lastMatchRequest.deck.name=='original','request mutated saved rematch payload')
    call.callback({gameId='rematched',running=true,prompt={id=5,type='ask',choices={}}})
    expect(model:prompt()and not model.gameBusy and not model.actionBusy,'old prompt/busy state survived rematch')
    expect(not model:rematch(),'running match allowed another rematch')
end)

check('room rematch is host-authorized and main menu preserves the private connection',function()
    local model=Model.new();model.game={running=false};model.roomConnectionId='private-local-connection';model.roomParticipantId='guest'
    model.room={phase='playing',hostId='host',config={kind='constructed'},canRematch=true}
    expect(not model:canRematch(),'guest could rematch')
    model.roomParticipantId='host';local endpoint
    function model:roomMutation(path)endpoint=path;return true end
    expect(model:rematch()and endpoint=='/rematch','host did not use its authenticated room')
    model:goMain();expect(model.page=='decks'and model.roomConnectionId=='private-local-connection','main menu closed or lost the room')
    model.replay={};expect(not model:canRematch(),'playback allowed rematch')
end)

check('new matches reset answered prompt and ordering IDs',function()
    local model=Model.new()
    model:setGame({gameId='old',revision=10,prompt={id=5,type='ask',choices={}}})
    model.answeredPrompt=5;model.orderPrompt=5;model.actionBusy=true
    model:setGame({gameId='new',revision=1,prompt={id=5,type='ask',choices={}}})
    expect(model:prompt() and model:prompt().id==5,'Old answered ID hid new match prompt')
    expect(not model.actionBusy,'Old action blocked new match')
end)

print(('Frontend model checks: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
