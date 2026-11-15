-- An HTTP ACK may precede native response delivery. Only the exact still-open
-- question may be restored after a delivery failure; no native retry is sent.
local json=require('lib.json')
local Delivery={}
function Delivery.install(Model)
    local setGame=Model.setGame
    function Model:setGame(data)
        setGame(self,data)
        if self.replay or self.game~=data then return end
        local delivery=type(data.inputDelivery)=='table'and data.inputDelivery~=json.null and data.inputDelivery
        if not delivery or type(delivery.id)~='string'or type(delivery.error)~='string'or delivery.error==''then return end
        local key=tostring(data.gameId)..':'..delivery.id
        if self.inputDeliveryErrorSeen==key then return end
        local prompt=type(data.prompt)=='table'and data.prompt or{}
        if self.answeredPrompt==delivery.promptId and prompt.id==delivery.promptId then
            self.inputDeliveryErrorSeen=key;self.answeredPrompt=nil;self.actionBusy=false;self.pollTimer=0
            self:toast('XMage did not accept that action: '..delivery.error,true)
        end
    end
end
return Delivery
