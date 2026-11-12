function love.errorhandler(message)
    io.stderr:write('QUIT STORAGE FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
function love.load()
    local API=require('app.api');local json=require('lib.json')
    local api=API.new();local validated,saved=false,false
    local deck={id='quit-check',name='Quit validation',format='Modern',description='',
        main=json.array({{name='Lightning Bolt',count=1}}),commander=json.array(),sideboard=json.array()}
    api:request('catalog','POST','/decks/validate',deck,function(result,err,code)
        assert(not err and code==200 and result.saveAllowed,'Validation callback did not finish')
        validated=true
        api:request('catalog','PUT','/ui-layout',{quitTest='callback-chain-committed',hand={x=.2,y=.8,w=.6,h=.2}},function(layout,saveError,status)
            assert(not saveError and status==200 and layout.quitTest=='callback-chain-committed','Chained write did not finish')
            saved=true
        end)
    end)
    -- Quit immediately, before the validation reply has arrived. Its callback
    -- must still be able to enqueue and finish the SQLite write.
    api:quit()
    assert(validated and saved,'Quit discarded a callback-generated SQLite write')
    print('QUIT STORAGE PASS: actual Love worker drained validation callback and chained SQLite PUT')
    love.event.quit(0)
end
