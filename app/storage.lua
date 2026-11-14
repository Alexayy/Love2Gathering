-- Storage/download presentation and transport. Destructive scope and image
-- selection remain authoritative in the catalog service.
local json=require('lib.json')
local Storage={}
local busyDownload={scanning=true,downloading=true,pausing=true}
local liveDownload={scanning=true,ready=true,downloading=true,pausing=true,paused=true,error=true}
local categories={
    export_duplicates={title='Duplicate exports',icon='collections',description='Remove only JPEG export copies that exactly match images already in the app cache. Cards and artwork stay available. Unmatched files are kept.'},
    replays={title='Replay timelines',icon='replay',description='Delete finished replay frames and event logs. Match history stays. Active recordings and unsynchronized replay data are protected.'},
    full_cards={title='Full-card image cache',icon='library',description='Delete downloaded full-card scans from the app cache and their managed export copies. Cards remain in your decks; scans must be downloaded again.'},
    art_crops={title='Artwork cache',icon='gallery',description='Delete downloaded artwork crops and their managed export copies. Gallery, deck covers, avatars and playmats may show placeholders until downloaded again.'},
}
Storage.categories=categories
function Storage.bytes(value)
    value=math.max(0,tonumber(value)or 0)
    local units={'B','KiB','MiB','GiB','TiB'};local i=1
    while value>=1024 and i<#units do value=value/1024;i=i+1 end
    return(i==1 and string.format('%.0f',value)or string.format('%.2f',value))..' '..units[i]
end
local function copy(value)return json.decode(json.encode(value))end
local function object(value)return type(value)=='table'and value~=json.null end
local function options(m)
    if not m.storageDownloadOptions then m.storageDownloadOptions={fullSize='normal',fullCards=true,artCrops=true,mirrors=false}end
    return m.storageDownloadOptions
end
local function selectedOptions(m)
    local out=options(m);local kinds=json.array()
    if out.fullCards then kinds[#kinds+1]='normal'end
    if out.artCrops then kinds[#kinds+1]='art_crop'end
    return{fullSize=out.fullSize,kinds=kinds,mirrors=out.mirrors==true}
end
function Storage.scanMatches(m)
    local scan=m.downloadStatus and m.downloadStatus.scan;if not object(scan)or m.downloadStatus.scanValid==false then return false end
    local desired=selectedOptions(m);local actual={}
    for _,kind in ipairs(scan.kinds or{})do actual[kind]=true end
    return desired.fullSize==scan.fullSize and desired.mirrors==(scan.mirrors==true)
        and (actual.normal or actual.large or false)==options(m).fullCards
        and (actual.art_crop or false)==options(m).artCrops
end
local function state(m)return m.downloadStatus and m.downloadStatus.state or'idle'end
function Storage.maintenanceBusy(m)
    return m.storageActionBusy or m.storageStatus and m.storageStatus.operation and m.storageStatus.operation.state=='running'
        or busyDownload[state(m)]or m.downloadActionBusy
end
local function categoryStats(m,key)
    local stats=m.storageStatus and m.storageStatus.stats or{}
    return stats[key]or(key=='export_duplicates'and stats.export_mirrors)or{}
end
local function invalidateImages(m,ready)
    for _,field in ipairs({'art','profileImages','galleryArt'})do
        if ready then m[field]={}
        else for key,entry in pairs(m[field]or{})do if not entry.image and not entry.pending then m[field][key]=nil end end end
    end
    m.artworkCacheInfo=nil;m.artworkCacheInfoRetry=0
end
local function operationDone(m,data)
    local op=data and data.operation;if not op or not op.id then return end
    m.storageWatchedOperations=m.storageWatchedOperations or{}
    if op.state=='running'then m.storageWatchedOperations[op.id]=op.categories or m.storagePendingCategories or{}end
    if op.state=='failed'then m.storageWatchedOperations[op.id]=nil;m.storagePendingCategories=nil;return end
    if op.state~='completed'or not m.storageWatchedOperations[op.id]then return end
    local chosen=type(op.categories)=='table'and#op.categories>0 and op.categories
        or op.result and type(op.result.categories)=='table'and#op.result.categories>0 and op.result.categories
        or m.storageWatchedOperations[op.id]
    m.storageWatchedOperations[op.id]=nil;m.storagePendingCategories=nil
    local names={};for _,name in ipairs(chosen or{})do names[name]=true end
    if names.full_cards or names.art_crops then
        invalidateImages(m,true);m.downloadEpoch=(m.downloadEpoch or 0)+1;m.downloadStatusBusy=false;m.downloadPollIn=0
        if m.downloadStatus and m.downloadStatus.scan then m.downloadStatus.scanValid=false;m.downloadStatus.scanInvalidReason='The image cache changed. Scan again before starting or resuming.'end
    end
    if names.replays then
        local page=m.page
        if m.replay and m.closeReplay then m:closeReplay();m.page=page end
        m.replaysVersion=(m.replaysVersion or 0)+1;m.replays={};m.replaysTotal=0
        if m.refreshReplays then m:refreshReplays()end
        if m.refreshHistory then m:refreshHistory()end
    end
end
local function adoptStorage(m,data)
    if data.operation or data.stats or data.dataDirectory then m.storageStatus=data
    elseif data.id and data.kind then m.storageStatus=m.storageStatus or{};m.storageStatus.operation=data end
    operationDone(m,m.storageStatus)
end
local function adoptDownload(m,data)
    m.downloadStatus=data
    if not m.storageDownloadHydrated and not m.storageDownloadOptionsDirty and object(data.scan)and data.scan.fullSize then
        local kinds={};for _,kind in ipairs(data.scan.kinds or{})do kinds[kind]=true end
        m.storageDownloadOptions={fullSize=data.scan.fullSize or'normal',fullCards=kinds.normal==true or kinds.large==true,artCrops=kinds.art_crop==true,mirrors=data.scan.mirrors==true}
    end
    m.storageDownloadHydrated=true
    local downloaded=tonumber(data.imagesAdded)or tonumber(data.downloaded)or 0
    if m.downloadObservedJob~=data.jobId then m.downloadObservedJob=data.jobId;m.downloadObservedCount=0 end
    if downloaded>(m.downloadObservedCount or 0)or data.state=='completed'and m.downloadObservedState~='completed'then
        m.downloadObservedCount=downloaded;invalidateImages(m,false);m.storagePollIn=0
    end
    if data.state=='completed'and m.downloadObservedState~='completed'then m.storageUsageStale=true end
    m.downloadObservedState=data.state
end
function Storage.install(Model)
    function Model:showStorage(section)
        if section=='cleanup'or section=='downloads'then self.storageSection=section end
        if self.openSettings then self:openSettings()else self.page='settings'end
        self.storageTabRequested=true;self:refreshStorage();self:refreshDownloadStatus()
    end
    function Model:refreshStorage(force,refreshUsage)
        if self.storageBusy and not force then return end
        self.storageRequestVersion=(self.storageRequestVersion or 0)+1;local version=self.storageRequestVersion
        self.storageBusy=true
        self:request('catalog','GET',refreshUsage and'/storage/status?refresh=1'or'/storage/status',nil,function(data,err)
            if self.storageRequestVersion~=version then return end
            self.storageBusy=false;self.storageError=err
            if data then adoptStorage(self,data)end
        end,true)
    end
    function Model:refreshDownloadStatus(force)
        if self.downloadActionBusy or self.downloadStatusBusy and not force then return end
        self.downloadRequestVersion=(self.downloadRequestVersion or 0)+1;local version=self.downloadRequestVersion;local epoch=self.downloadEpoch or 0
        self.downloadStatusBusy=true
        self:request('catalog','GET','/downloads/status',nil,function(data,err)
            if self.downloadRequestVersion~=version or(self.downloadEpoch or 0)~=epoch then return end
            self.downloadStatusBusy=false;self.downloadError=err
            if data then adoptDownload(self,data)end
        end,true)
    end
    function Model:previewStoragePurge(category)
        if not categories[category]or Storage.maintenanceBusy(self)then return false end
        local stats=categoryStats(self,category)
        if not self.storageStatus or self.storageStatus.scanning or not object(self.storageStatus.stats)then return false end
        self.storagePurgePreview={category=category,stats=copy(stats)};self.storageActionError=nil;return true
    end
    function Model:confirmStoragePurge()
        local preview=self.storagePurgePreview
        if not preview or not categories[preview.category]or Storage.maintenanceBusy(self)then return false end
        self.storageActionBusy=true;self.storageBusy=false;self.storageActionError=nil;self.storageRequestVersion=(self.storageRequestVersion or 0)+1
        self.storagePendingCategories=json.array({preview.category});local submitted=copy(self.storagePendingCategories)
        self:request('catalog','POST','/storage/purge',{categories=self.storagePendingCategories},function(data,err)
            self.storageActionBusy=false;self.storageActionError=err
            if not data then return end
            local op=data.operation or(data.id and data)
            if op and op.id then self.storageWatchedOperations=self.storageWatchedOperations or{};self.storageWatchedOperations[op.id]=submitted end
            self.storagePurgePreview=nil;adoptStorage(self,data);self.storagePollIn=0;self:refreshStorage(true)
        end,true)
        return true
    end
    function Model:compactStorage()
        if Storage.maintenanceBusy(self)then return false end
        local stats=self.storageStatus and self.storageStatus.stats and self.storageStatus.stats.database or{}
        if not stats.canCompact then return false end
        self.storagePurgePreview={category='compact',stats=copy(stats)};self.storageActionError=nil;return true
    end
    function Model:confirmStorageCompact()
        if not self.storagePurgePreview or self.storagePurgePreview.category~='compact'or Storage.maintenanceBusy(self)then return false end
        self.storageActionBusy=true;self.storageBusy=false;self.storageActionError=nil;self.storageRequestVersion=(self.storageRequestVersion or 0)+1
        self:request('catalog','POST','/storage/compact',{},function(data,err)
            self.storageActionBusy=false;self.storageActionError=err
            if data then self.storagePurgePreview=nil;adoptStorage(self,data);self.storagePollIn=0;self:refreshStorage(true)end
        end,true)
        return true
    end
    function Model:scanImageLibrary()
        if self.downloadActionBusy or busyDownload[state(self)]or Storage.maintenanceBusy(self)then return false end
        local payload=selectedOptions(self);if#payload.kinds==0 then return false end
        self.downloadEpoch=(self.downloadEpoch or 0)+1;local epoch=self.downloadEpoch
        self.downloadActionBusy=true;self.downloadError=nil;self.downloadStatusBusy=false
        self:request('catalog','POST','/downloads/scan',payload,function(data,err)
            if self.downloadEpoch~=epoch then return end
            self.downloadActionBusy=false;self.downloadError=err
            if data then adoptDownload(self,data);self.downloadPollIn=0 end
        end,true)
        return true
    end
    function Model:imageDownloadCommand(command)
        if self.downloadActionBusy or not({start=true,pause=true,resume=true,cancel=true})[command]then return false end
        local current=state(self)
        if command=='start'and(current~='ready'or not Storage.scanMatches(self)or self.downloadStatus.canStart==false)then return false end
        if command=='resume'and(current~='paused'and current~='error'or self.downloadStatus.canResume==false or self.downloadStatus.canResume~=true and self.downloadStatus.scanValid==false)then return false end
        if command=='pause'and current~='downloading'and current~='scanning'then return false end
        if command=='cancel'and not liveDownload[current]then return false end
        self.downloadEpoch=(self.downloadEpoch or 0)+1;local epoch=self.downloadEpoch
        self.downloadActionBusy=true;self.downloadStatusBusy=false;self.downloadError=nil
        self:request('catalog','POST','/downloads/control',{command=command},function(data,err)
            if self.downloadEpoch~=epoch then return end
            self.downloadActionBusy=false;self.downloadError=err
            if data then adoptDownload(self,data);self.downloadPollIn=0 end
        end,true)
        return true
    end
    function Model:updateStorage(dt)
        if self.catalogHealth and self.catalogHealth.ready and(tonumber(self.catalogHealth.apiVersion)or 0)>=8 then self.storageApiSupported=true end
        if not self.storageApiSupported then return end
        self.storagePollIn=(self.storagePollIn or 0)-dt;self.downloadPollIn=(self.downloadPollIn or 0)-dt
        if self.storagePollIn<=0 and not self.storageActionBusy then
            self.storagePollIn=Storage.maintenanceBusy(self)and 1.5 or 10;self:refreshStorage()
        end
        if self.downloadPollIn<=0 then self.downloadPollIn=busyDownload[state(self)]and 1 or 5;self:refreshDownloadStatus()end
    end
end

local function button(v,label,icon,w,h,opts)
    opts=opts or{};opts.W=w;opts.H=h;opts.Tooltip=opts.Tooltip or label
    opts.Image={Image=v.r.assets:buttonImage(icon,label,w,h,{font=v.r.fonts[16],iconSize=19})}
    return v.S.Button(label,opts)
end
local function text(v,value,w,color)v.S.Textf(tostring(value or''),{W=w,Color=color or v.r.colors.muted})end
local function line(v,icon,label,w,color)
    v.S.Image('storage-'..icon..label,{Image=v.r.assets:iconImage(icon,20,color),W=20,H=20});v.S.SameLine({CenterY=true});text(v,label,w-30,color)
end
local function statusLabel(m)
    local d=m.downloadStatus or{};local scan=d.scan or{};local current=d.state or'idle'
    if m.downloadError then return'Download status unavailable'end
    if current=='scanning'then return'Scanning image library…'end
    if current=='idle'then return'No image download is running'end
    if current=='ready'then return'Scan ready · '..tostring(scan.missing or 0)..' missing images'end
    local progress=string.format('%.0f%%',math.max(0,math.min(1,tonumber(d.progress)or 0))*100)
    return(current:gsub('^%l',string.upper))..' · '..progress..' · '..tostring(d.downloaded or 0)..' downloaded'
end
function Storage.tabs(v,width)
    local m=v.m;m.storageSection=m.storageSection or'cleanup'
    for i,item in ipairs({{'cleanup','Cleanup','delete'},{'downloads','Downloads','gallery'}})do
        if i>1 then v.S.SameLine({Pad=12})end
        if button(v,item[2],item[3],math.min(220,(width-12)/2),36,{Active=m.storageSection==item[1]})then m.storageSection=item[1]end
    end
    v.S.NewLine()
end
function Storage.build(v,width)
    local S,m=v.S,v.m;local C=v.r.colors;local data=m.storageStatus or{};local stats=object(data.stats)and data.stats or{};local busy=Storage.maintenanceBusy(m)
    if m.storageUsageStale and not m.storageBusy then m.storageUsageStale=nil;m:refreshStorage(true,true)
    elseif not m.storageStatus and not m.storageBusy then m:refreshStorage()end
    if not m.downloadStatus and not m.downloadStatusBusy then m:refreshDownloadStatus()end
    local op=object(data.operation)and data.operation or nil
    if m.storageSection~='downloads'then
    line(v,'library','Storage and image library',width,C.accent);S.NewLine()
    text(v,'Data folder',width,C.text);text(v,data.dataDirectory or m.catalogHealth and(m.catalogHealth.dataDirectory or m.catalogHealth.storage and m.catalogHealth.storage.dataDirectory)or'Loading…',width)
    if button(v,'Refresh usage','refresh',190,34,{Disabled=m.storageBusy})then m:refreshStorage(true,true);m:refreshDownloadStatus(true)end
    if data.scanning then S.SameLine({Pad=14,CenterY=true});S.Text('Measuring local files…',{Color=C.muted})end
    if m.storageError then text(v,m.storageError,width,C.gold)end
    S.NewLine()
    local db=stats.database or{}
    text(v,'Database '..Storage.bytes(db.bytes)..' · reusable space '..Storage.bytes(db.reusableBytes)..' · disk free '..Storage.bytes(db.freeBytes),width,C.text)
    text(v,'Purge makes deleted space reusable inside the database. Compact database returns that reusable space to the disk, using temporary space on this same drive.',width)
    if button(v,'Compact database','collections',225,34,{Disabled=busy or not db.canCompact})then m:compactStorage()end
    if not db.canCompact and db.compactionBlockedReason then text(v,db.compactionBlockedReason,width,C.gold)
    elseif not db.canCompact and tonumber(db.reusableBytes or 0)>0 then text(v,'Compaction needs about '..Storage.bytes(db.compactRequiredBytes)..' free on this drive.',width,C.gold)end
    S.Separator();S.NewLine()
    for _,key in ipairs({'export_duplicates','replays','full_cards','art_crops'})do
        local item=categoryStats(m,key);local meta=categories[key]
        line(v,meta.icon,meta.title,width,C.text)
        local count=item.count or 0;local size=item.bytes or 0
        local amount=(key=='export_duplicates'and'Up to 'or'')..tostring(count)..' '..(key=='replays'and'replays'or'images')..' · '..Storage.bytes(size)
        if(item.mirrorCount or 0)>0 then amount=amount..' + '..tostring(item.mirrorCount)..' exports · '..Storage.bytes(item.mirrorBytes)end
        text(v,amount,width,C.accent);text(v,meta.description,width)
        if key=='replays'and(item.protectedCount or 0)>0 then text(v,tostring(item.protectedCount)..' active or unsynchronized recordings are protected.',width,C.gold)end
        if button(v,'Purge '..meta.title:lower(),'delete',math.min(330,width),34,{Disabled=busy or data.scanning or not data.stats or count+(item.mirrorCount or 0)==0})then m:previewStoragePurge(key)end
        S.NewLine()
    end
    if op then text(v,(op.message or(op.kind or'Maintenance')..' · '..(op.state or'')),width,op.state=='failed'and C.gold or C.accent);if op.error then text(v,op.error,width,C.gold)end end
    if busyDownload[state(m)]then text(v,'Pause the image download before purging or compacting storage.',width,C.gold)end
    S.NewLine();return end
    line(v,'gallery','Download card images and artwork',width,C.accent);S.NewLine()
    text(v,'Save to '..tostring(data.dataDirectory or m.catalogHealth and m.catalogHealth.dataDirectory or'Loading…'),width)
    S.NewLine()
    local config=options(m);local changing=busyDownload[state(m)]or m.downloadActionBusy
    if S.CheckBox(config.fullCards,'Full-card scans',{Size=20,Disabled=changing})then config.fullCards=not config.fullCards;m.storageDownloadOptionsDirty=true end
    S.SameLine({Pad=20});if S.CheckBox(config.artCrops,'Artwork crops',{Size=20,Disabled=changing})then config.artCrops=not config.artCrops;m.storageDownloadOptionsDirty=true end
    S.NewLine()
    text(v,'Full-card size',width,C.text)
    local sizeChanged=m.storageOptionReleaseGuard~=nil
    local sizeLabel=config.fullSize=='large'and'Large (672 × 936)'or'Normal (488 × 680)'
    if changing then S.Button(sizeLabel,{W=math.min(330,width),H=34,Disabled=true,Tooltip='Pause the current job before changing image options.'})
    elseif S.BeginComboBox('download-full-size',{Selected=sizeLabel,W=math.min(330,width),H=34})then
        if S.TextSelectable('Normal (488 × 680)')then config.fullSize='normal';sizeChanged=true;m.storageOptionReleaseGuard=2;m.storageDownloadOptionsDirty=true end
        if S.TextSelectable('Large (672 × 936)')then config.fullSize='large';sizeChanged=true;m.storageOptionReleaseGuard=2;m.storageDownloadOptionsDirty=true end
        S.EndComboBox()
    end
    S.NewLine();if S.CheckBox(config.mirrors,'Also export separate JPEG folders',{Size=20,Disabled=changing or sizeChanged})then config.mirrors=not config.mirrors;m.storageDownloadOptionsDirty=true end
    text(v,'The app cache saves space. Export folders keep an additional JPEG copy; existing export folders stay unless you explicitly purge them.',width)
    if button(v,'Scan download size','search',230,36,{Disabled=changing or sizeChanged or busy or not(config.fullCards or config.artCrops)})then m:scanImageLibrary()end
    S.NewLine();text(v,statusLabel(m),width,C.accent)
    local download=m.downloadStatus or{};local scan=download.scan
    if object(scan)then
        text(v,tostring(scan.total or 0)..' image files · '..tostring(scan.cached or 0)..' cached · '..tostring(scan.missing or 0)..' missing',width,C.text)
        for _,kind in ipairs({'normal','large','art_crop'})do local row=scan.byKind and scan.byKind[kind]
            if row then text(v,(kind=='art_crop'and'Artwork'or'Full cards')..': '..tostring(row.missing or 0)..' missing · estimated '..Storage.bytes(row.estimatedBytes),width)end
        end
        text(v,'Estimated download '..Storage.bytes(scan.estimatedDownloadBytes)..' · new app cache '..Storage.bytes(scan.estimatedStorageBytes)..' · extra exports '..Storage.bytes(scan.estimatedMirrorBytes),width,C.text)
        text(v,'Estimate range '..Storage.bytes(scan.estimatedMinBytes)..'–'..Storage.bytes(scan.estimatedMaxBytes)..'. '..tostring(scan.estimateBasis or'Uses cached image sizes; actual files vary.'),width)
        text(v,'Retains '..Storage.bytes(download.reserveBytes or 3*1024^3)..' free disk space. Scanning does not download images.',width)
        if download.scanValid==false then text(v,download.scanInvalidReason or'The image cache changed. Scan again before starting or resuming.',width,C.gold)
        elseif not Storage.scanMatches(m)then text(v,'Image options changed. Scan again before starting a new download.',width,C.gold)end
    end
    if download.bytesDownloaded then text(v,Storage.bytes(download.bytesDownloaded)..' downloaded · '..Storage.bytes(download.rateBytesPerSecond)..'/s · '..tostring(download.failed or 0)..' failed',width)end
    local disabled=m.downloadActionBusy==true or op and op.state=='running'
    if state(m)=='ready'then
        if button(v,'Start download','play',210,36,{Disabled=disabled or not Storage.scanMatches(m)or download.canStart==false})then m:imageDownloadCommand('start')end
    elseif state(m)=='downloading'or state(m)=='scanning'then
        if button(v,'Pause download','pause',210,36,{Disabled=disabled})then m:imageDownloadCommand('pause')end
    elseif state(m)=='paused'or state(m)=='error'then
        if button(v,'Resume download','play',210,36,{Disabled=disabled or download.canResume==false or download.canResume~=true and download.scanValid==false})then m:imageDownloadCommand('resume')end
    end
    if liveDownload[state(m)]then
        S.SameLine({Pad=10});if button(v,'Cancel download','close',210,36,{Disabled=disabled or state(m)=='pausing'})then m:imageDownloadCommand('cancel')end
    end
    if m.storageOptionReleaseGuard and not love.mouse.isDown(1)then
        m.storageOptionReleaseGuard=m.storageOptionReleaseGuard-1
        if m.storageOptionReleaseGuard<=0 then m.storageOptionReleaseGuard=nil end
    end
    if download.error or m.downloadError then text(v,download.error or m.downloadError,width,C.gold)end
    S.NewLine()
end
function Storage.modal(v,w,h)
    local m,S=v.m,v.S;local preview=m.storagePurgePreview;if not preview then return end
    local width=math.min(640,w-56);local height=math.min(440,h-100);local inner=width-32;local C=v.r.colors
    v:window('storage-purge-confirm',(w-width)/2,(h-height)/2,width,height,preview.category=='compact'and'Compact database'or'Confirm purge',{Layer='ContextMenu',BgColor={.025,.04,.06,1}})
    if preview.category=='compact'then
        text(v,'Return reusable database space to the disk.',inner,C.text);S.NewLine()
        text(v,'Reusable space: '..Storage.bytes(preview.stats.reusableBytes)..'. Temporary free-space requirement: '..Storage.bytes(preview.stats.compactRequiredBytes)..'.',inner,C.accent)
        text(v,'This keeps decks, settings, profiles, cached images, history and recordings. It can take time; other storage operations wait until it finishes.',inner)
    else
        local meta=categories[preview.category]
        text(v,meta.title,inner,C.text);S.NewLine()
        text(v,(preview.category=='export_duplicates'and'Up to 'or'')..tostring(preview.stats.count or 0)..' items · '..Storage.bytes(preview.stats.bytes)..((preview.stats.mirrorBytes or 0)>0 and(' + '..Storage.bytes(preview.stats.mirrorBytes)..' export copies')or''),inner,C.accent)
        text(v,meta.description,inner);S.NewLine()
        text(v,preview.category=='export_duplicates'and'Every export is checked against the cached image before removal. Unique exports stay.'or'This removes all current items in this category. It cannot be undone. Deck lists, settings and profile selections stay.',inner,C.gold)
        if preview.category~='export_duplicates'then text(v,'Deleted database space becomes reusable first. Compact database can later return that space to the disk.',inner)end
    end
    S.NewLine();if m.storageActionError then text(v,m.storageActionError,inner,C.gold);S.NewLine()end
    if button(v,preview.category=='compact'and'Compact now'or'Purge now','delete',(inner-10)/2,40,{Disabled=m.storageActionBusy})then
        if preview.category=='compact'then m:confirmStorageCompact()else m:confirmStoragePurge()end
    end
    S.SameLine({Pad=10});if button(v,'Keep data','close',(inner-10)/2,40,{Disabled=m.storageActionBusy})then m.storagePurgePreview=nil end
    S.EndWindow()
end
function Storage.press(r,x,y,button)
    local box=r.storageProgressRect
    if button~=1 or not box or r:inputBlocked()or x<box.x or x>box.x+box.w or y<box.y or y>box.y+box.h then return false end
    local op=r.model.storageStatus and r.model.storageStatus.operation
    r.model:showStorage(op and op.state=='running'and'cleanup'or'downloads')
    return true
end
function Storage.drawProgress(r,w,h)
    local m=r.model;local download=m.downloadStatus or{};local op=m.storageStatus and m.storageStatus.operation
    local visible=liveDownload[download.state]or op and op.state=='running';if not visible then r.storageProgressRect=nil;return end
    local progress=math.max(0,math.min(1,tonumber(download.progress)or 0));local label=statusLabel(m)
    if op and op.state=='running'then progress=0;label=op.message or'Maintaining local storage…'end
    local x,y,width,height
    if m.page=='table'then x,y,width,height=w-268,46,246,3
    else width=math.min(480,w-48);x,y,height=(w-width)/2,66,16 end
    local C=r.colors;local tint=(download.state=='paused'or download.state=='error'or m.downloadError)and C.gold or C.accent
    love.graphics.push('all')
    if height>3 then r.assets:control(x,y,width,height,'dark')else love.graphics.setColor(C.panel[1],C.panel[2],C.panel[3],.98);love.graphics.rectangle('fill',x,y,width,height,2,2)end
    love.graphics.setColor(tint[1],tint[2],tint[3],.35);love.graphics.rectangle('fill',x,y,width*progress,height,2,2)
    if download.state=='scanning'or op and op.state=='running'then
        local motion=m.settings.reducedMotion and 0 or(love.timer.getTime()*.25)%1
        love.graphics.setColor(tint[1],tint[2],tint[3],.65);love.graphics.rectangle('fill',x+motion*(width-36),y,36,height,2,2)
    end
    if height>3 then r:text(r:fit(label,width-14,12,1),x+7,y+1,12,C.text,width-14,'center')end
    love.graphics.pop()
    r.storageProgressRect={x=x,y=y,w=width,h=height}
    r:hit({x=x,y=y,w=width,h=height,kind='download-progress',tooltip=label..'\n'..Storage.bytes(download.bytesDownloaded)..' downloaded · '..Storage.bytes(download.rateBytesPerSecond)..'/s\nOpen Settings → Storage for controls.',action=function()Storage.press(r,x+width/2,y+height/2,1)end})
end
return Storage
