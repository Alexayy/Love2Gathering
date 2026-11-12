package.path='./?.lua;./?/init.lua;'..package.path
local json=require('lib.json')
local function equal(actual,expected,message)assert(actual==expected,message or (tostring(actual)..' ~= '..tostring(expected)))end
local numbers=json.decode('[0,-0,17,-42,0.125,-3.5,1e3,2E-2,-4.25e+2,123456789]')
local expected={0,0,17,-42,.125,-3.5,1000,.02,-425,123456789}
for i,value in ipairs(expected)do equal(numbers[i],value,'Number at offset '..i..' decoded incorrectly')end
local nested=json.decode('{"first":17,"nested":{"values":[-2,3.75,6e-4,null,true,false]},"unicode":"Živeli — Nazgûl \\uD83D\\uDE00","empty":[]}')
equal(nested.first,17);equal(nested.nested.values[1],-2);equal(nested.nested.values[3],.0006)
equal(nested.nested.values[4],json.null);equal(nested.nested.values[5],true);equal(nested.nested.values[6],false)
equal(nested.unicode,'Živeli — Nazgûl 😀')
local roundtrip=json.decode(json.encode(nested))
equal(roundtrip.unicode,nested.unicode);equal(roundtrip.nested.values[4],json.null)
equal(json.encode(roundtrip.empty),'[]','Empty array lost its type')
local count=400000
local payload='['..string.rep('123456.25,',count-1)..'123456.25]'
assert(#payload>=4000000,'Numeric regression fixture is smaller than 4 MB')
local started=os.clock();local decoded=json.decode(payload);local elapsed=os.clock()-started
equal(#decoded,count);equal(decoded[1],123456.25);equal(decoded[math.floor(count/2)],123456.25);equal(decoded[count],123456.25)
-- A generous CPU budget catches the quadratic suffix-copy regression without
-- tying correctness to a particular machine's sub-second performance.
assert(elapsed<30,'4 MB numeric decode exceeded the 30-second regression budget: '..elapsed)
print(('JSON PASS: signed numbers, exponents, nested null/booleans, UTF-8, arrays and %.1f MB numeric decode in %.3fs'):format(#payload/1000000,elapsed))
