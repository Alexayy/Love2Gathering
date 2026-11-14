-- Curated, unmodified Kenney sprites. Drawing stays in the caller's logical
-- coordinates; this module never changes a control's input or layout geometry.
local Theme={};Theme.__index=Theme
local palette={
    WindowBackgroundColor={.045,.065,.092,.99},WindowTitleFocusedColor={.075,.175,.19,1},WindowTitleUnfocusedColor={.065,.105,.15,1},
    ButtonColor={.085,.17,.205,1},ButtonHoveredColor={.11,.285,.29,1},ButtonPressedColor={.13,.36,.31,1},
    ComboBoxColor={.065,.115,.15,1},ComboBoxHoveredColor={.09,.225,.245,1},ComboBoxDropDownColor={.12,.22,.255,1},ComboBoxDropDownHoveredColor={.14,.33,.32,1},
    InputBgColor={.035,.06,.09,1},InputEditBgColor={.05,.10,.14,1},InputSelectColor={.13,.47,.55,.88},
    TextColor={.90,.94,.98,1},TextDisabledColor={.46,.56,.66,1},SeparatorColor={.21,.34,.37,.8},
    ScrollBarColor={.18,.32,.36,1},ScrollBarHoveredColor={.26,.48,.46,1},CheckBoxSelectedColor={.28,.89,.72,1},
}
Theme.palette=palette
Theme.names={'Midnight','Amethyst','Ocean','Ember','Obsidian'}
local presets={
    Midnight={bg={.026,.036,.060},panel={.055,.085,.12},line={.15,.26,.29},accent={.28,.89,.72},purple={.62,.48,.96}},
    Amethyst={bg={.042,.027,.066},panel={.105,.065,.15},line={.30,.18,.39},accent={.78,.57,1},purple={.48,.84,.88}},
    Ocean={bg={.018,.043,.066},panel={.035,.105,.15},line={.11,.30,.40},accent={.30,.80,1},purple={.66,.65,.98}},
    Ember={bg={.057,.032,.030},panel={.13,.075,.065},line={.35,.20,.16},accent={1,.65,.32},purple={.75,.56,.91}},
    Obsidian={bg={.025,.027,.032},panel={.075,.082,.096},line={.25,.28,.33},accent={.75,.84,.93},purple={.68,.61,.87}},
}
local function copy(c)return{c[1],c[2],c[3],c[4]or 1}end
local function mix(a,b,t)return{a[1]*(1-t)+b[1]*t,a[2]*(1-t)+b[2]*t,a[3]*(1-t)+b[3]*t,1}end
local function hex(value,fallback)
    if type(value)=='string'and value:match('^#%x%x%x%x%x%x$')then return{tonumber(value:sub(2,3),16)/255,tonumber(value:sub(4,5),16)/255,tonumber(value:sub(6,7),16)/255,1}end
    return copy(fallback)
end
function Theme.colors(settings)
    settings=settings or{};local source=presets[settings.theme]or presets.Midnight;local out={}
    for key,value in pairs(source)do out[key]=copy(value)end
    out.accent=hex(settings.accentColor,out.accent);out.purple=hex(settings.opponentColor,out.purple)
    local accessible={Deuteranopia={.98,.80,.33,1},Protanopia={.49,.78,1,1},Tritanopia={1,.57,.78,1}}
    if accessible[settings.colorblindMode]then out.accent=copy(accessible[settings.colorblindMode])end
    out.text=settings.highContrast and{.98,.99,1,1}or{.90,.94,.98,1}
    out.muted=settings.highContrast and{.75,.82,.90,1}or{.59,.68,.77,1}
    out.red={1,.39,.40,1};out.gold={.98,.74,.34,1};return out
end
function Theme:configure(settings)
    self.settings=settings or{}
    local signature=table.concat({self.settings.theme or'Midnight',self.settings.accentColor or'',self.settings.opponentColor or'',tostring(self.settings.highContrast),self.settings.colorblindMode or'Off'},'|')
    if signature==self.colorSignature then return end
    self.colorSignature=signature;self.colors=Theme.colors(self.settings)
    local c=self.colors;self.styles={}
    for key,value in pairs(palette)do self.styles[key]=copy(value)end
    local p=self.styles
    p.WindowBackgroundColor=copy(c.panel);p.WindowTitleFocusedColor=mix(c.panel,c.accent,.20);p.WindowTitleUnfocusedColor=mix(c.panel,c.line,.22)
    p.ButtonColor=mix(c.panel,c.accent,.10);p.ButtonHoveredColor=mix(c.panel,c.accent,.25);p.ButtonPressedColor=mix(c.panel,c.accent,.38)
    p.ComboBoxColor=mix(c.bg,c.panel,.70);p.ComboBoxHoveredColor=mix(c.panel,c.accent,.16)
    p.ComboBoxDropDownColor=mix(c.panel,c.accent,.14);p.ComboBoxDropDownHoveredColor=mix(c.panel,c.accent,.31)
    p.InputBgColor=mix(c.bg,c.panel,.45);p.InputEditBgColor=mix(c.panel,c.accent,.08);p.InputSelectColor=mix(c.panel,c.accent,.45)
    p.TextColor=copy(c.text);p.TextDisabledColor=copy(c.muted);p.SeparatorColor=copy(c.line)
    p.ScrollBarColor=mix(c.panel,c.accent,.25);p.ScrollBarHoveredColor=mix(c.panel,c.accent,.55);p.CheckBoxSelectedColor=copy(c.accent)
    p.MultilineTextColor=copy(c.text);p.TextHoverBgColor=mix(c.panel,c.accent,.15)
end
local manifest={
    panel={file='space-panel.png',border=8,target=8,center={218/255,220/255,231/255}},
    button={file='space-button.png',border=12,target=9,center={218/255,220/255,231/255}},
    square={file='space-square.png',border=12,target=7,center={218/255,220/255,231/255}},
    frame={file='fantasy-frame.png',border=14,target=11},inset={file='fantasy-inset.png',border=14,target=9},
}
Theme.manifest=manifest
local root='assets/kenney/theme/'
local function load(path)
    local ok,result=pcall(love.graphics.newImage,path)
    if ok then result:setFilter('linear','linear');return result end
end
local function tint(color,reference)
    local out={color[1],color[2],color[3],color[4] or 1}
    if reference then for i=1,3 do out[i]=math.min(1,out[i]/reference[i])end end
    return out
end
function Theme.new()
    local self=setmetatable({slices={},stats={panel=0,control=0,input=0,title=0,frame=0}},Theme)
    for name,spec in pairs(manifest)do
        local source=load(root..spec.file)
        if source then
            local width,height=source:getDimensions();local border=spec.border
            local slice={image=source,quads={},target=spec.target,center=spec.center}
            for row=1,3 do for col=1,3 do
                local x=col==1 and 0 or col==2 and border or width-border
                local y=row==1 and 0 or row==2 and border or height-border
                local w=col==2 and width-border*2 or border;local h=row==2 and height-border*2 or border
                slice.quads[#slice.quads+1]=love.graphics.newQuad(x,y,w,h,width,height)
            end end
            self.slices[name]=slice
        end
    end
    self.focus=load(root..'space-focus.png');self.divider=load(root..'fantasy-divider.png')
    self.ready=self.slices.panel and self.slices.button and self.slices.frame and self.slices.inset
    self:configure({});return self
end
function Theme:slice(name,x,y,w,h,color,border)
    local sprite=self.slices[name];if not sprite or w<=0 or h<=0 then return false end
    local edge=math.min(border or sprite.target,w/2,h/2)
    local widths={edge,math.max(0,w-edge*2),edge};local heights={edge,math.max(0,h-edge*2),edge}
    love.graphics.setColor(tint(color or {1,1,1,1},sprite.center))
    local top=y;local index=0
    for row=1,3 do
        local left=x
        for col=1,3 do
            index=index+1;local quad=sprite.quads[index];local _,_,sw,sh=quad:getViewport()
            if widths[col]>0 and heights[row]>0 then love.graphics.draw(sprite.image,quad,left,top,0,widths[col]/sw,heights[row]/sh)end
            left=left+widths[col]
        end
        top=top+heights[row]
    end
    return true
end
function Theme:frame(x,y,w,h,style)
    if not self.ready then return false end
    self:configure(self.settings);local c=self.colors
    local color=type(style)=='table' and style or style=='accent'and c.accent or style=='purple'and c.purple or mix(c.line,c.text,.2)
    love.graphics.push('all');self:slice('frame',x,y,w,h,color);love.graphics.pop()
    self.stats.frame=self.stats.frame+1;return true
end
function Theme:panel(x,y,w,h,style)
    if not self.ready then return false end
    self:configure(self.settings);local c=self.colors
    local color=copy(type(style)=='table'and style or style=='accent'and mix(c.panel,c.accent,.12)or c.panel)
    color[4]=color[4]*math.max(0,math.min(1,tonumber(self.settings.panelOpacity)or .65))
    love.graphics.push('all');self:slice('panel',x,y,w,h,color)
    if w>=110 and h>=68 then
        local alpha=(color[4] or 1)*.6
        local frame=copy(style=='accent'and c.accent or mix(c.line,c.text,.2));frame[4]=alpha;self:slice('frame',x,y,w,h,frame)
    end
    love.graphics.pop();self.stats.panel=self.stats.panel+1;return true
end
function Theme:control(x,y,w,h,style)
    if not self.ready then return false end
    self:configure(self.settings)
    local color=type(style)=='table' and style or style=='accent' and self.styles.ButtonPressedColor or self.styles.ButtonColor
    love.graphics.push('all');self:slice(w<h*1.5 and 'square' or 'button',x,y,w,h,color,math.min(9,h*.3));love.graphics.pop()
    self.stats.control=self.stats.control+1;return true
end
function Theme.apply(S,assets,settings)
    local skin=assets and assets.theme;if not skin then return end
    assets:setSettings(settings);skin:configure(settings)
    local style=S.GetStyle()
    for key,value in pairs(skin.styles)do
        if type(style[key])=='table'then for i=1,4 do style[key][i]=value[i]end
        else style[key]=copy(value)end
    end
    style.ControlHeight=32;style.InputPaddingY=6;style.WindowTitleH=math.max(26,style.Font:getHeight()+8);style.TooltipsEnabled=settings.showTooltips~=false
    style.TextVerticalOffset=require('app.fonts').textOffset
end
function Theme:draw(kind,x,y,w,h,color)
    if kind=='panel' then return self:panel(x,y,w,h,color)
    elseif kind=='control' then return self:control(x,y,w,h,color) end
    love.graphics.push('all');self:slice('panel',x,y,w,h,color,math.min(6,h*.25))
    if kind=='input' and w>40 and h>16 then
        local border=mix(self.colors.line,self.colors.accent,.25);border[4]=(color[4]or 1)*.75
        self:slice('inset',x,y,w,h,border,math.min(7,h*.3))
    end
    love.graphics.pop();self.stats[kind]=(self.stats[kind] or 0)+1
end
function Theme:icon(name,x,y,size,color)
    if name~='focus' and name~='target' then return false end
    if not self.focus then return false end
    love.graphics.push('all');love.graphics.setColor(color or {.86,.92,.98,1})
    love.graphics.draw(self.focus,x,y,0,size/self.focus:getWidth(),size/self.focus:getHeight());love.graphics.pop();return true
end
function Theme:rule(x,y,w,color)
    if not self.divider then return false end
    -- Preserve the ornamental right cap; stretch only the straight middle.
    local image=self.divider;local sw,sh=image:getDimensions();local cap=20;local height=9;local edge=cap*height/sh
    love.graphics.push('all');love.graphics.setColor(color or {.35,.55,.56,.7})
    local left=love.graphics.newQuad(0,0,sw-cap,sh,sw,sh);local right=love.graphics.newQuad(sw-cap,0,cap,sh,sw,sh)
    love.graphics.draw(image,left,x,y,0,math.max(0,w-edge)/(sw-cap),height/sh)
    love.graphics.draw(image,right,x+math.max(0,w-edge),y,0,math.min(edge,w)/cap,height/sh)
    love.graphics.pop();return true
end
function Theme.install(S,assets)
    local skin=assets and assets.theme;if not skin or not skin.ready then return false end
    local style=S.GetStyle();local mapping={}
    style.TextVerticalOffset=require('app.fonts').textOffset
    skin:configure(assets.settings or{})
    for key,value in pairs(skin.styles)do style[key]=copy(value)end
    local groups={panel={'WindowBackgroundColor'},title={'WindowTitleFocusedColor','WindowTitleUnfocusedColor'},
        control={'ButtonColor','ButtonHoveredColor','ButtonPressedColor'},
        input={'InputBgColor','InputEditBgColor','ComboBoxColor','ComboBoxHoveredColor','ComboBoxDropDownColor','ComboBoxDropDownHoveredColor'}}
    for kind,keys in pairs(groups)do for _,key in ipairs(keys)do mapping[style[key]]=kind end end
    local draw=require('lib.Slab.Internal.Core.DrawCommands')
    draw.SetSkin({classify=function(mode,color,w,h)
        if mode=='fill' and color and (color[4] or 1)>0 and w>0 and h>0 then return mapping[color]end
    end,draw=function(kind,x,y,w,h,color)skin:draw(kind,x,y,w,h,color)end})
    -- Use accepted control activation, never hover/paint state, as the UI sound
    -- trigger. Installing the skin repeatedly must not stack wrappers or sounds.
    S._love2gatheringSkinAssets=assets
    if not S._love2gatheringSoundHooks then
        S._love2gatheringSoundHooks=true
        for _,name in ipairs({'Button','CheckBox','TextSelectable'})do
            local original=S[name]
            S[name]=function(...)
                local accepted=original(...)
                if accepted then
                    local current=S._love2gatheringSkinAssets;local settings=current and current.settings or {}
                    if current and settings.sfxEnabled~=false then current:playSound('click',settings.sfxVolume or .45)end
                end
                return accepted
            end
        end
    end
    return true
end
return Theme
