local Slab=require('lib.Slab')
local Model=require('app.model')
local Renderer=require('app.renderer')
local View=require('app.view')
local Layout=require('app.layout')
local Preferences=require('app.preferences')
local Storage=require('app.storage')
local Startup=require('app.startup')
local model,renderer,view,preferences,startup
local smoke,smokeMatch,smokeTime,smokeStage=false,false,0,0
local startupCaptured=false
function love.load(args)
    love.graphics.setDefaultFilter('linear','linear')
    Slab.SetINIStatePath(nil)
    local slabArgs={}
    for _,arg in ipairs(args or {}) do
        if arg=='--smoke-test' then smoke=true elseif arg=='--smoke-match' then smoke=true;smokeMatch=true else slabArgs[#slabArgs+1]=arg end
    end
    if not pcall(love.mouse.getSystemCursor,'arrow') then slabArgs[#slabArgs+1]='nocursor' end
    Slab.Initialize(slabArgs,true)
    model=Model.new();renderer=Renderer.new(model);view=View.new(Slab,model,renderer)
    preferences=Preferences.new(model,Slab,renderer);view.preferences=preferences;preferences:apply()
    love.window.setTitle('Love: 2 Gathering')
    love.window.setIcon(love.image.newImageData(renderer.assets:icon()))
    if smoke then model.settings.showCardArt=false end
    startup=Startup.new(model,renderer,preferences)
end
function love.update(dt)
    if startup and not startup.ready then startup:update(dt);if not startup.ready then return end end
    model:update(dt);preferences:update();Slab.Update(dt);renderer:update(dt);view:build()
    renderer.uiHovered=not Slab.IsVoidHovered()
    renderer:mousemoved(Layout.mouse())
    if smoke then
        smokeTime=smokeTime+dt
        if smokeStage==0 and #model.decks>=20 and model.catalogHealth.ready then
            smokeStage=1;smokeTime=0;print('SMOKE: catalog ready; '..#model.decks..' decks')
        elseif smokeStage==1 and smokeTime>1 then
            love.graphics.captureScreenshot('smoke-decks.png');smokeStage=11;smokeTime=0
        elseif smokeStage==11 and smokeTime>.2 then
            model:openDeck(model:findDeck('modern-boros-burn') or model.decks[1]);smokeStage=2;smokeTime=0
        elseif smokeStage==2 and smokeTime>2 and #model.cards>0 then
            love.graphics.captureScreenshot('smoke-builder.png');smokeStage=21;smokeTime=0
        elseif smokeStage==21 and smokeTime>.2 then
            model.page='lobby';smokeStage=3;smokeTime=0
        elseif smokeStage==3 and smokeTime>1 then
            love.graphics.captureScreenshot('smoke-lobby.png');smokeStage=31;smokeTime=0
        elseif smokeStage==31 and smokeTime>.2 then
            print('SMOKE: decks, search/builder, lobby rendered')
            if smokeMatch then model.playerDeckId='modern-boros-burn';model.botDeckId='modern-merfolk';model:startGame();smokeStage=4;smokeTime=0
            else love.event.quit(0) end
        elseif smokeStage==4 and model:prompt() and smokeTime>1 then
            local p=model:prompt();local human
            for _,player in ipairs(model.game.players or {}) do if player.human then human=player end end
            if human and #(human.hand or {})>0 and model.game.phase and model.game.phase~='' then
                love.graphics.captureScreenshot('smoke-table.png');print('SMOKE: real XMage opening hand and prompt rendered');smokeStage=41;smokeTime=0
            elseif p.type=='ask' then
                local choice=(p.message or ''):lower():find('mulligan',1,true) and p.choices[2] or p.choices[1]
                if choice then model:answerChoice(choice) end
            elseif p.choices and p.choices[1] then model:answerChoice(p.choices[1]) end
        elseif smokeStage==41 and smokeTime>.3 then love.event.quit(0)
        elseif smokeTime>35 then print('SMOKE FAILED: services or card results unavailable');love.event.quit(2) end
    end
end
function love.draw()
    if startup and not startup.ready then startup:draw();preferences:endFrame();if smoke and not startupCaptured then love.graphics.captureScreenshot('smoke-startup.png');startupCaptured=true end;love.timer.sleep(.012);return end
    local started=love.timer.getTime()
    preferences:beginFrame();renderer:draw();preferences:endScene();Slab.Draw({DeferOverlays=true})
    love.graphics.push();love.graphics.scale(Layout.scale)
    renderer:drawForeground();local choices=package.loaded['app.card_choices'];if choices then choices.draw(view)end
    renderer:drawToasts(Layout.dimensions());love.graphics.pop()
    Slab.DrawOverlays()
    preferences:endFrame()
    love.graphics.setColor(1,1,1,1)
    preferences:limitFrame(started)
end
function love.mousepressed(x,y,button,touch,clicks)
    if startup and not startup.ready then startup:press(x,y,button);return end
    Slab.OnMousePressed(x,y,button,touch,clicks)
    local lx,ly=Layout.toLogical(x,y)
    local choices=package.loaded['app.card_choices']
    if choices and not renderer:inputBlocked()and choices.press(view,lx,ly,button)then return end
    if not renderer:inputBlocked()and Storage.press(renderer,lx,ly,button)then return end
    if not renderer:inputBlocked()and Slab.IsVoidHovered() then
        renderer:mousepressed(lx,ly,button,clicks)
    end
end
function love.mousereleased(x,y,button,touch,clicks)
    if startup and not startup.ready then return end
    Slab.OnMouseReleased(x,y,button,touch,clicks);local lx,ly=Layout.toLogical(x,y)
    local choices=package.loaded['app.card_choices'];if choices and choices.release(view,lx,ly,button)then return end
    renderer:mousereleased(lx,ly,button)
end
function love.mousemoved(x,y,dx,dy,touch)
    if startup and not startup.ready then return end
    Slab.OnMouseMoved(x,y,dx,dy,touch);local lx,ly=Layout.toLogical(x,y)
    local choices=package.loaded['app.card_choices'];if choices then choices.move(view,lx,ly)end
    renderer:mousemoved(lx,ly)
end
function love.wheelmoved(...)
    if startup and not startup.ready then return end
    local empty=Slab.IsVoidHovered();Slab.OnWheelMoved(...)
    renderer.uiHovered=not empty
    if empty then renderer:wheelmoved(...)end
end
function love.textinput(...) if startup and not startup.ready then return end;Slab.OnTextInput(...) end
function love.keypressed(key,scancode,isrepeat)
    if startup and not startup.ready then if key=='escape'then love.event.quit()end;return end
    Slab.OnKeyPressed(key,scancode,isrepeat)
    if key=='escape'then
        if view.setPicker then require('app.set_picker').close(view);return end
        if model.imagePackFileDialog then model.imagePackCancelRequested=true;return end
        if model.cardPrintingPicker then model:closeCardPrintings();return end
        if model.tokenPicker then model:closeTokenPicker();return end
        if view.brandMenu then view.brandMenu=nil;return end
        model:closeSettings();model.zoneView=nil;model.deleteConfirm=nil;model.inspectCard=nil;model.galleryInspect=nil;model.confirmConcede=false;model.archiveCopy=nil;model.storagePurgePreview=nil;model.storageLocationConfirm=nil;model.storageFolderDialog=nil;model.imagePackFileDialog=nil
        view.builderPopup=nil;view.builderFiltersOpen=nil;view.themeColorEdit=nil;view.combatStopsOpen=false;require('app.deck_picker').close(view)
        return
    end
    if not Slab.IsAnyInputFocused()and not renderer:inputBlocked()then
        if key=='space' and model.page=='table' then
            if model.replay then model:toggleReplay()
            else
                local p=model:prompt()
                if p then for _,c in ipairs(p.choices or {}) do if tostring(c.label):lower():find('pass',1,true) then model:answerChoice(c);break end end end
            end
        elseif model.replay and key=='left' then model:stepReplay(-1)
        elseif model.replay and key=='right' then model:stepReplay(1)
        end
    end
end
function love.keyreleased(...) if startup and not startup.ready then return end;Slab.OnKeyReleased(...) end
function love.filedropped(file)if startup and not startup.ready then return end;if model.dropImagePack and model:dropImagePack(file)then return end;if model.importDeckFile then model:importDeckFile(file)end end
function love.resize() if preferences then preferences:update() end end
function love.quit() if preferences then preferences:quit() end;if model then model:quit() end;Slab.OnQuit() end
