-- Actual Slab/production input, edition staging and responsive child grids.
-- Metadata and absent card images are bounded local fixtures; no user saves.
local json=require('lib.json');local clock=0;local pending,requests={},{}
local root=assert(os.getenv('LOVE2GATHERING_SET_PICKER_OUTPUT'))
local source={};for i=1,160 do source[#source+1]={code='z'..i,name='Fixture expansion '..i,count=i}end
source[#source+1]={code='thb',name='Theros Beyond Death',count=3};source[#source+1]={code='neo',name='Kamigawa: Neon Dynasty',count=7};source[#source+1]={code='all',name='Alliances',count=12};source[#source+1]={code='tst',name='Čarobni Đavoli',count=4}
local function copy(value)return json.decode(json.encode(value))end
package.preload['app.api']=function()return{escape=function(text)return tostring(text):gsub('([^%w%-_%.~])',function(c)return string.format('%%%02X',c:byte())end)end,new=function()return{
 request=function(_,service,method,path,body,callback,mode)
  requests[#requests+1]={service=service,method=method,path=path}
  pending[#pending+1]={service=service,method=method,path=path,callback=callback,due=clock+(path:match('^/printings')and .65 or .03)}
 end,
 update=function()
  for i=#pending,1,-1 do local call=pending[i];if clock>=call.due then table.remove(pending,i)
   if call.service=='art'then call.callback(nil,nil,404)
   elseif call.path:match('^/printings')then
    local set=call.path:match('[?&]set=([^&]*)')or'';local items={}
    for n=1,(set==''and 12 or 3)do items[#items+1]={id='oracle-swamp',name='Swamp',printing_id=(set~=''and set or'fixture')..'-printing-'..n,set=set~=''and set or'z1',set_name='Fixture edition',collector_number=tostring(n),artist='Fixture artist',image_uris={},oracle_text='',type_line='Basic Land — Swamp'}end
    call.callback({items=items,sets=copy(source),name='Swamp',total=set==''and 170 or 3},nil,200)
   elseif call.path:match('^/sets')then call.callback({sets=copy(source)},nil,200)
   elseif call.path:match('^/cards')then call.callback({cards={},total=0},nil,200)
   elseif call.path=='/decks/validate'then call.callback({valid=true},nil,200)
   else call.callback({},nil,200)end
  end end
 end,quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Picker=require('app.set_picker')
assert(love.filesystem.load('application-main.lua'))()
local m,r,v,p,runner;local wake=0;local mouse={x=2,y=2};local down,keys,dispatch={},{},{}
local controls,inputs,texts,checks,captures,shots,geometry={},{},{},{},{},{},{}
local childTiles=0;local sawRune=false;local runeFont
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('SET PICKER UI PASS '..label);io.stdout:flush()end
local function wait(seconds)wake=clock+(seconds or .07);coroutine.yield()end
local function ready(fn,label)for _=1,150 do if fn()then return end;wait(.04)end;error('Timed out: '..label)end
local function move(box)local x,y=box.x+box.w/2,box.y+box.h/2;local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;dispatch.mousemoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy,false)end
local function click(box)assert(box,'Missing actual set control');move(box);wait(.04);down[1]=true;dispatch.mousepressed(mouse.x,mouse.y,1,false,1);wait(.04);down[1]=nil;dispatch.mousereleased(mouse.x,mouse.y,1,false,1);wait(.1)end
local function typeText(box,text)click(box);keys.lctrl=true;dispatch.keypressed('lctrl','lctrl',false);dispatch.keypressed('a','a',false);wait(.03);dispatch.keyreleased('a','a');keys.lctrl=nil;dispatch.keyreleased('lctrl','lctrl');dispatch.textinput(text);wait(.1)end
local function escape()dispatch.keypressed('escape','escape',false);dispatch.keyreleased('escape','escape');wait(.12)end
local function shot(name)shots[#shots+1]=name;wait(.1)end
local function printingCalls()local n=0;for _,call in ipairs(requests)do if call.path:match('^/printings')then n=n+1 end end;return n end
local function openEdition()
 m:showCardPrintings({name='Swamp'},'main');wait(.08);click(controls['printing-set']);ready(function()return inputs['set-picker-search']end,'set search child')
end
local function settled()ready(function()return m.cardPrintingPicker and not m.cardPrintingPicker.busy and not m.cardPrintingPicker.timer end,'printing filter response')end
local function boundsInside(box)
 local w,h=Layout.dimensions();return box and box.x>=0 and box.y>=0 and box.x+box.w<=w+1 and box.y+box.h<=h+1
end
local function scenario()
 wait(.15);local revision=m.deckRevision;openEdition();local parent=m.cardPrintingPicker;local selected=parent.selectedId
 local calls=printingCalls();typeText(inputs['set-picker-search'],'NEO')
 check(v.setPicker and v.setPicker.query=='NEO','The edition set button opens an independent searchable child grid')
 ready(function()return controls['set-tile-neo']end,'late set list arriving');check(v.setPicker.query=='NEO','An asynchronous edition response preserves the typed local set query')
 check(printingCalls()==calls,'Typing in the set grid does not request more printing metadata')
 click(controls['set-tile-neo']);check(not v.setPicker and m.cardPrintingPicker==parent and parent.set=='neo'and parent.offset==0,'Choosing a set closes the child and changes only the parent set filter/page')
 check(parent.selectedId==selected and m.deckRevision==revision and m.editDeck.printingSelections[1].printingId=='saved-edition','Set filtering preserves staged artwork and saved deck selections')
 settled();click(controls['printing-set']);wait(.1)
 check(childTiles<=v.setPicker.pageSize and v.setPicker.pageSize<=20 and#source>150,'Rendering stays bounded to one grid page instead of every available set')
 shot('bounded-set-grid');typeText(inputs['set-picker-search'],'THB');ready(function()return controls['set-tile-thb']end,'THB tile')
 check(boundsInside(controls['set-tile-thb'])and controls['set-tile-thb'].x>controls['set-tile-all-sets'].x+controls['set-tile-all-sets'].w,'Filtered tiles have separate visible positions inside the child grid')
 check(sawRune and runeFont and runeFont:hasGlyphs(require('utf8').char(0xE961)),'The THB tile actually renders its verified supplied Keyrune glyph')
 shot('verified-thb-symbol');local setBefore=parent.set;local chosenBefore=parent.selectedId;escape()
 check(not v.setPicker and m.cardPrintingPicker==parent and parent.set==setBefore and parent.selectedId==chosenBefore,'Production Escape closes only the child and preserves parent staging')
 check(not S.IsAnyInputFocused(),'Closing a child releases its hidden search focus')

 click(controls['printing-set']);typeText(inputs['set-picker-search'],'Alliances');click(controls['set-tile-all']);settled()
 check(parent.set=='all','The actual Alliances tile filters to set ALL rather than clearing the filter')
 click(controls['printing-set']);click(controls['set-tile-all-sets']);settled();check(parent.set=='','The separate All sets tile clears the filter')

 click(controls['printing-set']);click(controls['Next sets']);check(v.setPicker.page==1 and controls['set-tile-all-sets'],'Actual Next advances a bounded page while keeping All sets reachable')
 click(controls['Previous sets']);check(v.setPicker.page==0,'Actual Previous returns to the first bounded set page')
 typeText(inputs['set-picker-search'],'ČAROBNI');check(controls['set-tile-tst'],'The real UTF-8 search input finds an accented set name without byte damage');click(controls['Close set picker'])
 check(m.cardPrintingPicker==parent and parent.set=='','Closing a filtered child applies no set choice')
 click(controls['printing-set']);local stale=v.setPicker;m:closeCardPrintings();wait(.1)
 check(not v.setPicker and not Picker.select(v,'thb',stale),'Closing the edition parent invalidates its child and old selection callbacks')

 for _,mode in ipairs({'Classic','Simplified'})do
  m.settings.builderLayout=mode;m.sets=copy(source);m.setsFormat=m.searchFormat;m.setsBusy=false;m.setsError=nil
  wait(.15)
  if mode=='Classic'then click(controls['classic-set-filter'])else click(controls['More filters']);ready(function()return controls['simple-set-filter']end,'Simplified More filters panel');click(controls['simple-set-filter'])end
  ready(function()return inputs['set-picker-search']end,mode..' child set input');typeText(inputs['set-picker-search'],'THB');click(controls['set-tile-thb']);check(m.searchSet=='thb','Visible '..mode..' Builder controls open the grid and apply its set filter')
  click(controls[mode=='Classic'and'classic-set-filter'or'simple-set-filter']);wait(.1);escape()
  check(not v.setPicker and(mode~='Simplified'or v.builderFiltersOpen),'Escape preserves the '..mode..' Builder parent panel')
  if mode=='Simplified'then click(controls['Close filters']);check(not v.builderFiltersOpen,'The visible More filters Close control remains interactive after child Escape')end
 end

 for _,size in ipairs({{1120,720,1},{2560,1080,1.25}})do
  m.settings.resolution=size[1]..'x'..size[2];m.settings.uiScale=size[3];p:apply(true);wait(.15);m.settings.builderLayout='Classic';require('app.builder').openSetFilter(v,'builder-set');wait(.1)
  if size[1]==1120 then v.setPicker.title='Choose a set for '..string.rep('A Very Long Legendary Card Name ',8);wait(.1)end
  geometry[#geometry+1]={requested=size,physical={love.graphics.getDimensions()},logical={Layout.dimensions()}}
  check(boundsInside(controls['Close set picker'])and boundsInside(controls['Next sets'])and boundsInside(inputs['set-picker-search']),'Child search, close and pagination fit at '..size[1]..' width / scale '..size[3])
  typeText(inputs['set-picker-search'],'THB');check(boundsInside(controls['set-tile-thb']),'The selected set tile stays inside the actual scaled viewport');shot('set-grid-'..size[1]);escape()
 end
 m.settings.resolution='1440x900';m.settings.uiScale=1;p:apply(true);wait(.15)
 require('app.builder').openSetFilter(v,'builder-set');wait(.1);local stale=v.setPicker;m:openDeck({id='new-editor',name='New editor',format='Modern',main={{name='Swamp',count=1}},commander={},sideboard={}});wait(.1)
 check(not v.setPicker and not Picker.select(v,'thb',stale),'Replacing the editor closes the old child before any stale click can apply')
 for _,call in ipairs(requests)do check(call.method=='GET'or call.path=='/decks/validate','Set browsing sends no persistence, native game action or image download')end
 local file=assert(io.open(root..'/report.json','w'));file:write(json.encode({checks=checks,geometry=geometry,captures=captures,requests=requests,scope='Actual Slab/production main input, supplied Keyrune THB glyph, staged edition filtering and Classic/Simplified child ownership at native/scaled modes. Local metadata/404 image fixtures only; no user data or engine.'}));file:close();love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return down[button]==true end;love.keyboard.isDown=function(...)for _,key in ipairs({...})do if keys[key]then return true end end;return false end;love.keyboard.isScancodeDown=love.keyboard.isDown
 m=Model.new();m.loaded=true;m.settingsLoaded=true;m.profileLoaded=true;m.uiLayout={};m.settings.windowMode='Windowed';m.settings.resolution='1440x900';m.settings.uiScale=1;m.settings.skybox='Off';m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.vsync=false;m.settings.localArtworkOnly=true
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p:apply(true);p.appliedLoaded=true
 for i=1,30 do local name=debug.getupvalue(love.keypressed,i);if not name then break end;if name=='model'then debug.setupvalue(love.keypressed,i,m)elseif name=='renderer'then debug.setupvalue(love.keypressed,i,r)elseif name=='view'then debug.setupvalue(love.keypressed,i,v)end end
 -- Keep exercising production routing while excluding unrelated desktop input.
 -- Slab tracks callback coordinates, not love.mouse.getPosition(), so a real
 -- pointer moving over this test window otherwise steals the synthetic hover.
 for _,name in ipairs({'mousemoved','mousepressed','mousereleased','wheelmoved','keypressed','keyreleased','textinput'})do dispatch[name]=love[name];love[name]=function()end end
 m:openDeck({id='set-grid-fixture',name='Set grid fixture',format='Modern',main={{name='Swamp',count=1}},commander={},sideboard={},printingSelections={{name='Swamp',zone='main',count=1,printingId='saved-edition',set='thb'}}})
 local Cursor=require('lib.Slab.Internal.Core.Cursor');local Window=require('lib.Slab.Internal.UI.Window')
 local function bounds()local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);return{x=x,y=y,w=w,h=h}end
 local scopes={};local push,pop=S.PushID,S.PopID;S.PushID=function(id)scopes[#scopes+1]=id;return push(id)end;S.PopID=function()scopes[#scopes]=nil;return pop()end
 for _,kind in ipairs({'Button','Input'})do local original=S[kind];S[kind]=function(id,options)local result=original(id,options);local record=bounds();if kind=='Button'then controls[id]=record;if scopes[#scopes]=='builder-set'then controls['classic-set-filter']=record elseif scopes[#scopes]=='simple-set'then controls['simple-set-filter']=record end;if id:match('^set%-tile%-')then childTiles=childTiles+1;record.active=options.Active end else inputs[id]=record end;return result end end
 local textf=S.Textf;S.Textf=function(text,options)texts[text]=true;return textf(text,options)end
 local newFont=love.graphics.newFont;love.graphics.newFont=function(path,...)local font=newFont(path,...);if path=='assets/keyrune/keyrune.ttf'then runeFont=font end;return font end
 local print=love.graphics.print;love.graphics.print=function(text,...)if text==require('utf8').char(0xE961)and love.graphics.getFont()==runeFont then sawRune=true end;return print(text,...)end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<90,'Set grid UI timed out');m.api:update();m:updateCardPrintings(dt);S.Update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,problem=coroutine.resume(runner);assert(ok,problem)end
 controls={};inputs={};texts={};childTiles=0;v:build()
end
function love.draw()
 love.graphics.clear(.025,.035,.06,1);S.Draw()
 if#shots>0 then local path=root..'/'..table.remove(shots,1)..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local file=assert(io.open(path,'wb'));file:write(data:encode('png'):getString());file:close()end)end
end
function love.quit()if p then p:quit()end;S.OnQuit()end
function love.errorhandler(message)local problem=debug.traceback(tostring(message),2);print(problem);local file=assert(io.open(root..'/failure.txt','w'));file:write(problem);file:close();return function()return 1 end end
