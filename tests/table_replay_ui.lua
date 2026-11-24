function love.errorhandler(message)
    io.stderr:write('TABLE/REPLAY FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Layout=require('app.layout');local Preferences=require('app.preferences');local json=require('lib.json')
local m,r,v,prefs,Cursor,runner,wake,clock,checks,windows,buttons,mouse,down,shots,requests,reports,images,texts,navCalled
local function check(condition,message)assert(condition,message);checks=checks+1;print('TABLE/REPLAY PASS '..message)end
local function wait(seconds)wake=clock+(seconds or .06);coroutine.yield()end
local function untilTrue(fn,label,timeout)
    local endAt=clock+(timeout or 12)
    while not fn()do assert(clock<endAt,'Timed out: '..label..' '..json.encode({page=m and m.page,replay=m and m.replay and {id=m.replay.id,frames=#m.replay.frames,metadata=m.replay.metadata~=nil},loading=m and m.replayLoading,toasts=m and m.toasts}));wait(.04)end
end
local function shot(name)shots[#shots+1]=name;wait(.08)end
local function card(name,id,kind)
    local c={id=id,name=name,type=kind or 'Creature'};if not kind then c.power='2';c.toughness='2' end;return c
end
local function fixture(lands)
    local humanField,botField={},{}
    for i=1,lands do humanField[#humanField+1]=card('Mountain','human-land-'..i,'Land');botField[#botField+1]=card('Island','bot-land-'..i,'Land')end
    for i=1,3 do humanField[#humanField+1]=card('Monastery Swiftspear','human-creature-'..i);botField[#botField+1]=card('Goblin Guide','bot-creature-'..i)end
    local hand={};for i,name in ipairs({'Mountain','Lightning Bolt','Monastery Swiftspear','Boros Charm','Lava Spike','Sacred Foundry','Arclight Phoenix'})do hand[#hand+1]=card(name,'hand-'..i,(name=='Mountain' or name=='Sacred Foundry')and'Land'or'Instant')end
    local log={};for i,category in ipairs({'cast','resolve','trigger','damage','attack','turn','draw','land','mana','zone','system'})do log[#log+1]={text=(i%2==0 and 'XMage Bot' or 'You')..' · '..category..' · {R}{U} typed log fixture',actor=i%2==0 and'bot'or'human',category=category}end
    return {gameId='UI-ONLY-SYNTHETIC-'..lands,revision=100+lands,running=true,turn=4,phase='Precombat Main',step='Precombat Main',activePlayerId='human',priorityPlayerId='human',
        players={{id='human',name='You · isolated UI fixture',human=true,life=17,hand=hand,handCount=#hand,libraryCount=43,battlefield=humanField,graveyard={card('Lightning Bolt','grave-bolt','Instant')},exile={},command={},mana={R=2,U=1}},
        {id='bot',name='XMage Bot · fixture',human=false,life=13,hand={},handCount=7,libraryCount=42,battlefield=botField,graveyard={card('Lava Spike','grave-lava','Sorcery')},exile={},command={},mana={}}},
        stack={},log=log,prompt={id=300+lands,type='select',message='Play spells and abilities',actionable={'hand-2'},targets={'hand-2'},choices={{id='done',label='Pass / Done',responseType='boolean',value=true}}}}
end
local function mode(w,h,ui,render)
    m.settings.resolution=w..'x'..h;m.settings.windowMode='Windowed';m.settings.vsync=false;m.settings.msaa=0;m.settings.uiScale=ui or 1;m.settings.renderScale=render or 1
    m.settings.animations=false;m.settings.particles=false;m.settings.sfxEnabled=false;m.settings.showTooltips=false;m.settings.showCardArt=true
    prefs:apply(true);m.settingsLoaded=true;prefs.appliedLoaded=true
    r.hover=nil;r.poses={};r.cardRects={};m.settingsOpen=false;m.zoneView=nil;m.inspectCard=nil;m.toasts={}
    m.uiLayout={};m.uiLayoutVersion=(m.uiLayoutVersion or 0)+1;m.logOpen=false;m.stackOpen=true
end
local function click(label)
    local b=assert(buttons[label],'Button absent: '..label)
    mouse.x,mouse.y=(b.x+b.w/2)*Layout.scale,(b.y+b.h/2)*Layout.scale
    S.OnMouseMoved(mouse.x,mouse.y,0,0);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait()
    down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.08)
end
local function drag(x,y,dx,dy)
    mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,0,0);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait()
    mouse.x,mouse.y=mouse.x+dx*Layout.scale,mouse.y+dy*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,dx*Layout.scale,dy*Layout.scale);wait()
    down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.12)
end
local function inspectLayout(n,name)
    local w,h=Layout.dimensions();local pw,ph=love.graphics.getDimensions();local L=r.tableLayout
    check(not navCalled and L.board.x==16 and L.board.y==16 and L.board.w==w-32,'Full-width table and hidden navigation: '..name)
    local first,last=r.cardRects['human-land-1'],r.cardRects['human-land-'..n];local creature=assert(r.cardRects['human-creature-1'])
    check(first and last and first.y>=creature.y+creature.h+10,'Lands occupy a distinct lower row: '..name)
    local center=(first.x+last.x+last.w)/2;local target=L.fieldX+L.fieldW/2
    check(last.x+last.w>=L.fieldX+L.fieldW-8,'Short and crowded mana rows occupy the back-right edge: '..name)
    local handTop=h;local handCount=0
    for _,hit in ipairs(r.hits)do if hit.kind=='hand'then handTop=math.min(handTop,hit.y);handCount=handCount+1 end end
    check(handCount==7 and last.y+last.h<handTop-8,'Seven-card fan clear of lower mana row: '..name)
    check(first.x>=L.fieldX and last.x+last.w<=L.fieldX+L.fieldW,'Mana row remains inside full-width field: '..name)
    check(buttons['Table options'] and buttons['Stack 0'],'Table tools remain accessible: '..name)
    if n==1 then
        click('Table options')
        check(buttons['Presentation settings'] and buttons['Return to lobby'] and buttons['Replay library'],
            'Table options exposes settings, lobby and replay library: '..name)
        click('Close options')
    end
    reports[#reports+1]={name=name,physical={pw,ph},logical={w,h},scale=Layout.scale,render=m.settings.renderScale,lands=n,landRowCenter=center,fieldCenter=target,landCardHeight=first.h,handTop=handTop,landBottom=last.y+last.h}
end
local function inspectStack(name)
    local art=buttons['Inspect source card'];local rules=texts['stack-rules'];local stackWindow=windows['floating-stack'];local replayWindow=windows['replay-controls']
    check(art and rules and rules.x>=art.x+art.w+6,'Stack rules stay inside text column beside source artwork: '..name)
    check(stackWindow.y+stackWindow.h+stackWindow.titleH<=replayWindow.y or stackWindow.x>=replayWindow.x+replayWindow.w,'Floating stack leaves replay control strip unobstructed: '..name)
end
local function scenario()
    untilTrue(function()return #m.decks>=20 and m.catalogHealth.ready and m.settingsLoaded and m.uiLayout end,'Real catalog and isolated SQLite preferences')
    mode(1440,900)
    for _,name in ipairs({'instant','ability','damage','attack','turn','draw','land','C','graveyard','info'})do
        local image=r.assets:iconImage(name,24);local d=image:newImageData();local visible=false
        for y=0,d:getHeight()-1 do for x=0,d:getWidth()-1 do if select(4,d:getPixel(x,y))>.1 then visible=true end end end
        check(visible,'Typed log icon has visible pixels: '..name)
    end
    for _,size in ipairs({{1440,900,1,1},{1120,720,1,1},{1440,900,1.25,.75}})do
        mode(size[1],size[2],size[3],size[4])
        for _,n in ipairs({1,3,7,12})do
            m:setGame(fixture(n));m.page='table';m.pollTimer=99999;wait(n==1 and 1.2 or .12)
            local name=size[1]..'x'..size[2]..'-ui'..Layout.scale..'-lands'..n;inspectLayout(n,name)
            shot(name)
        end
        if size[4]==.75 then check(prefs.canvas and prefs.canvas:getWidth()==1080 and prefs.canvas:getHeight()==675,'Render scale .75 uses smaller scene canvas while UI remains native')end
    end
    mode(1440,900,1.25,.75);m:setGame(fixture(7));m.page='table';m.pollTimer=99999;m.logOpen=true;wait(.2)
    local start=assert(windows['floating-log']);start={x=start.x,y=start.y,w=start.w,h=start.h};wait(.2)
    local stable=windows['floating-log'];check(math.abs(stable.x-start.x)<.1 and math.abs(stable.y-start.y)<.1 and math.abs(stable.w-start.w)<.1 and math.abs(stable.h-start.h)<.1,'Floating log idle geometry does not drift or grow')
    -- Move away from right screen edge before resizing.
    local dx,dy=-200,45;drag(start.x+45,start.y+8,dx,dy)
    local moved=windows['floating-log'];check(math.abs(moved.x-start.x-dx)<1 and math.abs(moved.y-start.y-dy)<1,'Actual title drag follows pointer at UI scale 1.25 / render .75')
    local old={x=moved.x,y=moved.y,w=moved.w,h=moved.h};local titleH=moved.titleH
    -- The right edge contains Slab's scrollbar; use the opposite corner.
    drag(old.x+2,old.y+old.h+titleH-2,-85,55)
    local resized=windows['floating-log'];check(math.abs(resized.w-old.w-85)<1 and math.abs(resized.h-old.h-55)<1,'Actual log corner drag matches width/height pointer deltas: '..json.encode({before=old,after=resized,titleH=titleH}))
    shot('floating-log-dragged-resized-scaled');wait(.8)
    local saved;m:request('catalog','GET','/ui-layout',nil,function(data)saved=data end);untilTrue(function()return saved end,'Persisted UI layout response')
    local w,h=Layout.dimensions();local value=saved['floating-log'];check(value and math.abs(value.x-resized.x/w)<.002 and math.abs(value.y-resized.y/h)<.002 and math.abs(value.w-(resized.w-14)/w)<.002 and math.abs(value.h-(resized.h-14)/h)<.002,'Moved and resized log persisted to isolated SQLite')
    m.uiLayout=saved;m.uiLayoutVersion=m.uiLayoutVersion+1;v.floatBases={};wait(.15)
    local restored=windows['floating-log'];check(math.abs(restored.x-resized.x)<1 and math.abs(restored.y-resized.y)<1 and math.abs(restored.w-resized.w)<1 and math.abs(restored.h-resized.h)<1,'Saved normalized window geometry reapplies without border growth')
    mode(1440,900);m:setGame(fixture(3));m.pollTimer=99999;m.logOpen=true
    m:showReplays();untilTrue(function()return not m.replaysBusy and #(m.replays or {})>0 end,'Real replay library from copied SQLite')
    local recording
    for _,item in ipairs(m.replays)do if item.id=='game-90bfee5e-813c-435a-9746-7c5b3ff779cb'then recording=item end end
    check(recording and recording.status=='completed' and recording.frameCount==413,'Real XMage recording metadata: completed, 413 frames')
    m.replays={recording};wait(.12);shot('real-replay-library-metadata');click('Open recording')
    untilTrue(function()return m.replay and not m.replayLoading and #m.replay.frames==413 and m.replay.metadata end,'413 real frames and replay metadata loaded in pages',75)
    check(m.page=='table' and m.replay.index==1 and not m:prompt(),'Replay opens as table in view-only mode')
    local stackFrame;local events=0
    for i,frame in ipairs(m.replay.frames)do
        for _,player in ipairs(frame.data.players or {})do if not player.human then assert(#(player.hand or {})==0,'Bot hand leaked in real replay frame '..i);break end end
        if not stackFrame and #(frame.data.stack or {})>0 then stackFrame=i end
        events=events+#(frame.data.log or {})
    end
    check(stackFrame and events>0,'413 real frames contain stack/logs and preserve hidden bot hands')
    m:seekReplay(stackFrame);wait(.2)
    untilTrue(function()return buttons['Inspect source card']end,'Stack source art decoded from real card image',15)
    check(windows['floating-stack'] and buttons['Inspect source card'] and buttons['Play replay'],'Replay renders source-card stack art and playback controls')
    inspectStack('1440x900')
    shot('real-replay-stack-art-richtext')
    for _,size in ipairs({{1120,720,1,1},{1440,900,1.25,.75}})do
        mode(size[1],size[2],size[3],size[4]);wait(.15)
        inspectStack(size[1]..'x'..size[2]..'-ui'..Layout.scale)
        shot('real-replay-stack-'..size[1]..'x'..size[2]..'-ui'..Layout.scale)
    end
    mode(1440,900);wait(.1)
    local index=m.replay.index;click('Next frame');check(m.replay.index==index+1,'Actual Next frame control advances real recording')
    click('Previous frame');check(m.replay.index==index,'Actual Previous frame control reverses real recording')
    click('Play replay');check(m.replay.playing,'Actual Play replay control starts playback');wait(.3)
    check(m.replay.index>index,'Timed playback advances saved frames');click('Pause replay');check(not m.replay.playing,'Actual Pause replay control stops playback')
    local live=fixture(12);live.revision=999;m:setGame(live);local stale=fixture(1);stale.gameId=live.gameId;stale.revision=998;m:setGame(stale)
    check(m.liveGame.revision==999 and m.game~=live,'Live snapshot revisions stay separate while replay is visible')
    click('Close replay');check(not m.replay and m.game.gameId==live.gameId and m.game.revision==999,'Actual Close replay restores latest live revision')
    m.pollTimer=99999
    check(#requests==0,'UI fixture and replay interactions send no engine requests')
    local quitProbe={x=.1,y=.2,w=.3,h=(love.timer.getTime()%100)/100}
    m:setUILayout('table-replay-quit-probe',quitProbe)
    local f=assert(io.open('/tmp/love2gathering-table-replay-ui-report.json','w'));f:write(json.encode({checks=checks,cases=reports,replayId=recording.id,frames=recording.frameCount,stackFrame=stackFrame,engineRequests=#requests,quitProbe=quitProbe}));f:close()
    print('TABLE/REPLAY COMPLETE '..checks..' checks');love.event.quit(0)
end
function love.load()
    clock,wake,checks=0,0,0;windows={};buttons={};mouse={x=0,y=0};shots={};requests={};reports={};images={};texts={}
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor')
    m=Model.new();local originalRequest=m.request
    m.request=function(self,service,method,path,body,callback,quiet)
        if service=='engine'then if path=='/health' and method=='GET'then if callback then callback({ready=true,status='ok'})end;return end;requests[#requests+1]={method=method,path=path};error('Unexpected engine access '..method..' '..path)end
        return originalRequest(self,service,method,path,body,callback,quiet)
    end
    r=Renderer.new(m);v=View.new(S,m,r);prefs=Preferences.new(m,S);v.preferences=prefs
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down or false end
    local originalWindow=v.window;v.window=function(self,id,...)
        originalWindow(self,id,...);local x,y=S.GetWindowPosition();local w,h=S.GetWindowSize();local _,_,_,outerH=require('lib.Slab.Internal.UI.Window').GetBounds();windows[id]={x=x,y=y,w=w,h=h,titleH=outerH-h}
    end
    local originalButton=S.Button;S.Button=function(label,options)
        local result=originalButton(label,options);local x,y,w,h=Cursor.GetItemBounds();buttons[label]={x=x,y=y,w=w,h=h};return result
    end
    local originalNav=r.drawNav;r.drawNav=function(self,...)navCalled=true;return originalNav(self,...)end
    local rich=require('app.richtext');local originalRich=rich.slab;rich.slab=function(view,id,...)
        local result=originalRich(view,id,...);local x,y,w,h=Cursor.GetItemBounds();texts[id]={x=x,y=y,w=w,h=h};return result
    end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    clock=clock+dt;assert(clock<150,'Whole UI acceptance exceeded 150 seconds')
    m:update(dt);prefs:update();S.Update(dt);r:update(dt)
    if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
    buttons={};v:build();m.pollTimer=99999
end
function love.draw()
    navCalled=false;prefs:beginFrame();r:draw();prefs:endScene();S.Draw();love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();r:drawToasts(Layout.dimensions());love.graphics.pop()
    if #shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)
        local f=assert(io.open('/tmp/love2gathering-table-replay-'..name..'.png','wb'));f:write(data:encode('png'):getString());f:close()
    end)end
end
function love.quit()if m then m:quit()end;S.OnQuit()end
