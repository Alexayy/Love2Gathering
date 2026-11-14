-- Discover installed Latin-capable fonts through Fontconfig. Saved preferences
-- contain a family name, never a file path or a command to execute.
local Fonts={default='Built-in DejaVu Sans',titleDefault='Beleren',limit=256,maxBytes=24*1024*1024}
local titleCache,titleClock={},0
local catalog
local function validFamily(value)
    return type(value)=='string' and #value>0 and #value<=160 and not value:find('[%z\1-\31\127]')
end
local function score(style)
    style=style:lower()
    local value=(style:find('italic',1,true) or style:find('oblique',1,true)) and 100 or 0
    if style:find('regular',1,true) or style:find('book',1,true) or style:find('roman',1,true) then return value end
    return value+(style:find('bold',1,true) and 20 or 10)
end
function Fonts.available()
    if catalog then return catalog end
    catalog={{name=Fonts.default}}
    if not io.popen then return catalog end
    local ok,pipe=pcall(io.popen,[[fc-list ':lang=en' --format='%{family[0]}\t%{style[0]}\t%{file}\n' 2>/dev/null]],'r')
    if not ok or not pipe then return catalog end
    local families={}
    for line in pipe:lines() do
        local family,style,path=line:match('^([^\t]+)\t([^\t]*)\t(.+)$')
        if validFamily(family) and family~=Fonts.default and path and path:sub(1,1)=='/' and #path<=4096 and path:lower():match('%.[ot]tf$') then
            local entry=families[family] or {name=family};families[family]=entry
            local priority=score(style)
            if not entry.priority or priority<entry.priority or (priority==entry.priority and path<entry.path) then entry.path,entry.priority=path,priority end
            if style:lower():find('bold',1,true) and priority<100 and (not entry.bold or path<entry.bold) then entry.bold=path end
        end
    end
    pipe:close()
    local names={};for name in pairs(families) do names[#names+1]=name end
    table.sort(names,function(a,b)return a:lower()<b:lower()end)
    for i=1,math.min(#names,Fonts.limit-1) do catalog[#catalog+1]=families[names[i]] end
    return catalog
end
function Fonts.names()
    local names={};for _,entry in ipairs(Fonts.available())do names[#names+1]=entry.name end
    return names
end
local function readFont(path)
    local file,message=io.open(path,'rb');if not file then error(message or 'Font file is unavailable') end
    local size=file:seek('end')
    if not size or size<1 or size>Fonts.maxBytes then file:close();error('Font file is outside supported bounds') end
    file:seek('set');local data=file:read('*a');file:close()
    if not data or #data~=size then error('Could not read the complete font') end
    return love.filesystem.newFileData(data,path:match('[^/]+$'))
end
local function makeSet(source,boldSource,sizes,custom)
    local result={}
    for _,size in ipairs(sizes) do
        local font=love.graphics.newFont(source,size)
        if custom then
            if not font:hasGlyphs('Aa0123456789') then error('Font does not contain interface letters') end
            font:setFallbacks(love.graphics.newFont('assets/fonts/DejaVuSans.ttf',size))
        end
        result[size]=font
    end
    local bold=love.graphics.newFont(boldSource,22)
    if custom then bold:setFallbacks(love.graphics.newFont('assets/fonts/DejaVuSans-Bold.ttf',22)) end
    return result,bold
end
function Fonts.createSet(family,sizes)
    family=family or Fonts.default
    local problem
    if family~=Fonts.default then
        local selected
        for _,entry in ipairs(Fonts.available())do if entry.name==family then selected=entry;break end end
        if selected then
            local ok,result,bold=pcall(function()
                local source=readFont(selected.path)
                local boldSource=selected.bold and readFont(selected.bold) or source
                return makeSet(source,boldSource,sizes,true)
            end)
            if ok then return result,bold,nil,family end
            problem='Could not load '..family..'; using the built-in font.'
        else problem='The saved font is unavailable; using the built-in font.' end
    end
    local result,bold=makeSet('assets/fonts/DejaVuSans.ttf','assets/fonts/DejaVuSans-Bold.ttf',sizes,false)
    return result,bold,problem,Fonts.default
end
-- Titles use the supplied Magic display face; body copy and symbol fonts retain
-- their own settings. Keep this lazy: a heading does not rebuild a font set.
function Fonts.title(size,titleFamily,bodyFamily)
    size=math.max(8,math.min(96,math.floor((tonumber(size) or 22)+.5)))
    titleFamily=titleFamily=='Application font' and titleFamily or Fonts.titleDefault
    bodyFamily=bodyFamily or Fonts.default
    local key=table.concat({size,titleFamily,bodyFamily},'|')
    titleClock=titleClock+1
    if titleCache[key] then titleCache[key].used=titleClock;return titleCache[key].font,titleCache[key].family end
    local font,effective
    if titleFamily==Fonts.titleDefault and love.filesystem.getInfo('assets/fonts/Beleren2016-Bold.ttf') then
        local ok,result=pcall(love.graphics.newFont,'assets/fonts/Beleren2016-Bold.ttf',size)
        if ok then font=result;effective=Fonts.titleDefault;font:setFallbacks(love.graphics.newFont('assets/fonts/DejaVuSans-Bold.ttf',size)) end
    end
    if not font then
        local fonts,_,_,family=Fonts.createSet(bodyFamily,{size})
        font=fonts[size];effective=family
    end
    titleCache[key]={font=font,family=effective,used=titleClock}
    local count=0;for _ in pairs(titleCache)do count=count+1 end
    if count>32 then
        local oldest,when;for k,entry in pairs(titleCache)do if not when or entry.used<when then oldest,when=k,entry.used end end
        titleCache[oldest]=nil
    end
    return font,effective
end
return Fonts
