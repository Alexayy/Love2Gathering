package.path='./?.lua;'..package.path
local K=require('app.keywords');local n=0
local function check(value,label)assert(value,label);n=n+1;print('KEYWORDS PASS '..label)end
check(K.annotate('Flying'):find('Flying (',1,true),'A standalone keyword gains a display reminder')
local text=K.annotate('Flying, first strike\nWhenever this attacks, draw a card.')
check(text:find('Flying (',1,true)and text:find('first strike (',1,true),'Each keyword on an ability line is explained')
check(text:find('Whenever this attacks, draw a card.',1,true),'Card effect paragraphs remain unchanged')
check(K.annotate('Flying (This creature can fly.)')=='Flying (This creature can fly.)','Existing printed reminders are preserved without duplication')
check(K.annotate('Creatures you control have flying.')=='Creatures you control have flying.','A keyword mention in an effect is not rewritten as an intrinsic ability')
check(K.annotate('Flying',false)=='Flying','Explain-keywords preference disables annotations')
check(K.annotate('Ward {2}'):find('Ward {2} (',1,true),'Native mana tokens and variable ward costs remain intact')
check(K.annotate('Islandwalk'):find('Island',1,true),'Landwalk explains its defending-player condition')
check(K.annotate('Unknown mechanic')=='Unknown mechanic','Unknown mechanics never receive invented descriptions')
print('Keyword display checks: '..n..' passed')
