-- Keep valid display text byte-for-byte; replace only malformed UTF-8. This is
-- a presentation boundary, not a mutation of catalog/native card information.
local utf8=require('utf8')
local Text={}
local replacement=utf8.char(0xFFFD)
local function continuation(byte)return byte and byte>=0x80 and byte<=0xBF end
local function lengthAt(text,index)
    local a,b,c,d=text:byte(index,index+3)
    if a<0x80 then return 1 end
    if a>=0xC2 and a<=0xDF and continuation(b)then return 2 end
    if a>=0xE0 and a<=0xEF and continuation(b)and continuation(c)and(a~=0xE0 or b>=0xA0)and(a~=0xED or b<=0x9F)then return 3 end
    if a>=0xF0 and a<=0xF4 and continuation(b)and continuation(c)and continuation(d)and(a~=0xF0 or b>=0x90)and(a~=0xF4 or b<=0x8F)then return 4 end
end
function Text.clean(value)
    local text=tostring(value or'')
    if not text:find('[\128-\255]')then return text end
    local result;local index,start=1,1
    while index<=#text do
        local length=lengthAt(text,index)
        if length then index=index+length
        else
            result=result or{}
            if index>start then result[#result+1]=text:sub(start,index-1)end
            index=index+1;while continuation(text:byte(index))do index=index+1 end
            result[#result+1]=replacement;start=index
        end
    end
    if not result then return text end
    if start<=#text then result[#result+1]=text:sub(start)end
    return table.concat(result)
end
return Text
