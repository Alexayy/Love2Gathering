package.path='./?.lua;'..package.path
local calls={}
package.preload['app.api']=function()return{new=function()return{request=function(_,s,m,p,b,cb)calls[#calls+1]={service=s,method=m,path=p,body=b,callback=cb}end}end,escape=function(s)return tostring(s):gsub('([^%w%-_%.~])',function(c)return string.format('%%%02X',c:byte())end)end}end
love={math={random=function()return 1234 end}}
local Model=require('app.model');local Collection=require('app.collection');local n=0
local function check(value,message)assert(value,message);n=n+1;print('COLLECTION PASS '..message)end
local function model()calls={};return Model.new()end
local function deck(id,origin)return{id=id,origin=origin,name=id,format='Modern',main={{name='Forest',count=60}},sideboard={},commander={}}end
local m=model();check(Collection.sections(m).starter==true,'Starter starts collapsed without hiding My Decks')
m:toggleCollectionSection('user');check(Collection.sections(m).user and m.uiLayoutTimer,'Section collapse is queued for SQLite layout persistence')
m:toggleCollectionSection('user');check(Collection.sections(m).user==false,'An explicitly expanded section survives defaults')
m.collectionSearch='Angel & Elf';m:refreshPrecons();local old=calls[#calls]
check(old.path:find('limit=24',1,true)and old.path:find('Angel%20%26%20Elf',1,true),'Precon requests remain paged and encode the query')
m.collectionSearch='Goblin';m:collectionSearchChanged();old.callback({decks={{id='old'}},total=10})
check(not m.precons,'Editing a query immediately fences the old response before debounce')
m:refreshPrecons();calls[#calls].callback({decks={deck('fresh','preconstructed')},total=59})
check(m.precons[1].id=='fresh'and m.preconsTotal==59,'Current page adopts the server total without loading every deck')
m:setCollectionFormat('Brawl');check(m.format=='Modern'and Collection.format(m)=='Brawl','Historical browsing never selects an unsupported practice game format')
m:refreshPrecons();check(calls[#calls].path:find('format=Brawl',1,true),'Historical product formats reach the catalog filter')
m.preconCategory='packet';m:refreshPrecons();check(calls[#calls].path:find('category=packet',1,true),'Half-deck packets remain an explicit product category')
m=model();m.starterDecks={deck('starter-original','bundled')};check(m:findDeck('starter-original').id=='starter-original','Immutable Starter aliases stay selectable without shadowing user decks')
local source=deck('starter-original','bundled');m:openDeck(source);local request=calls[#calls]
check(request.method=='POST'and request.path=='/decks/starter-original/fork'and not m.editDeck,'Editing an original first creates a user copy')
request.callback({deck=deck('my-copy','user'),saved=true})
check(m.editDeck.id=='my-copy'and source.id=='starter-original'and m.editDeck.origin=='user','The builder adopts the actual user identity and preserves the original')
m=model();local archive=deck('old-precon','preconstructed');archive.format='Archive';m:openDeck(archive)
check(m.archiveCopy and#calls==0,'An archive asks for a supported target format before copying')
m.archiveCopy=nil;m:forkCollectionDeck(archive,'Modern',function(d)m:openDeck(d)end)
local failed=deck('repair-copy','user');calls[#calls].callback({saved=false,deck=failed,validation={saveAllowed=false,errors={{message='Named card is not legal'}}},error='Named card is not legal'},nil,422)
check(m.editDeck.id=='repair-copy'and m.dirty and#(m.decks or{})==0,'Illegal archival copies retain every card locally for repair without claiming a saved deck')
m=model();m:selectCollectionDeck(deck('source-one','preconstructed'));local first=calls[#calls]
m:selectCollectionDeck(deck('source-two','preconstructed'));local second=calls[#calls]
first.callback(deck('source-one','preconstructed'));check(not(m.preconDetails or{})['source-one']and m.preconDetailBusy,'Stale detail responses cannot replace a newer selection')
second.callback(deck('source-two','preconstructed'));check(m:collectionDeck('source-two').name=='source-two'and not m.preconDetailBusy,'Current source details remain separate from saved decks')

m=model();m:openDeck(deck('owned-A','user'));m.dirty=true;m:saveDeck();local pendingSave=calls[#calls]
m:openDeck(deck('owned-B','user'));m.selectedDeck='owned-B';m.editDeck.name='B has later unsaved edits';m.dirty=true
pendingSave.callback({id='saved-A',origin='user',draft=false,validation={playable=true}})
check(m.editDeck.id=='owned-B'and m.editDeck.name=='B has later unsaved edits'and m.dirty and m.selectedDeck=='owned-B'and calls[#calls].path=='/decks','A delayed save refreshes storage without rewriting a different open deck or clearing its edits')

for _,field in ipairs({'name','coverCard'})do
    m=model();m:openDeck(deck('pending-'..field,'user'));m.dirty=true;m:saveDeck();pendingSave=calls[#calls]
    local later='Later '..field
    if field=='name'then m.editDeck.name=later;m.dirty=true else m:setDeckCover({name=later})end
    pendingSave.callback({id='saved-'..field,origin='user',draft=false,validation={playable=true}})
    check(m.editDeck.id=='saved-'..field and m.editDeck[field]==later and m.dirty,'A completed save adopts its new ID while preserving later unsaved '..field..' changes')
end

m=model();local unfinished=deck('owned-draft','user');unfinished.draft=true;m.decks={unfinished};m:useCollectionDeck(unfinished)
check(m.page=='builder'and m.editDeck.id=='owned-draft'and not m.playerDeckId,'Using an owned unfinished deck opens the builder before entering the lobby')

m=model();m.catalogHealth.ready=true;m.decks={deck('available-bot','bundled')};m:updateCollection(.1)
local rawStarter=deck('starter-channel-response','bundled');local starterLoad
for _,call in ipairs(calls)do if call.path=='/decks?origin=starter'then starterLoad=call end end
assert(starterLoad and getmetatable(rawStarter.commander)==nil and getmetatable(rawStarter.sideboard)==nil,'Starter fixture must represent raw channel tables')
starterLoad.callback({decks={rawStarter}});m:useCollectionDeck(m.starterDecks[1]);m:startGame();local start
for _,call in ipairs(calls)do if call.path=='/session/start'then start=call end end
local encoded=start and require('lib.json').encode(start.body.deck)
check(start and start.body.deck.id==rawStarter.id and encoded:find('"commander":[]',1,true)and encoded:find('"sideboard":[]',1,true),'Loaded Starter aliases reach native Start with true empty zone arrays after channel metatables are lost')

for _,rejected in ipairs({false,true})do
    m=model();m.selectedDeck='starter-delayed';m:openDeck(deck('starter-delayed','bundled'));local pendingCopy=calls[#calls]
    m:openDeck(deck('later-editor','user'));m.editDeck.name='Later editor edits';m.dirty=true
    if rejected then
        pendingCopy.callback({saved=false,deck=deck('unsaved-repair','user'),validation={saveAllowed=false,errors={{message='Named card is not legal'}}},error='Named card is not legal'},nil,422)
    else pendingCopy.callback({saved=true,deck=deck('persisted-copy','user')})end
    local preserved=rejected and#(m.decks or{})==0 or not rejected and m:findDeck('persisted-copy')~=nil
    check(m.editDeck.id=='later-editor'and m.editDeck.name=='Later editor edits'and m.dirty and preserved,'A delayed copy '..(rejected and'rejection'or'success')..' cannot replace a later editor or misstate persisted ownership')
end

m=model()
local function loadDetail(index)
    local source=deck('precon-cache-'..index,'preconstructed');m:selectCollectionDeck(source);calls[#calls].callback(source)
end
for index=1,16 do loadDetail(index)end
m:selectCollectionDeck(deck('precon-cache-1','preconstructed'))
for index=17,20 do loadDetail(index)end
local cached=0;for _ in pairs(m.preconDetails or{})do cached=cached+1 end
check(cached<=16 and m.preconDetails['precon-cache-1']and not m.preconDetails['precon-cache-2']and m:collectionDeck('precon-cache-20').main[1].count==60,'Full product details use a bounded LRU while preserving recently inspected and current complete lists')
print('Collection model checks: '..n..' passed')
