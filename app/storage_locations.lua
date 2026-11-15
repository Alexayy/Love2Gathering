local Locations={}
local function object(value)return type(value)=='table'and value~=require('lib.json').null end
local function adopt(m,data)
    m.storageLocations=data
    local op=object(data.operation)and data.operation or{}
    m.storageLocationBlocked=data.restartRequired==true or op.state=='preparing'
    if not m.storageLocationDraft or not m.storageLocationDirty then
        local active=data.configured or data.active
        if object(active)then m.storageLocationDraft={databaseDirectory=active.databaseDirectory or'',cacheDirectory=active.cacheDirectory or''}end
    end
end
function Locations.install(Model)
    function Model:refreshStorageLocations()
        if self.storageLocationsBusy then return end
        self.storageLocationsBusy=true;self.storageLocationVersion=(self.storageLocationVersion or 0)+1;local version=self.storageLocationVersion;local epoch=self.storageLocationEpoch or 0
        self:request('catalog','GET','/storage/locations',nil,function(data,err)
            if version~=self.storageLocationVersion or epoch~=(self.storageLocationEpoch or 0)then return end
            self.storageLocationsBusy=false;self.storageLocationError=err
            if data then adopt(self,data)end
        end,true)
    end
    function Model:setStorageLocation(key,value)
        if key~='databaseDirectory'and key~='cacheDirectory'then return false end
        self.storageLocationDraft=self.storageLocationDraft or{};self.storageLocationDraft[key]=value
        self.storageLocationDirty=true;self.storageLocationRevision=(self.storageLocationRevision or 0)+1
        self.storageLocationPlan=nil;self.storageLocationConfirm=nil;return true
    end
    function Model:validateStorageLocations()
        if self.storageLocationActionBusy or self.storageLocationBlocked or not self.storageLocationDraft then return false end
        self.storageLocationActionBusy=true;local revision=self.storageLocationRevision or 0
        local body={databaseDirectory=self.storageLocationDraft.databaseDirectory,cacheDirectory=self.storageLocationDraft.cacheDirectory}
        self:request('catalog','POST','/storage/locations/validate',body,function(data,err)
            self.storageLocationActionBusy=false
            if revision~=(self.storageLocationRevision or 0)then return end
            self.storageLocationError=err;self.storageLocationPlan=data
            if data and data.valid then self.storageLocationValidatedRevision=revision end
        end,true);return true
    end
    function Model:previewStorageLocations()
        local plan=self.storageLocationPlan
        if not plan or not plan.valid or self.storageLocationBlocked or self.storageLocationActionBusy or self.storageLocationValidatedRevision~=(self.storageLocationRevision or 0)then return false end
        if self.game and self.game.running then self:toast('Finish the current match before changing storage locations.',true);return false end
        self.storageLocationConfirm={revision=self.storageLocationRevision or 0,plan=plan};return true
    end
    function Model:prepareStorageLocations()
        local preview=self.storageLocationConfirm
        if not preview or self.storageLocationBlocked or self.storageLocationActionBusy or preview.revision~=(self.storageLocationRevision or 0)then return false end
        self.storageLocationActionBusy=true;self.storageLocationBlocked=true;self.storageLocationConfirm=nil
        self.storageLocationEpoch=(self.storageLocationEpoch or 0)+1;self.storageLocationsBusy=false;local epoch=self.storageLocationEpoch
        local plan=preview.plan
        self:request('catalog','POST','/storage/locations',{databaseDirectory=plan.databaseDirectory,cacheDirectory=plan.cacheDirectory},function(data,err)
            if epoch~=self.storageLocationEpoch then return end
            self.storageLocationActionBusy=false;self.storageLocationError=err
            if data then adopt(self,data)else self.storageLocationBlocked=false end
            self.storageLocationPollIn=0
        end,true);return true
    end
    function Model:cancelStorageLocations()
        if self.storageLocationActionBusy then return false end
        self.storageLocationEpoch=(self.storageLocationEpoch or 0)+1;self.storageLocationsBusy=false;local epoch=self.storageLocationEpoch
        self.storageLocationActionBusy=true
        self:request('catalog','POST','/storage/locations/cancel',{},function(data,err)
            if epoch~=self.storageLocationEpoch then return end
            self.storageLocationActionBusy=false;self.storageLocationError=err
            if data then adopt(self,data)end
            self.storageLocationPollIn=0
        end,true);return true
    end
    function Model:updateStorageLocations(dt)
        if not(self.catalogHealth and(tonumber(self.catalogHealth.apiVersion)or 0)>=9)then return end
        self.storageLocationPollIn=(self.storageLocationPollIn or 0)-dt
        if self.storageLocationPollIn<=0 then
            self.storageLocationPollIn=self.storageLocationBlocked and 1 or 12;self:refreshStorageLocations()
        end
    end
end
local function button(v,label,icon,w,disabled)
    return v.S.Button(label,{W=w,H=40,Disabled=disabled,Tooltip=label,Image={Image=v.r.assets:buttonImage(icon,label,w,40,{font=v.r.fonts[16],iconSize=20})}})
end
function Locations.build(v,width)
    local S,m,C=v.S,v.m,v.r.colors;local info=m.storageLocations
    S.PushFont(v.r.assets:titleFont(22,m.settings));S.Text('Database and image cache',{Color=C.accent});S.PopFont();S.NewLine()
    if not info then
        S.Textf(m.storageLocationError or'Loading current locations…',{W=width,Color=C.muted})
        if not m.storageLocationsBusy then m:refreshStorageLocations()end;return
    end
    local active=info.active or{};local draft=m.storageLocationDraft or{}
    S.Textf(active.separateCache and'Image files live in images.sqlite, independently of saved decks, profiles and replays.'or'This installation currently has a combined database. Preparing locations separates cached images into images.sqlite.',{W=width,Color=C.muted});S.NewLine()
    local disabled=m.storageLocationBlocked or m.storageLocationActionBusy or info.foreignPending
    for _,item in ipairs({{'databaseDirectory','Database folder'},{'cacheDirectory','Image cache folder'}})do
        S.Text(item[2],{Color=C.text})
        if S.Input('storage-location-'..item[1],{Text=draft[item[1]]or'',W=math.max(160,width-132),H=42,ReadOnly=disabled,Tooltip='Absolute directory path; the original data remains as a backup.'})then m:setStorageLocation(item[1],S.GetInputText())end
        S.SameLine({Pad=12});if button(v,'Browse','inspect',112,disabled)then m.storageFolderDialog={key=item[1],directory=draft[item[1]]}end
        S.NewLine()
    end
    S.Textf('Active saves: '..tostring(active.databaseFile or''),{W=width,Color=C.muted})
    S.Textf('Active images: '..tostring(active.cacheDatabaseFile or''),{W=width,Color=C.muted});S.NewLine()
    local error=m.storageLocationError or info.error
    if error then S.Textf(error,{W=width,Color=C.gold});S.NewLine()end
    if info.foreignPending then S.Textf('Another installation has a prepared location change; finish/cancel it there.',{W=width,Color=C.gold});S.NewLine()end
    if button(v,'Check locations','check',210,disabled)then m:validateStorageLocations()end
    local plan=m.storageLocationPlan
    if object(plan)then
        local bytes=require('app.storage').bytes
        for _,err in ipairs(plan.errors or{})do S.Textf(err,{W=width,Color=C.gold})end
        if plan.valid then
            S.NewLine();S.Textf('Copy up to '..bytes(plan.copyBytes)..'. Temporary space required: '..bytes(plan.requiredBytes)..'.',{W=width,Color=C.text})
            for _,volume in ipairs(plan.volumes or{})do S.Textf(tostring(volume.directory)..' · '..bytes(volume.freeBytes)..' free · '..bytes(volume.requiredBytes)..' required',{W=width,Color=C.muted})end
            S.NewLine();if button(v,'Prepare and use after restart','save',math.min(340,width),disabled)then m:previewStorageLocations()end
        end
    end
    local operation=object(info.operation)and info.operation or{}
    if operation.state then
        S.NewLine();local progress=(operation.total or 0)>0 and string.format(' · %.0f%%',100*(operation.done or 0)/operation.total)or''
        S.Textf((operation.message or operation.phase or operation.state)..progress,{W=width,Color=operation.state=='error'and C.gold or C.accent})
    end
    if not info.foreignPending and(operation.state=='preparing'or info.restartRequired)then
        S.NewLine();if button(v,'Cancel location change','close',280,m.storageLocationActionBusy)then m:cancelStorageLocations()end
    end
    if info.restartRequired then
        S.NewLine();S.Textf('Copies are ready. Close the client and start it again with run.sh to activate these locations. New matches and saves stay paused until restart.',{W=width,Color=C.gold})
        if button(v,'Close client','close',210,false)then love.event.quit()end
    else
        S.NewLine();S.Textf('The current store pauses while copies are prepared. Cached images, decks, profiles and replay delivery are verified before the next startup activates the new locations. Originals remain available as backups.',{W=width,Color=C.muted})
    end
end
function Locations.modal(v,w,h)
    local m,S=v.m,v.S;local preview=m.storageLocationConfirm
    if preview then
        local width=math.min(720,w-64);local inner=width-44
        v:window('storage-location-confirm',(w-width)/2,math.max(70,h/2-200),width,360,'Change storage locations',{Layer='Dialog'})
        S.Textf('Prepare verified copies and pause this installation until restart?',{W=inner,Color=v.r.colors.gold});S.NewLine()
        S.Textf('Saves: '..preview.plan.databaseDirectory,{W=inner});S.NewLine();S.Textf('Image cache: '..preview.plan.cacheDirectory,{W=inner});S.NewLine()
        S.Textf('Original files are retained. This does not erase the old cache or recordings. Close other clients using these folders before restarting.',{W=inner,Color=v.r.colors.muted});S.NewLine()
        if button(v,'Prepare copies','save',(inner-12)/2,false)then m:prepareStorageLocations()end
        S.SameLine({Pad=12});if button(v,'Keep current locations','close',(inner-12)/2,false)then m.storageLocationConfirm=nil end
        S.EndWindow()
    end
    if m.storageFolderDialog then
        local dialog=m.storageFolderDialog
        local result=S.FileDialog({Type='opendirectory',Directory=dialog.directory,AllowMultiSelect=false})
        if result.Button=='OK'then if result.Files and result.Files[1]then m:setStorageLocation(dialog.key,result.Files[1])end;m.storageFolderDialog=nil
        elseif result.Button=='Cancel'then m.storageFolderDialog=nil end
    end
end
return Locations
