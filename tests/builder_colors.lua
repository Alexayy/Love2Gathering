package.path='./?.lua;./?/init.lua;'..package.path
local requests={}
package.preload['app.api']=function()return{escape=function(s)return tostring(s)end,new=function()return{request=function(_,service,method,path,body,cb)requests[#requests+1]={service=service,method=method,path=path,body=body,cb=cb}end,update=function()end,quit=function()end}end}end
love={math={random=function()return 123 end}}
local Model=require('app.model');local Colors=require('app.builder_colors');local m=Model.new();local n=0
local function check(value,label)assert(value,label);n=n+1;print('BUILDER COLORS PASS '..label)end
local function path()m:searchCards();return requests[#requests].path end
m.settings.builderLayout='Simplified'
check(Colors.symbols(m)=='','Fresh builder has no hidden color filter')
m:toggleSearchColor('W');check(Colors.symbols(m)=='W'and Colors.selected(m,'W'),'White is an independent toggle')
check(path():find('&color=W&colorMode=any',1,true),'White sends identity union mode')
m:toggleSearchColor('B');check(Colors.symbols(m)=='WB'and Colors.selected(m,'W')and Colors.selected(m,'B'),'Black keeps White selected')
check(path():find('&color=WB&colorMode=any',1,true),'White plus Black sends OR semantics')
m:toggleSearchColor('G');check(Colors.symbols(m)=='WBG','White Black Green retain all three toggles')
check(path():find('&color=WBG&colorMode=any',1,true),'Abzan colors default to any selected identity color')
m:toggleExactSearchColors();check(m.searchColorExact and path():find('&color=WBG&colorMode=exact',1,true),'Exact mode requests the complete selected identity')
m:toggleSearchColor('B');check(m.searchColorExact and Colors.symbols(m)=='WG','Removing a color keeps Exact mode and updates its set')
m:toggleSearchColor('C');check(Colors.symbols(m)=='C'and not Colors.selected(m,'W'),'Colorless identity is exclusive of colored identities')
check(path():find('&color=C&colorMode=exact',1,true),'Colorless Exact is a real empty-identity request')
m:toggleSearchColor('R');check(Colors.symbols(m)=='R'and not Colors.selected(m,'C'),'A colored identity replaces Colorless')
m:toggleSearchColor('R');check(Colors.symbols(m)==''and not m.searchColorExact,'Clearing the last color clears Exact mode')
check(not path():find('&color=',1,true),'No selected colors means no color restriction')
m:toggleSearchColor('W');m:searchCards();local old=requests[#requests];m:toggleSearchColor('B');old.cb({cards={{name='Old White'}},total=1})
check(#m.cards==0,'A response begun before a toggle cannot restore old card results')
m:toggleSearchColor('All');check(Colors.symbols(m)==''and m.searchColor=='All','All clears the selected set')
m:toggleExactSearchColors();check(not m.searchColorExact,'Exact cannot hide all cards when no colors are selected')
m.settings.builderLayout='Classic';m:setSearchColor('R');check(path():find('&color=R',1,true)and not path():find('colorMode',1,true),'Classic single-color requests retain their legacy contract')
m.settings.builderLayout='Simplified';check(Colors.symbols(m)=='R','Classic color choices synchronize the Simplified toggle')
m:newDeck();check(Colors.symbols(m)==''and not m.searchColorExact,'Opening another deck clears all old identity filters')
print('Builder color checks: '..n..' passed')
