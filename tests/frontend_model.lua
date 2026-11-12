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
