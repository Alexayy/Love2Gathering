local Layout=require('app.layout')
local RichText=require('app.richtext')
local Colors=require('app.builder_colors')
local Simple={}
local function contains(box,x,y)return x>=box.x and y>=box.y and x<=box.x+box.w and y<=box.y+box.h end
function Simple.splitRatio(h,y)
    return math.max(384,math.min(h-276,y))/h
end
function Simple.layout(w,h,ratio)
    local split=math.floor(Simple.splitRatio(h,h*(ratio or .55))*h)
    local width=w-48;local formWidth=width-14;local gridY=228;local gridH=split-gridY-40
    local cardH=math.min(226,math.max(92,gridH-24));local cardW=cardH/1.4
    local columns=math.max(2,math.floor((width+14)/(cardW+14)))
    return{mode='Simplified',controls={x=24,y=100,w=formWidth,h=44},search={x=24,y=162,w=formWidth,h=44},
        grid={x=24,y=gridY,w=width,h=gridH},list={x=24,y=split+76,w=width,h=h-split-96},
        divider={x=24,y=split+3,w=width,h=10,split=split},
        deckToolbar={x=24,y=split+24,w=formWidth,h=34},columns=columns,rows=1,cardW=cardW,cardH=cardH,pageSize=columns,pagerY=split-34}
end
local function button(v,label,icon,w,h,opts)
    opts=opts or{};opts.W=w;opts.H=h;opts.Tooltip=opts.Tooltip or label
    opts.Image={Image=v.r.assets:buttonImage(icon,label,w,h,{font=v.r.fonts[16],iconSize=18})}
    return v.S.Button(label,opts)
end
local function filters(v,w,h)
    if not v.builderFiltersOpen then return end
    local S,m=v.S,v.m;local width=math.min(560,w-60);local height=math.min(450,h-100)
    v:window('simplified-more-filters',(w-width)/2,(h-height)/2,width,height,'Card filters')
    local inner=width-30
    if button(v,'Close filters','close',inner,34)then v.builderFiltersOpen=nil end
    S.NewLine();S.Text('Card type',{Color=v.r.colors.muted})
    v:combo('simple-type',m.searchType==''and'All'or m.searchType,{'All','Creature','Instant','Sorcery','Artifact','Enchantment','Planeswalker','Land','Battle'},inner,function(value)m.searchType=value=='All'and''or value;m:searchChanged()end)
    S.NewLine();S.Text('Sort',{Color=v.r.colors.muted})
    v:combo('simple-sort',m.searchSort,{'Name','Color','Set'},inner,function(value)m.searchSort=value;m:searchChanged()end)
    S.NewLine();S.Text('Set',{Color=v.r.colors.muted})
    local selected='All sets';for _,set in ipairs(m.sets or{})do if set.code==m.searchSet then selected=set.name end end
    if S.BeginComboBox('simple-set',{Selected=selected,W=inner,H=36})then
        if S.TextSelectable('All sets')then m.searchSet='All';m:searchChanged()end
        for _,set in ipairs(m.sets or{})do if S.TextSelectable(set.name..' ['..set.code:upper()..']')then m.searchSet=set.code;m:searchChanged()end end
        S.EndComboBox()
    end
    S.NewLine();if button(v,'Reset filters','refresh',inner,36)then m:setSearchColor('All');m.searchType='';m.searchSet='All';m.searchSort='Name';m:searchChanged()end
    S.EndWindow()
end
function Simple.build(v,w,h)
    local S,m=v.S,v.m;local deck=m.editDeck;if not deck then return end
    local L=Simple.layout(w,h,m.simpleBuilderSplitRatio);m:setSearchLimit(L.pageSize)
    v:window('simple-deck-controls',L.controls.x,L.controls.y,L.controls.w,L.controls.h,nil,{AutoSizeContent=false,Border=6})
    v:combo('simple-deck-format',deck.format,{'Modern','Standard','Pioneer','Commander'},150,function(value)m:changeDeckFormat(value)end)
    S.SameLine({Pad=12});if button(v,m.dirty and'Save *'or'Save','save',96,36)then m:saveDeck()end
    S.SameLine({Pad=12});if button(v,'Validate','check',108,36)then m:validateDeck()end
    S.SameLine({Pad=12});if button(v,'Preview','search',100,36)then m.inspectCard=m.previewCard or m.cards[1]end
    if m.showCardPrintings then S.SameLine({Pad=12});if button(v,'Choose art','gallery',128,36)then m:showCardPrintings(m.previewCard or m.cards[1],m.selectedSection)end end
    S.EndWindow()
    v:window('simple-search',L.search.x,L.search.y,L.search.w,L.search.h,nil,{AutoSizeContent=false,Border=6})
    local inputW=math.max(160,L.search.w-30-596)
    if S.Input('query',{Text=m.search,W=inputW,H=36,Align='left',Tooltip='Search cards in '..deck.format})then m.search=S.GetInputText();m:searchChanged()end
    for _,symbol in ipairs({'All','W','U','B','R','G','C'})do
        S.SameLine({Pad=8})
        local tooltip=symbol=='All'and'Clear color filters' or symbol=='C'and'Colorless identity only' or'Toggle '..Colors.names[symbol]..' identity; selected colors are combined with OR'
        if S.Button('simple-color-'..symbol,{W=36,H=36,Image={Image=v.r.assets:iconImage(symbol=='All'and'filter'or symbol,23)},Active=Colors.selected(m,symbol),Tooltip=tooltip})then m:toggleSearchColor(symbol)end
    end
    S.SameLine({Pad=12})
    if button(v,'Exact','filter',100,36,{Active=m.searchColorExact,Disabled=Colors.symbols(m)=='',Tooltip='Exact color identity: require every selected color and exclude all other colors. '..Colors.summary(m)})then m:toggleExactSearchColors()end
    S.SameLine({Pad=12});if button(v,'More filters','filter',128,36)then v.builderFiltersOpen=not v.builderFiltersOpen end
    S.EndWindow()
    v:window('simple-deck-toolbar',L.deckToolbar.x,L.deckToolbar.y,L.deckToolbar.w,L.deckToolbar.h,nil,{AutoSizeContent=false,Border=6})
    local zones=(deck.format=='Commander'or m.count(deck,'commander')>0)and{'main','commander','sideboard'}or{'main','sideboard'}
    for i,zone in ipairs(zones)do
        if i>1 then S.SameLine({Pad=8})end
        if button(v,({main='Main',commander='Commander',sideboard='Sideboard'})[zone]..' '..m.count(deck,zone),({main='library',commander='commander',sideboard='cards'})[zone],152,34,{Active=m.selectedSection==zone})then m.selectedSection=zone;m.simpleDeckScroll=0 end
    end
    S.SameLine({Pad=20})
    local text=m.mutationBusy and'Checking addition…'or m.lastBuilderError or(m.validation and(m.validation.saveAllowed and(m.validation.draft and'Incomplete deck'or'Deck check passed')or'Deck needs corrections'))or''
    S.Text(v.r:fit(text,math.max(200,L.deckToolbar.w-#zones*160-70),13,1),{Color=m.lastBuilderError and v.r.colors.gold or v.r.colors.muted})
    S.EndWindow();filters(v,w,h)
end
local function groups(m)
    local indexed,order={},{}
    for _,entry in ipairs(m.editDeck[m.selectedSection]or{})do
        local data=m:cardData(entry)or entry
        local land=tostring(data.type_line or data.type or''):lower():find('land',1,true)
        local cmc=tonumber(data.cmc);local key=land and'Lands'or(cmc and tostring(math.min(7,math.floor(cmc)))or'Other')
        if not indexed[key]then indexed[key]={};order[#order+1]=key end
        indexed[key][#indexed[key]+1]=entry
    end
    table.sort(order,function(a,b)if a=='Lands'then return false elseif b=='Lands'then return true elseif a=='Other'then return false elseif b=='Other'then return true else return tonumber(a)<tonumber(b)end end)
    for _,list in pairs(indexed)do table.sort(list,function(a,b)return a.name<b.name end)end
    return indexed,order
end
function Simple.draw(r,w,h)
    local m=r.model;local C=r.colors;local L=Simple.layout(w,h,m.simpleBuilderSplitRatio);r.builderDrop=L.list;r.simpleBuilderLayout=L
    local width=L.columns*L.cardW+(L.columns-1)*14;local start=L.grid.x+(L.grid.w-width)/2
    for i,card in ipairs(m.cards)do if i<=L.pageSize then
        local x=start+(i-1)*(L.cardW+14)
        r:drawCard(card,x,L.grid.y,L.cardW,L.cardH,{kind='search',imageOnly=true})
        r:text(r:fit(card.name,L.cardW,12,1),x,L.grid.y+L.cardH+4,12,C.muted,L.cardW)
    end end
    if not m.catalogHealth.ready then r:text('Preparing card catalog…',L.grid.x,L.grid.y+20,18,C.muted,L.grid.w)
    elseif#m.cards==0 then r:text(m.searchBusy and'Searching…'or'No matching cards',L.grid.x,L.grid.y+20,16,C.muted,L.grid.w)end
    r:button('Previous',L.grid.x,L.pagerY,110,30,function()if m.offset>0 then m.offset=math.max(0,m.offset-m.searchLimit);m:searchCards()end end)
    r:button('Next',L.grid.x+L.grid.w-110,L.pagerY,110,30,function()if m.offset+m.searchLimit<m.total then m.offset=m.offset+m.searchLimit;m:searchCards()end end)
    r:text((m.total>0 and(m.offset+1)..'–'..math.min(m.offset+m.searchLimit,m.total)or'0')..' / '..m.total,L.grid.x+130,L.pagerY+7,13,C.muted,L.grid.w-260,'center')
    local divider=L.divider;local hot=contains(divider,Layout.mouse())
    love.graphics.setColor(hot and C.accent or C.line);love.graphics.rectangle('fill',divider.x,divider.y+4,divider.w,2,1,1)
    r.assets:iconSymbol('pan',divider.x+divider.w/2-9,divider.y-3,18,hot and C.accent or C.muted)
    r:hit({x=divider.x,y=divider.y-4,w=divider.w,h=18,kind='builder-divider',split=divider.split,tooltip='Drag to resize the card browser and deck area'})
    if hot then r.assets:setInteractionCursor('sizens')end
    r:panel(L.list.x,L.list.y,L.list.w,L.list.h,'dark')
    local indexed,order=groups(m);local n=#order
    if n==0 then r:text('Drag cards here to add them to '..m.selectedSection..'.',L.list.x+20,L.list.y+24,16,C.muted,L.list.w-40)end
    local gap=14;local landGap=indexed.Lands and n>1 and 24 or 0
    local cw=math.min(146,math.max(48,(L.list.h-44)/1.4),math.max(72,(L.list.w-32-gap*math.max(0,n-1)-landGap)/math.max(1,n)));local ch=cw*1.4
    local step=math.max(26,ch*.21);local scroll=m.simpleDeckScroll or 0;local x=L.list.x+16;local maximum=0
    Layout.clip(L.list.x,L.list.y,L.list.w,L.list.h)
    for _,key in ipairs(order)do
        if key=='Lands'and n>1 then x=x+landGap end
        local label=key=='7'and'7+'or key
        r:strong(label,x,L.list.y+7,14,C.accent,cw)
        for i,entry in ipairs(indexed[key])do
            local y=L.list.y+35+(i-1)*step-scroll
            if y+ch>=L.list.y+30 and y<L.list.y+L.list.h then
                r:drawCard(entry,x,y,cw,ch,{kind='builder-card',section=m.selectedSection,clip={x=L.list.x,y=L.list.y+30,w=L.list.w,h=L.list.h-30}})
                r:panel(x+cw-34,y+3,30,23,'dark');r:strong(entry.count,x+cw-33,y+4,14,C.text,28,'center')
                r:hit({x=x,y=y,w=cw,h=math.min(step,ch),kind='builder-card',section=m.selectedSection,card=entry,clip={x=L.list.x,y=L.list.y+30,w=L.list.w,h=L.list.h-30},tooltip=entry.name..' · '..entry.count..' copies · right-click for details, double-click to remove one'})
                if m.showCardPrintings then
                    local iconX,iconY=x+cw-24,y+math.min(step,ch)-22
                    r.assets:control(iconX,iconY,22,22,'dark');r.assets:iconSymbol('gallery',iconX+3,iconY+3,16,C.accent)
                    r:hit({x=iconX,y=iconY,w=22,h=22,clip={x=L.list.x,y=L.list.y+30,w=L.list.w,h=L.list.h-30},kind='printing-art',action=function()m:showCardPrintings(entry,m.selectedSection)end,tooltip='Choose edition or alternate artwork for '..entry.name})
                end
            end
        end
        maximum=math.max(maximum,35+math.max(0,#indexed[key]-1)*step+ch);x=x+cw+gap
    end
    Layout.clip();m.simpleDeckScrollMax=math.max(0,maximum-L.list.h+12);m.simpleDeckScroll=math.min(scroll,m.simpleDeckScrollMax)
    if r.drag and r.drag.kind=='search'then local x,y=Layout.mouse();r:drawCard(r.drag.card,x-60,y-84,120,168,{noHit=true,imageOnly=true})end
end
function Simple.wheel(m,L,x,y,dy)
    if contains(L.list,x,y)then m.simpleDeckScroll=math.max(0,math.min(m.simpleDeckScrollMax or 0,(m.simpleDeckScroll or 0)-dy*42));return true end
    return false
end
return Simple
