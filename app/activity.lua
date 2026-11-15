-- Explain actual pending work without treating an ordinary opponent turn as a
-- frozen engine. Presentation only: never submit/pass a native prompt here.
local Activity={}
local function clock()return love.timer.getTime()end
local function pending(m,service,path)
    local oldest
    for _,detail in pairs(m.api and m.api.pendingDetails or{})do
        if detail.service==service and(not path or detail.path==path)then
            oldest=math.min(oldest or detail.started,detail.started)
        end
    end
    return oldest and math.max(0,clock()-oldest)or 0
end
function Activity.install(Model)
    function Model:activityState()
        if self.replay or self.page~='table'then self.activityMarker=nil;return nil end
        local kind,label,busy,progress
        if self.gameBusy then kind,label,busy='connection','Preparing the match',true
        elseif self.actionBusy or self.priorityBusy or self.concedePending then kind,label,busy='action','Waiting for XMage to accept your action',true
        elseif self.gameConnectionError then kind,label,busy='connection','Reconnecting to XMage',true
        elseif self.game and type(self.game.inputDelivery)=='table'and self.game.inputDelivery.pending==true then kind,label,busy='action','Waiting for XMage to receive your action',true
        elseif self.game and self.game.running~=false and self.game.priority and self.game.priority.pending then kind,label,busy='engine','Waiting for XMage to update priority',true
        elseif self.game and self.game.running~=false and type(self.game.prompt)=='table'and self.answeredPrompt and self.game.prompt.id==self.answeredPrompt then kind,label,busy='engine','Waiting for XMage to advance the choice',true
        elseif self.polling and pending(self,self.roomGameActive and'room'or'engine','/session/state')>.8 then kind,label,busy='engine','Waiting for the next XMage state',true
        elseif self.gameArtwork and self.gameArtwork.handPending>0 then
            kind,label,busy='images','Loading your hand images',true
            progress=self.gameArtwork.handReady/math.max(1,self.gameArtwork.handTotal)
        elseif self.game and self.game.running~=false then
            local prompt=self:prompt()
            if not prompt then kind,label,busy='opponent','Waiting for the next player',false end
        end
        if not kind then self.activityMarker=nil;return nil end
        local marker=self.activityMarker
        if not marker or marker.kind~=kind or marker.label~=label then marker={kind=kind,label=label,since=clock()};self.activityMarker=marker end
        return{kind=kind,label=label,busy=busy,elapsed=clock()-marker.since,progress=progress}
    end
end
return Activity
