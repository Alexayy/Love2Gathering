-- Real land-choice hover, fallback card rendering, fonts and inline mana.
-- The native-style rules/choice are presentation fixtures, not engine outcomes.
local S=require('lib.Slab');local Renderer=require('app.renderer');local View=require('app.view');local Choices=require('app.card_choices');local Rich=require('app.richtext');local Text=require('app.utf8_text');local Preferences=require('app.preferences');local Layout=require('app.layout');local utf8=require('utf8');local json=require('lib.json')
local root=assert(os.getenv('LOVE2GATHERING_PREVIEW_UTF8_OUTPUT'))
local checks,captures,shots={},{},{};local m,r,v,p,runner;local clock,wake=0,0;local mouse={x=2,y=2}
local validRules='Landfall — Whenever a land you control enters, you may put a quest counter on this enchantment.\nRemove three quest counters from this enchantment and sacrifice it: Search your library for up to two basic land cards, put them onto the battlefield tapped, then shuffle.'
local edge=string.rep('a',96)..'— Add {G}. Čarobna šuma.'
local offered={id='offered-forest',choiceId='native-forest-choice',responseType='uuid',name='Forest',type='Basic Land — Forest',manaCost='',rules={'({T}: Add {G}.)',edge},oracle_text=edge,colors={'G'}}
local prompt={id='khalni-land-choice',type='pick_target',message='Khalni Heart Expedition: choose up to two basic land cards',choices={},cardPanel={kind='select',interactionId='khalni-fixture',cards={offered},doneChoice={id='done-native',label='Done',responseType='boolean',value=false}}}
local function check(value,label)assert(value,label);checks[#checks+1]=label;print('PREVIEW UTF8 PASS '..label);io.stdout:flush()end
local function wait(seconds)wake=clock+(seconds or .07);coroutine.yield()end
local function ready(fn,label)for _=1,150 do if fn()then return end;wait(.03)end;error('Timed out: '..label)end
local function shot(name)shots[#shots+1]=name;wait(.1)end
local function scenario()
 wait(.1);ready(function()return v.cardChoiceHits and v.cardChoiceHits[1]end,'native-style offered land tile')
 local hit=v.cardChoiceHits[1];mouse.x,mouse.y=hit.x+hit.w/2,hit.y+hit.h/2;S.OnMouseMoved(mouse.x,mouse.y,0,0);wait(.12)
 -- This deliberately reaches the unmodified preview path before checking the
 -- repair helper, so a baseline run reproduces Font:getWidth's real failure.
 ready(function()return m.choiceHover and m.choiceHover.card==offered end,'real offered-land hover')
 r:drawPreview(Layout.dimensions())
 check(true,'The real offered-land hover reaches fallback drawPreview without an invalid UTF-8 crash')
 check(utf8.len(edge)and not utf8.len(edge:sub(1,97)),'The valid native-style rule demonstrably crosses the old 97-byte slice inside an em dash')
 check(offered.oracle_text==edge and offered.rules[2]==edge and offered.id=='offered-forest','Rendering preserves the original native card identity and rule text')
 shot('land-choice-preview')

 local unicode={'—','’','é','Č','🌳'}
 for _,symbol in ipairs(unicode)do for part=1,#symbol-1 do
  local text=string.rep('x',97-part)..symbol..' {T}: Add {G}. '..string.rep('šuma ',12)
  local card={id='probe',name='Čarobna šuma',type='Basic Land — Forest',rules={text},colors={'G'}}
  m.choiceHover={card=card};r:drawPreview(Layout.dimensions())
  local layout=Rich.layout(r,text,230,{size=10,maxLines=3});for _,run in ipairs(layout.runs)do if run.text then assert(utf8.len(run.text))end end
 end end
 check(true,'Every interior byte position of two-, three- and four-byte characters is safe at the former preview boundary')
 local khalni={id='khalni-source',name='Khalni Heart Expedition',type='Enchantment',manaCost='{1}{G}',rules={validRules},colors={'G'}}
 m.choiceHover={card=khalni};r:drawPreview(Layout.dimensions());check(true,'The actual catalog Khalni oracle text also renders through the fallback preview')
 local good='Čarobna šuma — café 🌳 {T}: Add {G}.\n{G/U/P} and {2/U}; unknown {quest}.'
 check(Text.clean(good)==good,'Valid UTF-8, inline mana and unknown braces are retained byte-for-byte')
 local tokens=Rich.tokens(good);local symbols={};for _,token in ipairs(tokens)do if token.kind=='mana'then symbols[#symbols+1]=token.symbol end end
 check(table.concat(symbols,',')=='T,G,G/U/P,2/U','Mana parsing preserves tap, normal, hybrid and Phyrexian symbols')
 for _,bad in ipairs({'before\226\128','before\195 after','\128\129after','\192\175','\237\160\128','\244\144\128\128','\255after'})do
  local cleaned=Text.clean(bad);assert(utf8.len(cleaned));assert(cleaned:find(utf8.char(0xFFFD),1,true));local layout=Rich.layout(r,bad..' {G}',240,{size=14});for _,run in ipairs(layout.runs)do if run.text then assert(utf8.len(run.text))end end
  r:text(bad,8,8,14,r.colors.text);r:strong(bad,8,30,14,r.colors.text);assert(utf8.len(r:fit(bad,120,14,2)))
 end
 check(true,'Malformed external fragments are repaired before font measurement while valid adjacent text remains renderable')
 check(Text.clean('é\255🌳')=='é'..utf8.char(0xFFFD)..'🌳','Repair preserves valid multibyte text on both sides of a damaged byte')
 local long=Rich.layout(r,string.rep('Žeželj{G} ',80),200,{size=14,maxLines=3})
 check(long.lines==3 and long.truncated and long.runs[#long.runs].text=='…','The existing line bound truncates safely at text/mana run boundaries')
 local card={name='Forest',type='Basic Land — Forest',rules={good},colors={'G'}};m.choiceHover={card=card};offered.oracle_text=good;offered.rules={good};shot('mana-and-unicode-preview')
 local output=assert(io.open(root..'/report.json','w'));output:write(json.encode({checks=checks,captures=captures,scope='Actual LÖVE fonts, Slab native-card choice hover and Renderer.drawPreview/inline mana. Offered cards and damage-free native rules are presentation fixtures; actual Khalni oracle read from supplied catalog. No user storage, network, game actions or engine modifications.'}));output:close();love.event.quit(0)
end
function love.load()
 S.SetINIStatePath(nil);S.Initialize({},true);love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function()return false end
 m={settings=json.decode(json.encode(Preferences.defaults)),page='table',game={gameId='utf8-fixture',players={}},uiLayout={},toasts={}}
 m.settings.windowMode='Windowed';m.settings.resolution='1440x900';m.settings.skybox='Off';m.settings.vsync=false;m.settings.sfxEnabled=false;m.settings.musicEnabled=false
 function m:cardData(card)return card end;function m:getArt()return nil end;function m:canSelect()return false end;function m:answerChoice()error('A hover must not answer a native choice')end
 r=Renderer.new(m);v=View.new(S,m,r);p=Preferences.new(m,S,r);v.preferences=p;p:apply(true);p.appliedLoaded=true
 runner=coroutine.create(scenario)
end
function love.update(dt)
 clock=clock+dt;assert(clock<30,'UTF-8 preview acceptance timed out');S.Update(dt)
 if clock>=wake and coroutine.status(runner)~='dead'then local ok,problem=coroutine.resume(runner);assert(ok,problem)end
 local w,h=Layout.dimensions();Choices.build(v,w,h,prompt)
end
function love.draw()
 love.graphics.clear(.025,.035,.06,1);S.Draw();r:drawPreview(Layout.dimensions())
 if#shots>0 then local path=root..'/'..table.remove(shots,1)..'.png';captures[#captures+1]=path;love.graphics.captureScreenshot(function(data)local f=assert(io.open(path,'wb'));f:write(data:encode('png'):getString());f:close()end)end
end
function love.quit()if p then p:quit()end;S.OnQuit()end
function love.errorhandler(message)local problem=debug.traceback(tostring(message),2);print(problem);local file=assert(io.open(root..'/failure.txt','w'));file:write(problem);file:close();return function()return 1 end end
