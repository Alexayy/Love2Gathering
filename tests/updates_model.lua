-- Updater state machine with controlled loopback replies; no network/installer.
local json=require('lib.json');local count=0;local now=0;local quits={};local external={}
local function check(ok,label)assert(ok,label);count=count+1;print('UPDATES MODEL PASS '..label)end
love={timer={getTime=function()return now end},event={quit=function(code)quits[#quits+1]=code end},system={openURL=function(value)external[#external+1]=value;error('Updater must not open arbitrary paths/URLs')end}}
local execute,popen=os.execute,io.popen
os.execute=function(value)external[#external+1]=value;error('Updater must not execute shell commands')end
io.popen=function(value)external[#external+1]=value;error('Updater must not start shell pipes')end
local Updates=require('app.updates')
local function copy(value)return value and json.decode(json.encode(value))end
local function client()
 local m={calls={}}
 function m:request(service,method,path,body,callback,quiet)
  self.calls[#self.calls+1]={service=service,method=method,path=path,body=copy(body),callback=callback,quiet=quiet};return true
 end
 return m
end
local candidate={id='verified-candidate',version='2026.11.19.1',expectedSize=20971520,url='https://untrusted.invalid/arbitrary.exe',path='C:\\arbitrary\\installer.exe',command='do-not-execute'}
local m=client();Updates.poll(m);check(#m.calls==0,'Loading the module and polling idle startup performs no update request')
local auth=client();local secret='update-auth-fixture-sentinel-4702'
check(Updates.auth(auth,secret),'GitHub access is configured only by an explicit auth operation')
local access=auth.calls[1];local keys=0;for _ in pairs(access.body)do keys=keys+1 end
check(access.service=='catalog'and access.method=='POST'and access.path=='/updates/auth'and keys==1 and access.body.token==secret,'Auth sends exactly the token in a POST body without URL/query/path parameters')
check(not Updates.auth(auth,secret)and#auth.calls==1,'Pending auth cannot enqueue a duplicate credential save')
access.callback({state='idle',authenticated=true})
check(auth.updateState.authenticated and not json.encode(auth.updateState):find(secret,1,true)and auth.updateState.token==nil,'Auth acknowledgement stores only credential availability metadata, never the token')
Updates.auth(auth,'');access=auth.calls[2]
check(access.path=='/updates/auth'and access.body.token==''and next(access.body,'token')==nil,'Forget uses the same explicit body contract with an empty token')
access.callback({state='idle',authenticated=false});check(not auth.updateState.authenticated and#quits==0,'Forgetting GitHub access neither checks releases nor closes the application')
auth.updateApplying=true;check(not Updates.auth(auth,secret)and#auth.calls==2,'Credential changes are blocked during installation preparation')
Updates.check(m);local request=m.calls[1]
check(request.service=='catalog'and request.method=='POST'and request.path=='/updates/check'and m.updateBusy and request.quiet,'Only explicit checking starts the catalog update operation')
check(next(request.body)==nil and#quits==0,'The check request sends no client URL/path and never closes the application')
request.callback({state='checking'});check(not m.updateBusy and m.updateState.state=='checking','Checking acknowledgement releases only its request busy state')
Updates.poll(m);local first=m.calls[2];Updates.poll(m)
check(#m.calls==2 and first.method=='GET'and first.path=='/updates/status'and m.updatePolling,'Checking status has one bounded concurrent polling lane')
first.callback({state='checking'});now=.4;Updates.poll(m);check(#m.calls==2,'Status polling waits for its presentation interval')
now=.7;Updates.poll(m);m.calls[3].callback({state='available',candidate=copy(candidate),channel='development'})
check(m.updateState.state=='available'and m.updateState.candidate.id==candidate.id,'Only the controlled available response supplies the candidate identity')
Updates.download(m,candidate.id);request=m.calls[4]
check(request.path=='/updates/download'and request.body.candidateId==candidate.id and not request.body.url and not request.body.path and not request.body.command,'Download submits only the opaque candidate ID, never a URL/path/command')
local fields=0;for _ in pairs(request.body)do fields=fields+1 end;check(fields==1,'Untrusted candidate display fields cannot expand the install request')
request.callback({state='downloading',candidate=copy(candidate),progress={downloadedBytes=1048576,totalBytes=20971520}})
now=1.5;Updates.poll(m);m.calls[5].callback({state='ready',candidate=copy(candidate),method='appimage'})
check(m.updateState.state=='ready'and#quits==0 and#external==0,'Verified ready status neither executes nor opens downloaded files')
m.game={running=true};check(not Updates.canApply(m)and not Updates.apply(m,candidate.id),'A running local game blocks application and sends no installer request')
m.game=nil;m.roomConnectionId='membership';check(not Updates.canApply(m)and not Updates.apply(m,candidate.id),'An active room membership blocks installation before a game starts')
m.roomConnectionId=nil;m.roomGameActive=true;check(not Updates.canApply(m),'An active room game also blocks installation without a membership field')
m.roomGameActive=nil;m.replay={id='saved-game'};m.game={running=true};m.liveGame={running=true}
check(not Updates.canApply(m),'A live local match behind read-only replay still blocks installation')
m.game=nil;m.liveGame=nil;m.replay=nil
local before=#m.calls;check(Updates.apply(m,candidate.id),'An idle user may explicitly request the verified staged update')
request=m.calls[#m.calls];check(#m.calls==before+1 and request.path=='/updates/apply'and request.body.candidateId==candidate.id and m.updateApplying and m.updateBusy and#quits==0,'Apply waits behind a pending acknowledgement instead of quitting immediately')
check(not Updates.apply(m,candidate.id)and# m.calls==before+1,'A delayed apply acknowledgement cannot enqueue a second installation')
request.callback(nil,'Installer handoff failed')
check(m.updateApplying and not m.updateBusy and m.calls[#m.calls].method=='GET'and m.calls[#m.calls].path=='/updates/status'and#quits==0,'A lost installer acknowledgement keeps the modal while reconciling through one read')
m.calls[#m.calls].callback({state='error',candidate=copy(candidate)})
check(not m.updateApplying and not m.updateBusy and m.updateState.state=='error'and#quits==0,'A failed reconciled handoff keeps the application open and releases the modal')
Updates.apply(m,candidate.id);m.calls[#m.calls].callback({state='ready',candidate=copy(candidate)})
check(not m.updateApplying and#quits==0,'A response without apply_requested acknowledgement never closes the application')
Updates.apply(m,candidate.id);request=m.calls[#m.calls];request.callback({state='apply_requested',path='/tmp/do-not-execute',command='do-not-execute'})
check(m.updateQuitting and#quits==1 and quits[1]==0 and#external==0,'Only apply_requested acknowledgement queues graceful application shutdown; response paths stay inert')
check(not Updates.canApply(m)and not Updates.apply(m,candidate.id),'An acknowledged quitting update cannot be submitted twice')
local recovered=client();Updates.apply(recovered,candidate.id);recovered.calls[1].callback(nil,'Acknowledgement lost')
check(#recovered.calls==2 and recovered.calls[1].method=='POST'and recovered.calls[2].method=='GET'and recovered.updateApplying,'Lost acknowledgement never repeats POST apply and retains its pending modal')
recovered.calls[2].callback({state='apply_requested',candidate=copy(candidate)})
check(#quits==2 and recovered.updateQuitting and not recovered.updateApplying and#recovered.calls==2,'One exact previously approved candidate read reconciles to one graceful quit')
local foreign=client();Updates.apply(foreign,candidate.id);foreign.calls[1].callback(nil,'Acknowledgement lost');foreign.calls[2].callback({state='apply_requested',candidate={id='foreign-candidate'}})
check(#quits==2 and not foreign.updateApplying and not foreign.updateQuitting and#foreign.calls==2,'A foreign candidate reconciliation never quits or resubmits and releases its modal')
local lostRead=client();Updates.apply(lostRead,candidate.id);lostRead.calls[1].callback(nil,'Acknowledgement lost');lostRead.calls[2].callback(nil,'Status unavailable')
check(#quits==2 and not lostRead.updateApplying and lostRead.updateState.state=='error','A failed reconciliation read keeps the application open and releases pending input')
local stale=client();Updates.check(stale);stale.calls[1].callback({state='checking'});now=3;Updates.poll(stale);local old=stale.calls[2]
Updates.download(stale,candidate.id);stale.calls[3].callback({state='downloading',candidate=copy(candidate)});old.callback({state='available',candidate={id='obsolete'}})
check(stale.updateState.state=='downloading'and stale.updateState.candidate.id==candidate.id,'A status read from an earlier operation cannot replace a newer update state')
local errors=client();Updates.check(errors);errors.calls[1].callback(json.null,'Unavailable')
check(errors.updateState.state=='error'and errors.updateState.error=='Unavailable'and#quits==2,'Null or failed service replies remain visible errors without closing the application')
Updates.check(errors);errors.calls[2].callback({state='checking'});now=5;Updates.poll(errors);errors.calls[3].callback(nil,'Lost status connection')
check(errors.updateState.state=='error'and errors.updateState.error=='Lost status connection'and not errors.updatePolling,'A failed status read releases its lane and keeps an explicit retryable UI state')
local source=client();local buttons=0;local view={m=source,r={colors={accent={},muted={},gold={}}},S={Separator=function()end,NewLine=function()end,Text=function()end,Textf=function()end,Button=function()buttons=buttons+1;return true end}}
Updates.build(view,600,{packaged=false,channel='source'})
check(buttons==0 and#source.calls==0 and#external==0,'A source checkout exposes no check/download/install button and executes nothing')
os.execute=execute;io.popen=popen
print('Updater model: '..count..' checks passed (controlled transport only)')
