-- Exact per-deck card illustrations. Names/counts/legality remain unchanged.
local API=require('app.api')
local json=require('lib.json')
local Printings={}
local zones={'commander','main','sideboard'}
local function copy(value)return json.decode(json.encode(value))end
local function now()return love and love.timer and love.timer.getTime()or os.clock()end
local function member(deck,name,zone)
 for _,z in ipairs(zone and{zone}or zones)do for _,e in ipairs(deck and deck[z]or{})do if e.name==name then return e,z end end end
end
local function selected(deck,name,zone,seed)
 local choices={};local total=0
 for _,selection in ipairs(deck and deck.printingSelections or{})do
  if selection.name==name and(not zone or selection.zone==zone)and selection.printingId then choices[#choices+1]=selection;total=total+(selection.count or 1)end
 end
 if total==0 then return end
 local hash=0;for i=1,#tostring(seed or name)do hash=(hash*31+tostring(seed or name):byte(i))%2147483647 end
 local index=hash%total
 for _,choice in ipairs(choices)do index=index-(choice.count or 1);if index<0 then return choice end end
end
Printings.selected=selected
function Printings.install(Model)
 function Model:printingDeck(card)
  if self.page=='builder'then return self.editDeck end
  if not self.game or self.page~='table'then return nil end
  -- A native visible-card projection carries its owner's exact choice. This
  -- fallback serves older local practice frames; never borrow a human's deck
  -- for a room opponent or another recording.
  local owner=card.ownerId;local player
  for _,p in ipairs(self.game.players or{})do if owner==p.id then player=p;break end end
  if not player then return end
  local localPlayer=false
  if self.game.localPlayerId then localPlayer=player.id==self.game.localPlayerId
  else
   local explicit=false;local humans=0
   for _,p in ipairs(self.game.players or{})do if p.isLocal~=nil then explicit=true end;if p.human then humans=humans+1 end end
   localPlayer=explicit and player.isLocal==true or not explicit and humans==1 and player.human==true
  end
  if self.replay then
   local metadata=self.replay.metadata or{}
   if localPlayer then return metadata.playerDeck end
   if player.human or player.isHuman then return end
   local bots=metadata.bots or{};local seat=tonumber(player.seat)
   return seat and bots[seat]and bots[seat].deck or nil
  end
  if self.roomConnectionId then return localPlayer and self:findDeck(self.roomDeckId)or nil end
  local request=self.lastMatchRequest
  if request then
   if localPlayer then return request.deck end
   if player.human or player.isHuman then return end
   local seat=tonumber(player.seat)
   if request.bots and seat and request.bots[seat]then return request.bots[seat].deck end
   return request.botDeck
  end
  return localPlayer and self:findDeck(self.activeDeckId or self.lastMatchDeckId)or nil
 end
 function Model:cardPrintingSelection(card,zone,deck)
  if not card then return end
  return selected(deck or self:printingDeck(card),card.name or card.artName,zone,card.objectId or card.id or card.name)
 end
 function Model:cardPrintingLabel(card,zone)
  local choice=self:cardPrintingSelection(card,zone,self.editDeck)
  return choice and((choice.set or''):upper()..' '..(choice.collectorNumber or''))or'Default printing'
 end
 function Model:printingData(card,data)
  if not card or card.hidden or card.faceDown or card.token or card.isToken or card.tokenImageId then return data end
  local choice=not card.printingExact and self:cardPrintingSelection(card)or nil
  local printing=card.selectedPrintingId or(choice and choice.printingId)
  if not printing or card.printingExact and card.printing_id==printing then return data end
  self.printingMetadata=self.printingMetadata or{};local cache=self.printingMetadata
  local entry=cache[printing]
  if entry and entry.pending and entry.isCurrent and not entry.isCurrent()then cache[printing]=nil;entry=nil end
  if entry and not entry.pending and not entry.card and(entry.retryAt or 0)<=now()then cache[printing]=nil;entry=nil end
  if not entry and(self.printingLookupPending or 0)<4 then
   local count=0;for _ in pairs(cache)do count=count+1 end
   if count>=128 then for key,value in pairs(cache)do if not value.pending then cache[key]=nil;break end end end
   entry={pending=true};cache[printing]=entry;self.printingLookupPending=(self.printingLookupPending or 0)+1
   self:request('catalog','GET','/cards/'..API.escape(printing)..'?printing='..API.escape(printing),nil,function(value)
    self.printingLookupPending=math.max(0,(self.printingLookupPending or 1)-1)
    if cache[printing]~=entry then return end
    entry.pending=false;entry.card=value;entry.retryAt=now()+30
   end,true)
  end
  local out={};for key,value in pairs(data or card)do out[key]=value end
  out.selectedPrintingId=printing;out.printingExact=true;out.printingResolved=entry and entry.card~=nil or false
  -- Do not briefly substitute another illustrator while exact metadata loads.
  if not entry or not entry.card then return out end
  local printed=entry.card
  local candidates={card.name,card.artName,card.printing and card.printing.name}
  local belongs=false
  for _,name in pairs(candidates)do
   if name==printed.name then belongs=true end
   for _,face in ipairs(printed.card_faces or{})do if name==face.name then belongs=true end end
  end
  if not belongs then out.printingResolved=false;return out end
  for _,key in ipairs({'id','printing_id','image_uris','card_faces','set','set_name','collector_number','artist','artist_ids','frame_effects','border_color','illustration_id'})do out[key]=printed[key]end
  if card.ownerId or card.manaCost or card.objectId then out.objectId=card.objectId or card.id end
  local face=card.requested_face or(data and data.requested_face)
  if face==nil then
   for i,f in ipairs(printed.card_faces or{})do if f.name==card.name then face=i-1;break end end
  end
  out.requested_face=face or 0
  return out
 end
 local baseCardData=Model.cardData
 function Model:cardData(card)return self:printingData(card,baseCardData(self,card))end
 local baseCover=Model.deckCoverCard
 function Model:deckCoverCard(deck)
  local card=baseCover(self,deck);local choice=card and selected(deck,card.name)
  if choice then card.selectedPrintingId=choice.printingId end
  return card
 end
 function Model:syncCardPrintings(deck)
  deck=deck or self.editDeck
  if not deck or not deck.printingSelections then return end
  local counts,number={},{}
  for _,s in ipairs(deck.printingSelections)do local key=s.zone..'\0'..s.name;number[key]=(number[key]or 0)+1 end
  local result=json.array()
  for _,s in ipairs(deck.printingSelections)do
   local e=member(deck,s.name,s.zone);local key=s.zone..'\0'..s.name;local used=counts[key]or 0
   if e and used<e.count then local value=copy(s);value.count=math.min(number[key]==1 and e.count or s.count,e.count-used);result[#result+1]=value;counts[key]=used+value.count end
  end
  deck.printingSelections=result
 end
 function Model:showCardPrintings(card,zone)
  local name=card and(card.artName or card.name);local entry,z=member(self.editDeck,name,zone)
  if not entry then entry,z=member(self.editDeck,name)end
  if not entry then if self.toast then self:toast('Add this card to the deck before choosing its edition.')end;return false end
  local choice=selected(self.editDeck,name,z)
  self.cardPrintingOpening=(self.cardPrintingOpening or 0)+1
  self.cardPrintingPicker={opening=self.cardPrintingOpening,deck=self.editDeck,generation=self.editGeneration,name=name,zone=z,revision=self.deckRevision or 0,query='',set='',variant='all',offset=0,items={},total=0,sets={},selectedId=choice and choice.printingId,selected=choice and copy(choice)}
  self:refreshCardPrintings();return true
 end
 function Model:closeCardPrintings()self.cardPrintingPicker=nil;self.cardPrintingOpening=(self.cardPrintingOpening or 0)+1 end
 function Model:refreshCardPrintings()
  local picker=self.cardPrintingPicker;if not picker then return end
  picker.version=(picker.version or 0)+1;local version=picker.version;picker.busy=true;picker.error=nil
  local path='/printings?name='..API.escape(picker.name)..'&q='..API.escape(picker.query)..'&set='..API.escape(picker.set)..'&variant='..picker.variant..'&limit=12&offset='..picker.offset
  self:request('catalog','GET',path,nil,function(data,err)
   if self.cardPrintingPicker~=picker or picker.version~=version then return end
   picker.busy=false
   if data then picker.items=data.items or{};picker.total=data.total or 0;picker.sets=data.sets or{};picker.name=data.name or picker.name
   else picker.error=err or'Printing metadata is unavailable'end
  end,true)
 end
 function Model:filterCardPrintings(query,set,variant)
  local p=self.cardPrintingPicker;if not p then return end
  p.query=query or p.query;p.set=set or p.set;p.variant=variant or p.variant;p.offset=0;p.version=(p.version or 0)+1;p.timer=.18
 end
 function Model:updateCardPrintings(dt)
  local p=self.cardPrintingPicker;if not p then return end
  if self.editDeck~=p.deck or self.editGeneration~=p.generation or self.page~='builder'then self:closeCardPrintings();return end
  if p.timer then p.timer=p.timer-dt;if p.timer<=0 then p.timer=nil;self:refreshCardPrintings()end end
 end
 function Model:selectCardPrinting(id)
  local p=self.cardPrintingPicker;if not p then return false end
  for _,item in ipairs(p.items)do if item.printing_id==id then
   p.selectedId=id;p.selected={printingId=id,set=item.set,collectorNumber=item.collector_number}
   p.artSelection=(p.artSelection or 0)+1;p.explicitArtId=id
   self:getCardPrintingArt(item);return true
  end end
  return false
 end
 function Model:getCardPrintingArt(item,variant)
  local p=self.cardPrintingPicker
  local exact=copy(item);exact.printingExact=true;exact.printingResolved=true;exact.selectedPrintingId=item.printing_id
  if not p or p.explicitArtId~=item.printing_id or p.selectedId~=item.printing_id then return self:getArt(exact,true,nil,{variant=variant})end
  local token,id=p.artSelection,item.printing_id
  local function current()return self.cardPrintingPicker==p and self.editDeck==p.deck and self.editGeneration==p.generation and self.page=='builder'and(self.deckRevision or 0)==p.revision and p.artSelection==token and p.selectedId==id end
  return self:getArt(exact,true,nil,{priority='selected',network=true,selectionToken='printing:'..p.opening..':'..token..':'..id,isCurrent=current})
 end
 function Model:confirmCardPrinting(useDefault)
  local p=self.cardPrintingPicker
  if not p or self.editDeck~=p.deck or self.editGeneration~=p.generation or self.page~='builder'or(self.deckRevision or 0)~=p.revision then return false end
  local entry=member(self.editDeck,p.name,p.zone)
  if not entry or not useDefault and not(p.selected and p.selectedId)then return false end
  local choices=json.array()
  for _,selection in ipairs(self.editDeck.printingSelections or{})do if selection.name~=p.name or selection.zone~=p.zone then choices[#choices+1]=copy(selection)end end
  if not useDefault then choices[#choices+1]={name=p.name,zone=p.zone,count=entry.count,printingId=p.selectedId,set=p.selected.set,collectorNumber=p.selected.collectorNumber}end
  self.editDeck.printingSelections=choices;self.deckRevision=(self.deckRevision or 0)+1;self.dirty=true;self.validation=nil
  self.validationVersion=(self.validationVersion or 0)+1;self.validationTimer=.2
  self:closeCardPrintings();if self.selectBuilderArtwork then self:selectBuilderArtwork(entry)end;return true
 end
end
return Printings
