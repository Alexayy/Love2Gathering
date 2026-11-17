-- Public presentation identity and shared safe areas. Never supplies legality.
local P={}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
function P.layout(w,h,settings,prefs,stackVisible)
    settings=settings or{};prefs=prefs or{}
    local scale=clamp(tonumber(settings.cardScale)or 1,.8,1.3)
    local handH=clamp(h*.164,126,188)*scale
    local railW=stackVisible and clamp(w*.205,278,374)or 0
    -- The hand is an overlay on the play surface; it does not remove a strip
    -- of terrain. Only the HUD and an explicitly docked panel reserve space.
    local top=146;local bottom=h-24
    local historyW=prefs.logPinned and prefs.logOpen and clamp(w*.21,240,350)or 0
    local viewport={x=16+(historyW>0 and historyW+10 or 0),y=top,w=w-32-(railW>0 and railW+12 or 0)-(historyW>0 and historyW+10 or 0),h=math.max(190,bottom-top)}
    local rail=railW>0 and{x=w-railW-16,y=top,w=railW,h=math.max(190,h-top-76)}or nil
    return{viewport=viewport,rail=rail,handH=handH,handY=h-handH-56,handBottom=h-56,
        handLeft=math.min(190,w*.12),handRight=w-math.max(350,railW>0 and railW+28 or 0),
        actions={x=w-226,y=h-62,w=210,h=50},hud={x=16,y=16,w=w-32,h=122},
        history={x=16,y=top,w=math.min(440,w*.32),h=math.min(390,viewport.h)},cardScale=scale}
end
function P.forModel(w,h,m)
    local prefs=(m.uiLayout or{}).matchPrefs or{}
    return P.layout(w,h,m.settings,prefs,m.stackOpen~=false)
end
function P.primary(prompt,game)
    if not prompt then
        local holder
        for _,player in ipairs(game and game.players or{})do if player.id==(game or{}).priorityPlayerId then holder=player.name end end
        return holder and('Waiting for '..holder)or'Waiting for engine'
    end
    if prompt.mulligan then return'Keep Hand'end
    if prompt.priority then return'Pass Priority'end
    local role=(prompt.combat or{}).role
    if role=='attackers'then return'Confirm Attackers'end
    if role=='blockers'or role=='block_target'then return'Confirm Blockers'end
    if prompt.manaWheel or prompt.type=='mana'then return'Confirm Payment'end
    if prompt.type=='target'or prompt.type=='targets'then return'Confirm Targets'end
    if prompt.type=='order'then return'Confirm Order'end
    return'Confirm Choice'
end
local function canonical(value)
    if type(value)~='table'then return tostring(value)end
    local keys={};for key in pairs(value)do keys[#keys+1]=key end
    table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
    local out={};for _,key in ipairs(keys)do out[#out+1]=tostring(key)..'='..canonical(value[key])end
    return'{'..table.concat(out,';')..'}'
end
function P.equivalence(card)
    if card.hidden or card.faceDown then return nil end
    -- Combat assignments and composite/linked objects have individual public
    -- meaning even if their names and current characteristics happen to match.
    if card.attacking or card.blocking or type(card.mutate)=='table'and(card.mutate.count or 0)>0
        or type(card.attachedToId)=='string'and card.attachedToId~=''or type(card.attachedToPlayerId)=='string'and card.attachedToPlayerId~=''
        or type(card.attachmentIds)=='table'and#card.attachmentIds>0
        or type(card.linkedExile)=='table'and#card.linkedExile>0 then return nil end
    local basic=tostring(card.type_line or card.type or''):lower():match('basic.*land')
    if card.token~=true and card.isToken~=true and not basic then return nil end
    local fields={'name','type','type_line','colors','power','toughness','damage','counters','tapped','summoningSick',
        'canAttack','summoningSickness','attacking','blocking','defendingPlayerId','attachedToId','attachedToPlayerId','attachmentIds',
        'controllerId','ownerId','keywords','currentKeywords','mechanicCapabilities','keywordAbilities','mechanics','currentRules','loyalty','phasedIn','phasedOut',
        'set','number','printingId','tokenSourceId','components','mutate','tokenTemplate','copySourceCard',
        'rules','manaCost','subtypes','minBlockers','maxBlockers','transformed','originalTokenTemplate','sourceCard'}
    local state={};for _,key in ipairs(fields)do state[key]=card[key]end
    return canonical(state)
end
function P.groups(cards,enabled,selectable)
    local out,byKey={},{}
    for _,card in ipairs(cards or{})do
        local key=enabled and P.equivalence(card)
        if key then key=key..':'..tostring(selectable and selectable(card.id)or false)end
        local group=key and byKey[key]
        if group then group.cards[#group.cards+1]=card else
            group={card=card,cards={card}};out[#out+1]=group;if key then byKey[key]=group end
        end
    end
    return out
end
function P.freeze(r)
    local m=r.model;local p=m:prompt()
    return r.drag~=nil or r.panGesture~=nil or m.inspectCard~=nil or m.zoneView~=nil
        or p and not p.priority and not p.mulligan
end
return P
