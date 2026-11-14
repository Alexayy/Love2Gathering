-- Synthetic transport contracts; backend/native acceptance is separate.
package.path='./?.lua;'..package.path
local Library=require('app.library');local json=require('lib.json')
local Model={};Model.__index=Model
function Model:getArt(card)return card and card.printing_id end
Library.install(Model)
local calls,checks={},0
love={timer={getTime=function()return 10 end}}
local function check(ok,label)assert(ok,label);checks=checks+1;print('LIBRARY MODEL PASS '..label)end
local function client()
    local m=setmetatable({settings={showCardArt=true},format='Modern',calls={},decks={},activeDeckId='my-deck'},Model)
    function m:request(service,method,path,body,callback)self.calls[#self.calls+1]={service=service,method=method,path=path,body=body and json.decode(json.encode(body)),callback=callback}end
    function m:toast(text)self.lastToast=text end
    function m:refreshDecks()self.refreshed=true end
    return m
end
local m=client();m:showImport('4 Lightning Bolt');m:previewDeckImport();local first=m.calls[#m.calls]
check(first.path=='/imports/preview'and first.body.text=='4 Lightning Bolt'and first.body.format=='Modern','Pasted export requests a read-only import preview')
m:setImportText('https://moxfield.com/decks/abcdef');m:previewDeckImport();local second=m.calls[#m.calls]
check(second.body.url=='https://moxfield.com/decks/abcdef'and not second.body.text,'Public deck URL uses the bounded service import path')
first.callback({deck={name='Old'},validation={saveAllowed=true}})
check(not m.importPreview and m.importBusy,'An old text-preview response cannot replace the newer URL request')
local deck={id='new-deck',name='Actual imported',format='Modern',main={{name='Lightning Bolt',count=4}},sideboard={},commander={},printingSelections={{name='Lightning Bolt',zone='main',count=4,set='m10',collectorNumber='161',printingId='printing-b'}}}
second.callback({deck=deck,validation={saveAllowed=true,draft=true}})
check(m.importPreview.deck.main[1].count==4 and# m.calls==2,'Preview retains quantities and printings without saving')
check(m:saveImportedDeck(),'Explicit Save submits an allowed unfinished draft')
local save=m.calls[#m.calls]
check(save.path=='/decks'and save.body.printingSelections[1].collectorNumber=='161'and save.body.main[1].count==4,'Save preserves the reviewed printing and full card count')
save.callback({id='new-deck',name='Actual imported',draft=true})
check(m.refreshed and m.page=='decks'and m.lastToast:find('Draft saved',1,true),'Successful explicit save refreshes the collection')
m:showImport('251 Forest');m:previewDeckImport();local bad=m.calls[#m.calls];bad.callback({deck=deck,validation={saveAllowed=false,errors={{message='Too many copies'}}}})
check(not m:saveImportedDeck(),'Rejected construction cannot be saved by the import action')
m:showImport('New opening');bad.callback({deck=deck,validation={saveAllowed=true}})
check(not m.importPreview,'Reopening the importer invalidates previous callbacks')
local closed=false
check(m:importDeckFile({getFilename=function()return'list.txt'end,getSize=function()return 8 end,open=function()return true end,read=function()return'4 Forest'end,close=function()closed=true end})and closed,'Dropped deck exports are read within bounds and closed')
check(not m:importDeckFile({getFilename=function()return'secret.exe'end}),'Unrelated dropped files are rejected before reading')

m:showTokenSettings('my-deck');local tokens=m.calls[#m.calls]
tokens.callback({items={{tokenImageId='goblin-a-0',printing_id='goblin-a'},{tokenImageId='goblin-b-0',printing_id='goblin-b'}},total=2,preferences={mode='default',selected={}}})
check(m:toggleTokenArt('goblin-b-0')and not m:toggleTokenArt('unknown'),'Only catalog-projected token artwork identities can be selected')
check(m:setTokenMode('randomSelected')and not m:setTokenMode('guess'),'Only the three persisted artwork modes are accepted')
m:saveTokenSettings();local prefs=m.calls[#m.calls]
check(prefs.method=='PUT'and prefs.path=='/decks/my-deck/token-art'and prefs.body.selected[1]=='goblin-b-0','Token preferences save independently of the deck card lists')
prefs.callback({mode='randomSelected',selected={'goblin-b-0'}})
check(not m.tokenDirty and m.tokenArtGeneration==1,'Saving preferences invalidates old token resolution cache entries')
m:showTokenSettings('another-deck');local newer=m.calls[#m.calls];tokens.callback({items={{tokenImageId='old'}},preferences={mode='randomAll',selected={}}})
check(#m.tokenItems==0 and not m.tokenDirty,'A different deck opening rejects stale preferences and clears the dirty flag')
newer.callback({items={},preferences={mode='default',selected={}}})
local native={id='native-object',objectId='native-object',token=true,name='Goblin',power='4',toughness='4',colors={'R'},printing={power='1',toughness='1',colors={'R'}}}
local before=json.encode(native);local count=#m.calls
check(m:getArt(native,true)==nil and m:getArt(native,true)==nil and# m.calls==count+1,'A token has one bounded asynchronous resolution rather than repeated pending requests')
local resolve=m.calls[#m.calls]
check(resolve.body.seed=='native-object'and resolve.body.deckId=='my-deck'and resolve.body.token.printing.power=='1','Token art uses stable native object identity and original descriptor, retaining live stats')
resolve.callback({card={id='token-oracle',printing_id='goblin-b',image_uris={normal='local'},requested_face=0}})
check(m:getArt(native,true)=='goblin-b'and json.encode(native)==before,'Resolved art passes its actual printing to the original loader without changing native identity or power')
local enriched={id='arbitrary-oracle',objectId='enriched-native',token=true,name='Goblin',power='4',toughness='4',colors={'R'},image_uris={normal='arbitrary printing'},printing={power='1',toughness='1',colors={'R'}}}
count=#m.calls;check(m:getArt(enriched,true)==nil and# m.calls==count+1 and m.calls[#m.calls].body.seed=='enriched-native','An enriched token with arbitrary image metadata still resolves its native identity and per-deck preferences')
m.calls[#m.calls].callback({card={id='selected-oracle',printing_id='selected-printing',tokenImageId='selected-printing-0',token=true,image_uris={normal='selected'}}})
check(m:getArt(enriched,true)=='selected-printing'and enriched.id=='arbitrary-oracle','Enriched token art uses the preference-selected printing without overwriting its native/catalog identities')
count=#m.calls;check(m:getArt({id='selected-oracle',printing_id='selected-printing',tokenImageId='selected-printing-0',token=true,image_uris={normal='selected'}},true)=='selected-printing'and# m.calls==count,'Explicit catalog token thumbnails preserve their chosen printing without re-resolving')
native.id='unknown';native.objectId='unknown';m:getArt(native,true);local absent=m.calls[#m.calls];absent.callback({card=json.null});count=#m.calls
check(m:getArt(native,true)==nil and# m.calls==count,'Unknown token artwork has a bounded retry and is not treated as a real card')
m.roomConnectionId='room';m.room={config={kind='draft'}};native.objectId='draft-token';m:getArt(native,true)
check(m.calls[#m.calls].body.deckId==nil,'Drafted token artwork never inherits the unrelated practice deck preference');m.calls[#m.calls].callback({card=json.null})
m.room.config.kind='constructed';m.roomDeckId='room-deck';native.objectId='room-token';m:getArt(native,true)
check(m.calls[#m.calls].body.deckId=='room-deck','Constructed room token artwork uses that seat’s actual room deck');m.calls[#m.calls].callback({card=json.null})
m.settings.showCardArt=false;native.objectId='disabled';count=#m.calls;m:getArt(native,false)
check(#m.calls==count,'Disabled artwork does not start token resolution')

m:showHistory();local old=m.calls[#m.calls];m:showHistory();local fresh=m.calls[#m.calls]
fresh.callback({matches={{id='actual',outcome='win'}},total=1});old.callback({matches={{id='stale'}},total=99})
check(m.historyItems[1].id=='actual'and m.historyTotal==1,'Each history opening guards against stale list responses')
m.historyOffset=12;m:refreshHistory();check(m.calls[#m.calls].path=='/history?limit=12&offset=12','History pagination stays bounded and read-only')
print('Library model checks: '..checks..' passed')
