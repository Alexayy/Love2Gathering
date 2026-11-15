-- Deterministic frontend scheduling/identity contracts; no HTTP or user files.
package.path='./?.lua;'..package.path
local clock=0;local channels={};local uploads=0
love={timer={getTime=function()return clock end},thread={},graphics={},image={},filesystem={}}
function love.thread.getChannel(name)
 if not channels[name]then local c={};function c:push(v)self[#self+1]=v end;function c:pop()return table.remove(self,1)end;function c:clear()for i=#self,1,-1 do self[i]=nil end end;channels[name]=c end
 return channels[name]
end
function love.thread.newThread()return{start=function()end,isRunning=function()return false end}end
function love.graphics.newImage(data)uploads=uploads+1;return{getDimensions=function()return data.w or 512,data.h or 712 end,getFormat=function()return'rgba8'end}end
function love.filesystem.newFileData(body)return body end
function love.image.newImageData()return{w=512,h=712}end
local API=require('app.api');local Artwork=require('app.artwork');local Model=require('app.model')
local checks=0;local function check(value,label)assert(value,label);checks=checks+1;print('IMAGE PRIORITY PASS '..label)end
local api=API.new();local results={};local visible={}
for i=1,8 do visible[i]=api:request('art','GET','/art/visible-'..i..'?network=0',nil,function()end,'image')end
check(api:imageDiagnostics().visibleInFlight==2 and api:imageDiagnostics().queued==6,'Visible image reads occupy only two bounded workers')
local selected='a';local function select(name)
 selected=name;return api:request('art','GET','/art/'..name..'?network=1&priority=selected',nil,function(_,err,code)results[name]=code end,'image',{priority='selected',selectionToken=name,isCurrent=function()return selected==name end})
end
local a=select('a');local b=select('b')
check(api.pendingDetails[a].worker=='artSelected'and api.pendingDetails[b].worker=='artSelected2','A new selection starts beside an obsolete in-flight download instead of waiting for its socket')
local c=select('c');local d=select('d')
check(results.c==499 and api.pendingDetails[c]==nil and api.pendingDetails[d].queued,'Only the latest waiting selection survives when both selected sockets are busy')
local releases=0;local function decoded(size)return{getSize=function()return size end,release=function()releases=releases+1 end}end
api.workers.artSelected.output:push({id=a,code=200,imageData=decoded(16*1024*1024)});api:update()
check(results.a==499 and releases==1 and api.pendingDetails[d].worker=='artSelected','An obsolete decoded selection is released and its slot starts the newest queued request')
check(api:imageDiagnostics().lastFrameImages==0,'Obsolete selected images consume no GPU delivery budget')
local first,second=visible[1],visible[2]
api.workers.art.output:push({id=first,code=200,imageData=decoded(5*1024*1024)})
api.workers.art2.output:push({id=second,code=200,imageData=decoded(5*1024*1024)})
api.workers.artSelected.output:push({id=d,code=200,imageData=decoded(5*1024*1024)})
api:update()
check(results.d==200 and api.pendingDetails[first]and api.pendingDetails[second]and api:imageDiagnostics().lastFrameImages==1,'Selected delivery precedes thumbnails and the eight-MiB frame budget defers other buffers')
api:update();check(api:imageDiagnostics().lastFrameImages==1,'A deferred large completion is delivered on the following frame')
local meta=api:request('catalog','GET','/cards/by-name?name=Chosen',nil,function()end,false,{priority='selectedMetadata',selectionToken='chosen'})
check(api.pendingDetails[meta].worker=='catalogSelectedMetadata','Selected point metadata has a lane independent of the ordinary name lookup FIFO')

local calls={};local m=setmetatable({settings={showCardArt=true,localArtworkOnly=true},page='builder',editGeneration=1,editDeck={main={{name='Chosen',count=1}},printingSelections={{name='Chosen',zone='main',count=1,printingId='exact-alt'}}},byName={},lookupPending={},catalogHealth={ready=false},art={},artPending=0,api={request=function(_,service,method,path,body,callback,binary,options)calls[#calls+1]={service=service,path=path,callback=callback,options=options}end}},Model)
local card={name='Chosen'};m:selectBuilderArtwork(card)
check(#calls==1 and calls[1].service=='catalog'and calls[1].path:find('exact%-alt')and calls[1].options.priority=='selectedMetadata','A name-only selected deck entry resolves its saved exact edition before any image request')
m:getBuilderPreviewArt(card);check(#calls==1,'Repeated selected frames do not enqueue duplicate metadata')
calls[1].callback({id='oracle-chosen',printing_id='exact-alt',name='Chosen',image_uris={}},nil,200)
m:getBuilderPreviewArt(card);local imageCall=calls[#calls]
check(imageCall.service=='art'and imageCall.path:find('network=1',1,true)and imageCall.path:find('printing=exact-alt',1,true)and imageCall.path:find('exact=1',1,true),'Explicit Builder selection downloads only its exact printing even under Cache only')
for i=1,100 do m:getBuilderPreviewArt(card)end;check(#calls==2,'One hundred selected frames reuse the same pending request')
check(imageCall.options.isCurrent(),'The current image request carries an active editor/selection/printing fence')
m.editGeneration=2;check(not imageCall.options.isCurrent(),'Replacing the editor makes the previous selected download ineligible for delivery')
m.editGeneration=1;m.editDeck.printingSelections[1].printingId='other-alt';check(not imageCall.options.isCurrent(),'Changing a saved printing invalidates the earlier image completion')
local ordinary={id='o',printing_id='p',name='Other',image_uris={}}
m:getArt(ordinary,true);check(calls[#calls].path:find('network=0',1,true),'Unselected visible cards retain Cache only despite the explicit selection exception')

local captures={};local n={settings={localArtworkOnly=true},cardData=function(_,v)return v end,api={request=function(_,_,_,path,_,cb,_,options)captures[#captures+1]={path=path,callback=cb,options=options}end}}
local target={id='o',printing_id='alt',requested_face=1,image_uris={}}
Artwork.get(n,target,true,nil,nil,{variant='thumb'});local small=captures[#captures]
check(small.path:find('variant=thumb',1,true)and small.path:find('face=1',1,true)and small.path:find('printing=alt',1,true),'Thumbnails retain kind, face and exact printing identity')
small.callback(nil,nil,200,{w=672,h=936},{httpSeconds=.01},{variant='original',thumbPending=true})
local before=#captures;local full=Artwork.get(n,target,true)
check(full and #captures==before,'A temporary original thumbnail fallback is immediately reusable by a full-size view')
clock=clock+.5;Artwork.get(n,target,true,nil,nil,{variant='thumb'});check(#captures==before,'Pending thumbnail derivatives retry at a low rate rather than each frame')
clock=clock+.6;Artwork.get(n,target,true,nil,nil,{variant='thumb'});check(#captures==before+1,'A still-visible thumbnail retries its derivative after one second')
captures[#captures].callback(nil,nil,200,{w=256,h=357},{httpSeconds=.01},{variant='thumb'})
local thumb=Artwork.get(n,target,true,nil,nil,{variant='thumb'});local thumbWidth=thumb:getDimensions();check(thumb~=full and thumbWidth==256,'A completed derivative replaces only the small view and preserves the full image')
local unsupported={id='unsupported',printing_id='unsupported',image_uris={}};Artwork.get(n,unsupported,true,nil,nil,{variant='thumb'})
captures[#captures].callback(nil,nil,200,{w=672,h=936},{},{variant='original',thumbUnavailable=true});before=#captures;clock=clock+60;Artwork.get(n,unsupported,true,nil,nil,{variant='thumb'})
check(#captures==before,'An unavailable derivative keeps its original fallback without a retry loop')
check(n.artworkUploadMetrics.count==3 and api:imageDiagnostics().count>0,'Bounded diagnostics retain stage totals without request paths')
local q=Model.new();local qc={};q.api={request=function(_,service,method,path,body,callback,binary,options)qc[#qc+1]={service=service,path=path,callback=callback,options=options}end}
q:openDeck({id='candidate-fixture',name='Candidate fixture',format='Modern',main={{name='Chosen',count=1}},commander={},sideboard={}})
local original={id='oracle-chosen',printing_id='default-chosen',name='Chosen',image_uris={}};q:rememberCard(original);q:selectBuilderArtwork(original);local parentRequest=qc[#qc]
q:showCardPrintings(original,'main');local candidate={id='oracle-chosen',printing_id='candidate-alt',name='Chosen',set='tst',image_uris={}}
qc[#qc].callback({items={candidate},name='Chosen',total=1,sets={}})
q:getCardPrintingArt(candidate,'thumb');check(qc[#qc].path:find('network=0',1,true)and not parentRequest.options.isCurrent(),'An implicit edition candidate stays cache-only and suspends the hidden parent selected request')
q:selectCardPrinting('candidate-alt');local candidateRequest=qc[#qc]
check(candidateRequest.path:find('network=1',1,true)and candidateRequest.path:find('priority=selected',1,true)and candidateRequest.path:find('exact=1',1,true),'An explicitly clicked edition candidate fetches only its exact original at selected priority')
local before=#qc;q:getBuilderPreviewArt(original);check(#qc==before,'The hidden parent preview cannot compete with the open edition candidate')
q:closeCardPrintings();check(q.previewCard==original and not q.editDeck.printingSelections and not q.dirty and not candidateRequest.options.isCurrent(),'Cancel fences the candidate request while leaving deck and parent selection unchanged')
q.previewCard=nil;q.builderArtSelection=nil;q:showCardPrintings(original,'main');qc[#qc].callback({items={candidate},name='Chosen',total=1,sets={}})
q:selectCardPrinting('candidate-alt');check(q:confirmCardPrinting()and q.previewCard==q.editDeck.main[1]and q.builderArtSelection and q.editDeck.printingSelections[1].printingId=='candidate-alt','Apply from an implicit parent preview explicitly selects the updated deck entry after normal validation')
local function texture()return{getDimensions=function()return 4096,4096 end,getFormat=function()return'rgba8'end}end
local ta,tb,tc=texture(),texture(),texture()
local aliases={settings={artworkMemoryMiB=128},art={a={image=ta,order=1},b={image=tb,order=10},c={image=tc,order=20}},profileImages={a={image=ta,order=30}}}
check(Artwork.cacheInfo(aliases).bytes==192*1024*1024 and Artwork.cacheInfo(aliases).images==3,'Multiple cache aliases charge each actual Image once')
Artwork.trim(aliases,aliases.art.c)
check(aliases.art.a and aliases.profileImages.a and not aliases.art.b and aliases.art.c,'The most recent alias determines the whole texture group LRU age')
aliases.art.b={image=tb,order=40};aliases.art.a.order=1;aliases.profileImages.a.order=2;aliases.art.c.order=50
Artwork.trim(aliases,aliases.art.a)
check(aliases.art.a and aliases.profileImages.a and not aliases.art.b,'Keeping one alias protects the entire shared texture group')
aliases.art.b={image=tb,order=40};Artwork.trim(aliases,aliases.art.c)
check(not aliases.art.a and not aliases.profileImages.a and Artwork.cacheInfo(aliases).bytes==128*1024*1024,'Eviction removes every alias and frees one physical texture charge')
local outstanding={};local pendingModel={settings={artworkMemoryMiB=128},api={request=function(_,_,_,_,_,callback)outstanding[#outstanding+1]=callback end}}
Artwork.image(pendingModel,'art','artPending','fallback','/art/fallback?network=0',6,nil,true,{variant='thumb'})
outstanding[#outstanding](nil,nil,200,{w=2048,h=2048},{},{variant='original',thumbPending=true})
check(Artwork.cacheInfo(pendingModel).images==1 and Artwork.cacheInfo(pendingModel).bytes==16*1024*1024,'An original/thumbnail fallback pair shares one decoded allocation charge')
clock=clock+2;Artwork.image(pendingModel,'art','artPending','fallback','/art/fallback?network=0',6,nil,true,{variant='thumb'});local late=outstanding[#outstanding]
for i=1,8 do Artwork.image(pendingModel,'art','artPending','other-'..i,'/art/other-'..i..'?network=0',6);outstanding[#outstanding](nil,nil,200,{w=2048,h=2048},{},{variant='original'})end
local uploaded=pendingModel.artworkUploadMetrics.count;late(nil,nil,200,{w=256,h=357},{},{variant='thumb'})
check(not pendingModel.art.fallback and not pendingModel.art['fallback-thumb']and pendingModel.artworkUploadMetrics.count==uploaded and pendingModel.artPending==0,'A grouped eviction safely fences a late pending derivative without resurrecting aliases or uploading pixels')
print('Image priority checks: '..checks)
