-- Pure presentation/controller contracts. These fixtures do not replace
-- native scry/surveil/selection or establish a completed gameplay sequence.
local Choices=require('app.card_choices');local Log=require('app.log');local json=require('lib.json')
local passed=0;local function check(value,label)assert(value,label);passed=passed+1;print('CARD CHOICES PASS '..label)end
local function card(key)return{id=key,choiceId='choice-'..key,name='Card '..key,responseType='uuid',value='native-'..key}end
local panel={interactionId='scry-native',kind='scry',stage='select',selectionDestination='bottom',remainingDestination='top',cards={card('a'),card('b'),card('c')},doneChoice={id='done',responseType='boolean',value=false}}
local state=Choices.state(panel)
check(table.concat(state.rows.top,',')=='choice-a,choice-b,choice-c'and#state.rows.bottom==0,'Initial scry layout uses only the native offered instances')
check(Choices.place(state,'choice-c','bottom')and Choices.place(state,'choice-b','top',1),'Drag stages destinations and visible order without a native response')
check(not Choices.place(state,'foreign','top')and not Choices.place(state,'choice-a','graveyard'),'Unavailable instances and unsupported scry destinations are rejected')
check(table.concat(state.rows.top,',')=='choice-b,choice-a'and state.rows.bottom[1]=='choice-c','Local reordering preserves every offered instance exactly once')
check(Choices.nextResponse(state,{id=1,cardPanel=panel})==nil,'Staging never submits a choice before Confirm')
state.committing=true;local answer=Choices.nextResponse(state,{id=1,cardPanel=panel})
check(answer.responseType=='uuid'and answer.value=='native-c'and answer.id=='choice-c','Confirmation forwards the actual offered response ID and value')
state.lastAnswered=1;check(Choices.nextResponse(state,{id=1,cardPanel=panel})==nil,'A consumed prompt cannot be answered twice')
panel.cards[3].selected=true;answer=Choices.nextResponse(state,{id=2,cardPanel=panel})
check(answer==panel.doneChoice,'Native selected cards retained in the offered list are never toggled a second time')
panel.cards[2].selected=true;answer=Choices.nextResponse(state,{id=2,cardPanel=panel})
check(answer.value=='native-b','An explicitly native-selected card moved back to Top is deselected with its actual native toggle')
panel.cards={card('a'),card('b')};answer=Choices.nextResponse(state,{id=2,cardPanel=panel})
check(answer==panel.doneChoice and answer.value==false,'Finishing native destination selection preserves its actual false Done response')
panel.stage='order';panel.orderDestination='top';panel.orderDirection='last_chosen_topmost'
answer=Choices.nextResponse(state,{id=3,cardPanel=panel});check(answer.value=='native-a','Native top ordering chooses the reverse display order when the last choice becomes topmost')
panel.cards={card('b')};answer=Choices.nextResponse(state,{id=4,cardPanel=panel});check(answer.value=='native-b','Native ordering continues only with still-offered cards')
panel.orderDirection='unknown';check(Choices.nextResponse(state,{id=5,cardPanel=panel})==nil,'Unknown native order semantics never trigger an invented response')
check(not Choices.supports(panel),'Unsupported native ordering retains the generic prompt UI')
local selectedCard=card('selected');selectedCard.selected=true
local resumed=Choices.state({interactionId='resumed',kind='scry',selectionDestination='bottom',cards={selectedCard}})
check(resumed.rows.bottom[1]=='choice-selected'and#resumed.rows.top==0,'Reopening an in-progress native selection restores its already-selected destination')
resumed.committing=true;check(Choices.nextResponse(resumed,{id=7,cardPanel={interactionId='resumed',stage='select',selectionDestination='bottom',cards={selectedCard},doneChoice=json.null}})==nil,'A JSON null Done choice never creates a fabricated response')
panel.interactionId='different';check(Choices.nextResponse(state,{id=6,cardPanel=panel})==nil,'An unrelated native interaction cannot consume an old staged plan')
local surveil=Choices.state({interactionId='surveil',kind='surveil',cards={card('a'),card('b')}})
check(Choices.place(surveil,'choice-a','graveyard')and not Choices.place(surveil,'choice-b','bottom'),'Surveil exposes Graveyard and Top without adding Bottom')
surveil.committing=true;check(not Choices.place(surveil,'choice-b','graveyard'),'A submitted plan cannot change while native choices are pending')
local m={game={players={{battlefield={{id='a'},{id='b'}},hand={{id='private'}}}}}}
local p={type='pick_target',choices={{id='a',responseType='uuid'},{id='b',responseType='uuid'},{id='cancel',responseType='boolean',value=false}}}
check(Choices.prefersBoard(m,p),'Legal battlefield-only targets use board selection instead of a text choice modal')
p.choices[2].id='private';check(not Choices.prefersBoard(m,p),'A hidden-zone card choice retains its explicit offered-card panel')
p.type='select';p.choices[2].id='b';check(not Choices.prefersBoard(m,p),'Generic select and ability prompts retain their normal prompt coverage')
local countsGame={players={{battlefield={{id='menace',name='Native menace attacker'},{id='limited',name='Native limited attacker'},{id='unoffered',name='Unoffered attacker'}}}},combat={groups={{attackerId='menace',minBlockers=2,maxBlockers=0},{attackerId='limited',minBlockers=1,maxBlockers=1},{attackerId='unoffered',minBlockers=4,maxBlockers=0}}}}
local countHints=Choices.combatCounts(countsGame,{role='block_target',legalAttackerIds={'menace','limited'}})
check(#countHints==2 and countHints[1]=='Native menace attacker needs at least 2 blockers'and countHints[2]=='Native limited attacker allows at most 1 blocker','Combat count hints render only native offered attackers and treat maximum zero as unlimited')
local previewHints=Choices.combatCounts(countsGame,{role='blockers',blockers={{legalAttackerIds={'menace'}}}})
check(#previewHints==1 and previewHints[1]:find('at least 2',1,true),'Blocker preview bubbles carry native formation requirements separately from pairwise eligibility')
local twinA,twinB={id='blocker-a',name='Spirit Token'},{id='blocker-b',name='Spirit Token'}
local attackerA,attackerB={id='attacker-a',name='Wolf Token'},{id='attacker-b',name='Wolf Token'}
local masked={id='attacker-c',name='Hidden identity',faceDown=true}
local fight={players={{battlefield={twinA,twinB}},{battlefield={attackerA,attackerB,masked}}},combat={groups={
    {attackerId=attackerA.id,blockerIds={twinA.id}},
    {attackerId=attackerB.id,blockerIds={twinA.id}},
    {attackerId=masked.id,blockerIds={twinA.id}},
}}}
local blocking={combat={role='blockers'},choices={{id='second-option',responseType='uuid',value=twinB.id},
    {id='first-option',responseType='uuid',value=twinA.id},{id='done',responseType='boolean',value=true}}}
local blockers=Choices.combatCards(fight,blocking)
check(#blockers==2 and blockers[1].name=='Spirit Token #2' and blockers[2].name=='Spirit Token #1','Duplicate blockers are labeled by native battlefield instances independently of choice order')
check(blockers[1].status=='Unassigned' and not blockers[1].selected and blockers[2].selected and table.concat(blockers[2].targets,',')=='Wolf Token #1,Wolf Token #2,Face-down creature','Existing blockers show exact native assignments without revealing a face-down target')
local targets,source=Choices.combatCards(fight,{combat={role='block_target',blockerId=twinA.id},choices={
    {id='target',responseType='uuid',value=attackerB.id},{id='hidden',responseType='uuid',value=masked.id},
}})
check(source=='Spirit Token #1' and targets[1].selected and targets[1].choice.id=='target' and targets[1].value==attackerB.id,'Target selection retains the exact blocker and native response ID')
check(targets[2].name=='Face-down creature' and targets[2].card.faceDown and targets[2].card.name~='Hidden identity','An offered face-down attacker keeps a masked selectable image')
local log={{text='Cast',category='cast',stackEvent=true},{text='Trigger detail',category='trigger'},{text='Land',category='land'},{text='Resolve detail',category='resolve'}}
local compact=Log.entries(log,{},false);local verbose=Log.entries(log,{},true)
check(#compact==2 and compact[1].text=='Land'and compact[2].text=='Cast'and#verbose==4,'Compact log keeps ordinary casts/actions while Verbose restores stack details')
local source=card('visible');local game={players={{battlefield={source}}}}
check(Log.source({sourceId='visible'},game)==source,'Miniature source art resolves only from the entitled current projection')
check(Log.source({sourceCard={id='secret',name='Secret',hidden=true}},game)==nil,'Hidden source metadata cannot become a log thumbnail or preview')
check(Log.source({sourceCard=json.null},game)==nil,'A null native source does not create an invented card thumbnail')
check(#Log.entries(log,{},true,2)==2,'Log presentation keeps the existing bounded entry count')
print('Card choice checks: '..passed..' passed')
