-- Small derivatives are chosen by physical display size, not card identity.
local Layout=require('app.layout')
local Hints={}
function Hints.forSize(width,height,extraScale)
    local dpi=love.window and love.window.getDPIScale and love.window.getDPIScale()or 1
    local scale=Layout.scale*math.max(1,dpi)*(extraScale or 1)
    return{priority='visible',variant=width*scale<=256 and height*scale<=512 and'thumb'or nil}
end
return Hints
