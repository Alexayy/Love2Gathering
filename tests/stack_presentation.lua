package.path='./?.lua;'..package.path
-- UI state regression only: native choice classification is stubbed, not rules.
package.preload['lib.Slab.Internal.UI.Window']=function()return{}end
package.preload['app.card_choices']=function()return{prefersBoard=function(_,prompt)return prompt.boardChoice end}end
local UI=require('app.match_ui');local clicked=false;local window
local prompt={id=7,boardChoice=true};local m={game={gameId='first',stack={{sourceName='Ability'}}}}
function m:prompt()return prompt end
local v={m=m,S={Button=function()return clicked end,EndWindow=function()end},r={assets={buttonImage=function()end}}}
function v:window(id)window=id;if id=='floating-stack'then error('expanded-stack-render',0)end end
UI.stack(v,1120,760);assert(window=='stack-selection-summary','Native board choice starts with the stack folded')
clicked=true;UI.stack(v,1120,760);clicked=false
local ok,err=pcall(UI.stack,v,1120,760);assert(not ok and err=='expanded-stack-render','Explicit expansion is retained for the current choice')
m.game.gameId='rematch';UI.stack(v,1120,760);assert(window=='stack-selection-summary','A rematch reusing a prompt ID cannot inherit an obstructing expansion')
m.roomConnectionId='room-one';clicked=true;UI.stack(v,1120,760);clicked=false
m.roomConnectionId='room-two';UI.stack(v,1120,760);assert(window=='stack-selection-summary','Another connection cannot inherit the old seat choice expansion')
print('Stack presentation PASS: explicit expansion, native board-choice folding and game/connection fencing')
