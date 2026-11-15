-- Native result presentation. No life-total or empty-stack outcome guesses.
local json=require('lib.json')
local Outcome={}
local titles={win='YOU WON',loss='YOU LOST',draw='DRAW',ended='MATCH ENDED'}
local function localPlayer(game)
    local only,count,explicit=nil,0,false
    for _,p in ipairs(game.players or{})do
        if game.localPlayerId and p.id==game.localPlayerId or p.isLocal==true then return p end
        if p.isLocal~=nil then explicit=true end
        if p.human then only=p;count=count+1 end
    end
    if not game.localPlayerId and not explicit and count==1 then return only end
end
function Outcome.state(model)
    local game=model.game
    if model.replay or not game or game.running~=false or game.error and game.error~=json.null and game.error~=''then return nil end
    local result=type(game.result)=='table'and game.result~=json.null and game.result or nil
    local kind
    if result then
        if result.gameId and result.gameId~=game.gameId or result.completed~=true then return nil end
        if result.outcome=='win'or result.outcome=='loss'or result.outcome=='draw'then kind=result.outcome end
    else
        -- Old recordings/bridges can still supply authoritative won/lost flags.
        local player=localPlayer(game)
        if player then kind=player.won==true and'win'or player.lost==true and'loss'or nil end
    end
    if not kind then return nil end
    return{mode=#(game.players or{})==2 and'duel'or'multiplayer',terminal=true,outcome=kind,kind=kind,title=titles[kind]}
end
function Outcome.install(Model)
    function Model:matchOutcome()return Outcome.state(self)end
end
return Outcome
