-- Native projection/action identities only; no Magic permission heuristics.
package.path='./?.lua;'..package.path
local calls={};package.preload['app.api']=function()return{escape=function(v)return tostring(v)end,new=function()return{request=function(_,service,method,path,body,callback)calls[#calls+1]={service=service,path=path,body=body}end,update=function()end,quit=function()end,setNativeSession=function()end}end}end
love={timer={getTime=function()return 1 end},graphics={getDimensions=function()return 1440,900 end}}
local Model=require('app.model');local Renderer=require('app.renderer');local Table=require('app.table')
local m=Model.new();local checks=0;local function check(ok,label)assert(ok,label);checks=checks+1;print('LIBRARY TOP PASS '..label)end
local top={id='native-top',name='Forest',ownerId='human'}
local function state(card,actionable)
 return{gameId='native-game',revision=(m.game and m.game.revision or 0)+1,running=true,players={{id='human',name='You',human=true,libraryCount=50,libraryTop=card,libraryTopVisibility=card and'public'or nil},{id='bot',name='Bot',human=false,libraryCount=50}},prompt={id=100+checks,type='select',priority=true,actionable=actionable or{},choices={},targets={}},priority={canEndTurn=true}}
end
m:setGame(state(nil));check(not m:libraryTop('human')and not m:libraryTop('bot'),'Library ownership and count never reveal an unprojected top card')
m:openLibrary('human');check(#m.zoneView.cards==0,'A hidden library opens no fabricated card rows')
m:setGame(state(top,{top.id}));check(m:libraryTop('human')==top and m.zoneView.cards[1]==top,'A live library zone adopts only the explicitly entitled top card')
check(m:canSelect(top.id),'A native actionable top card uses its original UUID')
m.zoneView=nil;m:selectCard(top);check(#calls==1 and calls[1].path=='/session/action'and calls[1].body.type=='uuid'and calls[1].body.value==top.id and calls[1].body.expectedGameId=='native-game','Playing the top forwards the native UUID and game fence without a new action type')
m.actionBusy=false;m.answeredPrompt=nil;m:setGame(state(top,{}));check(not m:canSelect(top.id)and not m:selectCard(top)and#calls==1,'A present empty native actionable array forbids play even for a visible Forest')
m:setGame(state(top,{top.id}));m.game.priority.pending=true;check(not m:canSelect(top.id),'Pending native priority acknowledgement hides obsolete top-card playability')
m.game.priority.pending=nil;m.replay={};check(not m:canSelect(top.id)and not m:selectCard(top)and#calls==1,'Recorded visible top cards remain inspectable but never submit live actions')
check(m:inspectLibraryTop('human',top.id,'native-game')and m.inspectCard==top,'Replay inspection accepts an entitled top card')
m.replay=nil;m:openLibrary('human');local nextTop={id='native-next',name='Island'};m:setGame(state(nextTop,{nextTop.id}))
check(m.zoneView.cards[1]==nextTop and not m.inspectCard and not m.libraryTopInspect,'A changed top updates the zone and closes its previous top-specific inspector')
check(not m:libraryTopCurrent('human',top.id,'native-game')and not m:inspectLibraryTop('human',top.id,'native-game'),'Old top-card hits and right-clicks cannot retarget the new library top')
m:inspectLibraryTop('human',nextTop.id,'native-game');m:setGame(state(nil,{}));check(#m.zoneView.cards==0 and not m.inspectCard,'Removing visibility clears the top zone and inspector instead of retaining stale art')
m.game.players[1].libraryTop={id='redacted',name='Hidden',hidden=true};check(not m:libraryTop('human'),'An explicitly redacted top card never becomes a visible face')
m.game.players[1].libraryTop={id='face-down',name='Hidden',faceDown=true};check(not m:libraryTop('human'),'Face-down projection placeholders never become inspectable library cards')
m.game.players[1].libraryTop=nextTop;m.game.players[1].libraryTopVisibility='private';check(m:libraryTop('human')==nextTop,'Native private-look entitlement uses the same top-card presentation without public inference')
local different={id='other-detail',name='Other'};m:inspectLibraryTop('human',nextTop.id,'native-game');m.inspectCard=different;m:refreshLibraryViews();m.game.players[1].libraryTop=nil;m:refreshLibraryViews()
check(m.inspectCard==different and not m.libraryTopInspect,'Library updates do not close an unrelated card inspector')
m.inspectCard=nil;m.zoneView=nil;m.game.players[1].libraryTop=top
local r=setmetatable({model=m,view={},drag={kind='library-top',card=top,libraryPlayerId='human',libraryGameId='native-game',x=30,y=250,w=100,h=140},dragStart={30,250},dragPage='table',ghosts={}},Renderer)
m.page='table';m.game.players[1].libraryTop=nextTop;r:mousereleased(30,250,1);check(not r.drag and#calls==1,'A top changing between press and release rejects the stale drag before native input')
local untouched={kind='permanent',card={id='other'}}
local fake={model=m,hits={untouched},colors={text={1,1,1},gold={1,1,0},muted={.5,.5,.5}},assets={iconSymbol=function()end},panel=function()end,text=function()end,drawCard=function()end}
function fake:hit(hit)self.hits[#self.hits+1]=hit end
Table.library(fake,m.game.players[1],10,10,100)
check(not untouched.libraryPlayerId and untouched.kind=='permanent','An offscreen card that adds no hit cannot corrupt a previous unrelated hit')
fake.hits={};Table.library(fake,m.game.players[1],10,10,100);check(#fake.hits==2,'A clipped top with no previous hit still safely creates only its available zone controls')
fake.hits={untouched};fake.drag={card=nextTop};fake.cardRects={};fake.screenRect=Renderer.screenRect;fake.drawCard=Renderer.drawCard
Table.library(fake,m.game.players[1],10,10,100)
check(not untouched.libraryPlayerId,'Drawing a currently dragged top card cannot mutate another card hit')
print('Library top model checks: '..checks)
