function love.errorhandler(message)
    io.stderr:write('THEME FAILED: '..tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
    return function()return 1 end
end
local Assets=require('app.assets');local Theme=require('app.theme');local Layout=require('app.layout');local S=require('lib.Slab')
local assets,frame,checks,clicked,selected,input,controls,buttons,choices,mouse,down
local function check(ok,label)assert(ok,label);checks=checks+1;print('THEME PASS '..label)end
local function click(box,pressed)
    assert(box,'Missing themed control');local x,y=(box.x+box.w/2)*Layout.scale,(box.y+box.h/2)*Layout.scale
    mouse.x,mouse.y=x,y;down=pressed;S.OnMouseMoved(x,y,0,0)
    if pressed then S.OnMousePressed(x,y,1,false,1)else S.OnMouseReleased(x,y,1,false,1)end
end
function love.load()
    frame,checks=0,0;clicked=0;selected='One';input='Čarobna šuma';controls,buttons,choices={},{},{};mouse={x=1,y=1};down=false
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);assets=Assets.new()
    local style=S.GetStyle();style.Font=love.graphics.newFont('assets/fonts/DejaVuSans.ttf',16)
    check(assets.theme.ready,'Both supplied Kenney packs are available at runtime')
    check(Theme.install(S,assets) and Theme.install(S,assets),'Slab skin installation is idempotent')
    for name,spec in pairs(Theme.manifest)do
        local image=assets.theme.slices[name].image;local data=love.image.newImageData('assets/kenney/theme/'..spec.file)
        local minA,maxA=1,0;for y=0,data:getHeight()-1 do for x=0,data:getWidth()-1 do local _,_,_,a=data:getPixel(x,y);minA=math.min(minA,a);maxA=math.max(maxA,a)end end
        check(#assets.theme.slices[name].quads==9 and minA==0 and maxA==1,'Verified dimensions, nine slices and real alpha for '..name)
    end
    local canvas=Assets.rasterize(230,115,function()assets:panel(8,8,210,96,{.13,.22,.29,.4})end)
    local data=canvas:newImageData();local rr,gg,bb,aa=data:getPixel(110,60)
    check(math.abs(rr-.13)<.02 and math.abs(gg-.22)<.02 and math.abs(bb-.29)<.02 and math.abs(aa-.4)<.02,'Panel preserves explicit tint and alpha instead of baking a bright background')
    local _,_,_,corner=data:getPixel(0,0);check(corner==0,'Panel leaves pixels outside the requested rectangle transparent')
    love.graphics.push('all');love.graphics.translate(17,29);love.graphics.setScissor(10,20,100,150);love.graphics.setColor(.1,.2,.3,.6)
    local beforeFont=love.graphics.getFont();assets:control(20,30,180,40,'accent');assets:frame(20,90,160,110,'purple')
    local x,y=love.graphics.transformPoint(0,0);local sx,sy,sw,sh=love.graphics.getScissor();local _,_,_,alpha=love.graphics.getColor()
    check(x==17 and y==29 and sx==10 and sy==20 and sw==100 and sh==150 and math.abs(alpha-.6)<.001 and love.graphics.getFont()==beforeFont,'Frames preserve caller transform, scissor, font and graphics state');love.graphics.pop()
    local Cursor=require('lib.Slab.Internal.Core.Cursor')
    for _,name in ipairs({'BeginComboBox','TextSelectable','Button','Input'})do
        local original=S[name];S[name]=function(id,options)
            local result=original(id,options);local x,y,w,h=Cursor.GetItemBounds()
            local target=name=='Button' and buttons or name=='TextSelectable' and choices or controls
            target[id]={x=x,y=y,w=w,h=h};return result
        end
    end
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down or false end
end
function love.update(dt)
    frame=frame+1
    if frame==4 then click(buttons['Themed action'],true)
    elseif frame==5 then click(buttons['Themed action'],false)
    elseif frame==8 then check(clicked==1,'Themed button retains real mouse dispatch and unchanged geometry');click(controls['choice'],true)
    elseif frame==9 then click(controls['choice'],false)
    elseif frame==12 then click(choices.Two,true)
    elseif frame==13 then click(choices.Two,false)
    elseif frame==16 then
        check(selected=='Two','Themed nested combo retains real selection dispatch')
        check(assets.theme.stats.panel>0 and assets.theme.stats.control>0 and assets.theme.stats.input>0 and assets.theme.stats.title>0,'Slab windows, buttons, inputs, combos and title bars execute the supplied sprites')
        Layout.setScale(1.25);S.SetScale(Layout.scale)
    elseif frame==22 then
        check(controls['choice'].y>controls['input'].y,'Nested controls preserve their vertical flow at UI scale 1.25')
    elseif frame>26 then print('THEME COMPLETE '..checks..' checks');love.event.quit(0)end
    S.Update(dt)
    S.BeginWindow('theme',{X=40,Y=50,W=650,H=480,Title='Fantasy borders · Space controls',AutoSizeWindow=false,AllowResize=false,AllowMove=false})
    S.Text('Dark mint and purple · original Kenney sprites');S.Separator();S.NewLine()
    S.BeginListBox('nested',{W=610,H=300})
    S.Text('Text entry')
    if S.Input('input',{Text=input,W=330,H=32})then input=S.GetInputText()end
    S.NewLine();S.Text('Deck choice')
    if S.BeginComboBox('choice',{Selected=selected,W=330})then for _,name in ipairs({'One','Two'})do if S.TextSelectable(name,{Selected=selected==name})then selected=name end end;S.EndComboBox()end
    S.NewLine()
    if S.Button('Themed action',{W=220,H=42})then clicked=clicked+1 end
    S.EndListBox();S.EndWindow()
end
function love.draw()
    love.graphics.clear(.026,.036,.06,1)
    love.graphics.push();love.graphics.scale(Layout.scale)
    assets:panel(750,75,330,240,'dark');assets:frame(750,75,330,240,'purple')
    assets:control(785,150,245,42,'accent');assets:divider(785,225,245,{.28,.89,.72,.8})
    for i,name in ipairs({'focus','gallery','artist','calendar','external','commander'})do assets:iconSymbol(name,765+(i-1)*48,340,29)end
    love.graphics.pop();S.Draw()
    if frame==23 then love.graphics.captureScreenshot(function(data)
        local inputBox=controls.input;local combo=controls.choice
        for label,box in pairs({input=inputBox,combo=combo})do
            local rr,gg,bb=data:getPixel(math.floor((box.x+8)*Layout.scale),math.floor((box.y+box.h/2)*Layout.scale))
            check(bb>.05 and gg>.025,'Nested themed '..label..' remains visibly rendered after clipping')
        end
        local file=assert(io.open('/tmp/love2gathering-theme.png','wb'));file:write(data:encode('png'):getString());file:close()
    end)end
end
function love.quit()S.OnQuit()end
