local Log={}
local categories={cast={.48,.77,1},resolve={.43,.89,.70},trigger={1,.77,.35},damage={1,.40,.43},attack={1,.60,.34},turn={.97,.82,.45},draw={.62,.79,1},land={.56,.82,.58},mana={.40,.89,.85},zone={.65,.72,.82}}
local icons={cast='instant',resolve='ability',trigger='ability',damage='damage',attack='attack',turn='turn',draw='draw',land='land',mana='C',zone='graveyard',system='info'}
function Log.present(entry,players)
    local text=type(entry)=='table' and tostring(entry.text or entry.message or '') or tostring(entry)
    local actor=type(entry)=='table' and entry.actor or 'system'
    local category=type(entry)=='table' and entry.category or 'system'
    if actor=='system' then
        for _,player in ipairs(players or {}) do
            if text:sub(1,#(player.name or ''))==player.name then actor=player.human and 'human' or 'bot';break end
        end
    end
    local actorColor=actor=='human' and {.32,.91,.73} or actor=='bot' and {.74,.59,1} or {.58,.67,.76}
    return {text=text,actor=actor,category=category,actorColor=actorColor,color=categories[category] or actorColor,icon=icons[category] or 'info'}
end
return Log
