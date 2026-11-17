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
 function r:drawPermanent(card,x,y,w,h)self.cards[#self.cards+1]={card=card,x=x,y=y,w=w,h=h}end
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
    local left=box.x+(box.card.tapped and(box.w-box.h)/2 or 0)
    local right=left+(box.card.tapped and box.h or box.w)
    check(left>=x-.001 and right<=x+width+.001,'Actual tapped and upright footprints stay inside their field')
    check(box.y>=y-.001 and box.y+box.h<=y+rowH+.001,'Every row stays inside its allocated half-table')
   end
  end
  local r=renderer();local L=Layout.table(w,h,r.model);local p={id='seat',hand={}}
  for i=1,7 do p.hand[i]={id='hand-'..i}end
  mx,my=0,0;Table.hand(r,p,L,w,h)
  check(#r.cards==7,'Seven-card hand has no offscreen or culled opening card')
  for _,box in ipairs(r.cards)do
   check(box.y>=0 and box.y+box.h<=h-40 and box.x>=0 and box.x+box.w<=w,'Idle hand shows complete cards within the fixed safe area')
  end
  local idle=r.cards[4];mx,my=(idle.x+idle.w/2)*Layout.scale,(idle.y+25)*Layout.scale;r.cards={}
  Table.hand(r,p,L,w,h)
  local raised
  for _,box in ipairs(r.cards)do if box.options.hovered then raised=box end end
  check(raised and raised.h>idle.h,'Pointer hover raises exactly one stable card')
  check(raised.y>=0 and raised.y+raised.h<=h-40,'Raised hand card stays fully visible')
 end
end
print('Table card sizing geometry: '..checks..' checks (synthetic presentation only)')
