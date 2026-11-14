local oldClipboard
function love.errorhandler(message)
    if oldClipboard and love.system then pcall(love.system.setClipboardText,oldClipboard)end
    io.stderr:write('LIBRARY UI FAILED '..tostring(message)..'\n'..debug.traceback()..'\n');return function()return 1 end
end
local S=require('lib.Slab');local Assets=require('app.assets');local Fonts=require('app.fonts');local Layout=require('app.layout');local Theme=require('app.theme');local Library=require('app.library');local UI=require('app.library_ui');local json=require('lib.json')
local m,r,v,runner,Cursor,Region;local checks,buttons,queue,shots,inputs={},{},{},{},{};local elapsed,wake=0,0
local mouse={x=1,y=1};local down=false
local deck={id='imported',name='Imported Lightning',format='Modern',main={{name='Lightning Bolt',count=4},{name='Forest',count=56}},commander={},sideboard={},printingSelections={{name='Lightning Bolt',zone='main',count=4,set='m10',collectorNumber='161',printingId='bolt-printing'}}}
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('LIBRARY UI PASS '..label)end
local function wait(seconds)wake=elapsed+(seconds or .1);coroutine.yield()end
local function click(label)
    local box=assert(buttons[label],'Missing actual button '..label);local x,y=(box.x+box.w/2)*Layout.scale,(box.y+box.h/2)*Layout.scale
    mouse.x,mouse.y=x,y;S.OnMouseMoved(x,y,0,0);wait(.04);down=true;S.OnMousePressed(x,y,1,false,1);wait(.04);down=false;S.OnMouseReleased(x,y,1,false,1);wait(.16)
end
local function capture(name)shots[#shots+1]=name;wait(.15)end
local function scenario()
    wait(.15);m:showImport();love.system.setClipboardText('4 Lightning Bolt (M10) 161\n56 Forest');wait(.1)
    click('Paste');check(m.importText:find('Lightning Bolt',1,true),'Actual Paste button fills the UTF-8 multiline export input')
    click('Preview');check(m.importPreview and not m.saved,'Actual Preview displays deck and printing metadata without saving')
    check(buttons['Save deck']and m.importPreview.printingSelections[1].set=='m10','Preview retains the selected printing and offers explicit Save')
    capture('import-1440');click('Save deck');check(m.saved and m.saved.main[2].count==56 and m.saved.printingSelections[1].collectorNumber=='161','Actual Save preserves reviewed quantities and printing metadata')
    m:showHistory();wait(.2);check(m.historyItems[1].outcome=='win'and m.historyItems[1].players[2].deck.name=='Opponent deck','History presents supplied native-result and deck summaries')
    capture('history-1440');click('Open recording');check(m.openedReplay=='history-one','Actual history recording control opens the saved recording')
    m:showTokenSettings('my-deck');wait(.2);click('Random selected');click('Goblin · TM10');check(m.tokenMode=='randomSelected'and m.tokenSelected['goblin-0'],'Actual token controls select matching catalog artwork')
    capture('tokens-1440');click('Save token artwork');check(m.savedPrefs.mode=='randomSelected'and m.savedPrefs.selected[1]=='goblin-0','Actual token Save dispatches independent artwork preferences')
    love.window.setMode(1120,720,{vsync=0,resizable=true});Layout.setScale(1.25);S.SetScale(Layout.scale);Assets.invalidateRasterCaches();wait(.2)
    m:showImport('1 Unknown Card');wait(.1);click('Preview');check(m.importPreview and not m.importPreview.validation.saveAllowed,'Native/catalog validation errors retain a visible rejected preview')
    capture('import-error-1120');local previous=m.saved;click('Save deck');check(m.saved==previous,'Disabled Save prevents submitting an invalid preview')
    m:showTokenSettings('my-deck');wait(.2);capture('tokens-1120');check(buttons['Save token artwork'].y+buttons['Save token artwork'].h<=select(2,Layout.dimensions()),'Token save stays inside the smaller logical viewport')
    local file=assert(io.open('/tmp/love2gathering-library-ui-report.json','w'));file:write(json.encode({passed=true,checks=checks,scope='Actual themed LÖVE/Slab controls and multiline paste, synthetic service metadata/result adapter only; no native game or real service assertions',physical={love.graphics.getDimensions()},logical={Layout.dimensions()}}));file:close()
    print('LIBRARY UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
    local fonts,bold=Fonts.createSet(Fonts.default,{12,14,16,18,20,22,24});r={assets=Assets.new(),fonts=fonts,bold=bold,colors={text={.9,.94,.98},muted={.52,.63,.72},accent={.28,.89,.72},gold={.95,.75,.38}}};Theme.install(S,r.assets);S.GetStyle().Font=fonts[16];S.GetStyle().TextColor=r.colors.text
    local Model={};Model.__index=Model;function Model:getArt()return nil end;Library.install(Model)
    m=setmetatable({settings={showCardArt=true},format='Modern'},Model)
    function m:request(service,method,path,body,callback)
        local data
        if path=='/imports/preview'then data={deck=deck,printingSelections=deck.printingSelections,warnings={},validation={saveAllowed=not body.text:find('Unknown',1,true),playable=true,draft=false,errors=body.text:find('Unknown',1,true)and{{message='Unknown card: Unknown Card'}}or{}}}
        elseif path=='/decks'then self.saved=body;data=body
        elseif path:find('/history',1,true)then data={matches={{id='history-one',format='Modern',outcome='win',createdAt=1794600000000,players={{name='Player',deck={name='Imported Lightning'}},{name='XMage Bot',deck={name='Opponent deck'}}}}},total=1}
        elseif path:find('/token-art',1,true)then self.savedPrefs=body;data=body
        elseif path:find('/tokens?',1,true)then data={items={{id='token',tokenImageId='goblin-0',printing_id='goblin',name='Goblin',set='tm10',artist='Example artist',image_uris={normal='synthetic'}}},total=1,preferences={mode='default',selected={}}}
        end
        queue[#queue+1]=function()callback(data)end
    end
    function m:toast(text)self.message=text end;function m:refreshDecks()end;function m:openReplay(id)self.openedReplay=id end
    v={m=m,r=r,S=S};function v:window(id,x,y,w,h)S.BeginWindow(id,{X=x,Y=y,W=w,H=h,AutoSizeWindow=false,AutoSizeContent=false,AllowMove=false,AllowResize=false})end
    oldClipboard=love.system.getClipboardText();love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down end
    local original=S.Button;S.Button=function(label,options)local dx,dy=Region.Transform(nil,0,0);local result=original(label,options);local x,y,w,h=Cursor.GetItemBounds();buttons[label]={x=x+dx,y=y+dy,w=w,h=h};return result end
    local originalInput=S.Input;S.Input=function(id,options)local dx,dy=Region.Transform(nil,0,0);local result=originalInput(id,options);local x,y,w,h=Cursor.GetItemBounds();inputs[id]={x=x+dx,y=y+dy,w=w,h=h};return result end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    elapsed=elapsed+dt;assert(elapsed<35,'Library UI exceeded its bounded run')
    local pending=queue;queue={};for _,callback in ipairs(pending)do callback()end
    m:updateLibrary(dt);S.Update(dt)
    if elapsed>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
    local page=({import=UI.import,history=UI.history,tokens=UI.tokens})[m.page];if page then page(v,Layout.dimensions())end
end
function love.draw()
    love.graphics.clear(.025,.035,.055,1);love.graphics.push();love.graphics.scale(Layout.scale);S.Draw();love.graphics.pop()
    if#shots>0 then local name=table.remove(shots,1);local field=inputs['import-text'];love.graphics.captureScreenshot(function(data)
        local file=assert(io.open('/tmp/love2gathering-library-'..name..'.png','wb'));file:write(data:encode('png'):getString());file:close()
        if name:find('import',1,true)then
            local visible=0;for y=math.floor((field.y+5)*Layout.scale),math.floor((field.y+34)*Layout.scale)do for x=math.floor((field.x+8)*Layout.scale),math.floor((field.x+math.min(240,field.w-12))*Layout.scale)do local rr,gg,bb=data:getPixel(x,y);if rr>.6 and gg>.6 and bb>.6 then visible=visible+1 end end end
            check(visible>20,'Multiline export text has visible light glyph pixels on the dark input')
        end
    end)end
end
function love.quit()if oldClipboard then love.system.setClipboardText(oldClipboard)end;S.OnQuit()end
