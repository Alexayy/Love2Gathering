local Fonts=require('app.fonts');local Assets=require('app.assets');local Preferences=require('app.preferences');local S=require('lib.Slab')
local checks=0;local r,m,p
local function check(ok,text)assert(ok,text);checks=checks+1;print('FONTS PASS '..text)end
function love.errorhandler(message)io.stderr:write('FONTS FAILED '..tostring(message)..'\n'..debug.traceback()..'\n');return function()return 1 end end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({'nocursor'},true)
 check(Fonts.default=='Beleren'and Fonts.names()[1]=='Beleren','Beleren is the single application typeface')
 check(Fonts.available()==Fonts.available()and#Fonts.available()==1,'The public font catalog is stable and bounded')
 local fonts,bold,problem,effective=Fonts.createSet('Legacy system preference',{12,14,16,18,22,28})
 check(not problem and effective=='Beleren','Legacy font preferences cannot replace the requested Beleren typeface')
 for _,size in ipairs({12,14,16,18,22,28})do check(fonts[size]==Fonts.font(size),'Body font uses actual cached Beleren at size '..size)end
 check(fonts[16]:hasGlyphs('Čarobna šuma, Љубав 0123456789 →'),'Supplied face and UTF-8 fallback retain Serbian and interface characters')
 check(bold==Fonts.title(22)and bold==fonts[22],'Body, headings and card names use the same actual face')
 r={fonts=fonts,bold=bold,assets=Assets.new()};m={settings={fontFamily='Old custom family',titleFontFamily='Application font'},toast=function()end};p=Preferences.new(m,S,r);p:applyFont()
 check(m.settings.fontFamily=='Beleren'and m.settings.titleFontFamily=='Beleren'and S.GetStyle().Font==fonts[16],'Applying preferences forces all interface text to Beleren')
 local mana=r.assets:font(24);check(mana~=Fonts.font(24)and mana:hasGlyphs(require('utf8').char(58880)),'Mana symbols retain their separate supplied font')
 local body=Fonts.font(18);S.GetStyle().Font=body;S.PushFont(Fonts.font(28));S.PushFont(Fonts.font(22));S.PopFont();S.PopFont()
 check(S.GetStyle().Font==body,'Nested header font push/pop restores the current application base')
 S.GetStyle().Font=Fonts.font(16);S.PushFont(Fonts.font(22));S.PopFont();check(S.GetStyle().Font==Fonts.font(16),'Changing the base after initialization never restores a stale font')
 local info=love.filesystem.getInfo;Fonts.clearCache();love.filesystem.getInfo=function(path,...)if path=='assets/fonts/Beleren2016-Bold.ttf'then return nil end;return info(path,...)end
 local fallback,family=Fonts.font(23);love.filesystem.getInfo=info;Fonts.clearCache();check(family=='Built-in DejaVu Sans'and fallback:hasGlyphs('Čarobna'),'Missing display files use the bundled readable fallback safely')
 print('FONTS COMPLETE '..checks..' checks');love.event.quit(0)
end
function love.quit()S.OnQuit()end
