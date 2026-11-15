package.path='./?.lua;./?/init.lua;'..package.path
local Builder=require('app.builder')
local function overlaps(a,b)return a.x<b.x+b.w and b.x<a.x+a.w and a.y<b.y+b.h and b.y<a.y+a.h end
for _,size in ipairs({{1120,720},{1280,720},{1440,900},{1920,1080},{2560,1440},{3840,2160}})do
    local w,h=size[1],size[2];local l=Builder.layout(w,h)
    local regions={l.search,l.grid,l.controls,l.list};if l.preview then regions[#regions+1]=l.preview end
    local function outer(box,isWindow)return{x=box.x,y=box.y,w=box.w+(isWindow and 14 or 0),h=box.h+(isWindow and 14 or 0)}end
    local outerClassic={outer(l.search,true),outer(l.grid,false),outer(l.controls,true),outer(l.list,true)}
    if l.preview then outerClassic[#outerClassic+1]=outer(l.preview,true)end
    for i,a in ipairs(outerClassic)do
        assert(a.x+a.w<=w and a.y+a.h<=h,'Classic Slab outer border exceeds viewport')
        for j=i+1,#outerClassic do assert(not overlaps(a,outerClassic[j]),'Classic outer Slab border overlaps an adjacent region')end
    end
    for i,a in ipairs(regions)do
        assert(a.w>0 and a.h>0 and a.x>=0 and a.y>=0 and a.x+a.w<=w and a.y+a.h<=h,'Out of bounds '..w..'x'..h)
        for j=i+1,#regions do assert(not overlaps(a,regions[j]),'Overlapping builder panels '..w..'x'..h)end
    end
    assert(l.pageSize==l.columns*l.rows)
    assert(l.columns*l.cardW+(l.columns-1)*14<=l.grid.w+0.01,'Card columns exceed grid')
    assert(l.rows*l.cardH+(l.rows-1)*33+24<=l.grid.h+0.01,'Card rows and labels exceed grid')
    print(('PASS builder geometry %dx%d: %d columns, %d rows'):format(w,h,l.columns,l.rows))
    local simple=Builder.layout(w,h,'Simplified')
    local parts={simple.controls,simple.search,simple.grid,simple.deckToolbar,simple.list}
    for i,a in ipairs(parts)do
        assert(a.w>0 and a.h>0 and a.x>=0 and a.y>=0 and a.x+a.w<=w and a.y+a.h<=h,'Simplified panel out of bounds '..w..'x'..h)
        for j=i+1,#parts do assert(not overlaps(a,parts[j]),'Overlapping Simplified panels '..w..'x'..h)end
    end
    local outerSimple={outer(simple.controls,true),outer(simple.search,true),outer(simple.grid,false),outer(simple.deckToolbar,true),outer(simple.list,false)}
    for i,a in ipairs(outerSimple)do
        assert(a.x+a.w<=w and a.y+a.h<=h,'Simplified Slab outer border exceeds viewport')
        for j=i+1,#outerSimple do assert(not overlaps(a,outerSimple[j]),'Simplified outer Slab border overlaps an adjacent region')end
    end
    assert(simple.columns*simple.cardW+(simple.columns-1)*14<=simple.grid.w+.01,'Simplified card columns exceed grid')
    assert(simple.cardH+24<=simple.grid.h+.01 and simple.grid.y+simple.cardH+24<simple.pagerY,'Simplified card captions overlap page controls')
    assert(simple.pageSize==simple.columns*simple.rows and simple.list.y>simple.grid.y+simple.grid.h,'Shared Simplified search/drop geometry')
    print(('PASS Simplified geometry %dx%d: %d columns'):format(w,h,simple.columns))
    for _,ratio in ipairs({.1,.4,.7,.95})do
        local resized=Builder.layout(w,h,'Simplified',ratio)
        assert(resized.list.h>=179 and resized.list.y+resized.list.h<=h-12,'Resizable deck loses usable height or escapes viewport')
        assert(resized.grid.y+resized.cardH+24<resized.pagerY,'Resizing lets card captions overlap pagination')
        assert(resized.divider.y>resized.pagerY+30 and resized.divider.y+resized.divider.h<resized.deckToolbar.y,'Resize handle overlaps a button toolbar')
    end
end
