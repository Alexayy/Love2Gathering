local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Assets=require('app.assets');local Fonts=require('app.fonts');local Layout=require('app.layout');local Theme=require('app.theme');local json=require('lib.json')
local m,r,v,p,runner,Cursor,Region,DC,Tooltip
local clock,wake,frame=0,0,0;local scene='samples';local checks,shots,completed={},{},{};local controls,buttons,labels={},{},{}
local mouse={x=3,y=3};local down=false;local input='Friends table';local chosen='Commander';local enabled=false;local stored
local tip='Hover details are readable, centered, and stay outside the control. Čarobna šuma.'
local colorMesh
local coverTooltip=false
local function check(ok,text)assert(ok,text);checks[#checks+1]=text;print('GLOBAL CONTROLS PASS '..text)end
local function wait(s)wake=clock+(s or .08);coroutine.yield()end
local function move(box)local x,y=box.x+box.w/2,box.y+box.h/2;local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy);r:mousemoved(x,y)end
local function click(box)assert(box,'Missing actual UI control');move(box);wait(.06);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.06);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.16)end
local function shot(name)shots[#shots+1]=name;wait(.15)end
local function mode(w,h,scale,desktop)
 m.settings.resolution=desktop and'Desktop'or(w..'x'..h);m.settings.windowMode=desktop and'Borderless'or'Windowed';m.settings.uiScale=scale;m.settings.renderScale=1;m.settings.vsync=false;p:apply(true);wait(.2)
end
local function centered(label,key)
 local box=assert(controls[key]or buttons[key],key);local record=assert(labels[label],'Missing actual text command '..label);local expected=box.y+(box.h-record.font:getHeight())/2+Fonts.textOffset(record.font,label)
 check(math.abs(record.y-expected)<=1.1,'Actual '..key..' text command is vertically centered at UI scale '..Layout.scale)
 check(record.font==Fonts.font(16),'Actual '..key..' label uses Beleren after nested heading font changes')
end
local function hoverLayout(label)
 local ids={'setting-opponentColor','setting-builderLayout','setting-skybox'}
 move({x=4,y=4,w=1,h=1});wait(.3)
 local before={}
 for _,id in ipairs(ids)do local b=assert(controls[id],id);before[id]={x=b.x,y=b.y,w=b.w,h=b.h}end
 local function unchanged(phase)
  for _,id in ipairs(ids)do
   local b=assert(controls[id],id);local a=before[id]
   for _,key in ipairs({'x','y','w','h'})do
    check(math.abs(a[key]-b[key])<.01,label..' '..id..' '..key..' stays fixed '..phase..' ('..a[key]..'/'..b[key]..')')
   end
  end
 end
 shot('hover-layout-'..label..'-before')
 move(controls['setting-accentColor']);wait(.15);unchanged('before tooltip delay')
 wait(1.0)
 local bounds=Tooltip.GetBounds()
 check(bounds and bounds.text:find('Optional #RRGGBB',1,true),'Actual Settings input tooltip is visible in '..label)
 shot('hover-layout-'..label..'-visible');unchanged('with tooltip visible')
 move({x=4,y=4,w=1,h=1});wait(.3)
 shot('hover-layout-'..label..'-after');unchanged('after mouseleave')
end
local function dropdownLayout()
 v.settingsTab='Graphics';move({x=4,y=4,w=1,h=1});wait(.3)
 local ids={'setting-msaa','setting-fontQuality','setting-renderScale'};local before={}
 for _,id in ipairs(ids)do local b=assert(controls[id],id);before[id]={x=b.x,y=b.y,w=b.w,h=b.h}end
 local function unchanged(phase)
  for _,id in ipairs(ids)do for _,key in ipairs({'x','y','w','h'})do
   local a,b=before[id][key],assert(controls[id],id)[key]
   check(math.abs(a-b)<.01,'Graphics '..id..' '..key..' stays fixed '..phase..' ('..a..'/'..b..')')
  end end
 end
 local selected=m.settings.windowMode
 click(controls['setting-windowMode']);check(buttons[selected],'Actual Window mode dropdown is open')
 unchanged('with dropdown open');shot('graphics-dropdown-stable')
 click(buttons[selected]);unchanged('after dropdown selection')
 v.settingsTab='Presentation';move({x=4,y=4,w=1,h=1});wait(.2)
end
local function samples()
 v:window('control-proof',28,150,620,650,'Controls and typography')
 S.PushFont(r.assets:titleFont(22,m.settings));S.Text('Beleren controls');S.PopFont();S.NewLine()
 S.Text('Room name');if S.Input('input-proof',{Text=input,W=430,H=42,Align='left',Tooltip='Enter a room name'})then input=S.GetInputText()end
 S.NewLine();S.Text('Game format')
 if S.BeginComboBox('combo-proof',{Selected=chosen,W=430,H=42,Tooltip='Choose a supported format'})then for _,name in ipairs({'Commander','Modern','Pioneer'})do if S.TextSelectable(name)then chosen=name end end;S.EndComboBox()end
 S.NewLine();S.Text('Default-height dropdown')
 if S.BeginComboBox('combo-default',{Selected='Default height',W=430})then S.Text('Default sizing');S.EndComboBox()end
 S.NewLine()
 S.Button('Refresh recordings',{W=430,H=44,Tooltip=tip})
 S.NewLine();S.Button('Image label',{W=430,H=44,Image={Image=r.assets:buttonImage('replay','Refresh recordings',430,44,{font=r.fonts[16]})},Tooltip='Actual supplied icon and Beleren label'})
 S.NewLine();if S.CheckBox(enabled,'Automatic focus',{Size=22})then enabled=not enabled end
 S.NewLine();S.BeginListBox('nested-tip-region',{W=460,H=94});S.Text('A scrolling parent must not clip its tooltip.');S.Button('Nested tooltip',{W=430,H=38,Tooltip='Nested tooltip escapes its parent scissor and remains readable.'});S.EndListBox();S.EndWindow()
end
local function scenario()
 wait(.2)
 -- Select the real ultrawide monitor for the desktop-default proof without
 -- changing the desktop mode or any other process.
 local _,_,display=love.window.getPosition();display=display or 1
 for i=1,love.window.getDisplayCount()do local w,h=love.window.getDesktopDimensions(i);if w==2560 and h==1080 then display=i end end
 local dw,dh=love.window.getDesktopDimensions(display);love.window.setMode(dw,dh,{fullscreen=true,fullscreentype='desktop',display=display,vsync=0})
 m.settings.resolution='Desktop';m.settings.windowMode='Borderless';p:apply(true);wait(.2)
 local w,h,flags=love.window.getMode();check(flags.fullscreen and flags.fullscreentype=='desktop'and w==dw and h==dh,'Desktop Borderless uses the actual full native display dimensions')
 check(m.settings.fontFamily=='Beleren'and m.settings.titleFontFamily=='Beleren'and m.settings.cursorStyle=='Kenney','Beleren and dynamic Kenney pointers are the actual new presentation defaults')
 mode(2560,1080,1.25,true)
 centered('Friends table','input-proof');centered('Commander','combo-proof');centered('Refresh recordings','Refresh recordings')
 check(controls['combo-default'].h>=32,'Natural dropdown height has real vertical padding')
 check(S.GetStyle().Font==Fonts.font(16),'Header PopFont leaves the actual body font unchanged')
 move(buttons['Refresh recordings']);wait(1.1)
 local box=Tooltip.GetBounds();check(box and box.text==tip and box.w>120 and box.h>=30,'Actual30FPS hover produces a measured readable tooltip instead of a zero-size dot')
 check(box.x>=0 and box.y>=0 and box.x+box.w<=select(1,Layout.dimensions())and box.y+box.h<=select(2,Layout.dimensions()),'Actual tooltip stays inside the scaled logical viewport')
 shot('2560-scaled-tooltip')
 coverTooltip=true;wait(.9);shot('2560-overlapping-tooltip');coverTooltip=false;wait(.1)
 move(buttons['Nested tooltip']);wait(1.05);box=Tooltip.GetBounds();check(box and box.text:find('Nested tooltip',1,true)and box.w>200,'Tooltip inside a real scrolling region retains its full measured geometry');shot('2560-nested-tooltip')
 move(controls['input-proof']);wait(.1);p:endFrame();check(p.cursorType=='ibeam'and love.mouse.getCursor():getType()=='image','Text editing uses the supplied I-beam without switching to a system cursor')
 move(buttons['Refresh recordings']);wait(.1);p:endFrame();check(p.cursorType=='hand'and p.customCursorActive,'Clickable Slab controls select the supplied pointing-hand cursor')
 r.uiHovered=false;r.assets:setInteractionCursor('pan');p:endFrame();check(p.cursorType=='pan'and p.customCursorActive,'Board panning selects the supplied open-hand cursor')
 r.assets:setInteractionCursor('drag');p:endFrame();check(p.cursorType=='drag'and p.customCursorActive,'Dragging selects the supplied closed-hand cursor');r.assets:setInteractionCursor(nil)
 local opacity=Assets.rasterize(200,100,function()r.assets:panel(0,0,200,100,'dark')end):newImageData();local _,_,_,alpha=opacity:getPixel(100,50)
 check(math.abs(alpha-.65)<.02,'Actual panel pixels use the requested65percent opacity')
 m.settings.panelOpacity=.25;local faint=Assets.rasterize(200,100,function()r.assets:panel(0,0,200,100,'dark')end):newImageData();local _,_,_,a=faint:getPixel(100,50);check(math.abs(a-.25)<.02,'Changing opacity changes actual custom-panel alpha');m.settings.panelOpacity=.65
 local seen={};for _,name in ipairs(Theme.names)do m.settings.theme=name;p:update();local data=Assets.rasterize(200,100,function()r.assets:control(0,0,200,100,'accent')end):newImageData();local rr,gg,bb=data:getPixel(100,50);seen[string.format('%.2f,%.2f,%.2f',rr,gg,bb)]=true end
 local count=0;for _ in pairs(seen)do count=count+1 end;check(count==5,'All five theme presets change actual control pixels')
 m.settings.theme='Midnight';m.settings.accentColor='#E65C38';m.settings.opponentColor='#50A0ED';p:update()
 local c=Assets.palette(m.settings);check(math.abs(c.accent[1]-230/255)<.001 and math.abs(c.purple[3]-237/255)<.001,'Custom accent colors affect both actual renderer palette roles')
 check(math.abs(S.GetStyle().CheckBoxSelectedColor[1]-c.accent[1])<.001,'Slab colors stay synchronized with the selected custom accent')
 shot('custom-theme-controls')
 m.settings.accentColor='';m.settings.opponentColor='';m.settings.theme='Midnight';p:update()
 mode(1120,720,.85);centered('Friends table','input-proof');centered('Commander','combo-proof');centered('Refresh recordings','Refresh recordings');move(buttons['Refresh recordings']);wait(1.05);shot('1120-scaled-tooltip')
 scene='settings';m:openSettings();v.settingsTab='Presentation';wait(.2)
 check(m.page=='settings'and not m.settingsOpen,'Actual Settings routing opens a full page outside a match')
 check(buttons['Apply and save'].y+buttons['Apply and save'].h<=select(2,Layout.dimensions()),'Full-page settings save remains above the viewport bottom');shot('settings-1120-scaled')
 dropdownLayout()
 hoverLayout('page-scaled')
 mode(2560,1080,1,true);wait(.2);shot('settings-2560')
 hoverLayout('page-native')
 click(controls['setting-theme']);wait(.1);click(buttons.Ember);check(m.settings.theme=='Ember','Actual nested theme dropdown changes the chosen palette')
 click(buttons['Choose your accent']);wait(.3);check(v.themeColorEdit~=nil,'Actual accent button opens the native Slab color picker')
 local Window=require('lib.Slab.Internal.UI.Window');local picker=Window.GetDebugInfo and nil
 local before=buttons.OK;wait(.55);check(buttons.OK and before and math.abs(before.x-buttons.OK.x)<1 and math.abs(before.y-buttons.OK.y)<1,'Auto-sized native ColorPicker reaches stable usable geometry');shot('color-picker')
 click(buttons.Cancel);check(not v.themeColorEdit,'Color picker cancel preserves the selected colors')
 click(buttons['Choose your accent']);wait(.2);check(colorMesh,'Actual RGB color field is rendered')
 click({x=colorMesh.x+45,y=colorMesh.y+125,w=8,h=8});click(buttons.OK)
 check(not v.themeColorEdit and m.settings.accentColor:match('^#%x%x%x%x%x%x$'),'Actual color-field selection stores a valid chosen accent')
 check(m.settings.accentColor~='#FFA652','Actual chosen accent changes the rendered preset color')
 click(buttons['Apply and save']);check(stored and stored.theme=='Ember','Actual Settings Apply dispatches the selected presentation settings after closing ColorPicker')
 m:openSettings();v.settingsTab='Accessibility';wait(.15);shot('accessibility-2560')
 check(S.GetStyle().Font==Fonts.font(16),'Actual full settings page retains Beleren body text after every section')
 m.game={gameId='POPUP-UI-FIXTURE',running=true,format='Modern',turn=1,step='PRECOMBAT_MAIN',phase='PRECOMBAT_MAIN',players={{id='human',name='You',human=true,life=20,hand={},battlefield={},graveyard={},exile={},command={},libraryCount=60},{id='bot',name='Bot',human=false,life=20,hand={},battlefield={},graveyard={},exile={},command={},libraryCount=60}}}
 m.page='table';m.settingsOpen=true;v.settingsTab='Game';wait(.2);check(m.page=='table'and m.settingsOpen and buttons['Apply and save'],'Actual Settings routing retains a popup above the current match');shot('settings-table-popup')
 v.settingsTab='Presentation';wait(.2);hoverLayout('match-popup');m.game=nil
 local f=assert(io.open('/tmp/love2gathering-global-controls-ui-report.json','w'));f:write(json.encode({passed=true,checks=checks,captures=completed,physical={love.graphics.getDimensions()},logical={Layout.dimensions()},scope='Actual Model/Renderer/View/Preferences/Slab, native desktop mode/cursors and measured rendering; storage callback intercepted, no service or native-game calls'}));f:close();print('GLOBAL CONTROLS COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.errorhandler(message)io.stderr:write('GLOBAL CONTROLS FAILED '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region');DC=require('lib.Slab.Internal.Core.DrawCommands');Tooltip=require('lib.Slab.Internal.UI.Tooltip')
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(b)return b==1 and down end
 m=Model.new();check(m.settings.resolution=='Desktop'and m.settings.windowMode=='Borderless'and m.settings.cursorStyle=='Kenney','Actual Model constructor mirrors the new display and cursor defaults')
 m.page='decks';m.loaded=true;m.settingsLoaded=true;m.catalogHealth={ready=false};m.engineHealth={};m.settings.sfxEnabled=false;m.settings.animations=false;m.settings.particles=false
 m.saveSettings=function(self)stored=json.decode(json.encode(self.settings))end
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p
 local function bounds()local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();return{x=x+dx,y=y+dy,w=w,h=h}end
 for _,name in ipairs({'Button','Input','BeginComboBox','TextSelectable'})do local original=S[name];S[name]=function(id,options)local result=original(id,options);local t=name=='Button'or name=='TextSelectable';(t and buttons or controls)[id]=bounds();return result end end
 local Button=require('lib.Slab.Internal.UI.Button');local begin=Button.Begin;Button.Begin=function(label,options)local result=begin(label,options);if label=='Cancel'or label=='OK'then buttons[label]=bounds()end;return result end
 local print=DC.Print;DC.Print=function(text,x,y,color,font,...)labels[tostring(text)]={x=x,y=y,font=font or S.GetStyle().Font};return print(text,x,y,color,font,...)end
 local mesh=DC.Mesh;DC.Mesh=function(value,x,y,...)if require('lib.Slab.Internal.UI.Window').GetId()=='ColorPicker'and not colorMesh then colorMesh={x=x,y=y}end;return mesh(value,x,y,...)end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;frame=frame+1;assert(clock<90,'Global controls acceptance timed out')
 p:update();m.api:update();S.Update(dt);r:update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 controls={};buttons={};labels={}
 if scene=='samples'then samples()else v:build()end
 if coverTooltip then
  local b=assert(Tooltip.GetBounds())
  S.BeginWindow('tooltip-cover-proof',{X=b.x-4,Y=b.y-4,W=b.w+8,H=b.h+8,Border=0,Layer='Dialog',BgColor={.7,.025,.025,1},AutoSizeWindow=false,AutoSizeContent=false,AllowMove=false,AllowResize=false,AllowFocus=false,CanObstruct=false,NoSavedSettings=true})
  S.EndWindow()
 end
 r.uiHovered=not S.IsVoidHovered()
end
function love.draw()
 p:beginFrame();r:draw();p:endScene();S.Draw({DeferOverlays=true})
 if coverTooltip then
  local b=assert(Tooltip.GetBounds());love.graphics.push('all');love.graphics.scale(Layout.scale)
  love.graphics.setColor(.7,.025,.025,1);love.graphics.rectangle('fill',b.x-4,b.y-4,b.w+8,b.h+8);love.graphics.pop()
 end
 S.DrawOverlays();p:endFrame()
 if#shots>0 then local name=table.remove(shots,1);local path='/tmp/love2gathering-global-'..name..'.png';completed[#completed+1]=path
  local tipBox=Tooltip.GetBounds();local inputBox=controls['input-proof'];local refreshBox=buttons['Refresh recordings'];local scale=Layout.scale
  love.graphics.captureScreenshot(function(data)
   local f=assert(io.open(path,'wb'));f:write(data:encode('png'):getString());f:close()
   if name:find('tooltip',1,true)then
    local n=0;local scale=Layout.scale;for y=math.max(0,math.floor((tipBox.y+4)*scale)),math.min(data:getHeight()-1,math.floor((tipBox.y+tipBox.h-4)*scale))do for x=math.max(0,math.floor((tipBox.x+5)*scale)),math.min(data:getWidth()-1,math.floor((tipBox.x+tipBox.w-5)*scale))do local rr,gg,bb=data:getPixel(x,y);if rr>.65 and gg>.65 and bb>.65 then n=n+1 end end end
    check(n>25,'Actual '..name..' capture contains readable tooltip glyph pixels')
    for key,box in pairs({input=inputBox,button=refreshBox})do
     if box then
      local minY,maxY=math.huge,-math.huge
      for y=math.ceil((box.y+2)*scale),math.floor((box.y+box.h-2)*scale)do for x=math.ceil((box.x+8)*scale),math.floor((box.x+box.w-8)*scale)do
       local rr,gg,bb=data:getPixel(x,y);if rr>.65 and gg>.65 and bb>.65 then minY=math.min(minY,y);maxY=math.max(maxY,y)end
      end end
      local top=minY-box.y*scale;local bottom=(box.y+box.h)*scale-maxY-1
      check(top>3 and bottom>3 and math.abs(top-bottom)<=5*scale,'Actual '..key..' ink has balanced vertical breathing room in '..name..' ('..string.format('%.1f/%.1f',top,bottom)..')')
     end
    end
   end
  end)
 end
 love.timer.sleep(.034)
end
function love.quit()m.game=nil;m.uiLayoutTimer=nil;m.api:quit();p:quit();S.OnQuit()end
