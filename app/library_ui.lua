-- Shared supplied asset buttons; presentation only, all validation is service/native.
local UI={}
local function button(v,label,icon,w,h,options)
    options=options or{};options.W=w;options.H=h
    options.Image={Image=v.r.assets:buttonImage(icon,label,w,h,{font=v.r.fonts[14],iconSize=17})}
    return v.S.Button(label,options)
end
local function title(v,id,text,icon,w)
    v.S.Image(id..'-icon',{Image=v.r.assets:iconImage(icon,22),W=22,H=22});v.S.SameLine();v.S.Textf(text,{W=w-32,Color=v.r.colors.accent})
end
local function messages(v,items,width,color)
    for _,item in ipairs(items or{})do v.S.Textf(type(item)=='table'and(item.message or item.error or'Validation requires changes')or tostring(item),{W=width,Color=color or v.r.colors.gold})end
end
local function footer(v,w,h,text)
    v:window('library-footer',26,h-53,w-52,42)
    if button(v,'Decks','library',115,29)then v.m.page='decks'end;v.S.SameLine()
    v.S.Textf(text or'',{W=w-210,Color=v.r.colors.muted});v.S.EndWindow()
end
function UI.import(v,w,h)
    local S,m=v.S,v.m;local left=math.floor((w-66)*.47);local right=w-66-left
    v:window('import-source',26,105,left,h-170)
    title(v,'import-title','Import deck','library',left-28);S.NewLine()
    S.Textf('Paste a list or public deck link. Drop a TXT, DEC, COD, CSV or JSON export here.',{W=left-32,Color=v.r.colors.muted});S.NewLine()
    if S.BeginComboBox('import-format',{Selected=m.importFormat or'Commander',W=left-28})then
        for _,format in ipairs({'Commander','Modern','Standard','Pioneer'})do if S.TextSelectable(format,{Selected=m.importFormat==format})then m.importFormat=format;m:setImportText(m.importText or'')end end
        S.EndComboBox()
    end
    S.NewLine()
    if S.Input('import-name',{Text=m.importName or'',W=left-28,H=28,Align='left',Tooltip='Optional name for the imported deck'})then m.importName=S.GetInputText();m:setImportText(m.importText or'')end
    S.NewLine()
    -- Slab has a separate multiline color that otherwise defaults to black.
    local style=S.GetStyle();local multilineColor=style.MultilineTextColor;style.MultilineTextColor=v.r.colors.text
    local changed=S.Input('import-text',{Text=m.importText or'',W=left-28,H=math.max(100,h-475),MultiLine=true,MultiLineW=left-48,Align='left',Tooltip='Deck export text or HTTPS public deck URL'})
    style.MultilineTextColor=multilineColor
    if changed then m:setImportText(S.GetInputText())end
    S.NewLine()
    if button(v,'Paste','copy',math.floor((left-36)/2),34)then if love.system and love.system.getClipboardText then m:setImportText(love.system.getClipboardText())end end;S.SameLine()
    if button(v,'Preview','search',math.floor((left-36)/2),34,{Disabled=m.importBusy})then m:previewDeckImport()end
    if m.importBusy then S.NewLine();S.Text('Preparing preview…',{Color=v.r.colors.muted})end
    if m.importError then S.NewLine();S.Textf(m.importError,{W=left-32,Color=v.r.colors.gold})end
    S.EndWindow()
    v:window('import-preview',40+left,105,right,h-170)
    title(v,'import-preview-title','Preview before saving','search',right-28);S.NewLine()
    local preview=m.importPreview
    if preview then
        S.Textf(preview.deck.name..' · '..preview.deck.format,{W=right-32,Color=v.r.colors.text});S.NewLine()
        S.BeginListBox('import-preview-list',{W=right-28,H=math.max(120,h-380)})
        for _,zone in ipairs({'commander','main','sideboard'})do
            local entries=preview.deck[zone]or{};local count=0;for _,entry in ipairs(entries)do count=count+entry.count end
            if#entries>0 then S.Textf(zone..' · '..count,{W=right-55,Color=v.r.colors.accent})
                for _,entry in ipairs(entries)do S.Textf(entry.count..' × '..entry.name,{W=right-55})end;S.NewLine()end
        end
        messages(v,preview.warnings,right-55)
        messages(v,(preview.validation or{}).errors,right-55)
        for _,printing in ipairs(preview.printingSelections or{})do S.Textf(printing.name..' · '..(printing.set or''):upper()..' '..(printing.collectorNumber or''),{W=right-55,Color=v.r.colors.muted})end
        if#(preview.excluded or{})>0 then S.NewLine();S.Text('Outside the deck',{Color=v.r.colors.muted});for _,entry in ipairs(preview.excluded)do S.Textf(entry.count..' × '..entry.name,{W=right-55,Color=v.r.colors.muted})end end
        S.EndListBox();S.NewLine()
        local validation=preview.validation or{}
        if button(v,validation.draft and'Save unfinished draft'or'Save deck','save',right-28,36,{Disabled=m.importBusy or not validation.saveAllowed})then m:saveImportedDeck()end
        S.NewLine();S.Textf('XMage performs final validation when the match starts.',{W=right-32,Color=v.r.colors.muted})
    else S.Textf('Your list, printings and any validation errors appear here. Nothing is saved during preview.',{W=right-32,Color=v.r.colors.muted})end
    S.EndWindow();footer(v,w,h,'Public URLs may require using the site’s text export. Private authentication is not imported.')
end
function UI.history(v,w,h)
    local S,m=v.S,v.m
    v:window('history-list',26,105,w-52,h-170);title(v,'history-title','Match history','replay',w-85);S.NewLine()
    if m.historyError then S.Textf(m.historyError,{W=w-90,Color=v.r.colors.gold})end
    S.BeginListBox('history-items',{W=w-82,H=h-285})
    for _,match in ipairs(m.historyItems or{})do
        S.PushID('history-'..match.id)
        local stamp=match.createdAt and os.date('%Y-%m-%d %H:%M',math.floor(match.createdAt/1000))or''
        local outcome=({win='Win',loss='Loss',draw='Draw',aborted='Stopped',failed='Failed',running='In progress',unknown='Result unavailable'})[match.outcome]or'Result unavailable'
        title(v,'match',outcome..' · '..(match.format or'')..' · '..stamp,match.outcome=='win'and'check'or'replay',w-130)
        local opponents={};for _,player in ipairs(match.players or{})do
            local deck=type(player.deck)=='table'and player.deck.name or nil
            opponents[#opponents+1]=player.name..(deck and deck~=''and' · '..deck or'')
        end
        S.Textf(table.concat(opponents,'   /   '),{W=w-130,Color=v.r.colors.muted})
        if button(v,'Open recording','replay',160,30,{Disabled=not m.openReplay})then m:openReplay(match.id)end
        S.NewLine();S.PopID()
    end
    if#(m.historyItems or{})==0 then S.Text(m.historyBusy and'Loading history…'or'No recorded matches yet',{Color=v.r.colors.muted})end
    S.EndListBox();S.NewLine()
    if button(v,'Previous','previous',120,29,{Disabled=m.historyBusy or(m.historyOffset or 0)==0})then m.historyOffset=math.max(0,m.historyOffset-12);m:refreshHistory()end;S.SameLine()
    if button(v,'Next','next',120,29,{Disabled=m.historyBusy or(m.historyOffset or 0)+12>=(m.historyTotal or 0)})then m.historyOffset=(m.historyOffset or 0)+12;m:refreshHistory()end;S.SameLine()
    if button(v,'Refresh','replay',120,29,{Disabled=m.historyBusy})then m:refreshHistory()end
    S.EndWindow();footer(v,w,h,'Results come from saved native matches. Interrupted recordings do not count as wins or losses.')
end
function UI.tokens(v,w,h)
    local S,m=v.S,v.m
    v:window('token-preferences',26,105,w-52,h-170);title(v,'token-title','Token artwork for this deck','gallery',w-85);S.NewLine()
    local modes={{'default','Default'},{'randomSelected','Random selected'},{'randomAll','Random all'}}
    for index,mode in ipairs(modes)do if index>1 then S.SameLine()end;if button(v,mode[2],mode[1]=='default'and'gallery'or'overview',math.floor((w-100)/3),33,{Active=m.tokenMode==mode[1]})then m:setTokenMode(mode[1])end end
    S.NewLine();S.Textf('Only matching token identities use these illustrations. Select artwork below for Random selected.',{W=w-90,Color=v.r.colors.muted});S.NewLine()
    if S.Input('token-search',{Text=m.tokenQuery or'',W=w-90,H=28,Align='left',Tooltip='Search the tokens related to this deck'})then m.tokenQuery=S.GetInputText();m.tokenOffset=0;m.tokenVersion=(m.tokenVersion or 0)+1;m.tokenTimer=.25 end
    S.NewLine();S.BeginListBox('token-images',{W=w-82,H=math.max(120,h-480)})
    local columns=math.max(3,math.floor((w-125)/150));local cw=math.floor((w-125-(columns-1)*10)/columns);local ch=math.floor(cw*1.4)
    for index,item in ipairs(m.tokenItems or{})do
        if index>1 and(index-1)%columns~=0 then S.SameLine({Pad=10})end
        S.PushID(item.tokenImageId);local art=m:getArt(item,true)
        if art then
            if S.Button(item.name,{W=cw,H=ch,Image={Image=art},Active=(m.tokenSelected or{})[item.tokenImageId],Tooltip=item.name..' · '..(item.set or''):upper()..' · '..(item.artist or'')})then m:toggleTokenArt(item.tokenImageId)end
        else
            if button(v,item.name..' · '..(item.set or''):upper(),(m.tokenSelected or{})[item.tokenImageId]and'check'or'gallery',cw,ch,{Active=(m.tokenSelected or{})[item.tokenImageId],Tooltip='Click to select this token illustration'})then m:toggleTokenArt(item.tokenImageId)end
        end
        S.PopID();if index%columns==0 then S.NewLine()end
    end
    if#(m.tokenItems or{})==0 then S.Textf(m.tokenBusy and'Loading token metadata…'or'No related token images are available in this local metadata source.',{W=w-120,Color=v.r.colors.muted})end
    S.EndListBox();S.NewLine()
    if button(v,'Previous','previous',110,29,{Disabled=m.tokenBusy or(m.tokenOffset or 0)==0})then m.tokenOffset=math.max(0,m.tokenOffset-12);m:refreshTokenSettings()end;S.SameLine()
    if button(v,'Next','next',110,29,{Disabled=m.tokenBusy or(m.tokenOffset or 0)+12>=(m.tokenTotal or 0)})then m.tokenOffset=(m.tokenOffset or 0)+12;m:refreshTokenSettings()end;S.SameLine()
    if button(v,'Save token artwork','save',190,29,{Disabled=m.tokenBusy or not m.tokenDeckId})then m:saveTokenSettings()end
    if m.tokenError then S.NewLine();S.Textf(m.tokenError,{W=w-90,Color=v.r.colors.gold})end
    S.EndWindow();footer(v,w,h,'Token art changes presentation. The engine retains token type, abilities and current power/toughness.')
end
return UI
