-- UI preferences and transport only. XMage decides which priority windows hold.
local json=require('lib.json')
local Priority={groups={{label='Upkeep',key='UPKEEP',steps={'UPKEEP'}},{label='Draw',key='DRAW',steps={'DRAW'}},
    {label='Main 1',key='PRECOMBAT',steps={'PRECOMBAT_MAIN'}},{label='Combat',key='COMBAT',steps={'BEGIN_COMBAT'}},
    {label='Main 2',key='POSTCOMBAT',steps={'POSTCOMBAT_MAIN'}},{label='End step',key='END',steps={'END_TURN'}}}}
Priority.beforeDamage={label='Before combat damage',key='BEFORE_DAMAGE',steps={'DECLARE_BLOCKERS'}}
Priority.combatSteps={{label='Beginning of combat',steps={'BEGIN_COMBAT'}},{label='After attackers',steps={'DECLARE_ATTACKERS'}},
    Priority.beforeDamage,{label='After first-strike damage',steps={'FIRST_COMBAT_DAMAGE'}},
    {label='After combat damage',steps={'COMBAT_DAMAGE'}},{label='End of combat',steps={'END_COMBAT'}}}
local function copy(value) return json.decode(json.encode(value)) end
local function contains(items,value) for _,item in ipairs(items or {}) do if item==value then return true end end;return false end
function Priority.stopPresentation(model,group,side)
    local state=(model.game or{}).priority or{}
    local configured=type(state.stops)=='table'and type(state.stops[side])=='table'
    local requested=model:phaseStop(group,side)
    local enabled=false
    if configured then for _,step in ipairs(group.steps)do if contains(state.stops[side],step)then enabled=true;break end end end
    local pending=model.priorityBusy==true or state.pending==true
    local status=pending and'pending'or(not configured or requested~=enabled)and'unconfirmed'or enabled and'on'or'off'
    return{status=status,enabled=enabled,requested=requested,acknowledged=configured==true,pending=pending,
        label='Before damage · '..(status=='on'and'ON'or status=='off'and'OFF'or status=='pending'and'WAIT'or'?')}
end
function Priority.install(Model)
    function Model:priorityOptions()
        local prefs=(self.uiLayout or {}).matchPrefs or {}
        local options=prefs.priority
        if not options then
            options={autoPass=false,passWithOnlyMana=false,stops={own=json.array(),opponent=json.array()}}
            -- Migrate only the previous explicit WAIT intention, never SKIP.
            for _,group in ipairs(Priority.groups) do
                if (prefs.phaseMarkers or {})[group.key]=='WAIT' then
                    for _,step in ipairs(group.steps) do options.stops.own[#options.stops.own+1]=step;options.stops.opponent[#options.stops.opponent+1]=step end
                end
            end
        end
        local result=copy(options);result.stops=result.stops or {}
        result.autoPass=result.autoPass==true
        result.passWithOnlyMana=result.passWithOnlyMana==true
        for _,side in ipairs({'own','opponent'}) do result.stops[side]=json.array(result.stops[side] or {}) end
        return result
    end
    function Model:phaseStop(group,side)
        local options=self:priorityOptions()
        if self.replay then options=(self.game and self.game.priority) or {stops={}} end
        for _,step in ipairs(group.steps) do if contains((options.stops or {})[side],step) then return true end end
        return false
    end
    function Model:priorityCommand(command,extra)
        if self.replay or not self.game or self.game.running==false or self.priorityBusy
            or self.roomGameActive and self.roomDisconnected then return false end
        local gameId=self.game.gameId;local body=extra or {};body.command=command
        local request=(self.priorityRequest or 0)+1;self.priorityRequest=request
        self.priorityBusy=true
        self:request('engine','POST','/session/priority',body,function(data)
            if self.priorityRequest~=request then return end
            self.priorityBusy=false
            if self.game and self.game.gameId==gameId and data then self:setGame(data) end
            self.pollTimer=0
        end)
        return true
    end
    function Model:configurePriority(options)
        if self.replay or self.roomGameActive and self.roomDisconnected then return false end
        self:setUIOption('priority',options)
        if self.game and self.game.running~=false then return self:priorityCommand('configure',copy(options)) end
        return true
    end
    function Model:togglePhaseStop(group,side)
        if self.replay or self.priorityBusy then return false end
        local options=self:priorityOptions();local enabled=self:phaseStop(group,side)
        local result=json.array()
        for _,step in ipairs(options.stops[side]) do if not contains(group.steps,step) then result[#result+1]=step end end
        if not enabled then for _,step in ipairs(group.steps) do result[#result+1]=step end end
        options.stops[side]=result
        return self:configurePriority(options)
    end
    function Model:endTurn()
        local prompt=self:prompt()
        if not prompt or not prompt.priority or self.actionBusy then return false end
        return self:priorityCommand('end_turn',{promptId=prompt.id})
    end
    function Model:cancelYield() return self:priorityCommand('cancel') end
    function Model:toggleAutoPass()
        if self.priorityBusy or self.replay then return false end
        local options=self:priorityOptions();options.autoPass=not options.autoPass
        return self:configurePriority(options)
    end
    function Model:toggleManaOnlyPass()
        if self.priorityBusy or self.replay then return false end
        local options=self:priorityOptions();options.passWithOnlyMana=not options.passWithOnlyMana
        return self:configurePriority(options)
    end
end
return Priority
