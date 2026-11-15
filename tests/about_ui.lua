-- Real Slab input/scroll, supplied fonts/icons and offline notices. Build
-- provenance and the background match are explicit fixtures, never live data.
local S=require('lib.Slab');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Preferences=require('app.preferences');local Layout=require('app.layout');local Build=require('app.build_info');local About=require('app.about');local json=require('lib.json')
local output=assert(os.getenv('LOVE2GATHERING_ABOUT_OUTPUT'))
local m,r,v,p,runner,Region,Cursor;local clock,wake=0,0;local mouse={x=2,y=2};local down=false
local controls,texts,regions,ids={},{},{},{};local checks,captures,shots,opened,modes={},{},{},{},{}
local originalClipboard,originalOpenURL;local settingsBefore
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('ABOUT UI PASS '..label)end
local function itemId(name)
 for index,section in ipairs(require('app.credits').sections)do for number,item in ipairs(section.items or{})do if item.name==name then return'about-item-'..index..'-'..number end end end
 error('Missing attributed component: '..name)
end
local function itemButton(name,suffix,label)return itemId(name)..'-'..suffix..'/'..label end
local function wait(seconds)wake=clock+(seconds or .08);coroutine.yield()end
local function move(box)
 local oldX,oldY=mouse.x,mouse.y;mouse.x=(box.x+box.w/2)*Layout.scale;mouse.y=(box.y+box.h/2)*Layout.scale
 S.OnMouseMoved(mouse.x,mouse.y,mouse.x-oldX,mouse.y-oldY)
end
local function click(box)
 assert(box,'Missing actual Slab button');move(box);wait(.06);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);wait(.06);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);wait(.14)
end
local function shot(name)shots[#shots+1]=name;wait(.12)end
local function bounds()
 local dx,dy=Region.Transform(nil,0,0);local x,y,w,h=Cursor.GetItemBounds();return{x=x+dx,y=y+dy,w=w,h=h}
end
local function inView(box)
 local region=regions['settings-about-content'];return box and region and box.y>=region.y and box.y+box.h<=region.y+region.h
end
local function visible(id)
 for _=1,70 do
  local box=controls[id];if inView(box)then return box end
  local region=assert(regions['settings-about-content']);move({x=region.x+region.w*.8,y=region.y+region.h*.5,w=1,h=1});wait(.03)
  S.OnWheelMoved(0,box and box.y<region.y and 7 or-7);wait(.06)
 end
 error('About control failed to scroll into view: '..id)
end
local function top()
 local region=assert(regions['settings-about-content']);move({x=region.x+region.w*.8,y=region.y+region.h*.5,w=1,h=1});wait(.04);S.OnWheelMoved(0,500);wait(.15)
end
local function mode(width,height,scale)
 m.settings.resolution=width..'x'..height;m.settings.uiScale=scale;p:apply(true);wait(.18)
 modes[#modes+1]={physical={love.graphics.getDimensions()},logical={Layout.dimensions()},scale=Layout.scale}
end
local function tabBounds(label)
 local w,h=Layout.dimensions();local last
 for _,id in ipairs({'Game','Graphics','Presentation','Audio','Accessibility','Storage','About'})do
  local b=assert(controls[id],id);check(b.x>=0 and b.y>=0 and b.x+b.w<=w and b.y+b.h<=h,label..' keeps '..id..' inside the logical viewport')
  assert(not last or b.x>=last.x+last.w,'Settings tabs overlap');last=b
 end
 for _,id in ipairs({'Apply and save','Close'})do local b=assert(controls[id]);assert(b.y+b.h<=h,label..' footer remains visible')end
end
local function scenario()
 wait(.2);check(m.page=='settings'and not m.settingsOpen,'Production settings routing opens a page outside a match')
 click(controls.About);check(v.settingsTab=='About','Actual About tab click selects the seventh settings page')
 tabBounds('Full page');check(v.aboutState.info.version=='2026.11.16.42'and v.aboutState.info.channel=='development'and v.aboutState.info.revision==string.rep('a',40),'The actual packaged VFS manifest displays its version, channel and full source revision')
 shot('about-page-build')
 click(visible('about-copy-build/Copy build details'));check(love.system.getClipboardText():find('Version: 2026.11.16.42',1,true)and love.system.getClipboardText():find('XMage revision: d9b266fc981024873ac7ec5f90ee7121a060725e',1,true),'Copy build details uses the displayed actual manifest fields')
 click(visible('about-project-link-1/Project repository'));check(#opened==1 and opened[1]=='https://github.com/Alexayy/Love2Gathering','A real About link click reaches only the fixed project browser target')
 click(visible(itemButton('Love2Gathering contributors','notice','Read license notice')));check(v.aboutState.openNotice==itemId('Love2Gathering contributors')and v.aboutState.notices.LICENSE.text:find('MIT License',1,true),'A real notice button opens the included project MIT text offline')
 shot('about-project-license');click(visible(itemButton('Love2Gathering contributors','notice','Hide license notice')));check(not v.aboutState.openNotice,'The inline offline notice closes without leaving About')
 visible(itemButton('Beleren2016 Bold','link-1','Beleren design credit'));check(texts['Beleren2016 Bold']and texts['License · Locally supplied; redistribution grant not recorded'],'Beleren credit retains the explicit unverified redistribution status')
 shot('about-font-rights')
 visible(itemButton('Classic Magic / Mystic Eye','notice','Read license notice'));check(texts['Owner-supplied card backs']and texts['License · Rights not verified'],'Owner-supplied backs are attributed separately from licensed Kenney assets');shot('about-card-back-rights')
 visible(itemButton('Complete credits and notices','notice','Read license notice'));check(texts['Usage rights and contact'],'Credits remain reachable through the scrolling About form');shot('about-credits-bottom')
 click(visible(itemButton('Complete credits and notices','notice','Read license notice')));check(v.aboutState.notices['CREDITS.md'].text:len()>100,'The complete packaged credit document is readable offline');shot('about-complete-credits')
 for _,section in ipairs(require('app.credits').sections)do for _,item in ipairs(section.items or{})do if item.licensePath then local content,problem=About.readLicense(item.licensePath);check(content and#content>0,'Included offline credit notice: '..item.name..(problem and' '..problem or''))end end end
 top();click(controls.Game);check(v.settingsTab=='Game','Returning to another settings tab clears the About scroll focus');click(controls.About);wait(.1)
 check(json.encode(m.settings)==settingsBefore,'Browsing credits and notices leaves saved preferences untouched')
 click(controls.Close);check(m.page=='decks'and not m.settingsOpen,'The About page Close button returns to the original client page')

 mode(1120,720,1);m:openSettings();wait(.15);click(controls.About);top();tabBounds('Minimum page');shot('about-page-1120')
 click(controls.Close);m.page='table';m.game={gameId='synthetic-about-background',players={}};local game=m.game;m:openSettings();wait(.2)
 check(m.page=='table'and m.settingsOpen,'Production settings routing opens a popup over an existing match')
 click(controls.About);top();tabBounds('Minimum in-game popup');check(m.game==game,'Opening About keeps the background match identity');shot('about-popup-1120')
 click(visible(itemButton('XMage — Magic Another Game Engine','notice','Read license notice')));check(v.aboutState.openNotice==itemId('XMage — Magic Another Game Engine'),'The in-game About popup also opens local engine attribution');shot('about-popup-license')
 click(visible(itemButton('Roboto · Google','notice','Read license notice')));check(v.aboutState.notices['licenses/Apache-2.0.txt'].text:len()>10000,'The minimum-height popup opens the complete long Apache notice offline')
 local noticeEnd=visible(itemButton('Roboto · Google','link-1','Legacy Roboto source'));check(inView(noticeEnd),'The end of a long inline license remains scrollable inside the minimum-height popup');shot('about-popup-long-license-end')
 local policy=visible(itemButton('Wizards of the Coast','link-1','Fan Content Policy'));check(inView(policy),'The final usage-rights policy remains reachable in the minimum-height in-game popup');shot('about-popup-final-policy')
 local last=visible(itemButton('Complete credits and notices','link-1','Project maintainer'));check(inView(last),'The last credit/contact control remains reachable below all expanded license text');shot('about-popup-bottom')
 click(controls.Close);check(not m.settingsOpen and m.page=='table'and m.game==game,'Closing About returns to the same background match')

 mode(1440,900,1.25);m:openSettings();wait(.2);click(controls.About);top();tabBounds('Scaled in-game popup');check(Layout.scale==1.25,'Scaled popup verification uses actual UI scale 1.25');shot('about-popup-scaled')
 -- Read the actual source fallback through VFS/environment, not an injected
 -- Info.load return value. Only this isolated fixture manifest is renamed.
 assert(os.rename(output..'/build-info.json',output..'/build-info-fixture.json'));v.aboutState=nil;wait(.15);top()
 check(not v.aboutState.info.packaged and not v.aboutState.info.version and v.aboutState.info.revision=='724032c','With no embedded manifest, About reads the bounded launcher source revision and labels Source build')
 shot('about-source-build');click(controls.Close);check(m.game==game and not m.settingsOpen,'The scaled About close leaves the background match intact')
 local file=assert(io.open(output..'/report.json','w'));file:write(json.encode({checks=checks,captures=captures,modes=modes,browserTargets=opened,scope='Real LÖVE/Slab page and in-game popup input, scrolling, local credit documents and supplied fonts/icons. Build manifest and background match are explicit fixtures; browser calls intercepted; no live service/user settings/native game.'}));file:close();love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true)
 -- Native OS pointer callbacks are not installed; all test events enter Slab
 -- explicitly with the same scale conversion as the production callbacks.
 love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down end
 originalClipboard=love.system.getClipboardText();originalOpenURL=love.system.openURL;love.system.openURL=function(url)opened[#opened+1]=url;return true end
 m=setmetatable({settings=json.decode(json.encode(Preferences.defaults)),page='decks',profile={},uiLayout={},toasts={},art={},catalogHealth={},byName={},lookupPending={}},Model)
 m.settings.skybox='Off';m.settings.resolution='1440x900';m.settings.windowMode='Windowed';m.settings.musicEnabled=false;m.settings.sfxEnabled=false;m.settings.vsync=false
 m.api={request=function()error('About must not contact services')end};m.saveSettings=function()error('About must not save preferences')end
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p:apply(true);p.appliedLoaded=true;settingsBefore=json.encode(m.settings);m:openSettings()
 Region=require('lib.Slab.Internal.UI.Region');Cursor=require('lib.Slab.Internal.Core.Cursor')
 local push,pop=S.PushID,S.PopID;S.PushID=function(id)ids[#ids+1]=id;return push(id)end;S.PopID=function()ids[#ids]=nil;return pop()end
 local button=S.Button;S.Button=function(id,options)local value=button(id,options);controls[(#ids>0 and table.concat(ids,'/')..'/'or'')..id]=bounds();return value end
 for _,name in ipairs({'Text','Textf'})do local original=S[name];S[name]=function(value,options)local result=original(value,options);texts[value]=bounds();return result end end
 local begin=S.BeginListBox;S.BeginListBox=function(id,options)local x,y=S.GetCursorPos({Absolute=true});local dx,dy=Region.Transform(nil,0,0);local result=begin(id,options);regions[id]={x=x+dx,y=y+dy,w=options.W,h=options.H};return result end
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<70,'About GUI acceptance timed out');S.Update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,problem=coroutine.resume(runner);if not ok then local file=assert(io.open(output..'/failure.txt','w'));file:write(problem);file:close();print(problem);love.event.quit(1);return end end
 controls={};texts={};regions={};if m.page=='settings'or m.settingsOpen then v:settings(Layout.dimensions())end
end
function love.draw()
 love.graphics.clear(.025,.035,.06,1);S.Draw()
 if#shots>0 then local path=output..'/'..table.remove(shots,1)..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local file=assert(io.open(path,'wb'));file:write(data:encode('png'):getString());file:close()end)end
end
function love.quit()if originalClipboard then love.system.setClipboardText(originalClipboard)end;if originalOpenURL then love.system.openURL=originalOpenURL end;if p then p:quit()end;S.OnQuit()end
function love.errorhandler(message)
 local problem=debug.traceback(tostring(message),2);print(problem);local file=assert(io.open(output..'/failure.txt','w'));file:write(problem);file:close()
 if originalClipboard then love.system.setClipboardText(originalClipboard)end
 return function()return 1 end
end
