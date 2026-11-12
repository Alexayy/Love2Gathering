function love.errorhandler(message)
    io.stderr:write('ASSETS/INPUT FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function() return 1 end
end
local S=require('lib.Slab');local Assets=require('app.assets');local utf8=require('utf8')
local assets,input,steps,index,text,down,frame,done,selectionShot,particleShot,mouseDown,originalClipboard
local function key(name,mods)
    down={};for _,v in ipairs(mods or {}) do down[v]=true end
    S.OnKeyPressed(name,name,false);S.OnKeyReleased(name,name)
    down={}
end
local function equal(actual,expected,label) assert(actual==expected,(label or '')..' expected '..tostring(expected)..', got '..tostring(actual)) end
local function info()return input.GetDebugInfo()end
local function valid()assert(utf8.len(text),'Text ceased to be valid UTF-8')end
local function add(label,act,check)steps[#steps+1]={label=label,act=act,check=check}end
function love.load()
    originalClipboard=love.system.getClipboardText()
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true)
    local style=S.GetStyle();style.Font=love.graphics.newFont('assets/fonts/DejaVuSans.ttf',19);style.TextColor={.92,.96,1,1};style.WindowBackgroundColor={.04,.06,.09,1};style.InputBgColor={.07,.10,.15,1};style.InputEditBgColor={.07,.10,.15,1};style.InputSelectColor={.16,.42,.49,1}
    input=require('lib.Slab.Internal.UI.Input');assets=Assets.new();steps={};index=0;text='Izzet Phoenix';down={};frame=0
    love.keyboard.isScancodeDown=function(...)for _,k in ipairs({...}) do if down[k] then return true end end return false end
    love.mouse.isDown=function(button)return button==1 and mouseDown or false end
    add('focus',function()S.SetInputCursorPos(#text)end,function()assert(S.IsAnyInputFocused())end)
    add('fast Ctrl+A press/release',function()key('a',{'lctrl'})end,function()equal(info().SelectionStart,0);equal(info().SelectionEnd,#text)end)
    add('UTF-8 selection replacement',function()S.OnTextInput('čarobna šuma')end,function()equal(text,'čarobna šuma')end)
    add('Ctrl+Left UTF-8 word',function()key('left',{'lctrl'})end,function()equal(info().CursorPos,#'čarobna ')end)
    add('Ctrl+Shift+Right selection',function()key('right',{'lctrl','lshift'})end,function()equal(info().SelectionStart,#'čarobna ');equal(info().SelectionEnd,#text)end)
    add('copy selected word',function()key('c',{'lctrl'})end,function()equal(love.system.getClipboardText(),'šuma')end)
    add('cut selected word',function()key('x',{'lctrl'})end,function()equal(text,'čarobna ');equal(info().CursorPos,#text)end)
    add('paste UTF-8',function()key('v',{'lctrl'})end,function()equal(text,'čarobna šuma');equal(info().CursorPos,#text)end)
    add('Home',function()key('home')end,function()equal(info().CursorPos,0)end)
    add('Right crosses complete code point',function()key('right')end,function()equal(info().CursorPos,#'č')end)
    add('held Shift setup',function()down.lshift=true;S.OnKeyPressed('lshift','lshift',false)end)
    add('held Shift+Right selection',function()S.OnKeyPressed('right','right',false);S.OnKeyReleased('right','right')end,function()equal(info().SelectionStart,#'č');equal(info().SelectionEnd,#'ča');down={}end)
    add('Backspace deletes selection',function()key('backspace')end,function()equal(text,'črobna šuma');equal(info().CursorPos,#'č')end)
    add('Ctrl+Delete next word',function()key('delete',{'lctrl'})end,function()equal(text,'čšuma');equal(info().CursorPos,#'č')end)
    add('Ctrl+Backspace previous UTF-8 word',function()key('backspace',{'lctrl'})end,function()equal(text,'šuma');equal(info().CursorPos,0)end)
    add('Delete one complete UTF-8 character',function()key('delete')end,function()equal(text,'uma');equal(info().CursorPos,0)end)
    add('Ctrl+A before second replacement',function()key('a',{'rctrl'})end)
    add('replace with mana test',function()S.OnTextInput('mana test')end,function()equal(text,'mana test')end)
    add('place caret in middle',function()S.SetInputCursorPos(2)end,function()equal(info().CursorPos,2)end)
    add('paste keeps caret immediately after inserted text',function()key('v',{'lctrl'})end,function()equal(text,'mašumana test');equal(info().CursorPos,2+#'šuma')end)
    add('Shift+Home selects prefix',function()key('home',{'lshift'})end,function()equal(info().SelectionStart,0);equal(info().SelectionEnd,2+#'šuma');selectionShot=true end)
    add('replace prefix',function()S.OnTextInput('X')end,function()equal(text,'Xna test')end)
    add('End',function()key('end')end,function()equal(info().CursorPos,#text)end)
    add('Ctrl+Backspace final word',function()key('backspace',{'lctrl'})end,function()equal(text,'Xna ')end)
    add('Ctrl+Backspace final prefix',function()key('backspace',{'lctrl'})end,function()equal(text,'');equal(info().CursorPos,0)end)
    add('empty boundaries remain safe',function()key('backspace',{'lctrl'});key('delete',{'lctrl'})end,function()equal(text,'');equal(info().CursorPos,0)end)
    add('prepare mouse selection text',function()S.OnTextInput('čarobna šuma')end,function()equal(text,'čarobna šuma')end)
    add('mouse places UTF-8 caret',function()
        local x=34+S.GetStyle().Font:getWidth('č');S.OnMouseMoved(x,89,0,0);mouseDown=true;S.OnMousePressed(x,89,1,false,1)
    end,function()equal(info().CursorPos,#'č')end)
    add('mouse release preserves caret',function()
        local x=34+S.GetStyle().Font:getWidth('č');mouseDown=false;S.OnMouseReleased(x,89,1,false,1)
    end,function()equal(info().CursorPos,#'č')end)
    add('mouse drag starts selection',function()S.OnMouseMoved(34,89,0,0);mouseDown=true;S.OnMousePressed(34,89,1,false,1)end,function()equal(info().CursorPos,0)end)
    add('mouse drag highlights UTF-8 range',function()local x=34+S.GetStyle().Font:getWidth(text);S.OnMouseMoved(x,89,100,0)end,function()equal(info().SelectionStart,0);equal(info().SelectionEnd,#text)end)
    add('mouse release keeps selected range',function()local x=34+S.GetStyle().Font:getWidth(text);mouseDown=false;S.OnMouseReleased(x,89,1,false,1)end,function()equal(info().SelectionStart,0);equal(info().SelectionEnd,#text)end)
    add('font glyphs and real image metadata',function()
        local f=assets:font(24)
        for _,cp in pairs(require('assets.keyrune.glyphs')) do assert(f:hasGlyphs(utf8.char(cp)))end
        equal(assets.panelImage:getWidth(),64);equal(assets.textures.glow:getWidth(),512)
        for _,name in ipairs({'click','cast','resolve'}) do local sound=love.sound.newSoundData('assets/kenney/sounds/'..name..'.ogg');assert(sound:getSampleCount()>0 and sound:getChannelCount()==2)end
        local icon=love.image.newImageData(assets:icon());equal(icon:getWidth(),256);local _,_,_,a=icon:getPixel(0,0);equal(a,0)
        assets:particle('cast',400,490,10);assets:particle('resolve',560,490,10);equal(#assets.particles,20);particleShot=true
    end)
end
local function build()
    S.BeginWindow('editing',{X=30,Y=22,W=840,H=150,Title='Text editing and supplied asset integration',AllowMove=false,AllowResize=false,AutoSizeWindow=false})
    S.Text('Ctrl+A, selection, UTF-8 word editing, clipboard and visible caret')
    if S.Input('field',{Text=text,W=770,H=35,Align='left',SelectOnFocus=false})then text=S.GetInputText()end
    if frame==1 then S.SetInputFocus('field')end
    S.EndWindow()
end
function love.update(dt)
    frame=frame+1
    if frame>2 and index<#steps then
        index=index+1;steps[index].act()
    end
    S.Update(dt);build();assets:update(dt)
    if frame>2 and index>0 and not done then
        valid();if steps[index].check then steps[index].check()end
        print('ASSETS/INPUT PASS: '..steps[index].label)
    end
    if index==#steps then done=(done or 0)+1;if done>4 then print('ASSETS/INPUT COMPLETE: '..#steps..' actual LÖVE/Slab checks');love.event.quit(0)end end
end
function love.draw()
    love.graphics.clear(.025,.04,.065,1);assets:panel(26,190,848,210,'dark');assets:panel(30,418,844,185,'accent')
    local x=60
    for _,symbol in ipairs({'W','U','B','R','G','C','0','1','2','3','9','X','T','Q','S'}) do assets:mana(symbol,x,226,38);x=x+52 end
    assets:mana('{2}{U}{R}',80,310,34);assets:mana('2/U',265,310,34);assets:mana('B/P',315,310,34);assets:mana('G/U/P',365,310,34)
    love.graphics.setColor(1,1,1,1);local icon=love.graphics.newImage('assets/icons/thb.png');love.graphics.draw(icon,690,276,0,.38,.38)
    assets:drawParticles();S.Draw()
    if particleShot then
        particleShot=false
        love.graphics.captureScreenshot(function(data)local file=assert(io.open('/tmp/love2gathering-assets-particles.png','wb'));file:write(data:encode('png'):getString());file:close()end)
    end
    if selectionShot then
        selectionShot=false
        love.graphics.captureScreenshot(function(data)local file=assert(io.open('/tmp/love2gathering-assets-input.png','wb'));file:write(data:encode('png'):getString());file:close()end)
    end
end
function love.quit()if originalClipboard then love.system.setClipboardText(originalClipboard)end;S.OnQuit()end
