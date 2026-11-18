-- Verified credit data stays in app.credits; this module only presents it.
local Build=require('app.build_info');local Text=require('app.utf8_text')
local About={maxLicenseBytes=128*1024}
local function credits()return require('app.credits')end
local function relative(path)
    if type(path)~='string'or#path>240 or path:find('[%z\1-\31\127]')or path:find('\\',1,true)or path:find(':',1,true)or path:sub(1,1)=='/'then return false end
    for part in path:gmatch('[^/]+')do if part=='..'then return false end end
    return path~=''
end
function About.readLicense(path)
    if not relative(path)then return nil,'This notice is unavailable.'end
    local info=love.filesystem.getInfo(path,'file')
    if not info then return nil,'This notice is not included in this build.'end
    if info.size>About.maxLicenseBytes then return nil,'This notice is too large for the in-app reader. Read '..path..' in the application files.'end
    local content=love.filesystem.read(path,About.maxLicenseBytes+1)
    if not content or#content>About.maxLicenseBytes then return nil,'This notice could not be read.'end
    return Text.clean(content)
end
local function links(data)
    local result={}
    local function add(values)for _,value in ipairs(values or{})do if type(value.url)=='string'then result[value.url]=true end end end
    add(data.links)
    for _,section in ipairs(data.sections or{})do add(section.links);for _,item in ipairs(section.items or{})do add(item.links)end end
    return result
end
function About.openLink(url)
    if type(url)~='string'or#url>1024 or url:find('[%z\1-\32\127]')or not url:match('^https://[%w%.%-]+[/#?]?')or not links(credits())[url]then return false end
    local ok,result=pcall(love.system.openURL,url);return ok and result~=false
end
local function button(view,id,label,icon,width)
    local S,r=view.S,view.r;S.PushID(id)
    local clicked=S.Button(label,{W=math.min(360,width),H=36,Image={Image=r.assets:buttonImage(icon,label,math.min(360,width),36,{font=r.fonts[14],iconSize=18})},Tooltip=label})
    S.PopID();return clicked
end
function About.build(view,width)
    local S,r=view.S,view.r;local C=r.colors;local data=credits()
    view.aboutState=view.aboutState or{info=Build.load(),notices={}};local state=view.aboutState
    local function paragraph(value,color)if value and value~=''then S.Textf(Text.clean(value),{W=width,Color=color or C.text});S.NewLine()end end
    local function heading(value,icon)
        if icon then S.Image('about-icon-'..value,{Image=r.assets:iconImage(icon,22),W=22,H=22});S.SameLine({CenterY=true})end
        S.PushFont(r.assets:titleFont(22,view.m.settings));S.Textf(value,{W=width-(icon and 34 or 0),Color=C.accent});S.PopFont();S.NewLine()
    end
    local function showLinks(values,prefix)
        for index,link in ipairs(values or{})do
            if button(view,prefix..'-link-'..index,link.label or link.url,'external',width)then state.linkError=not About.openLink(link.url)and'Could not open this link in your browser.'or nil end
            S.NewLine()
        end
    end
    local function notice(item,id)
        if not item.licensePath then return end
        local opened=state.openNotice==id
        if button(view,id..'-notice',opened and'Hide license notice'or'Read license notice',opened and'collapse'or'expand',width)then state.openNotice=not opened and id or nil;opened=not opened end
        S.NewLine()
        if opened then
            local cached=state.notices[item.licensePath]
            if not cached then local value,problem=About.readLicense(item.licensePath);cached={text=value,error=problem};state.notices[item.licensePath]=cached end
            paragraph(cached.text or cached.error,cached.error and C.gold or C.muted)
        end
    end
    heading(data.title or'Love: 2 Gathering','info')
    for _,row in ipairs(Build.lines(state.info))do paragraph(row.label..' · '..row.value,C.muted)end
    if button(view,'about-copy-build','Copy build details','export',width)then love.system.setClipboardText(Build.summary(state.info))end;S.NewLine()
    require('app.updates').build(view,width,state.info)
    paragraph(data.notice,C.gold)
    showLinks(data.links,'about-project')
    if state.linkError then paragraph(state.linkError,C.gold)end
    for index,section in ipairs(data.sections or{})do
        S.Separator();S.NewLine();heading(section.title or'Credits')
        paragraph(section.text,C.muted);showLinks(section.links,'about-section-'..index)
        for number,item in ipairs(section.items or{})do
            local id='about-item-'..index..'-'..number
            S.PushFont(r.fonts[18]);S.Textf(item.name or'',{W=width,Color=C.text});S.PopFont();S.NewLine()
            paragraph(item.text,C.muted)
            if item.license then paragraph('License · '..item.license,C.muted)end
            notice(item,id);showLinks(item.links,id)
        end
    end
end
return About
