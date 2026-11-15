-- A Lobby shortcut into the existing private native draft workflow. Constructed
-- /session practice remains separate; draft picks/building/pairings stay native.
local json=require('lib.json')
local BotDraft={}
function BotDraft.install(Model)
    function Model:openBotDraft()
        self.lobbyMode='draft';self.botDraftError=nil
        if not self.roomCapabilities then self:refreshRoomCapabilities()end
        require('app.rooms').fitSetup(self)
        self.roomSetup.kind='draft'
        self.roomSetup.playerName=self.playerName
        if not self.botDraftInitialized then self.roomSetup.maxPlayers=8;self.botDraftInitialized=true end
        require('app.rooms').fitSetup(self)
    end
    function Model:startBotDraft()
        if self.botDraftBusy or self.roomBusy or self.roomConnectionId or self.storageLocationBlocked then return false end
        require('app.rooms').fitSetup(self)
        local caps=self.roomCapabilities and self.roomCapabilities.draft
        if not caps or caps.botSupport~=true then self.botDraftError='The installed engine has not confirmed bot draft support.';return false end
        local count=self.roomSetup.maxPlayers;local config=json.decode(json.encode(self.roomSetup))
        config.kind='draft';config.name='Bot draft';config.playerName=self.playerName
        self.botDraftGeneration=(self.botDraftGeneration or 0)+1;local generation=self.botDraftGeneration
        self.botDraftBusy=true;self.botDraftError=nil
        local connecting=self:connectRoom(false,config,function(data,err)
            if generation~=self.botDraftGeneration then return end
            if not data then self.botDraftBusy=false;self.botDraftError=err or'Draft could not be created';return end
            local connection=self.roomConnectionId
            local function current()return generation==self.botDraftGeneration and self.roomConnectionId==connection end
            self:setRoomBots(count-1,function(bots,botsError)
                if not current()then return end
                if not bots then self.botDraftBusy=false;self.botDraftError=botsError;return end
                self:setRoomReady(true,function(ready,readyError)
                    if not current()then return end
                    if not ready then self.botDraftBusy=false;self.botDraftError=readyError;return end
                    self:roomMutation('/start',{},function(started,startError)
                        if not current()then return end
                        self.botDraftBusy=false;self.botDraftError=startError
                        if started then self.roomPollTimer=0 end
                    end)
                end)
            end)
        end)
        if not connecting then self.botDraftBusy=false;self.botDraftError='Finish the current room action before starting the draft.'end
        return connecting==true
    end
end
return BotDraft
