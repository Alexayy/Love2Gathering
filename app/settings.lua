local Settings={}
function Settings.build(view,w,h,options)
    local S,m,r=view.S,view.m,view.r;local s=m.settings;local C=r.colors
    options=options or{};local fullPage=options.fullPage==true or m.page=='settings'
    local width=fullPage and w-56 or math.min(920,w-64);local height=fullPage and h-152 or math.min(820,h-72);local inner=width-44
    local formWidth=math.min(inner-24,940)
    local title;if not fullPage then title='Settings'end
    view:window(fullPage and'settings-page'or'settings',fullPage and 28 or(w-width)/2,fullPage and 126 or(h-height)/2,width,height,title,not fullPage and{Layer='ContextMenu'}or nil)
    local function close()if m.closeSettings then m:closeSettings()else m.settingsOpen=false;if fullPage then m.page='decks'end end end
    view.settingsTab=view.settingsTab or 'Game'
    if m.storageTabRequested then view.settingsTab='Storage';m.storageTabRequested=nil end
    local tabs={'Game','Graphics','Presentation','Audio','Accessibility','Storage'}
    for i,tab in ipairs(tabs) do
        if i>1 then S.SameLine() end
        local tw=math.min(158,(inner-(#tabs-1)*8)/#tabs);local icon=({Game='dice',Graphics='graphics',Presentation='playmat',Audio='audio',Accessibility='inspect',Storage='save'})[tab]
        if S.Button(tab,{W=tw,H=42,Active=view.settingsTab==tab,Image={Image=r.assets:buttonImage(icon,tab,tw,42,{font=r.fonts[16],iconSize=19})}}) then view.settingsTab=tab end
    end
    S.Separator();S.NewLine()
    local function heading(text) S.PushFont(r.assets.titleFont and r.assets:titleFont(22,s)or r.fonts[22]);S.Text(text,{Color=C.accent});S.PopFont();S.NewLine() end
    local function toggle(key,label,description)
        if S.CheckBox(s[key],label,{Size=21}) then s[key]=not s[key] end
        if description then S.Textf(description,{W=formWidth,Color=C.muted}) end
        S.NewLine()
    end
    local function choice(key,label,items)
        S.Text(label,{Color=C.text});view:combo('setting-'..key,tostring(s[key]),items,math.min(330,inner),function(value) s[key]=value end);S.NewLine()
    end
    local function slider(key,label,low,high)
        S.Text(label..'  '..math.floor((s[key] or 0)*100)..'%')
        if S.InputNumberSlider('setting-'..key,s[key] or 0,low or 0,high or 1,{W=math.min(460,formWidth),H=38,Step=.01,Precision=2}) then s[key]=S.GetInputNumber() end
        S.NewLine()
    end
    local storageTab=view.settingsTab=='Storage'
    if storageTab then require('app.storage').tabs(view,formWidth)end
    S.BeginListBox(storageTab and('settings-storage-'..(m.storageSection or'cleanup'))or'settings-content',{W=inner,H=height-(storageTab and 224 or 176)})
    S.Indent(14);S.NewLine(.4)
    if view.settingsTab=='Game' then
        heading('Rules and decisions')
        toggle('manualTriggers','Manual trigger ordering','Drag simultaneous abilities left to right. The leftmost resolves first. Otherwise XMage places them automatically.')
        toggle('autoMana','Automatically spend floating mana','Use available mana already in your pool. Land and other mana abilities remain engine choices.')
        S.Textf('Game options apply to the next match. Legal highlights, targets, timing and payment always come from XMage.',{W=formWidth,Color=C.muted})
    elseif view.settingsTab=='Graphics' then
        heading('Display and rendering')
        local resolutions={'Desktop','1120x720','1280x720','1366x768','1440x900','1600x900','1920x1080','2560x1080','2560x1440','3840x2160'}
        choice('resolution','Resolution',resolutions)
        choice('windowMode','Window mode',{'Windowed','Borderless','Fullscreen'})
        toggle('vsync','Vertical sync')
        choice('msaa','Antialiasing',{0,2,4,8})
        choice('fontQuality','Text quality',{'Standard','High'})
        S.Textf('High uses a denser Beleren glyph atlas. Menus and text retain native display resolution independently of table render scale.',{W=formWidth,Color=C.muted});S.NewLine()
        choice('renderScale','Table render scale',{.5,.75,1,1.25,1.5})
        choice('textureFilter','Texture filtering',{'linear','nearest'})
        choice('frameLimit','Frame limit (0 = unlimited)',{0,30,60,120,144})
        S.Textf('The table render scale changes the card scene. Menus and text stay at the display resolution.',{W=formWidth,Color=C.muted})
    elseif view.settingsTab=='Presentation' then
        heading('Table and playmat')
        choice('theme','Color theme',require('app.theme').names)
        slider('panelOpacity','Panel opacity')
        local roles=require('app.assets').palette(s)
        local function editColor(key,label,role)
            S.Text(label,{Color=C.text})
            S.Rectangle({W=28,H=36,Color=roles[role],Rounding=4});S.SameLine()
            if S.Button('Choose '..label:lower(),{W=190,H=36})then view.themeColorEdit={key=key,color=roles[role],fresh=true}end
            S.SameLine()
            if S.Input('setting-'..key,{Text=s[key]or'',W=132,H=36,Align='left',Tooltip='Optional #RRGGBB color; leave blank for the theme color'})then s[key]=S.GetInputText()end
            S.SameLine();S.PushID(key);if S.Button('Reset',{W=90,H=36})then s[key]=''end;S.PopID()
            if s[key]~=''and not(s[key]or''):match('^#%x%x%x%x%x%x$')then S.Text('Choose a color or enter six hexadecimal digits after #.',{Color=C.gold})end
            S.NewLine()
        end
        editColor('accentColor','Your accent','accent');editColor('opponentColor','Opponent accent','purple')
        choice('builderLayout','Deck builder layout',{'Classic','Simplified'})
        choice('skybox','Space background',{'Galaxy','Nebula','Band','Dark','Day','Off'})
        slider('skyboxBrightness','Background brightness')
        slider('playmatOpacity','Playmat opacity')
        choice('counterStyle','Counter display',{'Dice','Text'})
        toggle('autoFollowTurn','Follow the active player','In multiplayer, focus the next player when their turn starts. You can still pan and choose any player yourself.')
        if m.showProfile and S.Button('Profile and playmat',{W=math.min(330,inner),H=34,Image={Image=r.assets:buttonImage('profile','Profile and playmat',math.min(330,inner),34,{font=r.fonts[16],iconSize=19})}})then m.settingsOpen=false;m:showProfile()end
        S.NewLine()
        heading('Cards and effects')
        choice('cardBackStyle','Card back',require('app.surfaces').cardBackNames)
        if r.assets.surfaces then
            local spec=require('app.surfaces').cardBackSpec(s.cardBackStyle);local image=spec and r.assets.surfaces:load(spec)
            if image then local scale=math.min(70/image:getWidth(),95/image:getHeight());S.Image('card-back-preview',{Image=image,W=image:getWidth()*scale,H=image:getHeight()*scale})end
        end
        S.NewLine();slider('boardImpactIntensity','Board impact strength')
        toggle('showCardArt','Show card artwork on the table','The builder always uses card images. Artwork that is not cached shows a placeholder; use the artwork downloader for selected cards.')
        toggle('localArtworkOnly','Use local artwork only','Load cached cards and art without contacting Scryfall or its CDN. The separate downloader fills missing images. Disable this to allow on-demand downloads.')
        toggle('animations','Card movement and drag tweens')
        toggle('particles','Subtle cast and resolution particles')
        toggle('showTooltips','Hover card previews and tooltips')
        toggle('keywordReminders','Explain keywords','Show short reminders for recognized keywords in card details.')
    elseif view.settingsTab=='Audio' then
        heading('Sound and ambience')
        slider('masterVolume','Master volume')
        toggle('musicEnabled','Ambient music')
        slider('musicVolume','Music volume')
        toggle('sfxEnabled','Interface and game sounds')
        slider('sfxVolume','Sound effect volume')
        if S.Button('Preview dice sound',{W=260,H=38,Image={Image=r.assets:buttonImage('dice','Preview dice sound',260,38,{font=r.fonts[16],iconSize=20})}})then r:sound('dice-roll')end;S.NewLine()
        S.Textf('Ambient loop: Dark Portents — Shrouded Future. Credits and asset metadata are in assets/ASSET_GUIDE.md.',{W=formWidth,Color=C.muted})
    elseif view.settingsTab=='Storage' then
        require('app.storage').build(view,formWidth)
    elseif view.settingsTab=='Accessibility' then
        heading('Readability and motion')
        S.Textf('Beleren is used throughout the application. Missing characters use the bundled UTF-8 fallback; Magic symbols retain their own font.',{W=formWidth,Color=C.muted});S.NewLine()
        choice('cursorStyle','Pointer style',{'System','Kenney'})
        slider('cursorScale','Pointer size',.4,1)
        choice('uiScale','Interface scale',{.85,1,1.15,1.25,1.5,1.75})
        S.Textf('Scale fits the current window so controls remain reachable. Larger display modes allow larger interface scales.',{W=formWidth,Color=C.muted});S.NewLine()
        toggle('highContrast','High contrast text and borders')
        choice('colorblindMode','Color vision palette',{'Off','Deuteranopia','Protanopia','Tritanopia'})
        toggle('reducedMotion','Reduce motion','Disables movement tweens and particles. Legal actions also have an outline, so color is not the only cue.')
    end
    S.Unindent(14);S.EndListBox();S.NewLine()
    local validColors=true;for _,key in ipairs({'accentColor','opponentColor'})do local value=s[key]or'';if value~=''and not value:match('^#%x%x%x%x%x%x$')then validColors=false end end
    local buttonWidth=math.min(300,(inner-12)/2)
    if S.Button('Apply and save',{W=buttonWidth,H=42,Disabled=not validColors or m.storageLocationBlocked,Tooltip=m.storageLocationBlocked and'Restart or cancel the storage location change before saving preferences.'or'Apply and save'}) then
        if view.preferences then view.preferences:apply(true) end
        m:saveSettings();close()
    end;S.SameLine()
    if S.Button('Close',{W=buttonWidth,H=42})then close()end
    S.EndWindow()
    if view.themeColorEdit then
        local edit=view.themeColorEdit;local result=S.ColorPicker({Color=edit.color,Refresh=edit.fresh,AllowAlpha=false,X=w/2-180,Y=math.max(30,h/2-230)});edit.fresh=false
        if result.Button==1 then local c=result.Color;s[edit.key]=string.format('#%02X%02X%02X',math.floor(c[1]*255+.5),math.floor(c[2]*255+.5),math.floor(c[3]*255+.5));view.themeColorEdit=nil
        elseif result.Button==-1 then view.themeColorEdit=nil end
    end
end
return Settings
