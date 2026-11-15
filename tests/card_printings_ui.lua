-- Real Slab controls/HTTP JPEG decoding and deck persistence, isolated catalog only.
local json=require('lib.json');local Layout=require('app.layout');local S=require('lib.Slab');local API=require('app.api');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences')
local targets=json.decode(assert(love.filesystem.read('printing-targets.json')))
local m,r,v,p,Cursor,Window,runner;local mouse={x=2,y=2};local down,keys={},{};local time,wake=0,0;local buttons,inputs,combos,selectables,checks,shots,captures,tiles={},{},{},{},{},{},{},{}
local urls={};local function check(value,label)assert(value,label);checks[#checks+1]=label;print('PRINTING UI PASS '..label);io.stdout:flush()end
local function wait(seconds)wake=time+(seconds or .08);coroutine.yield()end
local function ready(fn,label,seconds)local limit=time+(seconds or 15);while not fn()do assert(time<limit,label..' '..json.encode(m.cardPrintingPicker and{name=m.cardPrintingPicker.name,busy=m.cardPrintingPicker.busy,total=m.cardPrintingPicker.total,error=m.cardPrintingPicker.error}or{}));wait(.05)end end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;love.mousemoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy,false)end
local function click(box)assert(box,'Missing printing control');move(box.x+box.w/2,box.y+box.h/2);wait(.05);down[1]=true;love.mousepressed(mouse.x,mouse.y,1,false,1);wait(.06);down[1]=nil;love.mousereleased(mouse.x,mouse.y,1,false,1);wait(.12)end
local function text(box,value)click(box);keys.lctrl=true;love.keypressed('lctrl','lctrl',false);love.keypressed('a','a',false);wait(.04);love.keyreleased('a','a');keys.lctrl=nil;love.keyreleased('lctrl','lctrl');love.textinput(value);wait(.28)end
local function request(method,path,body)local done,result,problem=false;m:request('catalog',method,path,body,function(data,err)result=data;problem=err;done=true end,true);ready(function()return done end,'HTTP request timed out');assert(not problem,problem);return result end
local function shot(name)shots[#shots+1]=name;wait(.2)end
local function settled()ready(function()return m.cardPrintingPicker and not m.cardPrintingPicker.busy and not m.cardPrintingPicker.timer and#m.cardPrintingPicker.items>0 end,'Edition list did not settle')end
local function selected(name)for _,s in ipairs(m.editDeck.printingSelections or{})do if s.name==name then return s end end end
local function actualArtIcon(name)for _,hit in ipairs(r.hits)do if hit.kind=='printing-art'and hit.tooltip:find(name,1,true)then return hit end end end
local function choose(target)
 ready(function()return tiles[target.printing_id]end,'Target printing tile did not render');click(tiles[target.printing_id]);check(m.cardPrintingPicker.selectedId==target.printing_id,'Actual thumbnail selects exact '..target.name..' printing')
 ready(function()return m:getArt(target,true)end,'Genuine exact JPEG did not decode')
 check(urls[target.printing_id]and urls[target.printing_id]:find('exact=1',1,true),'Exact thumbnail URL forbids another printing alias')
 local x=tiles[target.printing_id];local w,h=Layout.dimensions();check(x.x>=0 and x.y>=0 and x.x+x.w<=w and x.y+x.h<=h,'Selected printing is visible inside the logical viewport')
end
local function scenario()
 ready(function()return m.catalogHealth.ready end,'Temporary catalog did not become ready',25)
 local body={id=targets.deckId,name=targets.deckName,format='Commander',origin='user',main={{name='Forest',count=99}},commander={{name=targets.commander.name,count=1}},sideboard=json.array()}
 local created=request('POST','/decks',body);local deck=created.deck or created;m:openDeck(deck);m.settings.builderLayout='Simplified';wait(.35)
 check(m.editDeck.id==targets.deckId and Model.count(m.editDeck,'main')==99,'Real catalog created only the named isolated Commander fixture')
 ready(function()return actualArtIcon('Forest')end,'Simplified Forest edition icon is absent');click(actualArtIcon('Forest'));settled()
 check(m.cardPrintingPicker.name=='Forest'and m.cardPrintingPicker.zone=='main'and r:inputBlocked(),'Actual deck-card icon opens a modal locked to Forest main copies')
 local opening=m.cardPrintingPicker;click({x=26,y=110,w=30,h=20});check(m.cardPrintingPicker==opening and not v.builderPopup,'Modal stack lock rejects a visible background builder dropdown press')
 check(m.cardPrintingPicker.total>12 and#m.cardPrintingPicker.items==12,'Forest catalog stays paged instead of loading every printing')
 shot('forest-first-page');click(buttons.Next);settled();check(m.cardPrintingPicker.offset==12,'Actual Next button loads the second bounded printing page');click(buttons.Previous);settled()
 local setBounds=combos['printing-set'];click(setBounds);local thb
 shot('set-popup')
 for attempt=1,35 do
  for label,box in pairs(selectables)do if label:find('THB',1,true)==1 then thb=box;break end end
  if thb and thb.y>setBounds.y+36 and thb.y+thb.h<setBounds.y+236 then break end
  move(setBounds.x+100,setBounds.y+160);wait(.08);love.wheelmoved(0,-12);wait(.08)
 end
 click(thb);settled()
 check(m.cardPrintingPicker.set=='thb'and#m.cardPrintingPicker.items==3,'Actual set dropdown restricts Forest to Theros Beyond Death editions')
 choose(targets.forest);shot('forest-thb-selected');local revision=m.deckRevision;click(buttons.Cancel)
 check(not m.cardPrintingPicker and not selected('Forest')and m.deckRevision==revision,'Cancel leaves deck quantities and edition selection untouched')
 m:showCardPrintings({name='Forest'},'main');settled();m:filterCardPrintings(nil,'thb');settled();choose(targets.forest);click(buttons['Apply edition'])
 check(selected('Forest').printingId==targets.forest.printing_id and selected('Forest').count==99 and Model.count(m.editDeck,'main')==99,'Apply changes artwork for all Forest copies without changing card counts')
 m.selectedSection='commander';wait(.3);ready(function()return actualArtIcon(targets.commander.name)end,'Commander edition icon is absent');click(actualArtIcon(targets.commander.name));settled();choose(targets.commander);shot('commander-selected');click(buttons['Apply edition'])
 check(selected(targets.commander.name).zone=='commander'and selected(targets.commander.name).count==1,'Commander artwork retains the command-zone identity')
 ready(function()return buttons['Save *']end,'Builder save control missing');click(buttons['Save *']);ready(function()return not m.dirty end,'Actual save did not finish')
 local saved=request('GET','/decks/'..targets.deckId);check(#saved.printingSelections==2,'SQLite-backed GET restores both exact artwork choices')
 m:openDeck(saved);wait(.25);check(selected('Forest').printingId==targets.forest.printing_id and selected(targets.commander.name).printingId==targets.commander.printing_id,'Reopening the saved deck retains basic and commander editions')
 local current={id='native-forest',name='Forest',ownerId='seat-owner',selectedPrintingId=targets.forest.printing_id,power='7',toughness='8',counters={['+1/+1']=2}}
 ready(function()local c=m:cardData(current);return c.printingResolved and m:getArt(current,true)end,'Runtime exact chosen image did not load')
 local rendered=m:cardData(current);check(rendered.printing_id==targets.forest.printing_id and rendered.objectId=='native-forest'and rendered.power=='7'and rendered.toughness=='8','Runtime projection uses selected JPEG and preserves authoritative native values')
 m:showCardPrintings({name='Forest'},'main');settled();text(inputs['printing-search'],'Theros');local old=m.cardPrintingPicker;m:closeCardPrintings();m:showCardPrintings({name=targets.commander.name},'commander');settled();wait(.4)
 check(m.cardPrintingPicker~=old and m.cardPrintingPicker.name==targets.commander.name and#m.cardPrintingPicker.items==4,'Late response from a closed Forest opening cannot overwrite a commander opening')
 text(inputs['printing-search'],'Core');love.keypressed('escape','escape',false);love.keyreleased('escape','escape');wait(.15);check(not m.cardPrintingPicker,'Escape closes the edition picker while its search input is focused')
 m:showCardPrintings({name='Forest'},'main');settled();m:openDeck(saved);wait(.2);check(not m.cardPrintingPicker,'Opening another editor invalidates a previous edition popup')
 for _,size in ipairs({{1120,760,1},{2560,1080,1.25}})do
  m.settings.resolution=size[1]..'x'..size[2];m.settings.uiScale=size[3];p:apply(true);wait(.3);m:showCardPrintings({name=targets.commander.name},'commander');settled();choose(targets.commander)
  local _,h=Layout.dimensions();check(buttons['Apply edition'].y+buttons['Apply edition'].h<=h,'Edition footer remains visible at '..size[1]..' width and scale '..size[3]);shot('responsive-'..size[1]);click(buttons.Cancel)
 end
 request('DELETE','/decks/'..targets.deckId);check(true,'Only the test-created isolated deck was removed')
 local out=assert(io.open('/tmp/love2gathering-card-printings-ui-report.json','w'));out:write(json.encode({passed=true,checks=checks,captures=captures,forestPrinting=targets.forest.printing_id,commanderPrinting=targets.commander.printing_id,scope='Actual main callbacks, Slab, Renderer/View input, real isolated API11 SQLite deck saves and genuine cached JPEG HTTP decoding. Runtime native values are a presentation fixture; native entitlement is tested separately. No user storage, image downloads or active native match.'}));out:close();print('PRINTING UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
local originalAPI=API.new;API.new=function(options)options=options or{};options.catalogPort=assert(tonumber(os.getenv('LOVE2GATHERING_CATALOG_PORT')));return originalAPI(options)end
local oldModel=Model.new;Model.new=function(...)m=oldModel(...);return m end
local oldRenderer=Renderer.new;Renderer.new=function(...)r=oldRenderer(...);return r end
local oldView=View.new;View.new=function(...)v=oldView(...);return v end
local oldPreferences=Preferences.new;Preferences.new=function(...)p=oldPreferences(...);return p end
require('app.startup').new=function()return{ready=true}end -- Startup services have separate acceptance.
assert(love.filesystem.load('application.lua'))();local appLoad,appUpdate,appDraw,appQuit=love.load,love.update,love.draw,love.quit
function love.load()
 appLoad({});Cursor=require('lib.Slab.Internal.Core.Cursor');Window=require('lib.Slab.Internal.UI.Window');love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(b)return down[b]==true end;love.keyboard.isDown=function(...)for _,key in ipairs({...})do if keys[key]then return true end end;return false end;love.keyboard.isScancodeDown=love.keyboard.isDown
 m.loaded=true;m.settingsLoaded=true;m.uiLayout={};m.settings.windowMode='Windowed';m.settings.resolution='1440x900';m.settings.uiScale=1;m.settings.renderScale=1;m.settings.localArtworkOnly=true;m.settings.showCardArt=true;m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.particles=false;m.settings.animations=false;m.settings.frameLimit=0;m.saveSettings=function()end;m.setUILayout=function()end;p.appliedLoaded=true;p:apply(true)
 local apiRequest=m.api.request;m.api.request=function(self,service,method,path,...)
  if service=='art'then local id=path:match('[?&]printing=([^&]+)');if id then urls[id]=path end end;return apiRequest(self,service,method,path,...)
 end
 local pushID,popID=S.PushID,S.PopID;local stack={};S.PushID=function(id)stack[#stack+1]=id;return pushID(id)end;S.PopID=function()stack[#stack]=nil;return popID()end
 for _,kind in ipairs({'Button','Input','BeginComboBox','TextSelectable'})do local original=S[kind];S[kind]=function(id,options,...)local result=original(id,options,...);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);local b={x=x,y=y,w=w,h=h};({Button=buttons,Input=inputs,BeginComboBox=combos,TextSelectable=selectables})[kind][id]=b;if kind=='Button'and m.cardPrintingPicker then for _,item in ipairs(m.cardPrintingPicker.items)do if stack[#stack]==item.printing_id and id==item.name then tiles[item.printing_id]=b end end end;return result end end
 runner=coroutine.create(scenario)
end
function love.update(dt)time=time+dt;assert(time<120,'Printing acceptance timed out');buttons={};inputs={};combos={};selectables={};tiles={};appUpdate(dt);if time>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end end
function love.draw()appDraw();if#shots>0 then local name=table.remove(shots,1);local path='/tmp/love2gathering-card-printings-'..name..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local out=assert(io.open(path,'wb'));out:write(data:encode('png'):getString());out:close()end)end end
function love.quit()if appQuit then return appQuit()end end
function love.errorhandler(message)io.stderr:write('PRINTING UI FAILED '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
