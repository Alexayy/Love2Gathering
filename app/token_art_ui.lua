-- Related token families and a staged, exact-printing illustration picker.
local UI={}
local Cursor=require('lib.Slab.Internal.Core.Cursor')
local Draw=require('lib.Slab.Internal.Core.DrawCommands')
local Window=require('lib.Slab.Internal.UI.Window')
local names={default='Default',selected='Manual',randomSelected='Random selected',randomAll='Random all'}
local function button(v,label,icon,w,h,options)
    options=options or{};options.W=w;options.H=h
    options.Image={Image=v.r.assets:buttonImage(icon,label,w,h,{font=v.r.fonts[14],iconSize=17})}
    return v.S.Button(label,options)
end
local function countSelected(picker)local n=0;for _,on in pairs(picker.selected or{})do if on then n=n+1 end end;return n end
local function cardButton(v,label,item,w,h,selected,options)
    options=options or{};options.W=w;options.H=h;options.Active=selected
    local art=item and v.m:getArt(item,true)
    if art then
        UI.blank=UI.blank or require('app.assets').rasterize(1,1,function()end)
        options.Image={Image=UI.blank}
    else options.Image={Image=v.r.assets:buttonImage(selected and'check'or'gallery',item and item.name or'Artwork',w,h,{font=v.r.fonts[14],iconSize=25})}end
    local clicked=v.S.Button(label,options)
    if art then
        local x,y=Cursor.GetItemBounds();local iw,ih=art:getDimensions();local scale=math.min((w-8)/iw,(h-8)/ih)
        Draw.Image(math.floor(x+(w-iw*scale)/2),math.floor(y+(h-ih*scale)/2),art,0,scale,scale)
    end
    if selected then local x,y,bw,bh=Cursor.GetItemBounds();Draw.Rectangle('line',x+1,y+1,bw-2,bh-2,v.r.colors.accent,4,nil,3)end
    return clicked
end
local function grid(v,id,items,width,height,draw)
    local S=v.S
    S.BeginListBox(id,{W=width,H=height})
    local ax,ay=Cursor.GetPosition();local anchorX=Cursor.GetAnchorX();local cols=math.max(2,math.floor((width-20)/180));local gap=16
    local cw=math.floor((width-20-(cols-1)*gap)/cols);local ch=math.min(240,math.floor(cw*1.4),math.max(80,height-76));local rowH=ch+76
    for index,item in ipairs(items)do
        local col,row=(index-1)%cols,math.floor((index-1)/cols)
        Cursor.SetAnchorX(ax+col*(cw+gap));Cursor.SetPosition(ax+col*(cw+gap),ay+row*rowH)
        S.PushID(item.tokenImageId or item.tokenIdentity or tostring(index));draw(item,cw,ch);S.PopID()
    end
    Cursor.SetAnchorX(anchorX)
    if#items>0 then Cursor.SetPosition(ax,ay+math.ceil(#items/cols)*rowH)end
    S.EndListBox()
end
local function picker(v,w,h)
    local S,m=v.S,v.m;local p=m.tokenPicker;if not p then return end
    local width,height=math.min(1080,w-64),math.min(800,h-100);local inner=width-32
    local color=v.r.colors.panel or{.035,.055,.08}
    v:window('token-art-picker',(w-width)/2,(h-height)/2,width,height,'Choose '..p.group.name..' artwork',{Layer='Dialog',BgColor={color[1],color[2],color[3],1}})
    Window.SetStackLock('token-art-picker');m.tokenPickerLocked=true
    local modes={'default','selected','randomSelected','randomAll'}
    for index,mode in ipairs(modes)do
        if index>1 then S.SameLine()end
        if button(v,names[mode],(mode=='randomAll'or mode=='randomSelected')and'shuffle'or'gallery',(inner-20)/4,34,{Active=p.mode==mode})then m:setTokenPickerMode(mode)end
    end
    S.NewLine()
    local description=p.mode=='randomAll'and('Every matching '..p.group.name..' illustration in the local catalog is eligible.')or p.mode=='randomSelected'and('Choose multiple illustrations. '..countSelected(p)..' selected; outlined cards are active.')or p.mode=='selected'and'Choose one illustration. Its outline marks the active art.'or'The deck’s linked token printing is used. Choose a mode to override it.'
    S.Textf(description,{W=inner,Color=v.r.colors.muted});S.NewLine()
    if S.Input('token-art-search',{Text=p.query,W=inner,H=32,Align='left',Tooltip='Search this token’s sets or editions'})then p.query=S.GetInputText();p.offset=0;p.version=p.version+1;m.tokenPickerTimer=.2 end
    S.NewLine()
    grid(v,'token-art-variants',p.items,inner,math.max(90,height-285),function(item,cw,ch)
        local selected=p.mode=='randomAll'or((p.mode=='selected'or p.mode=='randomSelected')and p.selected[item.tokenImageId])or(p.mode=='default'and p.group.defaultCard and p.group.defaultCard.tokenImageId==item.tokenImageId)
        local tip=item.name..' · '..(item.set_name or item.set or'')..' · '..(item.collector_number or'')..' · '..(item.artist or'')
        if cardButton(v,'Artwork '..item.tokenImageId,item,cw,ch,selected,{Tooltip=tip})then m:toggleTokenPickerArt(item.tokenImageId)end
        S.Textf((item.set or''):upper()..' '..(item.collector_number or'')..(selected and' · Active'or''),{W=cw,Color=selected and v.r.colors.accent or v.r.colors.text})
        S.Textf(item.artist or'',{W=cw,Color=v.r.colors.muted})
    end)
    S.NewLine()
    if button(v,'Previous arts','previous',142,30,{Disabled=p.busy or p.offset==0})then p.offset=math.max(0,p.offset-12);m:refreshTokenPicker()end;S.SameLine()
    if button(v,'Next arts','next',120,30,{Disabled=p.busy or p.offset+12>=p.total})then p.offset=p.offset+12;m:refreshTokenPicker()end;S.SameLine()
    S.Text((p.busy and'Loading…'or tostring(p.total)..' illustrations'),{Color=v.r.colors.muted});S.NewLine()
    if p.error then S.Textf(p.error,{W=inner,Color=v.r.colors.gold})end
    if button(v,'Apply token selection','check',(inner-8)/2,34,{Disabled=p.busy})then m:applyTokenPicker()end;S.SameLine()
    if button(v,'Cancel token selection','close',(inner-8)/2,34)then m:closeTokenPicker()end
    S.EndWindow()
end
function UI.build(v,w,h)
    local S,m=v.S,v.m;local locked=m.tokenPicker~=nil;local width=w-52;local inner=width-32
    v:window('token-preferences',26,105,width,h-170)
    S.Image('token-title-icon',{Image=v.r.assets:iconImage('gallery',22),W=22,H=22});S.SameLine();S.Text('Token artwork for this deck',{Color=v.r.colors.accent});S.NewLine()
    S.Textf('Only tokens made by this deck are shown. Each tile shows its active art mode; open it to choose illustrations.',{W=inner,Color=v.r.colors.muted});S.NewLine()
    if S.Input('token-search',{Text=m.tokenQuery or'',W=inner,H=32,ReadOnly=locked,Align='left',Tooltip='Search related token names'})then m.tokenQuery=S.GetInputText();m.tokenOffset=0;m.tokenVersion=(m.tokenVersion or 0)+1;m.tokenTimer=.25 end
    S.NewLine()
    grid(v,'token-families',m.tokenItems or{},inner,math.max(100,h-390),function(group,cw,ch)
        local active=m:tokenGroupPresentation(group)
        if cardButton(v,'Edit '..group.name..' artwork',active.card,cw,ch,true,{Disabled=locked or m.tokenSaving,Tooltip=group.name..' · '..(names[active.mode]or'Default')..' · '..active.count..' active illustration(s)'})then m:openTokenPicker(group)end
        S.Textf(group.name..(group.power and' '..group.power..'/'..(group.toughness or'?')or''),{W=cw,Color=v.r.colors.text})
        local mode=names[active.mode]or'Default'
        S.Textf(mode..(active.mode=='randomSelected'and' · '..active.count..' selected'or active.mode=='randomAll'and' · '..active.count..' arts'or' · '..((active.card or{}).set or''):upper()),{W=cw,Color=v.r.colors.accent})
    end)
    S.NewLine()
    if#(m.tokenItems or{})==0 then S.Textf(m.tokenBusy and'Loading related tokens…'or'No linked token artwork is available for this deck in the local metadata.',{W=inner,Color=v.r.colors.muted})end
    if button(v,'Previous','previous',120,30,{Disabled=locked or m.tokenBusy or(m.tokenOffset or 0)==0})then m.tokenOffset=math.max(0,m.tokenOffset-12);m:refreshTokenSettings()end;S.SameLine()
    if button(v,'Next','next',100,30,{Disabled=locked or m.tokenBusy or(m.tokenOffset or 0)+12>=(m.tokenTotal or 0)})then m.tokenOffset=(m.tokenOffset or 0)+12;m:refreshTokenSettings()end;S.SameLine()
    if button(v,'Save token artwork','save',190,30,{Disabled=locked or m.tokenBusy or m.tokenSaving or not m.tokenDeckId})then m:saveTokenSettings()end;S.SameLine()
    S.Text(m.tokenSaving and'Saving…'or m.tokenDirty and'Unsaved changes'or'Saved selection',{Color=v.r.colors.muted})
    if m.tokenError then S.NewLine();S.Textf(m.tokenError,{W=inner,Color=v.r.colors.gold})end
    S.EndWindow()
    v:window('library-footer',26,h-53,w-52,42)
    if button(v,'Decks','library',115,29,{Disabled=locked})then m.page='decks'end;S.SameLine()
    S.Textf('Artwork changes presentation. Token rules and live stats remain native.',{W=w-210,Color=v.r.colors.muted});S.EndWindow()
    picker(v,w,h)
end
return UI
