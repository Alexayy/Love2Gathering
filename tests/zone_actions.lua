local Actions=require('app.card_actions')
local Choices=require('app.card_choices')
local a={id='grave-spell',name='Memory Deluge',zone='GRAVEYARD'}
local x={id='exile-spell',name='Known exile card',zone='EXILED'}
local h={id='hidden',name='Face-down card',hidden=true,zone='EXILED'}
local m={game={gameId='native-game',players={{graveyard={a},exile={x,h}}}},current={id=7,actionable={a.id,x.id,h.id},cardActions={{objectId=a.id,sourceZone='GRAVEYARD',options={{id='flashback-ability',label='Flashback {5}{U}{U}'}}},{objectId=x.id,sourceZone='EXILED',options={{id='spell-ability'}}},{objectId=h.id,sourceZone='EXILED',options={{id='private-ability'}}}}},answers={}}
function m:prompt()return self.current end
function m:canSelect(key)for _,id in ipairs(self.current and self.current.actionable or{})do if id==key then return true end end;return false end
function m:selectCard(card)self.answers[#self.answers+1]=card.id;return true end
assert(Actions.state(m,a).available and Actions.state(m,a).sourceZone=='GRAVEYARD')
assert(Actions.options(m,a)[1].id=='flashback-ability')
assert(#Actions.extension(m)==1 and Actions.extension(m)[1]==x,'Only actually offered visible exile cards form the extension')
local foretold={id='private-foretold',name='Face-down card',zone='EXILED',faceDown=true,faceDownIdentity={id='private-foretold',name='Doomskar',zone='EXILED',inspectionOnly=true}}
m.game.players[1].exile[#m.game.players[1].exile+1]=foretold;m.current.actionable[#m.current.actionable+1]=foretold.id;m.current.cardActions[#m.current.cardActions+1]={objectId=foretold.id,sourceZone='EXILED',options={{id='native-foretell-cost'}}}
assert(#Actions.extension(m)==2 and Actions.extension(m)[2].name=='Doomskar'and Actions.extension(m)[2].id==foretold.id,'Only the explicitly entitled owner identity can expose an offered face-down exile card')
assert(not Actions.state(m,h).available,'Hidden metadata never grants an action marker')
assert(Actions.select(m,a)and m.answers[1]==a.id,'Native object UUID is sent, never the informational ability UUID')
m.current.cardActions[1].options[2]={id='other-native-ability'}
assert(Actions.select(m,a)and m.cardActionSheet.objectId==a.id and#m.answers==1,'Several options open the shared sheet without submitting an invented ability')
m.roomDisconnected=true;assert(not Actions.commit(m,a)and#m.answers==1,'Disconnected offers cannot submit stale answers');m.roomDisconnected=false
m.current={id=8,actionable={},cardActions={}}
assert(not Actions.state(m,a).available and#Actions.extension(m)==0,'Expired permission disappears with the native offer')
m.replay={};assert(not Actions.commit(m,a)and#Actions.extension(m)==0,'Replays never offer live exile play');m.replay=nil

local panel={interactionId='memory-native',kind='select',stage='select',selectionMode='multiple',min=2,max=2,cards={{id='a',choiceId='a',name='A'},{id='b',choiceId='b',name='B'},{id='c',choiceId='c',name='C'}}}
local state=Choices.state(panel)
assert(Choices.toggle(state,'a')and not Choices.canConfirm(state))
assert(Choices.toggle(state,'b')and Choices.canConfirm(state))
assert(not Choices.toggle(state,'c'),'Native maximum is respected before committing')
assert(Choices.toggle(state,'a')and Choices.toggle(state,'c')and not state.selection.a,'Selections can be visibly reversed without a native answer')
state.committing=true
local first=Choices.nextResponse(state,{id=10,cardPanel=panel});assert(first.value=='b')
state.lastAnswered=10;assert(not Choices.nextResponse(state,{id=10,cardPanel=panel}),'Same native query cannot be answered twice')
panel.cards[2].selected=true
local second=Choices.nextResponse(state,{id=11,cardPanel=panel});assert(second.value=='c'and Choices.selectedCount(state)==2,'The selected state survives the next native query')
assert(not Choices.nextResponse(state,{id=12,cardPanel={interactionId='different-operation',cards=panel.cards}}),'Old local selection cannot answer another interaction')
print('zone actions and staged multi-card choice checks passed')
