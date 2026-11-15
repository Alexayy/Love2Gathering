-- Strict UTF-8 display repair, without graphics, native games or storage.
package.path='./?.lua;'..package.path
local Text=require('app.utf8_text');local utf8=require('utf8')
local checks=0;local function check(value,label)assert(value,label);checks=checks+1;print('UTF8 TEXT PASS '..label)end
local replacement=utf8.char(0xFFFD)
for _,value in ipairs({'','ASCII {T}: Add {G}.','Čarobna šuma — café','𐐀 🌳 {G/U/P}',utf8.char(0x10FFFF)})do assert(Text.clean(value)==value)end
check(true,'Valid text and mana syntax are preserved byte-for-byte, including four-byte scalars')
local invalid={
 {'before\226\128','before'..replacement},{'before\195 after','before'..replacement..' after'},
 {'\128\129after',replacement..'after'},{'\192\175',replacement},{'\224\159\191',replacement},
 {'\237\160\128',replacement},{'\244\144\128\128',replacement},{'\255after',replacement..'after'},
 {'é\255🌳','é'..replacement..'🌳'},
}
for _,case in ipairs(invalid)do local result=Text.clean(case[1]);assert(result==case[2]and utf8.len(result))end
check(true,'Truncated sequences, stray continuations, overlong encodings, surrogates and out-of-range scalars are repaired')
for byte=0,255 do local result=Text.clean('Č'..string.char(byte)..'🌳 {G}');assert(utf8.len(result));assert(result:sub(1,2)=='Č'and result:sub(-4)==' {G}')end
check(true,'Every possible byte between valid Unicode fragments yields valid display text without damaging its neighbors')
for point=0,0x10FFFF,7919 do if point<0xD800 or point>0xDFFF then local value='a'..utf8.char(point)..' — {W}';assert(Text.clean(value)==value)end end
check(true,'Valid scalars across the Unicode range remain unchanged')
print('UTF-8 text checks: '..checks..' passed')
