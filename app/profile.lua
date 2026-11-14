-- Public card-art identity. Life always comes from the native player projection.
local API=require('app.api')
local json=require('lib.json')
local Profile={}
local function copy(value)return json.decode(json.encode(value))end
local function init(m)
    m.profile=m.profile or {name=m.playerName or 'Planeswalker'}
    m.profileDraft=m.profileDraft or copy(m.profile)
    m.profileSlot=m.profileSlot or 'avatar';m.profileQuery=m.profileQuery or ''
    m.profileItems=m.profileItems or {};m.profileOffset=m.profileOffset or 0;m.profileLimit=m.profileLimit or 8
end
function Profile.reference(item)
    if not item then return nil end
    return {oracleId=item.oracleId or item.oracle_id,printingId=item.printingId or item.printing_id,face=item.face or item.requested_face or 0,name=item.name}
end
function Profile.install(Model)
    function Model:loadProfile()
        init(self);self.profileLoadVersion=(self.profileLoadVersion or 0)+1;local version=self.profileLoadVersion;local priorName=self.playerName;local priorRoomName=self.roomSetup and self.roomSetup.playerName or priorName
        self:request('catalog','GET','/profile',nil,function(data,err)
            if version~=self.profileLoadVersion then return end
            self.profileLoaded=data~=nil;self.profileLoadError=err
            if data then
                self.profile=copy(data);if self.playerName==priorName then self.playerName=data.name end
                if not self.profileDirty then self.profileDraft=copy(data)end
                if self.roomSetup and not self.roomConnectionId and self.roomSetup.playerName==priorRoomName then self.roomSetup.playerName=data.name end
            end
        end,true)
    end
    function Model:showProfile()
        init(self);if self.replay then self.replay.playing=false end
        self.profileOpening=(self.profileOpening or 0)+1;self.page='profile'
        if not self.profileLoaded then self:loadProfile()end
        self:refreshProfileArt()
    end
    function Model:profileOptions()init(self);return copy(self.profile)end
    function Model:setProfileName(name)init(self);self.profileDraft.name=name;self.profileDirty=true;self.profileEditVersion=(self.profileEditVersion or 0)+1 end
    function Model:chooseProfileArt(slot,item)
        init(self);if slot~='avatar'and slot~='playmat'then return false end
        local ref=Profile.reference(item);if not ref or not ref.printingId or not ref.oracleId then return false end
        self.profileDraft[slot]=ref;self.profileDirty=true;self.profileError=nil;self.profileEditVersion=(self.profileEditVersion or 0)+1;return true
    end
    function Model:clearProfileArt(slot)
        init(self);if slot~='avatar'and slot~='playmat'then return false end
        self.profileDraft[slot]=nil;self.profileDirty=true;self.profileEditVersion=(self.profileEditVersion or 0)+1;return true
    end
    function Model:resetProfileDraft()init(self);self.profileDraft=copy(self.profile);self.profileDirty=false;self.profileError=nil;self.profileEditVersion=(self.profileEditVersion or 0)+1 end
    function Model:saveProfile()
        init(self);if self.profileSaving then return false end
        self.profileSaving=true;self.profileError=nil;self.profileLoadVersion=(self.profileLoadVersion or 0)+1;local submitted=copy(self.profileDraft);local opening=self.profileOpening;local edit=self.profileEditVersion or 0;local priorName=self.playerName;local priorRoomName=self.roomSetup and self.roomSetup.playerName or priorName
        self:request('catalog','PUT','/profile',submitted,function(data,err)
            self.profileSaving=false
            if data then
                self.profile=copy(data);if self.playerName==priorName then self.playerName=data.name end
                if opening==self.profileOpening and edit==(self.profileEditVersion or 0)then self.profileDraft=copy(data);self.profileDirty=false end
                if self.roomSetup and not self.roomConnectionId and self.roomSetup.playerName==priorRoomName then self.roomSetup.playerName=data.name end
                self:toast('Profile saved')
            else self.profileError=err or 'Profile could not be saved'end
        end,true);return true
    end
    function Model:profileSearchChanged()
        init(self);self.profileOffset=0;self.profileSearchVersion=(self.profileSearchVersion or 0)+1;self.profileSearchTimer=.23
    end
    function Model:refreshProfileArt()
        init(self);self.profileSearchTimer=nil;self.profileSearchVersion=(self.profileSearchVersion or 0)+1
        local version,opening=self.profileSearchVersion,self.profileOpening;self.profileBusy=true;self.profileSearchError=nil
        self:request('catalog','GET','/gallery?q='..API.escape(self.profileQuery)..'&lang=en&limit='..self.profileLimit..'&offset='..self.profileOffset,nil,function(data,err)
            if version~=self.profileSearchVersion or opening~=self.profileOpening then return end
            self.profileBusy=false
            if data then self.profileItems=data.items or {};self.profileTotal=data.total or 0
            else self.profileItems={};self.profileSearchError=err or 'Card artwork index is unavailable'end
        end,true)
    end
    function Model:updateProfile(dt)
        init(self);if self.page~='profile'then return end
        if self.profileWasReady~=self.catalogHealth.ready then self.profileWasReady=self.catalogHealth.ready;if self.catalogHealth.ready then self.profileSearchTimer=0 end end
        if self.profileSearchTimer then self.profileSearchTimer=self.profileSearchTimer-dt;if self.profileSearchTimer<=0 then self:refreshProfileArt()end end
    end
    function Model:profileForPlayer(player)
        if player and type(player.profile)=='table'then return player.profile end
        init(self);return player and(player.human or player.isLocal)and self.profile or {name=player and player.name or 'Planeswalker'}
    end
    function Model:profileArt(reference)
        if not reference or not reference.printingId then return nil end
        self.profileImages=self.profileImages or {};self.profileArtPending=self.profileArtPending or 0
        local key=reference.printingId..':'..tostring(reference.face or 0);local time=love.timer.getTime();local entry=self.profileImages[key]
        if entry then entry.used=time;if entry.image or entry.pending or(entry.retryAt or 0)>time then return entry.image end end
        if self.profileArtPending>=4 then return nil end
        entry={used=time,pending=true};self.profileImages[key]=entry;self.profileArtPending=self.profileArtPending+1
        local path='/gallery/art/'..API.escape(reference.printingId)..'?face='..tostring(reference.face or 0)..'&kind=art_crop&network='..(self.settings.localArtworkOnly~=false and'0'or'1')
        self.api:request('art','GET',path,nil,function(body,err,code)
            self.profileArtPending=math.max(0,self.profileArtPending-1);if self.profileImages[key]~=entry then return end
            entry.pending=false;entry.retryAt=love.timer.getTime()+30
            if not err and code==200 and body then
                local ok,image=pcall(function()return love.graphics.newImage(love.image.newImageData(love.filesystem.newFileData(body,'profile.jpg')))end)
                if ok then entry.image=image end
            end
            local count=0;for _ in pairs(self.profileImages)do count=count+1 end
            while count>32 do local oldest,used;for id,cached in pairs(self.profileImages)do if id~=key and not cached.pending and(not used or cached.used<used)then oldest,used=id,cached.used end end;if not oldest then break end;self.profileImages[oldest]=nil;count=count-1 end
        end,true);return nil
    end
end
return Profile
