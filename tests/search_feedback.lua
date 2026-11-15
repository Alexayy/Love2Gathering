-- Failed local metadata requests must not masquerade as an empty card catalog.
package.path='./?.lua;'..package.path
local calls={}
package.preload['app.api']=function()return{escape=function(v)return tostring(v)end,new=function()return{request=function(_,service,method,path,body,callback)calls[#calls+1]=callback end}end}end
local Model=require('app.model');local m=Model.new();local checks=0
local function check(value,label)assert(value,label);checks=checks+1;print('SEARCH FEEDBACK PASS '..label)end
m:searchCards();calls[1](nil,'timeout',0)
check(not m.searchBusy and m.searchError=='timeout','Failed search exposes its error rather than claiming no matches')
m:searchCards();check(m.searchBusy and not m.searchError,'A fresh search clears the prior error while loading')
local previous=calls[2];m:searchCards();calls[3]({cards={{name='Forest'}},total=1},nil,200)
previous(nil,'old timeout',0)
check(not m.searchBusy and not m.searchError and m.total==1 and m.cards[1].name=='Forest','Late failed searches cannot replace a newer successful page')
print('Search feedback checks: '..checks)
