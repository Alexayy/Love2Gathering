local Settings={}
function Settings.build(view,w,h)
    local S,m,r=view.S,view.m,view.r;local s=m.settings;local C=r.colors
    local width=math.min(820,w-80);local height=math.min(664,h-110);local inner=width-34
    view:window('settings',w/2-width/2,h/2-height/2,width,height,'Settings · Love: 2 Gathering')
    view.settingsTab=view.settingsTab or 'Game'
    local tabs={'Game','Graphics','Presentation','Audio','Accessibility'}
    for i,tab in ipairs(tabs) do
        if i>1 then S.SameLine() end
        if S.Button(tab,{W=(inner-24)/5,H=35,Active=view.settingsTab==tab}) then view.settingsTab=tab end
    end
    S.Separator();S.NewLine()
    local function heading(text) S.PushFont(r.fonts[22]);S.Text(text,{Color=C.accent});S.PopFont();S.NewLine() end
    local function toggle(key,label,description)
        if S.CheckBox(s[key],label,{Size=21}) then s[key]=not s[key] end
        if description then S.Textf(description,{W=inner-10,Color=C.muted}) end
        S.NewLine()
    end
    local function choice(key,label,items)
        S.Text(label,{Color=C.text});view:combo('setting-'..key,tostring(s[key]),items,math.min(330,inner),function(value) s[key]=value end);S.NewLine()
    end
    local function slider(key,label)
        S.Text(label..'  '..math.floor((s[key] or 0)*100)..'%')
        if S.InputNumberSlider('setting-'..key,s[key] or 0,0,1,{W=math.min(460,inner),H=29,Step=.05}) then s[key]=S.GetInputNumber() end
        S.NewLine()
    end
    S.BeginListBox('settings-content',{W=inner,H=height-163})
    if view.settingsTab=='Game' then
        heading('Rules and decisions')
        toggle('manualTriggers','Manual trigger ordering','Drag simultaneous abilities left to right. The leftmost resolves first. Otherwise XMage places them automatically.')
        toggle('autoMana','Automatically spend floating mana','Use available mana already in your pool. Land and other mana abilities remain engine choices.')
        S.Textf('Game options apply to the next match. Legal highlights, targets, timing and payment always come from XMage.',{W=inner-10,Color=C.muted})
    elseif view.settingsTab=='Graphics' then
        heading('Display and rendering')
        local resolutions={'1120x720','1280x720','1366x768','1440x900','1600x900','1920x1080','2560x1080','2560x1440','3840x2160'}
        choice('resolution','Resolution',resolutions)
        choice('windowMode','Window mode',{'Windowed','Borderless','Fullscreen'})
        toggle('vsync','Vertical sync')
        choice('msaa','Antialiasing',{0,2,4,8})
        choice('renderScale','Table render scale',{.5,.75,1,1.25,1.5})
        choice('textureFilter','Texture filtering',{'linear','nearest'})
        choice('frameLimit','Frame limit (0 = unlimited)',{0,30,60,120,144})
        S.Textf('The table render scale changes the card scene. Menus and text stay at the display resolution.',{W=inner-10,Color=C.muted})
    elseif view.settingsTab=='Presentation' then
        heading('Cards and effects')
        toggle('showCardArt','Show card artwork on the table','The builder always uses card images. Missing downloads display a loading card and retry.')
        toggle('animations','Card movement and drag tweens')
        toggle('particles','Subtle cast and resolution particles')
        toggle('showTooltips','Hover card previews and tooltips')
    elseif view.settingsTab=='Audio' then
        heading('Sound and ambience')
        slider('masterVolume','Master volume')
        toggle('musicEnabled','Ambient music')
        slider('musicVolume','Music volume')
        toggle('sfxEnabled','Interface and game sounds')
        slider('sfxVolume','Sound effect volume')
        S.Textf('Ambient loop: Dark Portents — Shrouded Future. Credits and asset metadata are in assets/ASSET_GUIDE.md.',{W=inner-10,Color=C.muted})
    elseif view.settingsTab=='Accessibility' then
        heading('Readability and motion')
        choice('uiScale','Interface scale',{.85,1,1.15,1.25,1.5,1.75})
        S.Textf('Scale fits the current window so controls remain reachable. Larger display modes allow larger interface scales.',{W=inner-10,Color=C.muted});S.NewLine()
        toggle('highContrast','High contrast text and borders')
        choice('colorblindMode','Color vision palette',{'Off','Deuteranopia','Protanopia','Tritanopia'})
        toggle('reducedMotion','Reduce motion','Disables movement tweens and particles. Legal actions also have an outline, so color is not the only cue.')
    end
    S.EndListBox();S.NewLine()
    if S.Button('Apply and save',{W=inner/2-7,H=39}) then
        if view.preferences then view.preferences:apply(true) end
        m:saveSettings();m.settingsOpen=false
    end;S.SameLine()
    if S.Button('Close',{W=inner/2-7,H=39}) then m.settingsOpen=false end
    S.EndWindow()
end
return Settings
