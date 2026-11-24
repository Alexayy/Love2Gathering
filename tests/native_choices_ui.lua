-- Actual main callbacks/API/Slab over a test-only HTTP facade. Initial zones
-- are deterministic fixtures; responses and resulting effects are native.
function love.errorhandler(message)io.stderr:write('NATIVE CHOICES UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
local json=require('lib.json');local Layout=require('app.layout');local S=require('lib.Slab');local API=require('app.api');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences')
local m,r,v,p,Cursor,Window;local mouse={x=2,y=2};local pressed={};local clock,wake=0,0;local runner;local buttons,checks,shots={},{},{};local reports={};local strong={};local sceneBusy=false
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('NATIVE CHOICES UI PASS '..label);io.stdout:flush()end
local function wait(t)wake=clock+(t or .1);coroutine.yield()end
local function ready(fn,label,seconds)local deadline=clock+(seconds or 12);while not fn()do if clock>=deadline then io.stderr:write(json.encode({prompt=m and m.game and m.game.prompt,actionBusy=m and m.actionBusy,toasts=m and m.toasts})..'\n');error(label)end;wait(.06)end end
local function request(method,path,body)
    local done,result,problem=false
    m.api:request('engine',method,path,body,function(data,err,code)result=data;problem=err or(code and code>=400 and json.encode(data));done=true end)
    ready(function()return done end,'Native request did not finish: '..path);assert(not problem,tostring(problem));return result
end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;love.mousemoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy,false)end
local function click(box,button)
    assert(box,'Missing native UI control');button=button or 1;move(box.x+box.w/2,box.y+box.h/2);wait(.07);pressed[button]=true;love.mousepressed(mouse.x,mouse.y,button,false,1);wait(.07);pressed[button]=nil;love.mousereleased(mouse.x,mouse.y,button,false,1);wait(.18)
end
local function drag(hit,drop,index)
    assert(hit and drop,'Missing native drag geometry');move(hit.x+hit.w/2,hit.y+hit.h/2);wait(.06);pressed[1]=true;love.mousepressed(mouse.x,mouse.y,1,false,1);wait(.06)
    check(v.cardChoiceDrag~=nil,'Actual main input routes a native card drag before board input')
    move(drop.x+12+(index or 0)*drop.cardW,drop.y+drop.h/2);wait(.12);pressed[1]=nil;love.mousereleased(mouse.x,mouse.y,1,false,1);wait(.2)
end
local function shot(name)move(2,2);wait(.12);shots[#shots+1]=name;wait(.16)end
local function fixture(name)
    sceneBusy=true;ready(function()return not m.polling and not m.actionBusy end,'Prior native poll did not finish');m.game=nil;m.answeredPrompt=nil;m.actionBusy=false;m.priorityBusy=false;v.cardChoiceState=nil;v.cardChoiceHits={};v.cardChoiceDrag=nil;m.inspectCard=nil;m.zoneView=nil
    local opened=request('POST','/fixture/'..name,{});assert(opened.fixture and opened.scenario==name,'Not a native fixture server')
    local state=request('GET','/session/state');m:setGame(state);m.page='table';m.pollTimer=0;sceneBusy=false
    ready(function()return m.game and m.game.players and#m.game.players==2 end,'Native fixture board did not arrive');wait(.25)
end
local function finish(name)
    local report
    ready(function()report=request('GET','/fixture/result');return report.nativeResult and report.nativeResult.done end,'Native '..name..' operation did not finish',15)
    assert(report.scenario==name and not report.nativeResult.error,json.encode(report));reports[name]=report;return report
end
local function cardHit(name)
    for _,hit in ipairs(r.hits or {})do if hit.card and hit.card.name==name and(hit.kind=='permanent'or hit.kind=='card')then return hit end end
end
local function nativeDone()
    local prompt=m:prompt();for _,choice in ipairs(prompt and prompt.choices or {})do if choice.responseType=='boolean'and choice.value==true then return buttons[choice.label]end end
end
local function chooseBlocker(blocker,attacker)
    ready(function()return m:prompt()and m:prompt().combat and m:prompt().combat.role=='blockers'and cardHit(blocker)end,'Blocker stage did not arrive')
    local old=m:prompt().id;click(cardHit(blocker));ready(function()return m:prompt()and m:prompt().id~=old and m:prompt().combat and not m.actionBusy end,'Native blocker response did not arrive')
    if m:prompt().combat.role=='block_target'then click(cardHit(attacker));ready(function()return m:prompt()and m:prompt().combat and m:prompt().combat.role=='blockers'and not m.actionBusy end,'Native blocker assignment did not return')end
end
local function scenario()
    ready(function()return m.catalogHealth.ready end,'Temporary artwork catalog is not ready',20)
    for _,kind in ipairs({'scry','surveil'})do
        fixture(kind);ready(function()return m:prompt()and m:prompt().cardPanel and m:prompt().cardPanel.kind==kind and#(v.cardChoiceHits or {})==3 end,'Native '..kind..' card panel did not open')
        local prompt=m:prompt();local cards=prompt.cardPanel.cards;local top1,top2,moved=cards[1],cards[2],cards[3]
        ready(function()local total=0;for _,c in ipairs(cards)do local data=m:cardData(c);if data and m:getArt(data,true)then total=total+1 end end;return total==3 end,'Real card images did not load from temporary catalog',25)
        local before=request('GET','/fixture/result');check(#before.acceptedActions==0,'Native '..kind..' opens without injected answers')
        drag(v.cardChoiceHits[3],v.cardChoiceDrops[2]);drag(v.cardChoiceHits[2],v.cardChoiceDrops[1],0)
        local staged=request('GET','/fixture/result');check(#staged.acceptedActions==0,'Native '..kind..' arrangement sends no responses before actual Confirm')
        check(v.cardChoiceState.rows.top[1]==tostring(top2.choiceId or top2.id),'Native '..kind..' Top row preserves the user’s requested first card')
        shot(kind..'-arranged');click(buttons.Confirm);local report=finish(kind);local native=report.nativeResult
        if kind=='scry'then
            local library=native.libraryTopToBottom
            check(library[1].id==top2.id and library[2].id==top1.id and library[#library].id==moved.id,'Actual native scry produces the requested Top order and Bottom instance')
            check(#native.graveyard==0,'Actual native scry leaves the graveyard unchanged')
        else
            check(native.libraryTopToBottom[1].id==top2.id and native.libraryTopToBottom[2].id==top1.id,'Actual native surveil produces the requested Top order')
            check(#native.graveyard==1 and native.graveyard[1].id==moved.id,'Actual native surveil moves exactly the dragged instance to Graveyard')
        end
        check(#report.acceptedActions==3 and report.acceptedActions[1].value==moved.id and report.acceptedActions[2].value==false and report.acceptedActions[3].value==top1.id,'Native '..kind..' accepts each UUID/Done once and automatically places its final card')
        wait(.2)
    end
    fixture('look');local looked=finish('look');ready(function()return #(v.cardChoiceHits or {})>0 and buttons.Close end,'Retained native looked-at popup did not open')
    check(looked.nativeResult.nativeTransientListCleared and m.game.lookedAt[1].id and v.cardChoiceHits[1].card.id==looked.nativeResult.lookedAtCardId,'Native retained look identity opens its entitled card after the transient list has cleared')
    local viewed=v.cardChoiceHits[1].card;ready(function()return m:getArt(m:cardData(viewed),true)end,'Real looked-at artwork did not load',20);shot('native-look-at')
    click(v.cardChoiceHits[1],3);check(m.inspectCard and m.inspectCard.id==viewed.id,'Middle-click opens details of the native looked-at card')
    click(buttons['Close details']);click(buttons.Close);wait(.25);local closedLook=request('GET','/fixture/result');reports.look=closedLook
    check(#closedLook.acceptedActions==0 and#v.cardChoiceHits==0,'Closing the retained native look popup sends no engine answer and keeps that identity dismissed')
    fixture('cancel');ready(function()return m:prompt()and m:prompt().cancelChoice and buttons['Done / Cancel']end,'Native pre-sacrifice cancel was not offered');shot('woe-strider-cancel')
    local prompt=m:prompt();check(prompt.cancelScope=='pending_action'and prompt.pendingAction and prompt.pendingAction.canCancel==true and prompt.cancelChoice.value==false,'Woe Strider exposes a native pre-commit cancel response')
    click(buttons['Done / Cancel']);local canceled=finish('cancel')
    check(canceled.nativeResult.activationAccepted==false and canceled.nativeResult.sacrificeStillPresent and canceled.nativeResult.striderStillPresent and canceled.nativeResult.stackSize==0,'Actual native Cancel preserves the sacrifice and Strider without adding an activation')
    check(#canceled.acceptedActions==1 and canceled.acceptedActions[1].type=='boolean'and canceled.acceptedActions[1].value==false,'Only the native false cancel response enters accepted action history')
    fixture('angel');local angelReport=finish('angel');ready(function()return cardHit('Angel of Vitality')and strong['5/5']end,'Angel native5/5 badge did not render')
    local angel=cardHit('Angel of Vitality').card;local printing=m:cardData(angel)
    check(angel.power=='5'and angel.toughness=='5'and angel.printing.power=='2'and angel.printing.toughness=='2','Native Angel live stats remain5/5 while its printing remains2/2')
    check(printing.power=='5'and printing.toughness=='5'and strong['5/5'],'Catalog enrichment preserves the native5/5 badge sent to the actual renderer')
    ready(function()return m:getArt(m:cardData(angel),true)end,'Angel artwork did not load',20);shot('angel-five-five')
    fixture('combat');ready(function()return m:prompt()and m:prompt().combat and m:prompt().combat.role=='blockers'end,'Native combat blocker prompt did not arrive')
    local metadata=m:prompt().combat;local reasons={};for _,b in ipairs(metadata.blockers or {})do for _,unavailable in ipairs(b.unavailable or {})do for _,rule in ipairs(unavailable.rules or {})do reasons[#reasons+1]=rule end end end
    check(#reasons>0,'Actual native blocker preview supplies restriction rule text for the instruction bubble')
    local menace;for _,group in ipairs(m.game.combat.groups or {})do if group.minBlockers==2 then menace=group end end
    check(menace~=nil,'Actual native combat projection retains the two-blocker requirement separately from pair legality')
    click(cardHit('Giant Spider'));ready(function()return m:prompt()and m:prompt().combat and m:prompt().combat.role=='block_target'end,'Giant Spider native target stage did not open')
    local target=m:prompt();local ledger=request('GET','/fixture/result');local count=#ledger.acceptedActions;local flying
    for _,hit in ipairs(r.hits)do if hit.card and hit.card.name=='River Boa'and not m:canSelect(hit.card.id)then flying=hit;break end end
    assert(flying,'Native unoffered landwalk attacker fixture not found');click(flying);local after=request('GET','/fixture/result')
    check(#after.acceptedActions==count and m:prompt()and m:prompt().id==target.id,'Clicking a native-unoffered landwalk block cannot submit an engine answer')
    click(cardHit('Boggart Brute'));ready(function()return m:prompt()and m:prompt().combat and m:prompt().combat.role=='blockers'end,'Native first menace block did not return');shot('combat-one-blocker')
    local beforeDone=m:prompt().id;click(nativeDone());ready(function()return m:prompt()and m:prompt().id~=beforeDone and m:prompt().combat and m:prompt().combat.role=='blockers'end,'Native single-blocker formation was not rejected')
    local cleared=true;for _,group in ipairs(m.game.combat.groups or {})do if group.minBlockers==2 and#group.blockerIds>0 then cleared=false end end
    check(cleared,'XMage rejects and clears a lone blocker against the native two-blocker attacker')
    chooseBlocker('Grizzly Bears','Boggart Brute');chooseBlocker('Giant Spider','Boggart Brute');shot('combat-two-blockers');click(nativeDone());local combat=finish('combat');local valid
    for _,group in ipairs(combat.nativeResult.combat.groups or {})do if group.minBlockers==2 then valid=#group.blockerIds==2 end end
    check(valid,'Two actual board blocker assignments satisfy native combat validation')
    local out=assert(io.open('/tmp/love2gathering-native-choices-ui-report.json','w'));out:write(json.encode({passed=true,checks=checks,scenes=reports,scope='Actual main.lua input/update/draw callbacks, Slab and asynchronous API against test-only native initial zones; production Session.action and HumanPlayer responses; native final ordering/look-at/cancellation/combat; not a full production-deck game'}));out:close();print('NATIVE CHOICES UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
local originalNew=API.new;API.new=function(options)options=options or{};options.enginePort=assert(tonumber(os.getenv('LOVE2GATHERING_ENGINE_PORT')));options.catalogPort=assert(tonumber(os.getenv('LOVE2GATHERING_CATALOG_PORT')));return originalNew(options)end
local modelNew=Model.new;Model.new=function(...)m=modelNew(...);return m end
local rendererNew=Renderer.new;Renderer.new=function(...)r=rendererNew(...);local original=r.strong;r.strong=function(self,text,...)strong[tostring(text)]=true;return original(self,text,...)end;return r end
local viewNew=View.new;View.new=function(...)v=viewNew(...);return v end
local preferencesNew=Preferences.new;Preferences.new=function(...)p=preferencesNew(...);return p end
assert(love.filesystem.load('application.lua'))()
local appLoad,appUpdate,appDraw,appQuit=love.load,love.update,love.draw,love.quit
function love.load()
    appLoad({});Cursor=require('lib.Slab.Internal.Core.Cursor');Window=require('lib.Slab.Internal.UI.Window')
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return pressed[button]==true end
    m.loaded=true;m.settingsLoaded=true;m.page='table';m.uiLayout={};m.settings.showCardArt=true;m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.particles=false;m.settings.animations=false;m.settings.uiScale=1;m.settings.renderScale=1;m.settings.vsync=false;m.settings.frameLimit=0;p.appliedLoaded=true;p:apply(true)
    for _,name in ipairs({'Button','CheckBox'})do local original=S[name];S[name]=function(a,b,c)local result=original(a,b,c);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);buttons[name=='CheckBox'and b or a]={x=x,y=y,w=w,h=h};return result end end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    clock=clock+dt;assert(clock<180,'Native UI acceptance exceeded180 seconds');buttons={};appUpdate(dt)
    if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
end
function love.draw()
    appDraw()
    if #shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)local out=assert(io.open('/tmp/love2gathering-native-choices-'..name..'.png','wb'));out:write(data:encode('png'):getString());out:close()end)end
end
function love.quit()if appQuit then return appQuit()end end
function love.errorhandler(message)io.stderr:write('NATIVE CHOICES UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
