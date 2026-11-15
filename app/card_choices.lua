-- Presentation for native offered cards. All responses retain the current
-- prompt's IDs and response types; this module never decides Magic legality.
local json=require('lib.json')
local Layout=require('app.layout')
local Assets=require('app.assets')
local Combat=require('app.combat_choices')
local Presentation=require('app.card_presentation')
local Window
local UI={cache={},clock=0}
local function actualChoice(choice)return type(choice)=='table'and choice~=json.null and choice.id~=nil end
local function id(card)return tostring(card.choiceId or card.id)end
local function contains(box,x,y)return box and x>=box.x and y>=box.y and x<=box.x+box.w and y<=box.y+box.h end
local function response(card)local value=card.value;if value==nil then value=card.choiceId or card.id end;return {id=card.choiceId or card.id,responseType=card.responseType or'uuid',value=value}end
local function nativeCards(panel)
    local cards={};for _,original in ipairs(panel.cards or{})do
        local card=Presentation.peek(original)
        if card.id and not card.hidden and not card.faceDown then
            if card~=original then for _,key in ipairs({'choiceId','responseType','value','selected','selectable'})do if original[key]~=nil then card[key]=original[key]end end end
            cards[#cards+1]=card
        end
    end;return cards
end
function UI.displayCards(panel,query)
    local cards={};query=tostring(query or''):lower()
    for index,card in ipairs(nativeCards(panel))do if query==''or tostring(card.name or''):lower():find(query,1,true)then cards[#cards+1]={card=card,index=index}end end
    if tostring(panel.zone or''):upper()=='LIBRARY'and panel.stage~='order'then
        local function basic(card)
            local kind=card.type_line or(type(card.printing)=='table'and card.printing.type_line)or card.type or card.cardType or'';if type(kind)=='table'then kind=table.concat(kind,' ')end
            local supertypes=card.supertypes or(type(card.printing)=='table'and card.printing.supertypes)or{}
            local declared=false;if type(supertypes)=='table'then for _,supertype in ipairs(supertypes)do if tostring(supertype):lower()=='basic'then declared=true end end end
            kind=tostring(kind):lower();return(declared or kind:find('basic',1,true)~=nil)and kind:find('land',1,true)~=nil
        end
        table.sort(cards,function(a,b)local x,y=basic(a.card),basic(b.card);if x~=y then return x end;return a.index<b.index end)
    end
    local out={};for _,entry in ipairs(cards)do out[#out+1]=entry.card end;return out
end
function UI.selectable(m,card,prompt)
    if card.hidden or card.faceDown or card.selectable==false then return false end
    if(card.responseType or'uuid')=='uuid'and prompt and type(prompt.actionable)=='table'then
        local target=response(card).value
        for _,candidate in ipairs(prompt.actionable)do if tostring(candidate)==tostring(target)then return true end end
        return false
    end
    return true
end
function UI.state(panel)
    local state={identity=tostring(panel.interactionId),kind=panel.kind,cards={},rows={top={},bottom={},graveyard={},offered={}},committing=false}
    for _,card in ipairs(nativeCards(panel))do
        state.cards[id(card)]=card;local row=(panel.kind=='scry'or panel.kind=='surveil')and(card.selected==true and panel.selectionDestination or'top')or'offered'
        if state.rows[row]then state.rows[row][#state.rows[row]+1]=id(card)end
    end
    return state
end
function UI.place(state,cardId,destination,index)
    if state.committing or not state.rows[destination]or not state.cards[cardId]or state.cards[cardId].selectable==false then return false end
    local permitted=state.kind=='scry'and(destination=='top'or destination=='bottom')or state.kind=='surveil'and(destination=='top'or destination=='graveyard')
    if not permitted then return false end
    for _,row in pairs(state.rows)do for i=#row,1,-1 do if row[i]==cardId then table.remove(row,i)end end end
    local row=state.rows[destination];table.insert(row,math.max(1,math.min(#row+1,index or #row+1)),cardId);return true
end
function UI.nextResponse(state,prompt)
    local panel=prompt and prompt.cardPanel
    if not state.committing or not panel or tostring(panel.interactionId)~=state.identity or state.lastAnswered==prompt.id then return nil end
    local offered={};for _,card in ipairs(nativeCards(panel))do offered[id(card)]=card end
    if panel.stage=='select'and(state.kind=='scry'or state.kind=='surveil')then
        local desired={};for _,key in ipairs(state.rows[panel.selectionDestination]or {})do desired[key]=true end
        -- Native target selection keeps selected cards and permits toggling.
        -- Reconcile those explicit flags rather than toggling a UUID twice.
        for _,card in ipairs(nativeCards(panel))do if card.selected==true and not desired[id(card)]and card.selectable~=false then return response(card)end end
        for _,key in ipairs(state.rows[panel.selectionDestination]or {})do if offered[key]and offered[key].selected~=true and offered[key].selectable~=false then return response(offered[key])end end
        return actualChoice(panel.doneChoice)and panel.doneChoice or nil
    elseif panel.stage=='order'then
        local row=state.rows[panel.orderDestination or'']
        if not row then return nil end
        if panel.orderDirection=='last_chosen_topmost'then
            for i=#row,1,-1 do if offered[row[i]]and offered[row[i]].selectable~=false and offered[row[i]].selected~=true then return response(offered[row[i]])end end
        elseif panel.orderDirection=='last_chosen_bottommost'then
            for i=1,#row do if offered[row[i]]and offered[row[i]].selectable~=false and offered[row[i]].selected~=true then return response(offered[row[i]])end end
        end
    end
end
local function image(v,card,w,h)
    local hidden=card.hidden or card.faceDown
    if not hidden then local data=v.m:cardData(card)or card;local art=v.m:getArt(data,true);if art then return art end end
    if hidden then card={id='hidden-card',name='Face-down card',hidden=true}end
    local key=table.concat({Assets.rasterEpoch,tostring(v.r.fonts[12]),card.name or'',card.manaCost or'',tostring(card.rules or''),tostring(card.type or''),tostring(card.power or''),tostring(card.toughness or''),tostring(card.damage or''),tostring(card.tapped or false),json.encode(card.counters or{}),w,h,Layout.scale},'\31')
    UI.clock=UI.clock+1;local cached=UI.cache[key]
    if cached then cached.used=UI.clock;return cached.image end
    local canvas=Assets.rasterize(w*Layout.scale,h*Layout.scale,function()love.graphics.scale(Layout.scale);v.r:drawCard(card,0,0,w,h,{noHit=true,back=hidden,angle=0})end)
    UI.cache[key]={image=canvas,used=UI.clock};local count=0;for _ in pairs(UI.cache)do count=count+1 end
    if count>64 then local oldest,used;for k,item in pairs(UI.cache)do if not used or item.used<used then oldest,used=k,item.used end end;UI.cache[oldest]=nil end
    return canvas
end
UI.cardImage=image
local function clipped(rect,clip)
    local x,y=math.max(rect.x,clip.x),math.max(rect.y,clip.y);local right,bottom=math.min(rect.x+rect.w,clip.x+clip.w),math.min(rect.y+rect.h,clip.y+clip.h)
    return{x=x,y=y,w=math.max(0,right-x),h=math.max(0,bottom-y)}
end
local function button(v,label,icon,w,action,disabled)
    if v.S.Button(label,{W=w,H=32,Disabled=disabled,Image={Image=v.r.assets:buttonImage(icon,label,w,32)}})then action()end
end
local function card(v,object,w,h,zone,index,clip,immediate)
    local S=v.S;local x,y=S.GetCursorPos({Absolute=true});local sx,sy=Window.TransformPoint(x,y)
    local selecting=zone=='offered'or zone=='top'or zone=='bottom'or zone=='graveyard'
    local allowed=not selecting or UI.selectable(v.m,object,v.m:prompt())
    S.PushID('native-card-'..id(object));local clicked=S.Button(object.name or'Card',{W=w,H=h,Image={Image=image(v,object,w,h),Color=not allowed and{.36,.36,.36,.85}or nil},Tooltip=(object.name or'Card')..(allowed and' · right-click to inspect'or' · unavailable for this action · right-click to inspect'),Active=object.selected==true,Disabled=v.m.actionBusy or not allowed})
    local hit=clipped({x=sx,y=sy,w=w,h=h},clip);hit.card=object;hit.id=id(object);hit.zone=zone;hit.index=index
    v.cardChoiceHits[#v.cardChoiceHits+1]=hit
    if S.IsControlHovered()then
        v.m.choiceHover={card=object}
        if S.IsMouseClicked(2)then v.m.inspectCard=object end
    end
    if clicked and immediate and not v.cardChoiceConsumed then immediate(object)end
    S.PopID()
end
local function row(v,key,label,state,w,h,cw,ch)
    local S=v.S;S.Text(label,{Color=key=='top'and v.r.colors.accent or v.r.colors.purple});S.NewLine()
    local x,y=S.GetCursorPos({Absolute=true});x,y=Window.TransformPoint(x,y);local clip={x=x,y=y,w=w,h=h}
    local drop={x=x,y=y,w=w,h=h,zone=key,cardW=cw+12};v.cardChoiceDrops[#v.cardChoiceDrops+1]=drop
    S.BeginListBox('native-row-'..key,{W=w,H=h})
    local contentX,contentY=S.GetCursorPos({Absolute=true});drop.originX=select(1,Window.TransformPoint(contentX,contentY))
    for index,keyId in ipairs(state.rows[key])do
        if index>1 then S.SameLine({Pad=8})end
        card(v,state.cards[keyId],cw,ch,key,index,clip)
    end
    if #state.rows[key]==0 then S.Text('Drag cards here',{Color=v.r.colors.muted})end
    S.EndListBox();S.NewLine()
end
local function lookKey(m,group)
    local ids={tostring(m.game.gameId),tostring(group.id or group.label or'Look at cards')}
    for _,c in ipairs(group.cards or {})do ids[#ids+1]=tostring(c.id)end
    return table.concat(ids,':')
end
local function lookedAt(v)
    local m=v.m;v.lookDismissed=v.lookDismissed or {};local present={};local found
    for _,group in ipairs(m.game and m.game.lookedAt or {})do
        local key=lookKey(m,group);present[key]=true
        if not found and not v.lookDismissed[key]and#(group.cards or {})>0 then found={key=key,label=group.label,cards=nativeCards(group)}end
    end
    for key in pairs(v.lookDismissed)do if not present[key]then v.lookDismissed[key]=nil end end
    return found
end
function UI.prefersBoard(m,prompt)
    if not prompt then return false end
    if prompt.combat and(prompt.combat.role=='attackers'or prompt.combat.role=='blockers'or prompt.combat.role=='block_target')then return true end
    if prompt.cardPanel and prompt.cardPanel.kind=='board'then return true end
    if prompt.cardPanel and prompt.cardPanel.kind~='select'then return false end
    if prompt.type~='pick_target'then return false end
    local battlefield={};for _,player in ipairs(m.game and m.game.players or {})do for _,c in ipairs(player.battlefield or {})do battlefield[tostring(c.id)]=true end end
    local count=0
    for _,choice in ipairs(prompt.choices or {})do if choice.responseType=='uuid'then
        local target=choice.value~=nil and choice.value or choice.id
        if not battlefield[tostring(target)]then return false end
        count=count+1
    end end
    return count>0
end
function UI.currentModal(v,prompt)
    local m=v.m
    if m.page~='table'or m.replay or m.settingsOpen or m.inspectCard or m.zoneView or m.confirmConcede or v.combatStopsOpen then return nil end
    if v.r and require('app.dice').busy(v.r)then return nil end
    local amount=Combat.current(v,prompt);if amount then return amount end
    if UI.prefersBoard(m,prompt)then return nil end
    local panel=prompt and prompt.cardPanel
    if panel and UI.supports(panel)and#nativeCards(panel)>0 then return'native-card-choices'end
    if not prompt and m.actionBusy and v.cardChoiceState and v.cardChoiceState.committing and v.cardChoiceState.gameId==(m.game and m.game.gameId)then return'native-card-choices'end
    if prompt and type(prompt.pile1)=='table'and type(prompt.pile2)=='table'then
        local count=0;for _,choice in ipairs(prompt.choices or{})do if choice.responseType=='boolean'then count=count+1 end end
        if count>=2 then return'native-card-piles'end
    end
    if lookedAt(v)then return'looked-at-cards'end
end
function UI.modalKey(v,prompt,window)
    window=window or UI.currentModal(v,prompt);if not window then return nil end
    if window=='looked-at-cards'then local look=lookedAt(v);return look and(window..':'..look.key)or nil end
    local promptId=prompt and prompt.id
    if not promptId and window==Combat.window then promptId=v.combatChoiceState and v.combatChoiceState.prompt.id end
    if not promptId and window=='native-card-choices'then promptId=v.cardChoiceState and v.cardChoiceState.lastAnswered end
    return table.concat({window,tostring(v.m.game and v.m.game.gameId),tostring(promptId)},':')
end
function UI.escape(v)
    local window=UI.currentModal(v,v.m:prompt());if not window then return false end
    if window=='looked-at-cards'then local look=lookedAt(v);if look then v.lookDismissed[look.key]=true end end
    v.cardChoiceDrag=nil;v.combatChoiceDrag=nil;require('lib.Slab.Internal.UI.Region').ClearHotInstance();v.S.SetInputFocus(nil)
    -- Required native decisions stay open; only an offered Cancel button can
    -- send an actual cancellation. Escape never invents an engine answer.
    return true
end
function UI.supports(panel)
    if not panel then return false end
    if panel.kind=='select'or panel.kind=='order'then return true end
    if panel.kind~='scry'and panel.kind~='surveil'then return false end
    if panel.stage=='select'then return panel.selectionDestination==(panel.kind=='scry'and'bottom'or'graveyard')and panel.remainingDestination=='top'end
    return panel.stage=='order'and(panel.orderDestination=='top'or panel.orderDestination=='bottom')and(panel.orderDirection=='last_chosen_topmost'or panel.orderDirection=='last_chosen_bottommost')
end
function UI.combatCounts(game,combat)
    local offered,names={},{}
    for _,key in ipairs(combat and combat.legalAttackerIds or {})do offered[tostring(key)]=true end
    for _,blocker in ipairs(combat and combat.blockers or {})do for _,key in ipairs(blocker.legalAttackerIds or {})do offered[tostring(key)]=true end end
    for _,player in ipairs(game and game.players or {})do for _,c in ipairs(player.battlefield or {})do names[tostring(c.id)]=c.name end end
    local out={}
    for _,group in ipairs(game and game.combat and game.combat.groups or {})do
        local key=group.attackerId;local eligible=key and offered[tostring(key)]
        for _,candidate in ipairs(group.attackerIds or {})do if offered[tostring(candidate)]then eligible=true;key=key or candidate end end
        if eligible then
            local name=names[tostring(key)]or group.attackerName or'This attacker'
            local minimum=type(group.minBlockers)=='number'and group.minBlockers or 0
            local maximum=type(group.maxBlockers)=='number'and group.maxBlockers or 0
            if minimum>1 then out[#out+1]=name..' needs at least '..minimum..' blockers'end
            if maximum>0 then out[#out+1]=name..' allows at most '..maximum..(maximum==1 and' blocker'or' blockers')end
        end
    end
    return out
end
local function boardChoice(v,w,prompt)
    local S,m=v.S,v.m;local pw=math.min(690,w-100)
    local combat=prompt.combat
    local individuals={};local chosen={}
    if combat then
        for _,key in ipairs(combat.selectedAttackerIds or{})do chosen[tostring(key)]=true end
        for _,choice in ipairs(prompt.choices or{})do if choice.responseType=='uuid'then
            local value=choice.value~=nil and choice.value or choice.id;local object=choice.card
            if type(object)~='table'or object==json.null then
                for _,player in ipairs(m.game and m.game.players or{})do for _,candidate in ipairs(player.battlefield or{})do if tostring(candidate.id)==tostring(value)then object=candidate end end end
            end
            if type(object)=='table'and object~=json.null and not object.hidden and not object.faceDown then individuals[#individuals+1]={choice=choice,card=object,selected=chosen[tostring(value)]or choice.selected==true}end
        end end
    end
    v:window('board-card-choice',(w-pw)/2,108,pw,combat and(#individuals>0 and 330 or 190)or 110,combat and'Combat choices'or'Choose on the battlefield')
    S.Textf(v.r:fit(prompt.message or'Select a highlighted legal card',pw-34,16,2),{W=pw-34,Color=v.r.colors.text});S.NewLine()
    if combat then
        local hint=combat.message or combat.hint
        if not hint then
            local rules,seen={},{}
            for _,blocker in ipairs(combat.blockers or {})do for _,entry in ipairs(blocker.unavailable or {})do
                local detail=entry.reason
                if #(entry.rules or {})>0 then detail=(detail and(detail..' · ')or'')..table.concat(entry.rules,' · ')end
                if detail and not seen[detail]and#rules<2 then rules[#rules+1]=tostring(detail);seen[detail]=true end
            end end
            if #rules>0 then hint=table.concat(rules,' · ')end
        end
        local counts=UI.combatCounts(m.game,combat)
        if #counts>0 then hint=table.concat(counts,' · ')..(hint and(' · '..hint)or'')end
        local provisional=combat.declarationConfirmed==false and(combat.role=='attackers'and'Attacks provisional · Done confirms.'or'Blocks provisional · Done confirms.')
        if provisional then S.Text(provisional,{Color=v.r.colors.gold});S.NewLine()end
        if hint then S.PushFont(v.r.fonts[14]);S.Textf(v.r:fit(tostring(hint),pw-34,14,2),{W=pw-34,Color=v.r.colors.muted});S.PopFont();S.NewLine()end
        if v.combatToastPrompt~=prompt.id then
            v.combatToastPrompt=prompt.id
            m:toast(v.r:fit(tostring(hint or prompt.message or'Choose from the highlighted native combat options'),620,12,2))
            local toast=m.toasts and m.toasts[#m.toasts];if toast then toast.ttl=3 end
        end
    end
    if#individuals>0 then
        S.BeginListBox('individual-combat-cards',{W=pw-34,H=116})
        for index,entry in ipairs(individuals)do
            if index>1 then S.SameLine({Pad=8})end
            S.PushID('individual-combat-'..tostring(entry.choice.id))
            local disabled=m.actionBusy or entry.choice.selectable==false or not m:canSelect(entry.choice.value~=nil and entry.choice.value or entry.choice.id)
            if S.Button(entry.card.name or'Card',{W=76,H=106,Image={Image=image(v,entry.card,76,106),Color=disabled and{.36,.36,.36,.85}or nil},Active=entry.selected,Disabled=disabled,Tooltip=(entry.card.name or'Card')..(entry.selected and' · selected provisionally'or' · choose this card')})then m:answerChoice(entry.choice)end
            S.PopID()
        end
        S.EndListBox();S.NewLine()
    end
    local controls={};for _,c in ipairs(prompt.choices or {})do if c.responseType~='uuid'then controls[#controls+1]=c end end
    for index,c in ipairs(controls)do
        if index>1 then S.SameLine()end
        button(v,c.label or'Done','check',(pw-40)/math.max(1,#controls),function()m:answerChoice(c)end,m.actionBusy)
    end
    S.EndWindow()
end
local function piles(v,w,h,prompt)
    if not prompt or type(prompt.pile1)~='table'or type(prompt.pile2)~='table'then return false end
    local choices={}
    for _,choice in ipairs(prompt.choices or {})do if choice.responseType=='boolean'and type(choice.value)=='boolean'then choices[choice.value and 1 or 2]=choice end end
    if not choices[1]or not choices[2]then return false end
    local S,m=v.S,v.m;local pw,ph=math.min(980,w-70),math.min(540,h-140)
    v:window('native-card-piles',(w-pw)/2,math.max(78,(h-ph)/2),pw,ph,'Choose a pile')
    local inner=select(1,S.GetWindowSize())-42;S.Textf(v.r:fit(prompt.message or'Choose a native offered pile',inner,16,2),{W=inner,Color=v.r.colors.text});S.NewLine()
    local bx,by=S.GetCursorPos({Absolute=true});local half=(inner-18)/2;local listH=ph-155;local cw,ch=90,126
    for index=1,2 do
        local x=bx+(index-1)*(half+18);S.SetCursorPos(x,by,{Absolute=true});S.Text(index==1 and'Pile 1'or'Pile 2',{Color=v.r.colors.purple})
        S.SetCursorPos(x,by+28,{Absolute=true});local sx,sy=Window.TransformPoint(x,by+28);local clip={x=sx,y=sy,w=half,h=listH}
        S.BeginListBox('native-pile-'..index,{W=half,H=listH});local indent=(index-1)*(half+18);if indent>0 then S.Indent(indent)end;local cols=math.max(1,math.floor((half-20)/(cw+12)))
        local visible=nativeCards({cards=prompt[index==1 and'pile1'or'pile2']})
        for cardIndex,c in ipairs(visible)do if(cardIndex-1)%cols~=0 then S.SameLine({Pad=8})elseif cardIndex>1 then S.NewLine()end;card(v,c,cw,ch,'pile-'..index,cardIndex,clip,function(chosen)m.inspectCard=chosen end)end
        if #visible==0 then S.Text('No entitled card images',{Color=v.r.colors.muted})end
        if indent>0 then S.Unindent(indent)end;S.EndListBox();S.SetCursorPos(x,by+listH+40,{Absolute=true});local choice=choices[index]
        button(v,choice.label or(index==1 and'Pile 1'or'Pile 2'),'check',half,function()m:answerChoice(choice)end,m.actionBusy)
    end
    S.SetCursorPos(bx,by+listH+78,{Absolute=true});S.EndWindow();return true
end
function UI.build(v,w,h,prompt)
    Window=Window or require('lib.Slab.Internal.UI.Window')
    local m,S=v.m,v.S;v.cardChoiceHits={};v.cardChoiceDrops={};m.choiceHover=nil
    if m.replay or m.settingsOpen then v.cardChoiceDrag=nil;v.combatChoiceDrag=nil;return false end
    if v.r and require('app.dice').busy(v.r)then v.cardChoiceDrag=nil;v.combatChoiceDrag=nil;return true end
    if Combat.build(v,w,h,prompt)then return true end
    if not prompt and v.cardChoiceState and v.cardChoiceState.committing and m.actionBusy then return true end
    if UI.prefersBoard(m,prompt)then v.cardChoiceState=nil;v.cardChoiceDrag=nil;boardChoice(v,w,prompt);return true end
    if piles(v,w,h,prompt)then v.cardChoiceState=nil;v.cardChoiceDrag=nil;return true end
    local panel=prompt and prompt.cardPanel;local arrange=panel and(panel.kind=='scry'or panel.kind=='surveil')
    if panel and UI.supports(panel)and#nativeCards(panel)>0 then
        local identity=tostring(panel.interactionId or prompt.id)
        if not v.cardChoiceState or v.cardChoiceState.identity~=identity or v.cardChoiceState.gameId~=(m.game and m.game.gameId)then
            v.cardChoiceState=UI.state(panel);v.cardChoiceState.identity=identity;v.cardChoiceState.gameId=m.game and m.game.gameId;v.cardChoiceDrag=nil
        end
        local state=v.cardChoiceState
        for _,c in ipairs(nativeCards(panel))do state.cards[id(c)]=c end
        if arrange then
            local known={};for _,c in pairs(state.cards)do known[tostring(c.id)]=true end
            v.lookDismissed=v.lookDismissed or {}
            for _,group in ipairs(m.game and m.game.lookedAt or {})do
                local displayed=#(group.cards or {})>0
                for _,c in ipairs(group.cards or {})do if not known[tostring(c.id)]then displayed=false;break end end
                if displayed then v.lookDismissed[lookKey(m,group)]=true end
            end
        end
        if state.committing and state.lastAnswered==prompt.id and not m.actionBusy and m.answeredPrompt~=prompt.id then
            state.committing=false;state.lastAnswered=nil;state.error='Native response was not accepted. Review and confirm again.'
        end
        if state.committing and not m.actionBusy and not m.priorityBusy then
            local answer=UI.nextResponse(state,prompt)
            if answer then state.lastAnswered=prompt.id;m:answerChoice(answer);return true end
        end
        local pw=math.min(980,w-70);local cw=math.max(70,math.min(142,math.floor((pw-58)/math.min(6,math.max(3,#(panel.cards or {})))),math.floor((h-400)/2/1.4)));local ch=math.floor(cw*1.4)
        local ph=arrange and math.min(h-115,ch*2+285)or math.min(h-115,620)
        v:window('native-card-choices',(w-pw)/2,math.max(78,(h-ph)/2),pw,ph,panel.kind=='scry'and'Scry'or panel.kind=='surveil'and'Surveil'or'Choose a card',{BgColor={.025,.04,.06,.98}})
        if v.cardChoiceDrag and Window.IsObstructed(v.cardChoiceDrag.startX,v.cardChoiceDrag.startY)then v.cardChoiceDrag=nil end
        local inner=select(1,S.GetWindowSize())-42
        S.Textf(v.r:fit(state.error or prompt.message or'Choose from the offered cards',inner,16,2),{W=inner,Color=state.error and v.r.colors.gold or v.r.colors.text});S.NewLine()
        if arrange then
            local destination=panel.selectionDestination or(state.kind=='surveil'and'graveyard'or'bottom')
            row(v,'top','Top · leftmost card is drawn first',state,inner,ch+14,cw,ch)
            row(v,destination,destination=='bottom'and'Bottom'or'Graveyard',state,inner,ch+14,cw,ch)
            button(v,state.committing and'Applying native choices…'or'Confirm','check',inner,function()state.committing=true;state.error=nil end,m.actionBusy or m.priorityBusy or state.committing)
        else
            if S.Input('native-card-search',{Text=state.query or'',W=inner,H=34,Align='left',Tooltip='Search only the cards visible for this choice'})then state.query=S.GetInputText();state.offset=0 end;S.NewLine()
            local displayed=UI.displayCards(panel,state.query);local listH=math.max(ch+14,ph-215);local cols=math.max(1,math.floor((inner-20)/(cw+12)))
            local pageSize=math.min(24,cols*math.max(1,math.floor(listH/(ch+12))))
            state.offset=math.max(0,math.min(state.offset or 0,math.max(0,math.floor((#displayed-1)/pageSize)*pageSize)))
            if S.Button('Previous visible cards',{W=168,H=28,Disabled=state.offset==0})then state.offset=math.max(0,state.offset-pageSize)end
            S.SameLine();if S.Button('Next visible cards',{W=168,H=28,Disabled=state.offset+pageSize>=#displayed})then state.offset=state.offset+pageSize end
            S.SameLine();S.Text((#displayed==0 and'0'or(state.offset+1)..'–'..math.min(#displayed,state.offset+pageSize))..' / '..#displayed);S.NewLine()
            local x,y=S.GetCursorPos({Absolute=true});x,y=Window.TransformPoint(x,y);local clip={x=x,y=y,w=inner,h=listH}
            S.BeginListBox('native-select-cards',{W=inner,H=listH})
            for position=state.offset+1,math.min(#displayed,state.offset+pageSize)do local index=position-state.offset;local c=displayed[position]
                if(index-1)%cols~=0 then S.SameLine({Pad=8})elseif index>1 then S.NewLine()end
                card(v,c,cw,ch,'offered',position,clip,function(chosen)if UI.selectable(m,chosen,m:prompt())then m:answerChoice(response(chosen))end end)
            end
            if#displayed==0 then S.Text('No matching visible cards.',{Color=v.r.colors.muted})end
            S.EndListBox();S.NewLine()
            if actualChoice(panel.doneChoice)then button(v,panel.doneChoice.label or'Done','check',inner,function()m:answerChoice(panel.doneChoice)end,m.actionBusy)end
        end
        S.EndWindow();v.cardChoiceConsumed=false;return true
    end
    if prompt then v.cardChoiceState=nil;v.cardChoiceDrag=nil end
    if prompt and prompt.cardPanel and prompt.cardPanel.kind=='board'then return false end
    local look=lookedAt(v)
    if not look then return false end
    local pw=math.min(900,w-70);local ph=math.min(480,h-140);v:window('looked-at-cards',(w-pw)/2,math.max(78,(h-ph)/2),pw,ph,look.label or'Look at cards')
    local inner=select(1,S.GetWindowSize())-42;S.Text('Look only · right-click a card for details',{Color=v.r.colors.muted});S.NewLine()
    local x,y=S.GetCursorPos({Absolute=true});x,y=Window.TransformPoint(x,y);local clip={x=x,y=y,w=inner,h=ph-115};local cw,ch=120,168;local cols=math.max(1,math.floor((inner-20)/(cw+12)))
    S.BeginListBox('looked-at-images',{W=inner,H=ph-115})
    for index,c in ipairs(look.cards)do if(index-1)%cols~=0 then S.SameLine({Pad=8})elseif index>1 then S.NewLine()end;card(v,c,cw,ch,'look',index,clip,function(chosen)m.inspectCard=chosen end)end
    S.EndListBox();S.NewLine();button(v,'Close','close',inner,function()v.lookDismissed[look.key]=true end,false);S.EndWindow();return false
end
function UI.press(v,x,y,mouseButton)
    if v.m.game and v.m.game.running==false then return false end
    if v.m.page~='table'or v.m.replay or v.m.settingsOpen or v.m.inspectCard or v.m.zoneView or v.m.confirmConcede or v.combatStopsOpen then return false end
    if v.r and require('app.dice').busy(v.r)then return false end
    if Combat.press(v,x,y,mouseButton)then return true end
    for i=#(v.cardChoiceHits or {}),1,-1 do local hit=v.cardChoiceHits[i]
        if contains(hit,x,y)then
            if mouseButton==2 then v.m.inspectCard=hit.card;return true end
            if mouseButton==1 and not v.m.actionBusy and hit.card.selectable~=false and v.cardChoiceState and v.cardChoiceState.gameId==(v.m.game and v.m.game.gameId)and not v.cardChoiceState.committing and(hit.zone=='top'or hit.zone=='bottom'or hit.zone=='graveyard')then
                v.cardChoiceDrag={hit=hit,startX=x,startY=y,x=x,y=y,state=v.cardChoiceState};return true
            end
        end
    end
    return false
end
function UI.move(v,x,y)
    if Combat.move(v,x,y)then return true end
    local drag=v.cardChoiceDrag;if not drag then return false end
    drag.x,drag.y=x,y;drag.moved=drag.moved or math.abs(x-drag.startX)+math.abs(y-drag.startY)>5;return true
end
function UI.release(v,x,y,mouseButton)
    if Combat.release(v,x,y,mouseButton)then return true end
    local drag=v.cardChoiceDrag;if mouseButton~=1 or not drag then return false end
    v.cardChoiceDrag=nil;v.cardChoiceConsumed=true
    local prompt=v.m:prompt();local panel=prompt and prompt.cardPanel
    if v.m.page~='table'or v.m.replay or v.m.settingsOpen or v.m.inspectCard or v.m.zoneView or v.m.confirmConcede or v.m.actionBusy or v.combatStopsOpen or v.cardChoiceState~=drag.state or drag.state.gameId~=(v.m.game and v.m.game.gameId)or not panel or tostring(panel.interactionId or prompt.id)~=drag.state.identity then return true end
    if drag.moved then for _,drop in ipairs(v.cardChoiceDrops or {})do if contains(drop,x,y)then
        local index=math.floor((x-(drop.originX or drop.x))/drop.cardW)+1;UI.place(v.cardChoiceState,drag.hit.id,drop.zone,index);break
    end end end
    return true
end
function UI.draw(v)
    Combat.draw(v)
    local drag=v.cardChoiceDrag;if v.m.page~='table'or v.m.replay or v.m.settingsOpen or v.m.inspectCard or not drag or not drag.moved then return end
    love.graphics.push('all');love.graphics.setColor(1,1,1,.85);local art=image(v,drag.hit.card,110,154);love.graphics.draw(art,drag.x-55,drag.y-77,0,110/art:getWidth(),154/art:getHeight());love.graphics.pop()
end
return UI
