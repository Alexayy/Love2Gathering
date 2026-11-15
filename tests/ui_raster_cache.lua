-- Contract/operation-count regression; real raster pixels are checked in LÖVE.
package.path='./?.lua;'..package.path
love={graphics={getDimensions=function()return 1440,900 end},window={getDPIScale=function()return 1 end}}
local Assets=require('app.assets');local calls,raster=0,0
local font={getWidth=function(_,s)calls=calls+1;return #s*8 end}
Assets.rasterize=function(w,h)raster=raster+1;return{getWidth=function()return w end,getHeight=function()return h end}end
local a=setmetatable({iconCache={},iconClock=0,iconCacheLimit=96,iconPixelLimit=8*1024*1024,settings={fontQuality='Standard'}},Assets)
local first=a:buttonImage('collection',string.rep('Long label ',16),180,34,{font=font})
assert(calls>1 and raster==1,'Initial label is measured/truncated and rasterized')
local measured=calls
for _=1,600 do assert(a:buttonImage('collection',string.rep('Long label ',16),180,34,{font=font})==first)end
assert(calls==measured and raster==1,'Warm buttons must reuse both text fitting and raster work')
Assets.invalidateRasterCaches();assert(a:buttonImage('collection',string.rep('Long label ',16),180,34,{font=font})~=first)
assert(calls>measured and raster==2,'A changed display raster epoch regenerates the actual label')
print('UI raster cache: 600 warm calls performed zero font measurements/rasterizations')
