-- Local filtering and owner fences only; no catalog, images or native game.
package.path='./?.lua;'..package.path
local Picker=require('app.set_picker')
local checks=0;local function check(value,label)assert(value,label);checks=checks+1;print('SET PICKER PASS '..label)end
local focus,hover=0,0
package.loaded['lib.Slab.Internal.UI.Region']={ClearHotInstance=function()hover=hover+1 end}
local v={S={SetInputFocus=function(id)assert(id==nil);focus=focus+1 end}}
local items={{code='thb',name='Theros Beyond Death',count=3},{code='all',name='Alliances',count=12},{code='tst',name='Čarobni Đavoli',count=2}}
local calls={};local current=true
local function open(source,selected)
 return Picker.open(v,{id='test',owner=items,items=source or items,selected=selected or'',onSelect=function(code)calls[#calls+1]=code end,isCurrent=function()return current end})
end
local state=open();local result=Picker.items(v)
check(#result==4 and result[1].all and result[1].code==''and result[3].code=='all','All sets and the real Alliances code remain distinct options')
Picker.filter(v,'THB');result=Picker.items(v)
check(#result==2 and result[2].code=='thb','Set code matching ignores ASCII case and keeps the All sets tile')
Picker.filter(v,'THEROS beyond');check(#Picker.items(v)==2,'Set names match locally without a catalog request')
Picker.filter(v,'ČAROBNI ĐAVOLI');check(Picker.items(v)[2].code=='tst','Common accented Latin set names retain UTF-8 case-insensitive search')
Picker.filter(v,'nema takvog seta');check(#Picker.items(v)==1,'An unmatched local query still provides an explicit All sets choice')
check(#calls==0,'Typing and filtering do not select a set')
Picker.close(v);check(not v.setPicker and#calls==0 and focus>0 and hover>0,'Cancel clears child focus and hidden hover without changing the parent filter')

local source={};state=open(function()return source end,'thb');Picker.filter(v,'THEROS');check(#Picker.items(v)==1,'An opening may wait on an initially empty asynchronous set list')
source=items;result=Picker.items(v)
check(state.query=='THEROS'and#result==2 and result[2].code=='thb'and state.selected=='thb','Late array replacement preserves the typed query and current selection')
source={{code='mom',name='March of the Machine'}}
check(#Picker.items(v)==1 and state.query=='THEROS','A later provider response replaces old matching rows without resetting the query')
Picker.close(v)

state=open();Picker.filter(v,'thb');check(not Picker.select(v,'all')and#calls==0,'A stale or hidden tile cannot select an absent filtered option')
check(Picker.select(v,'thb')and calls[1]=='thb'and not v.setPicker,'Selecting a visible tile applies only the owner callback and closes the child')
state=open();check(Picker.select(v,'')and calls[2]=='','All sets explicitly clears the owning set filter')
state=open();check(Picker.select(v,'all')and calls[3]=='all','Alliances remains selectable as a real set rather than clearing the filter')

local old=open();local newer=open();check(old.closed and old.token~=newer.token,'Each child opening has an independent Slab interaction identity')
check(not Picker.select(v,'thb',old)and v.setPicker==newer and#calls==3,'An old opening callback cannot select a set into a newer owner')
current=false;check(not Picker.current(v)and not Picker.select(v,'thb')and#calls==3,'Closing or replacing the owner invalidates the child before any callback')
current=true

local parent={set='',offset=24,query='artist filter',selectedId='staged-edition'};local deck={revision=7,printing='saved-edition'}
Picker.open(v,{owner=parent,items=items,onSelect=function(code)parent.set=code;parent.offset=0 end,isCurrent=function()return true end})
Picker.select(v,'thb')
check(parent.set=='thb'and parent.offset==0 and parent.query=='artist filter'and parent.selectedId=='staged-edition','A set choice changes the filter/page while preserving staged edition and other search text')
check(deck.revision==7 and deck.printing=='saved-edition','Choosing a set does not apply an edition or modify the deck')
print('Set picker model checks: '..checks..' passed')
