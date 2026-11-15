package.path='./?.lua;'..package.path
local Dice=require('app.dice');local count=0
local function check(value,label)assert(value,label);count=count+1;print('DICE MODEL PASS '..label)end
local final={mode='2d6',winnerId='bot',rounds={{rolls={{playerId='you',name='You',dice={2,3},total=5},{playerId='bot',name='Bot',dice={5,6},total=11}}}}}
local r={model={page='table',settings={},game={gameId='first',openingRoll=final}},sounds={}}
function r:sound(name)self.sounds[#self.sounds+1]=name end
Dice.update(r,.05);check(Dice.busy(r),'A new native 2d6 result opens its transient animation')
check(r.diceOpening.roll==final and final.winnerId=='bot','Animation keeps the authoritative server winner/results')
check(r.sounds[1]=='dice-roll','Opening dice use the supplied dice audio role')
Dice.update(r,.9);Dice.update(r,.02);check(r.sounds[2]=='dice-land'and#r.sounds==2,'Settling dice play one landing sound')
Dice.update(r,4);check(not Dice.busy(r),'The animation settles and leaves game decisions available')
Dice.update(r,.1);check(not Dice.busy(r),'Polling the same game never replays the roll')
r.model.game.gameId='second';r.model.game.openingRoll={mode='chosen',winnerId='you',rounds={}};Dice.update(r,.1);check(not Dice.busy(r),'Manually chosen practice starter does not pretend to roll dice')
r.model.game.gameId='replay';r.model.game.openingRoll=final;r.model.replay={};Dice.update(r,.1);check(not Dice.busy(r),'Playback never blocks on an opening dice overlay')
r.model.replay=nil;r.model.game.gameId='late';r.model.game.turn=5;Dice.update(r,.1);check(not Dice.busy(r),'Reconnecting during later turns never replays pregame dice')
print('Dice model checks: '..count..' passed')
