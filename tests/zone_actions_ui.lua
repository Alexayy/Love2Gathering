-- Real LÖVE/Slab input against viewer-filtered frames exported by the native
-- ZoneActionsFixture. The response adapter replays its accepted UUID sequence;
-- live rules, costs, selection and privacy are tested separately by that fixture.
function love.errorhandler(msg)io.stderr:write('ZONE ACTIONS UI FAILED: '..tostring(msg)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
package.preload['app.api']=function()return{escape=function(s)return tostring(s)end,new=function()return{escape=function(s)return tostring(s)end,request=function()end,update=function()end,quit=function()end}end}end
local json=require('lib.json');local S=require('lib.Slab');local Layout=require('app.layout');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Choices=require('app.card_choices');local Zone=require('app.zone_ui');local Actions=require('app.card_actions')
local m,r,v,runner,Cursor,Window;local mouse={x=2,y=2};local down=false;local clock,wake=0,0;local buttons,checks,answers,texts={},{},{},{};local pending,mode,capture;local frames={};local output=os.getenv('LOVE2GATHERING_ZONE_UI_OUTPUT')or'/tmp'
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('ZONE ACTIONS UI PASS '..label)end
local function wait(t)wake=clock+(t or .1);coroutine.yield()end
local function ready(fn,label)local deadline=clock+6;while not fn()do assert(clock<deadline,label);wait(.05)end end
local function copy(value)return json.decode(json.encode(value))end
local function adopt(name)
    -- Each scenario explicitly opens an isolated recording frame. Do not try
    -- to rewind a live game through Model's increasing-revision guard.
    m.actionBusy=false;m.answeredPrompt=nil;m.game=nil;m:setGame(copy(frames[name]));m.game.openingRoll=nil
    m.game.animationEvents={};v.cardChoiceState=nil;v.cardChoiceDrag=nil;v.zoneCardDrag=nil
    v.tableOptionsOpen=false;m.inspectCard=nil;m.zoneView=nil;m.cardActionSheet=nil
end
local function move(x,y)
    local px,py=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale
    S.OnMouseMoved(mouse.x,mouse.y,mouse.x-px,mouse.y-py);Choices.move(v,x,y);Zone.move(v,x,y);r:mousemoved(x,y)
end
local function click(box,button)
    assert(box,'Missing native-frame UI control');button=button or 1;local x,y=box.x+box.w/2,box.y+box.h/2
    move(x,y);wait(.06);down=true;S.OnMousePressed(mouse.x,mouse.y,button,false,1)
    local consumed=Zone.press(v,x,y,button)or Choices.press(v,x,y,button)
    if not consumed and S.IsVoidHovered()then r:mousepressed(x,y,button,1)end
    wait(.06);down=false;S.OnMouseReleased(mouse.x,mouse.y,button,false,1)
    if not Zone.release(v,x,y,button)and not Choices.release(v,x,y,button)then r:mousereleased(x,y,button)end
    wait(.16)
end
local function drag(hit,replacePrompt)
    assert(hit and hit.available,'Expected current native highlighted zone card')
    local x,y=hit.x+hit.w/2,hit.y+hit.h/2;move(x,y);wait(.06);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1)
    check(Zone.press(v,x,y,1),'Highlighted native zone card owns drag input')
    wait(.06);move(70,760);wait(.1)
    if replacePrompt then m.game.prompt.id=m.game.prompt.id+1 end
    down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);Zone.release(v,70,760,1);wait(.16)
end
local function hitFor(hits,key)for _,hit in ipairs(hits or{})do if hit.card.id==key then return hit end end end
local function localPlayer()for _,player in ipairs(m.game.players)do if player.isLocal then return player end end end
local function shot(name)capture=name;wait(.14)end
local function scenario()
    adopt('memory-deluge-before-selection');mode='memory';wait(.3)
    local original=frames['memory-deluge-before-selection'];local panel=original.prompt.cardPanel
    local first,second=panel.cards[1].id,panel.cards[2].id
    local key=Choices.modalKey(v,m:prompt());local state=v.cardChoiceState
    check(state.multiple and state.minimum==2 and state.maximum==2,'Actual native Memory Deluge opens a bounded select-two panel')
    click(hitFor(v.cardChoiceHits,first));check(#answers==0 and state.selection[first]and Choices.selectedCount(state)==1,'First Memory Deluge selection is visibly staged without an engine answer')
    check(texts.SELECTED and texts['Selected 1 / 2 · Click again to deselect; Confirm applies the whole selection.'],'Selected card queues a visible SELECTED marker and count')
    shot('memory-one-staged');click(hitFor(v.cardChoiceHits,first));check(not state.selection[first]and#answers==0,'Clicking the same card reverses selection before any native commitment')
    click(hitFor(v.cardChoiceHits,first))
    if not hitFor(v.cardChoiceHits,second)then click(buttons['Next visible cards'])end
    click(hitFor(v.cardChoiceHits,second))
    check(v.cardChoiceState==state and Choices.selectedCount(state)==2 and #answers==0 and Choices.modalKey(v,m:prompt())==key,'Two staged choices retain one open panel and submit nothing before Confirm')
    shot('memory-two-staged');click(buttons['Confirm selection'])
    ready(function()return not pending and#m.game.players[1].hand==2 end,'Native-frame selection sequence failed to finish')
    check(#answers==2 and answers[1].value==first and answers[2].value==second,'Confirm emits exactly the two native UUIDs across consecutive accepted prompt IDs')
    check(m.acceptedPanelStable==true and m.applyingPanelVisible==true,'Selected markers and modal identity remain stable while native responses apply')
    shot('memory-confirmed')
    adopt('flashback-offer');mode='zone';wait(.25);local own=localPlayer();local flash=own.graveyard[1];check(m:openZone(own.id,'graveyard'),'Current graveyard opens through player and zone identity');wait(.3)
    local hit=hitFor(v.zoneCardHits,flash.id);check(hit and hit.available and r.zoneCardRects[flash.id]==hit,'Actual offered Flashback has a PLAY marker and its visible popup anchor')
    shot('flashback-zone');local before=#answers;drag(hit)
    check(#answers==before+1 and answers[#answers].value==flash.id and not m.zoneView,'Graveyard drag dispatches the actual card UUID and closes only after accepted submission')
    adopt('flashback-offer');wait(.2);own=localPlayer();m:openZone(own.id,'graveyard');wait(.3);before=#answers;drag(hitFor(v.zoneCardHits,flash.id),true)
    check(#answers==before and m.zoneView,'A changed native prompt cancels an in-flight graveyard drag')
    adopt('exile-extension-offered');mode='zone';wait(.25);own=localPlayer()
    local extension=Actions.extension(m);check(#extension==3 and extension[1].zone=='EXILED','Actual temporary permission creates an explicitly exiled hand extension for its three legal objects')
    m:openZone(own.id,'exile');wait(.3);local exiled=extension[1];before=#answers;shot('exile-zone');drag(hitFor(v.zoneCardHits,exiled.id))
    check(#answers==before+1 and answers[#answers].value==exiled.id,'Exile popup drag forwards the actual native offer without moving any card locally')
    adopt('exile-permission-expired');wait(.2);check(#Actions.extension(m)==0,'Native cleanup removes expired exile permissions from the hand extension')
    adopt('foretell-offered-owner');wait(.2);extension=Actions.extension(m)
    check(#extension==1 and extension[1].name=='Doomskar'and extension[1].faceDownContext and extension[1].inspectionOnly,'Owner-known native Foretell identity appears as a private exile extension')
    own=localPlayer();m:openZone(own.id,'exile');wait(.3);check(hitFor(v.zoneCardHits,extension[1].id).available,'Owner can select the actual offered face-down exile object without a guessed permission');shot('foretell-private-zone')
    adopt('foretell-hidden-opponent');wait(.2);check(#Actions.extension(m)==0,'Another human never gets the private Foretell identity or an exile play control')
    adopt('flashback-offer');wait(.2);own=localPlayer();m:openZone(own.id,'graveyard');m.roomDisconnected=true;wait(.3);before=#answers
    check(not hitFor(v.zoneCardHits,own.graveyard[1].id).available and not Zone.press(v,500,400,1),'Disconnected room preserves visible zone cards while disabling their actions')
    check(#answers==before,'Disconnected visible offers submit no stale engine response')
    m.roomDisconnected=false;m.replay={frames={},index=1,speed=1,playing=false};wait(.2);check(#Actions.extension(m)==0,'Read-only replay never exposes live exile actions')
    local f=assert(io.open(output..'/report.json','w'));f:write(json.encode({passed=true,checks=checks,answers=answers,scope='Actual LÖVE/Slab input and drawing from fresh real-XMage viewer-filtered fixture frames. The accepted response sequence is replayed locally; native fixture separately proves actual cast/cost/private selection/permission/expiry. No live GUI-to-running-engine or WAN claim.',userStoreModified=false}));f:close();print('ZONE ACTIONS UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Window=require('lib.Slab.Internal.UI.Window')
    for _,name in ipairs({'memory-deluge-before-selection','memory-deluge-one-selected','memory-deluge-complete','flashback-offer','exile-extension-offered','exile-permission-expired','foretell-offered-owner','foretell-hidden-opponent'})do frames[name]=json.decode(assert(love.filesystem.read('native/'..name..'.json')))end
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down or false end
    m=Model.new();m.page='table';m.settings.showCardArt=false;m.settings.sfxEnabled=false;m.settings.particles=false;m.settings.animations=false;m.catalogHealth.ready=false;m.uiLayout={};m.engineHealth.ok=true
    function m:answer(kind,value)
        if self.roomDisconnected or self.actionBusy or self.replay then return false end;local p=self:prompt();if not p then return false end
        answers[#answers+1]={promptId=p.id,type=kind,value=value};self.actionBusy=true;self.answeredPrompt=p.id
        if mode=='memory'then
            local index=#answers;local state=v.cardChoiceState;local key=Choices.modalKey(v,p)
            pending={at=clock+.24,callback=function()
                self.actionBusy=false;self.answeredPrompt=nil
                local nextFrame=copy(frames[index==1 and'memory-deluge-one-selected'or'memory-deluge-complete']);nextFrame.openingRoll=nil;nextFrame.animationEvents={};self:setGame(nextFrame)
                if index==1 then self.acceptedPanelStable=v.cardChoiceState==state and Choices.modalKey(v,self:prompt())==key and state.selection[value]end
            end}
        else self.game.prompt=nil;self.actionBusy=false;self.answeredPrompt=nil end
        return true
    end
    r=Renderer.new(m);v=View.new(S,m,r)
    for _,name in ipairs({'Button','CheckBox'})do local original=S[name];S[name]=function(a,b,c)
        local result=original(a,b,c);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);buttons[name=='CheckBox'and b or a]={x=x,y=y,w=w,h=h};return result
    end end
    local originalText=S.Text;S.Text=function(label,options)texts[label]=true;return originalText(label,options)end
    local draw=require('lib.Slab.Internal.Core.DrawCommands');local originalPrint=draw.Print;draw.Print=function(label,...)texts[label]=true;return originalPrint(label,...)end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    clock=clock+dt;assert(clock<60,'Native zone/choice UI acceptance timed out')
    if pending and clock>=pending.at then local next=pending;pending=nil;next.callback()end
    S.Update(dt);r:update(dt)
    if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
    buttons={};texts={};v:build()
    if pending and mode=='memory'and v.cardChoiceState and Choices.currentModal(v,m:prompt())=='native-card-choices'and#v.cardChoiceHits>0 then m.applyingPanelVisible=true end
end
function love.draw()
    love.graphics.clear(.026,.036,.06,1);love.graphics.push();love.graphics.scale(Layout.scale);r:draw();love.graphics.pop()
    S.Draw({DeferOverlays=true});love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();Choices.draw(v);Zone.ghost(v);love.graphics.pop();S.DrawOverlays()
    if capture then local name=capture;capture=nil;love.graphics.captureScreenshot(function(data)local f=assert(io.open(output..'/'..name..'.png','wb'));f:write(data:encode('png'):getString());f:close()end)end
end
function love.quit()S.OnQuit()end
