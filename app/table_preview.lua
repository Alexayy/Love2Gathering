local Layout=require('app.layout')
local Presentation=require('app.card_presentation')
local Traits=require('app.card_traits')
local RichText=require('app.richtext')
local Text=require('app.utf8_text')

local Preview={}
local margin=12

-- The preview lives in screen space. It never registers a hit or takes focus.
function Preview.geometry(r,w,h,footerHeight,pinned)
    local safe=Layout.table(w,h,r.model).safe
    local top=safe.viewport.y+4
    local bottom=h-66
    local maxWidth=math.min(386,w*.23)
    local v=r.view
    local window=v and (v.inputLock or v.cardChoiceModal)
    local form=v and (v.inputLockBounds or v.floatBases and v.floatBases[window or ''])
    if form and form.x>=180+2*margin then maxWidth=math.min(maxWidth,form.x-2*margin)end
    local height=math.min(bottom-top-footerHeight,maxWidth*1.4)
    local width=height/1.4
    local x=margin
    if not form then
        if r.model.logOpen then x=safe.history.x+safe.history.w+margin
        elseif not r.multiplayerView then
            -- Keep both duel life totals and their player targets visible.
            for _,player in pairs(r.playerRects or {})do
                local edge=player.x+player.w+margin
                if edge+width<w/2 then x=math.max(x,edge)end
            end
        end
    end
    local total=height+footerHeight
    local y=top+math.max(0,(bottom-top-total)*.32)
    local mx,my=Layout.mouse()
    if not pinned and mx>=x-margin and mx<=x+width+margin and my>=y-margin and my<=y+total+margin then
        if mx-x-margin>=180 then
            width=mx-x-margin;height=width*1.4;total=height+footerHeight
        elseif my+margin+total<=bottom then y=my+margin
        elseif my-margin-total>=top then y=my-margin-total
        else x=math.min(w-width-margin,mx+margin) end
    end
    return {x=x,y=y,w=width,h=total,cardH=height}
end

local function metadata(r,card)
    local colors=r.colors
    local rows={}
    local function add(text,color)rows[#rows+1]={text=text,color=color}end
    local players=r.boardPlayers or {}
    local owner,controller=players[card.ownerId],players[card.controllerId]
    local battlefield=card.zone=='BATTLEFIELD' or card.permanent or (r.boardCards or {})[card.id]==card
    if battlefield then
        local typeLine=Presentation.currentTypeLine(card)
        if typeLine~='' then add(typeLine,colors.gold)end
    end
    local stats=Presentation.stats(card)
    if stats then add(stats.label,stats.damage>0 and colors.red or colors.text)end
    if battlefield then
        local counters=Presentation.counterSummary(card)
        if counters~='' then add('Counters · '..counters,colors.gold)end
        if not card.faceDown and not card.hidden then
            local granted={}
            for _,trait in ipairs(Traits.entries(card))do
                if trait.gained then granted[#granted+1]=trait.label end
            end
            if #granted>0 then add('Granted · '..table.concat(granted,', '),colors.gold)end
        end
    end
    if owner and type(owner.name)=='string' then add('Owner · '..owner.name,r:playerColor(owner))end
    if controller and controller~=owner and type(controller.name)=='string' then add('Controller · '..controller.name,r:playerColor(controller))end
    local commander=(r.boardCommanders or {})[card.id]
    if commander then add(Presentation.commanderLabel(commander),colors.gold)end
    local linked=card.linkedExile or {}
    local attached=(r.boardAttached or {})[card.id] or {}
    for _,group in ipairs({{attached,'Attached'},{linked,'Linked exile'}})do
        if #group[1]>0 then
            local names={}
            for i=1,math.min(3,#group[1])do
                local item=group[1][i]
                names[i]=(item.hidden or item.faceDown) and 'Face-down card' or item.name or 'Card'
            end
            if #group[1]>#names then names[#names+1]='+'..(#group[1]-#names)end
            add(group[2]..' · '..table.concat(names,', '),colors.muted)
        end
    end
    return rows
end

local function fallback(r,card,data,box)
    local x,y,width,height=box.x+14,box.y+13,box.w-28,box.cardH-26
    local colors=r.colors
    local name=Text.clean(card.name or data.name or 'Card')
    local title=r:fit(name,width,22,2)
    r:strong(title,x,y,22,colors.text,width)
    local offset=(title:find('\n',1,true) and 2 or 1)*r:font(22):getHeight()+6
    local cost=Presentation.manaCost(card,data)
    if cost~='' then
        offset=offset+RichText.draw(r,cost,x,y+offset,width,{size=17,iconSize=20,lineSpacing=1,maxLines=2})+5
    end
    local kind=Presentation.currentTypeLine(card)
    if kind=='' then kind=data.type_line or data.type or '' end
    if type(kind)=='table'then kind=table.concat(kind,' ')end
    offset=offset+RichText.draw(r,kind,x,y+offset,width,{size=16,lineSpacing=1,maxLines=2,color=colors.gold})+8
    love.graphics.setColor(colors.line)
    love.graphics.line(x,y+offset,x+width,y+offset)
    offset=offset+10
    local rules=card.currentRules or card.rules or data.oracle_text or ''
    if rules=='' then rules=data.oracle_text or '' end
    local size=16
    local layout=RichText.layout(r,rules,width,{size=size,lineSpacing=2})
    if layout.height>height-offset then
        size=14
        local lineHeight=math.max(r:font(size):getHeight(),size*1.08)+2
        layout=RichText.layout(r,rules,width,{size=size,lineSpacing=2,maxLines=math.max(1,math.floor((height-offset)/lineHeight))})
    end
    RichText.draw(r,rules,x,y+offset,width,{layout=layout,color=colors.text})
end

function Preview.draw(r,card,w,h,pinned,context)
    if not card or card.hidden and not card.faceDown then return end
    local face=Presentation.peek(card)
    local rows=metadata(r,card)
    local line=math.ceil(math.max(r:font(14):getHeight(),16)+2)
    local footerHeight=#rows>0 and #rows*line+12 or 0
    local box=Preview.geometry(r,w,h,footerHeight,pinned)
    local stack=context and context.stackId and r.model:tableStackEntry(context)
    local rule=stack and stack.rules
    if type(rule)=='table' then rule=table.concat(rule,'\n') end
    local ruleLayout,ruleHeight=nil,0
    if type(rule)=='string' and rule~='' then
        -- Reserve room under the scan for this particular stack object's rule.
        -- Different abilities of the same permanent share a source image.
        local maxLines=math.max(3,math.min(8,math.floor((h-230)*.26/line)))
        for _=1,maxLines+1 do
            local measured=box.w
            ruleLayout=RichText.layout(r,rule,measured-20,{size=15,lineSpacing=1,maxLines=maxLines})
            ruleHeight=ruleLayout.height+line+12
            box=Preview.geometry(r,w,h,footerHeight+ruleHeight,pinned)
            if box.w>=measured then break end
        end
    end
    local x,y,width,height=box.x,box.y,box.w,box.cardH
    local colors=r.colors
    love.graphics.push('all')
    love.graphics.setColor(.012,.019,.028,1)
    love.graphics.rectangle('fill',x,y,width,box.h,8,8)
    if face.hidden or face.faceDown then
        r.assets:cardBack(x,y,width,height,r.model.settings.cardBackStyle)
    else
        -- Resolve the entitled native object before catalog enrichment so exact
        -- printings, faces, mutate components and token identities remain intact.
        local image=r.model:getArt(face,false,'normal',{priority='hand'})
        if image then
            local iw,ih=image:getDimensions()
            local scale=math.min(width/iw,height/ih)
            love.graphics.setColor(1,1,1,1)
            love.graphics.draw(image,x+(width-iw*scale)/2,y+(height-ih*scale)/2,0,scale,scale)
        else fallback(r,face,r.model:cardData(face) or face,box)end
    end
    if ruleLayout then
        love.graphics.setColor(colors.line);love.graphics.line(x+8,y+height,x+width-8,y+height)
        r:strong(stack.kind=='spell' and 'Spell on the stack' or 'Ability on the stack',x+10,y+height+4,14,colors.gold,width-20)
        RichText.draw(r,rule,x+10,y+height+line+6,width-20,{layout=ruleLayout,color=colors.text})
    end
    for i,row in ipairs(rows)do
        RichText.draw(r,row.text,x+8,y+height+ruleHeight+6+(i-1)*line,width-16,{size=14,iconSize=16,lineSpacing=1,maxLines=1,color=row.color})
    end
    love.graphics.setColor(pinned and colors.accent or colors.line);love.graphics.setLineWidth(pinned and 2 or 1)
    love.graphics.rectangle('line',x,y,width,box.h,8,8)
    love.graphics.pop()
    return box
end

return Preview
