-- Real main.lua callbacks, graphics and Slab windows; synthetic game snapshots.
local json=require('lib.json')
local actions={}
package.preload['app.api']=function()
    return {escape=tostring,new=function()
        return {request=function(_,service,method,path,body)
            if service=='engine' and method=='POST' then
                actions[#actions+1]={path=path,body=json.decode(json.encode(body))}
            end
            return true
        end,update=function()end,quit=function()end,setNativeSession=function()end}
    end}
end
package.preload['app.startup']=function()return {new=function()return {ready=true}end}end
local Slab=require('lib.Slab')
local Layout=require('app.layout')
local Cursor=require('lib.Slab.Internal.Core.Cursor')
local Window=require('lib.Slab.Internal.UI.Window')
local output=assert(os.getenv('L2G_PREVIEW_TEST'))
local prints=json.decode(love.filesystem.read('prints.json'))
local model,renderer,preferences
local Model=require('app.model')
local Renderer=require('app.renderer')
local Preferences=require('app.preferences')
local originalModel,originalRenderer,originalPreferences=Model.new,Renderer.new,Preferences.new
function Model.new(...)
    model=originalModel(...)
    local settings=model.settings
    settings.animations=false;settings.reducedMotion=true;settings.particles=false
    settings.windowMode='Windowed';settings.resolution='1120x720';settings.skybox='Off'
    settings.sfxEnabled=false;settings.musicEnabled=false;settings.vsync=false
    model.settingsLoaded=true;model.loaded=true;model.profileLoaded=true;model.uiLayout={}
    return model
end
function Renderer.new(...)renderer=originalRenderer(...);return renderer end
function Preferences.new(...)preferences=originalPreferences(...);return preferences end
assert(love.filesystem.load('application-main.lua'))()
local app={load=love.load,update=love.update,draw=love.draw}
for _,name in ipairs({'mousemoved','mousepressed','mousereleased','keypressed','keyreleased'})do
    app[name]=love[name];love[name]=function()end
end
local runner,closeBox,detailScan,confirmBox,optionsBox,stackDetails
local passiveRules={}
local pendingWheel
local images={}
local mouse,down={x=1,y=1},{}
local checks,displays,shots,artReads={}, {}, {}, {}
local clock,wake=0,0
local function wait(t)wake=clock+(t or .08);coroutine.yield()end
local function check(value,label)
    assert(value,label);checks[#checks+1]=label;print('PREVIEW PASS '..label);io.stdout:flush()
end
local function move(x,y)
    local px,py=mouse.x,mouse.y
    mouse.x,mouse.y=x*Layout.scale,y*Layout.scale
    app.mousemoved(mouse.x,mouse.y,mouse.x-px,mouse.y-py,false)
end
local function press(button)down[button]=true;app.mousepressed(mouse.x,mouse.y,button,false,1);wait(.07)end
local function release(button)down[button]=nil;app.mousereleased(mouse.x,mouse.y,button,false,1);wait(.08)end
local function click(button)press(button);release(button)end
local function hover(id)
    for _,hit in ipairs(renderer.hits)do if hit.card and hit.card.id==id then
        move(hit.x+hit.w/2,hit.y+hit.h*.35);wait(.12)
        return hit
    end end
    error('Missing table card '..id)
end
local function shot(name)
    love.graphics.captureScreenshot(function(image)
        local file=assert(io.open(output..'/'..name..'.png','wb'))
        local bytes=image:encode('png');file:write(bytes:getString());file:close();bytes:release();image:release()
    end)
    shots[#shots+1]=name..'.png';wait(.12)
end
local function card(id,name,kind,owner,rules,cost)
    return {id=id,name=name,type=kind,rules=rules,manaCost=cost,selectedPrintingId=prints[name],
        ownerId=owner,controllerId=owner,currentRules=rules}
end
local function scene(count,gameId)
    local players={}
    for i=1,count do
        local id='p'..i
        local creature=card('creature-'..id,i==1 and 'Llanowar Elves' or 'Goblin Guide','[Creature]',id,
            i==1 and '{T}: Add {G}.' or 'Haste',i==1 and '{G}' or '{R}')
        creature.power=i==1 and '1' or '2';creature.toughness=creature.power
        players[i]={id=id,name=i==1 and 'Local player' or 'Opponent '..(i-1),human=i==1,isLocal=i==1,
            seat=i-1,life=20,hand={},handCount=i==1 and 1 or 4,libraryCount=50,battlefield={creature},
            graveyard={},exile={},command={},mana={}}
    end
    players[1].hand={card('hand-bolt','Lightning Bolt','[Instant]','p1','Lightning Bolt deals 3 damage to any target.','{R}')}
    return {gameId=gameId,revision=1,running=true,turn=3,activePlayerId='p1',priorityPlayerId='p1',
        players=players,step='PRECOMBAT_MAIN',phase='Precombat Main',stack={},log={},
        prompt={id=37,type='select',priority=true,actionable={'hand-bolt','creature-p2','p2'},
            choices={{id='done',responseType='boolean',value=true}}},
        priority={canEndTurn=true,pending=false,autoPass=false,stops={own={},opponent={}}}}
end
local function adopt(frame)
    model.replay=nil;model.page='table';model:setGame(frame)
    model.stackOpen=false;model.logOpen=false;move(1,1);wait(.18)
end
local function closeDetails()
    assert(closeBox,'Missing Slab Close details control')
    move(closeBox.x+closeBox.w/2,closeBox.y+closeBox.h/2);wait(.05);click(1)
end
local function pinned(id)
    local preview=renderer.tablePreviewRect
    return preview and preview.pinned and preview.card.id==id
end
local function inspectStackDuringChoice(mode)
    local frame=scene(2,'stack-choice-'..mode)
    local chapter='Exile up to two target cards from graveyards. For each creature card exiled this way, you gain 1 life.'
    local firstChapter='Each player mills three cards.'
    local sourceRules='I — '..firstChapter..'\nII — '..chapter..'\nIII — Return target creature or land card from your graveyard to your hand.'
    local source=card('saga','The Binding of the Titans','Enchantment — Saga','p1',sourceRules,'{1}{G}')
    source.zone='BATTLEFIELD';frame.players[1].battlefield[#frame.players[1].battlefield+1]=source
    local first=card('grave-one','Goblin Guide','Creature','p1','Haste','{R}')
    local second=card('grave-two','Lightning Bolt','Instant','p1','Lightning Bolt deals 3 damage to any target.','{R}')
    frame.players[1].graveyard={first,second}
    frame.stack={{id='chapter-two',kind='ability',controllerId='p1',sourceId=source.id,sourceName=source.name,sourceCard=source,rules=chapter},
        {id='chapter-one',kind='ability',controllerId='p1',sourceId=source.id,sourceName=source.name,sourceCard=source,rules=firstChapter}}
    local guide=frame.players[2].battlefield[1]
    local attackRule='Whenever Goblin Guide attacks, defending player reveals the top card of their library. If it is a land card, that player puts it into their hand.'
    frame.stack[3]={id='guide-trigger',kind='ability',controllerId='p2',sourceId=guide.id,sourceName=guide.name,sourceCard=guide,rules=attackRule}
    frame.prompt={id=48,type='pick_target',message='Choose up to two target cards from graveyards',actionable={first.id,second.id},
        choices={{id=first.id,responseType='uuid',card=first},{id=second.id,responseType='uuid',card=second}},
        cardPanel={interactionId='chapter-targets',kind='select',stage='select',selectionMode='multiple',
            min=0,max=2,zone='GRAVEYARD',cards={first,second}}}
    adopt(frame);model.stackOpen=true;wait(.2)
    local v=renderer.view;local before=#actions
    local tile=assert(v.cardChoiceHits[1]);move(tile.x+tile.w/2,tile.y+tile.h/2);wait(.08);click(1)
    local state=v.cardChoiceState
    check(state.selection[first.id] and #actions==before,'A graveyard target is staged before inspecting the stack at '..mode)
    local row=assert(model.stackHits[1]);move(row.x+row.w*.55,row.y+34);wait(.12)
    local preview=renderer.tablePreviewRect;local form=v.inputLockBounds
    check(model.stackHover and model.stackHover.id=='chapter-two' and preview and preview.card.id==source.id and passiveRules[chapter],
        'Exposed stack row shows the source and this chapter’s exact rule in the left preview')
    check(form and preview.x+preview.w<=form.x and form.x+form.w<=row.x and preview.y+preview.h<=select(2,Layout.dimensions()),
        'Choice, passive preview and stack rail remain simultaneously visible at '..mode)
    shot('stack-choose-cards-'..mode)
    click(1);check(not model:pinnedTableCard() and not model.inspectCard and #actions==before,'Left-click outside the choice keeps the decision staged')
    click(2);check(model.tablePin and model.tablePin.stackId=='chapter-two','Right-click pins the specific ability on the stack')
    click(3);check(model.inspectCard and model.inspectCard.id==source.id and stackDetails==chapter,'Middle-click shows the full source and selected native stack rule')
    closeDetails();check(v.inputLock=='native-card-choices' and model:prompt()==frame.prompt and v.cardChoiceState==state and state.selection[first.id] and #actions==before,
        'Closing details returns to the very same staged targets and unanswered prompt')
    row=assert(model.stackHits[2]);move(row.x+row.w*.55,row.y+22);wait(.12)
    check(renderer.tablePreviewRect and renderer.tablePreviewRect.context.stackId=='chapter-one' and passiveRules[firstChapter]
        and not renderer.tablePreviewRect.pinned,'Two abilities from one permanent retain distinct rules and pin status')
    pendingWheel=-18;wait(.16)
    row=assert(model.stackHits[3]);local top,bottom=math.max(row.y,row.clip.y),math.min(row.y+row.h,row.clip.y+row.clip.h)
    check(bottom>top,'The stack rail scrolls to lower objects while the card choice owns native input')
    move(row.x+row.w*.55,(top+bottom)/2);wait(.12)
    check(renderer.tablePreviewRect and renderer.tablePreviewRect.card.id==guide.id and passiveRules[attackRule],
        'A scrolled stack ability shows its correct rule with the entitled source printing')
    shot('stack-source-scan-'..mode)
    move(optionsBox.x+optionsBox.w/2,optionsBox.y+optionsBox.h/2);wait(.08);click(1)
    check(v.inputLock=='native-card-choices' and not v.tableOptionsOpen and #actions==before,'The actual Table options button stays blocked while the choice permits stack inspection')
    assert(confirmBox);move(confirmBox.x+confirmBox.w/2,confirmBox.y+confirmBox.h/2);wait(.08);click(1)
    local sent=actions[#actions]
    check(#actions==before+1 and sent.body.promptId==frame.prompt.id and sent.body.value==first.id,
        'Confirm still dispatches the selected graveyard object and original native prompt exactly once')
end
local function scenario()
    for _,mode in ipairs({{1120,720,1,1,'minimum'},{1920,1080,1.25,.75,'scaled'}})do
        local s=model.settings
        s.resolution=mode[1]..'x'..mode[2];s.uiScale=mode[3];s.renderScale=mode[4];preferences:apply(true)
        local w,h=Layout.dimensions()
        displays[#displays+1]={physical={love.graphics.getDimensions()},logical={w,h},ui=Layout.scale,render=s.renderScale}
        local frame=scene(2,'preview-duel-'..mode[5]);adopt(frame)
        local before=#actions
        local permanent=hover('creature-p2')
        local preview=renderer.tablePreviewRect
        check(preview and preview.card.id==permanent.card.id and not preview.pinned,'Hover previews the exact battlefield object at '..mode[5])
        check(preview.x>=0 and preview.x+preview.w<w*.5 and preview.y>=0 and preview.y+preview.h<=h,
            'Readable preview fits on the left at '..mode[5])
        check(not model.inspectCard and not renderer:inputBlocked() and #actions==before,'Board hover leaves native input available')
        shot('hover-'..mode[5])
        move(w*.55,145);wait(.1)
        check(not renderer.tablePreviewRect and not model.inspectCard,'Leaving the hovered card restores the board')
        hover('creature-p2');click(2);move(w*.55,145);wait(.12)
        check(pinned('creature-p2') and not renderer:inputBlocked() and not model.inspectCard,'Right-click keeps the preview without locking the board')
        preview=renderer.tablePreviewRect
        move(preview.x+preview.w/2,preview.y+preview.cardH/2);wait(.1);click(3)
        check(model.inspectCard and model.inspectCard.id=='creature-p2','Middle-click on the pinned scan opens its own card')
        closeDetails()
        local player=renderer.playerRects.p2
        move(player.x+12,player.y+player.h*.6);wait(.05);click(1)
        local target=actions[#actions]
        check(#actions==before+1 and target.body.value=='p2' and target.body.promptId==frame.prompt.id,
            'Clicking a player on the preview side of the table sends the offered player ID')
        frame=json.decode(json.encode(frame));frame.revision=frame.revision+1;frame.prompt.id=frame.prompt.id+1
        model.actionBusy=false;model:setGame(frame);before=#actions;wait(.08)
        local hand=hover('hand-bolt')
        check(renderer.tablePreviewRect and renderer.tablePreviewRect.card.id=='hand-bolt','Moving onto the hand shows that exact card')
        click(3)
        check(model.inspectCard and model.inspectCard.id==hand.card.id and renderer:inputBlocked() and closeBox,'Middle-click opens interactive details')
        check(detailScan and detailScan.Image==images[prints['Lightning Bolt']].normal
            and detailScan.W>=320 and detailScan.H>=440,'Inspector draws the full selected printing at a readable size')
        shot('details-'..mode[5]);closeDetails()
        check(not model.inspectCard and model:prompt()==frame.prompt and #actions==before,'Closing details restores the unanswered native prompt')
        move(w*.55,145);wait(.08)
        check(pinned('creature-p2'),'Inspecting a different card keeps the original comparison pin')
        hover('hand-bolt');press(1)
        check(renderer.drag and renderer.drag.card.id=='hand-bolt','Left drag still starts on the offered hand card')
        move(w*.57,h*.42);wait(.05);release(1)
        local last=actions[#actions]
        check(#actions==before+1 and last.path=='/session/action' and last.body.type=='uuid' and last.body.value=='hand-bolt'
            and last.body.expectedGameId==frame.gameId and last.body.promptId==frame.prompt.id,'Dropping the card sends its exact offered UUID once')

        frame=scene(4,'preview-multiplayer-'..mode[5]);adopt(frame);before=#actions
        hover('creature-p2');click(2);move(w*.55,145);wait(.1)
        check(pinned('creature-p2'),'Stationary multiplayer right-click pins the preview')
        local camera=renderer.tableCamera;camera:focus(1,true);wait(.1)
        local view=renderer.multiplayerView
        move(view.x+view.w*.62,view.y+view.h*.40);wait(.06);press(2)
        local x,y=camera.x,camera.y;move(view.x+view.w*.62-90,view.y+view.h*.40-45);wait(.06);release(2)
        check(camera.mode=='free' and (math.abs(camera.x-x)>1 or math.abs(camera.y-y)>1) and not model.inspectCard and #actions==before,
            'Right drag pans the multiplayer table without opening details or selecting a card')
        inspectStackDuringChoice(mode[5])
    end
    local original=scene(2,'preview-replay')
    local frame=json.decode(json.encode(original))
    local facedown={id='face-down-p2',hidden=true,faceDown=true,power='2',toughness='2',damage=1,controllerId='p2',ownerId='p2',counters={charge=1}}
    original.players[2].battlefield[1].id=facedown.id
    frame.players[2].battlefield={facedown}
    adopt(original);model.replay={id='recorded-perspective',frames={{data=original,timestamp=0},{data=frame,timestamp=1000}},index=1,speed=1,playing=false}
    model:seekReplay(1);wait(.12)
    local before=#actions
    hover(facedown.id);click(2);click(3)
    check(model.inspectCard and model.inspectCard.name=='Goblin Guide','Replay exposes the identity visible on its first frame')
    artReads={};model:seekReplay(2);wait(.12)
    check(not model.inspectCard and not model:pinnedTableCard(),'Seeking into a redacted frame removes the previously known face from details and preview')
    hover(facedown.id);click(3)
    check(model.inspectCard and model.inspectCard.hidden and model.inspectCard.faceDown and model.inspectCard.name=='Face-down card'
        and model.inspectCard.toughness=='2' and model.inspectCard.counters.charge==1,'Anonymous details show the neutral card back and recorded public stats')
    check(not artReads[facedown.id] and not artReads['Face-down card'],'Hidden details and preview never request identity artwork')
    shot('face-down-replay');closeDetails()
    hover('hand-bolt');click(3);check(model.inspectCard.id=='hand-bolt','Replay can inspect its entitled hand card')
    closeDetails()
    check(#actions==before and not model:prompt(),'Preview and details during playback send no live actions')
    hover('hand-bolt');click(2);click(3)
    model:showRooms();wait(.12)
    check(model.page=='rooms' and not model.inspectCard and not model:pinnedTableCard(),'Leaving the table retires its pin and full inspector before drawing the room')
    local path=output..'/report.json';local f=assert(io.open(path,'w'))
    f:write(json.encode({scope='Actual LÖVE main callbacks, Slab windows and local printing images. Controlled native-shaped projections and action transport.',
        checks=checks,displays=displays,screenshots=shots,engineRequests=actions}));f:close()
    print('TABLE PREVIEW COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
    app.load({})
    for name,slug in pairs({['Goblin Guide']='guide',['Lightning Bolt']='bolt',['Llanowar Elves']='elves'})do
        local id=prints[name]
        images[id]={normal=love.graphics.newImage(slug..'-normal.jpg'),art_crop=love.graphics.newImage(slug..'-art_crop.jpg')}
        local printed={id=id,printing_id=id,name=name,image_uris={}}
        model.printingMetadata=model.printingMetadata or {};model.printingMetadata[id]={card=printed}
        model:rememberCard(printed)
    end
    function model:getArt(card,_,kind)
        if not card then return end
        artReads[card.id or card.name or 'anonymous']=true
        local id=card.selectedPrintingId or card.printing_id
        return images[id] and images[id][kind or 'normal']
    end
    local button=Slab.Button
    Slab.Button=function(label,options)
        local result=button(label,options)
        if label=='Close details' or label=='Confirm selection' or label=='Table options' then
            local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y)
            local box={x=x,y=y,w=w,h=h}
            if label=='Close details' then closeBox=box elseif label=='Confirm selection' then confirmBox=box else optionsBox=box end
        end
        return result
    end
    local rich=require('app.richtext');local richDraw,richSlab=rich.draw,rich.slab
    rich.draw=function(r,text,x,y,w,opts)
        if opts and opts.layout and x>0 and x<200 then passiveRules[text]=true end
        return richDraw(r,text,x,y,w,opts)
    end
    rich.slab=function(v,id,text,...)
        if id=='inspected-stack-rule' then stackDetails=text end
        return richSlab(v,id,text,...)
    end
    local image=Slab.Image
    Slab.Image=function(id,options)
        if id=='inspected-art' then detailScan=options end
        return image(id,options)
    end
    love.mouse.getPosition=function()return mouse.x,mouse.y end
    love.mouse.isDown=function(button)return down[button]==true end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    clock=clock+dt;assert(clock<50,'Table preview fixture timed out')
    if pendingWheel then love.wheelmoved(0,pendingWheel);pendingWheel=nil end
    closeBox=nil;detailScan=nil;confirmBox=nil;stackDetails=nil;app.update(dt)
    if clock>=wake then local ok,problem=coroutine.resume(runner);assert(ok,debug.traceback(runner,tostring(problem)))end
end
function love.draw()passiveRules={};app.draw()end
function love.errorhandler(msg)
    io.stderr:write(debug.traceback(tostring(msg))..'\n');io.stderr:flush()
    return function()return 1 end
end
