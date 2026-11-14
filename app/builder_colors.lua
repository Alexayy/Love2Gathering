-- Browser filters describe catalog color identity only; they never grant playability.
local Colors={order={'W','U','B','R','G'},names={W='White',U='Blue',B='Black',R='Red',G='Green',C='Colorless'}}
function Colors.symbols(m)
    local selected=m.searchColors or{}
    if selected.C then return'C'end
    local result={};for _,symbol in ipairs(Colors.order)do if selected[symbol]then result[#result+1]=symbol end end
    return table.concat(result)
end
function Colors.selected(m,symbol)
    local selected=Colors.symbols(m)
    return symbol=='All'and selected==''or symbol~='All'and selected:find(symbol,1,true)~=nil
end
function Colors.summary(m)
    local selected=Colors.symbols(m)
    if selected==''then return'All color identities'end
    if selected=='C'then return'Colorless identity'end
    local names={};for _,symbol in ipairs(Colors.order)do if selected:find(symbol,1,true)then names[#names+1]=Colors.names[symbol]end end
    return(m.searchColorExact and'Exact identity: 'or'Any selected color: ')..table.concat(names,' / ')
end
function Colors.install(Model)
    function Model:setSearchColor(symbol)
        if symbol~='All'and not Colors.names[symbol]then return end
        self.searchColor=symbol;self.searchColors=symbol=='All'and{}or{[symbol]=true};self.searchColorExact=false
        self.searchVersion=(self.searchVersion or 0)+1;self.cards={};self:searchChanged()
    end
    function Model:toggleSearchColor(symbol)
        if symbol=='All'then self:setSearchColor('All');return end
        if not Colors.names[symbol]then return end
        self.searchColors=self.searchColors or{}
        local enabled=self.searchColors[symbol]
        if symbol=='C'then self.searchColors={};if not enabled then self.searchColors.C=true end
        else self.searchColors.C=nil;self.searchColors[symbol]=not enabled or nil end
        local selected=Colors.symbols(self)
        self.searchColor=#selected==1 and selected or'All'
        if selected==''then self.searchColorExact=false end
        self.searchVersion=(self.searchVersion or 0)+1;self.cards={};self:searchChanged()
    end
    function Model:toggleExactSearchColors()
        if Colors.symbols(self)==''then return end
        self.searchColorExact=not self.searchColorExact
        self.searchVersion=(self.searchVersion or 0)+1;self.cards={};self:searchChanged()
    end
end
return Colors
