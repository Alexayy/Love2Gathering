-- Staged exact editions; only an explicitly chosen candidate forces its image.
local UI={}
local Cursor=require('lib.Slab.Internal.Core.Cursor')
local Draw=require('lib.Slab.Internal.Core.DrawCommands')
local function button(v,label,icon,w,options)
 options=options or{};options.W=w;options.H=36
 options.Image={Image=v.r.assets:buttonImage(icon,label,w,36,{font=v.r.fonts[14],iconSize=18})}
 return v.S.Button(label,options)
end
function UI.build(v,w,h)
 local S,m,r=v.S,v.m,v.r;local p=m.cardPrintingPicker;if not p then return false end
 local pw,ph=math.min(1120,w-64),math.min(880,h-64);local inner=pw-40
 local color=r.colors.panel or{.035,.055,.08}
 v:window('card-printing-picker',(w-pw)/2,(h-ph)/2,pw,ph,'Edition and artwork',{Layer='Dialog',BgColor={color[1],color[2],color[3],1}})
 S.Textf(p.name,{W=inner,Color=r.colors.accent});S.NewLine()
 local searchW,setW=math.floor(inner*.40),math.floor(inner*.33)
 if S.Input('printing-search',{Text=p.query,W=searchW,H=36,Align='left',Tooltip='Filter this card’s editions by set, collector number, year or artist'})then m:filterCardPrintings(S.GetInputText())end
 S.SameLine()
 local selectedSet='All sets';for _,set in ipairs(p.sets)do if set.code==p.set then selectedSet=(set.code or''):upper()..' · '..set.name;break end end
 if S.Button('printing-set',{W=setW,H=36,Image={Image=r.assets:buttonImage('collection',r:fit(selectedSet,setW-50,16,1),setW,36,{font=r.fonts[14],iconSize=18})},Tooltip='Choose a set in a searchable grid'})then
  require('app.set_picker').open(v,{id='printing-sets',owner=p,title='Choose a set for '..p.name,items=function()return p.sets end,selected=p.set,busy=function()return p.busy end,error=function()return p.error end,onSelect=function(code)m:filterCardPrintings(nil,code)end,isCurrent=function()return m.cardPrintingPicker==p and m.editDeck==p.deck and m.editGeneration==p.generation and m.page=='builder'end})
 end
 S.SameLine()
 local treatments={all='All treatments',extended='Extended art',borderless='Borderless',showcase='Showcase'}
 if S.BeginComboBox('printing-treatment',{Selected=treatments[p.variant],W=inner-searchW-setW-8,H=36,WinH=170})then
  for _,key in ipairs({'all','extended','borderless','showcase'})do if S.TextSelectable(treatments[key],{Selected=p.variant==key})then m:filterCardPrintings(nil,nil,key)end end
  S.EndComboBox()
 end
 S.NewLine()
 local zoneName=({main='the main deck',commander='the command zone',sideboard='the sideboard'})[p.zone]or p.zone
 S.Textf('Choose an edition for every copy in '..zoneName..'. Selecting a tile downloads its image if needed. Apply changes the deck; Cancel keeps its current edition.',{W=inner,Color=r.colors.muted})
 S.NewLine()
 -- Reserve title, wrapped guidance and footer rows at the largest body font.
 S.BeginListBox('card-printing-grid',{W=inner,H=math.max(130,ph-342)})
 local ox,oy=S.GetCursorPos({Absolute=true});local columns=math.max(3,math.min(6,math.floor((inner-18)/160)))
 local gap=12;local cw=math.floor((inner-24-gap*(columns-1))/columns);local ch=math.floor(cw*1.4);local tileH=ch+75
 for index,item in ipairs(p.items)do
  local column=(index-1)%columns;local row=math.floor((index-1)/columns);local offset=column*(cw+gap)
  S.Indent(offset);S.SetCursorPos(ox+offset,oy+row*tileH,{Absolute=true});S.PushID(item.printing_id)
  local density=require('app.layout').scale*(love.window and love.window.getDPIScale and love.window.getDPIScale()or 1)
  local active=p.selectedId==item.printing_id;local art,state=m:getCardPrintingArt(item,cw*density<=256 and'thumb'or nil)
  local tooltip=item.name..' · '..(item.set_name or item.set or'')..' #'..tostring(item.collector_number or'')..' · '..(item.artist or'')
  local options={W=cw,H=ch,Active=active,Tooltip=tooltip}
  if art then options.Image={Image=art,W=cw-8,H=ch-8}
  else options.Image={Image=r.assets:buttonImage('gallery',state=='loading'and'Loading…'or'Not cached',cw-8,ch-8,{font=r.fonts[14],iconSize=22})}end
  if S.Button(item.name,options)then m:selectCardPrinting(item.printing_id)end
  if active then local x,y=Cursor.GetItemBounds();Draw.Rectangle('line',x+1,y+1,cw-2,ch-2,r.colors.accent,4,nil,3)end
  S.SetCursorPos(ox+offset,oy+row*tileH+ch+7,{Absolute=true})
  S.PushFont(r.fonts[12]);S.Textf((active and'Selected · 'or'')..(item.set or''):upper()..' #'..tostring(item.collector_number or''),{W=cw,Color=active and r.colors.accent or r.colors.text})
  S.Textf(r:fit(item.set_name or'',cw,12,1),{W=cw,Color=r.colors.muted})
  S.Textf(r:fit(art and(item.artist or'')or state=='loading'and'Loading artwork…'or'Image not cached',cw,12,1),{W=cw,Color=r.colors.muted});S.PopFont()
  S.PopID();S.Unindent(offset)
 end
 if #p.items==0 then S.Textf(p.error or(p.busy and'Loading editions…'or'No editions match these filters.'),{W=inner-24,Color=p.error and r.colors.gold or r.colors.muted})end
 S.EndListBox();S.NewLine()
 S.Textf(p.selected and('Selected: '..(p.selected.set or''):upper()..' #'..tostring(p.selected.collectorNumber or''))or'Default printing',{W=inner,Color=r.colors.accent})
 if (m.deckRevision or 0)~=p.revision then S.Textf('The deck changed. Close and reopen this picker before applying an edition.',{W=inner,Color=r.colors.gold})end
 S.NewLine()
 if button(v,'Previous','previous',110,{Disabled=p.busy or p.offset==0})then p.offset=math.max(0,p.offset-12);m:refreshCardPrintings()end
 S.SameLine();if button(v,'Next','next',100,{Disabled=p.busy or p.offset+#p.items>=p.total})then p.offset=p.offset+12;m:refreshCardPrintings()end
 S.SameLine();if button(v,'Default art','gallery',145)then m:confirmCardPrinting(true)end
 S.SameLine();if button(v,'Apply edition','check',170,{Disabled=not p.selectedId or(m.deckRevision or 0)~=p.revision})then m:confirmCardPrinting()end
 S.SameLine();if button(v,'Cancel','cancel',100)then m:closeCardPrintings()end
 S.EndWindow();return true
end
return UI
