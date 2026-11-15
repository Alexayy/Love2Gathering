-- Builder binding and asynchronous format/editor ownership, no service writes.
package.path='./?.lua;'..package.path
local calls={}
package.preload['app.api']=function()return{escape=function(s)return s end,new=function()return{request=function(_,service,method,path,body,cb)calls[#calls+1]={path=path,callback=cb}end}end}end
local opened
package.preload['app.set_picker']=function()return{open=function(v,options)opened=options end}end
love={math={random=function()return 1234 end}}
local Model=require('app.model');local Builder=require('app.builder');local m=Model.new();local v={m=m}
local checks=0;local function check(value,label)assert(value,label);checks=checks+1;print('SET FILTER PASS '..label)end
m.searchFormat='Modern';m:refreshSets();local old=calls[#calls]
m.searchFormat='Commander';m:refreshSets();local fresh=calls[#calls]
old.callback({sets={{code='old',name='Old Modern'}}},nil,200)
check(m.setsBusy and #m.sets==0,'An earlier format cannot replace the pending new format list')
fresh.callback({sets={{code='thb',name='Theros Beyond Death'}}},nil,200)
check(not m.setsBusy and m.setsFormat=='Commander'and m.sets[1].code=='thb','Only the current format response supplies grid items')
m:refreshSets();local stale=calls[#calls];m.editGeneration=(m.editGeneration or 0)+1
stale.callback({sets={{code='wrong',name='Earlier editor'}}},nil,200)
check(not m.setsBusy and m.sets[1].code=='thb','An old editor response is discarded without leaving loading stuck')
m.editDeck={id='current'};m.page='builder';m.settings.builderLayout='Classic';m.searchSet='All'
Builder.openSetFilter(v,'builder-set')
check(opened.selected==''and opened.isCurrent(),'Classic opens the grid with its All-sets sentinel and current owner')
local initial=opened.items();m.sets={{code='mom',name='March of the Machine'}}
check(opened.items()~=initial and opened.items()[1].code=='mom','An open grid sees asynchronously replaced set arrays')
opened.onSelect('mom');check(m.searchSet=='mom'and m.searchTimer==.23,'Choosing a set updates only the builder filter and starts its normal debounce')
opened.onSelect('');check(m.searchSet=='All','All sets maps back to the builder sentinel')
m.searchFormat='Standard';check(not opened.isCurrent(),'Format changes invalidate the old set selector')
m.searchFormat='Commander';m.settings.builderLayout='Simplified';v.builderFiltersOpen=true
Builder.openSetFilter(v,'simple-set');check(opened.isCurrent(),'Simplified uses the same grid under its active filter popup')
v.builderFiltersOpen=nil;check(not opened.isCurrent(),'Closing the Simplified parent invalidates the child callback')
v.builderFiltersOpen=true;Builder.openSetFilter(v,'simple-set');m.editDeck={id='replacement'}
check(not opened.isCurrent(),'A replacement deck cannot receive an old grid selection')
print('Set filter checks: '..checks)
