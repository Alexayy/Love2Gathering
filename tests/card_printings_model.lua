-- Presentation-only async contracts; real HTTP/SQL/native checks are separate.
local calls={}
package.preload['app.api']=function()return{escape=function(s)return tostring(s):gsub(' ','%%20')end,new=function()return{request=function(_,service,method,path,body,callback)calls[#calls+1]={service=service,method=method,path=path,body=body,callback=callback}end,update=function()end,quit=function()end}end}end
love={timer={getTime=function()return 10 end},math={random=function()return 1111 end}}
local Model=require('app.model');local json=require('lib.json');local checks=0
local function check(ok,text)assert(ok,text);checks=checks+1;print('PRINTING MODEL PASS '..text)end
local function card(id,set)return{id='forest',name='Forest',printing_id=id,set=set,collector_number='254',image_uris={normal='exact'},printingExact=true,printingResolved=true}end
local m=Model.new();m:openDeck({id='test',name='Deck',format='Modern',main={{name='Forest',count=60}},sideboard={},commander={}})
local original=json.encode(m.editDeck.main)
check(m:showCardPrintings({name='Forest'},'main'),'A saved or unsaved deck card opens its exact printing chooser')
local old=calls[#calls];check(old.path:find('/printings?name=Forest',1,true),'Picker uses the same-card endpoint rather than an ambiguous gallery name search')
old.callback({name='Forest',items={card('thb','thb'),card('mom','mom')},total=2,sets={}})
check(not m:selectCardPrinting('unknown')and m:selectCardPrinting('thb'),'Only offered exact printing IDs can be staged')
check(not m.dirty and json.encode(m.editDeck.main)==original,'Staging does not mutate counts or the editor')
m:closeCardPrintings();check(not m.editDeck.printingSelections,'Cancel preserves the original deck')
m:showCardPrintings({name='Forest'},'main');local earlier=calls[#calls]
m:filterCardPrintings('artist','thb','all');m:updateCardPrintings(.3);local latest=calls[#calls]
earlier.callback({items={card('old','old')},total=99});check(m.cardPrintingPicker.busy and #m.cardPrintingPicker.items==0,'Filter version invalidates an older in-flight response')
latest.callback({name='Forest',items={card('thb','thb')},total=1,sets={}})
m:selectCardPrinting('thb');check(m:confirmCardPrinting(),'Explicit apply commits the staged edition')
check(m.editDeck.printingSelections[1].printingId=='thb'and m.editDeck.printingSelections[1].count==60 and m.dirty,'Edition covers the actual copies and marks the deck dirty')
check(json.encode(m.editDeck.main)==original and m.deckRevision==1,'The artwork edit changes revision without changing composition')
m:commitCard('Forest','main',-1);check(m.editDeck.printingSelections[1].count==59,'Removing copies keeps persisted printing quantities aligned')
m:commitCard('Forest','main',1);check(m.editDeck.printingSelections[1].count==60,'Adding another copy retains the selected edition')
local candidate=json.decode(json.encode(m.editDeck));candidate.main[1].count=59;m:syncCardPrintings(candidate)
check(candidate.printingSelections[1].count==59 and m.editDeck.printingSelections[1].count==60,'Synchronizing a validation candidate never mutates the live editor')
m:showCardPrintings({name='Forest'},'main');m:changeDeckFormat('Commander')
check(not m:confirmCardPrinting()and m.editDeck.printingSelections[1].count==60,'Changing format invalidates a staged printing through the deck revision fence')
m:showCardPrintings({name='Forest'},'main');local stale=calls[#calls];m:newDeck();stale.callback({items={card('old','old')},total=1})
check(not m.cardPrintingPicker,'Reopening the editor invalidates the whole picker and its callbacks')
check(not m:showCardPrintings({name='Forest'},'main'),'A card outside the new deck cannot receive an orphan selection')
m.byName.Forest={id='forest',name='Forest',printing_id='default',oracle_text='Basic land',image_uris={normal='default'}}
m.page='table';m.game={gameId='live',players={{id='owner',human=true,seat=0},{id='other',human=false,seat=1}}}
local native={id='native-forest',name='Forest',ownerId='owner',power='5',toughness='6',counters={['+1/+1']=2},selectedPrintingId='thb'}
local before=json.encode(native);local pending=m:cardData(native)
check(pending.printingExact and not pending.printingResolved,'An explicit but unloaded edition never flashes default artwork')
local metadata=calls[#calls];check(metadata.path=='/cards/thb?printing=thb','Exact metadata lookup cannot prefer an unrelated cached printing')
metadata.callback(card('thb','thb'))
local data=m:cardData(native)
check(data.id=='forest'and data.objectId=='native-forest'and data.printing_id=='thb','Native object and catalog/printing identities remain distinct')
check(data.power=='5'and data.toughness=='6'and data.counters['+1/+1']==2 and json.encode(native)==before,'Selected artwork never overwrites live native values or mutates projections')
m:getArt(data,true);check(calls[#calls].path:find('printing=thb',1,true)and calls[#calls].path:find('exact=1',1,true),'Runtime artwork requests enforce exact printing lookup')
check(m.art['thb-0-normal-exact']~=nil and not m.art['thb-0-normal'],'An earlier aliased default image cannot poison the exact-edition cache')
m.printingMetadata.bad={card={id='plains',name='Plains',printing_id='bad'}}
local forged=m:cardData({id='native-forest',ownerId='other',name='Forest',selectedPrintingId='bad'})
check(not forged.printingResolved,'A foreign seat cannot visually replace Forest with a Plains printing')
m.roomConnectionId='room';m.roomDeckId='own';m.decks={{id='own',printingSelections={{name='Forest',zone='main',count=60,printingId='thb'}}}}
m.game.players={{id='owner',human=true,isLocal=true},{id='other',human=true,isLocal=false,isHuman=true}}
check(m:printingDeck({ownerId='owner'})==m.decks[1]and not m:printingDeck({ownerId='other'}),'Room opponents never borrow the local human edition fallback')
m.replay={metadata={playerDeck=m.decks[1]}};check(m:printingDeck({ownerId='owner'})==m.decks[1]and not m:printingDeck({ownerId='other'}),'A multi-human replay keeps its perspective deck separate from another human')
m.roomConnectionId=nil;m.replay=nil
m.page='decks';m.editDeck={main={{name='Forest',count=60}},printingSelections={{name='Forest',zone='main',count=60,printingId='thb'}}}
check(not m:cardData({name='Forest'}).printingExact,'An open editor never leaks its edition choice into another deck tile')
local cover=m:deckCoverCard(m.editDeck);check(cover.selectedPrintingId=='thb','A deck cover uses that deck’s persisted exact choice')
local token={id='token',name='Forest',token=true,printing_id='token-print'}
check(m:cardData(token).selectedPrintingId==nil,'Token illustration selection remains independent of normal-card editions')
print('Card printing model checks: '..checks..' passed')
