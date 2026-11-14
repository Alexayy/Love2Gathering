-- Presentation of native current abilities. Never infer abilities from Oracle text.
local Traits={}
local symbols={trample=true,flying=true,first_strike=true,double_strike=true,deathtouch=true,lifelink=true,reach=true,menace=true,vigilance=true,haste=true,hexproof=true,indestructible=true,defender=true,shroud=false}
function Traits.entries(card)
    local out,base={},{};local known=type(card.printing)=='table'and type(card.printing.keywords)=='table'
    if known then for _,name in ipairs(card.printing.keywords)do base[name]=true end end
    for _,name in ipairs(type(card.keywords)=='table'and card.keywords or{})do
        if symbols[name]~=nil then
        local label=tostring(name):gsub('_',' ');label=label:sub(1,1):upper()..label:sub(2)
        out[#out+1]={name=name,label=label,icon=symbols[name]and tostring(name):gsub('_','-')or nil,gained=known and not base[name]or false}
        end
    end
    table.sort(out,function(a,b)if a.gained~=b.gained then return a.gained end;return a.label<b.label end)
    return out
end
return Traits
