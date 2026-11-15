local Model=require('app.model')
local palette={text={.90,.94,.98},muted={.46,.56,.66},accent={.28,.89,.72},gold={.98,.74,.34},red={1,.39,.40}}
local Builder={}
local formats={'Modern','Standard','Pioneer','Commander'}
local function clamp(n,a,b)return math.max(a,math.min(b,n))end
function Builder.layout(w,h,mode,splitRatio)
    if mode=='Simplified'then return require('app.builder_simplified').layout(w,h,splitRatio)end
    local margin,gap,top=24,26,100
    local previewW=w>=1200 and clamp(w*.20,240,320) or 0
    local deckW=clamp(w*.31,328,448)
    local searchW=w-margin*2-14-deckW-gap-(previewW>0 and previewW+gap or 0)
    if searchW<280 then deckW=math.max(250,w*.38);searchW=w-margin*2-14-deckW-gap end
    local deckX=margin+searchW+gap
    local gridY=top+258;local gridH=h-gridY-58
    local columns=math.max(2,math.floor((searchW+14)/154))
    local rows=gridH>=440 and 2 or 1
    local cardW=math.min((searchW-(columns-1)*14)/columns,(gridH/rows-33)/1.4)
    cardW=math.max(60,cardW)
    return {search={x=margin,y=top,w=searchW,h=230},grid={x=margin,y=gridY,w=searchW,h=gridH},
        controls={x=deckX,y=top,w=deckW,h=190},list={x=deckX,y=top+224,w=deckW,h=h-top-262},
        preview=previewW>0 and {x=deckX+deckW+gap,y=top,w=previewW,h=h-top-38} or nil,
        columns=columns,rows=rows,cardW=cardW,cardH=cardW*1.4,pageSize=columns*rows}
end
local function short(text,length)
    if #text<=length then return text end
    while length>0 and text:byte(length+1)>=128 and text:byte(length+1)<192 do length=length-1 end
    return text:sub(1,length)..'…'
end
local colorNames={W='White',U='Blue',B='Black',R='Red',G='Green',C='Colorless',All='All'}
local function iconButton(v,label,icon,width,height,options)
    options=options or {};local opts={};for key,value in pairs(options)do opts[key]=value end
    local tint=opts.LabelColor or (v.r.colors or palette).text
    opts.LabelColor=nil;opts.W=width;opts.H=height;opts.Tooltip=opts.Tooltip or label
    opts.Image={Image=v.r.assets:buttonImage(icon,label,width,height,{font=v.r.fonts[16],iconSize=18,color=tint})}
    return v.S.Button(label,opts)
end
local function space(v,pixels)
    local _,y=v.S.GetCursorPos({Absolute=true});v.S.SetCursorPos(nil,y+(pixels or 6),{Absolute=true})
end
local function combo(v,id,label,value,items,width,changed)

    local S=v.S;local x,y=S.GetCursorPos({Absolute=true})
    local icon='filter'
    if id=='builder-color' then icon=value~='All' and value or 'filter'
    elseif id=='builder-type' then icon=value~='All' and tostring(value):lower() or 'filter'
    elseif id=='builder-sort' or id=='builder-list-sort' then icon='sort'
    elseif id=='builder-deck-format' then icon='library' end
    local shown=id=='builder-color' and (colorNames[value] or value) or value
    if iconButton(v,label..': '..tostring(shown)..'  ▾',icon,width,34,{Tooltip=label}) then
        if v.builderPopup and v.builderPopup.id==id then v.builderPopup=nil
        else v.builderPopup={id=id,x=x,y=y+38,w=math.max(240,width),items=items,changed=changed,query=''} end
    end
end
local function popup(v,w,h)
    local p=v.builderPopup;if not p then return end
    local S=v.S;local width=math.min(430,math.max(260,p.w));local height=math.min(450,h-70)
    v:window('builder-choice-popup',clamp(p.x,16,w-width-16),clamp(p.y,88,h-height-16),width,height)
    if S.Button('Close selection',{W=width-24,H=32}) then v.builderPopup=nil end
    if S.Input('filter-selection',{Text=p.query,W=width-24,H=32,Align='left',Tooltip='Filter choices'}) then p.query=S.GetInputText() end
    S.Separator()
    for i,item in ipairs(p.items) do
        local label=type(item)=='table' and item.label or item
        local value=type(item)=='table' and item.value or item
        if p.query=='' or tostring(label):lower():find(p.query:lower(),1,true) then
            S.PushID('builder-select-'..i)
            local icon=p.id=='builder-color' and value~='All' and value or p.id=='builder-type' and value~='All' and tostring(value):lower() or nil
            local shown=p.id=='builder-color' and (colorNames[value] or label) or label
            local selected=icon and iconButton(v,tostring(shown),icon,width-24,32) or not icon and S.Button(tostring(shown),{W=width-24,H=32})
            if selected then p.changed(value);v.builderPopup=nil end
            S.PopID()
        end
    end
    S.EndWindow()
end
local function sortedEntries(m,zone)
    local entries={};for _,entry in ipairs(m.editDeck[zone] or {})do entries[#entries+1]=entry end
    local function key(entry)
        local card=m:cardData(entry) or entry
        if m.deckSort=='Color' then
            local colors=card.color_identity or {};local order={W=1,U=2,B=3,R=4,G=5}
            return tostring(#colors==0 and 0 or #colors>1 and 6 or order[colors[1]] or 7)..table.concat(colors)..entry.name
        elseif m.deckSort=='Set' then return (card.set or 'zzz')..entry.name end
        return entry.name
    end
    table.sort(entries,function(a,b)return key(a)<key(b)end);return entries
end
function Builder.build(v,w,h)
    if v.m.settings.builderLayout=='Simplified'then return require('app.builder_simplified').build(v,w,h)end
    local RichText=require('app.richtext')
    local C=v.r.colors or palette
    local S,m=v.S,v.m;local deck=m.editDeck;if not deck then return end
    local l=Builder.layout(w,h);m:setSearchLimit(l.pageSize)
    local content=l.search.w-24
    v:window('builder-search',l.search.x,l.search.y,l.search.w,l.search.h)
    if S.Input('query',{Text=m.search,W=content,H=36,Align='left',Tooltip='Search card names, rules and types'}) then m.search=S.GetInputText();m:searchChanged() end
    space(v,6)
    local half=(content-16)/2
    combo(v,'builder-format','Format',m.searchFormat,formats,half,function(value)m.searchFormat=value;m.searchSet='All';m:searchChanged();m:refreshSets()end);S.SameLine({Pad=12})
    combo(v,'builder-color','Color',m.searchColor,{'All','W','U','B','R','G','C'},half,function(value)m:setSearchColor(value)end)
    space(v,6)
    combo(v,'builder-type','Type',m.searchType=='' and 'All' or m.searchType,{'All','Creature','Instant','Sorcery','Artifact','Enchantment','Planeswalker','Land','Battle'},half,function(value)m.searchType=value=='All' and '' or value;m:searchChanged()end);S.SameLine({Pad=12})
    combo(v,'builder-sort','Sort',m.searchSort,{'Name','Color','Set'},half,function(value)m.searchSort=value;m:searchChanged()end)
    space(v,6)
    local setItems={{label='All sets',value='All'}};local selected='All sets'
    for _,set in ipairs(m.sets)do local label=set.name..' ['..set.code:upper()..']';setItems[#setItems+1]={label=label,value=set.code};if set.code==m.searchSet then selected=set.code:upper()end end
    combo(v,'builder-set','Set',selected,setItems,content,function(value)m.searchSet=value;m:searchChanged()end)
    S.EndWindow()
    local d=l.controls;local dw=d.w-24
    v:window('builder-deck-controls',d.x,d.y,d.w,d.h)
    combo(v,'builder-deck-format','Deck',deck.format,formats,dw-114,function(value)m:changeDeckFormat(value)end);S.SameLine({Pad=12})
    if iconButton(v,m.dirty and 'Save *' or 'Save','save',98,34)then m:saveDeck()end
    space(v,6)
    local zones=(deck.format=='Commander' or Model.count(deck,'commander')>0) and {'main','commander','sideboard'} or {'main','sideboard'}
    local zoneLabels={main='Main',commander='Cmd',sideboard='Side'}
    for i,zone in ipairs(zones)do
        if i>1 then S.SameLine()end
        if iconButton(v,zoneLabels[zone]..' '..Model.count(deck,zone),({main='library',commander='commander',sideboard='sideboard'})[zone],(dw-(#zones-1)*8)/#zones,34,{Color=m.selectedSection==zone and {.13,.37,.34,1} or nil})then m.selectedSection=zone end
    end
    space(v,6)
    local total=Model.count(deck,'main')+Model.count(deck,'commander')
    S.Text(total..(deck.format=='Commander' and '/100 cards' or ' main / 60 minimum')..' · '..Model.count(deck,'sideboard')..' sideboard',{Color=C.muted})
    space(v,6)
    local validateW=math.floor((dw-48)*.46);local previewW=dw-48-validateW
    if iconButton(v,'Validate','check',validateW,32)then m:validateDeck()end;S.SameLine()
    if S.Button('Preview card',{W=previewW,H=32,Image={Image=v.r.assets:buttonImage('search','Preview',previewW,32)},Tooltip='Inspect preview card'})then m.inspectCard=m.previewCard or m.cards[1]end;S.SameLine()
    if S.Button('Token artwork',{W=32,H=32,Image={Image=v.r.assets:iconImage('creature',21)},Tooltip='Token artwork choices'})then
        if m.dirty then m:toast('Save this deck before choosing token artwork',true)else m:showTokenSettings(deck.id)end
    end
    S.EndWindow()
    local list=l.list
    v:window('builder-deck-list',list.x,list.y,list.w,list.h)
    combo(v,'builder-list-sort','List order',m.deckSort,{'Name','Color','Set'},list.w-24,function(value)m.deckSort=value end)
    if m.mutationBusy then S.Text('Checking card addition…',{Color=C.muted})end
    if m.lastBuilderError then S.Textf('Addition refused: '..m.lastBuilderError,{W=list.w-24,Color=C.gold})end
    local validation=m.validation
    if validation then
        S.Text(validation.saveAllowed and (validation.draft and 'INCOMPLETE DRAFT' or 'CONSTRUCTION CHECK PASSED') or 'DECK NEEDS CORRECTIONS',{Color=validation.saveAllowed and C.accent or C.red})
        for _,issue in ipairs(validation.errors or {})do S.Textf(issue.message,{W=list.w-24,Color=C.red})end
        for _,issue in ipairs(validation.warnings or {})do S.Textf(issue.message,{W=list.w-24,Color=C.gold})end
        S.Separator()
    end
    local pending
    for _,entry in ipairs(sortedEntries(m,m.selectedSection))do
        S.PushID(entry.name)
        if S.Button('−',{W=32,H=32})then pending={entry,-1}end;S.SameLine()
        if S.Button('+',{W=32,H=32})then pending={entry,1}end;S.SameLine()
        local title=tostring(entry.count)..'  '..entry.name
        local data=m:cardData(entry) or entry;local rawCost=tostring(data.mana_cost or data.manaCost or '');local cost=rawCost:match('^(.-)%s*//') or rawCost
        local _,symbolCount=tostring(cost):gsub('{','')
        local costWidth=list.w>=400 and cost~='' and symbolCount<=4 and 72 or 0
        local nameWidth=list.w-140-(costWidth>0 and costWidth+4 or 0)
        local shown=v.r:fit(title,nameWidth-12,16,1)
        if S.Button(shown,{W=nameWidth,H=32,Tooltip=entry.name})then m.previewCard={name=entry.name}end
        if m.showCardPrintings then S.SameLine();if S.Button('Edition artwork',{W=32,H=32,Image={Image=v.r.assets:iconImage('gallery',19)},Tooltip='Choose edition or alternate artwork for '..entry.name})then m:showCardPrintings(entry,m.selectedSection)end end
        if costWidth>0 then S.SameLine({CenterY=true});RichText.slab(v,'entry-mana',cost,costWidth,{size=12,iconSize=14,lineHeight=20,maxLines=1})end
        S.PopID()
    end
    if pending then m:addCard(pending[1],m.selectedSection,pending[2])end
    if #deck[m.selectedSection]==0 then S.Textf('Drag a card into this list, or double-click a card to add it.',{W=list.w-24,Color=C.muted})end
    S.Separator()
    if not validation then S.Textf('Validate the list to check format, copies and Commander restrictions.',{W=list.w-24,Color=C.muted})end
    S.EndWindow()
    local preview=m.previewCard or (v.r.hover and v.r.hover.card) or m.cards[1] or m:deckCoverCard(deck)
    if preview then m:getArt(preview,true)end
    if l.preview then
        local p=l.preview;local pw=p.w-24
        v:window('builder-card-preview',p.x,p.y,p.w,p.h)
        if preview then
            local card=m:cardData(preview) or preview;local art=m:getArt(card,true)
            local imageW=math.min(pw,(p.h-185)/1.4)
            if art then S.Image('preview-art',{Image=art,W=imageW,H=imageW*1.4})else S.Textf(m.artworkLabel and m:artworkLabel(card)or'Card image unavailable',{W=pw,Color=C.muted})end
            S.Textf(card.name or '',{W=pw,Color=C.accent})
            RichText.slab(v,'preview-cost',card.mana_cost or card.manaCost or '',pw,{size=18,lineHeight=26})
            RichText.slab(v,'preview-type',card.type_line or card.type or '',pw,{size=14,color=C.muted})
            if iconButton(v,'Add to '..m.selectedSection,'plus',pw,36)then m:addCard(card)end
            if iconButton(v,'Use as deck cover','cover',pw,34)then m:setDeckCover(card)end
            if m.showCardPrintings and iconButton(v,'Choose edition / art','gallery',pw,34)then m:showCardPrintings(card,m.selectedSection)end
            if iconButton(v,'Inspect full card','search',pw,32)then m.inspectCard=card end
            RichText.slab(v,'preview-oracle',card.oracle_text or card.rules or '',pw,{size=14,color=C.text})
            if card.legalities and card.legalities[deck.format:lower()]~='legal' then S.Textf('Not legal in '..deck.format..'. Saving will require removing this card.',{W=pw,Color=C.gold})end
        end
        S.EndWindow()
    end
    popup(v,w,h)
end
function Builder.draw(r,w,h)
    if r.model.settings.builderLayout=='Simplified'then return require('app.builder_simplified').draw(r,w,h)end
    local C=r.colors or palette
    local m=r.model;local l=Builder.layout(w,h);r.builderDrop=l.list
    local totalW=l.columns*l.cardW+(l.columns-1)*14;local start=l.grid.x+(l.grid.w-totalW)/2
    for i,card in ipairs(m.cards)do
        if i<=l.pageSize then
            local x=start+((i-1)%l.columns)*(l.cardW+14);local y=l.grid.y+math.floor((i-1)/l.columns)*(l.cardH+33)
            m:getArt(card,true);r:drawCard(card,x,y,l.cardW,l.cardH,{kind='search',imageOnly=true})
            local name=short(card.name,26)
            r:text(name,x,y+l.cardH+5,12,C.muted,l.cardW)
        end
    end
    if not m.catalogHealth.ready then
        r:text('Preparing card catalog…',l.grid.x,l.grid.y+20,18,C.muted,l.grid.w)
    elseif #m.cards==0 then r:text(m.searchBusy and 'Searching…' or 'No legal cards match these filters.',l.grid.x,l.grid.y+20,16,C.muted,l.grid.w)end
    local y=h-43;local step=m.searchLimit
    r:button('‹ Previous',l.grid.x,y,112,32,function()if m.offset>0 then m.offset=math.max(0,m.offset-step);m:searchCards()end end)
    r:button('Next ›',l.grid.x+l.grid.w-96,y,96,32,function()if m.offset+step<m.total then m.offset=m.offset+step;m:searchCards()end end)
    r:text((m.total>0 and tostring(m.offset+1)..'–'..math.min(m.offset+step,m.total) or '0')..' / '..m.total,l.grid.x+124,y+8,13,C.muted,l.grid.w-232,'center')
    if r.drag and r.drag.kind=='search' then
        local Layout=require('app.layout');local x,y=Layout.mouse();r:drawCard(r.drag.card,x-60,y-84,120,168,{noHit=true,imageOnly=true})
    end
end
return Builder
