function love.errorhandler(message)
    io.stderr:write('BUILDER FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
local Model=require('app.model')
local m,stage,elapsed,id,baseline
local function advance(n)stage=n;elapsed=0 end
local function idle()return not m.mutationBusy and #(m.mutationQueue or {})==0 end
function love.load()m=Model.new();stage=0;elapsed=0 end
function love.update(dt)
    elapsed=elapsed+dt;assert(elapsed<20,'Stage '..stage..' timed out')
    m:update(dt)
    if stage==0 and m.loaded and m.catalogHealth.ready and #m.decks>=20 then
        baseline=#m.decks;m.format='Modern';m:newDeck();id=m.editDeck.id;m.editDeck.name='Builder acceptance temporary deck'
        for _=1,5 do m:addCard({name='Lightning Bolt'})end
        advance(1)
    elseif stage==1 and idle()then
        assert(m.count(m.editDeck,'main')==4,'Fifth copy appeared or a valid click was lost')
        assert(m.lastBuilderError and m.lastBuilderError:find('maximum 4',1,true),'Copy refusal lacked its cause')
        m:saveDeck();advance(2)
    elseif stage==2 and m:findDeck(id)then
        assert(m:findDeck(id).draft,'Incomplete legal deck was not saved as an explicit draft')
        m:changeDeckFormat('Standard');m:saveDeck();advance(3)
    elseif stage==3 and m.validation and m.validation.errors[1] and m.validation.errors[1].code=='format_legality'then
        assert(m:findDeck(id).format=='Modern','Illegal format switch overwrote the saved deck')
        m:addCard({name='Lightning Bolt'},'main',-4);m:changeDeckFormat('Commander')
        m:addCard({name='Giada, Font of Hope'},'commander',1)
        m:addCard({name='Hare Apparent'},'main',99)
        m:addCard({name='Hare Apparent'},'main',1)
        advance(4)
    elseif stage==4 and idle()then
        assert(m.count(m.editDeck,'main')==99 and m.count(m.editDeck,'commander')==1,'Commander size or unlimited-copy override failed')
        assert(m.lastBuilderError and m.lastBuilderError:find('100',1,true),'101st card was not rejected')
        m:setDeckCover({name='Hare Apparent'});m:saveDeck();advance(5)
    elseif stage==5 and m:findDeck(id) and m:findDeck(id).format=='Commander'then
        local saved=m:findDeck(id)
        assert(not saved.draft and saved.coverCard=='Hare Apparent','Complete deck or cover did not persist')
        m:deleteDeck(saved);advance(6)
    elseif stage==6 and not m:findDeck(id)then
        assert(#m.decks==baseline,'Acceptance run changed the existing collection')
        print('BUILDER PASS: real worker/API queued copy guards, legal draft saving, rejected format switch, Commander 100-card cap, oracle unlimited copies and cover persistence')
        love.event.quit(0)
    end
end
function love.quit()if m then m:quit()end end
