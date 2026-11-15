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
    return {text=text,fullText=text,actor=actor,category=category,actorColor=actorColor,color=categories[category] or actorColor,icon=icons[category] or 'info',
        sourceId=type(entry)=='table'and entry.sourceId,sourceCard=type(entry)=='table'and entry.sourceCard,raw=entry}
end
function Log.isStack(entry)
    return type(entry)=='table'and(entry.category=='trigger'or entry.category=='resolve'or entry.origin=='stack'or(entry.stackEvent==true and entry.category~='cast'))
end
function Log.entries(log,players,verbose,limit)
    local out={}
    for index=#(log or {}),1,-1 do
        local raw=log[index]
        if verbose or not Log.isStack(raw)then
            local entry=Log.present(raw,players);entry.index=index
            if type(raw)=='table'and type(raw.summary)=='string'then entry.text=raw.summary end
            out[#out+1]=entry
            if #out>=(limit or 80)then break end
        end
    end
    return out
end
function Log.source(entry,game)
    local card=entry.sourceCard
    if type(card)=='table'and(card.id or card.name)and not card.hidden and not card.faceDown then return card end
    if not entry.sourceId then return nil end
    -- Resolve only against this entitled projection, never a catalog name guess.
    for _,player in ipairs(game and game.players or {})do
        for _,zone in ipairs({'battlefield','hand','graveyard','exile','command'})do
            for _,candidate in ipairs(player[zone]or {})do
                if tostring(candidate.id)==tostring(entry.sourceId)and not candidate.hidden and not candidate.faceDown then return candidate end
            end
        end
    end
    return nil
end
return Log
