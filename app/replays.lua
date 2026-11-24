local API=require('app.api')
local Replays={}
local PAGE_SIZE=50 -- Bound JSON decode/channel work so large logs load progressively.
local function older(data,current)
    return current and data.gameId==current.gameId and data.revision and current.revision and data.revision<current.revision
end
local function applyFrame(model,index)
    local replay=model.replay;if not replay or #replay.frames==0 then return end
    replay.index=math.max(1,math.min(#replay.frames,math.floor(tonumber(index) or 1)))
    local frame=replay.frames[replay.index]
    model.game=frame.data;model.page='table';replay.elapsed=0
    model:refreshLibraryViews()
    model:refreshZoneView()
    model:refreshTableInspection()
    model.orderPrompt=nil;model.promptOrder={}
end
function Replays.install(Model)
    local baseSetGame=Model.setGame
    function Model:refreshReplays(append)
        local version=(self.replaysVersion or 0)+1;self.replaysVersion=version
        self.replaysBusy=true
        local offset=append and #(self.replays or {}) or 0
        self:request('catalog','GET','/replays?limit=100&offset='..offset,nil,function(data)
            if version~=self.replaysVersion then return end
            self.replaysBusy=false
            if data then
                if append then self.replays=self.replays or {};for _,item in ipairs(data.replays or {}) do self.replays[#self.replays+1]=item end else self.replays=data.replays or {} end
                self.replaysTotal=data.total
            end
        end)
    end
    function Model:showReplays()
        if self.replay then self.replay.playing=false end
        self.page='replays';self:refreshReplays()
    end
    function Model:openReplay(id)
        if self.replayLoading then return end
        if not self.replay then
            self.liveGame=self.game
            self.livePromptOrder={id=self.orderPrompt,choices=self.promptOrder}
        end
        local replay={id=id,frames={},index=1,speed=(self.uiLayout and self.uiLayout.replayPrefs or {}).speed or 1,playing=false,elapsed=0}
        self:clearTablePreview();self:closeTableInspection()
        self.zoneView=nil;self.cardActionSheet=nil
        self.replay=replay
        self.replayLoading=true;self.replayLoadProgress=0
        self:request('catalog','GET','/replays/'..API.escape(id),nil,function(metadata)
            if self.replay==replay then replay.metadata=metadata end
        end)
        local function load(offset)
            self:request('catalog','GET','/replays/'..API.escape(id)..'/frames?offset='..offset..'&limit='..PAGE_SIZE,nil,function(data,err)
                -- Object identity also distinguishes a later opening of the same recording.
                if self.replay~=replay then return end
                if err then self.replayLoading=false;self:closeReplay();return end
                for _,frame in ipairs(data.frames or {}) do self.replay.frames[#self.replay.frames+1]=frame end
                self.replayLoadProgress=#self.replay.frames;self.replay.total=data.total or #self.replay.frames
                if #self.replay.frames<self.replay.total and #(data.frames or {})>0 then load(offset+#data.frames)
                else
                    self.replayLoading=false
                    if #self.replay.frames>0 then applyFrame(self,1)
                    else self:toast('This recording has no saved frames yet',true);self:closeReplay() end
                end
            end)
        end
        load(0)
    end
    function Model:seekReplay(index)
        if not self.replay then return end
        self.replay.playing=false;applyFrame(self,index)
    end
    function Model:stepReplay(direction)
        if self.replay then self:seekReplay(self.replay.index+direction) end
    end
    function Model:toggleReplay()
        if not self.replay or self.replayLoading then return end
        if self.replay.index>=#self.replay.frames then applyFrame(self,1) end
        self.replay.playing=not self.replay.playing
    end
    function Model:closeReplay()
        if not self.replay then return end
        local live,order=self.liveGame,self.livePromptOrder
        self.replay=nil;self.replayLoading=false
        self:clearTablePreview();self:closeTableInspection()
        self.zoneView=nil;self.cardActionSheet=nil
        self.game=nil;self.liveGame=nil;self.livePromptOrder=nil;self.pollTimer=0
        self.orderPrompt=nil;self.promptOrder={}
        if live then
            baseSetGame(self,live)
            if order and order.id==self.orderPrompt then self.promptOrder=order.choices or self.promptOrder end
        end
        self.page='replays'
    end
    function Model:updateReplays(dt)
        local replay=self.replay
        if not replay or not replay.playing or self.replayLoading then return end
        if self.page~='table' then replay.playing=false;return end
        replay.elapsed=(replay.elapsed or 0)+dt*replay.speed
        local budget=160
        while replay.index<#replay.frames and budget>0 do
            local a,b=replay.frames[replay.index],replay.frames[replay.index+1]
            local delta=math.max(.025,math.min(1.5,((tonumber(b.timestamp) or 0)-(tonumber(a.timestamp) or 0))/1000))
            if replay.elapsed<delta then break end
            local remaining=replay.elapsed-delta;applyFrame(self,replay.index+1);replay.elapsed=remaining;budget=budget-1
        end
        if replay.index>=#replay.frames then replay.playing=false end
    end
    function Model:saveReplay()
        if self.replay then self:toast('Replay is already stored in SQLite');return end
        self:request('engine','POST','/session/replay/save',{},function(data)
            if data and data.replayId then
                if data.recordingError or data.saved==false then self:toast('Replay is stored locally; synchronization is pending',true) else self:toast('Replay saved') end
                self:refreshReplays()
            end
        end)
    end
    function Model:setUIOption(key,value)
        self.uiLayout=self.uiLayout or {};self.uiLayout.matchPrefs=self.uiLayout.matchPrefs or {}
        self.uiLayout.matchPrefs[key]=value;self.uiLayoutTimer=.4
    end
    function Model:setUILayout(key,geometry)
        self.uiLayout=self.uiLayout or {}
        local previous=self.uiLayout[key] or {};local changed=false
        for k,v in pairs(geometry) do if type(v)=='number' and math.abs((previous[k] or -100)-v)>.001 then changed=true end end
        if changed then self.uiLayout[key]=geometry;self.uiLayoutTimer=.6 end
    end
    function Model:updateUILayout(dt)
        if not self.uiLayoutTimer then return end
        self.uiLayoutTimer=self.uiLayoutTimer-dt
        if self.uiLayoutTimer<=0 then
            self.uiLayoutTimer=nil
            self:request('catalog','PUT','/ui-layout',self.uiLayout,function() end,true)
        end
    end
    function Model:setGame(data)
        if self.replay then if not older(data,self.liveGame) then self.liveGame=data end;return end
        baseSetGame(self,data)
    end
end
return Replays
