local requestName, responseName, port = ...
local http = require('socket.http')
local ltn12 = require('ltn12')
local json = require('lib.json')
local input, output = love.thread.getChannel(requestName), love.thread.getChannel(responseName)
http.TIMEOUT = 8
while true do
    local request = input:demand()
    if request.quit then break end
    local chunks = {}
    local headers = { ['Content-Type']='application/json', ['Connection']='close' }
    local body = request.bodyJson or ''
    headers['Content-Length'] = tostring(#body)
    local ok, code, responseHeaders = http.request({
        url='http://127.0.0.1:' .. port .. request.path, method=request.method or 'GET', headers=headers,
        source=ltn12.source.string(body), sink=ltn12.sink.table(chunks), redirect=false,
    })
    local data = table.concat(chunks)
    local result = { id=request.id, code=tonumber(code) or 0 }
    if not ok then result.error=tostring(code)
    elseif request.binary then result.body=data
    else
        local parsed, value = pcall(json.decode,data)
        if parsed then
            local function clean(t)
                if type(t)~='table' then return t end
                for k,v in pairs(t) do if v==json.null then t[k]=nil elseif type(v)=='table' then clean(v) end end
                return t
            end
            result.body=clean(value)
        else result.error='Invalid response: ' .. data:sub(1,180) end
    end
    output:push(result)
end
