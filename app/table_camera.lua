-- Presentation only: the engine remains authoritative for every seat and action.
local Camera={};Camera.__index=Camera
local function clamp(v,low,high) return math.max(low,math.min(high,v)) end
function Camera.new() return setmetatable({x=0,y=0,zoom=1},Camera) end
function Camera:configure(view,count)
    local signature=table.concat({view.x,view.y,view.w,view.h,count},':')
    if self.signature==signature then return end
    self.signature=signature
    self.view=view;self.columns=2;self.rows=math.ceil(count/2)
    -- This is a world-space table. Card sizes do not shrink to fit four seats.
    self.cellW=math.max(1040,math.min(1560,view.w*.92))
    self.cellH=math.max(760,math.min(940,view.h*.98));self.gap=22
    self.width=self.columns*(self.cellW+self.gap)-self.gap
    self.height=self.rows*(self.cellH+self.gap)-self.gap
    self.overviewZoom=math.min(view.w/self.width,view.h/self.height)
    self.focusZoom=1
    if not self.ready then self.x=self.width/2;self.y=self.height/2;self.zoom=1;self.mode='free';self:bound();self.ready=true
    elseif self.mode=='overview' then self:overview(true)
    elseif self.focusIndex then self:focus(self.focusIndex,true)
    else self:bound() end
end
function Camera:cell(index)
    return {x=((index-1)%2)*(self.cellW+self.gap),y=math.floor((index-1)/2)*(self.cellH+self.gap),w=self.cellW,h=self.cellH}
end
function Camera:bound()
    local v=self.view;local halfW=v.w/(2*self.zoom);local halfH=v.h/(2*self.zoom)
    self.x=self.width<=halfW*2 and self.width/2 or clamp(self.x,halfW,self.width-halfW)
    self.y=self.height<=halfH*2 and self.height/2 or clamp(self.y,halfH,self.height-halfH)
end
function Camera:overview(immediate)
    self.mode='overview';self.focusIndex=nil
    self.target={x=self.width/2,y=self.height/2,zoom=self.overviewZoom}
    if immediate then self.x=self.target.x;self.y=self.target.y;self.zoom=self.target.zoom;self:bound() end
end
function Camera:focus(index,immediate)
    local zoom=self.mode=='overview' and self.focusZoom or self.zoom
    self.mode='focus';self.focusIndex=index;local c=self:cell(index)
    self.target={x=c.x+c.w/2,y=c.y+math.min(c.h/2,self.view.h/(2*zoom)),zoom=zoom}
    if immediate then self.x=self.target.x;self.y=self.target.y;self.zoom=self.target.zoom;self:bound() end
end
function Camera:followTurn(playerId,turn,seats,enabled,immediate)
    if not playerId then return false end
    local key=tostring(turn or '')..':'..tostring(playerId)
    local changed=self.observedTurn~=key
    local enabledNow=enabled~=false
    local justEnabled=enabledNow and self.followEnabled==false
    self.observedTurn=key;self.followEnabled=enabledNow
    if not enabledNow or not(changed or justEnabled)then return false end
    for index,player in ipairs(seats or{})do
        if player.id==playerId then self:focus(index,immediate);return true end
    end
    return false
end
function Camera:zoomAt(factor,x,y)
    local t=self:transform();local wx,wy=(x-t.x)/self.zoom,(y-t.y)/self.zoom
    local zoom=clamp(self.zoom*factor,.45,1.65)
    self.x=wx-(x-self.view.x-self.view.w/2)/zoom
    self.y=wy-(y-self.view.y-self.view.h/2)/zoom
    self.zoom=zoom;self.target=nil;self.mode='free';self.focusIndex=nil;self:bound()
end
function Camera:update(dt,immediate)
    if not self.target then return end
    local ease=immediate and 1 or 1-math.exp(-dt*12)
    for _,k in ipairs({'x','y','zoom'}) do self[k]=self[k]+(self.target[k]-self[k])*ease end
    self:bound()
end
function Camera:pan(dx,dy)
    -- Screen deltas are already in logical UI coordinates.
    self.mode='free';self.focusIndex=nil;self.target=nil
    self.x=self.x-dx/self.zoom;self.y=self.y-dy/self.zoom;self:bound()
end
function Camera:transform()
    return {x=self.view.x+self.view.w/2-self.x*self.zoom,y=self.view.y+self.view.h/2-self.y*self.zoom,scale=self.zoom,clip=self.view}
end
function Camera:project(x,y)
    local t=self:transform();return t.x+x*t.scale,t.y+y*t.scale
end
return Camera
