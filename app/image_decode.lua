-- CPU image decoding belongs in HTTP workers; GPU upload stays on the main thread.
local Decode={maxPixels=4*1024*1024,maxBytes=3*1024*1024}
local function u16(data,pos)local a,b=data:byte(pos,pos+1);return a and b and a*256+b end
local function u32(data,pos)local a,b,c,d=data:byte(pos,pos+3);return a and d and((a*256+b)*256+c)*256+d end
function Decode.dimensions(data)
    if type(data)~='string'or#data>Decode.maxBytes then return nil,nil,'Image exceeds the compressed size bound'end
    if data:sub(1,8)=='\137PNG\13\10\26\10'and data:sub(13,16)=='IHDR'then return u32(data,17),u32(data,21)end
    if data:sub(1,2)~='\255\216'then return nil,nil,'Unsupported cached image format'end
    local pos=3
    while pos<=#data do
        if data:byte(pos)~=255 then break end
        while data:byte(pos)==255 do pos=pos+1 end
        local marker=data:byte(pos);pos=pos+1
        if not marker or marker==0xDA or marker==0xD9 then break end
        if marker~=0x01 and not(marker>=0xD0 and marker<=0xD8)then
            local size=u16(data,pos)
            if not size or size<2 or pos+size-1>#data then break end
            if marker>=0xC0 and marker<=0xCF and marker~=0xC4 and marker~=0xC8 and marker~=0xCC then
                if size<8 then break end
                return u16(data,pos+5),u16(data,pos+3)
            end
            pos=pos+size
        end
    end
    return nil,nil,'Image dimensions are missing or truncated'
end
function Decode.decode(data)
    local w,h,problem=Decode.dimensions(data)
    if not w or not h or w<1 or h<1 then return nil,problem or'Invalid image dimensions'end
    if w*h>Decode.maxPixels then return nil,'Image exceeds the decoded pixel bound'end
    local file
    local ok,value=pcall(function()
        file=love.filesystem.newFileData(data,'cached-image')
        return love.image.newImageData(file)
    end)
    if file then file:release()end
    if not ok then return nil,'Image decode failed: '..tostring(value)end
    return value
end
return Decode
