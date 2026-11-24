local requestName, responseName, port = ...
local http = require('socket.http')
local ltn12 = require('ltn12')
local json = require('lib.json')
local socket = require('socket')
require('love.image');require('love.filesystem')
local Decode=require('app.image_decode')
local input, output = love.thread.getChannel(requestName), love.thread.getChannel(responseName)
http.TIMEOUT = 8
while true do
    local request = input:demand()
    if request.quit then break end
    http.TIMEOUT=request.timeout or 8
    local headers = { ['Content-Type']='application/json', ['Connection']='close' }
    local body = request.bodyJson or ''
    headers['Content-Length'] = tostring(#body)
    local ok,code,responseHeaders,data
    local began=socket.gettime()
    for attempt=1,2 do
        local chunks={}
        local received=0
        local sink=request.decodeImage and function(chunk,problem)
            if chunk then received=received+#chunk;if received>Decode.maxBytes then return nil,'Image exceeds the compressed size bound'end;chunks[#chunks+1]=chunk end
            if problem then return nil,problem end;return 1
        end or ltn12.sink.table(chunks)
        local called,value,status,response=pcall(http.request,{
            url='http://127.0.0.1:'..port..request.path,method=request.method or'GET',headers=headers,
            source=ltn12.source.string(body),sink=sink,redirect=false,
        })
        ok,code,responseHeaders=called and value,called and status or value,response
        data=table.concat(chunks)
        if request.retryRead and attempt==1 and(not ok or tonumber(code)==502 or tonumber(code)==503 or tonumber(code)==504)then
            socket.sleep(math.min(1,math.max(.1,tonumber(responseHeaders and responseHeaders['retry-after'])or 1)))
        else break end
    end
    local result = { id=request.id, code=tonumber(code) or 0,timings={httpSeconds=socket.gettime()-began} }
    if responseHeaders then result.imageMeta={variant=responseHeaders['x-love2gathering-art-variant'],thumbPending=responseHeaders['x-love2gathering-thumb-pending']=='1',thumbUnavailable=responseHeaders['x-love2gathering-thumb-unavailable']=='1'}end
    if not ok then result.error=tostring(code)
    elseif request.decodeImage and tonumber(code)==200 then
        local started=socket.gettime()
        result.imageData,result.error=Decode.decode(data)
        result.timings.decodeSeconds=socket.gettime()-started
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
    -- The channel keeps its own reference until the main-thread consumer pops it.
    if result.imageData then result.imageData:release()end
end
