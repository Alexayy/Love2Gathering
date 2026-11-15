-- Image transport/status only. Rules and token identity remain in their modules.
local API=require('app.api')
local Artwork={labels={loading='Loading artwork…',catalog='Card metadata unavailable',missing='Artwork is not cached',error='Artwork could not be loaded',ready=''}}
local function now()return love.timer.getTime()end
function Artwork.image(m,field,pendingField,key,path,limit,cacheLimit)
    m[field]=m[field]or{};m[pendingField]=m[pendingField]or 0
    local cache=m[field];local entry=cache[key];local time=now()
    if entry then entry.used=time;if entry.image or entry.pending or(entry.retryAt or 0)>time then return entry.image,entry.state end end
    if m[pendingField]>=limit then return nil,'loading'end
    entry={pending=true,state='loading',used=time};cache[key]=entry;m[pendingField]=m[pendingField]+1
    m.api:request('art','GET',path,nil,function(body,err,code)
        m[pendingField]=math.max(0,m[pendingField]-1);if cache[key]~=entry then return end
        entry.pending=false;entry.retryAt=now()+30;entry.state=code==404 and'missing'or'error'
        if not err and code==200 and body then
            local ok,image=pcall(function()return love.graphics.newImage(love.image.newImageData(love.filesystem.newFileData(body,'artwork.jpg')))end)
            if ok then entry.image=image;entry.state='ready'end
        end
        local count=0;for _ in pairs(cache)do count=count+1 end
        while count>(cacheLimit or 96)do
            local oldest,used;for id,cached in pairs(cache)do if id~=key and not cached.pending and(not used or cached.used<used)then oldest,used=id,cached.used end end
            if not oldest then break end;cache[oldest]=nil;count=count-1
        end
    end,true)
    return nil,'loading'
end
local function identity(m,card,kind)
    local data=m:cardData(card)
    if not data or not data.id or not(data.printing_id or data.image_uris)then return nil end
    if data.printingExact and data.printingResolved==false then return nil end
    local face=data.requested_face or 0;kind=kind or'normal'
    local exact=data.printingExact or data.tokenImageId~=nil
    return(data.printing_id or data.id)..'-'..face..'-'..kind..(exact and'-exact'or''),data,face,kind
end
function Artwork.get(m,card,force,kind)
    if not card or(not force and m.settings.showCardArt==false)then return nil end
    local key,data,face,imageKind=identity(m,card,kind);if not key then return nil,'catalog'end
    local path='/art/'..API.escape(data.id)..'?face='..face..'&kind='..API.escape(imageKind)..'&network='..(m.settings.localArtworkOnly~=false and'0'or'1')
    if data.printing_id then path=path..'&printing='..API.escape(data.printing_id)end
    if data.printingExact or data.tokenImageId then path=path..'&exact=1'end
    return Artwork.image(m,'art','artPending',key,path,force and 6 or 2)
end
function Artwork.install(Model)
    function Model:refreshArtworkCacheInfo()
        if self.artworkCacheInfoPending or(self.artworkCacheInfoRetry or 0)>now()then return end
        self.artworkCacheInfoPending=true;self.artworkCacheInfoRetry=now()+30
        self:request('catalog','GET','/art/cache-info',nil,function(data)
            self.artworkCacheInfoPending=false;if data then self.artworkCacheInfo=data end
        end,true)
    end
    function Model:artworkStatus(card,kind)
        if self.artworkCard then card=self:artworkCard(card);if not card then return'catalog'end end
        if card and(card.token or card.isToken)and not card.tokenImageId and self.resolveTokenCard then
            card=self:resolveTokenCard(card);if not card then return'catalog'end
        end
        local key=identity(self,card,kind);if not key then return'catalog'end
        local entry=self.art and self.art[key];return entry and entry.state or'loading'
    end
    function Model:artworkLabel(card,kind)return Artwork.labels[self:artworkStatus(card,kind)]or Artwork.labels.error end
end
return Artwork
