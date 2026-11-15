-- Implementation coverage is not a format-legality verdict.
local UI={}
function UI.status(m,deck)
    if m.deckSupport then return m:deckSupport(deck)end
    return{state='unknown',missingNames={},legalityChecked=false}
end
function UI.label(status)
    if status.state=='unavailable'then return'Unavailable · '..#(status.missingNames or{})..' missing' end
    if status.state=='ready'then return'Cards implemented · XMage validates legality'end
    if status.state=='checking'then return'Checking installed cards…'end
    return'Installed card support not checked'
end
function UI.overlay(r,status,x,y,w,h)
    if status.state~='unavailable'then return end
    love.graphics.setColor(.015,.02,.035,.68);love.graphics.rectangle('fill',x,y,w,h,3,3)
    local size=math.min(26,math.max(16,h*.17));r.assets:iconSymbol('info',x+(w-size)/2,y+math.max(4,h*.19),size,r.colors.gold)
    r:strong('Unavailable',x+6,y+h*.47,math.min(16,math.max(11,w/12)),r.colors.text,w-12,'center')
    r:text(tostring(#(status.missingNames or{}))..' cards not implemented',x+6,y+h*.68,math.min(12,math.max(9,w/16)),r.colors.muted,w-12,'center')
end
function UI.details(v,status,width)
    local S=v.S;local C=v.r.colors
    S.Textf(UI.label(status),{W=width,Color=status.state=='unavailable'and C.gold or C.muted})
    if status.state=='unavailable'then
        S.Textf('The installed XMage cannot create these cards. The original deck stays available to inspect and edit.',{W=width,Color=C.muted});S.NewLine()
        for _,name in ipairs(status.missingNames or{})do S.Textf('• '..name,{W=width,Color=C.text})end
    end
    S.NewLine();S.Textf('This checks installed card implementations only. XMage still checks format legality when starting a match.',{W=width,Color=C.muted})
end
return UI
