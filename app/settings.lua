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
    local function heading(text) S.PushFont(r.assets.titleFont and r.assets:titleFont(22,s)or r.fonts[22]);S.Text(text,{Color=C.accent});S.PopFont();S.NewLine() end
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
        heading('Table and playmat')
        choice('skybox','Space background',{'Galaxy','Nebula','Band','Dark','Day','Off'})
        slider('skyboxBrightness','Background brightness')
        slider('playmatOpacity','Playmat opacity')
        choice('counterStyle','Counter display',{'Dice','Text'})
        if m.showProfile and S.Button('Profile and playmat',{W=math.min(330,inner),H=34,Image={Image=r.assets:buttonImage('profile','Profile and playmat',math.min(330,inner),34,{font=r.fonts[16],iconSize=19})}})then m.settingsOpen=false;m:showProfile()end
        S.NewLine()
        heading('Cards and effects')
        toggle('showCardArt','Show card artwork on the table','The builder always uses card images. Missing downloads display a loading card and retry.')
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
        S.Textf('Ambient loop: Dark Portents — Shrouded Future. Credits and asset metadata are in assets/ASSET_GUIDE.md.',{W=inner-10,Color=C.muted})
    elseif view.settingsTab=='Accessibility' then
        heading('Readability and motion')
        local Fonts=require('app.fonts')
        choice('fontFamily','Application font',Fonts.names())
        S.Textf(#Fonts.available()>1 and 'Installed system fonts. Apply and save updates interface text; Magic symbols retain their supplied font.' or 'System font discovery is unavailable. The bundled application font remains available.',{W=inner-10,Color=C.muted});S.NewLine()
        choice('titleFontFamily','Heading and card title font',{'Beleren','Application font'})
        S.Textf('Beleren is the supplied Magic display font. Application font keeps your selected family for titles as well.',{W=inner-10,Color=C.muted});S.NewLine()
        choice('cursorStyle','Pointer style',{'System','Kenney'})
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
