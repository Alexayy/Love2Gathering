-- Transport contracts only; real image decoding and UI are checked separately.
package.path='./?.lua;'..package.path
local calls={}
package.preload['app.api']=function()return {escape=function(s)return tostring(s):gsub(' ','%%20')end,new=function()return {request=function(_,service,method,path,body,callback)calls[#calls+1]={service=service,path=path,callback=callback}end,update=function()end,quit=function()end}end}end
love={math={random=function()return 1 end},system={openURL=function(url)calls[#calls+1]={url=url};return true end}}
local Model=require('app.model');local passed=0
local function check(value,label)assert(value,label);passed=passed+1;print('GALLERY MODEL PASS '..label)end
local m=Model.new();m:showGallery();local old=calls[#calls]
m.galleryQuery='Ayara';m:galleryChanged();m:updateGallery(.3);local newer=calls[#calls]
check(m.galleryBusy,'Pending filters disable pagination before their debounce request')
old.callback({items={{id='stale'}},total=1});check(#m.galleryItems==0,'Typing a filter invalidates already queued pages')
newer.callback({items={{id='new'}},total=4});check(m.galleryItems[1].id=='new' and m.galleryTotal==4,'Newest filtered page becomes visible')
m:refreshGallery();local previousOpening=calls[#calls];m:showGallery();local currentOpening=calls[#calls]
previousOpening.callback({items={{id='old-opening'}},total=1});check(m.galleryItems[1].id=='new','Reopening the same gallery invalidates prior callbacks')
currentOpening.callback({items={{id='reopened'}},total=10});check(m.galleryItems[1].id=='reopened','Current opening can load its page')
m.galleryOffset=6;m:setGalleryLimit(4);check(m.galleryOffset==0 and m.galleryLimit==4,'Responsive page size resets its offset')
m.galleryArtist='Ryan Pancoast';m.gallerySet='eld';m.galleryVariant='extended';m.galleryLanguage='all';m:refreshGallery()
local path=calls[#calls].path
check(path:find('artist=Ryan%%20Pancoast') and path:find('set=eld') and path:find('variant=extended') and path:find('lang=all'),'Gallery query preserves artist, set, variant and language')
calls[#calls].callback(nil,'Index unavailable');check(m.galleryError=='Index unavailable' and #m.galleryItems==0,'Unavailable metadata produces an explicit empty/error state')
local before=#calls;m:openGalleryLink({url='file:///tmp/test'});m:openGalleryLink({url='javascript:alert(1)'})
check(#calls==before,'Artist links cannot open local files or executable URL schemes')
m:openGalleryLink({url='https://www.ryanpancoast.com/'});check(calls[#calls].url=='https://www.ryanpancoast.com/','Explicit artist-link click opens its supplied HTTPS destination')
print('Gallery model checks: '..passed..' passed')
