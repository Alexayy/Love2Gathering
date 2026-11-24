-- Deterministic queue/entitlement contracts; no HTTP, downloaded bytes or GPU.
package.path='./?.lua;'..package.path
local clock=0;love={timer={getTime=function()return clock end}}
local Model={};Model.__index=Model;function Model:update()end
require('app.game_art').install(Model);require('app.activity').install(Model)
local checks=0;local function check(ok,label)assert(ok,label);checks=checks+1;print('GAME ART PASS '..label)end
local calls,images={},{};local handReady=false
local m=setmetatable({page='table',catalogHealth={ready=true},byName={},settings={localArtworkOnly=true},activeDeckId='own',
    game={gameId='one',running=true,localPlayerId='me',players={{id='me',human=true,hand={{id='hand-id',ownerId='me',name='Forest',selectedPrintingId='my-forest'}}},{id='foe',human=true,hand={{name='Secret enemy card'}}}}},
    deck={main={{name='Forest',count=99},{name='Own spell',count=1}},commander={},sideboard={},printingSelections={{name='Forest',zone='main',printingId='my-forest'}}}},Model)
function m:findDeck(id)return id=='own'and self.deck end
function m:rememberCard(card)self.byName[card.name]=card end
function m:prompt()return nil end
function m:getArt(card,force,kind,options)
    images[#images+1]={card=card,force=force,kind=kind,options=options}
    return handReady and{}or nil,handReady and'ready'or'loading'
end
m.api={pendingDetails={},request=function(_,service,method,path,body,callback,_,options)
    calls[#calls+1]={service=service,method=method,path=path,body=body,options=options,callback=callback}
    if method=='GET'then
        local name=path:find('my%-forest')and'Forest'or path:match('name=(.*)')or'Unknown'
        name=name:gsub('%%(%x%x)',function(h)return string.char(tonumber(h,16))end)
        callback({name=name,id='oracle-'..name,printing_id=path:find('my%-forest')and'my-forest'or'print-'..name,image_uris={}},nil,200)
    else callback({cached=true},nil,200)end
end}
m:update(0);check(#calls==1 and calls[1].options.priority=='handMetadata','Exact hand metadata gets a reserved lane before background work')
m:update(0);check(#images==1 and images[1].card.printing_id=='my-forest'and images[1].options.network and images[1].options.priority=='hand'and images[1].force,'Own hand forces the exact edition online despite Cache only')
check(m.gameArtwork.handPending==1 and #calls==1,'A waiting hand prevents background deck requests')
local busy=m:activityState();check(busy.kind=='images'and busy.busy and busy.progress==0,'Pending hand images have a truthful activity state')
handReady=true
for _=1,120 do m:update(0)end
local downloads,names,valid,private=0,{},true,true
for _,call in ipairs(calls)do if call.method=='POST'then downloads=downloads+1;names[call.body.printingId]=true;valid=valid and call.path=='/art/download'and(call.body.kind=='normal'or call.body.kind=='art_crop')end end
check(valid,'Background acquisition writes disk cache without decoding a deck of GPU textures')
check(downloads==15 and names['my-forest']and names['print-Own spell']and names['print-Wastes'],'Own selected edition, own deck and six default basics are cached once per kind')
for _,call in ipairs(calls)do private=private and not call.path:find('enemy')and not(call.body and tostring(call.body.printingId):find('enemy'))end
check(private,'Other human hand identities are excluded from warmup')
check(m.gameArtwork.phase=='ready'and m:activityState().busy==false,'Completed warmup is an ordinary player wait, not a loading spinner')
local old=m.gameArtWarmup;m.game={gameId='two',running=true,localPlayerId='me',players={{id='me',human=true,hand={}}}};m:update(0)
check(m.gameArtWarmup~=old and not images[1].options.isCurrent(),'New native game identity invalidates the previous warmup callbacks')
m.replay={};m:update(0);check(m.gameArtWarmup==nil and m:activityState()==nil,'Replay never starts network warmup or live activity')
m.replay=nil;m.game.players={{id='a',human=true,hand={{name='A'}}},{id='b',human=true,hand={{name='B'}}}};m.game.localPlayerId=nil;m:update(0)
check(m.gameArtwork==nil,'Ambiguous multi-human projections fail closed instead of choosing another player hand')
m.game.players={{id='observer-other',human=true,isLocal=false,hand={{name='Private card'}}}};m:update(0)
check(m.gameArtwork==nil,'An explicitly nonlocal human is not treated as a legacy local hand')
m.actionBusy=true;local first=m:activityState();clock=2;local second=m:activityState();check(first.kind=='action'and second.elapsed==2,'Accepted-action wait uses stable elapsed time')
m.actionBusy=false;m.polling=true;m.api.pendingDetails[1]={service='engine',path='/session/state',started=1};local delayed=m:activityState()
check(delayed.kind=='engine'and delayed.busy,'Only a genuinely delayed native state read shows engine activity')
m.api.pendingDetails[1].started=clock;check(m:activityState().kind=='opponent','Ordinary fast state polling does not flash a busy cursor')
m.game.prompt={id='accepted'};m.answeredPrompt='accepted';check(m:activityState().busy and m:activityState().label:find('advance',1,true),'An accepted answer awaiting a new native prompt remains visibly pending')
m.game.prompt=nil;m.answeredPrompt=nil;m.game.priority={pending=true};check(m:activityState().busy and m:activityState().label:find('priority',1,true),'An acknowledged pending priority transition is not shown as an ordinary opponent wait')
-- Use the actual artwork identity/status cache to prove warmup and ordinary
-- rendering share the ready texture, including an earlier Cache-only miss.
local Artwork=require('app.artwork')
love.graphics={newImage=function()return{getDimensions=function()return 100,140 end}end};love.image={newImageData=function(data)return data end};love.filesystem={newFileData=function(data)return data end}
local pending={};local normal={name='Plains',id='plains-oracle',printing_id='plains-print',image_uris={}}
local native={id='native-plains',name='Plains',ownerId='local'}
local cache=setmetatable({page='table',settings={localArtworkOnly=true},byName={Plains=normal},art={},catalogHealth={ready=true},game={gameId='cache-reuse',running=true,localPlayerId='local',players={{id='local',hand={native}}}}},Model)
function cache:cardData(card)return card.image_uris and card or self.byName[card.name]end
function cache:getArt(card,force,kind,options)return Artwork.get(self,card,force,kind,nil,options)end
cache.api={request=function(_,service,method,path,body,callback,_,options)pending[#pending+1]={path=path,callback=callback,options=options}end}
cache:getArt(native,true);pending[1].callback(nil,nil,404)
cache:updateGameArtwork()
check(#pending==2 and pending[2].options.priority=='hand','Hand acquisition immediately upgrades the ordinary Cache-only negative entry')
pending[2].callback('decoded-cache-fixture',nil,200)
local ready=cache:getArt(native,true)
check(ready and #pending==2,'The ordinary table reuses the warmed ready texture without another request or negative-cache delay')
local valid=pending[2].options.isCurrent
cache.api.routeGeneration=1;check(not valid(),'An API route change invalidates hand callbacks before the next model update')
cache.api.routeGeneration=0;cache.roomConnectionId='another-local-seat';check(not valid(),'Another seat in the same native game cannot adopt the previous hand callback')
cache.roomConnectionId=nil;cache.game.localPlayerId='unentitled';check(not valid(),'Losing the unique local perspective immediately invalidates pending hand work')
cache.game.localPlayerId='local';cache.storageLocationBlocked=true;cache:updateGameArtwork()
check(not valid()and cache.gameArtWarmup==nil and #pending==2,'Preparing a storage move stops new warmup requests and invalidates its callbacks')

-- Scryfall returns the combined name even when XMage names only the visible face.
local LiveModel=require('app.model')
local front,back='Delver of Secrets','Insectile Aberration'
local whole=front..' // '..back
local function payload(face)
    return {id='delver-oracle',name=whole,printing_id='delver-print',layout='transform',requested_face=face,
        image_uris={normal='front'},card_faces={{name=front,image_uris={normal='front'}},{name=back,image_uris={normal='back'}}}}
end
local localHand={{id='front-object',name=front},{id='back-object',name=back}}
local faces=setmetatable({settings={localArtworkOnly=true},byName={},lookupPending={},art={},catalogHealth={ready=true},
    game={gameId='faces',running=true,localPlayerId='p',players={{id='p',hand=localHand}}}},LiveModel)
local metadataReads,scanRequests,cropFaces=0,{},{}
faces.api={request=function(_,service,method,path,body,callback)
    if service=='art' then
        scanRequests[#scanRequests+1]=path;callback('scan-fixture',nil,200)
    elseif method=='POST' then
        if body.kind=='art_crop' then cropFaces[body.face]=true end
        callback({},nil,200)
    elseif path:match('^/cards/') then
        metadataReads=metadataReads+1
        local face
        if path:find('Insectile',1,true) then face=1 elseif path:find('Delver',1,true) then face=0 end
        callback(payload(face),nil,200)
    end
end}
faces:cardData(localHand[2])
check(faces:cardData(localHand[2]).requested_face==1 and metadataReads==1 and not faces.byName[whole],
    'Back-face inspection caches the successful face-name lookup once and leaves the canonical name independent')
faces:rememberCard(payload(nil))
faces:cardData(localHand[1])
local frontData,backData=faces:cardData(localHand[1]),faces:cardData(localHand[2])
check(frontData.requested_face==0 and backData.requested_face==1 and metadataReads==2 and faces.byName[whole].requested_face==nil,
    'Canonical, front and back names retain their independent face selections')
faces:getArt(localHand[1],true);faces:getArt(localHand[2],true)
check(#scanRequests==2 and scanRequests[1]:find('face=0&',1,true) and scanRequests[2]:find('face=1&',1,true),
    'The same double-faced printing loads distinct original scans for each native face')
localHand[1].selectedPrintingId='delver-print';localHand[2].selectedPrintingId='delver-print'
for _=1,6 do faces:updateGameArtwork()end
local exactFaces={}
for _,path in ipairs(scanRequests)do
    if path:find('exact=1',1,true) then exactFaces[tonumber(path:match('face=(%d+)'))]=true end
end
check(faces.gameArtwork.handTotal==2 and faces.gameArtwork.handReady==2 and #scanRequests==4
    and exactFaces[0] and exactFaces[1],
    'Exact-hand warmup distinguishes native face names sharing one selected printing ID')
check(cropFaces[0] and cropFaces[1],'Disk warmup also retains the selected face for each crop')
print('Game artwork/activity checks: '..checks)
