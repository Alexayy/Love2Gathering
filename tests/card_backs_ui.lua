-- Real rendering and Slab selection; API saves are captured in memory.
-- SQL persistence is separately covered by test_visual_preferences.py.
local json=require('lib.json')
local saved={}
package.preload['app.api']=function()return{escape=function(s)return tostring(s)end,new=function()return{request=function(_,service,method,path,body,cb)
 if method=='PUT'and path=='/settings'then saved[#saved+1]=json.decode(json.encode(body));cb(body)
 elseif cb then cb(nil,'Isolated card-back fixture',503)end
end,update=function()end,quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Surfaces=require('app.surfaces')
local m,r,v,p,runner,Cursor,Region;local clock,wake=0,0;local mouse={x=2,y=2};local down=false
local controls,regions={},{};local checks,captures,shots,proofs={},{},{},{};local scene='settings'
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('CARD BACK PASS '..label)end
local function wait(t)wake=clock+(t or .08);coroutine.yield()end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy)end
local function click(box)assert(box,'Missing actual control');move(box.x+box.w/2,box.y+box.h/2);wait(.04);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.06);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.12)end
local function visible(box)local a=regions['settings-content'];return box and a and box.y>=a.y and box.y+box.h<=a.y+a.h end
local function scrollTo(id)
 for _=1,65 do
  if visible(controls[id])and(id~='setting-cardBackStyle'or controls[id].y+controls[id].h+180<select(2,Layout.dimensions()))then return controls[id]end
  local a=assert(regions['settings-content']);move(a.x+a.w/2,a.y+a.h/2);S.OnWheelMoved(0,-3);wait(.06)
 end
 error('Could not reveal '..id)
end
local function shot(name)move(2,2);shots[#shots+1]=name;wait(.12)end
local function pixelsSame(a,b)
 local da,db=a:newImageData(),b:newImageData()
 for y=0,279 do for x=0,199 do
  local ar,ag,ab,aa=da:getPixel(x,y);local br,bg,bb,ba=db:getPixel(x,y)
  if math.abs(ar-br)>1/255 or math.abs(ag-bg)>1/255 or math.abs(ab-bb)>1/255 or math.abs(aa-ba)>1/255 then return false end
 end end
 return true
end
local function scenario()
 wait(.2);check(#Surfaces.cardBackNames==6,'Both supplied backs extend the four existing styles')
 for _,style in ipairs({'Classic Magic','Mystic Eye'})do
  local spec=Surfaces.cardBackSpec(style);local original=assert(r.assets.surfaces:load(spec))
  local canvas=love.graphics.newCanvas(200,280);local expected=love.graphics.newCanvas(200,280)
  love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear(0,0,0,0);love.graphics.setColor(.2,.3,.4,.5)
  check(r.assets:cardBack(0,0,200,280,style),'Actual renderer draws '..style)
  local red,green,blue,alpha=love.graphics.getColor();check(math.abs(red-.2)<.001 and math.abs(alpha-.5)<.001,'Rendering restores graphics state for '..style)
  love.graphics.setCanvas(expected);love.graphics.clear(0,0,0,0);love.graphics.setColor(1,1,1,1)
  local scale=math.min(200/original:getWidth(),280/original:getHeight());love.graphics.draw(original,(200-original:getWidth()*scale)/2,(280-original:getHeight()*scale)/2,0,scale,scale)
  love.graphics.setCanvas();love.graphics.pop()
  check(pixelsSame(canvas,expected),'Complete upright artwork retains original colors without tint or overlays: '..style)
  proofs[style]=canvas
  m:openSettings();v.settingsTab='Presentation';wait(.2)
  click(scrollTo('setting-cardBackStyle'));check(controls[style]~=nil,'Actual Settings dropdown offers '..style)
  click(controls[style]);check(m.settings.cardBackStyle==style,'Actual Settings selects '..style)
  check(controls['card-back-preview']and controls['card-back-preview'].w<=70 and controls['card-back-preview'].h<=95,'Settings preview fits its bounded area: '..style)
  scrollTo('card-back-preview');check(visible(controls['card-back-preview']),'The complete Settings preview remains reachable: '..style)
  shot(style=='Classic Magic'and'classic-settings'or'eye-settings')
  click(controls['Apply and save']);check(saved[#saved]and saved[#saved].cardBackStyle==style,'Apply sends the selected '..style..' preference')
 end
 scene='proofs';wait(.15);shot('supplied-backs')
 local f=assert(io.open('/tmp/love2gathering-card-backs-ui-report.json','w'));f:write(json.encode({passed=true,checks=checks,captures=captures,scope='Actual LÖVE image decoding/pixel equality, aspect fit, graphics-state restoration and real Settings dropdown/Apply dispatch. Saves captured in memory; real temporary SQLite persistence is a separate backend test. No user-data or engine changes.'}));f:close();print('CARD BACK UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.errorhandler(e)io.stderr:write('CARD BACK UI FAILED '..tostring(e)..'\n'..debug.traceback()..'\n');return function()return 1 end end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down end
 m=Model.new();m.settings.resolution='1600x900';m.settings.windowMode='Windowed';m.settings.vsync=false;m.settings.sfxEnabled=false;m.settings.musicEnabled=false
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p:apply(true)
 local function box()local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();return{x=x+dx,y=y+dy,w=w,h=h}end
 for _,name in ipairs({'Button','BeginComboBox','TextSelectable','Image'})do local original=S[name];S[name]=function(label,options)local result=original(label,options);controls[label]=box();return result end end
 local list=S.BeginListBox;S.BeginListBox=function(id,options)local x,y=S.GetCursorPos({Absolute=true});local dx,dy=Region.Transform(nil,0,0);local result=list(id,options);regions[id]={x=x+dx,y=y+dy,w=options.W,h=options.H};return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<40,'Card-back UI timed out');S.Update(dt);r:update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 controls={};regions={};if scene=='settings'then v:build()end
end
function love.draw()
 p:beginFrame();r:draw();p:endScene();S.Draw();p:endFrame()
 if scene=='proofs'then
  love.graphics.setColor(.02,.03,.05,1);love.graphics.rectangle('fill',0,82,love.graphics.getWidth(),love.graphics.getHeight()-82)
  for i,style in ipairs({'Classic Magic','Mystic Eye'})do local x=100+(i-1)*430;love.graphics.setColor(1,1,1,1);love.graphics.setFont(r.fonts[24]);love.graphics.print(style,x,130);love.graphics.draw(proofs[style],x,185,0,1.6,1.6)end
 end
 if#shots>0 then local name=table.remove(shots,1);local path='/tmp/love2gathering-card-back-'..name..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local file=assert(io.open(path,'wb'));file:write(data:encode('png'):getString());file:close()end)end
 love.timer.sleep(.015)
end
function love.quit()m.uiLayoutTimer=nil;m.api:quit();p:quit();S.OnQuit()end
