-- Native distributed amounts with a rearrangeable presentation. The response
-- remains in the engine's original index order; dragging creates no rule or
-- damage-order instruction and submits nothing until confirmation.
local json=require('lib.json')
local Layout=require('app.layout')
local Presentation=require('app.card_presentation')
local UI={window='native-amount-distribution'}
local function identity(m,p)return tostring(m.game and m.game.gameId)..':'..tostring(p and p.id)end
function UI.supports(p)return p and p.type=='multi_amount'and type(p.amountMessages)=='table'and#p.amountMessages>0 end
function UI.state(m,p)
    local state={identity=identity(m,p),prompt=p,rows={},values={}}
    for index,entry in ipairs(p.amountMessages)do
        state.rows[#state.rows+1]={nativeIndex=index,entry=entry}
        state.values[index]=tostring(entry.defaultValue~=nil and entry.defaultValue or entry.min or 0)
    end
    return state
end
function UI.reorder(state,index,destination)
    if not state or state.submitting or index<1 or index>#state.rows or destination<1 or destination>#state.rows then return false end
    if index~=destination then local row=table.remove(state.rows,index);table.insert(state.rows,destination,row)end
    return true
end
function UI.values(state,p)
    if not state or not UI.supports(p)or#state.rows~=#p.amountMessages then return nil,'Review every amount.'end
    local values,total=json.array(),0
    for index,entry in ipairs(p.amountMessages)do
        local raw=state.values[index];local number=type(raw)=='string'and raw:match('^%-?%d+$')and tonumber(raw)or nil
        if not number or number~=math.floor(number)or(entry.min~=nil and number<entry.min)or(entry.max~=nil and number>entry.max)then return nil,'Each amount must be a whole number within its displayed range.'end
        values[index]=number;total=total+number
    end
    if(p.min~=nil and total<p.min)or(p.max~=nil and total>p.max)then return nil,'The assigned total must match the displayed range.',total end
    return values,nil,total
end
function UI.current(v,p)
    if UI.supports(p)then return UI.window end
    if not p and v.m.actionBusy and v.combatChoiceState and v.combatChoiceState.identity==identity(v.m,v.combatChoiceState.prompt)then return UI.window end
end
local function rect(x,y,w,h,clip)
    local left,top=math.max(x,clip.x),math.max(y,clip.y)
    return{x=left,y=top,w=math.max(0,math.min(x+w,clip.x+clip.w)-left),h=math.max(0,math.min(y+h,clip.y+clip.h)-top)}
end
local function contains(box,x,y)return box and box.w>0 and box.h>0 and x>=box.x and y>=box.y and x<=box.x+box.w and y<=box.y+box.h end
local function blocked(v)return v.m.page~='table'or v.m.replay or v.m.settingsOpen or v.m.inspectCard or v.m.zoneView or v.m.confirmConcede or v.combatStopsOpen or v.r and require('app.dice').busy(v.r)end
function UI.build(v,w,h,p)
    v.combatChoiceHits={};v.combatChoiceDrops={}
    if not UI.current(v,p)then v.combatChoiceDrag=nil;if not v.m.actionBusy then v.combatChoiceState=nil end;return false end
    if blocked(v)then v.combatChoiceDrag=nil;return true end
    local m,S=v.m,v.S
    if p and(not v.combatChoiceState or v.combatChoiceState.identity~=identity(m,p))then v.combatChoiceState=UI.state(m,p);v.combatChoiceDrag=nil end
    local state=v.combatChoiceState;p=p or state.prompt;state.prompt=p
    if not m.actionBusy and m.answeredPrompt~=p.id then state.submitting=false end
    local Choices=require('app.card_choices')
    local left,pw,docked=Choices.choicePlacement(v,w,h,1040)
    local ph=math.min(620,h-130)
    Choices.choiceWindow(v,UI.window,left,math.max(76,(h-ph)/2),pw,ph,'Assign amounts',docked)
    local Window=require('lib.Slab.Internal.UI.Window');local inner=select(1,S.GetWindowSize())-42
    local x,y=S.GetCursorPos({Absolute=true})
    S.Textf(v.r:fit(p.message or'Assign the offered amounts',inner,16,2),{W=inner,Color=v.r.colors.text})
    S.SetCursorPos(x,y+46,{Absolute=true});S.PushFont(v.r.fonts[14]);S.Textf('Drag cards to arrange the display. Type the amount for each target, then confirm.',{W=inner,Color=v.r.colors.muted});S.PopFont()
    local values,problem,total=UI.values(state,p)
    if not total then total=0;for _,value in pairs(state.values)do total=total+(tonumber(value)or 0)end end
    local range=p.min==p.max and tostring(p.min or total)or tostring(p.min or 0)..'–'..tostring(p.max or total)
    S.SetCursorPos(x,y+80,{Absolute=true});S.Text('Assigned '..total..' · required '..range,{Color=problem and v.r.colors.gold or v.r.colors.accent})
    local listH=math.max(130,ph-184);local cw,ch=140,196;local tileH=ch+104;local cols=math.max(1,math.floor((inner-18)/(cw+18)))
    S.SetCursorPos(x,y+110,{Absolute=true});local sx,sy=Window.TransformPoint(x,y+110);local clip={x=sx,y=sy,w=inner,h=listH}
    S.BeginListBox('native-amount-targets',{W=inner,H=listH})
    local bx,by=S.GetCursorPos({Absolute=true})
    for position,row in ipairs(state.rows)do
        local entry=p.amountMessages[row.nativeIndex];row.entry=entry
        local tx=bx+((position-1)%cols)*(cw+18);local ty=by+math.floor((position-1)/cols)*tileH
        S.PushID('native-amount-'..row.nativeIndex);S.SetCursorPos(tx,ty,{Absolute=true})
        local card=type(entry.card)=='table'and entry.card~=json.null and Presentation.peek(entry.card) or nil
        if card and (card.hidden or card.faceDown) then card=nil end
        if card then
            S.Button(card.name or'Target',{W=cw,H=ch,Image={Image=Choices.cardImage(v,card,cw,ch)},Tooltip=(card.name or'Target')..' · Drag to arrange · Right-click to pin preview · Middle-click for details',Disabled=m.actionBusy})
            if S.IsControlHovered()and m:prompt()then Choices.hoverCard(v,entry.card,{choice=p}) end
        else S.Rectangle({W=cw,H=ch,Color={.055,.075,.11,1},Rounding=5});S.SetCursorPos(tx+8,ty+12,{Absolute=true});S.Textf(v.r:fit(entry.message or entry.label or('Target '..row.nativeIndex),cw-16,14,7),{W=cw-16,Color=v.r.colors.muted})end
        local hx,hy=Window.TransformPoint(tx,ty);local hit=rect(hx,hy,cw,ch,clip);hit.position=position;hit.nativeIndex=row.nativeIndex;hit.card=card;hit.identity=state.identity;v.combatChoiceHits[#v.combatChoiceHits+1]=hit
        local drop=rect(hx,hy,cw,tileH-8,clip);drop.position=position;v.combatChoiceDrops[#v.combatChoiceDrops+1]=drop
        S.SetCursorPos(tx,ty+ch+8,{Absolute=true});S.PushFont(v.r.fonts[14]);S.Textf(v.r:fit(entry.message or entry.label or(card and card.name)or('Target '..row.nativeIndex),cw,14,2),{W=cw,Color=v.r.colors.text});S.PopFont()
        S.SetCursorPos(tx,ty+ch+46,{Absolute=true})
        if S.Input('amount-'..state.identity..'-'..row.nativeIndex,{Text=state.values[row.nativeIndex],NumbersOnly=true,NoDrag=true,W=cw,H=34,Align='center',ReadOnly=m.actionBusy or state.submitting,Tooltip='Allowed '..tostring(entry.min or 0)..'–'..tostring(entry.max or'not specified')})then state.values[row.nativeIndex]=S.GetInputText()end
        S.SetCursorPos(tx,ty+ch+83,{Absolute=true});S.PushFont(v.r.fonts[12]);S.Text('Allowed '..tostring(entry.min or 0)..'–'..tostring(entry.max or'not specified'),{Color=v.r.colors.muted});S.PopFont();S.PopID()
    end
    S.SetCursorPos(bx,by+math.ceil(#state.rows/cols)*tileH,{Absolute=true});S.EndListBox()
    S.SetCursorPos(x,y+ph-62,{Absolute=true})
    local currentValues,currentProblem=UI.values(state,p)
    local offered=p.choices or{};local buttonW=(inner-8*#offered)/(#offered+1)
    if S.Button(state.submitting and'Applying amounts…'or'Confirm distribution',{W=buttonW,H=36,Disabled=m.actionBusy or m.priorityBusy or not currentValues,Tooltip=currentProblem or'Send these amounts for the current native choice'})then state.submitting=true;m:answer('multi_amount',currentValues)end
    for index,choice in ipairs(offered)do
        S.SameLine({Pad=8});S.PushID('amount-option-'..index)
        if S.Button(choice.label or'Offered action',{W=buttonW,H=36,Disabled=m.actionBusy or m.priorityBusy or choice.selectable==false})then m:answerChoice(choice)end
        S.PopID()
    end
    S.EndWindow();return true
end
function UI.press(v,x,y,button)
    local state=v.combatChoiceState
    if button~=1 or blocked(v)or not state or v.m.actionBusy or not v.m:prompt()or identity(v.m,v.m:prompt())~=state.identity then return false end
    for _,hit in ipairs(v.combatChoiceHits or{})do if contains(hit,x,y)then v.combatChoiceDrag={hit=hit,identity=state.identity,startX=x,startY=y,x=x,y=y};return true end end
    return false
end
function UI.move(v,x,y)local d=v.combatChoiceDrag;if not d then return false end;d.x,d.y=x,y;d.moved=d.moved or math.abs(x-d.startX)+math.abs(y-d.startY)>5;return true end
function UI.release(v,x,y,button)
    local d=v.combatChoiceDrag;if button~=1 or not d then return false end;v.combatChoiceDrag=nil
    local p=v.m:prompt();local state=v.combatChoiceState
    if blocked(v)or not p or not state or state.identity~=d.identity or identity(v.m,p)~=d.identity or v.m.actionBusy then return true end
    if d.moved then for _,drop in ipairs(v.combatChoiceDrops or{})do if contains(drop,x,y)then UI.reorder(state,d.hit.position,drop.position);break end end end
    return true
end
function UI.draw(v)
    local d=v.combatChoiceDrag;if not d or not d.moved or blocked(v)or not d.hit.card then return end
    local image=require('app.card_choices').cardImage(v,d.hit.card,110,154)
    love.graphics.push('all');love.graphics.setColor(1,1,1,.85);love.graphics.draw(image,d.x-55,d.y-77,0,110/image:getWidth(),154/image:getHeight());love.graphics.pop()
end
return UI
