local Layout=require('app.layout')
local Collection=require('app.collection')
local UI={}
local function tint(c,a)love.graphics.setColor(c[1],c[2],c[3],a or c[4]or 1)end
local function match(m,deck)
    local format=Collection.format(m)
    if format~='All'and tostring(deck.format):lower()~=format:lower()then return false end
    local query=(m.collectionSearch or''):lower()
    return query==''or table.concat({deck.name or'',deck.description or'',deck.expansion or'',deck.faceCommander or''},' '):lower():find(query,1,true)~=nil
end
function UI.layout(w,h)
    local side=306;local width=w-side-82;local columns=math.max(2,math.min(6,math.floor(width/218)))
    return{x=28,y=201,w=width,h=h-219,sideX=w-side-28,sideW=side,columns=columns,tile=(width-(columns-1)*16)/columns}
end
local function tile(r,m,d,x,y,size,L)
    local C=r.colors;local selected=m.selectedDeck==d.id
    r:panel(x,y,size,size,selected and'accent'or'dark')
    local cover=d.cover or(m.deckCoverCard and m:deckCoverCard(d))
    if type(cover)=='string'then cover={name=cover}end
    local art=cover and m:getArt(cover,true,'art_crop')
    local artH=size-91
    if art then
        local scale=math.min((size-10)/art:getWidth(),artH/art:getHeight())
        tint({1,1,1});love.graphics.draw(art,x+(size-art:getWidth()*scale)/2,y+5+(artH-art:getHeight()*scale)/2,0,scale,scale)
    else r.assets:iconSymbol('library',x+size/2-23,y+artH/2-18,46,C.muted)end
    tint({.015,.025,.045},.9);love.graphics.rectangle('fill',x+4,y+size-86,size-8,82,3,3)
    r:strong(r:fit(d.name or'Deck',size-24,16,2),x+12,y+size-81,16,C.text,size-24)
    local commander=d.faceCommander or(d.commander and d.commander[1]and d.commander[1].name)
    if type(commander)=='table'then commander=commander.name end
    if commander then r:text(r:fit(commander,size-24,11,1),x+12,y+size-43,11,C.gold,size-24)end
    local colors=d.colorIdentity or d.colors
    if colors then
        if #colors==0 then r.assets:mana('C',x+12,y+size-24,17)
        else for i,symbol in ipairs(colors)do r.assets:mana(symbol,x+12+(i-1)*21,y+size-24,17)end end
    end
    local count=d.cardCount or d.mainCount or(d.counts and((d.counts.main or 0)+(d.counts.commander or 0)))or(m.count(d,'main')+m.count(d,'commander'))
    r:text(tostring(count)..' cards',x+size-83,y+size-22,11,C.muted,71,'right')
    if selected then r.assets:iconSymbol('check',x+size-26,y+10,18,C.accent)end
    r:hit({x=x,y=y,w=size,h=size,kind='deck',deck=d,clip={x=L.x,y=L.y,w=L.w,h=L.h},action=function()m:selectCollectionDeck(d)end,tooltip=d.name})
end
local function title(r,m,key,label,count,y,L,depth)
    local C=r.colors;local x=L.x+(depth or 0)*14;local width=L.w-(depth or 0)*14
    local closed=Collection.sections(m)[key]==true
    r.assets:control(x,y,width,44,closed and'dark'or'accent')
    r.assets:iconSymbol(closed and'expand'or'collapse',x+10,y+11,22,C.accent)
    r:strong(label,x+43,y+12,18,C.text,width-110)
    r:strong(tostring(count or 0),x+width-66,y+13,16,C.muted,48,'right')
    r:hit({x=x,y=y,w=width,h=44,clip={x=L.x,y=L.y,w=L.w,h=L.h},action=function()m:toggleCollectionSection(key)end,kind='collection-section',section=key})
    return closed
end
function UI.draw(r,w,h)
    local m=r.model;local C=r.colors;local L=UI.layout(w,h)
    for i,f in ipairs(Collection.formats)do
        local width=math.min(112,(L.w-25)/6);local x=L.x+(i-1)*(width+5)
        r:button(f,x,101,width,31,function()m:setCollectionFormat(f)end,Collection.format(m)==f)
    end
    if m.collectionScrollReset then r.deckScroll=0;m.collectionScrollReset=nil end
    local y=L.y-(r.deckScroll or 0);local groups={{key='user',name='My Decks',decks={}},{key='starter',name='Starter',decks={}}}
    for _,deck in ipairs(m.decks or{})do if match(m,deck)then
        if deck.origin=='user'then groups[1].decks[#groups[1].decks+1]=deck
        elseif not m.starterDecks then groups[2].decks[#groups[2].decks+1]=deck end
    end end
    for _,deck in ipairs(m.starterDecks or{})do if match(m,deck)then groups[2].decks[#groups[2].decks+1]=deck end end
    Layout.clip(L.x-2,L.y,L.w+4,L.h)
    local function grid(decks)
        for i,d in ipairs(decks)do
            local rowY=y+math.floor((i-1)/L.columns)*(L.tile+16)
            if rowY+L.tile>=L.y and rowY<=L.y+L.h then tile(r,m,d,L.x+((i-1)%L.columns)*(L.tile+16),rowY,L.tile,L)end
        end
        y=y+math.ceil(#decks/L.columns)*(L.tile+16)
    end
    for _,group in ipairs(groups)do
        local closed=title(r,m,group.key,group.name,#group.decks,y,L);y=y+56
        if not closed then if #group.decks>0 then grid(group.decks)else r:text('No decks',L.x+14,y+3,13,C.muted);y=y+33 end end
        y=y+12
    end
    local closed=title(r,m,'preconstructed',m.preconCategory=='packet'and'Preconstructed · Packets'or'Preconstructed',m.preconsTotal,y,L);y=y+56
    if not closed then
        local order,sets={},{}
        for _,d in ipairs(m.precons or{})do
            local expansion=d.expansion or d.setName or d.set or'Other products'
            if not sets[expansion]then sets[expansion]={};order[#order+1]=expansion end
            sets[expansion][#sets[expansion]+1]=d
        end
        for _,expansion in ipairs(order)do
            local folded=title(r,m,'set:'..expansion,expansion,#sets[expansion],y,L,1);y=y+54
            if not folded then grid(sets[expansion])end
        end
        if #order==0 then r:text(m.preconsBusy and'Loading preconstructed decks…'or m.preconError or'No matching preconstructed decks',L.x+14,y+5,14,C.muted,L.w-28);y=y+60 end
    end
    Layout.clip();r.deckScrollMax=math.max(0,y+(r.deckScroll or 0)-L.y-L.h);r.deckScroll=math.max(0,math.min(r.deckScroll or 0,r.deckScrollMax))
    local selected=m:collectionDeck(m.selectedDeck)
    r:panel(L.sideX,L.y,L.sideW,L.h,'dark')
    if not selected then r:strong('Deck details',L.sideX+16,L.y+15,20,C.text,L.sideW-32)end
end
function UI.build(v,w,h)
    local S,m=v.S,v.m;local L=UI.layout(w,h)
    v:window('collection-search',24,143,L.w+8,34)
    if S.Input('collection-query',{Text=m.collectionSearch or'',W=L.w-180,H=28,Align='left',Tooltip='Search deck names, expansion or commander'})then m.collectionSearch=S.GetInputText();m:collectionSearchChanged()end
    S.SameLine()
    if S.Button('Previous precons',{Image={Image=v.r.assets:iconImage('previous',18)},W=30,H=28,Disabled=m.preconsBusy or(m.preconOffset or 0)==0,Tooltip='Previous preconstructed page'})then m:pagePrecons(-1)end
    S.SameLine()
    if S.Button('Next precons',{Image={Image=v.r.assets:iconImage('next',18)},W=30,H=28,Disabled=m.preconsBusy or(m.preconOffset or 0)+24>=(m.preconsTotal or 0),Tooltip='Next preconstructed page'})then m:pagePrecons(1)end
    S.SameLine();S.Text(tostring(math.min((m.preconOffset or 0)+24,m.preconsTotal or 0))..'/'..tostring(m.preconsTotal or 0),{Color=v.r.colors.muted});S.EndWindow()
    v:window('collection-formats',L.sideX,101,L.sideW,77)
    local formats={'All'};for _,entry in ipairs(m.preconStats and m.preconStats.formats or{})do formats[#formats+1]=entry.id end;formats[#formats+1]='Archive'
    v:combo('historical-format',Collection.format(m),formats,L.sideW-30,function(value)m:setCollectionFormat(value)end)
    if S.Button('Deck products',{W=(L.sideW-38)/2,H=27,Active=m.preconCategory~='packet',Tooltip='Complete preconstructed deck products'})then m.preconCategory='deck';m.preconTimer=0;m.preconOffset=0 end
    S.SameLine();if S.Button('Packets',{W=(L.sideW-38)/2,H=27,Active=m.preconCategory=='packet',Tooltip='Jumpstart and other partial-deck packets'})then m.preconCategory='packet';m:setCollectionFormat('All')end
    S.EndWindow()
    local d=m:collectionDeck(m.selectedDeck);if not d then return end
    v:window('collection-details',L.sideX+7,L.y+7,L.sideW-14,L.h-14)
    S.Textf(d.name or'Deck',{W=L.sideW-42,Color=v.r.colors.accent});S.Separator()
    if d.expansion or d.setName then S.Textf(d.expansion or d.setName,{W=L.sideW-42,Color=v.r.colors.muted})end
    if d.productType then S.Textf(d.productType,{W=L.sideW-42,Color=v.r.colors.muted})end
    S.Textf(tostring(d.historicalFormat or d.format or'Archive')..(d.format=='Archive'and' · original format'or''),{W=L.sideW-42,Color=v.r.colors.gold})
    local actionW=L.sideW-42
    if S.Button('Edit deck',{Image={Image=v.r.assets:buttonImage('edit','Edit deck',actionW,32)},W=actionW,H=32,Disabled=m.collectionForkBusy or m.preconDetailBusy})then m:openDeck(d)end
    if S.Button('Use in lobby',{Image={Image=v.r.assets:buttonImage('play','Use in lobby',actionW,32)},W=actionW,H=32,Disabled=m.collectionForkBusy or m.preconDetailBusy})then m:useCollectionDeck(d)end
    if d.origin=='user'then
        if S.Button('Token artwork',{Image={Image=v.r.assets:buttonImage('gallery','Token artwork',actionW,30)},W=actionW,H=30})then m:showTokenSettings(d.id)end
        if S.Button('Duplicate',{W=(actionW-8)/2,H=29})then m:duplicateDeck(d)end;S.SameLine()
        if S.Button('Delete',{W=(actionW-8)/2,H=29})then m.deleteConfirm=d end
    end
    S.NewLine();S.BeginListBox('collection-description',{W=actionW,H=math.max(80,L.h-280)})
    if m.preconDetailBusy then S.Text('Loading deck…',{Color=v.r.colors.muted})end
    if d.readOnly then S.Textf('Editing creates a copy in My Decks.',{W=actionW-16,Color=v.r.colors.muted});S.NewLine()end
    local generated=(d.productType or'')..' — '..(d.expansion or'')..'; original product list, current legality unverified.'
    if d.description and d.description~=''and not(d.origin=='preconstructed'and d.description==generated)then S.Textf(d.description,{W=actionW-16,Color=v.r.colors.text});S.NewLine()end
    for _,zone in ipairs({'commander','main','sideboard','planes','schemes'})do
        if #(d[zone]or{})>0 then
            S.Text(zone,{Color=v.r.colors.gold})
            for _,card in ipairs(d[zone])do if S.TextSelectable(tostring(card.count)..' × '..card.name,{W=actionW-16})then m.inspectCard=card end end
            S.NewLine()
        end
    end
    S.EndListBox();S.EndWindow()
end
function UI.modals(v,w,h)
    local m,S=v.m,v.S;local copy=m.archiveCopy;if not copy then return end
    v:window('archive-copy',w/2-250,h/2-150,500,300,'Copy to My Decks')
    S.Textf(copy.deck.name or'Preconstructed deck',{W=466});S.NewLine()
    S.Textf('Choose a supported format for your copy. Historical product lists may need changes before they are legal today.',{W=466,Color=v.r.colors.muted});S.NewLine()
    if copy.auxiliary then S.Textf('Planes and schemes stay in the original product. This constructed copy uses its main deck, sideboard and commanders.',{W=466,Color=v.r.colors.gold});S.NewLine()end
    v:combo('archive-format',copy.format,{'Modern','Standard','Pioneer','Commander'},466,function(value)copy.format=value end)
    S.NewLine()
    if S.Button('Create copy',{W=226,H=34,Disabled=m.collectionForkBusy})then m.archiveCopy=nil;m:forkCollectionDeck(copy.deck,copy.format,copy.callback or function(deck)m:openDeck(deck)end,true)end
    S.SameLine();if S.Button('Cancel',{W=226,H=34})then m.archiveCopy=nil end
    S.EndWindow()
end
return UI
