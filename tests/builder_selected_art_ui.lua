-- Actual Builder clicks and GPU uploads; delayed local response fixtures only.
local json=require('lib.json');local elapsed=0;local pending,calls={},{}
local output=assert(os.getenv('L2G_SELECTED_ART_OUTPUT'))
local cards={
 {id='oracle-a',printing_id='print-a',name='Slow selected fixture',oracle_text='Local test pixels.',type_line='Creature',image_uris={}},
 {id='oracle-b',printing_id='print-b',name='Current selected fixture',oracle_text='Local test pixels.',type_line='Creature',image_uris={}},
}
local pixels
package.preload['app.api']=function()return{escape=function(value)return tostring(value):gsub('([^%w%-_%.~])',function(c)return string.format('%%%02X',c:byte())end)end,new=function()return{
 request=function(_,service,method,path,body,callback,binary,options)
  local call={service=service,method=method,path=path,options=options,callback=callback,began=elapsed};calls[#calls+1]=call
  local delay=service=='art'and path:find('network=1',1,true)and(path:find('print%-a')and 1.2 or .03)or path:match('^/cards/alt%-b')and(options and options.priority=='selectedMetadata'and .03 or 1.8)or .02
  call.due=elapsed+delay;pending[#pending+1]=call;return #calls
 end,
 update=function()
  for i=#pending,1,-1 do local call=pending[i];if elapsed>=call.due then table.remove(pending,i)
   call.seconds=elapsed-call.began
   if call.options and call.options.isCurrent and not call.options.isCurrent()then call.callback(nil,'Image selection changed',499)
   elseif call.service=='art'then
    if call.path:find('network=1',1,true)then call.callback(nil,nil,200,pixels,{httpSeconds=call.seconds,decodeSeconds=0},{variant='original'})else call.callback(nil,nil,404)end
   elseif call.path:match('^/cards/alt%-b')or call.path:match('^/cards/popup%-alt')then local value=json.decode(json.encode(cards[2]));value.printing_id=call.path:find('popup%-alt')and'popup-alt'or'alt-b';call.callback(value,nil,200)
   elseif call.path:match('^/printings')then local value=json.decode(json.encode(cards[2]));value.printing_id='popup-alt';value.set='tst';value.set_name='Fixture edition';value.collector_number='1';call.callback({items={value},name=value.name,total=1,sets={}},nil,200)
   elseif call.path:match('^/cards/by%-name')then call.callback(cards[1],nil,200)
   elseif call.path:match('^/cards')then call.callback({cards=cards,total=#cards},nil,200)
   elseif call.path:match('^/sets')then call.callback({sets={}},nil,200)
   elseif call.path=='/decks/validate'then call.callback({valid=true,saveAllowed=true,errors={}},nil,200)
   else call.callback({},nil,200)end
  end end
 end,quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Artwork=require('app.artwork')
assert(love.filesystem.load('application-main.lua'))()
local m,r,v,p,runner;local wake=0;local mouse={x=2,y=2};local down=false;local dispatch={};local checks,shots,captures,controls={},{},{},{}
local function check(value,message)assert(value,message);checks[#checks+1]=message;print('SELECTED ART UI PASS '..message)end
local function wait(seconds)wake=elapsed+(seconds or .06);coroutine.yield()end
local function ready(predicate,message)for _=1,180 do if predicate()then return end;wait(.02)end;error(message)end
local function click(box)
 assert(box,'Visible Builder control missing')
 local x,y=(box.x+box.w/2)*Layout.scale,(box.y+box.h/2)*Layout.scale;local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x,y
 dispatch.mousemoved(x,y,x-ox,y-oy,false);wait(.03);down=true;dispatch.mousepressed(x,y,1,false,1);wait(.03);down=false;dispatch.mousereleased(x,y,1,false,1);wait(.06)
end
local function clickCard(name,kind)
 local box;for _,hit in ipairs(r.hits)do if hit.kind==(kind or'search')and hit.card.name==name then box=hit end end
 assert(box,'Visible Builder search card missing: '..name);click(box)
end
local function shot(name)shots[#shots+1]=name;wait(.08)end
local function selectedRequests(name)local count=0;for _,call in ipairs(calls)do if call.service=='art'and call.path:find('priority=selected',1,true)and call.path:find(name,1,true)then count=count+1 end end;return count end
local function scenario()
 wait(.2)
 check(m.settings.localArtworkOnly and not m.previewCard,'Builder opens under Cache only without an implicit selected download')
 for _,call in ipairs(calls)do if call.service=='art'then check(not call.path:find('network=1',1,true),'Initial visible artwork lookup never silently enables network')end end
 clickCard(cards[1].name);check(selectedRequests('print-a')==1,'Actual Classic card click requests its missing original at selected network priority')
 clickCard(cards[2].name)
 ready(function()return m:getBuilderPreviewArt(m.previewCard)~=nil end,'Selected exact image did not become visible')
 check(m.previewCard==cards[2]and selectedRequests('alt-b')==1,'The next actual card click resolves and downloads its saved alternate printing')
 local held=false;for _,call in ipairs(pending)do if call.service=='art'and call.path:find('priority=selected',1,true)and call.path:find('print%-a')then held=true end end
 check(held,'The current selected card becomes visible while the prior slow selected image is still waiting')
 local before=selectedRequests('alt-b');wait(.2);check(selectedRequests('alt-b')==before,'Idle frames reuse the selected image without repeated acquisition')
 check(m:getArt(cards[2],true,nil,{variant='thumb'})~=nil,'A previously missing thumbnail immediately reuses the acquired original')
 shot('classic-selected-exact')
 wait(1.3);check(m.previewCard==cards[2]and not(m.art['print-a-0-normal']and m.art['print-a-0-normal'].image),'A late obsolete download cannot upload or replace the current selected artwork')
 click(controls['Choose edition / art']);ready(function()return controls['edition-popup-alt']end,'Actual edition popup tile missing')
 check(selectedRequests('popup-alt')==0,'Opening an edition popup does not acquire its implicit candidate')
 click(controls['edition-popup-alt']);ready(function()local e=m.art['popup-alt-0-normal-exact'];return e and e.image end,'Explicit candidate did not download')
 check(selectedRequests('popup-alt')==1 and m.editDeck.printingSelections[1].printingId=='alt-b'and m.previewCard==cards[2],'Actual candidate click loads exact artwork while leaving deck and parent staging unchanged')
 shot('edition-candidate');click(controls.Cancel)
 check(not m.cardPrintingPicker and m.editDeck.printingSelections[1].printingId=='alt-b'and m.previewCard==cards[2],'Actual Cancel preserves both the saved edition and parent preview')
 click(controls['Choose edition / art']);ready(function()return controls['edition-popup-alt']end,'Reopened edition tile missing');click(controls['edition-popup-alt']);click(controls['Apply edition'])
 ready(function()return not m.cardPrintingPicker and m:getBuilderPreviewArt(m.previewCard)~=nil end,'Applied edition did not become selected')
 check(m.editDeck.printingSelections[1].printingId=='popup-alt'and m.previewCard==m.editDeck.main[2]and selectedRequests('popup-alt')==1,'Actual Apply selects the changed deck entry and reuses the acquired exact image')
 m:openDeck({id='simple-selected-art',name='Simplified selected art',format='Modern',main={{name=cards[1].name,count=1},{name=cards[2].name,count=1}},commander={},sideboard={},printingSelections={{name=cards[2].name,zone='main',count=1,printingId='alt-b'}}});m.cards=cards
 m.settings.builderLayout='Simplified';m.printingMetadata['alt-b']=nil
 for key in pairs(m.art)do if key:find('alt%-b')then m.art[key]=nil end end
 wait(.15);clickCard(cards[2].name,'builder-card')
 ready(function()local entry=m.art['alt-b-0-normal-exact'];return entry and entry.image end,'Simplified name-only entry did not finish its selected metadata/image chain')
 check(selectedRequests('alt-b')==2,'A real Simplified deck-entry click continues from unresolved edition metadata to its exact image')
 clickCard(cards[1].name)
 check(selectedRequests('print-a')==2,'Actual Simplified selection also explicitly fetches a cache miss')
 m:openDeck({id='replacement-editor',name='Replacement editor',format='Modern',main={},commander={},sideboard={}});m.cards=cards;wait(1.3)
 check(not m.previewCard and not(m.art['print-a-0-normal']and m.art['print-a-0-normal'].image),'Closing the old editor fences its pending selected image before GPU upload')
 check(m.settings.localArtworkOnly,'Explicit selection never changes the saved Cache only preference')
 for _,call in ipairs(calls)do if call.service=='art'and call.path:find('network=1',1,true)then check(call.path:find('priority=selected',1,true)and not call.path:find('variant=thumb',1,true),'Every acquired image belongs to an explicit full-size selection')end end
 check(m.artworkUploadMetrics and m.artworkUploadMetrics.count==3,'Only still-current exact selections reach real GPU uploads')
 local serial={};for _,call in ipairs(calls)do serial[#serial+1]={service=call.service,method=call.method,path=call.path,priority=call.options and call.options.priority,seconds=call.seconds}end
 local file=assert(io.open(output..'/report.json','w'));file:write(json.encode({checks=checks,captures=captures,requests=serial,uploadMetrics=m.artworkUploadMetrics,cache=Artwork.cacheInfo(m),scope='Actual production mouse callbacks, Classic/Simplified visible card clicks and LÖVE GPU upload. Local delayed image/metadata fixture callbacks, generated pixels, no external network, native game or user data. Worker socket priority tested separately.'}));file:close();love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function()return down end
 m=Model.new();m.loaded=true;m.settingsLoaded=true;m.profileLoaded=true;m.settings.windowMode='Windowed';m.settings.resolution='1440x900';m.settings.uiScale=1;m.settings.skybox='Off';m.settings.sfxEnabled=false;m.settings.musicEnabled=false;m.settings.vsync=false;m.settings.localArtworkOnly=true;m.settings.builderLayout='Classic';m.uiLayout={};m.catalogHealth={ready=false}
 pixels=love.image.newImageData(256,357);pixels:mapPixel(function(x,y)return .12+x/1024,.25+y/1024,.65,1 end)
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p:apply(true);p.appliedLoaded=true
 for i=1,30 do local name=debug.getupvalue(love.keypressed,i);if not name then break end;if name=='model'then debug.setupvalue(love.keypressed,i,m)elseif name=='renderer'then debug.setupvalue(love.keypressed,i,r)elseif name=='view'then debug.setupvalue(love.keypressed,i,v)end end
 for _,name in ipairs({'mousemoved','mousepressed','mousereleased','wheelmoved','keypressed','keyreleased','textinput'})do dispatch[name]=love[name];love[name]=function()end end
 local Cursor=require('lib.Slab.Internal.Core.Cursor');local Window=require('lib.Slab.Internal.UI.Window');local scopes={};local push,pop=S.PushID,S.PopID
 S.PushID=function(id)scopes[#scopes+1]=id;return push(id)end;S.PopID=function()scopes[#scopes]=nil;return pop()end
 local button=S.Button;S.Button=function(label,options)local result=button(label,options);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);local box={x=x,y=y,w=w,h=h};controls[label]=box;if scopes[#scopes]=='popup-alt'then controls['edition-popup-alt']=box end;return result end
 m:openDeck({id='selected-art-fixture',name='Selected art fixture',format='Modern',main={{name=cards[1].name,count=1},{name=cards[2].name,count=1}},commander={},sideboard={},printingSelections={{name=cards[2].name,zone='main',count=1,printingId='alt-b'}}});m.cards=cards;m.total=2;m.catalogHealth={ready=true};for _,card in ipairs(cards)do m:rememberCard(card)end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 elapsed=elapsed+dt;assert(elapsed<25,'Selected art UI timed out');m.api:update();S.Update(dt);r:update(dt)
 if elapsed>=wake and coroutine.status(runner)~='dead'then local ok,problem=coroutine.resume(runner);assert(ok,problem)end
 controls={};v:build()
end
function love.draw()
 love.graphics.clear(.025,.035,.06,1);r:draw();S.Draw()
 if#shots>0 then local path=output..'/'..table.remove(shots,1)..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local file=assert(io.open(path,'wb'));file:write(data:encode('png'):getString());file:close()end)end
end
function love.quit()if pixels then pixels:release()end;if p then p:quit()end;S.OnQuit()end
function love.errorhandler(message)local problem=debug.traceback(tostring(message),2);print(problem);local file=assert(io.open(output..'/failure.txt','w'));file:write(problem);file:close();return function()return 1 end end
