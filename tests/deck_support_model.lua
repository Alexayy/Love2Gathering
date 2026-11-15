package.path='./?.lua;'..package.path
local Support=require('app.deck_support');local calls={};local checks=0
local function check(ok,label)assert(ok,label);checks=checks+1;print('SUPPORT PASS '..label)end
local Model={update=function()end};Support.install(Model)
local function model()
 calls={};return setmetatable({api={enginePort=17372,catalogPort=17472},engineHealth={ok=true,instanceId='actual-native-instance'},catalogHealth={ready=true,deckSupport={available=true},storage={dataDirectory='/tmp/isolated'}},request=function(_,service,method,path,body,cb)calls[#calls+1]={service=service,method=method,path=path,body=body,callback=cb}end},{__index=Model})
end
local m=model();local d={id='owned',main={}}
check(m:deckSupport(d).state=='unknown','No installed registry is an honest unknown')
m:updateDeckSupport(.1);check(#calls==1 and calls[1].path=='/capabilities/cards','Actual native health ok=true starts one asynchronous registry request')
local old=calls[1];m:updateDeckSupport(.1);check(#calls==1,'Frames do not refetch an in-flight registry')
local revision=string.rep('a',64);old.callback({engineRevision=string.rep('b',40),registryRevision=revision,names={'Forest'},splitNameFallback=true})
check(calls[2].service=='catalog'and calls[2].method=='POST'and calls[2].body.names[1]=='Forest','Installed names transfer once to local metadata service')
calls[2].callback({registryRevision=revision,generation=1,state='checking'})
check(m:deckSupport(d).state=='checking','Verified registry with pending deck remains checking')
m:updateDeckSupport(1);local batch
for _,c in ipairs(calls)do if c.path=='/engine-support/decks'then batch=c end end
check(batch and#batch.body.ids==1,'Only requested visible deck identities enter a bounded batch')
batch.callback({status={registryRevision=revision,generation=1,state='ready'},decks={owned={registryRevision=revision,generation=1,state='unavailable',missingNames={'Missing card'},fingerprint='f'}}})
check(m:deckSupport(d).missingNames[1]=='Missing card','Named installed implementation gaps reach deck presentation')
check(m:deckSupport({id='owned',engineSupport={registryRevision=revision,generation=1,fingerprint='different',state='checking'}}).state=='checking','Changed deck composition never borrows a stale cached result')
m.engineHealth.instanceId='replacement';check(m:deckSupport(d).state=='unknown','Same-port JVM replacement invalidates old results immediately')
m:updateDeckSupport(.1);check(calls[#calls].path=='/capabilities/cards','New native instance starts its own registry generation')
local count=#calls;old.callback({engineRevision=string.rep('c',40),registryRevision=string.rep('d',64),names={'Wrong'}})
check(#calls==count,'Late native registry cannot overwrite a new instance')
m=model();m:updateDeckSupport(.1);local current=calls[1];m.api.catalogPort=17473;current.callback({engineRevision=string.rep('b',40),registryRevision=revision,names={'Forest'}})
check(#calls==1 and m:deckSupport(d).state=='unknown','Catalog relocation fences a pending registry transfer')
local Collection=require('app.collection');local M={findDeck=function()end,openDeck=function()end};Collection.install(M)
m=setmetatable({api={catalogPort=17472},catalogHealth={ready=true,deckCovers=true,storage={dataDirectory='/tmp/covers'}},request=function(_,service,method,path,body,cb)calls[#calls+1]={path=path,callback=cb}end,deckCoverCard=function()return{name='Anikthea, Hand of Erebos',selectedPrintingId='exact'}end,getArt=function(_,card,_,kind) m.lastArt={card=card,kind=kind};return'GPU' end},{__index=M});calls={}
local deck={id='source'};check(m:deckCoverArt(deck)==nil and calls[1].path:find('printing=exact',1,true),'Missing commander cover asks bounded metadata while preserving explicit printing')
local first=calls[1];m:deckCoverArt(deck);check(#calls==1,'Repeated frames share a single pending cover identity')
first.callback({card={name='Anikthea, Hand of Erebos',printing_id='exact',printingExact=true},kind='normal',cached=true})
check(m:deckCoverArt(deck)=='GPU'and m.lastArt.kind=='normal'and m.lastArt.card.printing_id=='exact','Cached full scan fills a missing crop with the same printing')
local map=require('assets.keyrune.sets');local n=0;for _ in pairs(map)do n=n+1 end
check(n==425 and map.thb==0xE961 and map.cmm and not map['invented-future-set'],'Set codes use verified release glyphs and leave unknown sets unmapped')
print('Deck support model checks: '..checks..' passed')
