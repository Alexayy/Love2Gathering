package.path='./?.lua;'..package.path
-- Dock/hover state regression with controlled cursor/scroll transforms. Actual
-- Slab rendering and mouse input are accepted by presentation_overhaul_ui.sh.
local mouse={x=-1,y=-1};local scroll=0;local obstructed=false;local cx,cy=0,0;local opened={}
local clicked,pin,detail
love={graphics={getDimensions=function()return 1366,768 end},mouse={getPosition=function()return mouse.x,mouse.y end}}
package.preload['lib.Slab.Internal.UI.Window']=function()return{
 TransformPoint=function(x,y)return x,y end,IsObstructedAtMouse=function()return obstructed end}end
package.preload['app.card_choices']=function()return{cardImage=function()return nil end}end
package.preload['app.richtext']=function()return{slab=function()cy=cy+28 end}end
local Panels=require('app.table_panels')
local n=0;local function check(value,label)assert(value,label);n=n+1;print('STACK PRESENTATION PASS '..label)end
local rail={x=1060,y=146,w=290,h=480};local source={id='shared-source',name='Repeated native source',type='Creature'}
local function object(id,target)return{id=id,sourceId=source.id,sourceName=source.name,sourceCard=source,controllerId='opponent',kind='ability',rules='Native offered ability',targets={{id=target,name=target}}}end
local m={game={gameId='first',prompt={id=7,type='pick_target'},stack={object('native-stack-a','target-a'),object('native-stack-b','target-b')}},stackOpen=true}
function m:pinTableCard(card,context)pin={card=card,id=context.stackId}end
function m:inspectTableCard(card,context)detail={card=card,id=context.stackId}end
local r={tableLayout={rail=rail},fonts={[20]={}},colors={text={},gold={},muted={}},boardPlayers={opponent={id='opponent',name='Opponent'}}}
function r:playerColor()return{}end
local S={}
for _,name in ipairs({'EndWindow','EndListBox','PushFont','PopFont','PushID','PopID','Indent','Unindent'})do S[name]=function()end end
function S.Button()return false end
function S.IsMouseClicked(button)return clicked==button end
function S.GetCursorPos()return cx,cy end
function S.SetCursorPos(x,y)cx,cy=x,y end
function S.Text()cy=cy+14 end
function S.Textf()cy=cy+24 end
function S.NewLine()cy=cy+7 end
function S.Separator()cy=cy+4 end
function S.BeginListBox()cx,cy=rail.x+14,rail.y+80-scroll end
local v={m=m,r=r,S=S}
function v:window(id,x,y,w,h,_,options)opened[#opened+1]={id=id,x=x,y=y,w=w,h=h,options=options};cx,cy=x+14,y+14 end
local function draw()Panels.stack(v,1366,768)end
draw()
check(opened[1].id=='docked-stack'and opened[1].x==rail.x and opened[1].w==rail.w-14,'Stack stays in the reserved rail even during a native board target choice')
local a,b=r.stackRows['native-stack-a'],r.stackRows['native-stack-b']
check(a and b and a~=b and a.stackId=='native-stack-a'and b.stackId=='native-stack-b','Two native stack objects from the same source retain separate exact row identities')
check(a.sourceId==b.sourceId and a.targets[1].id=='target-a'and b.targets[1].id=='target-b','Connections retain each stack object’s actual target records')
mouse.x,mouse.y=b.x+10,math.max(b.y,b.clip.y)+5;draw()
check(m.stackHover and m.stackHover.id=='native-stack-b'and r.hoverStackId=='native-stack-b','Hover selects the exact native stack row rather than the shared source permanent')
clicked=2;draw();check(pin and pin.id==b.stackId and pin.card==source and not detail,'Right-click pins only the hovered stack source')
clicked=3;draw();check(detail and detail.id==b.stackId and detail.card==source,'Middle-click inspects the same native stack object')
clicked=nil
check(b.clip.x>=rail.x and b.clip.y>=rail.y and b.clip.x+b.clip.w<=rail.x+rail.w and b.clip.y+b.clip.h<=rail.y+rail.h,'Stack row hover and link clipping stay bounded to the reserved dock')
obstructed=true;draw();check(m.stackHover==nil and r.hoverStackId==nil,'An obstructing modal clears stack hover and its connections immediately');obstructed=false
scroll=800;mouse.x,mouse.y=a.x+5,rail.y+81;draw()
check(not r.stackRows['native-stack-a'].visible and not r.stackRows['native-stack-b'].visible and not m.stackHover,'Rows scrolled outside the dock cannot retain a selectable connection anchor')
scroll=0;m.game={gameId='rematch',prompt={id=7,type='pick_target'},stack={object('rematch-stack','new-target')}};draw()
check(r.stackRows['native-stack-a']==nil and r.stackRows['native-stack-b']==nil and r.stackRows['rematch-stack']~=nil,'A rematch reusing a prompt ID rebuilds only its current native stack rows')
m.roomConnectionId='another-seat';m.game.stack={};draw()
check(next(r.stackRows)==nil and#m.stackHits==0 and not m.stackHover and not r.hoverStackId,'Another seat with an empty stack inherits no stale row or hover')
m.game.stack={object('last-object','last-target')};draw();m.stackOpen=false;local windows=#opened;draw()
check(#opened==windows and next(r.stackRows)==nil and#m.stackHits==0 and not m.stackHover,'Closing the stack clears connection rows without drawing a hidden interaction surface')
r.tableLayout.rail=nil;m.stackOpen=true;draw();check(next(r.stackRows)==nil,'No reserved rail leaves no stale native row mapping')
print('Stack presentation checks: '..n..' passed')
