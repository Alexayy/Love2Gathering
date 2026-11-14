function love.errorhandler(message)
    io.stderr:write('FONTS FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
local Fonts=require('app.fonts');local Assets=require('app.assets');local Preferences=require('app.preferences')
local S=require('lib.Slab');local Settings=require('app.settings');local Layout=require('app.layout')
local r,m,v,prefs,frame,checks,systemFamily,beforeSelection
local mouse={x=1,y=1};local mouseDown=false;local controls,choices,buttons={},{},{}
local function check(condition,message)assert(condition,message);checks=checks+1;print('FONTS PASS '..message)end
local function pixels(canvas)
    local image=canvas:newImageData();local count=0
    for y=0,image:getHeight()-1 do for x=0,image:getWidth()-1 do local _,_,_,a=image:getPixel(x,y);if a>.05 then count=count+1 end end end
    return count
end
function love.load()
    checks=0;frame=0;S.SetINIStatePath(nil);S.Initialize({'nocursor'},true)
    local catalog=Fonts.available();check(#catalog>=1 and #catalog<=Fonts.limit,'System font list is bounded and always includes the built-in font')
    check(catalog==Fonts.available() and catalog[1].name==Fonts.default,'Discovery is cached with a stable fallback')
    local sizes={10,12,14,16,18,20,22,24,28,32,36,44,52}
    local fonts,bold,problem,effective=Fonts.createSet(Fonts.default,sizes)
    check(not problem and effective==Fonts.default and fonts[16]:getHeight()>0 and bold:getHeight()>0,'Built-in fonts load at logical interface sizes')
    r={assets=Assets.new(),fonts=fonts,bold=bold,colors={text={.90,.94,.98},muted={.46,.56,.66},accent={.28,.89,.72}}}
    for _,name in ipairs({'player','bot','players','focus','pan','overview','commander','life'})do
        local icon=r.assets:iconImage(name,28);check(pixels(icon)>20,'Visible '..name..' icon uses existing assets or interface geometry')
    end
    local mana=r.assets:font(24)
    for i=2,#catalog do
        local trial,_,issue=Fonts.createSet(catalog[i].name,{16})
        if not issue and trial[16]:hasGlyphs('Čarobna šuma Aa0123456789') then systemFamily=catalog[i].name;break end
    end
    m={settings={},toasts={},toast=function(self,message)self.toasts[#self.toasts+1]=message end,saveSettings=function(self)self.savedFamily=self.settings.fontFamily end}
    prefs=Preferences.new(m,S,r)
    m.settings.fontFamily=Fonts.default;prefs:applyFont();beforeSelection=r.fonts[16]
    m.settings.resolution='1120x720';m.settings.vsync=false
    check(prefs.appliedFontFamily==m.settings.fontFamily and S.GetStyle().Font==r.fonts[16],'Applying a family updates the table fonts and Slab default')
    check(r.assets.textFonts[16]==r.fonts[16] and r.assets:font(24)==mana,'Text fonts change without changing Mana symbols')
    local original=r.fonts[16];prefs:applyFont();check(r.fonts[16]==original,'Unchanged family does not rebuild fonts')
    m.settings.fontFamily='/tmp/a-font-path-is-not-a-family.ttf';prefs:applyFont()
    check(prefs.appliedFontFamily==Fonts.default and #m.toasts==1,'Unavailable or path-like saved family safely falls back with feedback')
    m.settings.fontFamily=Fonts.default;prefs:applyFont();beforeSelection=r.fonts[16]
    v={S=S,m=m,r=r,preferences=prefs,settingsTab='Accessibility'}
    function v:window(id,x,y,w,h,title)S.BeginWindow(id,{X=x,Y=y,W=w,H=h,Title=title,AutoSizeWindow=false,AllowMove=false,AllowResize=false})end
    function v:combo(id,selected,items,width,changed)
        if S.BeginComboBox(id,{Selected=tostring(selected),W=width})then for _,item in ipairs(items)do if S.TextSelectable(tostring(item),{Selected=item==selected})then changed(item)end end;S.EndComboBox()end
    end
    love.mouse.getPosition=function()return mouse.x,mouse.y end
    love.mouse.isDown=function(button)return button==1 and mouseDown or false end
    local Cursor=require('lib.Slab.Internal.Core.Cursor')
    for _,name in ipairs({'BeginComboBox','TextSelectable','Button'})do
        local original=S[name]
        S[name]=function(id,options)
            local result=original(id,options);local x,y,w,h=Cursor.GetItemBounds()
            local target=name=='BeginComboBox' and controls or name=='TextSelectable' and choices or buttons
            target[id]={x=x,y=y,w=w,h=h};return result
        end
    end
    print(systemFamily and 'FONTS SYSTEM '..systemFamily or 'FONTS SYSTEM unavailable; built-in fallback verified')
end
local function click(box,pressed)
    assert(box,'Expected font settings control is missing')
    local x,y=(box.x+box.w/2)*Layout.scale,(box.y+box.h/2)*Layout.scale
    mouse.x,mouse.y=x,y;mouseDown=pressed;S.OnMouseMoved(x,y,0,0)
    if pressed then S.OnMousePressed(x,y,1,false,1)else S.OnMouseReleased(x,y,1,false,1)end
end
function love.update(dt)
    frame=frame+1
    if frame==4 then click(controls['setting-fontFamily'],true)
    elseif frame==5 then click(controls['setting-fontFamily'],false)
    elseif frame==8 then click(choices[systemFamily or Fonts.default],true)
    elseif frame==9 then click(choices[systemFamily or Fonts.default],false)
    elseif frame==12 then
        check(m.settings.fontFamily==(systemFamily or Fonts.default),'Actual settings dropdown selects the installed family')
        check(r.fonts[16]==beforeSelection,'Font selection waits for Apply and save')
        click(buttons['Apply and save'],true)
    elseif frame==13 then click(buttons['Apply and save'],false)
    elseif frame==17 then
        check(m.savedFamily==(systemFamily or Fonts.default) and prefs.appliedFontFamily==m.savedFamily,'Actual Apply and save applies the selected family and dispatches persistence')
        check(not systemFamily or r.fonts[16]~=beforeSelection,'The selected system font replaces the visible interface font')
    end
    S.Update(dt);Settings.build(v,Layout.dimensions())
    if frame>20 then print('FONTS COMPLETE '..checks..' checks');love.event.quit(0)end
end
function love.draw()
    love.graphics.clear(.026,.036,.060,1);S.Draw()
    for i,name in ipairs({'player','bot','players','focus','pan','overview','commander','life'})do r.assets:iconSymbol(name,45+(i-1)*44,665,30)end
    if frame==18 then love.graphics.captureScreenshot(function(data)local file=assert(io.open('/tmp/love2gathering-fonts-icons.png','wb'));file:write(data:encode('png'):getString());file:close()end)end
end
function love.quit()S.OnQuit()end
