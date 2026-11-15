-- Real LÖVE image decode/cache requests with controlled local metadata/pixels.
-- This test does not download art or claim its generated swatches are card art.
local json=require('lib.json');local calls={}
package.preload['app.api']=function()
 local API={escape=function(v)return tostring(v):gsub('([^%w%-_%.~])',function(c)return string.format('%%%02X',c:byte())end)end}
 function API.new()return{request=function(_,service,method,path,body,callback)calls[#calls+1]={service=service,method=method,path=path,body=body,callback=callback}end,update=function()end,quit=function()end}end
 return API
end
local Model=require('app.model');local output=assert(os.getenv('L2G_MECHANICS_CLIENT_OUTPUT'))
local checks,images,trace={}, {},{};local finished=false;local m;local nativeObjects=0;local drawnFrames=0
local function check(value,label)assert(value,label);checks[#checks+1]=label end
local function metadata(name,printing)return{id='catalog-'..printing,printing_id=printing,name=name,oracle_text='Controlled local metadata fixture',image_uris={normal='local-fixture'},power='2',toughness='2'}end
local function bytes(index)
 local data=love.image.newImageData(32,48);data:mapPixel(function(x,y)local stripe=(math.floor(x/8)+math.floor(y/8))%2;return index/5,.2+stripe*.15,.8-index/8,1 end)
 return data:encode('png'):getString()
end
local function exactImage(host,source,index,label)
 local before=json.encode(host);local start=#calls;local selected=source.selectedPrintingId
 m.byName[source.name]=metadata(source.name,'default-'..index)
 local initial=m:getArt(host,true)
 check(not initial and#calls==start+1 and calls[#calls].service=='catalog'and calls[#calls].path:find('/cards/'..selected..'?printing='..selected,1,true),label..': exact metadata requested for native visual source, without token lookup')
 calls[#calls].callback(metadata(source.name,selected),nil,200)
 m:getArt(host,true);local request=calls[#calls]
 check(request.service=='art'and request.path:find('printing='..selected,1,true)and request.path:find('exact=1',1,true)and request.path:find('network=0',1,true),label..': image request retains exact source printing and local-only flag')
 check(m:artworkStatus(host)=='loading',label..': status follows the same pending visual identity')
 request.callback(bytes(index),nil,200)
 local image=m:getArt(host,true);check(image and image:typeOf('Image')and m:artworkStatus(host)=='ready',label..': real LÖVE decode/cache returns ready source pixels')
 images[#images+1]={image=image,label=label..'\n'..selected}
 check(json.encode(host)==before,label..': host native identity, token status, counters and live values remain unchanged')
end
function love.load()
 m=Model.new();m.settings.showCardArt=true;m.settings.localArtworkOnly=true
 local top={id='gemrazer-component',name='Gemrazer',power='4',toughness='4',selectedPrintingId='gemrazer-selected',ownerId='human'}
 local rat={id='rat-host',name='Rat',token=true,isToken=true,power='1',toughness='1',printing={name='Rat',power='1',toughness='1',colors={'B'}}}
 local host={id='rat-host',objectId='rat-host',name='Gemrazer',token=true,isToken=true,power='5',toughness='5',counters={['+1/+1']=1},printing={name='Gemrazer',power='4',toughness='4'},mutate={topId=top.id,components={rat,top}}}
 exactImage(host,top,1,'Merged token / top card')
 local enriched=m:cardData(host)
 check(enriched.objectId=='rat-host'and enriched.token and enriched.power=='5'and enriched.mutate==host.mutate,'Catalog enrichment preserves native host and inspectable merged components')
 local copied={id='bear-source',name='Grizzly Bears',power='2',toughness='2',selectedPrintingId='bears-selected',ownerId='human'}
 local copy={id='copy-token',name='Grizzly Bears',token=true,isToken=true,power='6',toughness='6',copySourceCard=copied,selectedPrintingId='unrelated-host-selection',counters={['+1/+1']=4}}
 exactImage(copy,copied,2,'Copy token / native source')
 local copyEnriched=m:cardData(copy)
 check(copyEnriched.token and copyEnriched.power=='6'and copyEnriched.copySourceCard==copied,'Catalog enrichment preserves native copy-source metadata without changing token status')
 local nonToken={id='ordinary-host',name='Gemrazer',power='7',toughness='7',mutate={topId='third-component',components={{id='wrong-component',name='Wrong card'},{id='third-component',name='Gemrazer',selectedPrintingId='gemrazer-other'}}}}
 exactImage(nonToken,nonToken.mutate.components[2],3,'Merged card / explicit top ID')
 local nested={id='nested-host',name='Gemrazer',token=true,mutate={topId='copied-component',components={{id='copied-component',name='Grizzly Bears',token=true,copySourceCard={id='nested-source',name='Grizzly Bears',selectedPrintingId='nested-selected'}}}}}
 exactImage(nested,nested.mutate.components[1].copySourceCard,4,'Merged token / copied top')
 local template={id='ordinary-token',name='Changed live name',power='8',toughness='9',colors={'G'},token=true,printing={name='Wrong live visual',power='8',toughness='9'},tokenTemplate={name='Rat',token=true,printing={name='Rat',power='1',toughness='1',colors={'B'},type_line='Token Creature — Rat'}}}
 local before=json.encode(template);m:getArt(template,true);local request=calls[#calls]
 check(request.path=='/tokens/resolve'and request.body.token.name=='Rat'and request.body.token.printing.power=='1'and request.body.token.printing.colors[1]=='B'and request.body.seed=='ordinary-token','Ordinary token preferences resolve the native original template, not changed current name/stats/colors')
 request.callback({card={id='token-catalog',printing_id='rat-selected',tokenImageId='rat-selected-0',token=true,image_uris={normal='local-fixture'},printingExact=true}},nil,200)
 m:getArt(template,true);request=calls[#calls];check(request.service=='art'and request.path:find('printing=rat-selected',1,true),'Ordinary token retains actual preference-selected image request')
 request.callback(bytes(2),nil,200);check(m:getArt(template,true)and m:artworkStatus(template)=='ready'and json.encode(template)==before,'Token template status/cache remains ready without changing live host')
 local start=#calls
 for _,card in ipairs({{id='hidden',hidden=true,token=true,copySourceCard=copied},{id='down',faceDown=true,mutate=host.mutate},{id='missing-top',token=true,mutate={topId='absent',components={rat}}}})do
  check(m:getArt(card,true)==nil and m:artworkStatus(card)=='catalog','Hidden or unavailable native visual provenance never falls back to another component')
 end
 check(#calls==start,'Unavailable/hidden component metadata cannot start image or token requests')
 local native=os.getenv('L2G_MECHANICS_CLIENT_NATIVE')
 if native and native~=''then
  local file=assert(io.open(native,'rb'));local state=json.decode(file:read('*a'));file:close()
  for _,player in ipairs(state.players or{})do for _,card in ipairs(player.battlefield or{})do
   if card.mutate or card.copySourceCard then
    nativeObjects=nativeObjects+1;local source=m:artworkCard(card)
    if source and not(source.token or source.isToken)then
     local nativeBefore=json.encode(card);local printing=source.selectedPrintingId or('native-fixture-'..nativeObjects)
     m.byName[source.name]=metadata(source.name,printing)
     if source.selectedPrintingId then m.printingMetadata=m.printingMetadata or{};m.printingMetadata[printing]={card=metadata(source.name,printing)}end
     m:getArt(card,true);local actual=calls[#calls]
     check(actual.service=='art'and actual.path:find('printing='..printing,1,true),'Captured native visual source reaches its own local artwork request')
     actual.callback(bytes(1),nil,200);check(m:getArt(card,true)and m:artworkStatus(card)=='ready'and json.encode(card)==nativeBefore,'Captured native merged/copied host remains intact while source image decodes')
    else check(not source or source.token or source.isToken,'Captured native unavailable provenance remains explicitly unavailable or a native token template')end
   end
  end end
 end
 for _,call in ipairs(calls)do trace[#trace+1]={service=call.service,method=call.method,path=call.path,body=call.body}end
 check(love.filesystem.getSaveDirectory():find(assert(os.getenv('XDG_DATA_HOME')),1,true)==1,'LÖVE save location remains inside isolated run storage')
end
function love.draw()
 drawnFrames=drawnFrames+1
 love.graphics.clear(.04,.05,.08)
 love.graphics.setColor(1,1,1);love.graphics.print('Native visual identity routing · generated pixel fixtures, no downloaded art',30,25)
 for i,entry in ipairs(images)do local x=30+(i-1)*280;love.graphics.draw(entry.image,x,80,0,3,3);love.graphics.print(entry.label,x,245,0,1,1)end
 if not finished and drawnFrames>=3 then
  finished=true;love.graphics.captureScreenshot(function(data)
   local path=output..'/native-artwork-routing.png';local file=assert(io.open(path,'wb'));file:write(data:encode('png'):getString());file:close()
   local result={status='pass',scenarioId='client-native-visual-artwork-routing',evidenceType='client_artwork_transport_and_decode',checks=checks,attempts=#calls,acceptedNativeActions=0,nativeEvents=0,actionTrace=trace,capturedNativeObjects=nativeObjects,captures={path},scope='Actual local artwork request identity, LÖVE decode and image cache; controlled catalog metadata/generated pixels. Optional native snapshot supplies original merged/copied host metadata; no native rules or catalog downloads.'}
   file=assert(io.open(output..'/result.json','w'));file:write(json.encode(result));file:close();print('MECHANICS CLIENT ARTWORK COMPLETE '..#checks..' checks');love.event.quit(0)
  end)
 end
end
