-- Actual catalog/cache/persistence with a named temporary fixture deck; no game.
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local UI=require('app.token_art_ui');local Layout=require('app.layout');local json=require('lib.json')
local m,r,v,runner,Cursor,Region;local buttons,checks,shots={},{},{};local time,wake=0,0;local mouse={x=1,y=1};local down=false
local function check(ok,text)assert(ok,text);checks[#checks+1]=text;print('TOKEN LIVE UI PASS '..text)end
local function wait(seconds)wake=time+(seconds or .1);coroutine.yield()end
local function untilReady(fn)for _=1,180 do if fn()then return end;wait(.1)end;error('Timed out waiting for actual catalog/image response')end
local function click(label)
 local b=assert(buttons[label],label);local x,y=(b.x+b.w/2)*Layout.scale,(b.y+b.h/2)*Layout.scale
 mouse.x,mouse.y=x,y;S.OnMouseMoved(x,y,0,0);wait(.05);down=true;S.OnMousePressed(x,y,1,false,1);wait(.05);down=false;S.OnMouseReleased(x,y,1,false,1);wait(.15)
end
local function shot(name)shots[#shots+1]=name;wait(.15)end
local function scenario()
 m:showTokenSettings(assert(os.getenv('LOVE2GATHERING_TOKEN_FIXTURE')));untilReady(function()return not m.tokenBusy end)
 check(#m.tokenItems>=4,'Actual deck relationships expose Goat, both Rat rules families and Treasure')
 local treasure;local rats=0;for _,group in ipairs(m.tokenItems)do if group.name=='Treasure'then treasure=group elseif group.name=='Rat'then rats=rats+1 end end
 check(treasure and treasure.variantCount>60 and rats==2,'Real token families keep different Rat rules separate and include the full Treasure art catalog')
 shot('families');click('Edit Treasure artwork');untilReady(function()return m.tokenPicker and not m.tokenPicker.busy end)
 local first,second=m.tokenPicker.items[1],m.tokenPicker.items[2]
 untilReady(function()return m:getArt(first,true)and m:getArt(second,true)end)
 check(m:getArt(first,true):getWidth()>100,'Exact genuine cached JPEGs render in the actual token grid')
 click('Random selected');click('Artwork '..first.tokenImageId);click('Artwork '..second.tokenImageId)
 check(m.tokenPicker.selected[first.tokenImageId]and m.tokenPicker.selected[second.tokenImageId],'Actual card clicks stage two outlined matching Treasure editions')
 shot('random-selected');click('Apply token selection');click('Save token artwork');untilReady(function()return not m.tokenSaving end)
 check(not m.tokenDirty and not m.tokenError,'Per-token random-selected preference persisted through the actual catalog')
 local saved;m:request('catalog','GET','/decks/'..m.tokenDeckId..'/token-art',nil,function(data)saved=data end,true);untilReady(function()return saved end)
 check(saved.overrides[treasure.tokenIdentity].mode=='randomSelected'and#saved.overrides[treasure.tokenIdentity].selected==2,'SQLite-backed API returns the exact two selected artwork IDs')
 m.activeDeckId=m.tokenDeckId;local token={id='native-token-ui-fixture',objectId='native-token-ui-fixture',name='Treasure',token=true,printing={name='Treasure',type_line='Artifact — Treasure',colors=json.array()}}
 untilReady(function()return m:resolveTokenCard(token)end)
 local resolved=m:resolveTokenCard(token);check(resolved.tokenImageId==first.tokenImageId or resolved.tokenImageId==second.tokenImageId,'Normal token resolution consumes the saved family selection without changing native identity')
 click('Edit Treasure artwork');untilReady(function()return m.tokenPicker and not m.tokenPicker.busy end);click('Random all');shot('random-all');click('Cancel token selection')
 check(m.tokenOverrides[treasure.tokenIdentity].mode=='randomSelected','Closing the real popup preserves the prior saved active pool')
 click('Edit Treasure artwork');untilReady(function()return m.tokenPicker and not m.tokenPicker.busy end);click('Manual');click('Artwork '..second.tokenImageId);click('Apply token selection');click('Save token artwork');untilReady(function()return not m.tokenSaving end)
 local active=m:tokenGroupPresentation(treasure);check(active.mode=='selected'and active.card.tokenImageId==second.tokenImageId,'Main page shows the newly active exact manual printing')
 shot('manual-active')
 local f=assert(io.open('/tmp/love2gathering-token-art-live-ui-report.json','w'));f:write(json.encode({passed=true,checks=checks,physical={love.graphics.getDimensions()},logical={Layout.dimensions()},tokenFamilies=#m.tokenItems,treasureVariants=treasure.variantCount,scope='Actual LÖVE/Slab, isolated HTTP catalog/SQLite and genuine cached JPEGs. Only the explicitly named temporary deck token preferences are written. No engine/native match or network image download.'}));f:close()
 print('TOKEN LIVE UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.errorhandler(message)io.stderr:write('TOKEN LIVE UI FAILED '..tostring(message)..'\n'..debug.traceback()..'\n');return function()return 1 end end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
 m=Model.new();m.loaded=true;m.settingsLoaded=true;m.settings.sfxEnabled=false;m.settings.localArtworkOnly=true;m.settings.animations=false;m.settings.particles=false
 m.saveSettings=function()error('Live token test must not save application preferences')end;m.setUILayout=function()end
 r=Renderer.new(m);v=View.new(S,m,r)
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(b)return b==1 and down end
 local original=S.Button;S.Button=function(label,options)local result=original(label,options);local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();buttons[label]={x=x+dx,y=y+dy,w=w,h=h};return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 time=time+dt;assert(time<50,'Live token UI exceeded bounded run');m.api:update();m:updateLibrary(dt);S.Update(dt);r:update(dt)
 if time>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
 buttons={};UI.build(v,Layout.dimensions())
end
function love.draw()
 love.graphics.clear(.025,.035,.055,1);S.Draw()
 if#shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)local f=assert(io.open('/tmp/love2gathering-token-live-'..name..'.png','wb'));f:write(data:encode('png'):getString());f:close()end)end
 love.timer.sleep(.015)
end
function love.quit()if m then m:closeTokenPicker();m.game=nil;m.api:quit()end;S.OnQuit()end
