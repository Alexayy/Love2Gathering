-- Actual LÖVE/Slab input and rendering, synthetic projections. Native rules are
-- exercised separately by bridge/tests/test_multiplayer.py and MultiplayerFixture.
function love.errorhandler(message)
    io.stderr:write('MULTIPLAYER UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function() return 1 end
end
local requests={}
package.preload['app.api']=function() return {new=function() return {request=function()end,update=function()end,quit=function()end} end} end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Layout=require('app.layout');local Preferences=require('app.preferences');local json=require('lib.json')
local m,r,v,prefs,runner,clock,wake,checks,shots,mouse,down,cases
local handFans,activeFan={},nil
local function check(value,label) assert(value,label);checks=checks+1;print('MULTIPLAYER UI PASS '..label) end
local function wait(t) wake=clock+(t or .08);coroutine.yield() end
local function shot(name) shots[#shots+1]=name;wait(.1) end
local function card(name,id,kind) return {name=name,id=id,type=kind or 'Creature',oracle_text='Synthetic UI fixture',power=kind and nil or '2',toughness=kind and nil or '2'} end
local function fixture(count)
    local players={}
    for i=1,count do
        local field={};for j=1,7 do field[#field+1]=card(i==1 and 'Mountain' or 'Forest','p'..i..'-land'..j,'Land') end
        for j=1,3 do field[#field+1]=card('Creature '..j,'p'..i..'-creature'..j) end
        players[i]={id='p'..i,seat=i-1,name=i==1 and 'Planeswalker' or 'XMage Bot '..(i-1),human=i==1,life=40,hand={},handCount=7,libraryCount=92,battlefield=field,command={card(i==1 and 'Krenko, Mob Boss' or 'Goreclaw, Terror of Qal Sisma','cmd'..i)},graveyard={card('Graveyard card','grave'..i)},exile={},mana={}}
    end
    for i=1,7 do players[1].hand[i]=card(i==1 and 'Mountain' or 'Spell '..i,'hand'..i,i==1 and 'Land' or 'Instant') end
    if count>=4 then
        players[2].handCount=0;players[3].handCount=17
        players[4].isHuman=true;players[4].isLocal=false;players[4].handCount=nil
        players[4].hand={{id='private-hand-sentinel',name='Private hand sentinel'}}
    end
    return {gameId='SYNTHETIC-MULTIPLAYER-'..count,revision=1,running=true,format='Commander',turn=3,phase='Precombat Main',step='Precombat Main',activePlayerId='p2',priorityPlayerId='p2',players=players,stack={},log={},revealed={{label='Public',cards={card('Revealed card','reveal')}}},lookedAt={}}
end
local function mode(width,height,ui,render)
    m.settings.resolution=width..'x'..height;m.settings.uiScale=ui;m.settings.renderScale=render;m.settings.windowMode='Windowed';m.settings.vsync=false
    m.settings.animations=false;m.settings.reducedMotion=false;m.settings.particles=false;m.settings.showTooltips=false;m.settings.sfxEnabled=false;m.settings.showCardArt=false
    m.settings.autoFollowTurn=false
    prefs:apply(true);m.logOpen=false;m.stackOpen=false;m.page='table';r.hover=nil;m.inspectCard=nil;m.zoneView=nil
end
local function hit(kind,id)
    for _,h in ipairs(r.hits) do if h.kind==kind and (not id or h.playerId==id or h.card and h.card.id==id) then return h end end
end
local function move(x,y)
    local px,py=mouse.x,mouse.y;mouse.x=x*Layout.scale;mouse.y=y*Layout.scale
    love.mousemoved(mouse.x,mouse.y,mouse.x-px,mouse.y-py,false)
end
local function click(h,button)
    assert(h,'Missing hit region');move(h.x+h.w/2,h.y+h.h/2);wait(.03)
    down[button or 1]=true;love.mousepressed(mouse.x,mouse.y,button or 1,false,1);wait(.03)
    down[button or 1]=false;love.mousereleased(mouse.x,mouse.y,button or 1,false,1);wait(.1)
end
local function verifyHandFans(name)
    local missing,intercept=0,0
    for _,p in ipairs(m.game.players)do
        local fan=handFans[p.id]
        if p.human then
            check(not fan,'Local hand retains its normal seat header and fixed face-up fan: '..name)
        else
            local count=p.handCount==nil and '?' or tostring(p.handCount)
            if not fan or not fan.labels[count] then missing=missing+1 end
            for _,box in ipairs(r.hits)do
                if fan and box.x<fan.x+fan.w and fan.x<box.x+box.w and box.y<fan.y+fan.h and fan.y<box.y+box.h then
                    intercept=intercept+1
                end
            end
        end
    end
    check(missing==0,'Every opponent fan shows the exact public count, including zero, seventeen and unknown: '..name)
    check(intercept==0,'Opponent hand fans occupy distinct space clear of all player, priority, zone and card targets: '..name)
    check(hit('seat-focus','p4').tooltip:find('? in hand',1,true),'A remote human’s seat uses the unknown public count: '..name)
    local before=#requests;click(handFans.p3)
    check(#requests==before and r.tableCamera.mode=='overview' and not m.inspectCard,'Clicking an opponent fan leaves the camera, card details and native actions unchanged: '..name)
end
local function scenario()
    for _,size in ipairs({{1440,900,1,1},{2537,1041,1,1},{1120,720,1,1},{1440,900,1.25,.75}}) do
        for _,count in ipairs(size[1]==1120 and {4,5,6} or {4,6}) do
            mode(unpack(size));m:setGame(fixture(count));r.cameraIdentity=nil;wait(.2)
            local view=r.multiplayerView;local camera=r.tableCamera;local name=count..'-players-'..size[1]..'-ui'..Layout.scale
            check(#r.multiplayerSeats==count and camera.rows==math.ceil(count/2),'Every seat has a field: '..name)
            check(camera.mode=='overview' and camera.zoom==camera.overviewZoom,'Fresh match opens on the full table: '..name)
            check(view.y>r.tableLayout.navY+28 and view.y+view.h>=select(2,Layout.dimensions())-24,'Terrain clears the seat controls and extends beneath the hand: '..name)
            local fieldCard=assert(hit('permanent','p2-creature2'))
            check(fieldCard.w/camera.zoom>=116 and fieldCard.w>fieldCard.h,'Battlefield permanents retain a readable landscape footprint in world space: '..name)
            local hands=0;for _,h in ipairs(r.hits) do if h.kind=='hand' then hands=hands+1 end end
            check(hands==7,'Human hand stays fixed and all bot hands stay hidden: '..name)
            verifyHandFans(name)
            for _,p in ipairs(m.game.players) do check(hit('seat-focus',p.id)~=nil,'Visible navigation for '..p.name..': '..name) end
            local reveal
            for _,box in ipairs(r.hits)do if box.revealed then reveal=box end end
            check(reveal and reveal.x>=hit('table-overview').x+hit('table-overview').w and
                reveal.x+reveal.w<=Layout.beforeDamage(select(1,Layout.dimensions())).x,'Reveal control clears seat navigation and the combat stop: '..name)
            click(reveal);check(m.zoneView and m.zoneView.cards[1].id=='reveal','Revealed cards open through their own control: '..name)
            m.zoneView=nil;wait(.08)
            shot(name..'-default')
            local small=assert(hit('hand','hand4'));local smallW=small.w
            move(small.x+small.w*.5,small.y+30);wait(.35)
            local expanded=assert(hit('hand','hand4'))
            check(r.handExpansion>.9 and expanded.w>smallW,'Hover raises and enlarges the focused hand card: '..name)
            shot(name..'-hand-hover')
            move(20,125);wait(.45)
            check(r.handExpansion<.1,'Hand contracts to expose the table after leaving: '..name)
            move(view.x+view.w*.5,view.y+view.h*.5);local zoom=camera.zoom;r:wheelmoved(0,1);wait(.08)
            check(camera.zoom>zoom,'Wheel zooms the actual world viewport: '..name)
            r:wheelmoved(0,-1);wait(.08)
            click(hit('table-overview'));shot(name..'-overview')
            for _,p in ipairs(m.game.players) do
                local nav=hit('seat-focus',p.id);local index=nav.focusIndex
                click(nav);check(camera.focusIndex==index,'Actual player click focuses '..p.name..': '..name)
                local c=camera:cell(index);local x,y=camera:project(c.x+c.w/2,c.y+c.h/2)
                check(x>=view.x and y>=view.y and x<=view.x+view.w and y<=view.y+view.h,'Focused seat is inside clipped viewport: '..name)
            end
            shot(name..'-focus')
            click(hit('seat-focus','p2'));wait(.1)
            m.settings.autoFollowTurn=true;wait(.08)
            local beforeX,beforeY=camera.x,camera.y
            move(view.x+view.w*.53,view.y+view.h*.51);wait(.03)
            down[2]=true;love.mousepressed(mouse.x,mouse.y,2,false,1);wait(.03)
            move(view.x+view.w*.53-120,view.y+view.h*.51-65);wait(.03)
            down[2]=false;love.mousereleased(mouse.x,mouse.y,2,false,1);wait(.1)
            check(camera.mode=='free' and (math.abs(camera.x-beforeX)>5 or math.abs(camera.y-beforeY)>5),'Actual right-drag pans in scaled logical coordinates: '..name)
            check(not m.inspectCard,'Right-drag never opens card details: '..name)
            local freeX,freeY=camera.x,camera.y;wait(.1)
            check(camera.mode=='free'and camera.x==freeX and camera.y==freeY,'Repeated native turn frames preserve manual pan: '..name)
            m.game.activePlayerId='p'..count;m.game.turn=4;m.game.revision=m.game.revision+1;wait(.15)
            check(camera.focusIndex==assert(hit('seat-focus','p'..count)).focusIndex,'Next native active-player transition automatically focuses its terrain: '..name)
            click(hit('seat-focus','p1'));wait(.15)
            check(camera.focusIndex==3,'Manual player focus stays until the next turn: '..name)
            m.settings.autoFollowTurn=false;m.game.activePlayerId='p2';m.game.turn=5;wait(.15)
            check(camera.focusIndex==3,'Disabled automatic follow leaves terrain focus under user control: '..name)
            m.settings.autoFollowTurn=true;wait(.15)
            check(camera.focusIndex==1,'Enabling automatic follow focuses the current active player: '..name)
            click(hit('table-overview'));check(camera.mode=='overview','Overview icon restores the entire terrain: '..name)
            click(hit('seat-focus','p1'));wait(.4) -- Inspect a stationary card after the camera tween arrives.
            local permanent=assert(hit('permanent','p1-creature2'),'Human field card not rendered')
            check(permanent.clip and permanent.clip.x==view.x and permanent.clip.y==view.y and permanent.clip.w==view.w and permanent.clip.h==view.h,'World card hit region has the same viewport clip: '..name)
            click(permanent,3);check(m.inspectCard and m.inspectCard.id==permanent.card.id,'Middle-click opens details for the visible card: '..name)
            m.inspectCard=nil;wait(.1)
            local countBefore=#requests
            m.game.prompt={id=1000+checks,type='target',message='Select a player',targets={'p'..count},choices={}}
            m.answeredPrompt=nil;m.actionBusy=false;wait(.1)
            click(hit('seat-focus','p'..count))
            check(#requests==countBefore+1 and requests[#requests].body.value=='p'..count,'Far-seat target sends its native player ID: '..name)
            if size[1]==1120 and count==6 then
                click(hit('table-overview'));wait(.4)
                m.game.prompt={id=1500+checks,type='pick_target',message='Choose a target player',
                    actionable={'p6'},choices={{id='p6',label='XMage Bot 5',responseType='uuid'}},cardPanel={kind='board'}}
                m.answeredPrompt=nil;m.actionBusy=false;wait(.1)
                local fan=handFans.p6;local life
                for _,box in ipairs(r.hits)do
                    if box.kind=='player' and box.focusIndex and box.card.id=='p6' and box.x>=fan.x+fan.w then life=box end
                end
                local before=#requests;click(life)
                check(#requests==before+1 and requests[#requests].body.value=='p6','The opponent life total beside the fan still selects the exact far-seat target')
            end
            m.actionBusy=false;m.answeredPrompt=nil;m.game.prompt={id=2000+checks,type='select',actionable={},targets={'p2'},choices={}};wait(.1)
            countBefore=#requests;click(hit('seat-focus','p2'))
            check(#requests==countBefore,'Empty actionable list remains authoritative: '..name)
            m.game.prompt=nil;m.actionBusy=false;m.answeredPrompt=nil
            cases[#cases+1]={players=count,physical={love.graphics.getDimensions()},ui=Layout.scale,render=size[4]}
        end
    end
    mode(1440,900,1,1);m:setGame(fixture(4));wait(.1);local liveCamera=r.tableCamera
    m.replay={id='same-recording',frames={},index=1};wait(.1)
    check(r.tableCamera~=liveCamera,'Opening a replay gets a separate camera identity')
    click(hit('table-overview'))
    local header=assert(hit('player','p2'));click(header)
    check(r.tableCamera.focusIndex==header.focusIndex and not m.inspectCard,'Replay player header focuses without inspecting a player as a card')
    local replayCamera=r.tableCamera;m.replay={id='same-recording',frames={},index=1};wait(.1)
    check(r.tableCamera~=replayCamera,'Reopening the same recording resets camera identity')
    m.replay=nil;wait(.1)
    m:setGame(fixture(6));m.logOpen=true;wait(.2)
    for _,p in ipairs(m.game.players) do
        local nav=assert(hit('seat-focus',p.id));click(nav)
        check(r.tableCamera.focusIndex==nav.focusIndex,'Default floating log leaves '..p.name..' navigation clickable')
    end
    click(hit('table-overview'));check(r.tableCamera.mode=='overview','Default floating log leaves overview clickable')
    shot('six-player-default-log')
    -- A tapped card can extend inside the clip while its unrotated bounds do not.
    r.hits={};r.worldTransform={x=0,y=0,scale=1,clip={x=0,y=0,w=100,h=100}}
    local edge=r:hit({x=-30,y=0,w=20,h=100,angle=math.pi/2,kind='permanent',card={id='edge'}});r.worldTransform=nil
    r:mousemoved(10,50);check(r.hover==edge,'Rotated card remains clickable at a clipped terrain edge')
    r:mousemoved(-10,50);check(not r.hover,'Offscreen portion of rotated card cannot intercept input')
    local nativeCases=0
    for _,file in ipairs({'native-four.json','native-six.json'}) do
        if love.filesystem.getInfo(file) then
            local frame=json.decode(love.filesystem.read(file));m:setGame(frame);m.page='table';m.logOpen=true;wait(.2)
            check(#r.multiplayerSeats==#frame.players,'Actual engine projection renders every seat: '..file)
            for _,p in ipairs(frame.players) do check(p.human or #p.hand==0,'Actual engine projection preserves hidden hands: '..file) end
            shot('actual-'..file:gsub('%.json$','')..'-overview')
            local last=frame.players[#frame.players];click(hit('seat-focus',last.id))
            check(r.tableCamera.focusIndex~=nil,'Actual engine projection seat focus works: '..file)
            shot('actual-'..file:gsub('%.json$','')..'-focus');nativeCases=nativeCases+1
        end
    end
    local duel=fixture(2);duel.gameId='SYNTHETIC-DUEL';m:setGame(duel);wait(.1)
    check(not r.multiplayerView and not r.tableCamera and not r.multiplayerSeats and not hit('seat-focus'),'Switching to a duel clears the prior multiplayer camera and its controls')
    shot('duel-preserved')
    local output=assert(io.open('/tmp/love2gathering-multiplayer-ui-report.json','w'));output:write(json.encode({checks=checks,cases=cases,nativeProjectionCases=nativeCases,source='synthetic input fixtures plus optional native projections; actual LÖVE input/rendering',engineActions=#requests}));output:close()
    print('MULTIPLAYER UI COMPLETE '..checks..' checks');love.event.quit(0)
end
function love.load()
    clock,wake,checks=0,0,0;shots={};mouse={x=0,y=0};down={};cases={}
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true)
    m=Model.new();m.request=function(self,service,method,path,body) if service=='engine' then requests[#requests+1]={method=method,path=path,body=body} end end
    m.settingsLoaded=true;m.uiLayout={};r=Renderer.new(m);v=View.new(S,m,r);prefs=Preferences.new(m,S,r);v.preferences=prefs;prefs.appliedLoaded=true
    local HUD=require('app.table_hud')
    local drawHand=assert(HUD.opponentHand)
    HUD.opponentHand=function(renderer,player,x,y,w,h,compact)
        if compact then
            activeFan=renderer:screenRect({x=x,y=y,w=w,h=h})
            activeFan.labels={};handFans[player.id]=activeFan
        end
        local result=drawHand(renderer,player,x,y,w,h,compact);activeFan=nil;return result
    end
    local strong=r.strong
    function r:strong(label,...)
        if activeFan then activeFan.labels[tostring(label)]=true end
        return strong(self,label,...)
    end
    local getArt=m.getArt
    function m:getArt(object,...)
        assert(not object or object.id~='private-hand-sentinel','Opponent hands may not request card identities or art')
        return getArt(self,object,...)
    end
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return down[button] or false end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    clock=clock+dt;assert(clock<100,'Multiplayer UI acceptance exceeded 100 seconds')
    prefs:update();S.Update(dt);r:update(dt)
    if clock>=wake and coroutine.status(runner)~='dead' then local ok,err=coroutine.resume(runner);assert(ok,err) end
    v:build();r:mousemoved(Layout.mouse())
end
function love.draw()
    handFans={};prefs:beginFrame();r:draw();prefs:endScene();S.Draw()
    if #shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)
        local f=assert(io.open('/tmp/love2gathering-multiplayer-'..name..'.png','wb'));f:write(data:encode('png'):getString());f:close()
    end) end
end
function love.mousepressed(x,y,b,t,c)
    S.OnMousePressed(x,y,b,t,c)
    if not m.settingsOpen and not m.zoneView and not m.inspectCard and S.IsVoidHovered() then r:mousepressed(x/Layout.scale,y/Layout.scale,b,c) end
end
function love.mousereleased(x,y,b,t,c) S.OnMouseReleased(x,y,b,t,c);r:mousereleased(x/Layout.scale,y/Layout.scale,b) end
function love.mousemoved(x,y,dx,dy,t) S.OnMouseMoved(x,y,dx,dy,t);r:mousemoved(x/Layout.scale,y/Layout.scale) end
function love.quit() S.OnQuit() end
