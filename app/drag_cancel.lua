-- Cancel an unsubmitted presentation gesture. Never sends native cancellation
-- or reverses a cast/cost which has already been confirmed by the engine.
local Drag={}
function Drag.cancel(renderer,view,x,y)
    local active=renderer.drag or view and(view.cardChoiceDrag or view.combatChoiceDrag or view.zoneDrag)
    if not active then return false end
    local drag=renderer.drag
    if drag and drag.card and renderer.model.settings.animations~=false and not renderer.model.settings.reducedMotion then
        renderer.ghosts=renderer.ghosts or{}
        renderer.ghosts[#renderer.ghosts+1]={card=drag.card,from={x=x,y=y},target={x=drag.x+drag.w/2,y=drag.y+drag.h/2},time=0,duration=.22,accepted=false}
    end
    renderer.drag=nil;renderer.dragStart=nil;renderer.dragPos=nil;renderer.dragPage=nil;renderer.dragEditorGeneration=nil;renderer.panGesture=nil
    renderer.dragTablePrompt=nil
    if view then view.cardChoiceDrag=nil;view.combatChoiceDrag=nil;view.zoneDrag=nil end
    local button=package.loaded['lib.Slab.Internal.UI.Button'];if button and button.ClearClicked then button.ClearClicked()end
    renderer.dragCancelRight=true
    return true
end
return Drag
