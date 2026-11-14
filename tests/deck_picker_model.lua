package.path='./?.lua;'..package.path
local calls={}
package.preload['app.api']=function()return{new=function()return{request=function(_,s,m,p,b,cb)calls[#calls+1]={service=s,method=m,path=p,body=b,callback=cb}end}end,escape=function(s)return tostring(s):gsub('([^%w%-_%.~])',function(c)return string.format('%%%02X',c:byte())end)end}end
love={math={random=function()return 1234 end}}
local Model=require('app.model');local json=require('lib.json');local n=0
local function check(value,label)assert(value,label);n=n+1;print('DECK PICKER PASS '..label)end
local function deck(id)return{id=id,name=id,format='Archive',historicalFormat='Standard',origin='preconstructed',main={{name='Forest',count=60}},commander={},sideboard={},planes={},schemes={}}end
local function model()calls={};return Model.new()end
local function popup(m,format)local s={format=format or'Modern',search='',offset=0,changed=function(id)m.playerDeckId=id end};m.lobbyDeckPicker=s;return s end
local m=model();local s=popup(m);s.search='Angel & Elf';m:queryLobbyPrecons(s);local old=calls[#calls]
check(old.path:find('category=deck',1,true)and old.path:find('limit=24',1,true)and old.path:find('format=Modern',1,true)and old.path:find('Angel%20%26%20Elf',1,true),'Product requests are bounded, format-filtered and URL-encoded')
s.search='Goblin';m:searchLobbyPrecons(s);old.callback({decks={deck('old')},total=99})
check(#s.precons==0 and s.timer==.25,'Typing immediately fences an older precon page before debounce')
m:updateCollection(.3);local query=calls[#calls];query.callback({decks={deck('new')},total=45})
check(s.precons[1].id=='new'and s.total==45,'Lobby update adopts only the current asynchronous page')
m:queryLobbyPrecons(s);old=calls[#calls];local other=popup(m);old.callback({decks={deck('wrong-popup')},total=1})
check(not other.precons,'An old popup response cannot replace a reopened picker')
m:loadLobbyStarters(other);calls[#calls].callback({decks={{id='starter-alias',format='Modern',main={},sideboard={},commander={}}}})
check(m.startersLoaded and m:findDeck('starter-alias')and json.encode(m.starterDecks[1]):find('"sideboard":[]',1,true),'Loaded Starter aliases retain transport arrays and native selectable identity')
m=model();s=popup(m);m:selectLobbyPrecon(s,{id='historical'});old=calls[#calls];s.search='Later';m:searchLobbyPrecons(s);old.callback(deck('historical'))
check(not m.playerDeckId and not m.lobbyPrecons,'A delayed detail cannot select a deck after the query changes')
m:selectLobbyPrecon(s,{id='historical'});old=calls[#calls];s.closed=true;old.callback(deck('historical'))
check(not m.playerDeckId,'Closed pickers cannot adopt a late selected deck')
m=model();m.page='lobby';s=popup(m);s.openPage='lobby';m:selectLobbyPrecon(s,{id='page-fenced'});old=calls[#calls];m.page='decks';old.callback(deck('page-fenced'))
check(not m.playerDeckId and not m.lobbyPrecons,'Navigating away fences a late selection even without an explicit close')
m.page='lobby';s=popup(m);s.openPage='lobby';m:queryLobbyPrecons(s);old=calls[#calls];m.page='table';old.callback({decks={deck('page-fenced')},total=1})
check(not s.precons,'A room or gameplay page transition fences an outstanding product page')
m=model();s=popup(m);local original=deck('historical');m:selectLobbyPrecon(s,original);old=calls[#calls];old.callback(original)
local selected=m:findDeck(m.playerDeckId)
check(selected and selected.id=='lobby-modern-historical'and selected.format=='Modern'and selected.sourceDeckId=='historical','Full historical list is normalized into a separate temporary lobby identity')
check(original.format=='Archive'and original.id=='historical'and#m.decks==0,'Selecting an archive does not mutate or save its original')
check(json.encode(selected):find('"commander":[]',1,true)and json.encode(selected):find('"sideboard":[]',1,true),'Temporary preconstructed lists retain true empty engine arrays')
m.botDeckId=selected.id;m.botDeckIds={selected.id};m:syncLobbyDecks()
check(m.playerDeckId==selected.id and m.botDeckId==selected.id,'Lobby synchronization preserves selected cached precon IDs')
m.decks={{id='saved',format='Modern'}};m:refreshDecks();calls[#calls].callback({decks={{id='saved2',format='Modern',main={},sideboard={},commander={}}}})
check(m.playerDeckId==selected.id and m.botDeckId==selected.id,'Refreshing saved decks does not replace a selected temporary precon')
m=model();s=popup(m);local auxiliary=deck('plane-product');auxiliary.planes={{name='Plane',count=10}};auxiliary.counts={planes=10};m:cacheLobbyPrecon(s,auxiliary,false)
check(s.confirmAuxiliary and not m.playerDeckId and not m.lobbyPrecons,'Planes and schemes require explicit confirmation before any omission')
local copy=m:cacheLobbyPrecon(s,auxiliary,true)
check(copy.excludedAuxiliary.confirmed and copy.planes==nil and#auxiliary.planes==1 and auxiliary.format=='Archive','Confirmed constructed selection omits auxiliary cards only in the temporary copy')
m=model();local protected={};for index=1,30 do s=popup(m);local d=m:cacheLobbyPrecon(s,deck('source'..index),true);if index==1 then m.botDeckId=d.id;m.botDeckIds={d.id};protected.id=d.id end end
local count=0;for _ in pairs(m.lobbyPrecons)do count=count+1 end
check(count==16 and m.lobbyPrecons[protected.id]and m.lobbyPrecons[m.playerDeckId],'Temporary deck cache stays at16 entries and protects selected human and bot decks')
check(#calls==0,'Temporary selection and cache eviction issue no storage writes')
print('Deck picker model checks: '..n..' passed')
