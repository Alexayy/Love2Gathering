-- Inline mana symbols in wrapped text. Layout coordinates are logical UI units.
local utf8=require('utf8')
local Text=require('app.utf8_text')
local Assets=require('app.assets')
local glyphs=require('assets.keyrune.glyphs')
local RichText={cache={},clock=0,cacheLimit=96,pixelLimit=12*1024*1024}
local function clean(value)
    if type(value)=='table' then
        if value.message or value.text then value=value.message or value.text else local parts={};for _,item in ipairs(value)do parts[#parts+1]=tostring(item)end;value=table.concat(parts,'\n')end
    end
    local text=tostring(value or ''):gsub('\r\n','\n'):gsub('\r','\n'):gsub('<[Bb][Rr]%s*/?>','\n'):gsub('<[^>]*>',''):gsub('&nbsp;',' '):gsub('&amp;','&'):gsub('&lt;','<'):gsub('&gt;','>'):gsub('&#39;',"'")
    return Text.clean(text)
end
local function isMana(value)
    local key=value:upper():gsub('%s','')
    if key:match('^%d+$') or key:match('^[WUBRGCXYZSTQEP]$') or key=='CHAOS' or key=='∞' or key=='½' or key=='TK' then return true end
    if key:match('^[2WUBRGC]/[WUBRGC]$') or key:match('^[WUBRGC]/P$') or key:match('^[WUBRGC]/[WUBRGC]/P$') then return true end
    return false
end
function RichText.tokens(value)
    local text=clean(value);local tokens={};local index=1
    while index<=#text do
        local ch=text:sub(index,index)
        if ch=='\n' then tokens[#tokens+1]={kind='newline'};index=index+1
        elseif ch:match('%s') then
            local ending=index
            while ending<=#text and text:sub(ending,ending)~='\n' and text:sub(ending,ending):match('%s')do ending=ending+1 end
            tokens[#tokens+1]={kind='space',text=text:sub(index,ending-1):gsub('\t','    ')};index=ending
        elseif ch=='{' then
            local ending=text:find('}',index+1,true);local symbol=ending and text:sub(index+1,ending-1)
            if symbol and isMana(symbol) then tokens[#tokens+1]={kind='mana',symbol=symbol};index=ending+1
            else
                if ending then tokens[#tokens+1]={kind='text',text=text:sub(index,ending)};index=ending+1
                else tokens[#tokens+1]={kind='text',text='{'};index=index+1 end
            end
        else
            local ending=index+1
            while ending<=#text and not text:sub(ending,ending):match('[%s{]')do ending=ending+1 end
            tokens[#tokens+1]={kind='text',text=text:sub(index,ending-1)};index=ending
        end
    end
    return tokens
end
local function fontFor(renderer,opts)
    return opts.font or (renderer.fonts and renderer.fonts[opts.size or 16]) or renderer.assets:font(opts.size or 16,true)
end
function RichText.layout(renderer,value,width,opts)
    opts=opts or {};width=math.max(1,width or 300)
    local font=fontFor(renderer,opts);local iconSize=opts.iconSize or (opts.size or 16)*1.08
    local contentHeight=math.max(font:getHeight(),iconSize)
    local lineHeight=math.max(contentHeight,opts.lineHeight or contentHeight+(opts.lineSpacing or 3))
    local result={runs={},lines=1,lineHeight=lineHeight,iconSize=iconSize,font=font,width=width,height=lineHeight}
    local x,line,pending=0,1,0
    local function newline()x=0;pending=0;line=line+1 end
    local function add(kind,text,runWidth)
        if pending>0 and x>0 then
            if x+pending+runWidth>width then newline()else x=x+pending end
        end
        pending=0
        if x>0 and x+runWidth>width+.001 then newline()end
        local h=kind=='mana' and iconSize or font:getHeight()
        result.runs[#result.runs+1]={kind=kind,text=kind=='text' and text or nil,symbol=kind=='mana' and text or nil,x=x,y=(line-1)*lineHeight+(contentHeight-h)/2,w=runWidth,h=h,line=line}
        x=x+runWidth
    end
    for _,token in ipairs(RichText.tokens(value))do
        if token.kind=='newline' then newline()
        elseif token.kind=='space' then pending=pending+font:getWidth(token.text)
        elseif token.kind=='mana' then add('mana',token.symbol,iconSize+(opts.iconGap or 2))
        else
            local wordWidth=font:getWidth(token.text)
            if wordWidth<=width then add('text',token.text,wordWidth)
            else
                for _,point in utf8.codes(token.text)do local ch=utf8.char(point);add('text',ch,font:getWidth(ch))end
            end
        end
    end
    result.lines=clean(value)=='' and 0 or line
    local maxLines=opts.maxLines
    if maxLines and line>maxLines then
        maxLines=math.max(1,math.floor(maxLines));local trimmed={}
        for _,run in ipairs(result.runs)do if run.line<=maxLines then trimmed[#trimmed+1]=run end end
        local ellipsis='…';local ew=font:getWidth(ellipsis)
        while #trimmed>0 and trimmed[#trimmed].line==maxLines and trimmed[#trimmed].x+trimmed[#trimmed].w+ew>width do table.remove(trimmed)end
        local previous=trimmed[#trimmed];local ex=previous and previous.line==maxLines and previous.x+previous.w or 0
        trimmed[#trimmed+1]={kind='text',text=ellipsis,x=ex,y=(maxLines-1)*lineHeight+(contentHeight-font:getHeight())/2,w=ew,h=font:getHeight(),line=maxLines}
        result.runs=trimmed;result.lines=maxLines;result.truncated=true
    end
    result.height=result.lines*lineHeight
    return result
end
function RichText.draw(renderer,value,x,y,width,opts)
    opts=opts or {};local layout=opts.layout or RichText.layout(renderer,value,width,opts)
    love.graphics.push('all');love.graphics.setFont(layout.font)
    local color=opts.color or (renderer.colors and renderer.colors.text) or {.9,.94,.98,1}
    for _,run in ipairs(layout.runs)do
        if run.kind=='mana' then renderer.assets:mana(run.symbol,x+run.x,y+run.y,layout.iconSize,opts.manaColor)
        else love.graphics.setColor(color[1],color[2],color[3],color[4] or 1);love.graphics.print(run.text,x+run.x,y+run.y)end
    end
    love.graphics.pop();return layout.height
end
local function keyFor(renderer,text,width,opts,scale,font)
    local color=opts.color or (renderer.colors and renderer.colors.text) or {.9,.94,.98,1}
    local mana=opts.manaColor or {}
    return table.concat({Assets.rasterEpoch,text,tostring(font),string.format('%.4f',width),opts.size or 16,opts.lineHeight or '',opts.lineSpacing or '',opts.iconSize or '',opts.iconGap or '',opts.maxLines or '',opts.paddingX or 0,opts.paddingY or 0,opts.minHeight or 0,string.format('%.5f',scale),table.concat(color,','),table.concat(mana,',')},'\31')
end
function RichText.canvas(renderer,value,width,opts)
    opts=opts or {};local text=clean(value);width=math.max(1,width or 300);Assets.rasterContext()
    local scale=Assets.uiRasterScale(renderer.assets.settings)
    local font=fontFor(renderer,opts);local key=keyFor(renderer,text,width,opts,scale,font)
    RichText.clock=RichText.clock+1
    local entry=RichText.cache[key]
    if entry then entry.used=RichText.clock;return entry.image,entry.height end
    local padX,padY=opts.paddingX or 0,opts.paddingY or 0
    local contentWidth=math.max(1,width-padX*2)
    local layout=RichText.layout(renderer,text,contentWidth,opts)
    local maxSize=(love.graphics.getSystemLimits and love.graphics.getSystemLimits().texturesize) or 8192
    if (layout.height+padY*2)*scale>maxSize then
        local clipped={};for k,v in pairs(opts)do clipped[k]=v end;clipped.maxLines=math.max(1,math.floor((maxSize/scale-padY*2)/layout.lineHeight));layout=RichText.layout(renderer,text,contentWidth,clipped)
    end
    local height=math.max(opts.minHeight or 0,layout.height+padY*2)
    local canvas=Assets.rasterize(width*scale,height*scale,function()
        love.graphics.scale(scale);local drawOpts={};for k,v in pairs(opts)do drawOpts[k]=v end;drawOpts.layout=layout;RichText.draw(renderer,text,padX,(height-layout.height)/2,contentWidth,drawOpts)
    end)
    local pixels=canvas:getWidth()*canvas:getHeight()
    if pixels<=RichText.pixelLimit then
        RichText.cache[key]={image=canvas,height=height,used=RichText.clock,pixels=pixels}
        local count,total=0,0;for _,item in pairs(RichText.cache)do count=count+1;total=total+item.pixels end
        while count>RichText.cacheLimit or total>RichText.pixelLimit do
            local oldest,oldestTime
            for id,item in pairs(RichText.cache)do if not oldestTime or item.used<oldestTime then oldest,oldestTime=id,item.used end end
            total=total-RichText.cache[oldest].pixels;RichText.cache[oldest]=nil;count=count-1
        end
    end
    return canvas,height
end
function RichText.slab(view,id,text,width,opts)
    if clean(text)=='' then return 0 end
    local canvas,height=RichText.canvas(view.r,text,width,opts)
    view.S.Image(id,{Image=canvas,W=width,H=height,Color={1,1,1,1}})
    return height
end
function RichText.button(view,label,value,width,opts)
    opts=opts or {}
    local canvas,height=RichText.canvas(view.r,value,width,{size=opts.size or 16,lineSpacing=1,
        maxLines=opts.maxLines or 3,paddingX=12,paddingY=6,minHeight=opts.height or 38,
        color=opts.disabled and view.r.colors.muted or opts.color})
    return view.S.Button(label,{W=width,H=height,Image={Image=canvas},
        Tooltip=opts.tooltip or value,Active=opts.active,Disabled=opts.disabled})
end
function RichText.clearCache()RichText.cache={};RichText.clock=0 end
return RichText
