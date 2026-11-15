-- Pure presentation geometry. Native timing/actions/rules are not exercised.
package.path='./?.lua;'..package.path
package.preload['app.board_fx']=function()return{}end
package.preload['app.priority']=function()return{groups={}}end
local physicalW,physicalH,mx,my=1120,720,0,0
love={graphics={getDimensions=function()return physicalW,physicalH end},mouse={getPosition=function()return mx,my end}}
local Layout=require('app.layout');local Table=require('app.table');local checks=0
local function check(value,label)assert(value,label);checks=checks+1 end
local function near(a,b)return math.abs(a-b)<.0001 end
local function renderer(world)
 local r={colors={muted={1,1,1}},assets={iconSymbol=function()end},model={settings={reducedMotion=true}},dt=1/60,cards={},hits={}}
 if world then r.worldTransform={scale=1}end
 function r:drawPermanent(card,x,y,w,h)self.cards[#self.cards+1]={card=card,x=x,y=y,w=w,h=h}end
 function r:drawCard(card,x,y,w,h,options)self.cards[#self.cards+1]={card=card,x=x,y=y,w=w,h=h,options=options}end
 function r:hit(hit)self.hits[#self.hits+1]=hit end
 return r
end
local function field(count)
 local p={name='Fixture',battlefield={}}
 for i=1,count do p.battlefield[#p.battlefield+1]={id='land-'..i,type='Land'}end
 for i=1,3 do p.battlefield[#p.battlefield+1]={id='creature-'..i,type='Creature'}end
 return p
end
local function oldDuel(height)
 local hand=math.max(116,math.min(140,height*.15));local available=((height-hand-46-260)/2)-14
 local land=math.min(128,math.max(66,height*.12),available,(available-12)/2)
 return land,math.min(157,available-land-12)
end
local function drawn(r,id)for _,box in ipairs(r.cards)do if box.card.id==id then return box end end;error('Missing fixture card '..id)end
for _,size in ipairs({{1120,720},{1440,900},{2560,1080}})do
 physicalW,physicalH=size[1],size[2]
 for _,ui in ipairs({.85,1,1.25})do
  Layout.setScale(ui);local w,h=Layout.dimensions();local L=Layout.table(w,h)
  for _,count in ipairs({1,3,7,35})do
   local r=renderer();Table.field(r,field(count),L.fieldX,L.humanY,L.fieldW,L.rowH,false)
   local first,creature=drawn(r,'land-1'),drawn(r,'creature-1');local oldLand,oldCreature=oldDuel(h)
   for _,comparison in ipairs({{first.h,oldLand},{creature.h,oldCreature}})do
    check(comparison[1]/comparison[2]>=1.05 and comparison[1]/comparison[2]<=1.15,'Duel cards grow adaptively within5–15percent')
   end
   check(first.y>=creature.y+creature.h+12-.001,'Separate land/nonland rows retain their gap')
   check(first.y+first.h<=L.fieldBottom-14+.001,'Lower row stays inside the allocated field')
   check(L.fieldBottom-8>=first.y+first.h+6-.001,'Mana pool starts below enlarged lands')
   check(L.fieldBottom+12<h-84,'Mana indicators and resting hand retain a gap')
   for _,box in ipairs(r.cards)do
    check(box.x>=L.fieldX and box.x+box.w<=L.fieldX+L.fieldW,'Crowded row stays inside its horizontal field')
    check(box.x+(box.w-box.h)/2>=L.fieldX,'Tapped-card edge reserve grows with the card')
   end
  end
  for _,state in ipairs({'resting','expanded','hovered'})do
   local r=renderer();local p={hand={}};for i=1,7 do p.hand[i]={id='hand-'..i}end
   if state=='expanded'then r.drag={kind='hand'}elseif state=='hovered'then r.hover={kind='hand',index=4}end
   Table.hand(r,p,L,w,h)
   local small=math.min(104,math.max(84,w*.073));local expected=state=='resting'and small or 146
   for _,box in ipairs(r.cards)do
    local width=(state=='hovered'and box.card.id=='hand-4')and math.min(206,w*.16)or expected
    check(near(box.w,width*1.05)and near(box.h,box.w*1.4),'Every hand state grows uniformly by5percent')
    check(box.x>=0 and box.x+box.w<=w,'Hand stays inside viewport width')
   end
   check(near(L.handH,math.max(116,math.min(140,h*.15))*1.05),'Shared hand reservation grows once')
   if state=='resting'then check(near(r.cards[1].y,h-84+4.5),'Resting visible strip grows from80to84')end
   if state=='hovered'then check(r.handBounds.y>=0,'Expanded hovered card remains inside the viewport')end
  end
 end
end
physicalW,physicalH=2560,1080;Layout.setScale(1)
for _,count in ipairs({1,7,35})do
 local r=renderer(true);Table.field(r,field(count),168,140,706,462,false)
 check(near(drawn(r,'land-1').h,154*1.1)and near(drawn(r,'creature-1').h,196*1.1),'World lands and nonlands grow10percent without camera scaling')
end
print('Table card sizing geometry: '..checks..' checks (synthetic presentation only)')
