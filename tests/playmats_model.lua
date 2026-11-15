package.path='./?.lua;'..package.path
local time=0;love={timer={getTime=function()return time end}}
local Model={};require('app.playmats').install(Model)
local requests={};local ready={}
local m=setmetatable({game={gameId='first'},api={escape=function(s)return s end}},{__index=Model})
function m:request(service,method,path,body,callback)
    assert(service=='catalog'and method=='GET');requests[#requests+1]={path=path,callback=callback}
end
function m:profileArt(ref)return ready[ref.printingId]end
function m:getArt(card,force,kind)assert(force and kind=='art_crop');return ready[card.name]end
local n=0;local function check(value,message)n=n+1;assert(value,message)end
local player={id='bot',playmatCard={name='Forest',preferFullArt=true}}
check(m:botPlaymatArt(player)==nil and#requests==1,'Missing cached art requests a bounded exact reference')
m:botPlaymatArt(player);check(#requests==1,'An in-flight reference is not requested twice')
requests[1].callback({reference={printingId='missing'}})
time=10;m:botPlaymatArt(player);check(#requests==1,'Unavailable cached art does not cause per-frame requests')
time=31;m:botPlaymatArt(player);check(#requests==2,'A cache miss can discover artwork downloaded later')
ready.available={image=true};requests[2].callback({reference={printingId='available'}})
check(m:botPlaymatArt(player)==ready.available,'Newly cached exact art replaces the placeholder')
time=90;m:botPlaymatArt(player);check(#requests==2,'Ready artwork reuses its decoded image without polling')
m.game.gameId='second';m:botPlaymatArt(player);local old=requests[3]
m.game.gameId='third';m:botPlaymatArt(player)
old.callback({reference={printingId='old-game'}})
check(not m.botPlaymats['bot:Forest'].reference,'A prior-game response cannot overwrite the current playmat')
check(m:botPlaymatArt({human=true,playmatCard=player.playmatCard})==nil,'Human profile artwork is never replaced by a bot reference')
ready.Giada={commander=true}
check(m:botPlaymatArt({id='commander-bot',playmatCard={name='Giada'}})==ready.Giada,'Commander playmats use the existing local cropped-art path')
print('playmats_model: '..n..' checks passed')
