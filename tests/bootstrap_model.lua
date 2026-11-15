-- Saved-state hydration/retry/cache contracts; no native game or user storage.
package.path='./?.lua;'..package.path
local calls={}
package.preload['app.api']=function()return{escape=tostring,new=function()return{update=function()end,quit=function()end,request=function(_,service,method,path,body,cb)calls[#calls+1]={path=path,callback=cb}end}end}end
love={math={random=function()return 1 end}}
local Model=require('app.model');local checks=0
local function check(ok,label)assert(ok,label);checks=checks+1;print('BOOTSTRAP PASS '..label)end
local function call(path)for i=#calls,1,-1 do if calls[i].path==path then return calls[i]end end;error(path)end
local m=Model.new();m.catalogHealth={ready=true};m:beginStartupHydration()
check(#calls==4 and not m:startupHydrationState().ready,'Healthy services alone do not complete saved-state hydration')
m:beginStartupHydration();check(#calls==4,'Repeated health checks do not duplicate in-flight hydration')
call('/settings').callback({theme='Verdant',accentColor='#33aa55',uiScale=1.25},nil,200)
call('/profile').callback(nil,'Temporary storage contention',503)
call('/decks').callback({decks={}},nil,200);call('/ui-layout').callback({matchPrefs={logOpen=false,stackOpen=true}},nil,200)
check(m.settingsLoaded and m.settings.theme=='Verdant'and m.logOpen==false and m.stackOpen==true,'Saved presentation and false layout flags are adopted before handoff')
local state=m:startupHydrationState();check(not state.ready and state.retryable and state.error:find('profile',1,true),'Failed saved profile blocks readiness with an explicit retry')
local stale=call('/profile');m:retryStartupHydration()
check(#calls==5 and call('/profile')~=stale,'Retry repeats only the failed saved-data part')
call('/profile').callback({name='Saved player'},nil,200);stale.callback({name='Obsolete player'},nil,200)
check(m:startupHydrationState().ready and m.playerName=='Saved player','A late superseded profile cannot overwrite the recovered identity')
local offline=Model.new();calls={};offline.catalogHealth={ready=false};offline:beginStartupHydration()
call('/settings').callback({},nil,200);call('/profile').callback({name='Offline player'},nil,200);call('/decks').callback({decks={}},nil,200);call('/ui-layout').callback({},nil,200)
check(offline:startupHydrationState().ready,'Saved library data can hydrate while card metadata is unavailable')
offline.catalogHealth.ready=true;offline:beginStartupHydration()
check(#calls==5 and not offline:startupHydrationState().ready,'Deck color metadata is re-enriched when the index becomes ready')
call('/decks').callback({decks={}},nil,200);check(offline:startupHydrationState().ready,'Enriched library completes without reloading preferences')
for i=1,800 do m:rememberCard({name='Card '..i,id='oracle-'..i})end
local count=0;for _ in pairs(m.byName)do count=count+1 end
check(count==512 and m.byName['Card 800']and not m.byName['Card 1'],'Frontend metadata cache retains a bounded recent set')
print('Bootstrap model checks: '..checks)
