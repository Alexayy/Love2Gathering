-- A local archive is inspected first; only the reviewed Install action writes
-- its images. Validation, cache identity and import locks remain in the service.
local Storage=require('app.storage')
local Packs={}
local active={inspecting=true,importing=true,installing=true}
local function state(m)return m.imagePackStatus and m.imagePackStatus.state or'idle'end
function Packs.active(m)return active[state(m)]==true end
local function problem(m)
    if m.storageLocationBlocked then return'Finish or cancel the storage location change before installing an image pack.'end
    local download=m.downloadStatus and m.downloadStatus.state
    if download=='downloading'or download=='scanning'or download=='pausing'then return'Pause the image download before installing this pack.'end
    if Storage.maintenanceBusy(m)then return'Wait for the current storage operation to finish.'end
end
local function invalidate(m)
    for _,field in ipairs({'art','profileImages','galleryArt'})do
        for key,entry in pairs(m[field]or{})do if not entry.image then m[field][key]=nil end end
    end
    m.artworkCacheInfo=nil;m.artworkCacheInfoRetry=0;m.storageUsageStale=true
    if m.downloadStatus and m.downloadStatus.scan then m.downloadStatus.scanValid=false;m.downloadStatus.scanInvalidReason='An image pack added cached images. Scan again before starting or resuming the download.'end
end
local function adopt(m,data)
    m.imagePackStatus=data;m.imagePackLoaded=true
    if not m.imagePackJob and data.jobId and not m.imagePackPathEdited then
        m.imagePackPath=data.path or m.imagePackPath;m.imagePackJob=data.jobId;m.imagePackInspectedRevision=m.imagePackPathRevision or 0
    end
    if data.state=='completed'and data.jobId and m.imagePackCompletedJob~=data.jobId then
        m.imagePackCompletedJob=data.jobId
        if(tonumber(data.installed or data.installedImages)or 0)>0 then invalidate(m)end
    end
end
local function reviewed(m)
    local status=m.imagePackStatus or{}
    return status.state=='ready'and status.jobId~=nil and status.jobId==m.imagePackJob and m.imagePackInspectedRevision==(m.imagePackPathRevision or 0)
end
function Packs.install(Model)
    function Model:setImagePackPath(path)
        self.imagePackPath=tostring(path or'');self.imagePackPathRevision=(self.imagePackPathRevision or 0)+1
        self.imagePackPathEdited=true;self.imagePackJob=nil;self.imagePackError=nil
    end
    function Model:refreshImagePacks()
        if self.imagePackStatusBusy then return end
        local epoch=self.imagePackEpoch or 0;self.imagePackStatusBusy=true
        self:request('catalog','GET','/storage/image-packs/status',nil,function(data,err)
            if epoch~=(self.imagePackEpoch or 0)then return end
            self.imagePackStatusBusy=false;self.imagePackError=err
            if type(data)=='table'then adopt(self,data)end
        end,true)
    end
    function Model:inspectImagePack()
        if Packs.active(self)or self.imagePackActionBusy or self.storageLocationBlocked then return false end
        local path=(self.imagePackPath or''):match('^%s*(.-)%s*$')
        if path==''or#path>4096 or path:find('[%z\1-\31]')then self.imagePackError='Choose a local Starter image pack ZIP file.';return false end
        self.imagePackEpoch=(self.imagePackEpoch or 0)+1;local epoch=self.imagePackEpoch;local revision=self.imagePackPathRevision or 0
        self.imagePackStatusBusy=false;self.imagePackActionBusy=true;self.imagePackError=nil;self.imagePackJob=nil;self.imagePackPathEdited=true
        self:request('catalog','POST','/storage/image-packs/inspect',{path=path},function(data,err)
            if epoch~=self.imagePackEpoch then return end
            self.imagePackActionBusy=false;self.imagePackError=err;self.imagePackPollIn=0
            if type(data)=='table'then
                if revision==(self.imagePackPathRevision or 0)then self.imagePackPath=data.path or path;self.imagePackJob=data.jobId;self.imagePackInspectedRevision=revision end
                adopt(self,data)
            end
        end,true)
        return true
    end
    function Model:installImagePack()
        if self.imagePackActionBusy or problem(self)or not reviewed(self)then return false end
        local status=self.imagePackStatus
        if(tonumber(status.missing or status.missingImages)or 0)<=0 then return false end
        self.imagePackEpoch=(self.imagePackEpoch or 0)+1;local epoch=self.imagePackEpoch
        self.imagePackStatusBusy=false;self.imagePackActionBusy=true;self.imagePackError=nil
        self:request('catalog','POST','/storage/image-packs/install',{jobId=status.jobId},function(data,err)
            if epoch~=self.imagePackEpoch then return end
            self.imagePackActionBusy=false;self.imagePackError=err;self.imagePackPollIn=0
            if type(data)=='table'then adopt(self,data)end
        end,true)
        return true
    end
    function Model:updateImagePacks(dt)
        local visible=(self.page=='settings'or self.settingsOpen)and self.storageSection=='downloads'
        if not Packs.active(self)and not visible then return end
        self.imagePackPollIn=(self.imagePackPollIn or 0)-dt
        if self.imagePackPollIn<=0 then self.imagePackPollIn=Packs.active(self)and 1 or 10;self:refreshImagePacks()end
    end
    function Model:browseImagePack()
        if Packs.active(self)or self.imagePackActionBusy then return false end
        self.imagePackFileDialog={directory=(self.imagePackPath or''):match('^(.*)[/\\][^/\\]*$')};return true
    end
    function Model:dropImagePack(file)return Packs.fileDropped(self,file)end
end
function Packs.fileDropped(m,file)
    local path=file and file.getFilename and file:getFilename()
    if type(path)~='string'or not path:lower():match('%.zip$')then return false end
    if Packs.active(m)or m.imagePackActionBusy or m.storageLocationBlocked then m.imagePackError=problem(m)or'Wait for the current image pack to finish.';return true end
    m:setImagePackPath(path)
    if m.showStorage then m:showStorage('downloads')else m.page='settings';m.storageSection='downloads';m.storageTabRequested=true end
    m:inspectImagePack();return true
end
local function button(v,label,icon,width,disabled,tooltip)
    return v.S.Button(label,{W=width,H=36,Disabled=disabled,Tooltip=tooltip or label,Image={Image=v.r.assets:buttonImage(icon,label,width,36,{font=v.r.fonts[16],iconSize=19})}})
end
function Packs.build(v,width)
    local S,m,C=v.S,v.m,v.r.colors
    if not m.refreshImagePacks then return end
    if not m.imagePackLoaded and not m.imagePackStatusBusy and not m.imagePackError then m:refreshImagePacks()end
    S.Separator();S.NewLine()
    S.Image('starter-image-pack-icon',{Image=v.r.assets:iconImage('collections',20,C.accent),W=20,H=20});S.SameLine({CenterY=true});S.Text('Optional Starter image pack',{Color=C.accent});S.NewLine()
    S.Textf('Install images from a local Starter pack ZIP. Inspect checks the archive and shows what it will add. Existing cached images and deck lists stay in place.',{W=width,Color=C.muted});S.NewLine()
    local busy=Packs.active(m)or m.imagePackActionBusy;local blocked=problem(m)
    local data=m.imagePackStatus or{}
    S.Text('Image pack file',{Color=C.text})
    if S.Input('starter-image-pack-path',{Text=m.imagePackPath or'',W=math.max(180,width-124),H=38,ReadOnly=busy,Align='left',Tooltip='Local Starter image pack ZIP file. You can also drop a ZIP onto the client to inspect it.'})then m:setImagePackPath(S.GetInputText())end
    S.SameLine({Pad=10});if button(v,'Browse','inspect',110,busy)then m:browseImagePack()end
    S.NewLine()
    local fresh=reviewed(m)
    local linked=data.jobId~=nil and data.jobId==m.imagePackJob and m.imagePackInspectedRevision==(m.imagePackPathRevision or 0)
    local error=m.imagePackError or linked and data.state=='error'and data.error
    if error then S.Textf(error,{W=width,Color=C.gold});S.NewLine()end
    local busyLabel=state(m)=='importing'or state(m)=='installing'
    if button(v,busy and(busyLabel and'Installing images…'or'Checking image pack…')or'Inspect pack','inspect',230,busy or m.storageLocationBlocked or(m.imagePackPath or''):match('^%s*$')~=nil,'Read and verify this local archive; do not install its images yet')then m:inspectImagePack()end
    if blocked then S.NewLine();S.Textf(blocked,{W=width,Color=C.gold})end
    if fresh then
        local images=tonumber(data.images)or 0;local cached=tonumber(data.cached or data.cachedImages)or 0;local missing=tonumber(data.missing or data.missingImages)or 0
        S.NewLine();S.Textf(tostring(images)..' images · '..Storage.bytes(data.totalBytes)..' · '..cached..' already cached · '..missing..' to add',{W=width,Color=C.text})
        if data.complete==false then S.Textf('This pack is incomplete: '..tostring(data.missingEntries or 0)..' expected Starter images are absent. Available images can still be installed.',{W=width,Color=C.gold})end
        S.Textf('Only missing images are added to your configured image cache. This does not download cards or change your decks.',{W=width,Color=C.muted});S.NewLine()
        if button(v,'Install '..missing..' images','save',250,m.imagePackActionBusy or blocked~=nil or missing==0,'Install only the missing images from this reviewed archive')then m:installImagePack()end
        if missing==0 then S.NewLine();S.Textf('Every image in this pack is already cached.',{W=width,Color=C.accent})end
    elseif Packs.active(m)then
        local progress=math.max(0,math.min(1,tonumber(data.progress)or 0))
        S.NewLine();S.Textf((data.state=='inspecting'and'Checking archive'or'Installing images')..string.format(' · %.0f%%',progress*100)..' · '..tostring(data.processed or 0)..' / '..tostring(data.images or 0),{W=width,Color=C.accent})
    elseif linked and data.state=='completed'then
        S.NewLine();S.Textf('Image pack installed · '..tostring(data.installed or data.installedImages or 0)..' added · '..tostring(data.skipped or data.skippedImages or 0)..' already cached',{W=width,Color=C.accent})
    end
    S.NewLine()
end
function Packs.modal(v)
    local m=v.m;if not m.imagePackFileDialog then return end
    if m.imagePackCancelRequested then
        -- FileDialog leaves a registered Slab stack lock until its dialog is
        -- closed while active. Clearing our flag alone would lock the client.
        if v.S.BeginDialog('FileDialog')then v.S.CloseDialog();v.S.EndDialog()end
        m.imagePackFileDialog=nil;m.imagePackCancelRequested=nil;return
    end
    local result=v.S.FileDialog({Type='openfile',Title='Choose a Starter image pack',Directory=m.imagePackFileDialog.directory,AllowMultiSelect=false,Filters={{'*.zip','Image pack'}}})
    if result.Button=='OK'then
        if result.Files and result.Files[1]then m:setImagePackPath(result.Files[1])end
        m.imagePackFileDialog=nil
    elseif result.Button=='Cancel'then m.imagePackFileDialog=nil end
end
return Packs
