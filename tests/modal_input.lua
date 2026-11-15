package.path='./?.lua;'..package.path
love={graphics={getDimensions=function()return 1120,720 end}}
local Renderer=require('app.renderer');local Picker=require('app.deck_picker')
local count=0;local mutations={}
local m={page='builder',editGeneration=1,settings={animations=false,particles=false},selectedSection='main'}
function m:addCard(card,zone,amount)mutations[#mutations+1]={card=card,zone=zone,amount=amount}end
function m:selectCard()error('Background input must not become a native action')end
local v={m=m};local r=setmetatable({model=m,view=v,hits={},ghosts={},builderDrop={x=24,y=560,w=1072,h=136}},Renderer)
function r:mousemoved()end
local card={id='catalog-card',name='Forest'};r.hover={kind='search',card=card}
local function check(ok,label)assert(ok,label);count=count+1;print('MODAL INPUT PASS '..label)end
local function drag()
 r.drag={kind='search',card=card,x=100,y=280,w=100,h=140};r.dragStart={100,280};r.dragPage='builder';r.dragEditorGeneration=m.editGeneration
end
v.builderFiltersOpen=true;r:mousepressed(100,280,1,2)
check(#mutations==0,'An outside double-click cannot add a card through open More filters')
v.builderFiltersOpen=nil;drag();v.builderFiltersOpen=true;r.blockBuilderDrop=false;r:mousereleased(200,600,1)
check(#mutations==0 and not r.drag,'A filter opened after drag start blocks release before the next UI frame')
v.builderFiltersOpen=nil;drag();m.inspectCard={name='Details'};r:mousereleased(200,600,1)
check(#mutations==0,'An inspection opened during a drag cannot mutate the deck')
m.inspectCard=nil;drag();m.editGeneration=2;r:mousereleased(200,600,1)
check(#mutations==0,'A drag from a previous editor cannot change a newly opened deck')
drag();m.page='decks';r:mousereleased(200,600,1)
check(#mutations==0,'Navigating away cancels a pending builder drop')
m.page='builder';drag();r:mousereleased(200,600,1)
check(#mutations==1 and mutations[1].card==card,'A current unobstructed drop still reaches the existing addition method once')
v.setPicker={};drag();r.blockBuilderDrop=false;r:mousereleased(200,600,1)
check(#mutations==1 and not r.drag,'A set popup opened during drag blocks the late release')
r.hover={kind='search',card=card};r:mousepressed(100,280,1,2)
check(#mutations==1,'A set popup blocks native builder double-click actions')
r.uiHovered=false;r:wheelmoved(0,-2)
check(#mutations==1,'A wheel event outside a set popup never scrolls the hidden deck or zooms the table')
v.setPicker=nil
local state={};v.deckSelection=state;m.lobbyDeckPicker=state;Picker.close(v)
check(state.closed and not v.deckSelection and not m.lobbyDeckPicker,'Dismissal closes both picker identities before asynchronous callbacks')
Picker.close(v);check(not r:inputBlocked(),'Repeated dismissal leaves no invisible input blocker')
print('Modal input checks: '..count..' passed')
