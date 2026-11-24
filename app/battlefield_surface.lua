local Surface={}
local texture,quad,filter
local path='assets/battlefield/courtyard.jpg'

function Surface.draw(settings,x,y,w,h)
    local opacity=math.max(0,math.min(1,settings.playmatOpacity or .88))
    if opacity==0 or w<=0 or h<=0 then return end
    if texture==nil then
        local ok,image=pcall(love.graphics.newImage,path)
        texture=ok and image or false
        if texture then
            local iw,ih=texture:getDimensions()
            quad=love.graphics.newQuad(0,0,iw,ih,iw,ih)
        end
    end
    if not texture then return end
    local selectedFilter=settings.textureFilter or 'linear'
    if selectedFilter~=filter then
        texture:setFilter(selectedFilter,selectedFilter)
        filter=selectedFilter
    end
    local iw,ih=texture:getDimensions()
    local scale=math.max(w/iw,h/ih)
    local sw,sh=w/scale,h/scale
    quad:setViewport((iw-sw)/2,(ih-sh)/2,sw,sh,iw,ih)
    love.graphics.push('all')
    local light=settings.highContrast and .38 or .90
    love.graphics.setColor(light,light,light,opacity)
    love.graphics.draw(texture,quad,x,y,0,scale,scale)
    love.graphics.pop()
end

return Surface
