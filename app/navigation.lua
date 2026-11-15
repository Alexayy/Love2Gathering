-- Shared navbar geometry and window actions. No gameplay or deck rules.
local Layout=require('app.layout')
local Navigation={height=82}
local pages={{'Decks','decks','library'},{'Builder','builder','edit'},{'Lobby','lobby','commander'},{'Rooms','rooms','players'},{'Replays','replays','replay'},{'Gallery','gallery','gallery'}}
local function contains(b,x,y)return b and x>=b.x and y>=b.y and x<=b.x+b.w and y<=b.y+b.h end
function Navigation.layout(w,page,hasGame)
    local compact=w<1850;local brandW=compact and(w<1250 and 138 or 158)or 250
    local profileW=compact and 154 or 184;local settingsW=compact and 48 or 126
    local profileX=w-24-settingsW-10-profileW
    local out={brand={x=16,y=12,w=brandW,h=56},profile={x=profileX,y=16,w=profileW,h=50},settings={x=w-24-settingsW,y=16,w=settingsW,h=50},pages={},compact=compact}
    local x=brandW+30;local entries={};for _,p in ipairs(pages)do entries[#entries+1]=p end
    if hasGame then entries[#entries+1]={'Match','table','play'}end
    for _,p in ipairs(entries)do
        local width=compact and(page==p[2]and 104 or 44)or 118
        out.pages[#out.pages+1]={label=p[1],page=p[2],icon=p[3],x=x,y=16,w=width,h=50,showLabel=not compact or page==p[2]}
        x=x+width+(compact and 6 or 8)
    end
    out.dynamic={x=x+12,y=14,w=math.max(0,profileX-x-28),h=54}
    return out
end
local function switch(m,page)
    if page=='builder'and not m.editDeck then m:newDeck()
    elseif page=='replays'then m:showReplays()
    elseif page=='gallery'then m:showGallery()
    elseif page=='rooms'then m:showRooms()
    else m.page=page end
end
function Navigation.draw(r,w)
    local m,C=r.model,r.colors;local L=Navigation.layout(w,m.page,m.game~=nil);r.navigationLayout=L
    r.assets:divider(L.dynamic.x,69,L.dynamic.w,C.line)
    if not r.brandIcon then r.brandIcon=love.graphics.newImage(r.assets:icon())end
    love.graphics.setColor(C.gold);love.graphics.draw(r.brandIcon,24,18,0,44/r.brandIcon:getWidth(),44/r.brandIcon:getHeight())
    r:strong(L.compact and'Love: 2G'or'Love: 2 Gathering',81,27,L.compact and 18 or 20,C.text,L.brand.w-64)
    r:hit({x=L.brand.x,y=L.brand.y,w=L.brand.w,h=L.brand.h,kind='app-brand',tooltip='Right-click for window actions'})
    for _,item in ipairs(L.pages)do
        r:button(item.showLabel and item.label or'',item.x,item.y,item.w,item.h,function()switch(m,item.page)end,m.page==item.page,{icon=item.icon,size=16,tooltip=item.label})
    end
    r:button(L.compact and''or'Settings',L.settings.x,L.settings.y,L.settings.w,L.settings.h,function()m:openSettings()end,m.page=='settings',{icon='settings',size=16,tooltip='Settings'})
    local p=L.profile;local profile=m.profile or{name=m.playerName}
    r.assets:control(p.x,p.y,p.w,p.h,m.page=='profile'and'accent'or'dark');r:drawAvatar(nil,p.x+6,p.y+6,38)
    r:strong(r:fit(profile.name or'Profile',p.w-58,16,1),p.x+51,p.y+6,16,C.text,p.w-58)
    local life;for _,player in ipairs(m.game and m.game.players or{})do if player.human or player.isLocal then life=player.life end end
    r:text(life and tostring(life)..' life'or'Profile',p.x+51,p.y+28,12,C.muted,p.w-58)
    local ready=m.engineHealth.ok or m.engineHealth.status=='ok'or m.engineHealth.ready
    love.graphics.setColor(ready and C.accent or C.gold);love.graphics.circle('fill',p.x+p.w-8,p.y+4,3)
    r:hit({x=p.x,y=p.y,w=p.w,h=p.h,action=function()m:showProfile()end,tooltip=(profile.name or'Profile')..' · '..(ready and'XMage connected'or'XMage starting')})
    local b=L.dynamic
    if m.page=='decks'then
        local actions={{'Import','import',function()m:showImport()end},{'History','replay',function()m:showHistory()end},{'New deck','add',function()m:newDeck()end}}
        local bw=math.min(126,math.floor((b.w-16)/3));local labels=bw>=104
        for i,a in ipairs(actions)do r:button(labels and a[1]or'',b.x+(i-1)*(bw+8),16,bw,50,a[3],false,{icon=a[2],size=14,tooltip=a[1]})end
    elseif m.page=='builder'then
        local bw=L.compact and 80 or 108;local x=b.x+b.w-2*bw-8
        for i,name in ipairs({'Classic','Simplified'})do r:button(name,x+(i-1)*(bw+8),23,bw,36,function()m:setBuilderLayout(name)end,(m.settings.builderLayout or'Classic')==name,{size=14,tooltip=name..' deck builder layout'})end
    end
end
function Navigation.toggleBorder(v)
    local s=v.m.settings
    s.windowMode=s.windowMode=='Borderless'and'Windowed'or'Borderless';s.resolution='Desktop'
    if v.preferences then v.preferences:apply(true)end
    -- Native fullscreen windows cannot have decorations; a maximized desktop-
    -- sized window is the decorated counterpart to borderless fullscreen.
    if s.windowMode=='Windowed'and love.window.maximize then love.window.maximize();require('app.assets').invalidateRasterCaches()end
end
function Navigation.build(v,w,h)
    local S,m=v.S,v.m;local L=Navigation.layout(w,m.page,m.game~=nil)
    local x,y=Layout.mouse();local otherModal=m.settingsOpen or m.inspectCard or m.zoneView or m.galleryInspect or m.cardPrintingPicker or m.tokenPicker or v.deckSelection or v.themeColorEdit or m.storagePurgePreview or m.confirmConcede
    if m.page=='table'or(otherModal and not v.brandMenu)then v.brandMenu=nil end
    if m.page~='table'and not otherModal and S.IsMouseClicked(2)and contains(L.brand,x,y)then
        v.brandMenu=not v.brandMenu and{x=L.brand.x,y=72,w=254,h=152}or nil
    elseif v.brandMenu and(S.IsMouseClicked(1)or S.IsMouseClicked(2))and not contains(v.brandMenu,x,y)then v.brandMenu=nil end
    if v.brandMenu and S.IsKeyPressed and S.IsKeyPressed('escape')then v.brandMenu=nil end
    if m.page=='builder'and m.editDeck then
        local b=L.dynamic;local width=math.max(90,b.w-2*(L.compact and 80 or 108)-24)
        if width>=90 then
            v:window('navbar-deck-context',b.x,b.y,width,54,nil,{Border=0,BgColor={0,0,0,0},AutoSizeContent=false,AllowFocus=true})
            if S.Input('deck-name',{Text=m.editDeck.name,W=width,H=29,Align='left',Tooltip=m.editDeck.name..'\nLegal cards for your format. Double-click or drag to add.'})then m.editDeck.name=S.GetInputText();m.dirty=true end
            S.PushFont(v.r.fonts[11]);S.Text(v.r:fit(width<260 and'Double-click / drag to add'or'Legal cards for your format · double-click or drag to add',width,11,1),{Color=v.r.colors.muted});S.PopFont();S.EndWindow()
        end
    end
    if not v.brandMenu then return end
    local p=v.brandMenu
    v:window('app-brand-menu',p.x,p.y,p.w,p.h,nil,{Layer='ContextMenu',Border=8,AutoSizeContent=false})
    local actions={{'Border Toggle','window-borders',function()Navigation.toggleBorder(v)end,'Toggle window borders; bordered mode stays maximized'},{'Minimize','window-minimize',function()love.window.minimize()end,'Minimize the application'},{'Exit','window-close',function()love.event.quit()end,'Exit through the normal save and shutdown flow'}}
    for _,a in ipairs(actions)do
        if S.Button(a[1],{W=p.w-16,H=38,Image={Image=v.r.assets:buttonImage(a[2],a[1],p.w-16,38,{font=v.r.fonts[16],iconSize=18})},Tooltip=a[4]})then v.brandMenu=nil;a[3]()end
    end
    S.EndWindow()
end
return Navigation
