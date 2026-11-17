-- Derived labels only. Native values, permissions and answers remain unchanged.
local Presentation={}
function Presentation.eliminated(player)return player.lost==true or player.left==true end
function Presentation.phaseKey(game)
    local step=tostring(game.step or''):upper():gsub('[^%w]+','_')
    if step:find('PRECOMBAT',1,true)then return'PRECOMBAT'end
    if step:find('POSTCOMBAT',1,true)then return'POSTCOMBAT'end
    if step:find('COMBAT',1,true)or step:find('ATTACKER',1,true)or step:find('BLOCKER',1,true)then return'COMBAT'end
    if step:find('UPKEEP',1,true)then return'UPKEEP'end
    if step=='DRAW'or step=='DRAW_STEP'then return'DRAW'end
    if step=='END'or step=='END_TURN'or step=='END_STEP'or step=='CLEANUP'then return'END'end
    return nil
end
function Presentation.manaCost(card,data)
    -- An explicit native empty cost is meaningful, including transformed faces.
    if type(card.manaCost)=='string'then return card.manaCost end
    if type(card.mana_cost)=='string'then return card.mana_cost end
    return type(data)=='table'and type(data.mana_cost)=='string'and data.mana_cost or''
end
function Presentation.stats(card)
    local power,toughness=card.power,card.toughness
    if power==nil or toughness==nil or tostring(power)==''or tostring(toughness)==''then return nil end
    if tostring(power)=='0'and tostring(toughness)=='0'and not tostring(card.type_line or card.type or''):lower():find('creature',1,true)then return nil end
    local damage=math.max(0,tonumber(card.damage)or 0)
    local remaining=tonumber(toughness)and(tonumber(toughness)-damage)or nil
    local native=tostring(power)..'/'..tostring(toughness)
    local shown=tostring(power)..'/'..(remaining and string.format('%g',remaining)or tostring(toughness))
    return{native=native,shown=shown,damage=damage,remaining=remaining,
        label='Native P/T '..native..(damage>0 and' · '..tostring(damage)..' damage marked · remaining '..(remaining and string.format('%g',remaining)or'unknown')or'')}
end
function Presentation.peek(card)
    local identity=type(card)=='table'and card.faceDownIdentity
    if card and card.faceDown and not card.hidden and type(identity)=='table'and not identity.hidden and identity.id==card.id then
        local result={};for key,value in pairs(identity)do result[key]=value end
        local stats=Presentation.stats(card)
        result.faceDownContext={nativePT=stats and stats.native,damage=stats and stats.damage or 0}
        return result
    end
    return card
end
function Presentation.commanderLabel(commander)
    if type(commander)~='table'then return nil end
    local tax=type(commander.additionalTax)=='table'and commander.additionalTax or{}
    local cost=type(tax.manaCost)=='string'and tax.manaCost or''
    local other=type(tax.otherCosts)=='table'and table.concat(tax.otherCosts,', ')or tostring(tax.otherCosts or'')
    local suffix=cost~=''and(' · Tax '..cost)or''
    if other~=''then suffix=suffix..' · '..other end
    return tostring(commander.commandZonePlays or 0)..' command casts · '..tostring(commander.deaths or 0)..' deaths'..suffix
end
local function highestCommanderDamage(player)
    local highest=0
    for _,entry in ipairs(type(player.commanderDamageReceived)=='table'and player.commanderDamageReceived or{})do
        highest=math.max(highest,tonumber(entry.amount)or 0)
    end
    return highest
end
function Presentation.commanderDamageSummary(player,enabled)
    if enabled~=true and enabled~=false then return nil end
    if enabled==false then return'Commander damage disabled' end
    return'Max commander damage: '..tostring(highestCommanderDamage(player))
end
function Presentation.playerTooltip(player,enabled)
    local lines={(player.name or'Player')..' · '..tostring(player.life or 0)..' life',
        tostring(player.handCount or 0)..' in hand · '..tostring(player.libraryCount or 0)..' in library'}
    local summary=Presentation.commanderDamageSummary(player,enabled)
    if summary then
        lines[#lines+1]=enabled and'Highest damage received from one commander: '..tostring(highestCommanderDamage(player))or summary
        for _,entry in ipairs(type(player.commanderDamageReceived)=='table'and player.commanderDamageReceived or{})do
            lines[#lines+1]=(entry.name or'Commander')..' · '..tostring(entry.amount or 0)..' damage received'
        end
    end
    for _,commander in ipairs(type(player.commanders)=='table'and player.commanders or{})do
        lines[#lines+1]=(commander.name or'Commander')..' · '..Presentation.commanderLabel(commander)
    end
    return table.concat(lines,'\n')
end
return Presentation
