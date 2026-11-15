-- Installed engine discovery. Keep native format/setup support separate from
-- catalog construction checks and card implementation coverage.
local Capabilities={fallback={'Modern','Standard','Pioneer','Commander'}}
local function identity(m)return tostring(m.api.enginePort)..'|'..tostring((m.engineHealth or{}).instanceId or'')end
function Capabilities.install(Model)
    function Model:snapshotFilterAvailable(format)
        local id=tostring(format or self.searchFormat or''):lower()
        local info=self.searchFilterInfo
        if info and tostring(info.formatId or''):lower()==id then return info.snapshotFilterAvailable==true end
        return id=='modern'or id=='standard'or id=='pioneer'or id=='commander'
    end
    function Model:catalogSearchHint()
        return self:snapshotFilterAvailable()and'Cards for this format · double-click or drag to add'or'Full catalog · XMage validates the format when the match starts'
    end
    function Model:playFormats()
        local out={}
        for _,format in ipairs(self.nativeCapabilities and self.nativeCapabilities.formatDetails or{})do
            if format.supported==true and format.construction~='limited'and format.id~='Limited'then out[#out+1]=format.id end
        end
        if#out==0 then for _,id in ipairs(Capabilities.fallback)do out[#out+1]=id end end
        return out
    end
    function Model:refreshNativeCapabilities()
        if self.nativeCapabilitiesPending then return false end
        self.nativeCapabilitiesRequest=(self.nativeCapabilitiesRequest or 0)+1
        local request,key=self.nativeCapabilitiesRequest,identity(self)
        self.nativeCapabilitiesPending=true;self.nativeCapabilitiesRetry=30
        self:request('engine','GET','/capabilities',nil,function(data,err)
            if self.nativeCapabilitiesRequest~=request or identity(self)~=key then return end
            self.nativeCapabilitiesPending=false
            if type(data)=='table'and type(data.formatDetails)=='table'then self.nativeCapabilities=data;self.nativeCapabilitiesError=nil
            else self.nativeCapabilitiesError=err or'Installed engine capabilities are unavailable'end
        end,true)
        return true
    end
    local update=Model.update
    function Model:update(dt)
        update(self,dt)
        local key=identity(self)
        if self.nativeCapabilitiesIdentity~=key then
            self.nativeCapabilitiesIdentity=key;self.nativeCapabilitiesRequest=(self.nativeCapabilitiesRequest or 0)+1
            self.nativeCapabilitiesPending=false;self.nativeCapabilities=nil;self.nativeCapabilitiesRetry=0
        end
        self.nativeCapabilitiesRetry=math.max(0,(self.nativeCapabilitiesRetry or 0)-dt)
        local health=self.engineHealth or{}
        if(health.ok or health.ready or health.status=='ok')and self.nativeCapabilitiesRetry<=0 then self:refreshNativeCapabilities()end
    end
end
return Capabilities
