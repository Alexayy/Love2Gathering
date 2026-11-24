-- Presentation only: the engine remains authoritative for every seat and action.
local Camera={};Camera.__index=Camera
local function clamp(v,low,high) return math.max(low,math.min(high,v)) end
function Camera.new() return setmetatable({x=0,y=0,zoom=1},Camera) end
function Camera:configure(view,count,requiredSeatWidth)
    -- Keep the extra room for the rest of the match, so removing a permanent
    -- does not pull the playmats and camera back together.
    self.expandedW=math.max(self.expandedW or 0,math.min(1728,math.ceil((requiredSeatWidth or 0)/128)*128))
    local rows=math.ceil(count/2);local gap=18
    local seatH=(view.h-gap*(rows-1))/rows
    local cellW=math.max(760,math.min((view.w-gap)/2,seatH*1.7),self.expandedW)
    local signature=table.concat({view.x,view.y,view.w,view.h,count,cellW},':')
    if self.signature==signature then return end
    self.signature=signature
    -- Stable world-space seats share one overview/focus camera transform.
    -- Reposition a manually panned camera with the right-hand column.
    if self.mode=='free' and self.cellW and self.x>=self.cellW+gap/2 then
        self.x=self.x+cellW-self.cellW
    end
    self.view=view;self.columns=2;self.rows=rows
    self.cellW=cellW;self.cellH=math.max(420,seatH);self.gap=gap
    self.width=self.columns*(self.cellW+self.gap)-self.gap
    self.height=self.rows*(self.cellH+self.gap)-self.gap
    self.overviewZoom=math.min(view.w/self.width,view.h/self.height)
    if not self.ready then self.ready=true;self:overview(true)
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
    local zoom=self.zoom
    if self.mode=='overview' then zoom=math.min(2,math.max(1.15,self.overviewZoom*1.6))
    elseif self.mode=='focus' and self.target then zoom=self.target.zoom end
    zoom=math.min(zoom,self.view.w/self.cellW)
    if self.view.fitSeatHeight then zoom=math.min(zoom,self.view.h/self.cellH)end
    self.mode='focus';self.focusIndex=index;local c=self:cell(index)
    self.target={x=c.x+c.w/2,y=c.y+math.min(c.h/2,self.view.h/(2*zoom)),zoom=zoom}
    if immediate then self.x=self.target.x;self.y=self.target.y;self.zoom=self.target.zoom;self:bound() end
end
function Camera:followTurn(playerId,turn,seats,enabled,immediate,blocked)
    if not playerId then return false end
    local key=tostring(turn or '')..':'..tostring(playerId)
    local changed=self.observedTurn~=key
    local enabledNow=enabled==true
    local justEnabled=enabledNow and self.followEnabled==false
    self.observedTurn=key;self.followEnabled=enabledNow
    if blocked or not enabledNow or not(changed or justEnabled)then return false end
    for index,player in ipairs(seats or{})do
        if player.id==playerId then self:focus(index,immediate);return true end
    end
    return false
end
function Camera:zoomAt(factor,x,y)
    local t=self:transform();local wx,wy=(x-t.x)/self.zoom,(y-t.y)/self.zoom
    local zoom=clamp(self.zoom*factor,math.min(.45,self.overviewZoom*.8),2.2)
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
