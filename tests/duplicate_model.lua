-- Pending duplicate saves must not replace a different editor or later edits.
package.path='./?.lua;'..package.path
local calls={}
package.preload['app.api']=function()return{new=function()return{request=function(_,service,method,path,body,callback)calls[#calls+1]={service=service,method=method,path=path,body=body,callback=callback}end}end,escape=function(value)return tostring(value)end}end
love={math={random=function()return 1234 end}}
local Model=require('app.model');local json=require('lib.json');local checks=0
local function check(value,label)assert(value,label);checks=checks+1;print('DUPLICATE PASS '..label)end
local function deck(id)return{id=id,origin='user',name=id,format='Modern',coverCard='Forest',description='Owned description',main={{name='Forest',count=60}},commander={},sideboard={}}end
local function model()calls={};return Model.new()end
local function result(id)local d=deck(id);d.name='Server-normalized copy';return d end

local m=model();local original=deck('original');m.selectedDeck=original.id;m:duplicateDeck(original);local pending=calls[#calls]
check(pending.method=='POST'and pending.path=='/decks'and pending.body.id~=original.id and pending.body.main[1].count==60 and pending.body.coverCard=='Forest','Duplicate submits a new owned identity with complete quantities and cover')
pending.callback({deck=result('actual-server-copy')})
check(m.page=='builder'and m.editDeck.id=='actual-server-copy'and m.editDeck.origin=='user'and m.editDeck.description=='Owned description','A current duplicate opens the actual returned owned deck')
check(json.encode(m.editDeck.sideboard)=='[]'and json.encode(m.editDeck.commander)=='[]'and original.id=='original'and original.name=='original'and original.main[1].count==60,'Returned empty zones remain arrays and the original is untouched')

m=model();m.selectedDeck='original';m:duplicateDeck(deck('original'));pending=calls[#calls]
m:openDeck(deck('new-editor'));m.editDeck.name='New editor has unsaved work';m.dirty=true
pending.callback(result('saved-copy'))
check(m.editDeck.id=='new-editor'and m.editDeck.name=='New editor has unsaved work'and m.dirty and calls[#calls].path=='/decks','A late duplicate refreshes saved decks without replacing another editor')

for _,field in ipairs({'name','coverCard'})do
    m=model();m:openDeck(deck('current-editor'));m.selectedDeck='original';m:duplicateDeck(deck('original'));pending=calls[#calls]
    m.editDeck[field]='Later '..field;m.dirty=true;pending.callback(result('saved-copy'))
    check(m.editDeck.id=='current-editor'and m.editDeck[field]=='Later '..field and m.dirty,'Later unsaved '..field..' changes survive a pending duplicate')
end

m=model();m:openDeck(deck('current-editor'));m.selectedDeck='original';m:duplicateDeck(deck('original'));pending=calls[#calls]
m:commitCard('Forest','main',1);pending.callback(result('saved-copy'))
check(m.editDeck.id=='current-editor'and m.editDeck.main[1].count==61 and m.dirty,'Later card-quantity revisions survive a pending duplicate')

m=model();m.selectedDeck='original';m:duplicateDeck(deck('original'));pending=calls[#calls];m.selectedDeck='different-selection';pending.callback(result('saved-copy'))
check(m.page=='decks'and m.selectedDeck=='different-selection'and not m.editDeck,'A late duplicate does not steal a newer collection selection')

m=model();m.selectedDeck='original';m:duplicateDeck(deck('original'));pending=calls[#calls];m.page='settings';pending.callback(result('saved-copy'))
check(m.page=='settings'and not m.editDeck,'A late duplicate does not navigate away from another page')

m=model();m:openDeck(deck('current-editor'));m.dirty=true;m:duplicateDeck(deck('original'));pending=calls[#calls];pending.callback({error='Save rejected'},nil,422)
check(m.editDeck.id=='current-editor'and m.dirty and m.toasts[#m.toasts].bad,'Rejected duplicate save preserves the editor and reports its actual error')
print('Duplicate model checks: '..checks..' passed')
