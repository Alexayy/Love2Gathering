-- A visible, measured startup gate. No automatic source update or image fetch.
local json=require('lib.json')
local Startup={};Startup.__index=Startup
local labels={dependencies='Dependencies',storage='Database and image cache',version='Installed version',assets='Resources',catalog='Card catalog',build='XMage build',bridge='XMage bridge',rooms='Private rooms',modules='Client modules',graphics='Graphics and fonts',audio='Sound resources',ready='Services ready'}
function Startup.new(model,renderer)
    local modules={}
    for _,name in ipairs(love.filesystem.getDirectoryItems('app'))do if name:match('%.lua$')and name~='http_worker.lua'and name~='startup.lua'then modules[#modules+1]='app.'..name:gsub('%.lua$','')end end
    table.sort(modules)
    local resources={};local manifest=require('assets.kenney.runtime.manifest');local seen={}
    for _,family in ipairs({'icons','cursors','surfaces','cardBacks','sounds'})do
        for name,spec in pairs(manifest[family]or{})do if not seen[spec.path]then seen[spec.path]=true;resources[#resources+1]={family=family,name=name,path=spec.path}end end
    end
    table.sort(resources,function(a,b)return a.path<b.path end)
    return setmetatable({m=model,r=renderer,modules=modules,resources=resources,moduleIndex=1,resourceIndex=1,checks={},phase='modules',poll=0,filePoll=0,path=os.getenv('LOVE2GATHERING_STARTUP_STATUS'),time=0},Startup)
end
function Startup:check(key,state,message)
    self.checks[key]={stage=key,state=state,message=message or labels[key]or key}
end
function Startup:launcher()
    if not self.path then return true end
    local file=io.open(self.path,'rb');if not file then return false end
    local content=file:read(65537);file:close()
    if not content or#content>65536 then self.error='Startup status is invalid';return false end
    local ok,data=pcall(json.decode,content)
    if not ok or type(data)~='table'then return false end
    self.status=data
    if data.state=='error'then self.error=data.message or'Local services could not start';return false end
    return data.state=='ready'
end
function Startup:update(dt)
    self.time=self.time+dt;self.m.api:update()
    if self.error then return end
    local ok,err=pcall(function()
        if self.phase=='modules'then
            local name=self.modules[self.moduleIndex]
            if name then require(name);self.moduleIndex=self.moduleIndex+1;self:check('modules','loading','Loading '..name)
            else self:check('modules','ready','Client modules loaded');self.phase='assets'end
        elseif self.phase=='assets'then
            local resource=self.resources[self.resourceIndex]
            if resource then
                assert(love.filesystem.getInfo(resource.path),'Missing resource: '..resource.path)
                if resource.family=='icons'then self.r.assets:iconImage(resource.name,24);assert(self.r.assets.runtimeImages[resource.path],'Could not decode '..resource.path)
                elseif resource.family=='surfaces'or resource.family=='cardBacks'then assert(self.r.assets.surfaces:load({path=resource.path}),'Could not decode '..resource.path)
                elseif resource.family=='cursors'then local decoded=love.image.newImageData(resource.path);decoded:release()
                elseif resource.family=='sounds'and love.sound then local decoded=love.sound.newSoundData(resource.path);decoded:release()end
                self.resourceIndex=self.resourceIndex+1;self:check('assets','loading','Preparing '..resource.family..' · '..self.resourceIndex..' / '..#self.resources)
            else self:check('assets','ready','Curated resources decoded; card artwork streams from local storage');self.phase='graphics'end
        elseif self.phase=='graphics'then
            local canvas=love.graphics.newCanvas(48,48);local previous=love.graphics.getCanvas()
            love.graphics.push('all')
            local warmed,problem=pcall(function()
                love.graphics.setCanvas(canvas);love.graphics.clear(0,0,0,0)
                self.r.assets:surface('spotlight',0,0,48,48,{.4,.8,.7,.5});love.graphics.setFont(self.r.fonts[16]);love.graphics.print('Aa',2,2)
            end)
            love.graphics.setCanvas(previous);love.graphics.pop();canvas:release()
            if not warmed then error(problem,0)end
            self:check('graphics','ready','Font atlases, image masks and graphics surface ready');self.phase='services'
        end
    end)
    if not ok then self.error=tostring(err);return end
    self.filePoll=self.filePoll-dt
    if self.filePoll<=0 then self.filePoll=.2;self.servicesStarted=self:launcher()end
    if self.phase~='services'or not self.servicesStarted then return end
    self.poll=self.poll-dt
    if self.poll<=0 and not self.polling then
        self.poll=1;self.polling=3
        for _,service in ipairs({'catalog','engine','room'})do
            self.m.api:request(service,'GET','/health',nil,function(data,problem,code)
                self.polling=self.polling-1
                if not problem and(not code or code<400)then self[service]=data end
            end)
        end
    end
    local catalog=self.catalog;local engine=self.engine;local room=self.room
    if catalog and catalog.ready and engine and engine.engine=='XMage'and room and(room.status=='ok'or room.ok)then
        self.m.catalogHealth=catalog;self.m.engineHealth=engine
        self.ready=true;self.m.startupReport={checks=self.checks,launcher=self.status};self:check('ready','ready','Client ready')
    elseif catalog and catalog.index and catalog.index.state=='error'then self.error=catalog.index.error or'Card metadata index failed';self.allowOffline=true
    elseif catalog and self.time>8 and not self.path then self.message='Some local services are unavailable. The saved library can still be opened.';self.allowOffline=true
    elseif self.time>30 and not catalog then self.message='Waiting for the local catalog. Start this client with run.sh.'
    elseif catalog and not catalog.ready then self.message='Indexing local card metadata · '..tostring((catalog.index or{}).cards or 0)..' cards'
    else self.message='Checking catalog, XMage bridge and private rooms'end
end
function Startup:progress()
    if self.ready then return 1 end
    local localProgress=self.phase=='modules'and .25*self.moduleIndex/math.max(1,#self.modules)or self.phase=='assets'and(.25+.5*self.resourceIndex/math.max(1,#self.resources))or .8
    return math.min(.97,self.path and(localProgress*.35+math.min(.95,self.status and self.status.progress or 0)*.65)or localProgress)
end
function Startup:draw()
    local w,h=love.graphics.getDimensions();local assets=self.r.assets;local colors=self.r.colors
    love.graphics.clear(.025,.035,.06,1);assets:background(w,h,self.m.settings)
    assets:surface('gradient',0,0,w,h,{.015,.024,.05,.94})
    local width=math.min(780,w-64);local x=(w-width)/2;local y=math.max(34,(h-570)/2)
    assets:panel(x,y,width,math.min(570,h-68),'dark')
    love.graphics.setColor(1,1,1,1);local font=assets:titleFont(32,self.m.settings);love.graphics.setFont(font)
    assets:iconSymbol('commander',x+34,y+26,42,colors.gold);love.graphics.print('Love: 2 Gathering',x+92,y+30)
    assets:surface('halo',x+width-115,y+22,65,65,{colors.accent[1],colors.accent[2],colors.accent[3],.28})
    local rows={};for _,item in ipairs(self.status and self.status.checks or{})do rows[#rows+1]=item end
    for _,key in ipairs({'modules','assets','graphics'})do if self.checks[key]then rows[#rows+1]=self.checks[key]end end
    if self.status and self.status.version then love.graphics.setFont(self.r.fonts[12]);love.graphics.setColor(colors.muted);love.graphics.print('Installed revision · '..tostring(self.status.version),x+92,y+72)end
    local top=y+110;local rowHeight=math.min(30,(math.min(570,h-68)-230)/math.max(1,#rows))
    for i,item in ipairs(rows)do
        local rowY=top+(i-1)*rowHeight;local ready=item.state=='ready';local tint=ready and colors.accent or colors.muted
        assets:iconSymbol(ready and'check'or'timer',x+34,rowY+2,18,tint)
        love.graphics.setFont(self.r.fonts[14]);love.graphics.setColor(tint);love.graphics.print(labels[item.stage]or item.stage or'Resource',x+64,rowY)
    end
    local footer=y+math.min(570,h-68)-122
    love.graphics.setFont(self.r.fonts[14]);love.graphics.setColor(self.error and colors.red or colors.text)
    love.graphics.printf(self.error or self.message or(self.status and self.status.message)or'Preparing client modules',x+34,footer,width-68,'left')
    assets.surfaces:slider(x+34,footer+55,width-68,26,self:progress(),colors)
    if self.allowOffline then
        local bx,by,bw,bh=x+34,footer+85,math.min(330,width-68),34;self.continueBounds={x=bx,y=by,w=bw,h=bh}
        assets:control(bx,by,bw,bh,'accent');love.graphics.setFont(self.r.fonts[14]);love.graphics.setColor(colors.text);love.graphics.printf('Continue to saved library',bx,by+6,bw,'center')
    elseif self.error then
        love.graphics.setFont(self.r.fonts[12]);love.graphics.setColor(colors.muted);love.graphics.printf('Close this window after reviewing the error. Logs are in .runtime.',x+34,footer+90,width-68,'left')
    end
end
function Startup:press(x,y,button)
    local b=self.continueBounds
    if button==1 and self.allowOffline and b and x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then
        self.m.catalogHealth=self.catalog or{};self.m.engineHealth=self.engine or{};self.ready=true;self.m.startupReport={checks=self.checks,launcher=self.status,offline=true,error=self.error};return true
    end
end
return Startup
