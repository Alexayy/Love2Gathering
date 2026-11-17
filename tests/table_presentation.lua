package.path='./?.lua;'..package.path
local P=require('app.table_presentation');local json=require('lib.json');local count=0
local function check(value,label)assert(value,label);count=count+1 end
local function card(id)return{id=id,name='Plains',type='Basic Land — Plains',ownerId='owner',controllerId='owner',tapped=false,counters={},attachmentIds={},linkedExile={}}end
local function clone(value)return json.decode(json.encode(value))end
local a,b=card('first'),card('second')
local grouped=P.groups({a,b},true,function()return false end)
check(#grouped==1 and grouped[1].cards[1].id=='first'and grouped[1].cards[2].id=='second','Equivalent basics retain exact individual native identities')
check(#P.groups({a,b},false)==2,'Grouping can be reversed without losing objects')
for _,change in ipairs({{tapped=true},{counters={charge=1}},{ownerId='other'},{controllerId='other'},{power='3',toughness='3'},
 {currentKeywords={{id='haste'}}},{currentRules='An actual different native ability'},{attachmentIds={'aura'}},{attachedToId='host'},
 {linkedExile={{id='exiled'}}},{attacking=true},{blocking=true},{mutate={count=1,components={{id='component'}}}},
 {faceDown=true},{hidden=true},{tokenSourceId='different-source'},{summoningSick=true},{damage=1}})do
 local other=clone(b);for key,value in pairs(change)do other[key]=value end
 check(#P.groups({a,other},true)==2,'Public differences and complex objects never combine: '..json.encode(change))
end
check(#P.groups({a,b},true,function(id)return id=='first'end)==2,'Different native legal selections stay distinct')
local nonbasic=clone(a);nonbasic.type='Land';local another=clone(nonbasic);another.id='third'
check(#P.groups({nonbasic,another},true)==2,'A common name never groups ordinary nonbasic lands')
for _,size in ipairs({{1120,720},{1366,768},{1920,1080},{2560,1080},{2560,1440}})do
 local L=P.layout(size[1],size[2],{cardScale=1.3},{},true)
 check(L.viewport.y+L.viewport.h>L.handY+L.handH*.8,'Hand overlays usable terrain without reserving a blank strip')
 check(L.viewport.x+L.viewport.w<L.rail.x and L.rail.x+L.rail.w<=size[1],'Dock and terrain have separate bounded horizontal regions')
end
local r={model={prompt=function()return{priority=true}end}}
check(not P.freeze(r),'An ordinary priority window permits layout updates')
r.model.prompt=function()return{type='target'}end;check(P.freeze(r),'Required native targeting freezes field positions')
r.model.prompt=function()return nil end;r.drag={};check(P.freeze(r),'Dragging freezes field positions')
print('Table presentation: '..count..' checks (presentation only)')
