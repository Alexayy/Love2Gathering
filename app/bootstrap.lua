-- Saved identity/presentation must be hydrated before the first client view.
local Bootstrap={}
local order={'settings','profile','decks','uiLayout'}
local labels={settings='Saved theme and preferences',profile='Player profile',decks='Saved deck library',uiLayout='Saved panel layout'}
function Bootstrap.install(Model)
    function Model:beginStartupHydration()
        if not self.startupHydration then
            self.startupHydration={parts={}}
            for _,key in ipairs(order)do self.startupHydration.parts[key]={serial=0}end
        end
        local state=self.startupHydration;self.loaded=true
        for _,key in ipairs(order)do
            local part=state.parts[key]
            -- /decks is readable without a built index, but its color metadata
            -- is enriched once the catalog becomes ready, still under the gate.
            if key=='decks'and part.ready and not part.catalogReady and self.catalogHealth.ready then part.ready=false end
            if not part.ready and not part.pending and not part.error then
                part.pending=true;part.serial=part.serial+1;local serial=part.serial
                local catalogReady=self.catalogHealth.ready==true
                local function done(data,err)
                    if self.startupHydration~=state or serial~=part.serial then return end
                    part.pending=false
                    if type(data)~='table'then part.error=err or(labels[key]..' could not be loaded');return end
                    if key=='settings'then
                        for name,value in pairs(data)do self.settings[name]=value end
                        self.settingsLoaded=true
                    elseif key=='uiLayout'then
                        self.uiLayout=data;self.uiLayoutVersion=(self.uiLayoutVersion or 0)+1
                        local prefs=data.matchPrefs or{};self.logOpen=prefs.logOpen;self.stackOpen=prefs.stackOpen
                    end
                    part.ready=true;part.error=nil;part.catalogReady=catalogReady
                end
                if key=='profile'then self:loadProfile(done)
                elseif key=='decks'then self:refreshDecks(done)
                else self:request('catalog','GET',key=='settings'and'/settings'or'/ui-layout',nil,done,true)end
            end
        end
        return self:startupHydrationState()
    end
    function Model:startupHydrationState()
        local state=self.startupHydration;local ready=0;local message,problem
        for _,key in ipairs(order)do
            local part=state and state.parts[key]or{}
            if part.ready then ready=ready+1
            elseif not message then message='Loading '..labels[key]:lower()..'…'end
            if part.error and not problem then problem=labels[key]..': '..part.error end
        end
        return{ready=ready==#order,progress=ready/#order,message=message or'Saved client state loaded',error=problem,retryable=problem~=nil}
    end
    function Model:retryStartupHydration()
        if self.startupHydration then
            for _,part in pairs(self.startupHydration.parts)do
                if part.error then part.serial=part.serial+1;part.error=nil;part.pending=false end
            end
        end
        return self:beginStartupHydration()
    end
end
return Bootstrap
