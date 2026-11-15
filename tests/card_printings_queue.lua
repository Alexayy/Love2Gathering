-- Headless real HTTP validation: artwork counts follow staged builder mutations.
local m,runner;local clock=0;local checks=0;local Model,json
local function check(ok,label)assert(ok,label);checks=checks+1;print('PRINTING QUEUE PASS '..label)end
local function ready(test,label)local deadline=clock+15;while not test()do assert(clock<deadline,label);coroutine.yield()end end
local function count(name)for _,e in ipairs(m.editDeck.main)do if e.name==name then return e.count end end;return 0 end
local function choice(name)for _,s in ipairs(m.editDeck.printingSelections or{})do if s.name==name then return s end end end
local function settle()ready(function()return not m.mutationBusy and#m.mutationQueue==0 end,'Queued validation did not finish')end
local function queued(name,delta)
 m.mutationQueue[#m.mutationQueue+1]={name=name,section='main',delta=delta};m:processCardQueue()
end
local function selectForest()
 m:showCardPrintings({name='Forest'},'main');ready(function()return not m.cardPrintingPicker.busy end,'Exact printing list did not load')
 check(m:selectCardPrinting('forest-b')and m:confirmCardPrinting(),'Actual printing response can be selected before builder edits')
end
local function scenario()
 m:openDeck({id='queue-fixture',name='Queue fixture',format='Modern',main={{name='Forest',count=60}},sideboard=json.array(),commander=json.array()});selectForest()
 local before=json.encode(m.editDeck);m:addCard({name='Forest'},'main',1)
 check(m.mutationBusy and json.encode(m.editDeck)==before,'A staged request does not mutate the live deck or its printing quantities')
 settle();check(count('Forest')==61 and choice('Forest').count==61 and not m.lastBuilderError,'Adding a selected-art copy passes real HTTP validation and retains its edition')
 queued('Forest',-1);settle();check(count('Forest')==60 and choice('Forest').count==60 and not m.lastBuilderError,'Queued one-copy removal validates the synchronized candidate before committing')
 m:addCard({name='Plains'},'main',1);settle();check(count('Plains')==1 and count('Forest')==60 and choice('Forest').count==60 and not choice('Plains'),'An unrelated card addition keeps per-name artwork counts independent')
 queued('Forest',-60);settle();check(count('Forest')==0 and not choice('Forest')and count('Plains')==1 and not m.lastBuilderError,'Removing the last selected-art copies validates without an orphan artwork entry')
 m:addCard({name='Forest'},'main',1);settle();selectForest();queued('Forest',-1);settle();check(count('Forest')==0 and not choice('Forest')and not m.lastBuilderError,'A selected single copy can be removed through actual asynchronous validation')
 m:addCard({name='Forest'},'main',1);settle();selectForest();m:showCardPrintings({name='Forest'},'main');ready(function()return not m.cardPrintingPicker.busy end,'Revision picker did not load');m:commitCard('Forest','main',-1)
 check(not m:confirmCardPrinting()and not choice('Forest'),'A newer deck revision still rejects a stale artwork confirmation')
 m:closeCardPrintings();m:addCard({name='Forest'},'main',1);settle();selectForest();queued('Forest',-1)
 m:openDeck({id='replacement',name='New opening',format='Modern',main={{name='Plains',count=60}},sideboard=json.array(),commander=json.array()})
 local done=false;m:request('catalog','GET','/health',nil,function()done=true end,true);ready(function()return done end,'Callback fence did not drain')
 check(m.editDeck.id=='replacement'and count('Plains')==60 and not m.editDeck.printingSelections,'A prior editor queued response cannot mutate the new deck opening')
 print('PRINTING QUEUE COMPLETE '..checks..' checks');love.event.quit(0)
end
function love.load()
 local root=assert(os.getenv('LOVE2GATHERING_QUEUE_TEST_ROOT'));package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
 Model=require('app.model');json=require('lib.json');m=Model.new();runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<60,'Headless queue acceptance timed out');m.api:update()
 if coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 love.timer.sleep(.002)
end
function love.quit()if m then m.api:quit()end end
function love.errorhandler(message)io.stderr:write(tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
