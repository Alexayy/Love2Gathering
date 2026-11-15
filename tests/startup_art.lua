-- Actual LÖVE image decoding and production Model/Artwork caches, with synthetic
-- local-service replies. No user storage, remote acquisition or engine is used.
local Model=require('app.model')
local Warm=require('app.startup_art')
local json=require('lib.json')
local checks,requests={},{}
local output=os.getenv('LOVE2GATHERING_STARTUP_ART_OUTPUT')
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('STARTUP ART PASS '..label)end
local function card(name,id)return{name=name,id='oracle-'..id,printing_id=id,image_uris={art_crop='fixture-only'},oracle_text='Fixture metadata'}end
local function fixture(decks,folds)
    local m=setmetatable({settings={localArtworkOnly=false,showCardArt=true},profile={},page='decks',format='Modern',decks=decks or{},catalogHealth={ready=true},uiLayout={collection={collapsed=folds or{starter=true}}},byName={},lookupPending={},art={},artPending=0,toasts={}},Model)
    m.calls={};m.time=0
    m.api={request=function(_,service,method,path,body,callback,binary)
        check(method=='GET'and body==nil,'Warmup uses a read-only local route')
        if service=='art'then check(path:find('network=0',1,true)~=nil,'Warmup disables remote image access despite saved online preference')end
        local call={service=service,method=method,path=path,callback=callback,binary=binary}
        m.calls[#m.calls+1]=call;requests[#requests+1]={service=service,method=method,path=path};return true
    end}
    return m,Warm.new({clock=function()return m.time end,timeout=2})
end
local function reply(m,match,body,err,code)
    for _,call in ipairs(m.calls)do if not call.done and(not match or call.path:find(match,1,true))then call.done=true;call.callback(body,err,code or 200);return call end end
    error('Missing fixture route: '..tostring(match))
end
local function fill(m,bytes)
    for _,call in ipairs(m.calls)do if not call.done and call.service=='art'then call.done=true;call.callback(bytes,nil,200)end end
end
local displayed
function love.load()
    local ok,problem=xpcall(function()
        local jpeg=assert(love.filesystem.read('assets/card-backs/classic-magic.jpg'))
        local decks={};for i=1,12 do decks[i]={id='user-'..i,origin='user',name='Visible '..i,format='Modern',cover=card('Cover '..i,'print-'..i)}end
        decks[#decks+1]={id='other-format',origin='user',format='Commander',name='Filtered',cover=card('Filtered','filtered')}
        local m,warm=fixture(decks);m.profile.avatar={printingId='avatar-printing',face=1,name='Saved avatar'}
        local state=warm:update(m)
        check(not state.ready and state.cached==0,'The optional gate waits for delayed cached JPEG replies')
        check(#warm.items==9,'At most eight relevant deck covers plus the saved avatar are selected')
        local count=#m.calls;warm:update(m);check(#m.calls==count,'Repeated startup frames deduplicate pending local reads')
        fill(m,jpeg);state=warm:update(m);fill(m,jpeg);state=warm:update(m)
        check(state.ready and state.cached==9 and not state.timedOut and state.missing==0,'All cached JPEGs are decoded before the optional gate completes')
        check(state.progress==1 and m.settings.localArtworkOnly==false,'Completion leaves the saved artwork preference unchanged')
        local before=#m.calls;local avatar=m:profileArt(m.profile.avatar);local cover=m:getArt(decks[1].cover,true,'art_crop')
        check(avatar and cover and# m.calls==before,'The first normal avatar and deck draw reuse the exact warmed image caches')
        check(m.profileImages['avatar-printing:1'].image==avatar,'Profile printing and face identity are retained')
        for _,call in ipairs(m.calls)do check(not call.path:find('filtered',1,true)and not call.path:find('/precons',1,true),'Warmup does not browse filtered formats or historical products')end
        displayed={avatar=avatar,cover=cover}

        local miss,wm=fixture({{id='missing',origin='user',name='Missing',format='Modern',cover=card('Missing','missing')}})
        wm:update(miss);reply(miss,'/art/',nil,nil,404);local absent=wm:update(miss)
        check(absent.ready and absent.missing==1 and absent.cached==0 and not absent.error and not absent.timedOut,'A legitimate cache 404 permits entry without claiming the image was cached')

        local failed,wf=fixture({{id='error',origin='user',name='Failed image',format='Modern',cover=card('Error','error')}})
        wf:update(failed);reply(failed,'/art/',nil,'Fixture timeout',0);local bad=wf:update(failed)
        check(bad.ready and bad.failed==1 and bad.error:find('Failed image',1,true)and bad.cached==0,'A transport failure is surfaced as an optional artwork error')

        local slow,ws=fixture({{id='slow',origin='user',name='Slow',format='Modern',cover=card('Slow','slow')}})
        ws:update(slow);slow.time=2.1;local late=ws:update(slow)
        check(late.ready and late.timedOut and late.pending==1 and late.cached==0 and late.message:find('still pending',1,true),'The bounded wait reports pending work explicitly instead of claiming artwork readiness')
        reply(slow,'/art/',jpeg);local lateImage=slow:getArt(slow.decks[1].cover,true,'art_crop')
        check(lateImage~=nil,'A late cached JPEG still fills the normal view cache after the optional deadline')

        local exact,we=fixture({{id='chosen',origin='user',name='Chosen Forest',format='Modern',coverCard='Forest',main={{name='Forest',count=1}},printingSelections={{zone='main',name='Forest',printingId='chosen-forest',count=1}}}})
        exact:rememberCard(card('Forest','default-forest'));we:update(exact)
        check(#exact.calls==1 and exact.calls[1].path=='/cards/chosen-forest?printing=chosen-forest','A deck cover resolves the saved chosen printing rather than substituting default art')
        reply(exact,'/cards/',card('Forest','chosen-forest'));we:update(exact)
        local route=exact.calls[#exact.calls].path
        check(route:find('printing=chosen-forest',1,true)and route:find('exact=1',1,true)and not route:find('default-forest',1,true),'The cached art request preserves exact selected printing identity')
        reply(exact,'/art/',jpeg);check(we:update(exact).cached==1,'Exact selected cover art is prepared through production printing metadata')
        local originalCalls=#exact.calls
        check(exact:getArt(exact:deckCoverCard(exact.decks[1]),true,'art_crop')~=nil and#exact.calls==originalCalls,'The normal selected-edition deck cover reuses the warmed cache key')

        local starter,wt=fixture({{id='old',origin='bundled',format='Modern',name='Owned starter override',cover=card('Old','old')}},{})
        wt:update(starter);check(starter.calls[1].path=='/decks?origin=starter','An open Starter section loads the bounded explicit-template endpoint')
        reply(starter,'/decks?',{decks={{id='template',origin='starter',format='Modern',name='Original starter',cover=card('Original','original')}}})
        wt:update(starter);check(starter.startersLoaded and#wt.items==1 and wt.items[1].label=='Original starter','Original Starter templates supersede the legacy override before choosing visible covers')
        fill(starter,jpeg);check(wt:update(starter).cached==1,'The explicit Starter cover is ready for the first collection frame')
        local hidden,wh=fixture({}, {user=true,starter=true,preconstructed=true});check(wh:update(hidden).ready and#hidden.calls==0,'Collapsed empty groups need no metadata or artwork requests')
        local offline,wo=fixture({{id='unindexed',origin='user',format='Modern',name='Unknown',main={{name='Unindexed'}}}})
        offline.catalogHealth.ready=false;wo:update(offline);offline.time=2.1
        check(wo:update(offline).timedOut and#offline.calls==0,'Missing local metadata has a bounded optional wait and never triggers a remote fallback')
    end,debug.traceback)
    if not ok then print(problem);if output then local f=assert(io.open(output..'/failure.txt','w'));f:write(problem);f:close()end;love.event.quit(1);return end
end
function love.draw()
    if not displayed then return end
    love.graphics.clear(.025,.035,.06,1);love.graphics.setColor(1,1,1,1)
    love.graphics.print('First normal frame: avatar and cover already decoded from local cache',24,20)
    for i,key in ipairs({'avatar','cover'})do local image=displayed[key];love.graphics.draw(image,24+(i-1)*180,64,0,150/image:getWidth(),205/image:getHeight());love.graphics.print(key,24+(i-1)*180,284)end
    displayed=nil
    if output then love.graphics.captureScreenshot(function(data)
        local f=assert(io.open(output..'/first-cached-art-frame.png','wb'));f:write(data:encode('png'):getString());f:close()
        local report=assert(io.open(output..'/report.json','w'));report:write(json.encode({checks=checks,requests=requests,capture=output..'/first-cached-art-frame.png',scope='Actual LÖVE JPEG decode and production Model/Artwork identity caches; synthetic local responses; no user data, acquisition or engine'}));report:close();love.event.quit(0)
    end)else love.event.quit(0)end
end
