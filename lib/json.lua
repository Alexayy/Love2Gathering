-- Small JSON codec for the local bridge protocol. JSON null is preserved.
local json = { null = {} }
function json.array(t) return setmetatable(t or {},{__jsontype='array'}) end
local escapes = { ['"']='\\"', ['\\']='\\\\', ['\b']='\\b', ['\f']='\\f', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t' }
local function quote(s)
    return '"' .. s:gsub('[%z\1-\31\\"]', function(c) return escapes[c] or string.format('\\u%04x', c:byte()) end) .. '"'
end
function json.encode(value)
    local seen = {}
    local function encode(v)
        if v == json.null or v == nil then return 'null' end
        if type(v) == 'string' then return quote(v) end
        if type(v) == 'boolean' then return tostring(v) end
        if type(v) == 'number' then assert(v == v and math.abs(v) ~= math.huge, 'Non-finite JSON number'); return tostring(v) end
        assert(type(v) == 'table', 'Unsupported JSON type: ' .. type(v))
        assert(not seen[v], 'Circular JSON value'); seen[v] = true
        local list, n = true, 0
        for k in pairs(v) do if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then list = false; break end; n = math.max(n, k) end
        local out = {}
        if list and (n > 0 or (getmetatable(v) or {}).__jsontype=='array') then
            for i=1,n do out[i] = encode(v[i]) end
        else
            list = false
            for k,x in pairs(v) do out[#out+1] = quote(tostring(k)) .. ':' .. encode(x) end
            table.sort(out)
        end
        seen[v] = nil
        return (list and '[' or '{') .. table.concat(out, ',') .. (list and ']' or '}')
    end
    return encode(value)
end
local function utf8char(n)
    if n < 128 then return string.char(n) elseif n < 2048 then return string.char(192+math.floor(n/64),128+n%64)
    elseif n < 65536 then return string.char(224+math.floor(n/4096),128+math.floor(n/64)%64,128+n%64)
    else return string.char(240+math.floor(n/262144),128+math.floor(n/4096)%64,128+math.floor(n/64)%64,128+n%64) end
end
function json.decode(s)
    local pos, len = 1, #s
    local function fail(message) error(message .. ' at byte ' .. pos) end
    local function skip() local _,e=s:find('^[ \n\r\t]*',pos); pos=(e or pos-1)+1 end
    local value
    local function str()
        pos=pos+1; local out={}; local start=pos
        while pos<=len do
            local c=s:sub(pos,pos)
            if c=='"' then out[#out+1]=s:sub(start,pos-1);pos=pos+1;return table.concat(out) end
            if c=='\\' then
                out[#out+1]=s:sub(start,pos-1);pos=pos+1;c=s:sub(pos,pos)
                local map={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
                if c=='u' then
                    local h=s:sub(pos+1,pos+4); if not h:match('^%x%x%x%x$') then fail('Invalid Unicode escape') end
                    local n=tonumber(h,16);pos=pos+4
                    if n>=55296 and n<=56319 then
                        local lo=s:sub(pos+1,pos+6);if not lo:match('^\\u%x%x%x%x$') then fail('Missing surrogate') end
                        local low=tonumber(lo:sub(3),16);if low<56320 or low>57343 then fail('Invalid surrogate') end
                        n=65536+(n-55296)*1024+low-56320;pos=pos+6
                    end
                    out[#out+1]=utf8char(n)
                elseif map[c] then out[#out+1]=map[c] else fail('Invalid escape') end
                pos=pos+1;start=pos
            else if c:byte()<32 then fail('Control character in string') end; pos=pos+1 end
        end
        fail('Unterminated string')
    end
    value=function()
        skip();local c=s:sub(pos,pos)
        if c=='"' then return str() end
        if c=='{' or c=='[' then
            local object=c=='{';local result=object and {} or json.array();pos=pos+1;skip()
            if s:sub(pos,pos)==(object and '}' or ']') then pos=pos+1;return result end
            while true do
                local key
                if object then if s:sub(pos,pos)~='"' then fail('Expected object key') end;key=str();skip();if s:sub(pos,pos)~=':' then fail('Expected colon') end;pos=pos+1 end
                local v=value();result[object and key or #result+1]=v;skip();local nextc=s:sub(pos,pos);pos=pos+1
                if nextc==(object and '}' or ']') then return result end
                if nextc~=',' then fail('Expected comma') end;skip()
            end
        end
        for word,v in pairs({['true']=true,['false']=false,['null']=json.null}) do
            if s:sub(pos,pos+#word-1)==word then pos=pos+#word;return v end
        end
        -- Match at the cursor without copying the rest of a large replay page.
        local token=s:match('^-?%d+%.?%d*[eE]?[+-]?%d*',pos)
        local n=token and tonumber(token);if not n then fail('Expected JSON value') end;pos=pos+#token;return n
    end
    local result=value();skip();if pos<=len then fail('Trailing data') end;return result
end
return json
