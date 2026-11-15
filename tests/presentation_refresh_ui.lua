-- Actual LÖVE/Slab controls and supplied assets in isolated memory-only state.
-- No game engine, catalog, user saves, network requests or real clipboard edits remain.
local json=require('lib.json')
local requests={}
package.preload['app.api']=function()return{escape=function(x)return tostring(x)end,new=function()return{request=function(_,service,method,path,body,callback)requests[#requests+1]={service=service,method=method,path=path};if callback then callback(nil,'Isolated presentation fixture',503)end end,update=function()end,quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Assets=require('app.assets');local Fonts=require('app.fonts');local Layout=require('app.layout')
local m,r,v,p,runner,Cursor,Region,Mouse
local sliderLabelCommands=0;local footerClicks=0;local hiddenText='Hidden text';local hiddenChoice='Choose an item';local hiddenDropdownOpen=false
local clock,wake=0,0;local scene='samples';local mouse={x=2,y=2};local held={};local down=false
local checks,shots,captures,geometry={},{},{},{};local controls,buttons,regions={},{},{}
local input='Čarobna šuma';local slider=.5;local clipboard;local saved;local proofs={};local cursorCalls,cursorBuilds={},{};local monitor=false;local cursorFrames=0
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('PRESENTATION REFRESH PASS '..label)end
local function wait(t)wake=clock+(t or .08);coroutine.yield()end
local function ready(fn,label)for _=1,180 do if fn()then return end;wait(.05)end;error('Timed out: '..label)end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy);r:mousemoved(x,y)end
local function hover(box)assert(box,'Missing actual control');move(box.x+box.w/2,box.y+box.h/2)end
local function press(clicks)down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,clicks or 1)end
local function release()down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1)end
local function click(box,clicks)hover(box);wait(.05);press(clicks);wait(.06);release();wait(.12)end
local function key(name,mods)mods=mods or{};for _,value in ipairs(mods)do held[value]=true end;S.OnKeyPressed(name,name,false);wait(.04);S.OnKeyReleased(name,name);for _,value in ipairs(mods)do held[value]=nil end;wait(.05)end
local function text(value)S.OnTextInput(value);wait(.08)end
local function shot(name)move(2,2);wait(.06);shots[#shots+1]=name;wait(.12)end
local function mode(w,h,scale)
 m.settings.resolution=w..'x'..h;m.settings.windowMode='Windowed';m.settings.uiScale=scale or 1;m.settings.vsync=false;m.settings.renderScale=1;p:apply(true);wait(.2)
 geometry[#geometry+1]={requested={w,h},physical={love.graphics.getDimensions()},logical={Layout.dimensions()},uiScale=Layout.scale}
end
local function drag(box,from,to)
 move(box.x+box.w*from,box.y+box.h/2);wait(.06);press();wait(.06)
 for i=1,8 do move(box.x+box.w*(from+(to-from)*i/8),box.y+box.h/2);wait(.025)end
 release();wait(.1)
end
local function showSamples()
 local w,h=Layout.dimensions();local width=math.min(620,w-60)
 v:window('refresh-controls',28,124,width,math.min(550,h-160),'Typography, pointer and sliders')
 S.Text('Čarobna šuma · Beleren',{Color=r.colors.accent});S.NewLine()
 S.Text('Editable UTF-8 text')
 if S.Input('refresh-text',{Text=input,W=width-34,H=42,Align='left',Tooltip='Text editing keeps the supplied pointer throughout hover and selection'})then input=S.GetInputText()end
 S.NewLine();S.Button('Refresh asset proof',{W=width-34,H=40,Tooltip='A clickable control uses the Kenney hand'})
 S.NewLine();S.Text('Native Slab slider, Kenney track and thumb')
 if S.InputNumberSlider('refresh-slider',slider,0,1,{W=width-34,H=40,Step=.05,Precision=2,Tooltip='Drag to either end or double-click to type a number'})then slider=S.GetInputNumber()end
 S.NewLine();S.Text('Font quality: '..tostring(m.settings.fontQuality)..' · pointer scale '..tostring(m.settings.cursorScale))
 S.NewLine();S.Textf('The input and slider use actual Slab input. Card backs and transparent masks use the supplied Kenney artwork.',{W=width-34,Color=r.colors.muted})
 S.EndWindow()
 if w>=1400 and proofs.Arcane then
  v:window('refresh-asset-proof',width+64,124,math.min(820,w-width-100),550,'Licensed card backs and masks')
  for i,style in ipairs({'Arcane','Azure','Verdant','Crimson'})do
   if i>1 then S.SameLine({Pad=12})end
   S.Image('back-'..style,{Image=proofs[style],W=120,H=168})
  end
  S.NewLine();S.Text('Gradient · Noise · Spotlight',{Color=r.colors.accent});S.NewLine()
  for i,name in ipairs({'gradient','noise','spotlight'})do if i>1 then S.SameLine({Pad=12})end;S.Image('mask-'..name,{Image=proofs[name],W=150,H=110})end
  S.EndWindow()
 end
end
local function showClipped()
 v:window('clip-proof',28,124,620,420,'Ancestor clipping and popup input')
 S.Text('A clipped input and dropdown cannot capture the footer click.')
 S.NewLine();local _,top=S.GetCursorPos({Absolute=true})
 S.BeginListBox('clip-proof-list',{W=580,H=100})
 S.Text('Scroll this region to reach the controls below.')
 local left=S.GetCursorPos({Absolute=true})
 S.SetCursorPos(left,top+116,{Absolute=true})
 if S.Input('clip-hidden-text',{Text=hiddenText,W=330,H=38,Align='left'})then hiddenText=S.GetInputText()end
 S.SetCursorPos(left,top+116,{Absolute=true})
 hiddenDropdownOpen=false
 if S.BeginComboBox('clip-hidden-choice',{Selected=hiddenChoice,W=330,H=38})then
  hiddenDropdownOpen=true
  if S.TextSelectable('Visible popup item')then hiddenChoice='Visible popup item'end
  S.EndComboBox()
 end
 S.EndListBox();S.NewLine()
 if S.Button('Visible footer action',{W=330,H=42})then footerClicks=footerClicks+1 end
 S.EndWindow()
end
local function visible(box)
 local region=regions['settings-content'];return box and region and box.y>=region.y+2 and box.y+box.h<=region.y+region.h-2
end
local function scrollTo(id,up)
 for _=1,36 do
  local box=controls[id]or buttons[id];if visible(box)then return box end
  local region=assert(regions['settings-content'],'Settings scroll region missing');move(region.x+region.w*.85,region.y+region.h*.5);S.OnWheelMoved(0,up and 5 or-5);wait(.08)
 end
 error('Settings control unreachable: '..id)
end
local function settingsGeometry(label)
 local w,h=Layout.dimensions();local footer=assert(buttons['Apply and save']);local region=assert(regions['settings-content'])
 check(footer.x>=12 and footer.y+footer.h<=h-10,'Settings footer keeps bottom padding in '..label)
 check(region.x>=20 and region.x+region.w<=w-16 and region.y+region.h<footer.y-6,'Settings body and footer have separate margins in '..label)
 if controls['setting-resolution']and controls['setting-windowMode']and visible(controls['setting-resolution'])and visible(controls['setting-windowMode'])then
  local a,b=controls['setting-resolution'],controls['setting-windowMode'];check(b.y-(a.y+a.h)>=12,'Graphics rows retain space for captions and padding in '..label)
 end
end
local function visualProofs()
 local seen={}
 for _,style in ipairs({'Arcane','Azure','Verdant','Crimson'})do
  local did=false;proofs[style]=Assets.rasterize(120,168,function()did=r.assets:cardBack(0,0,120,168,style)end)
  check(did,'Supplied '..style..' card-back artwork renders')
  local data=proofs[style]:newImageData();local sum={0,0,0};local alpha=0
  for y=25,143,13 do for x=20,100,10 do local a,b,c,d=data:getPixel(x,y);sum[1]=sum[1]+a;sum[2]=sum[2]+b;sum[3]=sum[3]+c;alpha=alpha+d end end
  check(alpha>30,'The '..style..' card back has visible artwork pixels')
  seen[string.format('%.1f/%.1f/%.1f',sum[1],sum[2],sum[3])]=true
 end
 local count=0;for _ in pairs(seen)do count=count+1 end;check(count==4,'All four card-back choices produce distinct actual pixels')
 for _,name in ipairs({'gradient','noise','spotlight'})do
  local did=false;proofs[name]=Assets.rasterize(150,110,function()did=r.assets:surface(name,0,0,150,110,{.25,.75,.5,.6},name=='noise')end)
  check(did,'Supplied '..name..' surface renders with its mask')
  local data=proofs[name]:newImageData();local minimum,maximum=1,0;local checked=0;local tintOK=true
  for y=5,104,7 do for x=5,144,7 do local a,b,c,d=data:getPixel(x,y);minimum=math.min(minimum,d);maximum=math.max(maximum,d);if d>.15 then checked=checked+1;if math.abs(a-.25)>.035 or math.abs(b-.75)>.035 or math.abs(c-.5)>.035 then tintOK=false end end end end
  check(maximum>minimum+.03 and maximum<=.63,'Actual '..name..' alpha varies without an opaque background')
  if not tintOK then local a,b,c,d=data:getPixel(75,55);io.stderr:write('MASK PIXELS '..name..' '..tostring(a)..' '..tostring(b)..' '..tostring(c)..' '..tostring(d)..'\n')end
  check(checked>10 and tintOK,'Actual '..name..' pixels retain tint without black rectangles')
 end
 local shader=love.graphics.newShader('vec4 effect(vec4 c, Image t, vec2 u, vec2 p){return Texel(t,u)*c;}')
 love.graphics.push('all');love.graphics.setColor(.2,.3,.4,.5);love.graphics.setShader(shader);love.graphics.setScissor(3,5,19,23);love.graphics.setLineWidth(3)
 r.assets:surface('spotlight',10,10,70,50,{.2,.7,.4,.5});r.assets:cardBack(10,10,60,84,'Arcane')
 local a,b,c,d=love.graphics.getColor();local x,y,w,h=love.graphics.getScissor()
 check(math.abs(a-.2)<.001 and math.abs(d-.5)<.001 and love.graphics.getShader()==shader and x==3 and y==5 and w==19 and h==23 and love.graphics.getLineWidth()==3,'Surface and card-back helpers preserve color shader scissor and line state')
 love.graphics.pop();shader:release()
 local manifest=require('assets.kenney.runtime.manifest');local names={}
 for name in pairs(manifest.sounds or{})do names[#names+1]=name end;table.sort(names)
 for _,name in ipairs(names)do local data=love.sound.newSoundData(manifest.sounds[name].path);check(data:getDuration()>0 and data:getSampleCount()>0,'Curated '..name..' sound decodes from its licensed source');data:release()end
 check(#names>=5,'Runtime sound selection contains the actual interface and game roles')
end
local function scenario()
 wait(.2);mode(2560,1080,1)
 check(m.settings.fontQuality=='High'and m.settings.cursorScale==.55,'High-quality text and smaller pointer are the applied defaults')
 visualProofs();wait(.2)
 m.settings.fontQuality='Standard';p:applyFont();local standard=r.fonts[16];local width=standard:getWidth('Čarobna šuma');local height=standard:getHeight();local dpi=standard:getDPIScale()
 m.settings.fontQuality='High';p:applyFont();wait(.1);local high=r.fonts[16]
 check(high~=standard and high:getDPIScale()>=dpi*1.9,'High quality rebuilds real font atlases at twice the raster density')
 check(math.abs(high:getHeight()-height)<=1 and math.abs(high:getWidth('Čarobna šuma')-width)<=math.max(2,width*.05),'Font raster quality preserves logical text and caret metrics (Standard '..height..'/'..width..', High '..high:getHeight()..'/'..high:getWidth('Čarobna šuma')..')')
 check(S.GetStyle().Font==high,'Slab uses the actual rebuilt high-quality Beleren font')
 wait(.1);check(sliderLabelCommands==0,'Skinned idle slider omits the numeric caption beneath its thumb')
 hover(buttons['Refresh asset proof']);wait(.15);p:endFrame();check(p.cursorType=='hand'and love.mouse.getCursor():getType()=='image','Clickable controls use a custom hardware hand cursor')
 cursorCalls={};monitor=true;hover(controls['refresh-text']);wait(.2);check(p.cursorType=='ibeam'and love.mouse.getCursor():getType()=='image','Textbox hover uses the curated custom I-beam')
 click(controls['refresh-text']);key('a',{'lctrl'});text('Čarobna šuma Ž');check(input=='Čarobna šuma Ž','High-density text input preserves UTF-8 typing')
 key('a',{'lctrl'});key('c',{'lctrl'});check(love.system.getClipboardText()=='Čarobna šuma Ž','Actual Ctrl+A/C copies complete UTF-8 text ('..json.encode(love.system.getClipboardText())..')')
 key('x',{'lctrl'});check(input=='','Actual cut removes the selected UTF-8 text')
 key('v',{'lctrl'});check(input=='Čarobna šuma Ž','Actual paste restores UTF-8 content with the custom pointer')
 local box=controls['refresh-text'];drag(box,.82,.10);key('c',{'lctrl'});local selected=love.system.getClipboardText();check(#selected>0 and require('utf8').len(selected)~=nil,'Actual mouse-drag selection copies valid UTF-8 text');shot('text-selection-2560')
 hover(buttons['Refresh asset proof']);wait(.12);hover(controls['refresh-text']);wait(.12);hover(buttons['Refresh asset proof']);wait(.12)
 monitor=false;local native=0;for _,call in ipairs(cursorCalls)do if call.kind~='image'then native=native+1 end end
 check(cursorFrames>=12 and#cursorCalls>0 and native==0,'Hover focus and drag selection never temporarily install a system cursor')
 local small=0;for _,build in ipairs(cursorBuilds)do if build.width<=40 and build.height<=40 then small=small+1 end end
 check(small>=3,'Default pointer scale builds smaller arrow hand and I-beam images')
 m.settings.cursorScale=1;p:applyCursor();hover(controls['refresh-text']);wait(.1);p:endFrame();local larger=false;for _,build in ipairs(cursorBuilds)do if build.width>40 or build.height>40 then larger=true end end;check(larger,'Pointer scale changes actual hardware image dimensions');m.settings.cursorScale=.55
 m.settings.cursorStyle='System';p:applyCursor();wait(.12);check(love.mouse.getCursor():getType()=='ibeam','Explicit System mode retains the native text cursor');m.settings.cursorStyle='Kenney';p:applyCursor()
 drag(controls['refresh-slider'],.5,-.1);check(slider<=.001,'Native skinned slider reaches its zero endpoint')
 drag(controls['refresh-slider'],.1,1.1);check(slider>=.999,'Native skinned slider reaches its full endpoint')
 click(controls['refresh-slider'],2);key('a',{'lctrl'});text('0.35');key('return');check(math.abs(slider-.35)<.001,'Double-click editing retains typed numeric slider values')
 check((r.assets.surfaces.stats.slider or 0)>0,'Actual native slider is painted by the Kenney track and thumb hook')
 shot('samples-2560')
 scene='clipped';wait(.15);local footer=assert(buttons['Visible footer action']);local hidden=assert(controls['clip-hidden-choice']);check(footer.y+footer.h/2>hidden.y and footer.y+footer.h/2<hidden.y+hidden.h,'Fixture places an offscreen child exactly behind the visible footer')
 click(footer);check(footerClicks==1 and not hiddenDropdownOpen and not S.IsInputFocused('clip-hidden-text'),'Clipped input and dropdown cannot intercept a visible footer click');shot('clipped-footer-2560')
 for _=1,8 do local region=assert(regions['clip-proof-list']);move(region.x+region.w*.85,region.y+region.h*.5);S.OnWheelMoved(0,-3);wait(.08)end
 hidden=assert(controls['clip-hidden-choice']);local region=assert(regions['clip-proof-list']);check(hidden.y>=region.y and hidden.y+hidden.h<=region.y+region.h,'Scrolling makes the same nested dropdown fully visible')
 click({x=hidden.x+hidden.w-28,y=hidden.y,w=20,h=hidden.h});wait(.1);check(hiddenDropdownOpen and buttons['Visible popup item'],'The scrolled dropdown opens when its anchor is visible')
 local item=assert(buttons['Visible popup item']);check(item.y+item.h>region.y+region.h,'The popup extends outside its parent scrolling clip')
 click(item);check(hiddenChoice=='Visible popup item','Popup selection uses its own window clip and stays clickable');shot('clipped-popup-2560')
 scene='samples';mode(1120,720,.85);shot('samples-1120')
 scene='settings';m:openSettings();v.settingsTab='Graphics';wait(.2);settingsGeometry('1120 Graphics');shot('settings-graphics-1120')
 local quality=scrollTo('setting-fontQuality');click(quality);wait(.1);click(buttons.Standard);check(m.settings.fontQuality=='Standard','Actual Graphics dropdown selects Standard text quality')
 quality=scrollTo('setting-fontQuality');click(quality);wait(.1);click(buttons.High);check(m.settings.fontQuality=='High','Actual Graphics dropdown selects High text quality')
 mode(2560,1080,1);v.settingsTab='Graphics';wait(.15);settingsGeometry('2560 Graphics');shot('settings-graphics-2560')
 v.settingsTab='Accessibility';wait(.2);local size=scrollTo('setting-cursorScale');check(size.h>=34,'Actual pointer-size slider has padded interaction height');shot('settings-accessibility-2560')
 v.settingsTab='Presentation';wait(.2);local style=scrollTo('setting-cardBackStyle');click(style);wait(.1);click(buttons.Verdant);check(m.settings.cardBackStyle=='Verdant','Actual Settings chooses supplied Verdant card-back artwork')
 click(buttons['Apply and save']);check(saved and saved.fontQuality=='High'and saved.cardBackStyle=='Verdant','Apply saves the actual selected graphics and artwork preferences')
 local file=assert(io.open('/tmp/love2gathering-presentation-refresh-ui-report.json','w'));file:write(json.encode({passed=true,checks=checks,captures=captures,geometry=geometry,cursorCalls=cursorCalls,cursorBuilds=cursorBuilds,cursorFrames=cursorFrames,requests=requests,scope='Actual LÖVE/Slab fonts, hardware cursor calls, UTF-8 editing/clipboard, native slider input, supplied artwork/mask pixels and Settings controls. Memory-only synthetic Model transport; no catalog/native gameplay/user saves.'}));file:close();print('PRESENTATION REFRESH COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.errorhandler(err)if clipboard~=nil then pcall(love.system.setClipboardText,clipboard)end;io.stderr:write('PRESENTATION REFRESH FAILED '..tostring(err)..'\n'..debug.traceback()..'\n');return function()return 1 end end
function love.load()
 clipboard=love.system.getClipboardText();S.SetINIStatePath(nil);S.Initialize({},true)
 Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region');Mouse=require('lib.Slab.Internal.Input.Mouse')
 local DC=require('lib.Slab.Internal.Core.DrawCommands');local print=DC.Print;DC.Print=function(value,...)if require('lib.Slab.Internal.UI.Window').GetId()=='refresh-controls'and tonumber(value)then sliderLabelCommands=sliderLabelCommands+1 end;return print(value,...)end
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down end
 love.keyboard.isDown=function(...)for i=1,select('#',...)do if held[select(i,...)]then return true end end;return false end;love.keyboard.isScancodeDown=love.keyboard.isDown
 local setCursor=love.mouse.setCursor;love.mouse.setCursor=function(cursor)if monitor then cursorCalls[#cursorCalls+1]={frame=clock,kind=cursor and cursor:getType()or'default'}end;return setCursor(cursor)end
 local newCursor=love.mouse.newCursor;love.mouse.newCursor=function(data,x,y)local width,height;if type(data)=='string'then local source=love.image.newImageData(data);width,height=source:getDimensions()else width,height=data:getDimensions()end;cursorBuilds[#cursorBuilds+1]={width=width,height=height,x=x,y=y};return newCursor(data,x,y)end
 m=Model.new();m.loaded=true;m.settingsLoaded=true;m.catalogHealth={ready=false};m.searchTimer=nil;m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.animations=false;m.settings.particles=false;m.settings.reducedMotion=true
 m.saveSettings=function(self)saved=json.decode(json.encode(self.settings))end
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p:apply(true);p.appliedLoaded=true
 local function bounds()local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();return{x=x+dx,y=y+dy,w=w,h=h}end
 for _,name in ipairs({'Input','BeginComboBox','InputNumberSlider'})do local original=S[name];S[name]=function(id,...)local result=original(id,...);controls[id]=bounds();return result end end
 -- Keep separate button/choice capture: both native TextSelectable and Button are clickable.
 for _,name in ipairs({'Button','TextSelectable'})do local original=S[name];S[name]=function(id,...)local result=original(id,...);buttons[id]=bounds();return result end end
 local list=S.BeginListBox;S.BeginListBox=function(id,options)local x,y=S.GetCursorPos({Absolute=true});local dx,dy=Region.Transform(nil,0,0);local result=list(id,options);regions[id]={x=x+dx,y=y+dy,w=options.W,h=options.H};return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<110,'Presentation refresh acceptance timed out');S.OnMouseMoved(mouse.x,mouse.y,0,0);p:update();S.Update(dt);r:update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 controls={};buttons={};regions={};sliderLabelCommands=0;if scene=='samples'then showSamples()elseif scene=='clipped'then showClipped()else v:build()end;r.uiHovered=not S.IsVoidHovered()
end
function love.draw()
 p:beginFrame();r:draw();p:endScene();S.Draw();p:endFrame()
 if monitor then cursorFrames=cursorFrames+1;assert(love.mouse.getCursor():getType()=='image','Custom pointer became a system cursor between rendered frames')end
 if#shots>0 then local name=table.remove(shots,1);local path='/tmp/love2gathering-presentation-refresh-'..name..'.png';captures[#captures+1]=path;local inputBox=controls['refresh-text'];local scale=Layout.scale
  love.graphics.captureScreenshot(function(data)
   if name=='text-selection-2560'and inputBox then
    local minY,maxY=math.huge,-math.huge;local ink,selection=0,0
    for yy=math.ceil((inputBox.y+3)*scale),math.floor((inputBox.y+inputBox.h-3)*scale)do for xx=math.ceil((inputBox.x+6)*scale),math.floor((inputBox.x+inputBox.w-6)*scale)do local rr,gg,bb=data:getPixel(xx,yy);if rr>.65 and gg>.65 and bb>.65 then ink=ink+1;minY=math.min(minY,yy);maxY=math.max(maxY,yy)end;if gg>rr*1.5 and gg>.22 and bb>.18 then selection=selection+1 end end end
    check(ink>20 and minY-inputBox.y*scale>3 and(inputBox.y+inputBox.h)*scale-maxY>3,'High-quality UTF-8 text has actual visible ink and vertical padding')
    check(selection>40,'Actual mouse-drag selection paints a visible bounded highlight')
   end
   local file=assert(io.open(path,'wb'));file:write(data:encode('png'):getString());file:close()end)end
 love.timer.sleep(.018)
end
function love.quit()if clipboard~=nil then love.system.setClipboardText(clipboard)end;m.game=nil;m.uiLayoutTimer=nil;m.api:quit();p:quit();S.OnQuit()end
