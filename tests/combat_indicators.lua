-- Presentation only: acknowledgement labels, native anchors and static arrows.
package.path='./?.lua;'..package.path
local Priority=require('app.priority');local Board=require('app.board_fx');local json=require('lib.json');local checks=0
local function check(ok,label)assert(ok,label);checks=checks+1 end
local m={game={priority={stops={own={},opponent={}}}},wanted=false}
function m:phaseStop(group,side)return side=='opponent'and self.wanted or false end
local function stop()return Priority.stopPresentation(m,Priority.beforeDamage,'opponent')end
check(stop().status=='off'and stop().label=='Before damage · OFF','Only acknowledged disabled state reads OFF')
m.wanted=true;m.priorityBusy=true
check(stop().status=='pending'and stop().label=='Before damage · WAIT'and not stop().enabled,'Pending enable never masquerades as acknowledged ON')
m.priorityBusy=false
check(stop().status=='unconfirmed'and stop().label=='Before damage · ?','Failed/unacknowledged preference is visibly distinct')
m.game.priority.stops.opponent={'DECLARE_BLOCKERS'}
check(stop().status=='on'and stop().enabled and stop().acknowledged,'Native acknowledgement enables the indicator')
check(Priority.stopPresentation(m,Priority.beforeDamage,'own').status=='off','Opponent quick stop does not imply an own-turn stop')
m.wanted=false;m.priorityBusy=true
check(stop().status=='pending'and stop().enabled,'Pending disable retains actual acknowledged state separately')
m.priorityBusy=false;m.game.priority={pending=true,stops={own={},opponent={}}}
check(stop().status=='pending','Native queue pending state is not mistaken for an applied stop')
m.game.priority={};m.wanted=true
check(stop().status=='unconfirmed'and not stop().acknowledged,'Missing native configuration never claims a confirmed stop')
local before=json.encode({game=m.game,wanted=m.wanted});stop();check(json.encode({game=m.game,wanted=m.wanted})==before,'Indicator reads do not alter settings or native state')
local commands,color,width={},{},0
local function record(kind,...)
 local entry={kind=kind,values={...},width=width,color={color[1],color[2],color[3]}}
 commands[#commands+1]=entry
end
love={graphics={setColor=function(a,b,c)color={a,b,c}end,setLineWidth=function(value)width=value end,
 line=function(...)record('line',...)end,polygon=function(...)record('polygon',...)end,circle=function(...)record('circle',...)end}}
local game={players={{id='human',human=true},{id='bot',seat=1}},combat={groups={
 {attackerId='a',defenderId='human',attackingPlayerId='bot',blocked=true,declarationConfirmed=true,blockerIds={}},
 {attackerId='b',defenderId='bot',attackingPlayerId='human',blockerIds={}}}},
 stack={{id='ability',sourceId='a',controllerId='bot',targetIds={'b'}}}}
local r={model={page='table',game=game,settings={reducedMotion=true}},colors={accent={.2,.9,.7},purple={.7,.4,1},gold={1,.8,.3}},
 cardRects={a={x=100,y=250,w=100,h=140},b={x=350,y=250,w=100,h=140}},
 playerRects={human={x=600,y=30,w=100,h=50},bot={x=800,y=30,w=100,h=50}},assets={},labels={},icons={},hits={}}
function r.assets:iconSymbol(name,x,y,size,tint)r.icons[#r.icons+1]={name=name,x=x,y=y,size=size,color=tint}end
function r:panel()end
function r:text(value)self.labels[#self.labels+1]=value end
function r:hit(value)self.hits[#self.hits+1]=value end
r.boardCards={a={id='a',controllerId='bot'},b={id='b',controllerId='human'}}
r.boardPlayers={human=game.players[1],bot=game.players[2]}
Board.links(r)
local core,owner,heads,origins,targets={},{},{},{},{}
for _,entry in ipairs(commands)do
 if entry.kind=='line'and entry.width==4 then core[#core+1]=entry end
 if entry.kind=='line'and entry.width==8 then owner[#owner+1]=entry end
 if entry.kind=='polygon'and entry.width==8 then heads[#heads+1]=entry end
 if entry.kind=='circle'and entry.values[4]==9 then origins[#origins+1]=entry end
end
for _,entry in ipairs(r.icons)do if entry.name=='focus'then targets[#targets+1]=entry end end
check(#core>0 and #owner>0 and #heads==2 and #origins==2,'Attack shafts, heads and origin markers remain directional and readable')
check(json.encode(core[1].color)~=json.encode(core[#core].color),'Different attackers retain distinct inner colors')
check(json.encode(owner[1].color)==json.encode(Board.color(r,'bot'))and json.encode(owner[#owner].color)==json.encode(Board.color(r,'human')),'Each larger arrow retains its actual player outline')
local tip=heads[1].values;local baseWidth=math.sqrt((tip[4]-tip[6])^2+(tip[5]-tip[7])^2)
check(math.abs(baseWidth-24)<.001,'Attack arrowhead has a readable bounded24pixel outer base')
check(targets[1].size==22 and targets[2].size==22 and#targets==2,'Only actual combat targets render until a stack object is inspected')
check(#r.boardLinks==2 and r.boardLinks[1].targetId=='human'and r.boardLinks[1].to.x==650,'Attack geometry is recorded at the actual native recipient')
r.stackRows={ability={x=900,y=300,w=160,h=80,visible=true}};r.hoverStackId='ability';r.boardLinks={};commands={};Board.links(r)
local connection;for _,link in ipairs(r.boardLinks)do if link.kind=='stack'then connection=link end end
check(connection and connection.sourceId=='ability'and connection.targetId=='b'and connection.from.x>=900 and connection.to.x<=450,'Hovered stack connection uses exact current row and current target edge')
r.hoverStackId=nil;r.boardLinks={};commands={};r.icons={};Board.links(r)
check(r.labels[1]=='BLOCKED'and r.hits[1].tooltip:find('Removing its blockers',1,true),'Confirmed native block remains visible after a blocker disappears')
local rendered=json.encode(commands);commands={};r.icons={};r.model.settings.reducedMotion=false;Board.links(r)
check(json.encode(commands)==rendered,'Static attack indicators do not add movement when motion preference changes')
commands={};game.combat.groups={{attackerId='redacted',defenderId='human'}};game.stack={};r.icons={};Board.links(r)
check(#commands==0 and #r.icons==0,'Missing source anchors never draw an invented screen-center arrow')
print('Combat indicator geometry: '..checks..' checks (presentation only)')
