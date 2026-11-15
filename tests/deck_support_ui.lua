-- Actual controlled-input LÖVE/Slab presentation; service correctness tested separately.
local json=require('lib.json');local pending={};local calls={};local clock=0
package.preload['app.api']=function()return{escape=function(s)return tostring(s):gsub('([^%w%-_%.~])',function(c)return string.format('%%%02X',c:byte())end)end,new=function()return{request=function()error('Unexpected live service access')end,quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Assets=require('app.assets');local SetIcons=require('app.set_icons');local Collection=require('app.collection');local CollectionUI=require('app.collection_ui');local DeckPicker=require('app.deck_picker')
local m,r,v,prefs,runner;local mouse={x=1,y=1};local down=false;local buttons={};local wake=0;local builds,wakeBuild=0,0;local checks={};local shots={};local glyphs,artDraws,texts={}, {},{};local output=assert(os.getenv('LOVE2GATHERING_SUPPORT_OUTPUT'));local normal;local printing='8b796a56-1611-4835-ac5b-48b4e9263685';local missing={'Unimplemented test card','Second missing test card'}
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('SUPPORT UI PASS '..label);io.stdout:flush()end
local function wait(dt)wake=clock+(dt or .08);wakeBuild=builds+2;coroutine.yield()end
local function move(x,y)local dx,dy=x*Layout.scale-mouse.x,y*Layout.scale-mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,dx,dy);r:mousemoved(x,y)end
local function click(box)assert(box,'Missing actual control');move(box.x+box.w/2,box.y+box.h/2);wait(.06);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);if S.IsVoidHovered()then r:mousepressed(box.x+box.w/2,box.y+box.h/2,1,1)end;wait(.05);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);r:mousereleased(box.x+box.w/2,box.y+box.h/2,1);wait(.13)end
local function shot(name)love.graphics.captureScreenshot(function(data)local f=assert(io.open(output..'/'..name..'.png','wb'));f:write(data:encode('png'):getString());f:close()end);shots[#shots+1]=name..'.png';wait(.12)end
local function hit(id)for _,h in ipairs(r.hits)do if h.kind=='deck'and h.deck.id==id then return h end end end
local function hasText(q)for _,text in ipairs(texts)do if tostring(text):find(q,1,true)then return true end end;return false end
local function scenario()
 wait(.4)
 local font=love.graphics.newFont('assets/keyrune/keyrune.ttf',22);local count=0
 for _,cp in pairs(SetIcons.mapping)do assert(font:hasGlyphs(require('utf8').char(cp)),'Mapped glyph missing from supplied font');count=count+1 end
 check(count==425,'All425 official set mappings exist in the unchanged supplied font')
 for _,scale in ipairs({1,1.25})do
  m.page='decks';m.settings.uiScale=scale;prefs:apply(true);m.collectionSearch='';m.collectionFormat='All';r.deckScroll=0;m.selectedDeck=nil;wait(.3)
  local good=assert(hit('precon-covered'));local bad=assert(hit('precon-missing'))
  check(good.w==good.h and good.y+good.h<=select(2,Layout.dimensions()),'Full commander tile stays inside logical viewport at scale '..scale)
  local fit=false
  for _,draw in ipairs(artDraws)do if draw.image==normal and draw.x>=good.x and draw.x<good.x+good.w then fit=draw.w<=good.w-9 and draw.h<=good.h-90 and math.abs(draw.w/draw.h-normal:getWidth()/normal:getHeight())<.001 end end
  check(fit,'Anikthea cached full scan displays complete aspect with no crop needed at scale '..scale)
  check(glyphs.cmm and glyphs.cmm.verified,'Actual preconstructed header draws its supplied Commander Masters glyph')
  check(hasText('Unavailable')and hasText('2 cards not implemented'),'Unavailable card implementation status overlays the tile')
  shot('collection-scale'..scale);click(bad)
  check(m.selectedDeck=='precon-missing'and buttons['Use in lobby']and buttons['Use in lobby'].disabled,'Unavailable collection tile remains inspectable but its Use action is disabled')
  check(hasText(missing[1])and hasText(missing[2]),'Actual details list names both unimplemented cards')
  check(not buttons['Edit deck'].disabled,'Unavailable archived list remains editable for repair')
  shot('details-scale'..scale)
  m.page='lobby';wait(.2);click(buttons.yourDeck)
  check(v.deckSelection~=nil,'Actual player-deck button opens lobby card picker')
  local state=v.deckSelection;state.timer=nil;state.precons=m.precons;state.total=2;state.collapsed['set:Commander Masters']=false;wait(.2);click(buttons['My Decks · 1'])
  check(buttons['Unavailable product'],'Expanded set group contains actual unavailable product button')
  shot('picker-grid-scale'..scale);click(buttons['Unavailable product']);check(v.deckSelection==state and state.supportDetails and state.supportDetails.id=='precon-missing','Unavailable lobby tile opens details without selecting or closing picker')
  check(hasText(missing[1])and hasText(missing[2]),'Lobby support details show exact unavailable card names')
  shot('picker-details-scale'..scale);click(buttons['Back to deck choices']);check(not state.supportDetails,'Back returns to bounded deck grid')
  click(buttons['Enduring Enchantments']);check(not v.deckSelection and m.playerDeckId=='selected-precon-covered','Implemented deck still selects through normal exact source callback')
 end
 for _,call in ipairs(calls)do assert(call.method=='GET','Fixture made unexpected write');if call.path:find('^/deck%-cover')then assert(call.path:find('deckId=precon%-covered')or call.path:find('deckId=precon%-missing')or call.path:find('deckId=own'))end end
 check(#calls<20,'Visible cover metadata is shared across frames rather than requested repeatedly')
 local f=assert(io.open(output..'/report.json','w'));f:write(json.encode({checks=checks,captures=shots,requests=calls,scope='Actual LÖVE/Slab clicks, Collection and lobby popup at UI scales1/1.25. Genuine cached Anikthea normal JPEG read-only copied into isolated fixture. Controlled registry/product metadata, no native match, writes or network acquisition.'}));f:close();love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true)
 for _,name in ipairs({'mousepressed','mousereleased','mousemoved','wheelmoved','keypressed','keyreleased','textinput'})do love[name]=function()end end
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function()return down end;love.keyboard.isDown=function()return false end;love.keyboard.isScancodeDown=function()return false end
 m=Model.new();m.loaded=true;m.settingsLoaded=true;m.profileLoaded=true;m.startersLoaded=true;m.starterDecks={};m.preconLoaded=true;m.preconStats={formats={{id='Commander'}}};m.uiLayout={collection={collapsed={user=true,starter=true,preconstructed=false}}};m.page='decks';m.format='Commander'
 m.catalogHealth={ready=true,deckCovers=true,storage={dataDirectory='/tmp/support-ui'}};m.settings.windowMode='Windowed';m.settings.resolution='1440x900';m.settings.uiScale=1;m.settings.vsync=false;m.settings.skybox='Off';m.settings.musicEnabled=false;m.settings.sfxEnabled=false;m.settings.localArtworkOnly=true;m.settings.showCardArt=true
 local function deck(id,name,status)return{id=id,name=name,format='Commander',origin='preconstructed',set='cmm',expansion='Commander Masters',faceCommander='Anikthea, Hand of Erebos',coverCard='Anikthea, Hand of Erebos',main={{name='Forest',count=99}},sideboard={},commander={{name='Anikthea, Hand of Erebos',count=1}},colors={'W','B','G'},engineSupport=status}end
 m.precons={deck('precon-covered','Enduring Enchantments',{state='ready',missingNames={}}),deck('precon-missing','Unavailable product',{state='unavailable',missingNames=missing})};m.preconsTotal=2;m.decks={deck('own','Own deck',{state='ready',missingNames={}})};m.decks[1].origin='user';m.playerDeckId='own';m.botDeckId='own';m.botDeckIds={'own','own','own'}
 normal=love.graphics.newImage('anikthea-normal.jpg');m.deckSupport=function(_,d)return d.engineSupport or{state='unknown'}end
 m.request=function(_,service,method,path,body,cb)calls[#calls+1]={method=method,path=path};pending[#pending+1]={at=clock+.03,path=path,cb=cb};return true end
 m.getArt=function(_,card,_,kind)if card.printing_id==printing and kind=='normal'then return normal end end
 m.selectLobbyPrecon=function(_,state,deck)state.changed('selected-'..deck.id);DeckPicker.close(v,state)end
 r=Renderer.new(m);v=View.new(S,m,r);prefs=Preferences.new(m,S,r);v.preferences=prefs;prefs:apply(true);prefs.appliedLoaded=true
 local Cursor=require('lib.Slab.Internal.Core.Cursor');local Window=require('lib.Slab.Internal.UI.Window');local original=S.Button
 S.Button=function(id,opt)local result=original(id,opt);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);buttons[id]={x=x,y=y,w=w,h=h,disabled=opt.Disabled};return result end
 local draw=love.graphics.draw;love.graphics.draw=function(image,x,y,a,sx,sy,...)if image==normal and type(x)=='number'then artDraws[#artDraws+1]={image=image,x=x,y=y,w=image:getWidth()*(sx or 1),h=image:getHeight()*(sy or sx or 1)}end;return draw(image,x,y,a,sx,sy,...)end
 for _,name in ipairs({'text','strong'})do local original=r[name];r[name]=function(self,text,...)texts[#texts+1]=text;return original(self,text,...)end end
 local text=S.Textf;S.Textf=function(value,...)texts[#texts+1]=value;return text(value,...)end
 local icon=SetIcons.draw;SetIcons.draw=function(assets,code,...)local verified=icon(assets,code,...);glyphs[code]={verified=verified};return verified end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<45,'Support fixture timed out')
 for i=#pending,1,-1 do if pending[i].at<=clock then local q=table.remove(pending,i);if q.path:find('^/deck%-cover')then q.cb({card={name='Anikthea, Hand of Erebos',printing_id=printing,id='991fd651-0cba-41ee-855a-d01a1a7c8f60',printingExact=true},kind='normal',cached=true})elseif q.path:find('^/precons/')then q.cb(m.precons[2])else q.cb({decks={},total=0})end end end
 S.Update(dt);r:update(dt)
 if clock>=wake and builds>=wakeBuild and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 buttons={};texts={};v:build();r.uiHovered=not S.IsVoidHovered();builds=builds+1
end
function love.draw()glyphs={};artDraws={};prefs:beginFrame();r:draw();prefs:endScene();S.Draw();prefs:endFrame()end
function love.quit()m.uiLayoutTimer=nil;prefs:quit();S.OnQuit()end
function love.errorhandler(message)local trace=debug.traceback(tostring(message),2);print(trace);local f=assert(io.open(output..'/failure.txt','w'));f:write(trace);f:close();return function()return 1 end end
