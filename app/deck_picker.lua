local Assets=require('app.assets')
local Layout=require('app.layout')
local SetIcons=require('app.set_icons')
local SupportUI=require('app.deck_support_ui')
local UI={cache={},clock=0,pixelLimit=12*1024*1024}
local function tile(v,deck,w,h,squareTile)
    local artW=squareTile and w-14 or h-14;local artH=squareTile and h-91 or h-14
    local art=deck and v.m:deckCoverArt(deck,require('app.image_hints').forSize(artW,artH))
    local support=deck and SupportUI.status(v.m,deck)or{state='unknown'}
    local colors=deck and(deck.colorIdentity or deck.colors)or{}
    local commander=deck and(deck.faceCommander or(deck.commander and deck.commander[1]and deck.commander[1].name));if type(commander)=='table'then commander=commander.name end
    local key=table.concat({Assets.rasterEpoch,tostring(art),deck and deck.id or'',deck and deck.name or'',commander or'',table.concat(colors),w,h,Layout.scale,tostring(v.r.fonts[16]),tostring(squareTile),support.state,tostring(#(support.missingNames or{})),v.r.assets.theme and v.r.assets.theme.colorSignature or''},':')
    UI.clock=UI.clock+1;local cached=UI.cache[key];if cached then cached.used=UI.clock;return cached.image end
    local image=Assets.rasterize(w*Layout.scale,h*Layout.scale,function()
        love.graphics.scale(Layout.scale);v.r.assets:control(0,0,w,h,'dark')
        local square=squareTile and h-91 or h-14;local artW=squareTile and w-14 or square
        if art then
            love.graphics.setScissor(7*Layout.scale,7*Layout.scale,artW*Layout.scale,square*Layout.scale)
            local scale=math.min(artW/art:getWidth(),square/art:getHeight());love.graphics.setColor(1,1,1,1)
            love.graphics.draw(art,7+(artW-art:getWidth()*scale)/2,7+(square-art:getHeight()*scale)/2,0,scale,scale);love.graphics.setScissor()
        else v.r.assets:iconSymbol('library',15,15,square-16,v.r.colors.accent)end
        SupportUI.overlay(v.r,support,7,7,artW,square)
        local x=squareTile and 10 or square+18;local y=squareTile and square+12 or 9;local width=squareTile and w-20 or w-square-30
        v.r:strong(v.r:fit(deck and deck.name or'Choose a deck',width,16,(squareTile or h>=120)and 2 or 1),x,y,16,v.r.colors.text,width)
        if commander then v.r:text(v.r:fit(commander,width,11,1),x,h-43,11,v.r.colors.gold,width)end
        local cy=h-25
        if deck and not deck.colorIdentity and not deck.colors then v.r:text('Color identity pending',x,cy,10,v.r.colors.muted,width)
        elseif deck and #colors==0 then v.r.assets:mana('C',x,cy,18)
        else for i,symbol in ipairs(colors)do v.r.assets:mana(symbol,x+(i-1)*22,cy,18)end end
    end)
    UI.cache[key]={image=image,used=UI.clock,pixels=image:getWidth()*image:getHeight()};local n,pixels=0,0;for _,entry in pairs(UI.cache)do n=n+1;pixels=pixels+entry.pixels end
    while n>96 or pixels>UI.pixelLimit do local oldest,stamp;for candidate,e in pairs(UI.cache)do if candidate~=key and(not stamp or e.used<stamp)then oldest,stamp=candidate,e.used end end;if not oldest then break end;pixels=pixels-UI.cache[oldest].pixels;UI.cache[oldest]=nil;n=n-1 end
    return image
end
local function close(v,state)
    state=state or v.deckSelection;if not state then return end
    state.closed=true;v.deckSelection=nil;if v.m.lobbyDeckPicker==state then v.m.lobbyDeckPicker=nil end
end
UI.close=close
function UI.button(v,id,deckId,format,width,changed,opts)
    opts=opts or{};local height=opts.height or 84;local deck=v.m:findDeck(deckId)
    if v.S.Button(id,{W=width,H=height,Image={Image=tile(v,deck,width,height)},Tooltip=deck and(deck.name..' · '..format..' · choose another deck')or('Choose '..format..' deck')})then
        if v.deckSelection then close(v,v.deckSelection)end
        local state={id=id,selected=deckId,format=format,changed=changed,search='',offset=0,precons={},collapsed={starter=true},timer=0,openPage=v.m.page,scrollReset=true}
        v.deckSelection=state;v.m.lobbyDeckPicker=state;if v.m.loadLobbyStarters then v.m:loadLobbyStarters(state)end
    end
end
local function normalized(value)return tostring(value or''):lower():gsub('&',' and '):gsub('[%p%s]+',' ')end
local function matches(deck,state)
    if tostring(deck.format or''):lower()~=state.format:lower()then return false end
    local names={deck.name or'',deck.expansion or deck.setName or deck.set or''}
    local face=deck.faceCommander;names[#names+1]=type(face)=='table'and(face.name or'')or(face or'')
    for _,card in ipairs(deck.commander or{})do names[#names+1]=card.name or''end
    local haystack=normalized(table.concat(names,' '));local query=normalized(state.search)
    if haystack:find(query,1,true)then return true end
    for token in query:gmatch('%S+')do local found=false;for word in haystack:gmatch('%S+')do if word:sub(1,#token)==token then found=true;break end end;if not found then return false end end
    return true
end
local function header(v,state,key,label,count,defaultClosed,width,setCode)
    local closed=state.collapsed[key];if closed==nil then closed=defaultClosed or false end
    local title=label..' · '..tostring(count or 0)
    local headerImage
    if setCode then
        state.setHeaders=state.setHeaders or{};local cacheKey=table.concat({key,title,setCode,tostring(closed),width,Layout.scale,Assets.rasterEpoch,tostring(v.r.fonts[16]),v.r.assets.theme and v.r.assets.theme.colorSignature or''},'|');headerImage=state.setHeaders[cacheKey]
        if not headerImage then headerImage=Assets.rasterize(width*Layout.scale,34*Layout.scale,function()love.graphics.scale(Layout.scale);v.r.assets:control(0,0,width,34,'dark');v.r.assets:iconSymbol(closed and'expand'or'collapse',10,8,18,v.r.colors.accent);SetIcons.draw(v.r.assets,setCode,35,6,23,v.r.colors.gold,v.m.settings);v.r:strong(v.r:fit(title,width-77,16,1),66,8,16,v.r.colors.text,width-77)end);state.setHeaders[cacheKey]=headerImage;local count=0;for _ in pairs(state.setHeaders)do count=count+1 end;if count>48 then state.setHeaders={[cacheKey]=headerImage}end end
    else headerImage=v.r.assets:buttonImage(closed and'expand'or'collapse',title,width,34)end
    if v.S.Button(title,{W=width,H=34,Image={Image=headerImage},Tooltip=(closed and'Expand 'or'Collapse ')..label})then closed=not closed;state.collapsed[key]=closed end
    v.S.NewLine();return closed
end
function UI.popup(v,w,h)
    local state=v.deckSelection;if not state then return end;if state.closed then v.deckSelection=nil;return end
    local S,m=v.S,v.m;local width=math.min(1000,w-70);local height=math.min(700,h-110);local inner=width-32
    v:window('choose-deck-tiles',(w-width)/2,(h-height)/2,width,height,'Choose '..state.format..' deck',{Layer='ContextMenu',BgColor={.025,.04,.06,.99}})
    if S.Button('Close deck selection',{W=inner,H=28})then close(v,state);S.EndWindow();return end
    if S.Input('deck-tile-search',{Text=state.search,W=inner,H=30,Align='left',Tooltip='Search My Decks, Starter and preconstructed products'})then state.search=S.GetInputText();state.scrollReset=true;if m.searchLobbyPrecons then m:searchLobbyPrecons(state)end end
    S.NewLine()
    if state.supportDetails then
        local deck=state.supportDetails;S.Textf(deck.name,{W=inner-12,Color=v.r.colors.accent})
        if S.Button('Back to deck choices',{W=inner,H=30})then state.supportDetails=nil end;S.NewLine()
        S.BeginListBox('deck-support-details',{W=inner,H=math.max(120,height-216),AlwaysShowScrollBarY=true,ScrollStep=100});SupportUI.details(v,SupportUI.status(m,deck),inner-28);S.EndListBox();S.EndWindow();return
    end
    if state.confirmAuxiliary then
        local pending=state.confirmAuxiliary
        S.Textf(pending.source.name..' includes planes or schemes. These auxiliary cards are not used by '..state.format..'. The archived original will stay unchanged.',{W=inner-12,Color=v.r.colors.gold});S.NewLine()
        if S.Button('Use constructed cards',{W=(inner-8)/2,H=34})then m:cacheLobbyPrecon(state,pending.source,true)end
        S.SameLine();if S.Button('Keep browsing',{W=(inner-8)/2,H=34})then state.confirmAuxiliary=nil end;S.NewLine()
    end
    local listH=math.max(150,height-(state.confirmAuxiliary and 240 or 158))
    local Window=require('lib.Slab.Internal.UI.Window');local vx,vy=S.GetCursorPos({Absolute=true});vx,vy=Window.TransformPoint(vx,vy)
    if state.scrollReset then require('lib.Slab.Internal.UI.Region').ResetTransform(Window.GetItemId('deck-tiles'));state.scrollReset=nil end
    S.BeginListBox('deck-tiles',{W=inner,H=listH,AlwaysShowScrollBarY=true,ScrollStep=100})
    local columns=width>=780 and 4 or 3;local tw=math.floor((inner-28-(columns-1)*12)/columns);local th=tw;local selected=m:findDeck(state.selected)
    local function grid(decks,precon)
        for index,deck in ipairs(decks)do
            if(index-1)%columns~=0 then S.SameLine({Pad=8})elseif index>1 then S.NewLine()end
            S.PushID('tile-'..deck.id)
            local active=state.selected==deck.id or selected and selected.sourceDeckId==deck.id
            local tx,ty=S.GetCursorPos({Absolute=true});tx,ty=Window.TransformPoint(tx,ty)
            local visible=ty+th>=vy and ty<=vy+listH and tx+tw>=vx and tx<=vx+inner-18
            local support=visible and SupportUI.status(m,deck)or{state='unknown'}
            if S.Button(deck.name,{W=tw,H=th,Image=visible and{Image=tile(v,deck,tw,th,true)}or nil,Invisible=not visible,Tooltip=deck.name..' · '..SupportUI.label(support),Active=active,Disabled=not visible or state.detailBusy})then
                if support.state=='unavailable'then state.supportDetails=deck
                elseif precon then m:selectLobbyPrecon(state,deck)else state.changed(deck.id);close(v,state)end
            end
            S.PopID()
        end
        if #decks==0 then S.Text('No matching decks',{Color=v.r.colors.muted})end;S.NewLine()
    end
    local own,starter={},{};local originals=m.startersLoaded and m.starterDecks or nil
    for _,deck in ipairs(m.decks or{})do if matches(deck,state)then
        if deck.origin=='bundled'or deck.origin=='starter'then if not originals then starter[#starter+1]=deck end else own[#own+1]=deck end
    end end
    for _,deck in ipairs(originals or{})do if matches(deck,state)then starter[#starter+1]=deck end end
    if not header(v,state,'user','My Decks',#own,false,inner-20)then grid(own,false)end
    if not header(v,state,'starter','Starter',#starter,state.search=='',inner-20)then grid(starter,false)end
    if not header(v,state,'preconstructed','Preconstructed',state.total or#state.precons,false,inner-20)then
        local groups,order={},{}
        for _,deck in ipairs(state.precons)do local name=deck.expansion or deck.setName or deck.set or'Other products';if not groups[name]then groups[name]={};order[#order+1]=name end;groups[name][#groups[name]+1]=deck end
        for _,name in ipairs(order)do if not header(v,state,'set:'..name,name,#groups[name],true,inner-20,groups[name][1].set)then grid(groups[name],true)end end
        if state.busy or state.timer then S.Text('Loading preconstructed decks…',{Color=v.r.colors.muted})
        elseif state.error then S.Textf(state.error,{W=inner-24,Color=v.r.colors.red});if S.Button('Retry deck search',{W=200,H=28})then m:queryLobbyPrecons(state,true)end
        elseif#order==0 then S.Text('No matching preconstructed products',{Color=v.r.colors.muted})end
        if state.detailBusy then S.Text('Loading selected deck…',{Color=v.r.colors.muted})end
    end
    S.EndListBox();S.NewLine()
    if S.Button('Previous preconstructed page',{W=34,H=28,Image={Image=v.r.assets:iconImage('previous',18)},Disabled=state.busy or state.offset==0,Tooltip='Previous preconstructed page'})then state.offset=math.max(0,state.offset-24);m:queryLobbyPrecons(state)end
    S.SameLine();S.Text(tostring(math.min(state.offset+24,state.total or 0))..' / '..tostring(state.total or 0),{Color=v.r.colors.muted});S.SameLine()
    if S.Button('Next preconstructed page',{W=34,H=28,Image={Image=v.r.assets:iconImage('next',18)},Disabled=state.busy or state.offset+24>=(state.total or 0),Tooltip='Next preconstructed page'})then state.offset=state.offset+24;m:queryLobbyPrecons(state)end
    S.SameLine();S.Text('XMage checks final legality',{Color=v.r.colors.muted});S.EndWindow()
end
return UI
