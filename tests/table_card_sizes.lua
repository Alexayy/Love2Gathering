-- Synthetic geometry only. Actual Slab input and native rules have separate gates.
package.path='./?.lua;'..package.path
package.preload['app.board_fx']=function()return{}end
local physicalW,physicalH,mx,my=1120,720,0,0
love={graphics={getDimensions=function()return physicalW,physicalH end},mouse={getPosition=function()return mx,my end}}
local Layout=require('app.layout');local Table=require('app.table');local checks=0
local function check(value,label)assert(value,label);checks=checks+1 end
local function renderer()
 local m={settings={reducedMotion=true,groupEquivalent=false},game={gameId='geometry'},stackOpen=true}
 function m:prompt()end;function m:canSelect()return false end
 local r={colors={muted={1,1,1}},assets={iconSymbol=function()end},model=m,dt=1/60,cards={},hits={}}
 function r:drawPermanent(card,x,y,w,h,options)self.cards[#self.cards+1]={card=card,x=x,y=y,w=w,h=h,options=options}end
 function r:drawCard(card,x,y,w,h,options)self.cards[#self.cards+1]={card=card,x=x,y=y,w=w,h=h,options=options}end
 function r:hit(value)self.hits[#self.hits+1]=value end
 function r:inputBlocked()return false end
 function r:button()end;function r:text()end
 return r
end
local function field(count)
 local p={id='seat',name='Fixture',battlefield={}}
 for i=1,count do p.battlefield[#p.battlefield+1]={id='land-'..i,type='Land',tapped=i%3==0}end
 for i=1,3 do p.battlefield[#p.battlefield+1]={id='creature-'..i,type='Creature'}end
 return p
end
for _,size in ipairs({{1120,720},{1366,768},{1920,1080},{2560,1440}})do
 physicalW,physicalH=size[1],size[2]
 for _,scale in ipairs({.85,1,1.25})do
  Layout.setScale(scale);local w,h=Layout.dimensions()
  for _,count in ipairs({1,3,7,35})do
   local r=renderer();local L=Layout.table(w,h,r.model);local V=L.viewport
   local x,y,width,rowH=V.x+118,V.y+28,V.w-228,V.h/2-46
   Table.field(r,field(count),x,y,width,rowH,false)
   check(#r.cards==count+3,'Every distinct permanent keeps an individual native identity')
   for _,box in ipairs(r.cards)do
    local bw,bh=Layout.rotatedSize(box.w,box.h,box.options.angle)
    local left,top=box.x+(box.w-bw)/2,box.y+(box.h-bh)/2
    check(left>=x-.001 and left+bw<=x+width+.001,'Actual tapped and upright footprints stay inside their field')
    check(top>=y-.001 and top+bh<=y+rowH+.001,'Every rotated row stays inside its allocated half-table')
    check(box.w>box.h and (not box.card.tapped or math.abs(box.options.angle-math.rad(15))<.001),'Landscape tiles share the same compact tap angle for layout and drawing')
   end
  end
  local r=renderer();local L=Layout.table(w,h,r.model);local p={id='seat',hand={}}
  for i=1,7 do p.hand[i]={id='hand-'..i}end
  mx,my=0,0;Table.hand(r,p,L,w,h)
  check(#r.cards==7,'Seven-card hand has no offscreen or culled opening card')
  for _,box in ipairs(r.cards)do
   check(box.y>=0 and box.y+box.h<=h-40 and box.x>=0 and box.x+box.w<=w,'Idle hand shows complete cards within the fixed safe area')
  end
  local first,middle,last=r.cards[1],r.cards[4],r.cards[7]
  check(first.options.angle<-.2 and middle.options.angle==0 and last.options.angle>.2 and first.y>middle.y+10 and last.y>middle.y+10,'Seven-card hand fans along an arc around the middle card')
  local idle=r.cards[4];mx,my=(idle.x+idle.w/2)*Layout.scale,(idle.y+25)*Layout.scale;r.cards={}
  Table.hand(r,p,L,w,h)
  local raised
  for _,box in ipairs(r.cards)do if box.options.hovered then raised=box end end
  check(raised and raised.h>idle.h,'Pointer hover raises exactly one stable card')
  check(raised.y>=0 and raised.y+raised.h<=h-40,'Raised hand card stays fully visible')
  mx,my=(raised.x+raised.w/2)*Layout.scale,(raised.y+5)*Layout.scale;r.cards={}
  Table.hand(r,p,L,w,h)
  check(r.handHoverIndex==raised.options.index,'Pointer can move up onto the enlarged card without collapsing it')
  for i=8,55 do p.hand[i]={id='hand-'..i}end
  r.cards={};r.handScroll=1.75
  Table.hand(r,p,L,w,h)
  local ids={};for _,box in ipairs(r.cards)do ids[box.card.id]=true end
  check(r.handScroll==1.75 and ids['hand-2'] and not ids['hand-1'],'Fractional scrolling keeps exact whole-card indices and the partial delta')
 end
end
do
 local r=renderer();r.model.settings.groupEquivalent=true
 local p={id='seat',battlefield={
  {id='first',name='Island',type='[Land]',supertypes={'Basic'}},
  {id='second',name='Island',type='[Land]',supertypes={'Basic'}},
  {id='awakened',name='Animated land',type={'Land','Creature'}},
 }}
 r.model.canSelect=function(_,id)return id=='first' or id=='second'end
 r.model.prompt=function()return {priority=true}end
 local rows=Table.battlefieldRows(r,p)
 check(#rows.lands.groups==1 and #rows.lands.groups[1].cards==2,'Priority grouping keeps both native basic land objects')
 check(#rows.creatures.groups==1 and rows.creatures.shown[1].id=='awakened','An animated native creature land joins the front rank')
 for _,kind in ipairs({'target','play_mana'})do
  r.model.prompt=function()return {type=kind}end
  rows=Table.battlefieldRows(r,p)
  check(#rows.lands.groups==2 and rows.lands.shown[1].id=='first' and rows.lands.shown[2].id=='second',
      'Both offered basics have independent targets for '..kind)
 end
end
do
 local r=renderer();r.model.prompt=function()return {type='target'}end
 local a,b,c={id='a',type='Creature'},{id='b',type='Creature'},{id='c',type='Creature'}
 local seat={id='seat',battlefield={a,b}}
 Table.field(r,seat,0,0,600,180,false)
 local oldB=r.cards[2].x
 seat.battlefield={b,a};r.cards={};Table.field(r,seat,0,0,600,180,false)
 check(r.cards[1].x==oldB,'Unchanged native targets keep stationary coordinates during reordering')
 seat.battlefield={b,c};r.cards={};Table.field(r,seat,0,0,600,180,false)
 check(r.cards[1].x+r.cards[1].w<r.cards[2].x,'A replaced permanent gets its own spot during an open target prompt')
end
do
 local Cards=require('app.card_presentation')
 local mixed={
  {id='dryad',type={'Land','Creature'},printing={type='Land'}},
  {id='construct',type='[Artifact, Creature]',token=true},
  {id='forest',type='[Land]',type_line='Creature — Elf'},
  {id='artifact-land',type='[Artifact, Land]'},
  {id='walker',type='[Planeswalker]'},
  {id='saga',type_line='Enchantment — Saga'},
  {id='treasure',type='[Artifact]',isToken=true},
  {id='battle',type='[Battle]'},
  {id='manifest',faceDown=true,hidden=true,power='2',toughness='2',faceDownIdentity={type='Planeswalker'}},
  {id='unknown',hidden=true,type='',faceDownIdentity={type='Land'}},
  {id='subtype',type_line='Enchantment — Enchant Creature'},
 }
 local wanted={'creatures','creatures','lands','lands','walkers','support','support','support','creatures','support','support'}
 for i,card in ipairs(mixed)do check(Cards.battlefieldRole(card)==wanted[i],'Only public current types choose the lane for '..card.id)end
 check(#Cards.battlefieldTypes(mixed[9])==0 and #Cards.battlefieldTypes(mixed[10])==0,'Hidden identities do not provide type chips or lanes')
 local r=renderer();local p={id='seat',battlefield=mixed}
 local function draw(foe,width)
  r.cards={};r.hits={};Table.field(r,p,0,0,width,230,foe)
  local positions={};for _,box in ipairs(r.cards)do positions[box.card.id]=box end
  return positions
 end
 for _,width in ipairs({430,760,1320})do
  for _,foe in ipairs({false,true})do
   local pos=draw(foe,width)
   local support,land,walker,creature=pos.saga,pos.forest,pos.walker,pos.dryad
   check(support.x+support.w<land.x and walker.x+walker.w<creature.x,'Support and walkers have separate left-side lanes in both seat orientations')
   check(foe and land.y+land.h<creature.y or not foe and creature.y+creature.h<land.y,'Forward and rear ranks mirror depth for the opposing seat')
   check(math.abs(walker.y+walker.h/2-creature.y-creature.h/2)<.01,'A walker shares front depth with creatures')
  end
 end
 local normal=draw(false,1200);local firstX=normal.dryad.x
 p.battlefield[#p.battlefield+1]={id='walker2',type='Planeswalker'}
 p.battlefield[#p.battlefield+1]={id='walker3',type='Planeswalker'}
 local crowded=draw(false,1200)
 check(crowded.dryad.x>firstX+70 and crowded.walker3.x+crowded.walker3.w<crowded.dryad.x,'Additional walkers expand the dedicated strip')
 local rows=Table.battlefieldRows(r,p);local before=Table.multiplayerFieldWidth(rows)
 for i=1,28 do p.battlefield[#p.battlefield+1]={id='mana'..i,type='Land'} end
 for i=1,16 do p.battlefield[#p.battlefield+1]={id='equipment'..i,type='Artifact'} end
 rows=Table.battlefieldRows(r,p)
 check(Table.multiplayerFieldWidth(rows)>before,'Crowded simultaneous land and support lanes contribute to the multiplayer playmat width')
 local packed=draw(false,440);local last=packed.equipment16
 check(last.x+last.w<packed.forest.x and packed.mana28.x+packed.mana28.w<=440,'The last crowded support tile and all land IDs stay in their lane')
 local ids={};for _,box in ipairs(r.cards)do ids[box.card.id]=true end
 for _,card in ipairs(p.battlefield)do check(ids[card.id],'Crowded mixed battlefield retains native '..card.id)end
 p.battlefield={mixed[3],mixed[6]};local back=draw(false,900)
 check(back.saga.x<15 and back.forest.x+back.forest.w>885,'Sparse rear row preserves screen-left support and screen-right land')
 p.battlefield={{id='changing',type='Enchantment'}}
 local rear=draw(false,900).changing
 p.battlefield[1].type='[Enchantment, Creature]'
 local animated=draw(false,900).changing
 check(animated.y+animated.h/2<rear.y+rear.h/2,'Changing live type moves the same native enchantment to the creature rank')
end
do
 local cards={};for i=1,24 do cards[i]={tapped=i==23}end
 for _,width in ipairs({60,100,160,330})do
  for _,align in ipairs({0,.5,1})do
   local boxes=Layout.battlefieldRow(cards,0,50,width,85,38,1.6,align)
   local previous=-1
   for i,box in ipairs(boxes)do
    local rotated=Layout.rotatedSize(box.w,box.h,Layout.battlefieldAngle(cards[i]))
    local left=box.x+(box.w-rotated)/2
    check(left>previous and left>=7-.001 and left+rotated<=width-7+.001,
        'A tilted penultimate card stays inside a crowded lane and every native object retains an exposed edge')
    previous=left
   end
  end
 end
end
print('Table card sizing geometry: '..checks..' checks (synthetic presentation only)')
