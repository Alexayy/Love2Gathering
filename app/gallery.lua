-- Paged, read-only art browsing. Card rules and playable actions stay elsewhere.
local API=require('app.api')
local Gallery={}
local function defaults(m)
    m.galleryQuery=m.galleryQuery or '';m.galleryArtist=m.galleryArtist or '';m.gallerySet=m.gallerySet or ''
    m.galleryVariant=m.galleryVariant or 'all';m.galleryLanguage=m.galleryLanguage or 'en'
    m.galleryOffset=m.galleryOffset or 0;m.galleryLimit=m.galleryLimit or 6;m.galleryItems=m.galleryItems or {}
end
function Gallery.install(Model)
    function Model:showGallery()
        defaults(self)
        if self.replay then self.replay.playing=false end
        self.galleryOpening=(self.galleryOpening or 0)+1;self.galleryInspect=nil;self.page='gallery'
        self:refreshGallery()
    end
    function Model:galleryChanged()
        defaults(self);self.galleryOffset=0;self.galleryTimer=.23;self.galleryBusy=true;self.galleryError=nil
        self.galleryVersion=(self.galleryVersion or 0)+1
    end
    function Model:setGalleryLimit(limit)
        defaults(self);limit=math.max(1,math.min(60,math.floor(limit)))
        if self.galleryLimit~=limit then self.galleryLimit=limit;self:galleryChanged() end
    end
    function Model:refreshGallery()
        defaults(self);self.galleryTimer=nil
        local opening=self.galleryOpening;local version=(self.galleryVersion or 0)+1;self.galleryVersion=version
        self.galleryBusy=true;self.galleryError=nil
        local path='/gallery?q='..API.escape(self.galleryQuery)..'&artist='..API.escape(self.galleryArtist)..'&set='..API.escape(self.gallerySet)
            ..'&variant='..API.escape(self.galleryVariant)..'&lang='..API.escape(self.galleryLanguage)..'&limit='..self.galleryLimit..'&offset='..self.galleryOffset
        self:request('catalog','GET',path,nil,function(data,err)
            if opening~=self.galleryOpening or version~=self.galleryVersion then return end
            self.galleryBusy=false
            if data then self.galleryItems=data.items or {};self.galleryTotal=data.total or 0
            else self.galleryItems={};self.galleryTotal=0;self.galleryError=err or 'Artwork index is unavailable' end
        end,true)
    end
    function Model:updateGallery(dt)
        if self.page~='gallery' then return end
        if self.galleryWasReady~=self.catalogHealth.ready then
            self.galleryWasReady=self.catalogHealth.ready
            if self.catalogHealth.ready then self.galleryTimer=0 end
        end
        if self.galleryTimer then
            self.galleryTimer=self.galleryTimer-dt
            if self.galleryTimer<=0 then self:refreshGallery() end
        end
    end
    function Model:getGalleryArt(item)
        self.galleryArt=self.galleryArt or {};self.galleryArtPending=self.galleryArtPending or 0
        local key=item.printing_id..'-'..tostring(item.face or 0)..'-art_crop';local time=love.timer.getTime()
        local entry=self.galleryArt[key]
        if entry then
            entry.used=time
            if entry.image or entry.pending or (entry.retryAt or 0)>time then return entry.image end
        end
        if self.galleryArtPending>=4 then return nil end
        entry={pending=true,used=time};self.galleryArt[key]=entry;self.galleryArtPending=self.galleryArtPending+1
        self.api:request('art','GET','/gallery/art/'..API.escape(item.printing_id)..'?face='..tostring(item.face or 0)..'&kind=art_crop',nil,function(body,err,code)
            self.galleryArtPending=math.max(0,self.galleryArtPending-1)
            if self.galleryArt[key]~=entry then return end
            entry.pending=false;entry.retryAt=love.timer.getTime()+30
            if not err and code==200 and body then
                local ok,img=pcall(function()return love.graphics.newImage(love.image.newImageData(love.filesystem.newFileData(body,'gallery.jpg')))end)
                if ok then
                    entry.image=img
                    local count=0;for _,cached in pairs(self.galleryArt)do if cached.image then count=count+1 end end
                    while count>60 do
                        local oldest,used
                        for candidate,cached in pairs(self.galleryArt)do if candidate~=key and cached.image and (not used or cached.used<used)then oldest,used=candidate,cached.used end end
                        if not oldest then break end;self.galleryArt[oldest]=nil;count=count-1
                    end
                end
            end
        end,true)
    end
    function Model:openGalleryLink(link)
        if type(link)~='table' or type(link.url)~='string' or not link.url:match('^https://[^%s]+$') then return end
        local ok,opened=pcall(love.system.openURL,link.url)
        if not ok or opened==false then self:toast('Could not open the artist link',true) end
    end
end
local function button(v,label,icon,width,height,options)
    options=options or {};options.W=width;options.H=height
    options.Image={Image=v.r.assets:buttonImage(icon,label,width,height,{font=v.r.fonts[14],iconSize=17})}
    return v.S.Button(label,options)
end
local function iconText(v,id,icon,text,width,color)
    local S=v.S;S.Image(id..'-icon',{Image=v.r.assets:iconImage(icon,17,color),W=17,H=17});S.SameLine()
    S.Textf(v.r:fit(text,width-24,14,1),{W=width-24,Color=color or v.r.colors.muted})
end
local function links(v,item,width)
    local S=v.S;local offered=item.artist_links or {}
    if #offered==0 then S.Text('No verified artist links yet',{Color=v.r.colors.muted});return end
    local count=math.min(3,#offered);local bw=(width-(count-1)*6)/count
    for index=1,count do
        if index>1 then S.SameLine({Pad=6}) end
        local link=offered[index];local text=({website='Artist',shop='Shop',services='Services'})[link.kind] or 'Website'
        if button(v,text,'external',bw,28,{Tooltip=link.label..' · verified '..tostring(link.verifiedAt or '')}) then v.m:openGalleryLink(link) end
    end
end
local function art(v,item,x,y,width,height,id)
    local S,m=v.S,v.m;local image=m:getGalleryArt(item)
    S.SetCursorPos(x,y,{Absolute=true})
    S.Rectangle({W=width,H=height,Color={.027,.040,.060,1},Rounding=6})
    if image then
        local scale=math.min(width/image:getWidth(),height/image:getHeight());local iw,ih=image:getWidth()*scale,image:getHeight()*scale
        S.SetCursorPos(x+(width-iw)/2,y+(height-ih)/2,{Absolute=true})
        S.Image(id,{Image=image,W=iw,H=ih,Tooltip='Inspect artwork'})
        if S.IsControlClicked()then m.galleryInspect=item end
    else
        S.SetCursorPos(x+12,y+height/2-12,{Absolute=true})
        S.Text('Loading artwork…',{Color=v.r.colors.muted})
    end
    S.SetCursorPos(x,y+height+9,{Absolute=true})
end
function Gallery.layout(w,h)
    local width=w-76;local columns=math.max(2,math.floor((width+18)/330))
    local cellW=(width-(columns-1)*18)/columns;local imageH=math.min(200,cellW*.60);local cellH=imageH+114
    local rows=math.max(1,math.min(3,math.floor((h-278)/cellH)))
    return {columns=columns,rows=rows,cellW=cellW,imageH=imageH,cellH=cellH,limit=columns*rows}
end
function Gallery.build(v,w,h)
    local S,m,r=v.S,v.m,v.r;defaults(m);local C=r.colors;local l=Gallery.layout(w,h);m:setGalleryLimit(l.limit)
    v:window('gallery-controls',24,102,w-48,132)
    S.Image('gallery-heading',{Image=r.assets:iconImage('gallery',24,C.accent),W=24,H=24});S.SameLine()
    S.PushFont(r.fonts[22]);S.Text('Artwork gallery',{Color=C.text});S.PopFont();S.SameLine()
    S.Text(m.galleryBusy and 'Loading…' or tostring(m.galleryTotal or 0)..' artworks',{Color=C.muted})
    local fieldW=math.max(210,w*.30)
    S.Image('gallery-query-icon',{Image=r.assets:iconImage('search',20,C.muted),W=20,H=20,Tooltip='Search card, artist, set or year'});S.SameLine()
    if S.Input('gallery-search',{Text=m.galleryQuery,W=fieldW,H=29,Align='left',Tooltip='Search card, artist, set or year'})then m.galleryQuery=S.GetInputText();m:galleryChanged()end
    S.SameLine()
    S.Image('gallery-artist-icon',{Image=r.assets:iconImage('artist',20,C.muted),W=20,H=20,Tooltip='Artist name'});S.SameLine()
    if S.Input('gallery-artist',{Text=m.galleryArtist,W=math.max(150,w*.18),H=29,Align='left',Tooltip='Filter artist name'})then m.galleryArtist=S.GetInputText();m:galleryChanged()end
    S.SameLine()
    S.Image('gallery-set-icon',{Image=r.assets:iconImage('library',20,C.muted),W=20,H=20,Tooltip='Set code'});S.SameLine()
    if S.Input('gallery-set',{Text=m.gallerySet,W=95,H=29,Align='left',Tooltip='Set code, for example ELD'})then m.gallerySet=S.GetInputText():lower();m:galleryChanged()end
    S.SameLine()
    if button(v,'Refresh','replay',110,29)then m:refreshGallery()end
    S.NewLine()
    local variants={all='All artwork',extended='Extended art',borderless='Borderless',showcase='Showcase'}
    v:combo('gallery-variant',variants[m.galleryVariant],{'All artwork','Extended art','Borderless','Showcase'},180,function(value)
        for key,label in pairs(variants)do if label==value then m.galleryVariant=key end end;m:galleryChanged()
    end);S.SameLine()
    v:combo('gallery-language',m.galleryLanguage=='all' and 'All languages' or 'English',{'English','All languages'},160,function(value)m.galleryLanguage=value=='English' and 'en' or 'all';m:galleryChanged()end)
    S.SameLine()
    if button(v,'Previous','previous',115,29,{Disabled=m.galleryBusy or m.galleryOffset==0})then m.galleryOffset=math.max(0,m.galleryOffset-m.galleryLimit);m:refreshGallery()end
    S.SameLine()
    if button(v,'Next','next',100,29,{Disabled=m.galleryBusy or m.galleryOffset+m.galleryLimit>=(m.galleryTotal or 0)})then m.galleryOffset=m.galleryOffset+m.galleryLimit;m:refreshGallery()end
    S.SameLine();S.Text(tostring(m.galleryOffset+((m.galleryTotal or 0)>0 and 1 or 0))..'–'..math.min(m.galleryOffset+m.galleryLimit,m.galleryTotal or 0),{Color=C.muted})
    S.EndWindow()
    v:window('gallery-grid',24,248,w-48,h-272)
    if m.galleryError then
        S.Textf(m.galleryError,{W=w-90,Color=C.gold});S.NewLine()
        S.Textf('Choose a local Scryfall metadata file for the catalog, or run the optional image downloader with its explicit metadata bootstrap option. Your existing collection is preserved.',{W=w-90,Color=C.muted})
    elseif #(m.galleryItems or {})==0 and not m.galleryBusy then S.Text('No artworks match these filters.',{Color=C.muted})
    else
        local x,y=S.GetCursorPos({Absolute=true})
        for index,item in ipairs(m.galleryItems or {})do
            local col=(index-1)%l.columns;local row=math.floor((index-1)/l.columns)
            local tx,ty=x+col*(l.cellW+18),y+row*l.cellH
            S.PushID(item.id);S.Indent(tx-x);art(v,item,tx,ty,l.cellW,l.imageH,'gallery-art')
            S.PushFont(r.fonts[18]);S.Textf(r:fit(item.name,l.cellW,18,1),{W=l.cellW,Color=C.text});S.PopFont()
            iconText(v,'gallery-set','library',(item.set_name or item.set or '')..' · '..tostring(item.year or ''),l.cellW,C.muted)
            iconText(v,'gallery-artist','artist',item.artist~='' and item.artist or 'Artist not supplied',l.cellW,C.accent)
            links(v,item,l.cellW);S.Unindent(tx-x);S.PopID()
        end
    end
    S.EndWindow()
    local item=m.galleryInspect
    if item then
        local ww,hh=math.min(1000,w-64),h-96;local inner=ww-32
        v:window('gallery-inspect',(w-ww)/2,48,ww,hh,'Artwork · '..item.name)
        if button(v,'Close artwork','close',inner,30)then m.galleryInspect=nil
        else
            local x,y=S.GetCursorPos({Absolute=true});art(v,item,x,y,inner,math.max(120,hh-204),'gallery-full-art')
            S.Textf(item.name,{W=inner,Color=C.text})
            iconText(v,'art-inspect-set','library',(item.set_name or item.set or '')..' · '..tostring(item.year or ''),inner,C.muted)
            iconText(v,'art-inspect-artist','artist',item.artist~='' and item.artist or 'Artist not supplied',inner,C.accent)
            links(v,item,inner)
        end
        S.EndWindow()
    end
end
return Gallery
