-- Real LÖVE/Slab input and rendering; native multiplayer is tested separately.
function love.errorhandler(message)
    io.stderr:write('LOBBY UI FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
local requests={}
package.preload['app.api']=function()
    local API={}
    function API.escape(value)return tostring(value)end
    function API.new()
        return {catalogPort=17490,update=function()end,quit=function()end,request=function(_,service,method,path,body,callback)
            requests[#requests+1]={service=service,method=method,path=path,body=body}
            if path=='/session/start' then callback({gameId='LOBBY-SYNTHETIC-START',revision=1,players={},running=true}) end
        end}
    end
    return API
end
local S=require('lib.Slab');local Region=require('lib.Slab.Internal.UI.Region');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Layout=require('app.layout');local Preferences=require('app.preferences');local json=require('lib.json')
local m,r,v,prefs,runner,Cursor
local mouse={x=1,y=1};local down=false;local buttons={}
local checks={};local frames=0
local function expect(value,message)assert(value,message);checks[#checks+1]=message end
local function wait(count)for _=1,count or 3 do coroutine.yield()end end
local function move(x,y)
    local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale
    S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy)
end
local function click(box)
    assert(box,'Missing input control');move(box.x+box.w/2,box.y+box.h/2);wait(2)
    down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(2)
    down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(4)
end
local function screenshot(name,textControl)
    love.graphics.captureScreenshot(function(data)
        if textControl then
            local bright=0
            -- Sample the title area to the right of the cover/icon. A visible
            -- icon alone must not satisfy the selected-name pixel regression.
            for y=math.ceil((textControl.y+6)*Layout.scale),math.floor((textControl.y+38)*Layout.scale) do
                for x=math.ceil((textControl.x+90)*Layout.scale),math.floor((textControl.x+math.min(320,textControl.w-8))*Layout.scale) do
                    local rr,gg,bb=data:getPixel(x,y)
                    if rr>.40 and gg>.45 and bb>.50 then bright=bright+1 end
                end
            end
            expect(bright>35,'Selected bot tile name stays visible inside the scrolled form at UI scale '..Layout.scale)
        end
        local output=assert(io.open('/tmp/love2gathering-lobby-'..name..'.png','wb'));output:write(data:encode('png'):getString());output:close()
    end);wait(3)
end
local function mode(width,height,scale)
    m.settings.resolution=width..'x'..height;m.settings.uiScale=scale or 1
    m.settings.vsync=false;m.settings.sfxEnabled=false;m.settings.showCardArt=false;m.settings.animations=false
    prefs:apply(true);m.page='lobby';m.game=nil;wait(6)
end
local function chooseFifth(deckName,deckId)
    move(120,390);wait(2);S.OnWheelMoved(0,-150);wait(6)
    local fifth=buttons.botDeck5
    expect(fifth and fifth.y>240 and fifth.y+fifth.h<buttons['Start match'].y,'Fifth bot tile is visible after list scroll at UI scale '..Layout.scale)
    local otherIds={};for i=1,4 do otherIds[i]=m.botDeckIds[i]end
    click(fifth)
    expect(v.deckSelection and v.deckSelection.id=='botDeck5'and buttons[deckName],'Scrolled fifth-bot tile opens the actual deck grid')
    expect(buttons['Commander deck 6']and not buttons['Modern deck'],'Deck grid contains every Commander option and excludes other formats')
    screenshot('six-player-deck-grid-ui'..Layout.scale)
    click(buttons[deckName])
    expect(not v.deckSelection and m.botDeckIds[5]==deckId,'Actual deck tile selection changes the fifth bot')
    for i=1,4 do expect(m.botDeckIds[i]==otherIds[i],'Fifth-bot tile selection preserves bot '..i)end
end
local function startPayload(expected)
    click(buttons['Start match'])
    local body
    for i=#requests,1,-1 do if requests[i].path=='/session/start'then body=requests[i].body;break end end
    expect(body and body.bots and#body.bots==5,'Visible launch button sends all five bot decks at UI scale '..Layout.scale)
    expect(body.bots[5].deck.id==expected,'Launch preserves the fifth-bot tile selection')
end
local function run()
    mode(1440,900,1)
    expect(m:lobbyPlayerCount()==4,'Commander starts with four seats')
    expect(buttons.botDeck2 and buttons.botDeck3,'All three default bot tiles are constructed')
    expect(buttons['Start match'].y+buttons['Start match'].h<900,'Launch control fits at 1440×900')
    screenshot('1440-four-player')
    click(buttons['6']);expect(m:lobbyPlayerCount()==6,'Six-player button handles actual Slab input')
    chooseFifth('Commander deck 1','commander-1')
    screenshot('1440-six-player-scrolled',buttons.botDeck5)
    startPayload('commander-1')
    mode(1440,900,1.25)
    expect(Layout.scale==1.25,'Large window applies actual UI scale 1.25')
    chooseFifth('Commander deck 2','commander-2')
    screenshot('1440-six-player-scrolled-scaled',buttons.botDeck5)
    startPayload('commander-2')
    mode(1120,720,1.25)
    expect(buttons['Start match'].y+buttons['Start match'].h<=select(2,Layout.dimensions()),'Launch control fits a clamped 1120×720 window')
    move(120,350);wait(2);S.OnWheelMoved(0,150);wait(6)
    click(buttons['4']);expect(m:lobbyPlayerCount()==4,'Four-player option remains clickable in small window')
    screenshot('1120-four-player')
    click(buttons['2']);expect(m:lobbyPlayerCount()==2,'Commander duel remains available')
    screenshot('1120-duel')
    local report={passed=true,scope='Synthetic lobby decks and intercepted native start; actual LÖVE/Slab tile popup, six-seat scrolling, name-glyph pixels, fifth-bot selection and payload at UI scales 1/1.25; no native-game claims',checks=checks,physical={love.graphics.getDimensions()},logical={Layout.dimensions()},frames=frames}
    local output=assert(io.open('/tmp/love2gathering-lobby-ui-report.json','w'));output:write(json.encode(report));output:close()
    print('LOBBY UI PASS '..#checks..' checks');love.event.quit(0)
end
function love.load()
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor')
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down or false end
    m=Model.new();m.decks={}
    for i=1,6 do m.decks[#m.decks+1]={id='commander-'..i,name='Commander deck '..i,format='Commander',colorIdentity={('WUBRG'):sub((i-1)%5+1,(i-1)%5+1)},description='Commander deck for seat selection.',main={},sideboard={},commander={}}end
    m.decks[#m.decks+1]={id='modern',name='Modern deck',format='Modern',colorIdentity={'U'},main={},sideboard={},commander={}}
    m:setLobbyFormat('Commander');m.engineHealth={ok=true};m.catalogHealth={ready=false}
    r=Renderer.new(m);v=View.new(S,m,r);prefs=Preferences.new(m,S,r);v.preferences=prefs
    local originalButton=S.Button;S.Button=function(label,options)
        local dx,dy=Region.Transform(nil,0,0);local result=originalButton(label,options);local x,y,w,h=Cursor.GetItemBounds();buttons[label]={x=x+dx,y=y+dy,w=w,h=h};return result
    end
    runner=coroutine.create(run)
end
function love.update(dt)
    frames=frames+1;assert(frames<1800,'Lobby input acceptance timed out')
    if coroutine.status(runner)~='dead' then local ok,err=coroutine.resume(runner);if not ok then error(err)end end
    prefs:update();S.Update(dt);r:update(dt);buttons={};v:build()
end
function love.draw()
    prefs:beginFrame();r:draw();prefs:endScene();S.Draw();prefs:endFrame()
end
