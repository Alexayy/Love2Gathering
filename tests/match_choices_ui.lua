-- Real LÖVE/Slab input against deliberately synthetic native prompt sequences.
-- This proves presentation/dispatch, not native Magic gameplay.
function love.errorhandler(msg)io.stderr:write('MATCH CHOICES UI FAILED: '..tostring(msg)..'\n'..debug.traceback()..'\n');io.stderr:flush();return function()return 1 end end
package.preload['app.api']=function()return{escape=function(s)return tostring(s)end,new=function()return{request=function()end,update=function()end,quit=function()end}end}end
local json=require('lib.json');local S=require('lib.Slab');local Layout=require('app.layout');local Model=require('app.model');local Renderer=require('app.renderer');local View=require('app.view');local Match=require('app.match_ui');local Choices=require('app.card_choices')
local m,r,v,runner,Cursor,Window;local mouse={x=2,y=2};local down=false;local clock,wake=0,0;local buttons,checks,shots={},{},{};local answers={};local pending;local promptId=0;local mode;local selected={};local offered;local stage
local visibleText={}
local function check(ok,label)assert(ok,label);checks[#checks+1]=label;print('MATCH CHOICES UI PASS '..label)end
local function wait(t)wake=clock+(t or .1);coroutine.yield()end
local function ready(fn,label)local deadline=clock+8;while not fn()do if clock>=deadline then io.stderr:write(json.encode({prompt=m.game.prompt,answers=answers,state=v.cardChoiceState,actionBusy=m.actionBusy,answeredPrompt=m.answeredPrompt})..'\n');error(label)end;wait(.05)end end
local function move(x,y)local px,py=mouse.x,mouse.y;mouse.x,mouse.y=x*Layout.scale,y*Layout.scale;S.OnMouseMoved(mouse.x,mouse.y,mouse.x-px,mouse.y-py);Choices.move(v,x,y);r:mousemoved(x,y)end
local function click(box,button,beforeRelease)
    assert(box,'Missing UI fixture control');button=button or 1;local x,y=box.x+box.w/2,box.y+box.h/2;move(x,y);wait(.05);down=true;S.OnMousePressed(mouse.x,mouse.y,button,false,1);local taken=Choices.press(v,x,y,button)
    if not taken and S.IsVoidHovered()then r:mousepressed(x,y,button,1)end
    wait(.05)
    if beforeRelease then beforeRelease();wait(.05) end
    down=false;S.OnMouseReleased(mouse.x,mouse.y,button,false,1);if not Choices.release(v,x,y,button)then r:mousereleased(x,y,button)end;wait(.15)
end
local function drag(hit,drop,index)
    assert(hit and drop,'Missing drag fixture geometry');local x,y=hit.x+hit.w/2,hit.y+hit.h/2;move(x,y);wait(.05);down=true;S.OnMousePressed(mouse.x,mouse.y,1,false,1);check(Choices.press(v,x,y,1),'Card-panel press owns the drag before board input')
    wait(.05);local dx=drop.x+12+(index or 0)*drop.cardW;local dy=drop.y+drop.h/2;move(dx,dy);wait(.1);down=false;S.OnMouseReleased(mouse.x,mouse.y,1,false,1);Choices.release(v,dx,dy,1);wait(.15)
end
local function shot(name)shots[#shots+1]=name;wait(.12)end
local function nativeCard(key,name)return{id=key,choiceId=key,responseType='uuid',value=key,name=name,manaCost='{1}{B}',type='Creature',rules='A native offered card for a presentation fixture.',power='2',toughness='2'}end
local cards={nativeCard('a','Woe Strider'),nativeCard('b','Persistent Specimen'),nativeCard('c','Ayara, First of Locthwain')}
local function prompt()
    promptId=promptId+1
    local choices={};for _,c in ipairs(offered)do choices[#choices+1]={id=c.id,responseType='uuid',value=c.id,card=c,label=c.name}end
    local done={id='done',label='Done / Cancel',responseType='boolean',value=false};if stage=='select'then choices[#choices+1]=done end
    m.game.prompt={id=promptId,type='pick_target',message=mode=='scry'and'Scry 3'or'Surveil 3',choices=choices,actionable={},cardPanel={interactionId=mode..'-interaction',kind=mode,stage=stage,selectionDestination=mode=='scry'and'bottom'or'graveyard',remainingDestination='top',orderDestination=stage=='order'and'top'or nil,orderDirection='last_chosen_topmost',cards=offered,doneChoice=stage=='select'and done or nil}}
end
local function start(kind)
    mode=kind;stage='select';selected={};for _,c in ipairs(cards)do c.selected=false;c.selectable=true end;offered={cards[1],cards[2],cards[3]};m.actionBusy=false;m.answeredPrompt=nil;v.cardChoiceState=nil;m.game.lookedAt={};prompt()
end
local function scenario()
    start('scry');wait(.2);shot('scry-before')
    drag(v.cardChoiceHits[3],v.cardChoiceDrops[2]);check(#answers==0 and v.cardChoiceState.rows.bottom[1]=='c','Scry drag stages Bottom without answering the native prompt')
    drag(v.cardChoiceHits[2],v.cardChoiceDrops[1],0);check(v.cardChoiceState.rows.top[1]=='b','Scry drag changes the desired top-card order')
    shot('scry-arranged');click(buttons.Confirm);ready(function()return not m.game.prompt and not pending end,'Scry response sequence did not finish')
    check(#answers==4 and answers[1].value=='c'and answers[2].value==false and answers[3].value=='a'and answers[4].value=='b','Scry Confirm sends native Bottom, Done and reverse Top ordering exactly once')
    start('surveil');wait(.2);local before=#answers;drag(v.cardChoiceHits[1],v.cardChoiceDrops[2]);check(v.cardChoiceState.rows.graveyard[1]=='a'and#answers==before,'Surveil exposes Graveyard staging without a fake Bottom action')
    shot('surveil-arranged');click(buttons.Confirm);ready(function()return not m.game.prompt and not pending end,'Surveil response sequence did not finish')
    check(answers[before+1].value=='a'and answers[before+2].value==false,'Surveil confirmation forwards the offered UUID and real native Done response')
    start('scry');m.forceReject=true;wait(.2);before=#answers;click(buttons.Confirm);ready(function()return v.cardChoiceState and v.cardChoiceState.error end,'Rejected response did not reopen confirmation')
    check(#answers==before+1 and not v.cardChoiceState.committing,'A rejected native response preserves the plan and requires explicit retry instead of looping')
    click(buttons.Confirm);ready(function()return not m.game.prompt and not pending end,'Explicit response retry did not finish');check(#answers==before+5,'Explicit retry resumes exact native responses without losing the staged order')
    m.game.prompt={id=900,type='choose_card',message='Choose an offered card from your hand',choices={},cardPanel={interactionId='private-hand',kind='select',stage='select',cards={{id='private-offered',choiceId='native-choice',responseType='uuid',value='actual-native-response',name='Persistent Specimen',manaCost='{B}',type='Creature',rules='Only an offered private card.'}}}};m.answeredPrompt=nil;wait(.2);shot('private-card-choice');click(buttons['Persistent Specimen']);check(answers[#answers].value=='actual-native-response','Private-zone card image click forwards its actual native choice value')
    wait(.2);m.game.prompt={id=901,type='ask',message='Choose one offered pile',pile1={cards[1]},pile2={cards[2],cards[3]},choices={{id='actual-first',label='Take first pile',responseType='boolean',value=true},{id='actual-second',label='Take second pile',responseType='boolean',value=false}}};m.answeredPrompt=nil;wait(.2)
    check(#v.cardChoiceHits==3 and v.cardChoiceHits[2].w>0 and v.cardChoiceHits[2].x>select(1,Layout.dimensions())/2,'Both image piles keep visible card bounds inside their separate clipped columns')
    shot('pile-choices');click(buttons['Take second pile']);check(answers[#answers].value==false,'Image pile controls preserve the offered native second-pile false response')
    wait(.2);m.game.prompt={id=902,type='unrecognized_native_choice',message='Generic native fallback',choices={{id='native-mode',label='Actual native mode',responseType='string',value='native-mode'}}};m.answeredPrompt=nil;wait(.2);click(buttons['Actual native mode']);check(answers[#answers].value=='native-mode','Unsupported native prompts retain the existing generic response path')
    v.cardChoiceState=nil;before=#answers;m.game.lookedAt={{id='private-look',label='Look at your cards',cards={cards[1],cards[2]}}};wait(.2);shot('look-at')
    click(buttons['Woe Strider'],2);check(m:pinnedTableCard() and m:pinnedTableCard().id=='a' and not m.inspectCard and #answers==before,
        'Right-click pins a retained look-at card without closing its panel or answering')
    click(buttons['Woe Strider'],3);check(m.inspectCard and m.inspectCard.id=='a','Look-at card supports detailed inspection through actual middle-click input')
    click(buttons['Close details']);click(buttons.Close);check(#answers==before and not m.inspectCard,'Closing a look-at popup sends no engine action')
    wait(.2);check(#v.cardChoiceHits==0,'Dismissed looked-at groups stay closed during repeated snapshots')
    m.game.lookedAt={};m.game.prompt={id=1000,type='pick_target',message='Select another black creature (to sacrifice)',actionable={'a','b'},choices={{id='a',label=cards[1].name,responseType='uuid',card=cards[1]},{id='b',label=cards[2].name,responseType='uuid',card=cards[2]},{id='done',label='Done / Cancel',responseType='boolean',value=false}}};m.answeredPrompt=nil;wait(.2)
    check(buttons['Done / Cancel']and not buttons['Ayara, First of Locthwain'],'Sacrifice selection keeps legal cards on the board with only the actual native cancel control')
    shot('board-sacrifice');click(buttons['Done / Cancel']);check(answers[#answers].value==false,'Cancel forwards the native pre-commit false response without undoing a stack object')
    m.game.prompt={id=1001,type='select',message='Declare blockers',actionable={'b'},choices={{id='done',label='Done declaring blockers',responseType='boolean',value=true}},combat={role='blockers',blockers={{blockerId='b',legalAttackerIds={},unavailable={{attackerId='opponent-attacker',reason='XMage does not offer this block',rules={'Flying'}}},preview=true}}}};m.answeredPrompt=nil;wait(.2)
    local toastCount=#m.toasts;check(v.combatToastPrompt==1001 and m.toasts[toastCount].ttl==3,'Native blocker stage displays one short-lived instruction toast')
    wait(.2);check(#m.toasts==toastCount,'Repeated blocker snapshots do not repeat the same instruction toast');shot('native-blocker-hint');click(buttons['Done declaring blockers'])
    wait(.16)
    local spiritA,spiritB=nativeCard('spirit-a','Spirit Token'),nativeCard('spirit-b','Spirit Token')
    local bearA,bearB=nativeCard('bear-a','Bear'),nativeCard('bear-b','Bear')
    m.game.players[1].battlefield={cards[1],cards[2],spiritA,spiritB};m.game.players[2].battlefield={bearA,bearB}
    m.game.combat={groups={{attackerId=bearB.id,defenderId='human',blockerIds={spiritA.id},blocked=true,declarationConfirmed=false}}}
    local function choice(option,card)return{id=option,label=card.name,responseType='uuid',value=card.id}end
    m.game.prompt={id=1002,type='select',message='Select blockers',actionable={spiritB.id,spiritA.id},choices={choice('first',spiritB),choice('second',spiritA),{id='done',label='Pass / Done',responseType='boolean',value=true}},combat={role='blockers',declarationConfirmed=false}};m.answeredPrompt=nil;wait(.2)
    check(buttons['Spirit Token #1'] and buttons['Spirit Token #2'] and visibleText.Blocks and visibleText.Unassigned and visibleText['Bear #2'],'Blocker popup renders distinct duplicate instances and visibly names the assigned attacker')
    local duplicate=buttons['Spirit Token #2'];move(duplicate.x+duplicate.w/2,duplicate.y+duplicate.h/2);wait(.12)
    check(m.choiceHover and m.choiceHover.combatId==spiritB.id,'Hovering the matching blocker thumbnail focuses its exact battlefield instance');shot('assigned-blockers')
    before=#answers
    click(duplicate,1,function()m.game.prompt.id=2002 end)
    check(#answers==before,'Releasing a blocker held across a replacement prompt leaves the new declaration untouched')
    click(duplicate);check(answers[#answers].value==spiritB.id,'Clicking a duplicate blocker sends its actual native offered UUID')
    m.game.prompt={id=1003,type='pick_target',message='Select attacker to block',actionable={bearA.id,bearB.id},choices={choice('target-one',bearA),choice('target-two',bearB),{id='done',label='Done / Cancel',responseType='boolean',value=false}},combat={role='block_target',blockerId=spiritA.id,legalAttackerIds={bearA.id,bearB.id},declarationConfirmed=false}};m.answeredPrompt=nil;wait(.2)
    check(buttons['Bear #1'] and buttons['Bear #2'] and visibleText['Blocking with Spirit Token #1'] and visibleText['Already assigned'],'Attacker popup shows which duplicate is blocking and its existing target')
    check(buttons['Cancel attacker selection'] and not visibleText['Blocks provisional · Done confirms.'],'The attacker subchoice correctly labels cancellation separately from confirming blocks')
    shot('choose-block-target');click(buttons['Bear #1']);check(answers[#answers].value==bearA.id,'Attacker target click preserves the exact native identity')
    local many,offers,actionable={},{},{}
    for i=1,16 do
        local spirit=nativeCard('wide-spirit-'..i,'Spirit Token')
        many[i]=spirit;offers[i]=choice('wide-option-'..i,spirit);actionable[i]=spirit.id
    end
    m.game.players[1].battlefield=many
    m.game.prompt={id=1004,type='select',message='Select blockers',actionable=actionable,choices=offers,combat={role='blockers',declarationConfirmed=false}};m.answeredPrompt=nil;wait(.2)
    check(buttons['Spirit Token #1'] and not buttons['Spirit Token #16'],'Crowded blocker popup only rasterizes the visible grid rows')
    local first=buttons['Spirit Token #1'];move(first.x+first.w/2,first.y+first.h/2);wait(.1);S.OnWheelMoved(0,-5);wait(.2)
    check(buttons['Spirit Token #16'],'Scrolling reveals the last row of native combat choices')
    click(buttons['Spirit Token #16']);check(answers[#answers].value==many[16].id,'Clicking a scrolled blocker sends its actual native UUID')
    m.game.players[1].battlefield={cards[1],cards[2]};m.game.players[2].battlefield={};m.game.combat=nil
    m.game.prompt=nil;m.actionBusy=false;m.game.log={{id='l1',actor='human',category='cast',stackEvent=true,text='You cast Woe Strider',sourceCard=cards[1]},{id='l2',actor='bot',category='trigger',text='A very long triggered ability detail that must stay within the existing compact log footprint.',sourceCard=cards[3]},{id='l3',actor='human',category='land',text='You play a land'}};m.game.stack={{id='stack-1',sourceId='a',name='Woe Strider ability',sourceCard=cards[1],sourceName=cards[1].name,rules='Sacrifice another creature: Scry 1.',targets={{id='opponent',name='Opponent'}},isTop=true}};wait(.2)
    check(#m.stackHits==1 and m.stackHits[1].sourceId=='a'and m.stackHits[1].targets[1].id=='opponent','Stack rows register exact native source and target IDs with their visible geometry')
    local hit=m.stackHits[1];move(hit.x+hit.w/2,hit.y+20);wait(.15);check(m.stackHover and m.stackHover.id=='stack-1','Hovering a visible stack source exposes preview/link metadata')
    move(2,2);wait(.15);check(not m.stackHover,'Stack hover clears outside the stack region')
    click(buttons['Table options']);click(buttons['Open history drawer']);click(buttons['Close options']);wait(.2)
    click(buttons['Include repetitive triggers and resolutions']);check(m.uiLayout.matchPrefs.logVerbose==true,'History checkbox persists optional repetitive stack entries')
    shot('compact-log-stack');click(buttons['Include repetitive triggers and resolutions']);check(m.uiLayout.matchPrefs.logVerbose==false,'History can return to the compact default log');click(buttons['Close history'])
    m.game.stack={};m.game.running=false;m.game.players[1].won=true;wait(.2);check(buttons.Rematch and buttons['Main menu'],'Native ended-match state exposes Rematch and Main menu controls')
    shot('match-ended');click(buttons.Rematch);check(m.rematched==1,'Actual Rematch button calls the model authority hook')
    m.game.running=false;wait(.2);click(buttons['Main menu']);check(m.mainSelected and m.page=='decks','Actual Main menu button calls the model navigation hook')
    m.page='table';m.game.running=true;m.game.players[1].won=false;m.uiLayout={};m.uiLayoutVersion=(m.uiLayoutVersion or 0)+1;Layout.setScale(1.25);S.SetScale(Layout.scale);start('scry');wait(.2)
    drag(v.cardChoiceHits[1],v.cardChoiceDrops[2]);check(v.cardChoiceState.rows.bottom[1]=='a','Scry drag uses the same logical coordinates at UI scale 1.25')
    shot('scry-scaled')
    local beforeReplay=#answers;m.replay={frames={},index=1,speed=1,playing=false};wait(.2)
    check(#v.cardChoiceHits==0 and#answers==beforeReplay,'Read-only playback hides live card-choice controls and sends no staged responses')
    m.replay=nil;v.cardChoiceState.committing=true;m.actionBusy=true;m.game.prompt=nil
    m.api.routeGeneration=(m.api.routeGeneration or 0)+1;wait(.15)
    check(not v.cardChoiceState and #v.cardChoiceHits==0 and #answers==beforeReplay,
        'Changing the connection while a selection is pending retires its private cards and staged answers')
    m.actionBusy=false
    m.replay=nil;m.game.prompt={id=1200,type='play_mana',message='Pay {1} for Talisman of Creativity',choices={
        {id='keep',label='Kher Keep',responseType='uuid'},
        {id='keep-choice',sourceId='keep',label='Tap: add {C}',manaColors={'C'},responseType='mana_source'},
        {id='city',label='City of Brass',responseType='uuid'},
        {id='city-green',sourceId='city',label='Tap: add one mana of any color',manaColors={'G'},manaColor='Green',responseType='mana_source'},
        {id='city-blue',sourceId='city',label='Tap: add one mana of any color',manaColors={'U'},manaColor='Blue',responseType='mana_source'},
        {id='done',label='Cancel payment',value=true,responseType='boolean'},
        {id='mana-B',label='Pay {B} from pool (3)',manaCount=3,manaSymbol='B',value='BLACK',responseType='mana'}}}
    local manaPrompt=m.game.prompt;m.answeredPrompt=nil;v.cardChoiceState=nil;wait(.2)
    check(buttons['Pay {B} from pool (3)'].y<buttons['Kher Keep'].y and buttons['Tap: add {C}'].x>buttons['Kher Keep'].x,
        'Payment popup puts floating mana above the source list and colorless beside Kher Keep')
    shot('manual-mana')
    check(buttons['Kher Keep'].x>select(1,Layout.dimensions())/2 and visibleText['Spend from mana pool'],
        'The manual payment dock leaves the center of the battlefield exposed and labels spendable pool mana')
    before=#answers
    manaPrompt.actionable={};wait(.15)
    local green='Tap: add one mana of any color · Green'
    check(buttons['City of Brass'].disabled and buttons[green].disabled and not buttons['Pay {B} from pool (3)'].disabled,
        'An empty native actionable list disables sources and their colors while floating mana remains available')
    click(buttons[green]);check(#answers==before,'An unavailable source color sends no payment')
    manaPrompt.actionable=nil;wait(.15)
    local optionBox=buttons[green];move(optionBox.x+optionBox.w/2,optionBox.y+optionBox.h/2);wait(.15)
    check(v.manaRuleText=='Tap: add one mana of any color' and #answers==before,
        'Hovering a source color reveals its actual ability text before any native response')
    click(buttons[green],1,function()m.game.prompt.id=2000 end)
    check(#answers==before,'A held mana option cannot spend mana in a later prompt with the same source and color')
    click(buttons[green])
    check(answers[#answers].type=='mana_source' and answers[#answers].value=='city-green','Clicking an inline source color sends its exact offered token')
    m.game.prompt=manaPrompt;manaPrompt.id=1201;m.answeredPrompt=nil;wait(.2);click(buttons['Pay {B} from pool (3)'])
    check(answers[#answers].type=='mana' and answers[#answers].value=='BLACK','Floating mana button dispatches native pool payment at UI scale 1.25')
    for i=1,12 do manaPrompt.choices[#manaPrompt.choices+1]={id='land-'..i,label='Land '..i,responseType='uuid'} end
    m.game.prompt=manaPrompt;manaPrompt.id=1202;m.answeredPrompt=nil;wait(.2)
    local keep,pay=buttons['Kher Keep'],buttons['Pay {B} from pool (3)']
    check(not keep.invisible and buttons['Land 12'].invisible,'Mana source scrolling clips off-screen controls')
    move(keep.x+keep.w/2,keep.y+keep.h/2);wait(.1);S.OnWheelMoved(0,-12);wait(.2)
    check(not buttons['Land 12'].invisible and buttons['Pay {B} from pool (3)'].y==pay.y,'Scrolling to the last mana source keeps the pool fixed')
    click(buttons['Land 12']);check(answers[#answers].value=='land-12','A scrolled mana source sends its exact native object ID')
    m.game.prompt={id=1203,type='play_mana',message='Pay {1}',choices={{id='done',label='Cancel payment',value=true,responseType='boolean'}}}
    m.answeredPrompt=nil;wait(.2)
    check(visibleText['No pool mana offered'] and not buttons['Pay {B} from pool (3)'] and buttons['Cancel payment'],
        'A fresh payment with no offered pool mana cannot spend the previous balance')
    local field=m.game.players[1].battlefield
    field[#field+1]={id='first-island',name='Island',type='Basic Land'}
    field[#field+1]={id='second-island',name='Island',type='Basic Land'}
    local firstIsland={id='first-island',label='Island',responseType='uuid'}
    local secondIsland={id='second-island',label='Island',responseType='uuid'}
    m.game.prompt={id=1204,type='play_mana',message='Pay {2}',choices={secondIsland,firstIsland}}
    m.answeredPrompt=nil;wait(.2)
    check(buttons['Island (2)'].y<buttons['Island (1)'].y and buttons['Island (2)'].tooltip:find('second-island',1,true),
        'Same-name sources follow battlefield numbering even when offered in reverse order')
    click(buttons['Island (1)']);check(answers[#answers].value=='first-island','The numbered first source submits its own native UUID')
    field[#field-1].tapped=true;m.game.prompt={id=1205,type='play_mana',message='Pay {1}',choices={secondIsland}}
    m.answeredPrompt=nil;wait(.15)
    check(not buttons['Island (1)'] and buttons['Island (2)'],'The second Island keeps its number after the first is tapped')
    click(buttons['Island (2)']);check(answers[#answers].value=='second-island','The remaining copy submits its own native UUID')
    table.remove(field);table.remove(field)
    m.game.prompt={id=1300,type='choose_ability',message='Choose an action',choices={
        {id='cast',responseType='uuid',label='Cast Shark Typhoon',manaCost='{5}{U}'},
        {id='cycle',responseType='uuid',label='Cycling',manaCost='{X}{1}{U}'}}}
    m.answeredPrompt=nil;wait(.2);before=#answers
    click(buttons['Cast Shark Typhoon'],1,function()m.game.gameId='SYNTHETIC-REMATCH' end)
    check(#answers==before,'A new game reusing the prompt and ability IDs cannot receive a held cast click')
    click(buttons.Cycling)
    check(answers[#answers].type=='uuid' and answers[#answers].value=='cycle','The newly displayed ability can be selected with a fresh click')
    m.game.prompt={id=1301,type='select',priority=true,message='Priority',choices={
        {id='done',responseType='boolean',label='Pass / Done',value=true},
        {id='special',responseType='string',label='Special action'},
        {id='undo',responseType='undo',label='Undo last mana action',value=true}}}
    m.answeredPrompt=nil;wait(.2)
    check(buttons['Pass Priority'] and buttons['Special action'] and buttons['Undo last mana action'],
        'Priority labels distinguish Pass, Special action and Undo')
    check(buttons['Pass Priority'].x>buttons['End Turn'].x+buttons['End Turn'].w and buttons['Pass Priority'].w>buttons['End Turn'].w,
        'The primary priority button has a distinct rightmost position and wider target than End Turn')
    shot('priority-actions')
    local priorityPrompt=m.game.prompt
    click(buttons['Special action']);check(answers[#answers].type=='string' and answers[#answers].value=='special',
        'The separately labeled special action dispatches its native token')
    m.game.prompt=priorityPrompt;priorityPrompt.id=1302;m.answeredPrompt=nil;wait(.15)
    click(buttons['Pass Priority']);check(answers[#answers].type=='boolean' and answers[#answers].value==true,'Pass Priority submits the offered native boolean')
    m.game.prompt={id=1303,type='ask',message='Pay kicker {1}{R}?',choices={{id='yes',label='Pay {1}{R}',responseType='boolean',value=true},{id='no',label='Decline',responseType='boolean',value=false}}}
    m.answeredPrompt=nil;wait(.2);before=#answers
    check(not buttons['Pass Priority'] and buttons['Pay {1}{R}'] and buttons.Decline,'The optional cost presents the actual alternatives without a priority action')
    click(buttons['Pay {1}{R}'],1,function()m.game.prompt.id=1304 end)
    check(#answers==before,'Holding an optional cost across a new prompt cannot accept the later cost')
    click(buttons.Decline);check(answers[#answers].type=='boolean' and answers[#answers].value==false,'An explicit decline preserves the native false value')
    local out=assert(io.open('/tmp/love2gathering-match-choices-ui-report.json','w'));out:write(json.encode({passed=true,checks=checks,answers=answers,scope='Actual LÖVE/Slab input, native-shaped synthetic prompts and deterministic response adapter; no real-engine scry/surveil/gameplay claim'}));out:close();print('MATCH CHOICES UI COMPLETE '..#checks..' checks');love.event.quit(0)
end
function love.load()
    S.SetINIStatePath(nil);S.Initialize({'nocursor'},true);Cursor=require('lib.Slab.Internal.Core.Cursor');Window=require('lib.Slab.Internal.UI.Window')
    love.mouse.getPosition=function()return mouse.x,mouse.y end;love.mouse.isDown=function(button)return button==1 and down or false end
    m=Model.new();m.page='table';m.settings.showCardArt=false;m.settings.sfxEnabled=false;m.settings.particles=false;m.settings.animations=false;m.catalogHealth.ready=false;m.uiLayout={};m.engineHealth.ok=true
    m.game={gameId='SYNTHETIC-MATCH-CHOICES',revision=1,running=true,turn=1,phase='Precombat Main',step='PRECOMBAT_MAIN',activePlayerId='human',players={{id='human',name='You',human=true,isLocal=true,life=40,hand={},battlefield={cards[1],cards[2]},graveyard={},exile={},command={},mana={},libraryCount=50},{id='opponent',name='Opponent',bot=true,life=40,hand={},battlefield={},graveyard={},exile={},command={},mana={},libraryCount=50}},log={},stack={}}
    function m:answer(kind,value)
        if self.actionBusy or self.replay then return end;local p=self:prompt();if not p then return end
        answers[#answers+1]={promptId=p.id,type=kind,value=value};self.actionBusy=true;self.answeredPrompt=p.id
        pending={at=clock+.09,callback=function()
            self.actionBusy=false
            if self.forceReject then self.forceReject=nil;self.answeredPrompt=nil;return end
            if p.cardPanel and p.cardPanel.kind=='select'then self.game.prompt=nil
            elseif p.cardPanel then
                if kind=='uuid'then
                    local nextCards={};for _,c in ipairs(offered)do
                        if stage=='select'then if c.id==value then c.selected=not c.selected;selected[c.id]=c.selected or nil end;nextCards[#nextCards+1]=c
                        elseif c.id~=value then nextCards[#nextCards+1]=c end
                    end;offered=nextCards
                    if stage=='order'and#offered==0 then self.game.prompt=nil else prompt()end
                else stage='order';offered={};for _,c in ipairs(cards)do if not selected[c.id]then offered[#offered+1]=c end end;prompt()end
            else self.game.prompt=nil end
        end}
    end
    function m:canRematch()return not self.roomConnectionId end;function m:rematch()self.rematched=(self.rematched or 0)+1;self.game.running=true end;function m:goMain()self.mainSelected=true;self.page='decks'end
    r=Renderer.new(m);v=View.new(S,m,r)
    for _,name in ipairs({'Button','CheckBox'})do local original=S[name];S[name]=function(a,b,c)
        local result=original(a,b,c);local x,y,w,h=Cursor.GetItemBounds();x,y=Window.TransformPoint(x,y);local label=name=='CheckBox'and b or a;buttons[label]={x=x,y=y,w=w,h=h,invisible=type(b)=='table' and b.Invisible or nil,disabled=type(b)=='table' and b.Disabled or nil,tooltip=type(b)=='table' and b.Tooltip or nil};return result
    end end
    local draw=require('lib.Slab.Internal.Core.DrawCommands')
    for _,name in ipairs({'Print','Printf'}) do
        local original=draw[name];draw[name]=function(label,...)visibleText[label]=true;return original(label,...)end
    end
    runner=coroutine.create(scenario)
end
function love.update(dt)
    clock=clock+dt;assert(clock<80,'Match-choice UI acceptance timed out')
    if pending and clock>=pending.at then local next=pending;pending=nil;next.callback()end
    S.Update(dt);r:update(dt)
    if clock>=wake and coroutine.status(runner)~='dead'then local ok,err=coroutine.resume(runner);assert(ok,err)end
    buttons={};visibleText={};S.PushFont(r.fonts[16]);Match.build(v,Layout.dimensions());v:modals(Layout.dimensions());S.PopFont()
end
function love.draw()
    love.graphics.clear(.026,.036,.06,1);love.graphics.push();love.graphics.scale(Layout.scale);r:draw();love.graphics.pop();S.Draw();love.graphics.push();love.graphics.scale(Layout.scale);Choices.draw(v);love.graphics.pop()
    if #shots>0 then local name=table.remove(shots,1);love.graphics.captureScreenshot(function(data)local out=assert(io.open('/tmp/love2gathering-match-choices-'..name..'.png','wb'));out:write(data:encode('png'):getString());out:close()end)end
end
function love.quit()S.OnQuit()end
