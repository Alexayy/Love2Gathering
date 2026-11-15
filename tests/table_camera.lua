package.path='./?.lua;'..package.path
local Camera=require('app.table_camera')
local n=0
local function check(ok,label) assert(ok,label);n=n+1 end
for _,size in ipairs({{1088,592},{1408,772},{2505,913}}) do
    for _,count in ipairs({4,5,6}) do
        local c=Camera.new();local v={x=32,y=224,w=size[1],h=size[2]};c:configure(v,count)
        check(c.rows==math.ceil(count/2) and c.columns==2,'Two-column seat geometry')
        check(c.zoom==1 and c.width>v.w and c.height>v.h,'Initial table is life-size pannable world rather than fitted miniatures')
        c:overview(true);local x,y=c:project(0,0);local bx,by=c:project(c.width,c.height)
        check(x>=v.x-.01 and y>=v.y-.01 and bx<=v.x+v.w+.01 and by<=v.y+v.h+.01,'Explicit overview contains every seat')
        c:focus(count);local old=c.zoom;c:configure(v,count)
        check(c.zoom==old and c.zoom~=c.target.zoom,'Repeated layout does not bypass camera animation')
        for i=1,90 do c:update(1/60,false) end
        local cell=c:cell(count);local sx,sy=c:project(cell.x+cell.w/2,cell.y+cell.h/2)
        check(sx>=v.x and sx<=v.x+v.w and sy>=v.y and sy<=v.y+v.h,'Focus brings the selected seat into view')
        check(math.abs(c.zoom-1)<.001,'Player focus restores readable card scale')
        c:zoomAt(1.2,v.x+v.w/2,v.y+v.h/2);check(math.abs(c.zoom-1.2)<.001,'Wheel zoom enlarges the world without changing UI coordinates')
        c:pan(100000,100000);check(c.x>=0 and c.y>=0,'Panning clamps to terrain bounds')
        c:pan(-200000,-200000);check(c.x<=c.width and c.y<=c.height,'Opposite terrain edges are bounded')
        c:overview(true);check(c.focusIndex==nil and c.mode=='overview','Overview clears seat focus')
    end
end
do
    local c=Camera.new();c:configure({x=20,y=220,w=1100,h=620},4)
    local seats={{id='a'},{id='b'},{id='you'},{id='d'}}
    check(c:followTurn('b',1,seats,nil,true)and c.focusIndex==2,'Native active player is followed by default')
    c:focus(3,true);check(not c:followTurn('b',1,seats,true,true)and c.focusIndex==3,'Manual seat focus stays free during the current turn')
    c:pan(30,20);check(not c:followTurn('b',1,seats,true,true)and c.mode=='free','Manual pan is not pulled back by repeated projections')
    check(c:followTurn('d',2,seats,true,true)and c.focusIndex==4,'Next native turn resumes automatic focus')
    c:focus(1,true);check(not c:followTurn('you',3,seats,false,true)and c.focusIndex==1,'Disabled follow preserves manual camera across turns')
    check(c:followTurn('you',3,seats,true,true)and c.focusIndex==3,'Enabling follow focuses the current native active player')
    c:pan(20,0);check(c:followTurn('you',4,seats,true,true)and c.focusIndex==3,'A native extra turn by the same player resumes follow')
end
print('Camera checks: '..n..' passed (presentation geometry only)')
