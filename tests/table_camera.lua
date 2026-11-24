package.path='./?.lua;'..package.path
local Camera=require('app.table_camera')
local n=0
local function check(ok,label) assert(ok,label);n=n+1 end
for _,size in ipairs({{1088,592},{1408,772},{2505,913}}) do
    for _,count in ipairs({4,5,6}) do
        local c=Camera.new();local v={x=32,y=224,w=size[1],h=size[2]};c:configure(v,count)
        check(c.rows==math.ceil(count/2) and c.columns==2,'Two-column seat geometry')
        check(c.mode=='overview'and math.abs(c.zoom-math.min(v.w/c.width,v.h/c.height))<.0001,'Initial overview fits every world-space seat')
        c:overview(true);local x,y=c:project(0,0);local bx,by=c:project(c.width,c.height)
        check(x>=v.x-.01 and y>=v.y-.01 and bx<=v.x+v.w+.01 and by<=v.y+v.h+.01,'Explicit overview contains every seat')
        c:focus(count);local old=c.zoom;c:configure(v,count)
        check(c.zoom==old and c.zoom~=c.target.zoom,'Repeated layout does not bypass camera animation')
        for i=1,90 do c:update(1/60,false) end
        local cell=c:cell(count);local sx,sy=c:project(cell.x+cell.w/2,cell.y+cell.h/2)
        check(sx>=v.x and sx<=v.x+v.w and sy>=v.y and sy<=v.y+v.h,'Focus brings the selected seat into view')
        check(c.zoom>=1.149 and c.zoom<=2.001,'Player focus enlarges cards from the overview')
        local before=c.zoom;c:zoomAt(1.2,v.x+v.w/2,v.y+v.h/2);check(math.abs(c.zoom-math.min(2.2,before*1.2))<.001,'Wheel zoom changes only the world transform')
        c:pan(100000,100000);check(c.x>=0 and c.y>=0,'Panning clamps to terrain bounds')
        c:pan(-200000,-200000);check(c.x<=c.width and c.y<=c.height,'Opposite terrain edges are bounded')
        c:overview(true);check(c.focusIndex==nil and c.mode=='overview','Overview clears seat focus')
    end
end
do
    local c=Camera.new();c:configure({x=20,y=220,w=1100,h=620},4)
    local seats={{id='a'},{id='b'},{id='you'},{id='d'}}
    check(not c:followTurn('b',1,seats,nil,true)and c.mode=='overview','Fresh camera does not automatically follow turns')
    check(c:followTurn('b',1,seats,true,true)and c.focusIndex==2,'Explicitly enabling follow focuses the current native player')
    c:focus(3,true);check(not c:followTurn('b',1,seats,true,true)and c.focusIndex==3,'Manual seat focus stays free during the current turn')
    c:pan(30,20);check(not c:followTurn('b',1,seats,true,true)and c.mode=='free','Manual pan is not pulled back by repeated projections')
    check(c:followTurn('d',2,seats,true,true)and c.focusIndex==4,'Next native turn resumes automatic focus')
    c:focus(1,true);check(not c:followTurn('you',3,seats,false,true)and c.focusIndex==1,'Disabled follow preserves manual camera across turns')
    check(c:followTurn('you',3,seats,true,true)and c.focusIndex==3,'Enabling follow focuses the current native active player')
    c:pan(20,0);check(c:followTurn('you',4,seats,true,true)and c.focusIndex==3,'A native extra turn by the same player resumes follow')
    c:pan(20,0);check(not c:followTurn('d',5,seats,true,true,true)and c.mode=='free','Selection and inspection block automatic camera motion')
    check(not c:followTurn('d',5,seats,true,true,false)and c.mode=='free','Ending an interaction does not replay a blocked camera jump')
    check(c:followTurn('a',6,seats,true,true,false)and c.focusIndex==1,'A later turn can follow after the interaction ends')
end
do
    local c=Camera.new();local v={x=20,y=146,w=1160,h=660}
    c:configure(v,4);local normalW,normalH=c.cellW,c.cellH
    c:focus(2,true);c:pan(0,0)
    local offset=c.x-c:cell(2).x
    c:configure(v,4,1500)
    check(c.cellW>=1500 and c.cellW>normalW and c.cellH==normalH,'Crowded terrain gains width independent of card height')
    check(c.mode=='free' and math.abs(c.x-c:cell(2).x-offset)<.001,'Widening terrain preserves the manually panned seat position')
    c:configure(v,4,600)
    check(c.cellW>=1500,'Removing permanents does not collapse the playmats')
    c:overview(true);local right,bottom=c:project(c.width,c.height)
    check(right<=v.x+v.w+.01 and bottom<=v.y+v.h+.01,'Expanded world fits the overview')
    c:focus(3,true)
    check(c.zoom>c.overviewZoom and c.cellW*c.zoom<=v.w+.01,'Focusing expanded terrain fits the selected seat horizontally')
    c:configure(v,4,100000)
    check(c.cellW<2000,'Exceptional board size keeps the world bounded')
    check(c.focusIndex==3 and c.cellW*c.zoom<=v.w+.01,'An already focused seat still fits after its battlefield widens')
    c:overview(true);c:focus(3);local requested=c.target.zoom;c:focus(2)
    check(c.target.zoom==requested,'Switching seats mid-animation retains the requested focus zoom')
end
print('Camera checks: '..n..' passed (presentation geometry only)')
