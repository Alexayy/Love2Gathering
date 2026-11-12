package.path='./?.lua;./?/init.lua;'..package.path
local calls={}
package.preload['app.api']=function()
    return {new=function()return {request=function(_,service,method,path,body,callback)calls[#calls+1]={service=service,method=method,path=path,body=body,callback=callback}end,update=function()end,quit=function()end}end,
        escape=function(s)return tostring(s):gsub(' ','%%20')end}
end
love={math={random=function()return 1111 end}}
local Model=require('app.model')
local m=Model.new();m:newDeck();m.search='Bolt';m.searchColor='R';m.searchSet='lea';m:changeDeckFormat('Standard')
assert(m.editDeck.format=='Standard' and m.searchFormat=='Standard' and m.searchSet=='All','Format switch left stale legality filters')
assert(m.validation==nil,'Format switch retained stale validation')
m.searchSort='Color';m.searchSet='dmu';m:searchCards()
assert(calls[#calls].path:find('sort=color',1,true) and calls[#calls].path:find('set=dmu',1,true),'Sort/set absent from query')
m:setDeckCover({name='Hare Apparent'});assert(m.editDeck.coverCard=='Hare Apparent')
assert(m:deckCoverCard(m.editDeck).name=='Hare Apparent','Cover helper did not resolve explicit selection')
local commander={commander={{name='Giada, Font of Hope'}},main={{name='Plains'}}}
assert(m:deckCoverCard(commander).name=='Giada, Font of Hope','Commander did not supply default cover')
m:setGame({gameId='test',revision=1,prompt={id=1,actionable={},targets={'illegal'},choices={{id='illegal',responseType='uuid'}}}})
assert(not m:canSelect('illegal'),'Empty authoritative legal-action list fell back to illegal targets')
m:setGame({gameId='test',revision=2,prompt={id=2,actionable={'legal'},targets={'illegal'}}})
assert(m:canSelect('legal') and not m:canSelect('illegal'),'Legal-action list was not authoritative')
local json=require('lib.json')
m.editDeck={id='queue-test',name='Test',format='Modern',description='',main=json.array({{name='Lightning Bolt',count=3}}),sideboard=json.array(),commander=json.array()}
m.deckRevision=0;m.editGeneration=1;m.mutationQueue={};m.mutationBusy=false
m:addCard({name='Lightning Bolt'});local first=calls[#calls]
m:addCard({name='Lightning Bolt'})
assert(m.count(m.editDeck,'main')==3,'Queued addition changed the list before validation')
first.callback({saveAllowed=true,errors={},counts={main=4}},nil,200)
assert(m.count(m.editDeck,'main')==4,'First approved addition was lost')
local second=calls[#calls]
assert(second.body.main[1].count==5,'Rapid second click did not validate against committed first click')
second.callback({saveAllowed=false,errors={{code='copy_limit',message='Only four copies',cards={'Lightning Bolt'}}}},nil,200)
assert(m.count(m.editDeck,'main')==4,'A rejected fifth copy appeared in the list')
m.editDeck.main[1].count=3;m.mutationQueue={};m.mutationBusy=false;m.deckRevision=0
m:addCard({name='Lightning Bolt'});local pending=calls[#calls]
m:addCard({name='Lightning Bolt'},'main',-1)
assert(m.count(m.editDeck,'main')==2,'Removal was not immediate')
pending.callback({saveAllowed=true,errors={}},nil,200)
assert(m.count(m.editDeck,'main')==2,'Stale positive result overwrote an intervening removal')
calls[#calls].callback({saveAllowed=true,errors={}},nil,200)
assert(m.count(m.editDeck,'main')==3,'Addition was not revalidated after removal')
print('PASS builder model: format/filter synchronization, covers, actionability, serialized copy guards and removal races')
