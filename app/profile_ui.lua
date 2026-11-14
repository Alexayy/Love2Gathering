-- Profile editing uses the current Slab/theme controls and exact catalog art.
local Profile=require('app.profile')
local Shared=require('app.draft_ui')
local Assets=require('app.assets')
local Layout=require('app.layout')
local UI={tileCache={},tileOrder={}}
function UI.layout(w,h)
    local side=math.max(270,math.min(350,w*.30));local x=26+side+18;local width=w-x-26
    local inner=width-30;local columns=math.max(2,math.min(4,math.floor(inner/220)));local tile=(inner-(columns-1)*12)/columns
    return {side={x=26,y=126,w=side,h=h-152},gallery={x=x,y=126,w=width,h=h-152},columns=columns,tileW=tile,imageH=math.min(150,tile*.58),limit=columns*2}
end
local function tileImage(v,image,width,height)
    local scale=Layout.scale or 1;local key=table.concat({Assets.rasterEpoch,tostring(image),width,height,scale},':')
    if UI.tileCache[key]then return UI.tileCache[key]end
    local canvas=Assets.rasterize(width*scale,height*scale,function()
        love.graphics.scale(scale);v.r.assets:panel(0,0,width,height,{.035,.055,.075,1})
        local fit=math.min((width-4)/image:getWidth(),(height-4)/image:getHeight());love.graphics.setColor(1,1,1,1)
        love.graphics.draw(image,(width-image:getWidth()*fit)/2,(height-image:getHeight()*fit)/2,0,fit,fit)
    end)
    UI.tileCache[key]=canvas;UI.tileOrder[#UI.tileOrder+1]=key;while#UI.tileOrder>32 do UI.tileCache[table.remove(UI.tileOrder,1)]=nil end;return canvas
end
local function preview(v,ref,id,width,height)
    local S,m,r=v.S,v.m,v.r;local image=m:profileArt(ref)
    if image then
        local scale=math.min(width/image:getWidth(),height/image:getHeight())
        S.Image(id,{Image=image,W=image:getWidth()*scale,H=image:getHeight()*scale,Tooltip=ref.name or 'Card illustration'})
    else S.Image(id..'-fallback',{Image=r.assets:iconImage(ref and'image'or'player',math.min(64,height),r.colors.muted),W=math.min(64,height),H=math.min(64,height)});S.SameLine();S.Text(ref and'Artwork is not cached yet'or'No illustration selected',{Color=r.colors.muted})end
end
function UI.build(v,w,h)
    local S,m,r=v.S,v.m,v.r;local l=UI.layout(w,h);local draft=m.profileDraft or m.profile or {name='Planeswalker'};local C=r.colors
    if m.profileLimit~=l.limit then m.profileLimit=l.limit;m:profileSearchChanged()end
    v:window('profile-details',l.side.x,l.side.y,l.side.w,l.side.h);local width=l.side.w-30
    Shared.heading(v,'Your profile','player',width);S.NewLine()
    if S.Input('profile-name',{Text=draft.name or '',W=width,H=31,Align='left',Tooltip='Your name in new games and rooms'})then m:setProfileName(S.GetInputText())end
    S.NewLine()
    S.BeginListBox('profile-customization',{W=width,H=math.max(220,l.side.h-170)});local outerWidth=width;width=width-18
    for _,slot in ipairs({'avatar','playmat'})do
        S.PushID('profile-'..slot)
        local label=slot=='avatar'and'Avatar'or'Playmat';local icon=slot=='avatar'and'player'or'image'
        if Shared.button(v,label,icon,width-38,31,{IsSelected=m.profileSlot==slot,Tooltip='Choose '..label:lower()..' artwork'})then m.profileSlot=slot end
        S.SameLine({Pad=6});if Shared.button(v,'Clear','close',32,31,{Tooltip='Clear '..label:lower(),Disabled=not draft[slot]})then m:clearProfileArt(slot)end
        preview(v,draft[slot],'profile-preview-'..slot,width,slot=='avatar' and 88 or 104)
        S.Textf(draft[slot]and(draft[slot].name or 'Selected card illustration')or'Use the artwork list to choose an illustration.',{W=width,Color=C.muted});S.NewLine();S.PopID()
    end
    local live
    for _,player in ipairs(m.game and m.game.players or {})do if player.human or player.isLocal then live=player.life end end
    S.Textf(live and('Current match life: '..tostring(live))or'Life is supplied by XMage when a match starts.',{W=width,Color=C.accent})
    S.Textf('Changes apply to new games and rooms.',{W=width,Color=C.muted});S.NewLine()
    if m.profileError or m.profileLoadError then S.Textf(m.profileError or m.profileLoadError,{W=width,Color=C.gold})end
    S.EndListBox();S.NewLine();width=outerWidth
    if Shared.button(v,m.profileSaving and'Saving…'or'Save profile','save',width*.60,32,{Disabled=m.profileSaving or not m.profileDirty})then m:saveProfile()end
    S.SameLine({Pad=6});if Shared.button(v,'Reset','reset',width*.40-6,32,{Disabled=m.profileSaving or not m.profileDirty})then m:resetProfileDraft()end
    S.EndWindow()
    v:window('profile-art',l.gallery.x,l.gallery.y,l.gallery.w,l.gallery.h);local area=l.gallery.w-30
    Shared.heading(v,'Choose '..(m.profileSlot=='playmat'and'playmat'or'avatar')..' artwork','gallery',area);S.NewLine()
    S.Image('profile-search-icon',{Image=r.assets:iconImage('search',20,C.muted),W=20,H=20});S.SameLine()
    if S.Input('profile-search',{Text=m.profileQuery or '',W=area-28,H=30,Align='left',Tooltip='Search card, artist, set or year'})then m.profileQuery=S.GetInputText();m:profileSearchChanged()end
    S.Text(m.profileBusy and'Loading artwork…'or tostring(m.profileTotal or 0)..' illustrations',{Color=C.muted});S.NewLine()
    if m.profileSearchError then S.Textf(m.profileSearchError,{W=area,Color=C.gold})end
    S.BeginListBox('profile-results',{W=area,H=math.max(150,l.gallery.h-170)})
    local originX,originY=S.GetCursorPos({Absolute=true});local tileH=l.imageH+58
    for index,item in ipairs(m.profileItems or {})do
        local column=(index-1)%l.columns;local row=math.floor((index-1)/l.columns);local offset=column*(l.tileW+12)
        S.Indent(offset);S.SetCursorPos(originX+offset,originY+row*tileH,{Absolute=true})
        local ref=Profile.reference(item);local image=m:profileArt(ref)
        local options={W=l.tileW,H=l.imageH,Tooltip=(item.name or '')..' · '..(item.artist or '')}
        if image then options.Image={Image=tileImage(v,image,l.tileW,l.imageH)} else options.Image={Image=r.assets:buttonImage('image',r:fit(item.name or'Artwork',l.tileW-16,14,2),l.tileW,l.imageH,{font=r.fonts[14],iconSize=22})}end
        if S.Button('profile-select-'..item.printing_id..'-'..tostring(item.face),options)then m:chooseProfileArt(m.profileSlot,item)end
        S.Textf(r:fit(item.name or'',l.tileW,14,1),{W=l.tileW,Color=C.text})
        S.PushFont(r.fonts[12]);S.Textf(r:fit((item.artist or'')..' · '..(item.set_name or item.set or''),l.tileW,12,2),{W=l.tileW,Color=C.muted});S.PopFont()
        S.Unindent(offset)
    end
    S.EndListBox();S.NewLine()
    if Shared.button(v,'Previous','previous',110,30,{Disabled=(m.profileOffset or 0)==0 or m.profileBusy})then m.profileOffset=math.max(0,m.profileOffset-m.profileLimit);m:refreshProfileArt()end
    S.SameLine();if Shared.button(v,'Next','next',110,30,{Disabled=(m.profileOffset or 0)+#(m.profileItems or {})>=(m.profileTotal or 0)or m.profileBusy})then m.profileOffset=m.profileOffset+m.profileLimit;m:refreshProfileArt()end
    S.EndWindow()
end
return UI
