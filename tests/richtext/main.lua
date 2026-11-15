function love.errorhandler(message)io.stderr:write('RICHTEXT FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
local S=require('lib.Slab');local Assets=require('app.assets');local Rich=require('app.richtext');local Layout=require('app.layout');local utf8=require('utf8')
local r,v,frame,checks,shot
local function check(value,label)assert(value,label);checks=checks+1;print('RICHTEXT PASS '..label)end
local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
local example='Pay {X}{W}{U}{B}{R}{G}{C}, then tap {T} or untap {Q}.\nHybrid: {2/U}, {B/P}, {G/U/P}. Mana {100}, snow {S}, energy {E}, chaos {CHAOS}.\n\nČarobna šuma — words and mana symbols wrap together. This card costs {2}{U}{U} to cast.'
function love.load()
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);checks=0;frame=0
    r={assets=Assets.new(),fonts={},colors={text={.90,.94,.98,1}}};for _,size in ipairs({14,16,18,20,24,32})do r.fonts[size]=love.graphics.newFont('assets/fonts/DejaVuSans.ttf',size)end;v={S=S,r=r}
    local style=S.GetStyle();style.Font=r.fonts[16];style.TextColor=r.colors.text;style.WindowBackgroundColor={.045,.065,.09,1}
    local ts=Rich.tokens('{unknown}{W} {2/U}{B/P}{G/U/P}');local n=0;for _,t in ipairs(ts)do if t.kind=='mana'then n=n+1 end end
    check(n==4 and ts[1].text=='{unknown}','Known tokens recognized; unknown braces preserved')
    local layout=Rich.layout(r,example,310,{size=16});check(layout.lines>=6,'Words, explicit newlines and empty line wrap')
    for _,run in ipairs(layout.runs)do assert(run.x>=0 and run.x+run.w<=310.01);if run.text then assert(utf8.len(run.text))end end
    check(true,'All wrapped runs remain within bounds and valid UTF-8')
    local long='ŽeželjČarobnoDrvoŠumadija';local joined='';local narrow=Rich.layout(r,long,45,{size=16});for _,run in ipairs(narrow.runs)do joined=joined..(run.text or '')end
    check(joined==long and narrow.lines>1,'Long UTF-8 words split without corrupting text')
    local clipped=Rich.layout(r,example,100,{size=16,maxLines=2});check(clipped.lines==2 and clipped.truncated and clipped.runs[#clipped.runs].text=='…','Maximum lines truncate at safe run boundaries')
    check(Rich.layout(r,'',100,{size=16}).height==0,'Empty rich text has no extra height')
    local a,h=Rich.canvas(r,example,310,{size=16});local b=Rich.canvas(r,example,310,{size=16});check(a==b,'Identical rich text reuses cached native canvas')
    Layout.setScale(1.25);local c,ch=Rich.canvas(r,example,310,{size=16});local density=Assets.uiRasterScale()
    check(c~=a and c:getWidth()==math.ceil(310*density) and c:getHeight()==math.ceil(ch*density),'Canvas rasterization follows display, UI scale and text quality')
    Layout.renderScale=.5;local d=Rich.canvas(r,example,310,{size=16});check(d==c,'Table render scale does not reduce Slab text resolution');Layout.renderScale=1;Layout.setScale(1)
    local icon=r.assets:iconImage('library',24);check(icon==r.assets:iconImage('library',24),'Icon images are cached')
    local defaultMana=r.assets:iconImage('W',24);local tintedMana=r.assets:iconImage('W',24,{.86,.92,.98,1});check(defaultMana~=tintedMana,'Mana cache distinguishes automatic and explicit glyph tints')
    local oldMin,oldMag,oldAnisotropy=love.graphics.getDefaultFilter();love.graphics.setDefaultFilter('nearest','nearest')
    r.assets:setSettings({fontQuality='Standard'});local standardMana=r.assets:font(24);local standardWidth=standardMana:getWidth(utf8.char(require('assets.keyrune.glyphs').w))
    r.assets:setSettings({fontQuality='High'});local sharpMana=r.assets:font(24)
    local minFilter,magFilter=sharpMana:getFilter()
    check(minFilter=='linear'and magFilter=='linear','Mana glyphs stay antialiased when card texture filtering is nearest')
    check(sharpMana:getDPIScale()>=standardMana:getDPIScale()*1.9 and math.abs(sharpMana:getWidth(utf8.char(require('assets.keyrune.glyphs').w))-standardWidth)<=1,'High quality doubles the real Mana glyph atlas while keeping logical advances')
    local sharpIcon=r.assets:iconImage('W',24)
    check(sharpIcon:getWidth()==math.ceil(24*Assets.uiRasterScale(r.assets.settings)),'Mana icon images retain the high-density raster instead of enlarging a small bitmap')
    love.graphics.setDefaultFilter(oldMin,oldMag,oldAnisotropy)
    for _,name in ipairs({'library','graveyard','exile','commander','hand','creature','instant','sorcery','artifact','enchantment','planeswalker','land','battle','token','saga'})do local cp=require('assets.keyrune.glyphs')[name];assert(cp and r.assets:font(24):hasGlyphs(utf8.char(cp)))end
    check(true,'All named Magic zone and type icons use actual font glyphs')
    local beforeFont=love.graphics.getFont();love.graphics.push('all');love.graphics.translate(5,6);love.graphics.setScissor(10,11,40,41);love.graphics.setColor(.3,.4,.5,.7)
    Rich.canvas(r,'State restoration {R}',200,{size=18});local x,y=love.graphics.transformPoint(0,0);local sx,sy,sw,sh=love.graphics.getScissor();local rr,gg,bb,aa=love.graphics.getColor()
    check(x==5 and y==6 and sx==10 and sy==11 and sw==40 and sh==41 and math.abs(aa-.7)<.001 and love.graphics.getFont()==beforeFont and love.graphics.getCanvas()==nil,'Canvas rasterization restores transforms, clips, font, alpha and target');love.graphics.pop()
    local edge=Rich.canvas(r,'S',60,{size=32,color={1,1,1,1}}):newImageData();local found=false
    for iy=0,edge:getHeight()-1 do for ix=0,edge:getWidth()-1 do local rr,gg,bb,aa=edge:getPixel(ix,iy);if aa>.1 and aa<.9 then assert(rr>.85 and gg>.85 and bb>.85);found=true end end end
    check(found,'Antialiased canvas edges retain straight RGB for Slab alpha blending')
    local beforeResize=Rich.canvas(r,'Resize {W}',180,{size=16});local buttonBefore=r.assets:buttonImage('save','Save',98,34)
    assert(love.window.setMode(1120,720,{vsync=0}));local afterResize=Rich.canvas(r,'Resize {W}',180,{size=16});local buttonAfter=r.assets:buttonImage('save','Save',98,34)
    check(afterResize~=beforeResize and buttonAfter~=buttonBefore,'Display-size changes rebuild text and fixed-size button canvases')
    assert(love.window.setMode(1440,900,{vsync=0}));local returnResize=Rich.canvas(r,'Resize {W}',180,{size=16});check(returnResize~=beforeResize,'Returning to a previous resolution does not reuse cleared canvases')
    Assets.invalidateRasterCaches();local afterReset=Rich.canvas(r,'Resize {W}',180,{size=16});check(afterReset~=returnResize,'Same-size native mode resets have an explicit cache invalidation hook')
    Rich.clearCache();local oldLimit=Rich.cacheLimit;Rich.cacheLimit=3;for i=1,7 do Rich.canvas(r,'Cache '..i..' {W}',110,{size=16})end
    check(count(Rich.cache)<=3,'Rich text LRU entry limit is enforced');Rich.cacheLimit=oldLimit;Rich.clearCache()
    local oldIcons=r.assets.iconCacheLimit;r.assets.iconCacheLimit=3;for _,name in ipairs({'settings','save','replay','log','stack'})do r.assets:iconImage(name,24)end
    check(count(r.assets.iconCache)<=3,'Icon LRU entry limit is enforced');r.assets.iconCacheLimit=oldIcons
    r.assets.iconCache={};r.assets.iconPixelLimit=10000
    for _,name in ipairs({'W','U','B','R','G','C'})do r.assets:iconImage(name,24)end
    local pixels=0;for _,entry in pairs(r.assets.iconCache)do pixels=pixels+entry.image:getWidth()*entry.image:getHeight()end
    check(pixels<=r.assets.iconPixelLimit,'High-density icon cache also obeys a pixel budget');r.assets.iconPixelLimit=8*1024*1024
end
function love.update(dt)
    frame=frame+1
    if frame==15 then Layout.setScale(1.25);S.SetScale(Layout.scale)end
    S.Update(dt)
    S.BeginWindow('richtext',{X=30,Y=26,W=math.min(1000,select(1,Layout.dimensions())-60),H=640,Title='Mana icons and inline rich text',AllowMove=false,AllowResize=false,AutoSizeWindow=false})
    S.Text('Oracle text and mana costs use the supplied Mana font.')
    Rich.slab(v,'cost','{X}{W}{U}{B}{R}{G}{C}{T}{Q}',800,{size=24,lineHeight=34})
    S.Separator();Rich.slab(v,'oracle',example,760,{size=18,color=r.colors.text});S.NewLine()
    local x,y=S.GetCursorPos({Absolute=true});S.Text('Real zone/type glyphs and native toolbar vectors:')
    for i,name in ipairs({'library','hand','graveyard','exile','commander','creature','instant','sorcery','land','settings','save','home','log','stack','replay','concede','play','pause','previous','next','close'})do
        if i>1 and (i-1)%14~=0 then S.SameLine()end
        S.Image('icon-'..name,{Image=r.assets:iconImage(name,27),W=27,H=27,Tooltip=name})
    end
    S.NewLine();Rich.slab(v,'wrap','Narrow wrapping: Čarobna šuma {G}{G} and mana {2/U} then {T}: Draw a card.\nA separate line.',280,{size=18})
    S.EndWindow()
    if frame==10 or frame==20 then shot=frame==10 and 'native' or 'scaled' end
    if frame>23 then print('RICHTEXT COMPLETE '..checks..' checks');love.event.quit(0)end
end
function love.draw()
    love.graphics.clear(.025,.04,.065,1);S.Draw()
    if shot then local name=shot;shot=nil;love.graphics.captureScreenshot(function(data)local f=assert(io.open('/tmp/love2gathering-richtext-'..name..'.png','wb'));f:write(data:encode('png'):getString());f:close()end)end
end
function love.quit()S.OnQuit()end
