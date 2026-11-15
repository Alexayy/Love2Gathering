-- Build provenance is embedded by packaging, never inferred as a release.
local json=require('lib.json')
local Info={maxBytes=16384,repository='https://github.com/Alexayy/Love2Gathering'}
local function text(value,limit)
    if type(value)~='string'or#value>limit or value:find('[%z\1-\31\127]')then return nil end
    return value
end
local function revision(value,short)
    value=text(value,40)
    if value and#value>=(short and 7 or 40)and value:match('^[0-9a-f]+$')then return value end
end
function Info.decode(content)
    if type(content)~='string'or#content>Info.maxBytes then return nil end
    local ok,data=pcall(json.decode,content)
    if not ok or type(data)~='table'then return nil end
    local version=text(data.version,48);local sha=revision(data.revision)
    local numeric=version and(version:match('^%d+%.%d+%.%d+%.%d+$')or(data.channel=='source'and version:match('^%d+%.%d+%.%d+$')))
    if not numeric or not sha or not({development=true,stable=true,source=true})[data.channel]then return nil end
    local result={version=version,channel=data.channel,revision=sha,packaged=true}
    result.branch=text(data.branch,128);result.tag=text(data.tag,128)
    local built=text(data.builtAtUTC,40)
    if built and(built:match('^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$')or built:match('^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z$'))then result.builtAtUTC=built end
    result.engineRevision=revision(data.engineRevision)
    if data.repository==Info.repository then result.repository=data.repository end
    return result
end
local function readManifest()
    if not(love and love.filesystem)then return nil end
    local info=love.filesystem.getInfo('build-info.json','file')
    if not info or info.size>Info.maxBytes then return nil end
    return love.filesystem.read('build-info.json',Info.maxBytes+1)
end
local function readStatus()
    local path=os.getenv('LOVE2GATHERING_STARTUP_STATUS');if not path then return nil end
    local file=io.open(path,'rb');if not file then return nil end
    local body=file:read(65537);file:close()
    if not body or#body>65536 then return nil end
    local ok,value=pcall(json.decode,body);if ok and type(value)=='table'then return value end
end
function Info.load(options)
    options=options or{}
    local content=(options.readManifest or readManifest)()
    local result=Info.decode(content)
    if result then return result end
    local status=(options.readStatus or readStatus)()
    return{channel='source',packaged=false,revision=type(status)=='table'and revision(status.version,true)or nil}
end
function Info.lines(info)
    local channel=({development='Development',stable='Stable',source='Source build'})[info.channel]or'Source build'
    local rows={{label='Version',value=info.version or'Source build'},{label='Build channel',value=channel},{label='Revision',value=info.revision or'Not available'}}
    if info.branch and info.branch~=''then rows[#rows+1]={label='Branch',value=info.branch}end
    if info.tag and info.tag~=''then rows[#rows+1]={label='Release tag',value=info.tag}end
    if info.builtAtUTC then rows[#rows+1]={label='Built at (UTC)',value=info.builtAtUTC}end
    if info.engineRevision then rows[#rows+1]={label='XMage revision',value=info.engineRevision}end
    return rows
end
function Info.summary(info)
    local rows={};for _,row in ipairs(Info.lines(info))do rows[#rows+1]=row.label..': '..row.value end
    return table.concat(rows,'\n')
end
return Info
