-- Real LÖVE/Slab + HTTP integration. Synthetic game data only exercises the UI;
-- it makes no claim about rules-engine behavior.
function love.errorhandler(message)
    io.stderr:write('FRONTEND FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function() return 1 end
end
local Slab=require('lib.Slab')
local Model=require('app.model')
local Renderer=require('app.renderer')
local View=require('app.view')
local model,renderer,view,stage,timer,draws,createdId,captured
local function expect(value,message) assert(value,message) end
local function nextStage(n) stage=n;timer=0;draws=0 end
local function makeGame()
    local forest={id='forest-ui',name='Forest',type_line='Basic Land — Forest',tapped=true}
    return {gameId='ui-fixture',revision=1,running=true,turn=3,phase='PRECOMBAT_MAIN',step='PRECOMBAT_MAIN',activePlayerId='human',
        players={{id='human',human=true,name='Interaction check',life=20,hand={{id='bolt-ui',name='Lightning Bolt'}},battlefield={forest},graveyard={},exile={},command={},libraryCount=52,mana={R=1}},
                 {id='bot',human=false,name='XMage bot UI fixture',life=18,handCount=5,battlefield={},graveyard={},exile={},libraryCount=51}},
        stack={{name='Trigger on stack'}},log={'Synthetic UI fixture: verifies rendering only'},
        prompt={id=100,type='order',message='Order triggered abilities',choices={{id='first',label='Draw a card'},{id='second',label='Gain 1 life'}},targets={},required=true}}
end
function love.load()
    Slab.SetINIStatePath(nil);Slab.Initialize({'nocursor'},true)
    model=Model.new();renderer=Renderer.new(model);view=View.new(Slab,model,renderer)
    stage=0;timer=0;draws=0
end
function love.update(dt)
    timer=timer+dt
    expect(timer<25,'Frontend stage '..stage..' timed out')
    model:update(dt);Slab.Update(dt);renderer:update(dt);model.settings.showCardArt=false;model.settings.sfxEnabled=false
    if stage==0 and #model.decks>=20 and model.catalogHealth.ready then
        expect(model:findDeck(model.playerDeckId).format=='Modern','Initial lobby player is not Modern')
        model:newDeck();createdId=model.editDeck.id;model.editDeck.name='Frontend integration temporary deck'
        model:saveDeck();nextStage(1)
    elseif stage==1 and model:findDeck(createdId) then
        local saved=model:findDeck(createdId)
        expect(#saved.main==0 and #saved.sideboard==0 and #saved.commander==0,'Empty deck zones corrupted across Love thread')
        print('FRONTEND PASS: empty deck round-trip through actual Love worker + service')
        model.search='Arclight Phoenix';model.searchFormat='Pioneer';model:searchChanged();nextStage(2)
    elseif stage==2 and not model.searchBusy and model.cards[1] and model.cards[1].name=='Arclight Phoenix' then
        nextStage(21)
    elseif stage==21 and draws>2 then
        local hit
        for _,candidate in ipairs(renderer.hits) do if candidate.kind=='search' and candidate.card.name=='Arclight Phoenix' then hit=candidate;break end end
        expect(hit,'Search card was not rendered')
        renderer:mousepressed(hit.x+hit.w/2,hit.y+hit.h/2,1,1)
        renderer:mousereleased(1000,450,1)
        nextStage(22)
    elseif stage==22 and #(model.mutationQueue or {})==0 then
        expect(model.count(model.editDeck,'main')==1,'Validated drag into deck panel did not add card')
        model:saveDeck();nextStage(3)
    elseif stage==3 and model:findDeck(createdId) and model.count(model:findDeck(createdId),'main')==1 then
        print('FRONTEND PASS: Pioneer search, card drag-and-drop, saved quantity')
        model:deleteDeck(model:findDeck(createdId));nextStage(4)
    elseif stage==4 and not model:findDeck(createdId) then
        expect(#model.decks==20,'Deleting test deck modified bundled library')
        model:setGame(makeGame());model.page='table';model.pollTimer=9999
        model.answer=function(_,kind,value)captured={kind=kind,value=value}end
        nextStage(5)
    elseif stage==5 and draws>3 then
        local a,b
        for _,hit in ipairs(renderer.hits) do if hit.kind=='order' then if hit.index==1 then a=hit else b=hit end end end
        expect(a and b,'Trigger ordering cards not rendered')
        renderer:mousepressed(a.x+a.w/2,a.y+a.h/2,1,1)
        renderer:mousereleased(b.x+b.w/2,b.y+b.h/2,1)
        expect(model.promptOrder[1].id=='second','Dragging triggers did not reorder')
        model:submitOrder();expect(captured.kind=='order' and captured.value[1]=='second','Trigger confirmation changed order')
        print('FRONTEND PASS: table, hand fan, zones, trigger drag and answer order rendered')
        love.graphics.captureScreenshot('frontend-table.png');nextStage(6)
    elseif stage==6 and draws>2 then
        local game=makeGame();game.revision=2;game.prompt={id=101,type='multi_amount',message='Divide damage',choices={},targets={},amountMessages={{label='First target',min=0,max=3,defaultValue=1},{label='Second target',min=0,max=3,defaultValue=2}}}
        model:setGame(game);nextStage(7)
    elseif stage==7 and draws>3 then
        love.graphics.captureScreenshot('frontend-amounts.png');model.settingsOpen=true;nextStage(8)
    elseif stage==8 and draws>3 then
        love.graphics.captureScreenshot('frontend-settings.png');nextStage(9)
    elseif stage==9 and draws>2 then
        print('FRONTEND PASS: divided amount prompts and settings rendered')
        print('FRONTEND COMPLETE: real service interactions passed; synthetic game fixture was rendering-only')
        love.event.quit(0)
    end
    view:build()
end
function love.draw()
    renderer:draw();Slab.Draw();renderer:drawForeground();renderer:drawToasts(love.graphics.getDimensions());draws=draws+1
end
function love.quit()if model then model:quit()end;Slab.OnQuit()end
