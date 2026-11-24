package.path='./?.lua;./?/init.lua;'..package.path
local Startup=require('app.startup')
local function contains(text,part)assert(text:find(part,1,true),text..' did not include '..part)end
local waiting=Startup.catalogMessage({state='waiting',seconds=12.4})
contains(waiting,'Waiting for another local card index');contains(waiting,'12s')
contains(Startup.catalogMessage({state='waiting',phase='checking'}),'Checking the existing')
local reading=Startup.catalogMessage({state='indexing',phase='reading',cards=0,lines=32000,bytesRead=512,totalBytes=1024})
contains(reading,'50%');contains(reading,'32000 entries');contains(reading,'0 cards')
local finishing=Startup.catalogMessage({state='indexing',phase='indexes',cards=42000,indexesDone=6,indexesTotal=14,seconds=45.7})
contains(finishing,'Preparing local card and artwork search');contains(finishing,'6 / 14');contains(finishing,'45s')
assert(not finishing:find('0 cards',1,true))
contains(Startup.catalogMessage({phase='reading',bytesRead=100,totalBytes=100}),'99%')
contains(Startup.catalogMessage({state='indexing',cards=12}),'12 cards')
print('catalog progress presentation passed')
