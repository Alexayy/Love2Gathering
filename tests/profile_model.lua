package.path='./?.lua;'..package.path
local json=require('lib.json')
local Profile=require('app.profile')
local Model={};Model.__index=Model;Profile.install(Model)
local queue,checks={},0
local function ok(value,label)assert(value,label);checks=checks+1 end
function Model:request(service,method,path,body,callback)queue[#queue+1]={service=service,method=method,path=path,body=body,callback=callback}end
function Model:toast(value)self.toastLast=value end
local m=setmetatable({playerName='Planeswalker',catalogHealth={ready=true},settings={localArtworkOnly=true}},Model)
local function take()local value=table.remove(queue,1);assert(value);return value end
m:loadProfile();local load=take();ok(load.path=='/profile'and load.method=='GET','loads SQLite profile endpoint')
load.callback({name='Čarobnjak'});ok(m.profile.name=='Čarobnjak'and m.playerName=='Čarobnjak','saved name drives player name')
m:showProfile();local first=take();ok(m.page=='profile'and first.path:find('/gallery?',1,true),'profile opens independent artwork search')
m.profileQuery='new';m:profileSearchChanged();first.callback({items={{name='Old'}},total=1});ok(#m.profileItems==0,'stale search response cannot replace new query')
m:updateProfile(.3);local search=take();search.callback({items={{name='New'}},total=1});ok(m.profileItems[1].name=='New','current search result is accepted')
local card={oracle_id='11111111-1111-4111-8111-111111111111',printing_id='22222222-2222-4222-8222-222222222222',face=1,name='Back'}
ok(m:chooseProfileArt('avatar',card),'selects exact catalog reference');ok(m.profileDraft.avatar.face==1 and not m.profileDraft.avatar.image_uris,'profile does not copy arbitrary image URLs')
m:setProfileName('Saved');m:saveProfile();local save=take();ok(save.method=='PUT'and save.body.avatar.printingId==card.printing_id,'saves exact printing identity')
m:setProfileName('Newer edit');save.callback(save.body);ok(m.profile.name=='Saved'and m.profileDraft.name=='Newer edit'and m.profileDirty,'late save cannot replace newer editor input')
m:saveProfile();save=take();save.callback(save.body);ok(not m.profileDirty and m.profile.name=='Newer edit','acknowledged saved profile becomes default')
m:clearProfileArt('avatar');ok(m.profileDraft.avatar==nil and m.profileDirty,'clear is an actual persisted draft change');m:resetProfileDraft();ok(m.profileDraft.avatar.printingId==card.printing_id and not m.profileDirty,'reset restores saved profile only')
local p=m:profileForPlayer({profile={name='Opponent',playmat={printingId='other'}}});ok(p.name=='Opponent'and p.playmat.printingId=='other','native opponent profile takes precedence over local data')
ok(m.profile.life==nil,'profile never invents native life')
m:loadProfile();load=take();m.playerName='Match nickname';load.callback({name='Saved baseline'});ok(m.profile.name=='Saved baseline'and m.playerName=='Match nickname','late saved-profile load preserves an explicit match nickname')
print('PROFILE MODEL '..checks..' checks passed')
