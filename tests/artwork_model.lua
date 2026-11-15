-- Image status/transport contracts, with no disk, HTTP or native game.
package.path='./?.lua;'..package.path
local now=0
love={timer={getTime=function()return now end},graphics={newImage=function(data)return{bytes=data}end},image={newImageData=function(data)return data end},filesystem={newFileData=function(data)return data end}}
local Artwork=require('app.artwork');local Model={};Model.__index=Model;Artwork.install(Model)
function Model:cardData(card)return card end
local calls={};local m=setmetatable({settings={showCardArt=true,localArtworkOnly=true},api={request=function(_,service,method,path,body,callback)calls[#calls+1]={service=service,path=path,callback=callback}end}},Model)
local checks=0;local function check(value,label)assert(value,label);checks=checks+1;print('ARTWORK PASS '..label)end
local card={id='oracle',printing_id='printing',requested_face=1,image_uris={normal='https://cards.scryfall.io/example'}}
Artwork.get(m,card,true);local request=calls[#calls]
check(request.path:find('printing=printing',1,true)and request.path:find('face=1',1,true)and request.path:find('network=0',1,true),'Runtime requests retain catalog printing/face and strict local-only preference')
check(m:artworkStatus(card)=='loading','Only an actual pending image request is loading')
Artwork.get(m,card,true);check(#calls==1,'Repeated frames do not enqueue the same pending image')
request.callback(nil,nil,404);check(m:artworkStatus(card)=='missing'and m:artworkLabel(card)=='Artwork is not cached','A local miss becomes an explicit missing label instead of perpetual loading')
Artwork.get(m,card,true);check(#calls==1,'An image miss respects its bounded retry interval')
now=31;Artwork.get(m,card,true);calls[#calls].callback('real decoded fixture bytes',nil,200)
local image=Artwork.get(m,card,true);check(image and m:artworkStatus(card)=='ready','A later cache fill can become a ready image after retry')
Artwork.get(m,card,true,'art_crop');check(calls[#calls].path:find('kind=art_crop',1,true)and m:artworkStatus(card,'normal')=='ready','Full-card and cropped-art requests have distinct cache/status identities')
calls[#calls].callback(nil,'Connection failure',0);check(m:artworkStatus(card,'art_crop')=='error','Transport failure has an error state without hiding a ready full-card image')
check(m:artworkStatus({name='Unindexed native card'})=='catalog','Unavailable card metadata is separate from image download progress')
m.resolveTokenCard=function()return card end
check(m:artworkStatus({isToken=true,id='native-token'})=='ready','Token status follows its resolved artwork identity without replacing the native token')
for i=1,110 do
    local item={id='oracle-'..i,printing_id='printing-'..i,image_uris={}}
    Artwork.get(m,item,true);calls[#calls].callback(nil,nil,404);now=now+1
end
local count=0;for _,entry in pairs(m.art)do if not entry.image then count=count+1 end end
check(count<=96,'Missing/error status entries have their own bounded cache independently of decoded textures')
local warm={id='warm',printing_id='warm',image_uris={}}
m.settings.localArtworkOnly=false
local before=#calls;Artwork.get(m,warm,true,'art_crop',true)
check(calls[#calls].path:find('network=0',1,true),'Startup prewarm is local-only even when online artwork is enabled')
calls[#calls].callback(nil,nil,404);Artwork.get(m,warm,true,'art_crop')
check(#calls==before+2 and calls[#calls].path:find('network=1',1,true),'A local startup miss does not impose its negative TTL on an enabled online view')
calls[#calls].callback('cached',nil,200)
local reused=Artwork.get(m,warm,true,'art_crop',true)
check(reused and #calls==before+2,'A ready image is reused across startup and ordinary view policies')
local busy={id='busy',printing_id='busy',image_uris={}}
Artwork.get(m,busy,true);local request=calls[#calls];request.callback(nil,nil,503);before=#calls
now=now+.5;Artwork.get(m,busy,true);check(#calls==before,'A busy image response has a bounded retry delay')
now=now+.6;Artwork.get(m,busy,true);check(#calls==before+1,'Busy cached image lookup retries after one second rather than thirty')
local missCalls=0;local misses=setmetatable({settings={showCardArt=true,localArtworkOnly=true},art={},api={request=function(_,_,_,_,_,callback)missCalls=missCalls+1;callback(nil,nil,404)end}},Model)
for i=1,80 do misses.art['ready-'..i]={image={getDimensions=function()return 1,1 end},state='ready',order=i}end
local absent={};for i=1,64 do absent[i]={id='absent-'..i,printing_id='absent-printing-'..i,image_uris={}}end
for _,card in ipairs(absent)do Artwork.get(misses,card,true)end
check(missCalls==64,'A populated decoded cache still records each first visible image miss')
before=missCalls;for _,card in ipairs(absent)do Artwork.get(misses,card,true)end
check(missCalls==before,'Eighty ready textures do not evict sixty-four negative statuses or refetch them within the retry interval')
now=now+31;Artwork.get(misses,absent[1],true)
check(missCalls==before+1,'A retained negative status still retries after its ordinary thirty-second interval')
print('Artwork model checks: '..checks..' passed')
