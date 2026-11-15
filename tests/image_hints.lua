-- Physical-size hints and exact profile variant keys, no HTTP or GPU work.
package.path='./?.lua;'..package.path
local dpi=1;love={graphics={getDimensions=function()return 2560,1440 end},window={getDPIScale=function()return dpi end}}
local Layout=require('app.layout');local Hints=require('app.image_hints');local checks=0
local function check(value,label)assert(value,label);checks=checks+1;print('IMAGE HINT PASS '..label)end
Layout.setScale(1)
check(Hints.forSize(256,512).variant=='thumb','The small variant fits its physical pixel bounds')
check(not Hints.forSize(257,200).variant and not Hints.forSize(200,513).variant,'A larger display area retains the original')
Layout.setScale(1.25);check(not Hints.forSize(220,300).variant,'UI scaling cannot silently upscale a smaller derivative')
Layout.setScale(1);dpi=2;check(not Hints.forSize(200,200).variant and Hints.forSize(128,180).variant=='thumb','High-DPI displays use physical rather than logical dimensions')
dpi=1;check(not Hints.forSize(200,300,2).variant,'An additional render/camera factor can require original pixels')
local calls={}
package.loaded['app.artwork']=nil
package.preload['app.artwork']=function()return{image=function(...)calls[#calls+1]={...};return nil,'loading'end}end
local Profile=require('app.profile');local Model={};Profile.install(Model)
local m=setmetatable({settings={localArtworkOnly=true}},{__index=Model});local ref={printingId='exact-printing',face=1}
m:profileArt(ref,true);local normal=calls[#calls]
check(normal[4]=='exact-printing:1'and normal[5]:find('network=0',1,true)and not normal[5]:find('variant=',1,true),'Startup local-only profile warming retains its original identity and network policy')
m:profileArt(ref,nil,{variant='thumb',priority='visible'});local small=calls[#calls]
check(small[4]=='exact-printing:1'and not small[5]:find('variant=',1,true)and small[5]:find('network=0',1,true),'Profile forwards exact-face identity and lets the shared cache add its derivative key once')
check(small[9].priority=='visible','The profile image request forwards its scheduling hint')
m.profileImages={['exact-printing:1']={state='ready'},['exact-printing:1-thumb']={state='missing'}}
check(m:profileArtState(ref)=='ready'and m:profileArtState(ref,{variant='thumb'})=='missing','Thumbnail state cannot overwrite full-art state')
print('Image hints: '..checks..' passed')
