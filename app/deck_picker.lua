local Assets=require('app.assets')
local Layout=require('app.layout')
local UI={cache={},clock=0}
local function tile(v,deck,w,h)
    local cover=deck and v.m:deckCoverCard(deck);local art=cover and v.m:getArt(cover,true,'art_crop')
    local colors=deck and(deck.colorIdentity or deck.colors)or{}
    local key=table.concat({Assets.rasterEpoch,tostring(art),deck and deck.id or'',deck and deck.name or'',table.concat(colors),w,h,Layout.scale,tostring(v.r.fonts[16])},':')
    UI.clock=UI.clock+1;local cached=UI.cache[key];if cached then cached.used=UI.clock;return cached.image end
    local image=Assets.rasterize(w*Layout.scale,h*Layout.scale,function()
        love.graphics.scale(Layout.scale);v.r.assets:control(0,0,w,h,'dark')
        local square=h-14
        if art then
            love.graphics.setScissor(7*Layout.scale,7*Layout.scale,square*Layout.scale,square*Layout.scale)
            local scale=math.max(square/art:getWidth(),square/art:getHeight());love.graphics.setColor(1,1,1,1)
            love.graphics.draw(art,7+(square-art:getWidth()*scale)/2,7+(square-art:getHeight()*scale)/2,0,scale,scale)
            love.graphics.setScissor()
        else v.r.assets:iconSymbol('library',15,15,square-16,v.r.colors.accent)end
        local x=square+18;local width=w-x-12
        v.r:strong(v.r:fit(deck and deck.name or'Choose a deck',width,16,2),x,9,16,v.r.colors.text,width)
        if deck and not deck.colorIdentity and not deck.colors then v.r:text('Color identity pending',x,h-27,10,v.r.colors.muted,width)
        elseif deck and #colors==0 then v.r.assets:mana('C',x,h-29,19)
        else for i,symbol in ipairs(colors)do v.r.assets:mana(symbol,x+(i-1)*25,h-29,19)end end
    end)
    UI.cache[key]={image=image,used=UI.clock};local n=0;for _ in pairs(UI.cache)do n=n+1 end
    if n>96 then local oldest,stamp;for candidate,e in pairs(UI.cache)do if not stamp or e.used<stamp then oldest,stamp=candidate,e.used end end;UI.cache[oldest]=nil end
    return image
end
function UI.button(v,id,deckId,format,width,changed)
    local deck=v.m:findDeck(deckId)
    if v.S.Button(id,{W=width,H=84,Image={Image=tile(v,deck,width,84)},Tooltip=deck and(deck.name..' · '..format..' · choose another deck')or('Choose '..format..' deck')})then
        v.deckSelection={id=id,selected=deckId,format=format,changed=changed,search=''}
    end
end
function UI.popup(v,w,h)
    local state=v.deckSelection;if not state then return end
    local S=v.S;local width=math.min(1000,w-70);local height=math.min(670,h-110);local inner=width-32
    v:window('choose-deck-tiles',(w-width)/2,(h-height)/2,width,height,'Choose '..state.format..' deck')
    if S.Button('Close deck selection',{W=inner,H=30})then v.deckSelection=nil;S.EndWindow();return end
    if S.Input('deck-tile-search',{Text=state.search,W=inner,H=30,Align='left',Tooltip='Search decks'})then state.search=S.GetInputText()end
    S.NewLine();S.BeginListBox('deck-tiles',{W=inner,H=height-124})
    local columns=width>=780 and 2 or 1;local tw=math.floor((inner-28-(columns-1)*12)/columns);local index=0
    for _,deck in ipairs(v.m.decks or{})do
        if deck.format:lower()==state.format:lower()and deck.name:lower():find(state.search:lower(),1,true)then
            if index%columns~=0 then S.SameLine({Pad=8})elseif index>0 then S.NewLine()end
            S.PushID('tile-'..deck.id)
            if S.Button(deck.name,{W=tw,H=100,Image={Image=tile(v,deck,tw,100)},Tooltip=deck.description,Active=state.selected==deck.id})then
                state.changed(deck.id);v.deckSelection=nil
            end
            S.PopID();index=index+1
        end
    end
    if index==0 then S.Text('No matching decks',{Color=v.r.colors.muted})end
    S.EndListBox();S.EndWindow()
end
return UI
