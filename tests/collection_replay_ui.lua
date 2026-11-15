local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences')
local Layout=require('app.layout');local Collection=require('app.collection');local CollectionUI=require('app.collection_ui');local Assets=require('app.assets');local json=require('lib.json')
local m,r,v,prefs,runner,Cursor,Region,refs
local elapsed,wake,frame=0,0,0;local checks,shots,created,requests={},{},{},{}
local buttons,inputs,replayButtons,replayText,draws,manas,renderedText={},{},{},{},{},{},{}
local idStack={};local mouse={x=1,y=1};local down=false;local held={};local frozen=false;local delayed,holdMatch
local detailTitleFont,detailRules
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('COLLECTION REPLAY PASS '..label)end
local function wait(seconds)wake=elapsed+(seconds or .08);coroutine.yield()end
local function ready(fn,timeout,label)local deadline=elapsed+(timeout or 15);while not fn()do assert(elapsed<deadline,label);wait(.06)end end
local function request(method,path,body)
    local result,problem,done;m:request('catalog',method,path,body,function(data,err)result,problem,done=data,err,true end,true)
    ready(function()return done end,20,'Catalog request timed out: '..path);assert(result,problem or path);return result
end
local function move(x,y)local ox,oy=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-ox,mouse.y-oy);r:mousemoved(x,y)end
local function press(button)
    down=true;S.OnMousePressed(mouse.x,mouse.y,button,false,1)
    if S.IsVoidHovered()then local x,y=Layout.toLogical(mouse.x,mouse.y);r:mousepressed(x,y,button,1)end
end
local function release(button)down=false;S.OnMouseReleased(mouse.x,mouse.y,button,false,1);local x,y=Layout.toLogical(mouse.x,mouse.y);r:mousereleased(x,y,button)end
local function click(box)assert(box,'Expected actual UI control');move(box.x+box.w/2,box.y+box.h/2);wait(.05);press(1);wait(.05);release(1);wait(.14)end
local function section(key)for _,hit in ipairs(r.hits)do if hit.kind=='collection-section'and hit.section==key and hit.y>=239 and hit.y+hit.h<=select(2,Layout.dimensions())then return hit end end end
local function deckHit(id)for _,hit in ipairs(r.hits)do if hit.kind=='deck'and hit.deck.id==id and hit.y>=239 and hit.y+hit.h<=select(2,Layout.dimensions())then return hit end end end
local function capture(name)shots[#shots+1]=name;wait(.15)end
local function text(query)
    click(inputs['collection-query']);held.lctrl=true;S.OnKeyPressed('a','a',false);wait(.04);S.OnKeyReleased('a','a');held.lctrl=false
    S.OnTextInput(query);wait(.35)
end
local function mode(w,h,scale)
    m.settings.resolution=w..'x'..h;m.settings.uiScale=scale;m.settings.renderScale=1;m.settings.vsync=false;prefs:apply(true);wait(.18)
end
local function loadQuery(query)
    m.collectionSearch=query;m:collectionSearchChanged();ready(function()return not m.preconTimer and not m.preconsBusy end,15,'Preconstructed query did not complete');wait(.1)
end
local function replayCheck(label)
    local lastBottom=0;for _,recording in ipairs(m.replays)do
        local button=assert(replayButtons[recording.id]);local entries=assert(replayText[recording.id]);local seen={};local bottom=button.y+button.h
        for _,entry in ipairs(entries)do
            check(entry.x>=button.x+button.w+12,'Replay '..entry.kind..' stays right of Open at '..label)
            check(entry.x+entry.w<=select(1,Layout.dimensions())-23,'Replay '..entry.kind..' stays in the viewport at '..label)
            seen[entry.kind]=true;bottom=math.max(bottom,entry.y+entry.h)
        end
        check(seen.title and seen.status and seen.date,'Replay title, status and date all use the right-hand information column at '..label)
        check(button.y>=lastBottom,'Replay rows do not overlap wrapped information at '..label);lastBottom=bottom
    end
end
local function matPixels()
    local player={id='human',human=true,profile={avatar=refs[1],playmat=refs[1]}}
    m.settings.playmatOpacity=1;local image=m:profileArt(refs[1]);assert(image,'Expected decoded cached profile image')
    local oldScale=Layout.scale;Layout.scale=1;r.worldTransform={x=30,y=20,scale=.5,clip={x=30,y=20,w=100,h=80}}
    local function paint(opacity)
        m.settings.playmatOpacity=opacity
        return Assets.rasterize(180,140,function()
            love.graphics.clear(.1,.12,.14,1);love.graphics.setScissor(35,25,90,70);love.graphics.push();love.graphics.translate(30,20);love.graphics.scale(.5);r:drawPlaymat(player,0,0,200,160);love.graphics.pop()
        end):newImageData()
    end
    local full=paint(1);local faint=paint(.2);local off=paint(0)
    local a,b,c=full:getPixel(80,60);local x,y,z=faint:getPixel(80,60);local p,q,t=off:getPixel(80,60)
    check(math.abs(p-.1)<.01 and math.abs(q-.12)<.01 and math.abs(t-.14)<.01,'Playmat opacity zero leaves actual scene pixels untouched')
    check(math.abs(a-x)+math.abs(b-y)+math.abs(c-z)>.015,'Playmat opacity changes actual cached-art pixels')
    local outside={full:getPixel(31,21)};check(math.abs(outside[1]-.1)<.01 and math.abs(outside[2]-.12)<.01,'World playmat scissor intersects the caller clip and preserves outside pixels')
    local iw,ih=image:getDimensions();local sr,sg,sb=Assets.rasterize(iw,ih,function()love.graphics.setColor(1,1,1,1);love.graphics.draw(image)end):newImageData():getPixel(math.floor(iw/2),math.floor(ih/2))
    check(math.abs(a-(sr*.43+.018*.57))<.08 and math.abs(b-(sg*.43+.029*.57))<.08,'Playmat applies the real dark overlay to contained cached profile art')
    r.worldTransform=nil;Layout.scale=oldScale;m.settings.playmatOpacity=.88
end
local function scenario()
    ready(function()return m.settingsLoaded and m.catalogHealth.ready and m.startersLoaded and m.preconLoaded and m.profileLoaded end,30,'API6 collection initialization did not finish')
    check(m.api.catalogPort==tonumber(os.getenv('LOVE2GATHERING_CATALOG_PORT'))and m.catalogHealth.apiVersion>=6,'Actual Model and HTTP worker load the isolated API6 catalog')
    m.settings.localArtworkOnly=true;m.settings.sfxEnabled=false;m.settings.animations=false;m.settings.particles=false;m.settings.titleFontFamily='Beleren';m.settings.showCardArt=true
    mode(1440,900,1);m:setCollectionFormat('All');m.uiLayout.collection={collapsed={user=false,starter=true,preconstructed=false}};wait(.15)
    check(#m.starterDecks>=10 and m.preconStats.deckCount>=1183,'Real starter lists and full preconstructed catalog load separately')
    check(section('user')and section('starter')and section('preconstructed'),'My Decks, Starter and Preconstructed sections have actual independent header hits')
    local unwanted=false;for _,entry in ipairs(renderedText)do if entry.y>=97 and entry.y<145 and not({Decks=true,Import=true,History=true,['New deck']=true})[entry.text]then unwanted=true end end
    check(not unwanted,'Collection heading has no extra motivational phrase')
    click(section('user'));check(Collection.sections(m).user,'Actual My Decks header collapses its section')
    click(section('starter'));check(not Collection.sections(m).starter,'Actual Starter header expands its section')
    click(section('starter'));click(section('preconstructed'));check(Collection.sections(m).starter and Collection.sections(m).preconstructed,'Starter and Preconstructed headers independently collapse')
    wait(.6);local saved=request('GET','/ui-layout');check(saved.collection.collapsed.user and saved.collection.collapsed.starter and saved.collection.collapsed.preconstructed,'Collapse state persists through the actual SQLite layout endpoint')
    m.uiLayout=nil;m.uiLayout=saved;m.uiLayoutVersion=(m.uiLayoutVersion or 0)+1;wait(.15);check(Collection.sections(m).preconstructed and section('preconstructed'),'Reloading persisted layout restores the collapsed collection sections')
    click(section('starter'));text('Ayara');check(m.collectionSearch=='Ayara','Actual collection search input accepts and dispatches the query')
    local original=assert(m.starterDecks[1]);for _,d in ipairs(m.starterDecks)do if d.id=='starter-commander-ayara-devotion'then original=d end end
    local before=json.encode(original);ready(function()return deckHit(original.id)and m:getArt(m:deckCoverCard(original),true,'art_crop')end,20,'Cached Ayara cover did not load')
    local tile=assert(deckHit(original.id));check(math.abs(tile.w-tile.h)<.001,'Starter deck cover tile is square')
    local art=m:getArt(m:deckCoverCard(original),true,'art_crop');local drawing
    for _,d in ipairs(draws)do if d.image==art and math.abs(d.x-tile.x)<tile.w then drawing=d end end
    check(drawing and drawing.w<=tile.w-9 and drawing.h<=tile.h-90 and math.abs(drawing.w/drawing.h-art:getWidth()/art:getHeight())<.001,'Actual collection art draw contains the complete image with its original aspect ratio')
    local black=false;for _,d in ipairs(manas)do if d.symbol=='B'and math.abs(d.x-tile.x-12)<1 and math.abs(d.y-(tile.y+tile.h-24))<1 then black=true end end
    check(black,'Deck color identity renders a real Mana glyph in the tile footer')
    capture('starter-square-contain-1440');click(tile);ready(function()return buttons['Edit deck']end,3,'Starter details did not open');click(buttons['Edit deck'])
    ready(function()return m.page=='builder'and m.editDeck and m.editDeck.id~=original.id end,20,'Actual Starter Edit did not fork a saved user deck')
    local copy=m.editDeck;check(copy.origin=='user'and copy.id~=original.id,'Actual Starter Edit creates a new user identity')
    check(json.encode(original)==before,'Editing a starter preserves its original source and quantities')
    local stored=request('GET','/decks/'..copy.id);check((stored.deck or stored).id==copy.id,'Forked deck is actually saved and retrievable through the service')
    local source=request('GET','/decks/'..original.id);source=source.deck or source
    check(source.id==original.id and source.origin~='user'and json.encode(source.main)==json.encode(original.main)and json.encode(source.commander)==json.encode(original.commander),'Actual source starter remains unchanged after creating the user fork')
    m.page='decks';m.collectionSearch='Ayara';Collection.sections(m).starter=true;Collection.sections(m).user=false;r.deckScroll=0;wait(.2)
    ready(function()return deckHit(copy.id)end,10,'Saved copy did not appear under My Decks');check(deckHit(copy.id)and copy.name~='', 'Saved starter copy appears as a selectable My Decks tile');capture('my-deck-fork-1440')
    mode(1120,720,1);local small=assert(deckHit(copy.id));local sw,sh=Layout.dimensions()
    check(small.w==small.h and small.x+small.w<sw and small.y+small.h<=sh,'Square My Decks tile remains inside the 1120×720 viewport');capture('my-deck-fork-1120')
    mode(1440,900,1.25);small=assert(deckHit(copy.id));sw,sh=Layout.dimensions()
    check(small.w==small.h and small.x+small.w<sw and small.y+small.h<=sh,'Square My Decks tile remains inside the logical viewport at UI scale 1.25');capture('my-deck-fork-scaled');mode(1440,900,1)
    Collection.sections(m).user=true;Collection.sections(m).preconstructed=false;m.selectedDeck=nil;loadQuery('Calling All Angels')
    check(#m.precons==1 and m.precons[1].name=='Calling All Angels','Actual preconstructed query returns the genuine Calling All Angels product')
    ready(function()return deckHit(m.precons[1].id)end,5,'Preconstructed tile not visible');click(deckHit(m.precons[1].id))
    ready(function()return not m.preconDetailBusy and m.preconDetails and m.preconDetails[m.precons[1].id]end,20,'Actual preconstructed detail did not load')
    local angels=m.preconDetails[m.precons[1].id];check(m.count(angels,'main')==99 and m.count(angels,'commander')==1 and angels.commander[1].name=='Giada, Font of Hope','Real Calling All Angels detail contains 99 main cards plus Giada, Font of Hope')
    check(section('set:Foundations Commander'),'Expansion header groups the actual product under Foundations Commander');capture('precon-angels-1440')
    click(buttons.Packets);ready(function()return m.preconCategory=='packet'and not m.preconsBusy and not m.preconTimer end,20,'Packet category did not complete')
    check(m.preconsTotal==0,'Existing search remains active when switching to the packet category')
    text('');ready(function()return not m.preconsBusy and not m.preconTimer and#m.precons>0 end,15,'Packet listings did not load')
    check(m.precons[1].category=='packet'and m.preconsTotal>=611,'Actual Packets button loads source packet products separately');capture('packets-1440')
    click(buttons['Deck products']);ready(function()return not m.preconsBusy and not m.preconTimer end,15,'Deck products did not reload')
    local first=m.precons[1].id;click(buttons['Next precons']);ready(function()return not m.preconsBusy and not m.preconTimer and m.preconOffset==24 end,15,'Next page did not complete')
    check(m.precons[1].id~=first and#m.precons<=24,'Actual next-page control loads a bounded different preconstructed page')
    -- Hold real completed HTTP responses locally, then publish them after newer
    -- responses; this exercises the model's request identity without a fake API.
    holdMatch='q=Sliver';m.collectionSearch='Sliver';m:refreshPrecons();ready(function()return delayed end,10,'Old query response was not held')
    m.collectionSearch='Calling All Angels';m.preconOffset=0;m:refreshPrecons();ready(function()return not m.preconsBusy and m.precons[1]and m.precons[1].name=='Calling All Angels'end,10,'New query did not win')
    local late=delayed;delayed=nil;holdMatch=nil;late();check(m.precons[1].name=='Calling All Angels','An older real HTTP query cannot overwrite the newer collection query')
    m.collectionSearch='';m.preconOffset=0;holdMatch='offset=0';m:refreshPrecons();ready(function()return delayed end,10,'Old page response was not held')
    m.preconOffset=24;m:refreshPrecons();ready(function()return not m.preconsBusy and m.preconOffset==24 end,10,'New page did not finish');local current=m.precons[1].id
    late=delayed;delayed=nil;holdMatch=nil;late();check(m.precons[1].id==current and m.preconOffset==24,'An older real HTTP page cannot replace the currently requested page')
    m.replays={{id='ui-replay-long',title='Commander with friends: a very long saved recording title that wraps gracefully alongside its Open button and preserves readable match details across narrow windows',format='Commander',status='complete',frameCount=413,createdAt=1794600000000},{id='ui-replay-two',title='Second recording · date and status remain separate',format='Modern',status='pending',frameCount=26,createdAt=1794600300000}};m.replaysTotal=2;m.page='replays';m.openReplay=function(self,id)self.openedRecording=id end
    wait(.2);replayCheck('1440×900');capture('replays-1440');click(replayButtons['ui-replay-long']);check(m.openedRecording=='ui-replay-long','Actual Open button dispatches the selected recording identity without loading frames')
    mode(1120,720,1);wait(.15);replayCheck('1120×720');capture('replays-1120')
    mode(1440,900,1.25);check(Layout.scale==1.25,'Actual native display mode applies UI scale 1.25');wait(.15);replayCheck('1440×900 at 1.25');capture('replays-1440-scaled')
    for _,ref in ipairs(refs)do m:profileArt(ref)end;ready(function()return m:profileArt(refs[1])and m:profileArt(refs[2])end,15,'Genuine cached profile-art HTTP images did not decode')
    check(m:profileArt(refs[1]):getWidth()>100 and m:profileArt(refs[2]):getHeight()>100,'Own and opponent profile art decode from actual cached JPEG responses')
    m.profileQuery='Ayara';m:showProfile();m.profileDraft={name='Local UI preview',avatar=refs[1],playmat=refs[2]};m.profileDirty=false
    ready(function()return not m.profileBusy and not m.profileSearchTimer and#m.profileItems>0 end,15,'Actual profile artwork query did not settle')
    mode(1120,720,1);ready(function()return not m.profileBusy and not m.profileSearchTimer end,10,'Responsive profile query did not finish');wait(.12)
    local _,ph=Layout.dimensions();check(buttons['Save profile']and buttons['Save profile'].y+buttons['Save profile'].h<=ph and buttons.Next.y+buttons.Next.h<=ph,'Profile save and art navigation stay reachable at 1120×720');capture('profile-1120')
    mode(1440,900,1.25);ready(function()return not m.profileBusy and not m.profileSearchTimer end,10,'Scaled profile query did not finish');wait(.12);_,ph=Layout.dimensions()
    check(buttons['Save profile'].y+buttons['Save profile'].h<=ph and buttons.Next.y+buttons.Next.h<=ph,'Profile save and art navigation stay reachable at UI scale 1.25');capture('profile-scaled')
    mode(1440,900,1);m.page='decks';local angel=request('GET','/cards/by-name?name=Angel%20of%20Vitality');angel=angel.card or angel;m.byName[angel.name]=angel
    m.inspectCard={id='details-native-style-angel',name=angel.name,power='5',toughness='5'};m.settings.keywordReminders=true;wait(.2)
    ready(function()return m:getArt(m.inspectCard)and detailTitleFont and detailRules end,10,'Actual inspected card image/title/rules did not render')
    check(detailTitleFont==r.assets:titleFont(22,m.settings),'Actual card-details title uses the supplied Beleren display font')
    check(detailRules:find('Flying (',1,true)and detailRules:find('If you would gain life',1,true),'Actual card details add the short parenthetical keyword reminder while retaining full supplied rules');capture('beleren-keyword-details-1440')
    m.settings.keywordReminders=false;wait(.12);check(not detailRules:find('Flying (',1,true)and detailRules:find('Flying',1,true),'Disabling keyword reminders restores the supplied card rules in the actual details view')
    click(buttons['Close details']);check(not m.inspectCard,'Actual card-details close button dismisses the inspected card');m.settings.keywordReminders=true
    mode(1440,900,1);matPixels();frozen=true;m.page='table';m.game={gameId='PROFILE-RENDERING-FIXTURE',revision=1,format='Commander',running=true,turn=3,phase='PRECOMBAT_MAIN',step='PRECOMBAT_MAIN',activePlayerId='human',players={}}
    for i=1,2 do m.game.players[i]={id=i==1 and'human'or'opponent',name=i==1 and'Own profile'or'Opponent profile',human=i==1,life=i==1 and 17 or 31,hand={},battlefield={},graveyard={},exile={},command={},libraryCount=90,handCount=0,profile={avatar=refs[i],playmat=refs[i]}}end
    m.profile={name='Local UI fixture',avatar=refs[1],playmat=refs[1]};wait(.2);capture('duel-profile-mats')
    check(m.game.players[1].life==17 and m.game.players[2].life==31,'Duel presentation preserves the supplied native-style life values')
    for i=3,4 do m.game.players[i]={id='seat'..i,name='Profile seat '..i,human=false,life=i==3 and 40 or 7,hand={},battlefield={},graveyard={},exile={},command={},libraryCount=90,handCount=0,profile={avatar=refs[(i-1)%2+1],playmat=refs[(i-1)%2+1]}}end
    m.game.gameId='PROFILE-FOUR-RENDERING-FIXTURE';wait(.2);r.tableCamera:overview(true);wait(.2);capture('four-seat-profile-mats')
    check(m.game.players[3].life==40 and m.game.players[4].life==7,'Four-seat profile presentation preserves each supplied life value')
    m.game=nil;m.page='decks';frozen=false;m.uiLayoutTimer=nil
    local file=assert(io.open('/tmp/love2gathering-collection-replay-ui-report.json','w'));file:write(json.encode({passed=true,checks=checks,scope='Actual frontend Model/API6/Slab collection requests, SQLite fork/layout writes and real cached JPEGs; stale real HTTP callback publication; synthetic replay metadata/Open dispatch only and synthetic duel/four-seat profiles for presentation, no native game/rules claims',captures=shots.completed,createdCopyCount=#created,frames=frame}));file:close();print('COLLECTION REPLAY COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.errorhandler(message)io.stderr:write('COLLECTION REPLAY FAILED '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
function love.load()
    refs=json.decode(love.filesystem.read('profile-art.json'));S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Region=require('lib.Slab.Internal.UI.Region')
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(b)return b==1 and down end;love.keyboard.isDown=function(...)for i=1,select('#',...)do if held[select(i,...)]then return true end end;return false end
    m=Model.new();r=Renderer.new(m);v=View.new(S,m,r);prefs=Preferences.new(m,S,r);v.preferences=prefs
    local original=m.request;m.request=function(self,service,method,path,body,callback,quiet)
        requests[#requests+1]={method=method,path=path}
        return original(self,service,method,path,body,function(data,err,failed)
            if method=='POST'and path:match('^/decks/.+/fork$')and data then
                local d=data.deck or data;created[#created+1]=d.id;local f=assert(io.open(os.getenv('LOVE2GATHERING_UI_CREATED_IDS'),'w'));f:write(json.encode(created));f:close()
            end
            if holdMatch and path:match('^/precons%?')and path:find(holdMatch,1,true)and not delayed then delayed=function()if callback then callback(data,err,failed)end end
            elseif callback then callback(data,err,failed)end
        end,quiet)
    end
    local function bounds()local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();return{x=x+dx,y=y+dy,w=w,h=h}end
    for _,name in ipairs({'Button','Input','Textf','Text'})do local original=S[name];S[name]=function(label,options)
        local result=original(label,options);local box=bounds()
        if name=='Button'then buttons[label]=box;if label=='Open recording'then replayButtons[idStack[#idStack]]=box end
        elseif name=='Input'then inputs[label]=box
        elseif name=='Textf'and m.inspectCard and label=='Angel of Vitality'then detailTitleFont=S.GetStyle().Font
        elseif m.page=='replays'and idStack[#idStack]then
            local kind=name=='Textf'and(tostring(label):find('frames',1,true)and'status'or'title')or'date';box.kind=kind;local id=idStack[#idStack];replayText[id]=replayText[id]or{};replayText[id][#replayText[id]+1]=box
        end
        return result
    end end
    local push,pop=S.PushID,S.PopID;S.PushID=function(id)idStack[#idStack+1]=id;return push(id)end;S.PopID=function()idStack[#idStack]=nil;return pop()end
    local draw=love.graphics.draw;love.graphics.draw=function(image,x,y,angle,sx,sy,...)
        if m.page=='decks'and type(x)=='number'and image.typeOf and image:typeOf('Image')then draws[#draws+1]={image=image,x=x,y=y,w=image:getWidth()*(sx or 1),h=image:getHeight()*(sy or sx or 1)}end
        return draw(image,x,y,angle,sx,sy,...)
    end
    local mana=r.assets.mana;r.assets.mana=function(self,symbol,x,y,...)if m.page=='decks'then manas[#manas+1]={symbol=symbol,x=x,y=y}end;return mana(self,symbol,x,y,...)end
    local RichText=require('app.richtext');local slab=RichText.slab;RichText.slab=function(view,id,text,...)
        if id=='inspected-rules'then detailRules=text end
        return slab(view,id,text,...)
    end
    for _,name in ipairs({'text','strong'})do local original=r[name];r[name]=function(self,text,x,y,...)
        if m.page=='decks'then renderedText[#renderedText+1]={text=tostring(text),x=x,y=y}end
        return original(self,text,x,y,...)
    end end
    runner=coroutine.create(scenario);shots.completed={}
end
function love.update(dt)
    elapsed=elapsed+dt;frame=frame+1;assert(elapsed<120,'Collection/replay acceptance exceeded 120 seconds')
    if frozen then m.api:update()else m:update(dt)end;prefs:update();S.Update(dt);r:update(dt)
    if elapsed>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
    buttons={};inputs={};replayButtons={};replayText={};v:build();r.uiHovered=not S.IsVoidHovered()
end
function love.draw()
    draws={};manas={};renderedText={};prefs:beginFrame();r:draw();prefs:endScene();S.Draw();prefs:endFrame()
    if#shots>0 then local name=table.remove(shots,1);local path='/tmp/love2gathering-collection-'..name..'.png';shots.completed[#shots.completed+1]=path
        love.graphics.captureScreenshot(function(data)local f=assert(io.open(path,'wb'));f:write(data:encode('png'):getString());f:close()end)
    end
end
function love.quit()m.game=nil;m.uiLayoutTimer=nil;m.api:quit();prefs:quit();S.OnQuit()end
