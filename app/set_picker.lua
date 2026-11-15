-- Reusable local set filtering. Selecting a set never selects an edition or
-- applies a deck edit; the current owner's callback controls its filter only.
local utf8=require('utf8')
local Picker={};local tiles={};local clock,opening=0,0;local runeFont,runeEpoch
local function value(option)if type(option)=='function'then return option()end;return option end
local function lower(code)
    if code>=65 and code<=90 or code>=0xC0 and code<=0xD6 or code>=0xD8 and code<=0xDE then return code+32 end
    if code>=0x100 and code<=0x12F and code%2==0 or code>=0x132 and code<=0x137 and code%2==0 or code>=0x14A and code<=0x177 and code%2==0 then return code+1 end
    if code>=0x139 and code<=0x148 and code%2==1 or code>=0x179 and code<=0x17E and code%2==1 then return code+1 end
    if code==0x178 then return 0xFF elseif code==0x130 then return 105 end
    if code>=0x391 and code<=0x3A1 or code>=0x3A3 and code<=0x3AB then return code+32 end
    if code>=0x410 and code<=0x42F then return code+32 elseif code>=0x400 and code<=0x40F then return code+80 end
    return code
end
function Picker.fold(text)
    text=tostring(text or'')
    local ok,result=pcall(function()local out={};for _,code in utf8.codes(text)do out[#out+1]=utf8.char(lower(code))end;return table.concat(out)end)
    return ok and result or text:lower()
end
local function releaseInput(v)
    if v.S and v.S.SetInputFocus then v.S.SetInputFocus(nil)end
    local region=package.loaded['lib.Slab.Internal.UI.Region'];if region then region.ClearHotInstance()end
end
function Picker.close(v)
    if v.setPicker then v.setPicker.closed=true;v.setPicker=nil;releaseInput(v)end
end
function Picker.current(v)
    local state=v.setPicker
    if state and(state.closed or state.isCurrent and not state.isCurrent())then Picker.close(v);return nil end
    return state
end
function Picker.open(v,options)
    Picker.close(v);releaseInput(v)
    opening=opening+1
    local state={id=options.id or'sets',token='set-picker-'..opening,owner=options.owner,title=options.title or'Choose a set',items=options.items or{},busy=options.busy,error=options.error,selected=tostring(options.selected or''):lower(),onSelect=options.onSelect,isCurrent=options.isCurrent,query='',page=0,focus=true}
    v.setPicker=state;return state
end
function Picker.filter(v,query)
    local state=Picker.current(v);if not state then return false end
    state.query=query or'';state.page=0;state.interacted=true;state.filtered=nil;return true
end
function Picker.items(v)
    local state=Picker.current(v);if not state then return{}end
    local source=value(state.items)or{}
    if state.source~=source or state.sourceCount~=#source or not state.filtered then
        state.source=source;state.sourceCount=#source
        local query=Picker.fold(state.query);local result={{code='',name='All sets',all=true}};local seen={}
        for _,item in ipairs(source)do
            local code=tostring(item.code or''):lower();local name=tostring(item.name or code:upper())
            if code~=''and not seen[code]and(query==''or Picker.fold(name..' '..code):find(query,1,true))then
                seen[code]=true;result[#result+1]={code=code,name=name,count=tonumber(item.count)}
            end
        end
        state.filtered=result
    end
    return state.filtered
end
function Picker.select(v,code,expected)
    local state=Picker.current(v);if not state then return false end
    if expected and state~=expected then return false end
    code=tostring(code or''):lower();local found=code==''
    for _,item in ipairs(Picker.items(v))do if item.code==code then found=true;break end end
    if not found then return false end
    if state.onSelect then state.onSelect(code)end
    if v.setPicker==state then Picker.close(v)end
    return true
end
local function icon(v,code,x,y,size,color)
    -- Only THB has a retained, verified Keyrune mapping (ASSET_GUIDE.md).
    -- Unknown sets use the supplied collection icon and their explicit code.
    if code=='thb'then
        local Assets=require('app.assets');local epoch=Assets.rasterContext();local density=math.max(1,Assets.uiRasterScale(v.m.settings));local signature=epoch..':'..density
        if runeEpoch~=signature then
            runeEpoch=signature;local ok,font=pcall(love.graphics.newFont,'assets/keyrune/keyrune.ttf',size,'normal',density)
            runeFont=ok and font or false;if runeFont then runeFont:setFilter('linear','linear')end
        end
        local glyph=utf8.char(0xE961)
        if runeFont and runeFont:hasGlyphs(glyph)then love.graphics.setFont(runeFont);love.graphics.setColor(color);love.graphics.print(glyph,x+(size-runeFont:getWidth(glyph))/2,y+(size-runeFont:getHeight())/2);return end
    end
    v.r.assets:iconSymbol('collection',x,y,size,color)
end
local function tile(v,item,width,height,selected)
    local Assets=require('app.assets');local epoch=Assets.rasterContext();local scale=Assets.uiRasterScale(v.m.settings);local C=v.r.colors
    local key=table.concat({epoch,scale,item.code,item.name,tostring(item.count),width,height,tostring(selected),tostring(v.r.fonts[14]),v.r.assets.theme and v.r.assets.theme.colorSignature or''},'|')
    clock=clock+1;local cached=tiles[key];if cached then cached.used=clock;return cached.image end
    local image=Assets.rasterize(width*scale,height*scale,function()
        love.graphics.scale(scale);icon(v,item.code,(width-32)/2,8,32,selected and C.accent or C.gold)
        love.graphics.setColor(selected and C.accent or C.text);love.graphics.setFont(v.r.fonts[16]);love.graphics.printf(item.all and'ALL'or item.code:upper(),8,44,width-16,'center')
        love.graphics.setFont(v.r.fonts[14]);love.graphics.printf(v.r:fit(item.name,width-18,14,2),9,68,width-18,'center')
        if item.count then love.graphics.setColor(C.muted);love.graphics.setFont(v.r.fonts[12]);love.graphics.printf(tostring(item.count)..' results',8,height-21,width-16,'center')end
        if selected then v.r.assets:iconSymbol('check',width-25,8,17,C.accent)end
    end)
    tiles[key]={image=image,used=clock};local count=0;for _ in pairs(tiles)do count=count+1 end
    if count>48 then local oldest,used;for id,entry in pairs(tiles)do if id~=key and(not used or entry.used<used)then oldest,used=id,entry.used end end;if oldest then tiles[oldest]=nil end end
    return image
end
function Picker.build(v,w,h)
    local state=Picker.current(v);if not state then return false end
    local S,r=v.S,v.r;local pw,ph=math.min(1000,w-64),math.min(800,h-64);local inner=pw-40;local gridH=math.max(150,ph-256)
    local columns=math.max(2,math.min(5,math.floor((inner-12)/180)));local rows=math.max(1,math.min(4,math.floor((gridH-12)/140)));local pageSize=columns*rows
    local perPage=math.max(1,pageSize-1);local items=Picker.items(v);local pages=math.max(1,math.ceil((#items-1)/perPage))
    if not state.initialShown and not state.interacted and state.query==''then
        for index,item in ipairs(items)do if item.code==state.selected then state.page=math.max(0,math.floor((index-2)/perPage));state.initialShown=true;break end end
    end
    state.page=math.max(0,math.min(state.page,pages-1));state.pageSize=pageSize
    local C=r.colors;v:window('set-picker',(w-pw)/2,(h-ph)/2,pw,ph,nil,{Layer='Dialog',BgColor={C.panel[1],C.panel[2],C.panel[3],1}})
    local function button(id,options)S.PushID(state.token);local result=S.Button(id,options);S.PopID();return result end
    S.PushFont(r.fonts[22]);S.Textf(r:fit(state.title,inner-110,22,1),{W=inner-110,Color=C.accent});S.PopFont();S.SameLine()
    if button('Close set picker',{W=100,H=34,Image={Image=r.assets:buttonImage('close','Close',100,34)},Tooltip='Keep the current set filter'})then Picker.close(v);S.EndWindow();return true end
    S.NewLine()
    if S.Input('set-picker-search',{Text=state.query,W=inner,H=38,Align='left',Tooltip='Search set names or set codes'})then Picker.filter(v,S.GetInputText());items=Picker.items(v);pages=math.max(1,math.ceil((#items-1)/perPage))end
    if state.focus then S.SetInputFocus('set-picker-search');state.focus=nil end
    S.NewLine()
    local busy,error=value(state.busy),value(state.error)
    local matched=#items-1
    S.Textf(error and r:fit(error,inner,16,1)or(busy and'Loading sets…'or tostring(matched)..(matched==1 and' matching set'or' matching sets')),{W=inner,Color=error and C.gold or C.muted,Tooltip=error});S.NewLine()
    S.BeginListBox('set-picker-grid',{W=inner,H=gridH})
    local ox,oy=S.GetCursorPos({Absolute=true})
    local width=math.floor((inner-24-(columns-1)*12)/columns);local height=128
    -- Keep All sets reachable even when the active set opens on a later page.
    local visible={items[1]};for index=state.page*perPage+2,math.min(#items,(state.page+1)*perPage+1)do visible[#visible+1]=items[index]end
    for localIndex,item in ipairs(visible)do
        local offset=((localIndex-1)%columns)*(width+12);S.Indent(offset);S.SetCursorPos(ox+offset,oy+math.floor((localIndex-1)/columns)*(height+12),{Absolute=true})
        local selected=item.code==state.selected
        if button('set-tile-'..(item.all and'all-sets'or item.code),{W=width,H=height,Active=selected,Image={Image=tile(v,item,width-4,height-4,selected)},Tooltip=item.all and'Clear the set filter'or(item.name..' · '..item.code:upper())})then Picker.select(v,item.code,state)end
        S.Unindent(offset)
    end
    if #items==1 and not busy and not error then S.NewLine();S.Textf('No sets match this search.',{W=inner-24,Color=C.muted})end
    S.EndListBox();S.NewLine()
    if button('Previous sets',{W=130,H=34,Disabled=state.page==0,Image={Image=r.assets:buttonImage('previous','Previous',130,34)}})then state.page=state.page-1;state.interacted=true end
    S.SameLine();S.Text(tostring(state.page+1)..' / '..pages,{Color=C.muted});S.SameLine()
    if button('Next sets',{W=110,H=34,Disabled=state.page+1>=pages,Image={Image=r.assets:buttonImage('next','Next',110,34)}})then state.page=state.page+1;state.interacted=true end
    S.EndWindow();return true
end
return Picker
