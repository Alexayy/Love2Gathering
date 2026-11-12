package.path='./?.lua;./?/init.lua;'..package.path
local Builder=require('app.builder')
local function overlaps(a,b)return a.x<b.x+b.w and b.x<a.x+a.w and a.y<b.y+b.h and b.y<a.y+a.h end
for _,size in ipairs({{1120,720},{1280,720},{1440,900},{1920,1080},{2560,1440},{3840,2160}})do
    local w,h=size[1],size[2];local l=Builder.layout(w,h)
    local regions={l.search,l.grid,l.controls,l.list};if l.preview then regions[#regions+1]=l.preview end
    for i,a in ipairs(regions)do
        assert(a.w>0 and a.h>0 and a.x>=0 and a.y>=0 and a.x+a.w<=w and a.y+a.h<=h,'Out of bounds '..w..'x'..h)
        for j=i+1,#regions do assert(not overlaps(a,regions[j]),'Overlapping builder panels '..w..'x'..h)end
    end
    assert(l.pageSize==l.columns*l.rows)
    assert(l.columns*l.cardW+(l.columns-1)*14<=l.grid.w+0.01,'Card columns exceed grid')
    assert(l.rows*l.cardH+(l.rows-1)*33+24<=l.grid.h+0.01,'Card rows and labels exceed grid')
    print(('PASS builder geometry %dx%d: %d columns, %d rows'):format(w,h,l.columns,l.rows))
end
