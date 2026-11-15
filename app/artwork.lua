-- Image transport/status only. Rules and token identity remain in their modules.
local API=require('app.api')
local Artwork={labels={loading='Loading artwork…',catalog='Card metadata unavailable',missing='Artwork is not cached',error='Artwork could not be loaded',ready=''}}
local function now()return love.timer.getTime()end
local fields={'art','profileImages','galleryArt'}
local MiB=1024*1024
local wideFormats={rgba16=8,rgba16f=8,rgba32f=16,rg32f=8}
function Artwork.budget(m)
    local value=tonumber(m.settings and m.settings.artworkMemoryMiB)
    return(value==128 or value==512)and value*MiB or 256*MiB
end
local function touch(m,entry)
    m.artworkUseCounter=(m.artworkUseCounter or 0)+1;entry.order=m.artworkUseCounter;entry.used=now()
end
local function bytes(image)
    if image and image.getDimensions then
        local w,h=image:getDimensions();local format=image.getFormat and image:getFormat()
        return w*h*(wideFormats[format]or 4)
    end
    return 0
end
function Artwork.cacheInfo(m)
    local info={bytes=0,images=0,pending=0,statuses=0,budget=Artwork.budget(m)}
    local seen={}
    for _,field in ipairs(fields)do for _,entry in pairs(m[field]or{})do
        if entry.image then
            if not seen[entry.image]then seen[entry.image]=bytes(entry.image);info.bytes=info.bytes+seen[entry.image];info.images=info.images+1 end
            entry.bytes=seen[entry.image]
        elseif entry.pending then info.pending=info.pending+1 else info.statuses=info.statuses+1 end
    end end
    return info
end
function Artwork.trim(m,keep)
    local images,byImage,total={},{},0
    for _,field in ipairs(fields)do for key,entry in pairs(m[field]or{})do if entry.image then
        local group=byImage[entry.image]
        if not group then
            group={bytes=bytes(entry.image),order=0,aliases={}};byImage[entry.image]=group;images[#images+1]=group;total=total+group.bytes
        end
        entry.bytes=group.bytes;group.order=math.max(group.order,entry.order or 0);group.keep=group.keep or entry==keep
        group.aliases[#group.aliases+1]={cache=m[field],key=key,entry=entry}
    end end end
    table.sort(images,function(a,b)return a.order<b.order end)
    local count=#images;local budget=Artwork.budget(m);local evicted=false
    for _,item in ipairs(images)do
        if total<=budget and count<=512 then break end
        if not item.keep then
            for _,alias in ipairs(item.aliases)do if alias.cache[alias.key]==alias.entry then alias.cache[alias.key]=nil end end
            total=total-item.bytes;count=count-1;evicted=true
        end
    end
    -- A control may retain an Image until its next draw. Drop cache ownership
    -- without releasing that borrowed texture; incremental GC retires it safely.
    images=nil;byImage=nil
    if evicted then collectgarbage('step',256)end
    m.artworkMemory={bytes=total,images=count,budget=budget}
    return m.artworkMemory
end
local function release(value)
    if value and type(value)~='string'and value.release then value:release()end
end
local function upload(m,body,decoded,token)
    m.artworkDecodedUploads=m.artworkDecodedUploads or setmetatable({},{__mode='kv'})
    m.artworkDecodedTokens=m.artworkDecodedTokens or setmetatable({},{__mode='k'})
    if decoded and token and m.artworkDecodedTokens[decoded]==token and m.artworkDecodedUploads[decoded]then return m.artworkDecodedUploads[decoded]end
    local started=now()
    local file,data
    local ok,image=pcall(function()
        if not decoded then file=love.filesystem.newFileData(body,'artwork.jpg');data=love.image.newImageData(file)end
        local source=decoded or data
        if bytes(source)>Artwork.budget(m)then error('This image exceeds the decoded image memory budget')end
        return love.graphics.newImage(source)
    end)
    -- The API owns off-thread ImageData through all coalesced callbacks. Only
    -- the synchronous compatibility path owns and releases these local buffers.
    release(data);release(file)
    if ok then
        if decoded and token then m.artworkDecodedUploads[decoded]=image;m.artworkDecodedTokens[decoded]=token end
        local metrics=m.artworkUploadMetrics or{count=0,seconds=0,bytes=0};m.artworkUploadMetrics=metrics
        metrics.count=metrics.count+1;metrics.seconds=metrics.seconds+now()-started;metrics.bytes=metrics.bytes+bytes(image)
    end
    return ok and image or nil,not ok and tostring(image)or nil
end
function Artwork.image(m,field,pendingField,key,path,limit,cacheLimit,localOnly,options)
    options=options or{}
    local originalKey=key;local thumbnail=options.variant=='thumb';local selected=options.priority=='selected'or options.priority=='hand'
    local function parameter(value)path=path..(path:find('?',1,true)and'&'or'?')..value end
    if thumbnail then key=key..'-thumb';parameter('variant=thumb')end
    if selected then parameter('priority=selected')end
    if localOnly==nil then localOnly=not path:find('network=1',1,true)end
    m[field]=m[field]or{};m[pendingField]=m[pendingField]or 0
    local cache=m[field];local entry=cache[key];local time=now()
    if entry and entry.pending and entry.isCurrent and not entry.isCurrent()then
        local stale=entry;entry=stale.image and{image=stale.image,bytes=stale.bytes,state='ready',localOnly=stale.localOnly}or nil;cache[key]=entry
    end
    if entry then
        touch(m,entry)
        -- A local-only startup miss must not delay an explicitly enabled online
        -- view. Ready/pending images keep the same exact identity and cache.
        local retryOnline=localOnly==false and entry.localOnly and not entry.image and(not entry.pending or selected)
        local newSelection=selected and entry.selectionToken~=options.selectionToken and not entry.image
        local refreshThumb=thumbnail and entry.thumbPending and not entry.pending and time>=(entry.retryAt or 0)
        if not retryOnline and not newSelection and not refreshThumb and(entry.image or entry.pending or(entry.retryAt or 0)>time)then
            local fallback=thumbnail and cache[originalKey];return entry.image or fallback and fallback.image,entry.state
        end
    end
    -- Selected work has a separate bounded API lane; an old visible lookup must
    -- never prevent the explicit request from upgrading Cache only to network.
    if options.priority=='hand'and m[pendingField]>=2 or not selected and m[pendingField]>=limit then return entry and entry.image,'loading'end
    local previous=entry
    entry={pending=true,state=previous and previous.image and'ready'or'loading',image=previous and previous.image,bytes=previous and previous.bytes,used=time,localOnly=localOnly,selectionToken=options.selectionToken,isCurrent=options.isCurrent};touch(m,entry);cache[key]=entry;m[pendingField]=m[pendingField]+1
    m.api:request('art','GET',path,nil,function(body,err,code,decoded,timings,meta)
        m[pendingField]=math.max(0,m[pendingField]-1);if cache[key]~=entry then return end
        if code==499 then cache[key]=previous and previous.image and previous or nil;return end
        entry.pending=false;entry.retryAt=now()+(code==503 and 1 or 30);entry.state=code==404 and'missing'or'error'
        entry.error=err
        if not err and code==200 and(body or decoded)then
            local original=thumbnail and meta and meta.variant=='original'
            local full=original and cache[originalKey]
            if full and full.image then entry.image=full.image
            else entry.image,entry.error=upload(m,body,decoded,timings)end
            if entry.image then entry.state='ready';entry.bytes=bytes(entry.image);touch(m,entry)end
            if original and entry.image and not(full and full.image)then cache[originalKey]={image=entry.image,bytes=entry.bytes,state='ready',localOnly=localOnly};touch(m,cache[originalKey])end
            entry.thumbPending=thumbnail and meta and meta.thumbPending and not meta.thumbUnavailable or false
            if entry.thumbPending then entry.retryAt=now()+1 end
        end
        -- Negative statuses are cheap and keep their own bounded retry cache;
        -- ready textures share one byte budget across cards, gallery and profile.
        local count=0;for _,cached in pairs(cache)do if not cached.image then count=count+1 end end
        local statusLimit=math.max(16,cacheLimit or 96)
        while count>statusLimit do
            local oldest,used;for id,cached in pairs(cache)do if id~=key and not cached.image and not cached.pending and(not used or(cached.order or 0)<used)then oldest,used=id,cached.order or 0 end end
            if not oldest then break end;cache[oldest]=nil;count=count-1
        end
        Artwork.trim(m,entry)
    end,'image',{priority=options.priority,isCurrent=options.isCurrent,selectionToken=options.selectionToken})
    local fallback=thumbnail and cache[originalKey]
    return entry.image or fallback and fallback.image,entry.state
end
local function identity(m,card,kind)
    local data=m:cardData(card)
    if not data or not data.id or not(data.printing_id or data.image_uris)then return nil end
    if data.printingExact and data.printingResolved==false then return nil end
    local face=data.requested_face or 0;kind=kind or'normal'
    local exact=data.printingExact or data.tokenImageId~=nil
    return(data.printing_id or data.id)..'-'..face..'-'..kind..(exact and'-exact'or''),data,face,kind
end
function Artwork.get(m,card,force,kind,localOnly,options)
    options=options or{}
    if not card or(not force and m.settings.showCardArt==false)then return nil end
    local key,data,face,imageKind=identity(m,card,kind);if not key then return nil,'catalog'end
    local offline=localOnly==true or options.network~=true and m.settings.localArtworkOnly~=false
    local path='/art/'..API.escape(data.id)..'?face='..face..'&kind='..API.escape(imageKind)..'&network='..(offline and'0'or'1')
    if data.printing_id then path=path..'&printing='..API.escape(data.printing_id)end
    if data.printingExact or data.tokenImageId then path=path..'&exact=1'end
    local pending=options.priority=='selected'and'selectedArtPending'or options.priority=='hand'and'handArtPending'or'artPending'
    return Artwork.image(m,'art',pending,key,path,force and 6 or 4,nil,offline,options)
end
Artwork.identity=identity
function Artwork.cached(m,card,kind)
    local key=identity(m,card,kind);local entry=key and m.art and m.art[key]
    if entry and entry.image then touch(m,entry);return entry.image,'ready'end
    return nil,entry and entry.state or'loading'
end
function Artwork.install(Model)
    function Model:refreshArtworkCacheInfo()
        if self.artworkCacheInfoPending or(self.artworkCacheInfoRetry or 0)>now()then return end
        self.artworkCacheInfoPending=true;self.artworkCacheInfoRetry=now()+30
        self:request('catalog','GET','/art/cache-info',nil,function(data)
            self.artworkCacheInfoPending=false;if data then self.artworkCacheInfo=data end
        end,true)
    end
    function Model:artworkStatus(card,kind,options)
        if self.artworkCard then card=self:artworkCard(card);if not card then return'catalog'end end
        if card and(card.token or card.isToken)and not card.tokenImageId and self.resolveTokenCard then
            card=self:resolveTokenCard(card);if not card then return'catalog'end
        end
        local key=identity(self,card,kind);if not key then return'catalog'end
        if options and options.variant=='thumb'then key=key..'-thumb'end
        local entry=self.art and self.art[key];return entry and entry.state or'loading'
    end
    function Model:artworkLabel(card,kind,options)return Artwork.labels[self:artworkStatus(card,kind,options)]or Artwork.labels.error end
end
return Artwork
