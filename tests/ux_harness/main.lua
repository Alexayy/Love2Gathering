function love.errorhandler(message)
    io.stderr:write('UX FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Layout=require('app.layout');local Preferences=require('app.preferences');local json=require('lib.json')
local m,r,v,prefs,stage,timer,draws,cases,caseIndex,caseFrames,mouse,mouseDown,windows,buttons,controls,selections,reports,captured,fixture,dragState
local Cursor
local function expect(condition,message)assert(condition,message)end
local function card(name,id,extra)local c={id=id,name=name,type=(name=='Mountain' or name=='Sacred Foundry') and '[Land]' or (name=='Goblin Guide' or name=='Monastery Swiftspear' or name=='Arclight Phoenix') and '[Creature]' or '[Instant]'};for k,val in pairs(extra or {})do c[k]=val end;return c end
local function game()
    local hand={card('Mountain','hand-land'),card('Goblin Guide','hand-guide'),card('Lightning Bolt','hand-bolt'),card('Arclight Phoenix','hand-phoenix'),card('Boros Charm','hand-charm'),card('Lava Spike','hand-lava'),card('Sacred Foundry','hand-foundry')}
    local humanField={},{}
    humanField={card('Mountain','human-land1',{tapped=true}),card('Mountain','human-land2'),card('Mountain','human-land3'),card('Sacred Foundry','human-land4'),card('Goblin Guide','human-guide',{power='2',toughness='2',attacking=true}),card('Monastery Swiftspear','human-swift',{power='2',toughness='3',counters={['+1/+1']=1}})}
    return {gameId='UX-SYNTHETIC-FIXTURE',revision=10,running=true,turn=4,phase='Precombat Main',step='Precombat Main',activePlayerId='human',priorityPlayerId='human',
        players={{id='human',name='UI review — human',human=true,life=17,hand=hand,handCount=#hand,libraryCount=47,battlefield=humanField,graveyard={card('Lightning Bolt','human-grave')},exile={card('Lava Spike','human-exile')},command={},mana={R=2,W=1}},
        {id='bot',name='XMage bot — UI fixture',human=false,life=13,hand={},handCount=7,libraryCount=46,battlefield={card('Mountain','enemy-land1',{tapped=true}),card('Mountain','enemy-land2'),card('Sacred Foundry','enemy-land3'),card('Goblin Guide','enemy-guide',{power='2',toughness='2'}),card('Arclight Phoenix','enemy-phoenix',{power='3',toughness='2'})},graveyard={card('Lava Spike','enemy-grave')},exile={},command={},mana={}}},
        stack={{id='stack-one',name='Lightning Bolt'}},exile={},log={'Synthetic UX fixture. This checks rendering and interaction, not rules execution.','Outlined cards are the fixture’s explicit legal actions.'},
        prompt={id=200,type='select',message='Play spells and abilities',required=false,actionable={'hand-land','hand-bolt','human-land2'},targets={'hand-land','hand-bolt','human-land2'},choices={{id='done',label='Pass / Done',responseType='boolean',value=true}}}}
end
local function writeImage(filename)
    love.graphics.captureScreenshot(function(data)
        if filename:find('settings',1,true) and controls['setting-windowMode'] then
            for _,id in ipairs({'setting-windowMode','setting-msaa'})do
                local box=controls[id];local x=math.floor((box.x+8)*Layout.scale);local y=math.floor((box.y+box.h*.5)*Layout.scale);local rr,gg,bb=data:getPixel(x,y)
                expect(bb>.14 and gg>.10,'Settings control is constructed but invisible after nested input clipping: '..id..' RGB '..rr..','..gg..','..bb)
            end
            reports[#reports].pixelVisibility='Window mode and MSAA dropdown backgrounds rendered after Resolution'
        end
        local f=assert(io.open('/tmp/love2gathering-ux-'..filename..'.png','wb'));f:write(data:encode('png'):getString());f:close()
    end)
end
local function setMode(case)
    m.settings.resolution=case.w..'x'..case.h;m.settings.windowMode='Windowed';m.settings.vsync=false;m.settings.msaa=0;m.settings.uiScale=case.ui or 1;m.settings.renderScale=case.render or 1
    m.settings.textureFilter='linear';m.settings.animations=false;m.settings.particles=true;m.settings.showTooltips=false;m.settings.sfxEnabled=false;m.settings.showCardArt=true
    prefs:apply(true);m.settingsLoaded=true;prefs.appliedLoaded=true
    r.hover=nil;r.drag=nil;r.poses={};r.cardRects={};m.settingsOpen=false;m.zoneView=nil;m.inspectCard=nil;v.builderPopup=nil;m.toasts={};m.page=case.page
    if case.page=='table' then fixture=game();m:setGame(fixture);m.pollTimer=99999 end
    if case.variant=='mulligan' then
        fixture.phase='';fixture.step='null';fixture.prompt={id=201,type='ask',message='Mulligan down to 6 cards?',choices={},actionable={},mulligan={downTo=6,free=false,keepChoice={id='keep',label='Keep',responseType='boolean',value=false},mulliganChoice={id='mulligan',label='Mulligan',responseType='boolean',value=true}}};m:setGame(fixture)
    elseif case.variant=='wheel' then
        fixture.prompt={id=202,type='choose_ability',message='Choose mana ability',actionable={},choices={},manaWheel={sourceId='human-land2'}}
        for _,symbol in ipairs({'W','U','B','R','G'})do fixture.prompt.choices[#fixture.prompt.choices+1]={id='mana-'..symbol,label='Add {'..symbol..'}',manaColors={symbol},responseType='uuid'}end;m:setGame(fixture)
    elseif case.variant=='order' then
        fixture.prompt={id=203,type='order',message='Order simultaneous triggered abilities',actionable={},choices={{id='trigger-one',label='Whenever another creature enters, gain 1 life.'},{id='trigger-two',label='Whenever you gain life, put a +1/+1 counter on this creature.'},{id='trigger-three',label='Draw a card, then discard a card.'}}};m:setGame(fixture)
    elseif case.page=='builder' then
        m:openDeck(m:findDeck('pioneer-izzet-phoenix'));m.search='Phoenix';m:searchChanged()
    elseif case.page=='decks' then m.selectedDeck='modern-boros-burn'
    elseif case.variant=='settings' then m.settingsOpen=true;v.settingsTab='Graphics'
    elseif case.variant=='popup' then m.inspectCard=card('Arclight Phoenix','inspect') end
    caseFrames=0;timer=0;draws=0;dragState=nil;buttons={};windows={};controls={};selections={}
end
function love.load()
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor')
    m=Model.new();r=Renderer.new(m);v=View.new(S,m,r);prefs=Preferences.new(m,S);v.preferences=prefs
    local originalNav=r.drawNav;r.drawNav=function(self,...)self.navCalledThisDraw=true;return originalNav(self,...)end
    mouse={x=1,y=1};love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and mouseDown or false end
    local originalWindow=v.window
    v.window=function(self,id,...)
        originalWindow(self,id,...);local x,y=S.GetWindowPosition();local w,h=S.GetWindowSize();windows[id]={x=x,y=y,w=w,h=h}
    end
    local originalButton=S.Button
    S.Button=function(label,options)
        local result=originalButton(label,options);local x,y,w,h=Cursor.GetItemBounds();buttons[label]={x=x,y=y,w=w,h=h};return result
    end
    local originalCombo=S.BeginComboBox
    S.BeginComboBox=function(id,options)local result=originalCombo(id,options);local x,y,w,h=Cursor.GetItemBounds();controls[id]={x=x,y=y,w=w,h=h};return result end
    local originalCheckBox=S.CheckBox
    S.CheckBox=function(value,label,options)local result=originalCheckBox(value,label,options);local x,y,w,h=Cursor.GetItemBounds();controls[label]={x=x,y=y,w=w,h=h};return result end
    local originalSelectable=S.TextSelectable
    S.TextSelectable=function(label,options)local result=originalSelectable(label,options);local x,y,w,h=Cursor.GetItemBounds();selections[tostring(label)]={x=x,y=y,w=w,h=h};return result end
    captured={};m.answer=function(_,kind,value)captured[#captured+1]={kind=kind,value=value}end
    reports={};stage='load';timer=0;draws=0;caseIndex=0
    cases={
        {name='1440-decks',w=1440,h=900,page='decks',wait=3},
        {name='1440-builder',w=1440,h=900,page='builder',wait=1.3},
        {name='1440-table',w=1440,h=900,page='table',wait=1},
        {name='1440-mulligan',w=1440,h=900,page='table',variant='mulligan',wait=.3},
        {name='1440-wheel',w=1440,h=900,page='table',variant='wheel',wait=.3},
        {name='1440-order',w=1440,h=900,page='table',variant='order',wait=.3},
        {name='1120-table',w=1120,h=720,page='table',wait=.3},
        {name='1120-builder',w=1120,h=720,page='builder',wait=.7},
        {name='2560-table',w=2560,h=1080,page='table',wait=.3},
        {name='2560-table-scaled',w=2560,h=1080,ui=1.25,render=.75,page='table',wait=.3},
        {name='2560-settings-scaled',w=2560,h=1080,ui=1.25,render=.75,page='table',variant='settings',wait=.3},
        {name='1440-popup',w=1440,h=900,ui=1.25,render=.75,page='table',variant='popup',wait=.3},
    }
    if os.getenv('LOVE2GATHERING_UX_ONLY')=='settings' then local filtered={};for _,case in ipairs(cases)do if case.variant=='settings' then filtered[#filtered+1]=case end end;cases=filtered
    elseif os.getenv('LOVE2GATHERING_UX_ONLY')=='builder' then local filtered={};for _,case in ipairs(cases)do if case.page=='builder' then filtered[#filtered+1]=case end end;cases=filtered
    elseif os.getenv('LOVE2GATHERING_UX_ONLY')=='match-layout' then local filtered={};for _,case in ipairs(cases)do if case.page=='table' and case.variant~='settings' and case.variant~='popup' then filtered[#filtered+1]=case end end;cases=filtered end
    if os.getenv('LOVE2GATHERING_UX_WIDTH')then local wanted=tonumber(os.getenv('LOVE2GATHERING_UX_WIDTH'));local filtered={};for _,case in ipairs(cases)do if case.w==wanted then filtered[#filtered+1]=case end end;cases=filtered end
end
local function clickSlab(button,pressed)
    local x=(button.x+button.w/2)*Layout.scale;local y=(button.y+button.h/2)*Layout.scale
    mouse.x,mouse.y=x,y;S.OnMouseMoved(x,y,0,0);mouseDown=pressed
    if pressed then S.OnMousePressed(x,y,1,false,1)else S.OnMouseReleased(x,y,1,false,1)end
end
local function inspect(case)
    local w,h=Layout.dimensions();local actualW,actualH=love.graphics.getDimensions();local record={name=case.name,requested={case.w,case.h},physical={actualW,actualH},logical={w,h},uiScale=Layout.scale,renderScale=m.settings.renderScale,checks={}}
    if case.page=='table' then
        local L=Layout.table(w,h)
        if os.getenv('LOVE2GATHERING_UX_ONLY')=='match-layout' then
            expect(not r.navCalledThisDraw,'Global brand/navigation header still renders on match page')
            expect(L.board.y==16 and L.sidebar.y==16,'Match board/sidebar did not reclaim header space')
            expect(buttons.Settings and buttons.Lobby,'Compact Settings/Lobby access is missing from action pane')
            local battlefield=r.cardRects['human-guide'];expect(battlefield,'Fixture creature missing')
            local handTop=h
            for _,hit in ipairs(r.hits)do if hit.kind=='hand'then handTop=math.min(handTop,hit.y)end end
            for _,id in ipairs({'human-land1','human-land2','human-land3','human-land4'})do
                local mana=r.cardRects[id];expect(mana and mana.y>=battlefield.y+20,'Mana row is not below the creature battlefield')
                expect(mana.y+mana.h<=handTop-8,'Mana row overlaps the hand')
            end
            record.checks[#record.checks+1]='Match header hidden, space reclaimed, lower mana row clear of hand'
        end
        expect(L.rowH>70,'Battlefield rows too short');expect(L.fieldW>300,'Battlefield too narrow')
        local hand=0;local minW=1000
        for _,hit in ipairs(r.hits)do
            if hit.kind=='hand' then hand=hand+1;minW=math.min(minW,hit.w);expect(hit.x>=L.board.x-2 and hit.x+hit.w<=L.board.x+L.board.w+2,'Hand rectangle extends outside board')end
            if hit.kind=='mana' then expect(hit.x>=0 and hit.y>=0 and hit.x+hit.w<=w and hit.y+hit.h<=h,'Mana wheel outside viewport')end
        end
        expect(hand==7,'Seven-card hand not rendered');expect(minW>=100,'Hand cards became too small')
        record.handWidth=minW;record.checks[#record.checks+1]='Hand fan, battlefield and wheel bounds'
        local before=#captured
        if not case.variant then
            expect(m:canSelect('hand-bolt'),'Explicit legal action missing');expect(not m:canSelect('hand-guide'),'Non-actionable card became legal')
            expect(not m:selectCard({id='hand-guide'}),'Illegal card was selected');expect(#captured==before,'Non-actionable click sent an answer')
            local hit;for _,candidate in ipairs(r.hits)do if candidate.y==L.phaseY and candidate.action then hit=candidate;break end end
            expect(hit,'Phase marker missing');r:mousepressed(hit.x+hit.w/2,hit.y+hit.h/2,1,1)
            expect(#captured==before,'Preview phase marker sent an engine action');record.checks[#record.checks+1]='Legal outlines and preview-only phase marker'
        elseif case.variant=='wheel' then
            local hit;for _,candidate in ipairs(r.hits)do if candidate.kind=='mana' then hit=candidate;break end end
            expect(hit,'Mana wheel choices missing');r:mousepressed(hit.x+hit.w/2,hit.y+hit.h/2,1,1)
            expect(#captured==before+1 and captured[#captured].kind=='uuid','Mana wheel did not send chosen synthetic engine action');record.checks[#record.checks+1]='Mana wheel choice dispatch'
        elseif case.variant=='order' then
            local first,last;for _,hit in ipairs(r.hits)do if hit.kind=='order' then if hit.index==1 then first=hit elseif hit.index==3 then last=hit end end end
            expect(first and last,'Ordering cards missing');r:mousepressed(first.x+first.w/2,first.y+first.h/2,1,1);r:mousereleased(last.x+last.w/2,last.y+last.h/2,1)
            expect(m.promptOrder[3].id=='trigger-one','Trigger drag order wrong');m:submitOrder();expect(captured[#captured].kind=='order','Order answer was not submitted');record.checks[#record.checks+1]='Trigger drag and submitted left-to-right array'
        elseif case.variant=='mulligan' then
            local win=windows.mulligan;expect(win and math.abs((win.x+win.w/2)-(L.board.x+L.board.w/2))<20,'Mulligan is not centered over table')
            expect(buttons.Keep and buttons['Mulligan Down to 6'],'Centered mulligan actions missing');record.checks[#record.checks+1]='Centered Keep/Mulligan controls'
        elseif case.variant=='settings' then
            local win=windows.settings;expect(win and win.x>=0 and win.y>=0 and win.x+win.w<=w+2 and win.y+win.h<=h+2,'Settings outside logical viewport')
            expect(prefs.canvas and prefs.canvas:getWidth()==math.floor(actualW*.75) and prefs.canvas:getHeight()==math.floor(actualH*.75),'Render scale canvas not applied');local resolution=controls['setting-resolution'];local windowMode=controls['setting-windowMode'];local vsync=controls['Vertical sync']
            expect(resolution and windowMode and vsync,'Graphics display controls not constructed')
            expect(windowMode.y>resolution.y and vsync.y>windowMode.y and windowMode.y<h-70,'Graphics controls fail to flow visibly below Resolution: '..json.encode(controls))
            record.graphicsControls=controls;record.checks[#record.checks+1]='Scaled settings display controls flow and lower-resolution scene canvas'
        end
    elseif case.page=='builder' then
        if case.w==1120 then for key,entry in pairs(r.assets.iconCache)do if key:find('button|save|Save|98|34',1,true)then local data=entry.image:newImageData();local file=assert(io.open('/tmp/love2gathering-save-source.png','wb'));file:write(data:encode('png'):getString());file:close()end end end
        local b=require('app.builder').layout(w,h);expect(b.search.x>=0 and b.list.x+b.list.w<=w,'Builder panels outside viewport');expect(b.grid.h>150 and b.cardW>=60,'Builder search cards clipped')
        expect(#m.cards>0,'Real catalog card search returned no results');record.checks[#record.checks+1]='Real catalog results and responsive builder grid'
    elseif case.page=='decks' then
        expect(#m.decks>=20,'Real deck library unavailable');local cover=m:deckCoverCard(m:findDeck('modern-boros-burn'));expect(cover and cover.name,'Deck cover missing')
        record.checks[#record.checks+1]='Real deck library and cover selection'
    end
    reports[#reports+1]=record;print('UX PASS '..case.name..': '..table.concat(record.checks,'; '))
end
function love.update(dt)
    timer=timer+dt;expect(timer<25,'UX stage timed out: '..stage)
    if stage=='popupPress' then
        local win=windows['inspect-card'];dragState={x=win.x,y=win.y,dx=120,dy=25};mouse.x=(win.x+70)*Layout.scale;mouse.y=(win.y+8)*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,0,0);mouseDown=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);stage='popupMove';timer=0
    elseif stage=='popupMove' then
        mouse.x=mouse.x+dragState.dx;mouse.y=mouse.y+dragState.dy;S.OnMouseMoved(mouse.x,mouse.y,dragState.dx,dragState.dy);stage='popupSettle';timer=0
    elseif stage=='popupSettle' then
        mouseDown=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);stage='popupVerify';timer=0
    elseif stage=='keepPress' then clickSlab(buttons.Keep,true);stage='keepRelease';timer=0
    elseif stage=='keepRelease' then clickSlab(buttons.Keep,false);stage='keepVerify';timer=0
    elseif stage=='colorOpen' then clickSlab(dragState.control,true);stage='colorOpenRelease';timer=0
    elseif stage=='colorOpenRelease' then clickSlab(dragState.control,false);stage='colorWait';timer=0
    elseif stage=='colorChoose' then clickSlab(buttons.Blue,true);stage='colorChooseRelease';timer=0
    elseif stage=='colorChooseRelease' then clickSlab(buttons.Blue,false);stage='colorVerify';timer=0
    elseif stage=='dropdownOpen' then local job=dragState.jobs[dragState.job];clickSlab(controls[job.id],true);stage='dropdownOpenRelease';timer=0
    elseif stage=='dropdownOpenRelease' then local job=dragState.jobs[dragState.job];clickSlab(controls[job.id],false);stage='dropdownChooseWait';timer=0
    elseif stage=='dropdownChoose' then local job=dragState.jobs[dragState.job];expect(selections[job.label],'Dropdown choice not rendered '..job.label);clickSlab(selections[job.label],true);stage='dropdownChooseRelease';timer=0
    elseif stage=='dropdownChooseRelease' then local job=dragState.jobs[dragState.job];clickSlab(selections[job.label],false);stage='dropdownVerify';timer=0 end
    m:update(dt);prefs:update();S.Update(dt);r:update(dt)
    if stage=='load' then
        if #m.decks>=20 and m.catalogHealth.ready and m.settingsLoaded then caseIndex=1;setMode(cases[caseIndex]);stage='case' end
    elseif stage=='case' then
        caseFrames=caseFrames+1
        if timer>cases[caseIndex].wait and draws>4 and (cases[caseIndex].page~='builder' or (#m.cards>0 and not m.searchBusy)) then
            inspect(cases[caseIndex]);writeImage(cases[caseIndex].name)
            if cases[caseIndex].variant=='settings' then
                dragState={job=1,jobs={{id='setting-resolution',label='1280x720',key='resolution',value='1280x720'},{id='setting-msaa',label='2',key='msaa',value=2},{id='setting-windowMode',label='Borderless',key='windowMode',value='Borderless'}}};stage='dropdownOpen'
            elseif cases[caseIndex].variant=='popup' then stage='popupPress'
            elseif cases[caseIndex].variant=='mulligan' then dragState={answers=#captured};stage='keepPress'
            elseif cases[caseIndex].page=='builder' then
                m:addCard({name='Arclight Phoenix'});stage='builderVerify'
            else stage='capture' end
            timer=0
        end
    elseif stage=='dropdownChooseWait' and timer>.04 then stage='dropdownChoose';timer=0
    elseif stage=='dropdownVerify' and timer>.04 then
        local job=dragState.jobs[dragState.job];expect(m.settings[job.key]==job.value,'Dropdown did not change '..job.key..': '..tostring(m.settings[job.key]));reports[#reports].checks[#reports[#reports].checks+1]='Actual dropdown changed '..job.key
        dragState.job=dragState.job+1
        if dragState.jobs[dragState.job] then stage='dropdownOpen' else writeImage(cases[caseIndex].name..'-controls');stage='nativeApply' end;timer=0
    elseif stage=='nativeApply' and timer>.08 then
        m.settings.resolution='1280x720';m.settings.windowMode='Windowed';m.settings.vsync=false;m.settings.msaa=0;m.settings.textureFilter='nearest';prefs:apply(true)
        local ww,hh,flags=love.window.getMode();local minFilter,magFilter=love.graphics.getDefaultFilter()
        expect(ww==1280 and hh==720 and not flags.fullscreen and flags.msaa==0,'Native window mode did not apply')
        expect(love.window.getVSync()==0 and minFilter=='nearest' and magFilter=='nearest','Native VSync/filter did not apply')
        reports[#reports].nativePreferences={w=ww,h=hh,fullscreen=flags.fullscreen,msaa=flags.msaa,vsync=love.window.getVSync(),filter=minFilter}
        reports[#reports].checks[#reports[#reports].checks+1]='Actual native window/VSync/MSAA/filter preferences applied';stage='capture';timer=0
    elseif stage=='popupVerify' and timer>.08 then
        local win=windows['inspect-card'];local expectedX=dragState.x+dragState.dx/Layout.scale;local expectedY=dragState.y+dragState.dy/Layout.scale
        expect(math.abs(win.x-expectedX)<1 and math.abs(win.y-expectedY)<1,'Popup drag does not match physical pointer delta at UI scale: got '..win.x..','..win.y..' expected '..expectedX..','..expectedY)
        reports[#reports].checks[#reports[#reports].checks+1]='Actual popup drag at UI1.25/render0.75 matches pointer delta';writeImage(cases[caseIndex].name..'-moved');stage='capture';timer=0
    elseif stage=='keepVerify' and timer>.08 then
        expect(#captured==dragState.answers+1 and captured[#captured].kind=='boolean' and captured[#captured].value==false,'Keep button did not dispatch synthetic Keep answer')
        reports[#reports].checks[#reports[#reports].checks+1]='Actual centered Keep button dispatch';stage='capture';timer=0
    elseif stage=='colorWait' and timer>.06 then
        expect(v.builderPopup and v.builderPopup.id=='builder-color' and buttons.Blue,'Mana-icon color popup did not open')
        writeImage(cases[caseIndex].name..'-color-popup');stage='colorChoose';timer=0
    elseif stage=='colorVerify' and timer>.06 then
        expect(m.searchColor=='U' and not v.builderPopup,'Mana-icon Blue choice did not preserve backend color value')
        reports[#reports].checks[#reports[#reports].checks+1]='Actual mana-icon color filter opens and selects Blue/U'
        m.searchColor='All';m:searchChanged();stage='colorRestore';timer=0
    elseif stage=='colorRestore' and timer>.4 and not m.searchBusy then writeImage(cases[caseIndex].name);stage='capture';timer=0
    elseif stage=='builderVerify' and timer>.08 and #(m.mutationQueue or {})==0 then
        local count=0;for _,entry in ipairs(m.editDeck.main)do if entry.name=='Arclight Phoenix'then count=entry.count end end
        expect(count==4 and m.lastBuilderError,'Fifth card copy was not blocked after actual catalog validation')
        reports[#reports].checks[#reports[#reports].checks+1]='Actual catalog rejected fifth copy before mutating deck'
        if os.getenv('LOVE2GATHERING_UX_ONLY')=='builder' then
            local control;for label,box in pairs(buttons)do if label:match('^Color:')then control=box;break end end;expect(control,'Color filter control missing');dragState={control=control};stage='colorOpen'
        else stage='capture' end;timer=0
    elseif stage=='capture' and timer>.1 then
        caseIndex=caseIndex+1
        if cases[caseIndex]then setMode(cases[caseIndex]);stage='case'
        else
            local f=assert(io.open('/tmp/love2gathering-ux-report.json','w'));f:write(json.encode({passed=true,scope='Real catalog data, synthetic game fixtures; UI rendering/actions only',cases=json.array(reports)}));f:close();print('UX COMPLETE '..#reports..' screenshot cases');love.event.quit(0)
        end
    end
    v:build()
end
function love.draw()
    r.navCalledThisDraw=false;prefs:beginFrame();r:draw();prefs:endScene();S.Draw();love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();r:drawToasts(Layout.dimensions());love.graphics.pop();draws=draws+1
end
function love.quit()if prefs then prefs:quit()end;if m then m:quit()end;S.OnQuit()end
