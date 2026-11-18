-- Real About/Slab controls; update replies and graceful quit are controlled.
local ledger={};local json=require('lib.json')
package.preload['app.api']=function()return{escape=tostring,new=function()return{request=function(_,service,method,path,body,callback)
 local call={service=service,method=method,path=path,body=body and json.decode(json.encode(body)),callback=callback};ledger[#ledger+1]=call
 if not path:find('^/updates/')and callback then callback({saved=true})end;return true
end,update=function()end,quit=function()end}end}end
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout')
local Region=require('lib.Slab.Internal.UI.Region');local Cursor=require('lib.Slab.Internal.Core.Cursor')
local output=assert(os.getenv('LOVE2GATHERING_UPDATES_OUTPUT'));local manifest=assert(os.getenv('LOVE2GATHERING_UPDATES_FIXTURE'))
local m,r,v,p,runner;local clock,wake=0,0;local mouse={x=2,y=2};local down=false;local controls,texts,regions,inputs={},{},{},{};local checks,shots,quits,external={},{},{},{};local capture;local realQuit;local phase='startup';local keys={};local authSaved=false
local secret='update-auth-fixture-sentinel-4702';local accessInput='update-github-access'
local candidate={id='verified-fixture-candidate',version='2026.11.19.1',expectedSize=20971520,url='https://untrusted.invalid/never-open.exe',path='C:\\never-execute.exe',command='do-not-run'}
local function copy(value)return json.decode(json.encode(value))end
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('UPDATES UI PASS '..label)end
local function wait(seconds)wake=clock+(seconds or .08);coroutine.yield()end
local function count(path)local n=0;for _,call in ipairs(ledger)do if call.path==path then n=n+1 end end;return n end
local function latest(path)for i=#ledger,1,-1 do local c=ledger[i];if c.path==path then return c end end end
local function reply(call,value,errorCode)assert(call and not call.answered,'Missing/unexpected duplicate controlled response');call.answered=true;value=value and copy(value);if type(value)=='table'and value.authenticated==nil then value.authenticated=authSaved end;call.callback(value,nil,errorCode);wait(.13)end
local function pending(path)
 for _=1,80 do for _,call in ipairs(ledger)do if call.path==path and not call.answered then return call end end;wait(.04)end
 error('No controlled update request '..path)
end
local function bounds()local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();return{x=x+dx,y=y+dy,w=w,h=h}end
local function move(box)local oldX,oldY=mouse.x,mouse.y;mouse.x=(box.x+box.w/2)*Layout.scale;mouse.y=(box.y+box.h/2)*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-oldX,mouse.y-oldY)end
local function click(box)
 assert(box,'Missing actual About control');move(box);wait(.05);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.05);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.13)
end
local function inView(box)local region=regions['settings-about-content'];return box and region and box.y>=region.y and box.y+box.h<=region.y+region.h end
local function visible(label,isText)
 for _=1,60 do local box=(isText=='input'and inputs or isText and texts or controls)[label];if inView(box)then return box end
  local region=assert(regions['settings-about-content']);move({x=region.x+region.w*.88,y=region.y+region.h*.5,w=1,h=1});wait(.025);S.OnWheelMoved(0,box and box.y<region.y and 5 or-5);wait(.04)
 end;error('Update control not reachable: '..label..' '..json.encode({control=controls[label],region=regions['settings-about-content'],hot=Region.GetHotInstanceId(),debug=Region.GetDebugInfo('settings-about-content')}))
end
local function shot(name)capture=name;shots[#shots+1]=output..'/'..name..'.png';wait(.12)end
local function enterAccess(value)
 click(visible(accessInput,'input'));keys.lctrl=true;S.OnKeyPressed('a','a',false);wait(.04);S.OnKeyReleased('a','a');keys.lctrl=nil;S.OnTextInput(value);wait(.15)
end
local function publicBody(body)
 local result=body and copy(body);if result and result.token~=nil then result.token=result.token==''and''or'[redacted fixture token]'end;return result
end
local function scenario()
 wait(.2);click(controls.About);wait(.12)
 check(v.settingsTab=='About'and v.aboutState.info.packaged,'Real About tab reads the isolated packaged build manifest')
 check(count('/updates/check')==0 and count('/updates/status')==0 and count('/updates/apply')==0,'Opening About never checks online or installs automatically')
 check(inputs[accessInput]and inputs[accessInput].isPassword and controls['Save GitHub access'].disabled,'GitHub access uses an actual masked Slab input with explicit disabled empty Save')
 m.updateAuthToken='prefill-fixture-only';S.SetInputFocus(nil);wait(.12);click(visible(accessInput,'input'))
 check(S.GetInputText()=='prefill-fixture-only'and require('lib.Slab.Internal.UI.Input').GetDebugInfo().Text==string.rep('*',#'prefill-fixture-only'),'An unfocused programmatic password replacement synchronizes its real and masked values')
 enterAccess(secret);local debug=require('lib.Slab.Internal.UI.Input').GetDebugInfo()
 check(m.updateAuthToken==secret and debug.Text==string.rep('*',#secret)and count('/updates/auth')==0,'Actual typed access is masked and remains unsent until Save is clicked');shot('update-auth-masked')
 click(visible('Save GitHub access'));local auth=latest('/updates/auth');local fields=0;for _ in pairs(auth.body)do fields=fields+1 end
 check(auth.service=='catalog'and auth.method=='POST'and auth.path=='/updates/auth'and fields==1 and auth.body.token==secret,'Actual Save sends only token in the local POST body without URL/query/path fields')
 check(m.updateAuthToken==''and inputs[accessInput].text==''and inputs[accessInput].readOnly,'Saving immediately clears local credential entry and locks it during acknowledgement')
 authSaved=true;reply(auth,{state='idle',authenticated=true});click(visible(accessInput,'input'));debug=require('lib.Slab.Internal.UI.Input').GetDebugInfo()
 check(S.GetInputText()==''and debug.Text==''and debug.CursorPos==0 and debug.SelectionStart==debug.SelectionEnd,'Refocusing after Save cannot recover the old secret or stale selection from Slab')
 check(not json.encode(m.updateState):find(secret,1,true)and not json.encode(m.settings):find(secret,1,true)and texts['GitHub access token saved.'],'Auth state exposes only saved availability while settings remain secret-free')
 click(visible('Forget GitHub access'));auth=latest('/updates/auth');check(auth.body.token==''and m.updateAuthToken=='','Actual Forget requests credential removal without returning or resending the old token')
 authSaved=false;reply(auth,{state='idle',authenticated=false});check(not controls['Forget GitHub access']and not m.updateState.authenticated,'Forget acknowledgement removes saved-access availability from the actual About page')
 enterAccess(secret);click(visible('Save GitHub access'));authSaved=true;reply(latest('/updates/auth'),{state='idle',authenticated=true})
 check(m.updateAuthToken==''and not json.encode(m.updateState):find(secret,1,true),'Saving access again after Forget does not revive cached plaintext')
 phase='check';click(visible('Check for updates'));local request=assert(latest('/updates/check'))
 check(request.service=='catalog'and request.method=='POST'and m.updateBusy and#quits==0,'Actual Check for updates click starts one controlled update request')
 reply(request,{state='checking'});check(m.updateState.state=='checking'and controls['Checking for updates…'].disabled,'The checking acknowledgement displays disabled checking state')
 local before=count('/updates/check');click(visible('Checking for updates…'));check(count('/updates/check')==before,'Disabled checking control cannot start duplicate requests')
 reply(pending('/updates/status'),{state='available',candidate=copy(candidate),channel='development'})
 check(controls['Download complete update']and m.updateState.candidate.id==candidate.id,'Available response exposes the complete-package Download control');shot('update-available')
 phase='download';click(visible('Download complete update'));request=latest('/updates/download')
 check(request.body.candidateId==candidate.id and not request.body.path and not request.body.url and not request.body.command,'Download click sends only the verified opaque candidate identity')
 reply(request,{state='downloading',candidate=copy(candidate),progress={downloadedBytes=0,totalBytes=20971520}})
 reply(pending('/updates/status'),{state='downloading',candidate=copy(candidate),progress={downloadedBytes=5242880,totalBytes=20971520}})
 check(texts['Downloading · 5.0 / 20.0 MiB']and#quits==0,'Actual About displays polled byte progress while keeping the application open');shot('update-progress')
 reply(pending('/updates/status'),{state='ready',candidate=copy(candidate),method='appimage'})
 local install='Close, install and restart';check(controls[install]and not controls[install].disabled,'Verified ready response exposes installation while idle');shot('update-ready')
 m.settings.resolution='1120x720';p:apply(true);wait(.2);local compact=visible(install);local w,h=Layout.dimensions()
 check(compact.x>=0 and compact.y>=0 and compact.x+compact.w<=w and compact.y+compact.h<=h,'Real installation control remains reachable in the minimum 1120×720 window');shot('update-ready-minimum')
 compact=visible(accessInput,'input');check(compact.isPassword and compact.x>=0 and compact.y>=0 and compact.x+compact.w<=w and compact.y+compact.h<=h,'Masked GitHub access remains reachable in the minimum About form')
 compact=visible('Save GitHub access');check(compact.disabled and inView(compact),'Explicit empty Save remains reachable and disabled in the minimum About form')
 compact=visible('Forget GitHub access');check(not compact.disabled and inView(compact),'Explicit Forget remains reachable for saved access in the minimum About form')
 m.game={running=true,players={}};wait(.15);check(controls[install].disabled,'A running local game disables the real installation button')
 before=count('/updates/apply');click(visible(install));check(count('/updates/apply')==before,'Disabled in-game installation cannot send an apply request')
 m.liveGame=m.game;m.replay={id='read-only-fixture'};m.game={running=false,players={}};wait(.13);check(controls[install].disabled,'A live match behind replay also disables the real installation button')
 m.liveGame=nil;m.replay=nil;m.game=nil;m.roomConnectionId='controlled-room';wait(.13);check(controls[install].disabled,'A room membership keeps installation disabled between native games')
 m.roomConnectionId=nil;m.updateState.method='flatpak';wait(.13);check(controls['Close and open system installer'],'Flatpak ready state clearly selects the system installer handoff')
 m.updateState.method='appimage';wait(.13);phase='apply_pending';click(visible(install));request=latest('/updates/apply')
 check(m.updateApplying and m.updateBusy and v.inputLock=='update-install-pending'and r:inputBlocked()and#quits==0,'Delayed Apply acknowledgement opens the real modal and blocks background renderer input')
 check(not texts['Finish the current game and leave your room before installing.'],'An idle pending installation does not invent an active-game warning')
 click(controls.Close);check(m.page=='settings'and m.updateApplying and#quits==0,'Pending installer modal blocks the underlying Settings Close button')
 local nav=require('app.navigation').layout(Layout.dimensions(),m.page,m.game~=nil).pages[3]
 r:mousepressed(nav.x+nav.w/2,nav.y+nav.h/2,1,1);check(m.page=='settings'and m.updateApplying,'Pending installer modal blocks actual background navigation hits');shot('update-apply-pending')
 phase='apply_error';reply(request,{error='Controlled installer handoff failed'},503)
 check(m.updateApplying and v.inputLock=='update-install-pending'and#quits==0,'An uncertain installer acknowledgement retains the real modal until one status reconciliation')
 reply(pending('/updates/status'),{state='error',candidate=copy(candidate),error='Controlled installer handoff failed'})
 check(not m.updateApplying and not m.updateBusy and m.updateState.state=='error'and#quits==0 and v.inputLock~='update-install-pending','A handoff error releases the modal and keeps the application open')
 check(texts['Controlled installer handoff failed'],'The actual About form preserves the installer error for review');shot('update-handoff-error')
 click(visible('Check for updates'));reply(latest('/updates/check'),{state='ready',candidate=copy(candidate),method='appimage'})
 phase='second_apply_pending';click(visible(install));request=latest('/updates/apply');check(#quits==0,'Retrying installation still waits for its own service acknowledgement')
 local approvedPosts=count('/updates/apply');reply(request,nil);check(m.updateApplying and#quits==0 and count('/updates/apply')==approvedPosts,'A lost Apply reply uses one read while retaining the modal and never resubmits installation')
 phase='apply_requested_ack';reply(pending('/updates/status'),{state='apply_requested',candidate=copy(candidate),path='/tmp/never-execute',command='do-not-run'})
 check(#quits==1 and quits[1].phase=='apply_requested_ack'and quits[1].code==0 and m.updateQuitting,'Only acknowledged apply_requested queues the production graceful quit event')
 check(#external==0,'Candidate and acknowledgement paths never reach browser, filesystem execution or a shell')
 phase='source';assert(os.rename(manifest..'/build-info.json',manifest..'/build-info-isolated.json'));v.aboutState=nil;m.updateState=nil;m.updateQuitting=nil;wait(.2)
 check(not v.aboutState.info.packaged and not controls['Check for updates']and not controls[install]and not controls['Download complete update']and not inputs[accessInput]and not controls['Save GitHub access']and not controls['Forget GitHub access'],'Actual source-build fallback exposes no credential/check/download/install controls')
 check(inView(visible('Use an installed release for in-app updates. Source checkouts keep their repository workflow.',true)),'The source-build explanation remains reachable in the actual minimum About form')
 before=#ledger;wait(.7);check(#ledger==before and#quits==1,'Source-build About performs no automatic update request or additional execution');shot('update-source-build')
 local calls={};for _,call in ipairs(ledger)do if call.path:find('^/updates/')then calls[#calls+1]={service=call.service,method=call.method,path=call.path,body=publicBody(call.body),answered=call.answered}end end
 local report={passed=true,checks=checks,captures=shots,quitRequests=quits,externalActions=external,requests=calls,renderer={love.graphics.getRendererInfo()},physicalSize={love.graphics.getDimensions()},logicalSize={Layout.dimensions()},scope='Actual LÖVE/Slab About controls at 1440×900 and minimum 1120×720, plus modal/background input using production model/view/renderer with delayed controlled loopback replies. Packaged manifest and game/room states are explicit fixtures. No remote release, real download, installer, process exit handoff or user store access.'}
 local f=assert(io.open(output..'/report.json','w'));f:write(json.encode(report));f:close();realQuit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);realQuit=love.event.quit
 love.event.quit=function(code)quits[#quits+1]={code=code,phase=phase}end
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down end
 love.keyboard.isDown=function(...)for i=1,select('#',...)do if keys[select(i,...)]then return true end end;return false end
 love.keyboard.isScancodeDown=love.keyboard.isDown
 love.system.openURL=function(value)external[#external+1]=value;error('Unexpected updater URL/path execution')end
 m=Model.new();m.profile={};m.uiLayout={};m.settings.skybox='Off';m.settings.resolution='1440x900';m.settings.windowMode='Windowed';m.settings.musicEnabled=false;m.settings.sfxEnabled=false;m.settings.vsync=false
 m.saveSettings=function()error('Updater GUI must not save or replace user preferences')end
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p:apply(true);p.appliedLoaded=true;m:openSettings()
 os.execute=function(value)external[#external+1]={kind='shell',value=value};error('Unexpected updater shell command')end
 io.popen=function(value)external[#external+1]={kind='pipe',value=value};error('Unexpected updater shell pipe')end
 local button=S.Button;S.Button=function(label,options)local result=button(label,options);controls[label]=bounds();controls[label].disabled=options and options.Disabled;return result end
 local input=S.Input;S.Input=function(label,options)local result=input(label,options);inputs[label]=bounds();inputs[label].isPassword=options and options.IsPassword;inputs[label].text=options and options.Text;inputs[label].readOnly=options and options.ReadOnly;return result end
 for _,name in ipairs({'Text','Textf'})do local original=S[name];S[name]=function(value,options)local result=original(value,options);texts[value]=bounds();return result end end
 local begin=S.BeginListBox;S.BeginListBox=function(id,options)local x,y=S.GetCursorPos({Absolute=true});local dx,dy=Region.Transform(nil,0,0);local result=begin(id,options);regions[id]={x=x+dx,y=y+dy,w=options.W,h=options.H};return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<55,'Updater GUI acceptance timed out');S.Update(dt);r:update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,message=coroutine.resume(runner);assert(ok,message)end
 controls={};texts={};regions={};inputs={};v:build();r.uiHovered=not S.IsVoidHovered()
end
function love.draw()
 love.graphics.push();love.graphics.scale(Layout.scale);r:draw();love.graphics.pop();S.Draw({DeferOverlays=true})
 love.graphics.push();love.graphics.scale(Layout.scale);r:drawForeground();love.graphics.pop();S.DrawOverlays()
 if capture then local name=capture;capture=nil;love.graphics.captureScreenshot(function(data)local f=assert(io.open(output..'/'..name..'.png','wb'));f:write(data:encode('png'):getString());f:close();data:release()end)end
end
function love.quit()if p then p:quit()end;S.OnQuit()end
function love.errorhandler(message)local problem=debug.traceback(tostring(message),2);io.stderr:write(problem..'\n');local f=io.open(output..'/failure.txt','w');if f then f:write(problem);f:close()end;return function()return 1 end end
