-- Viewer-filtered presentation only. This module never computes legal actions.
local FX={}
local tau=math.pi*2
local EMPTY={}
local profiles={}
local neutralColor={.65,.72,.78}
local multicolor={.85,.79,.63}
local colorless={.64,.79,.85}
local colorsByName={W={.91,.86,.70},U={.39,.73,.93},B={.67,.51,.78},R={.98,.59,.38},G={.38,.80,.60}}
local aliases={jumpstart='jump_start',firststrike='first_strike',doublestrike='double_strike',livingweapon='living_weapon',
    modal_double_faced='modal_double_faced',double_faced='transform',face_down='face_down',megamorph='megamorph',
    totem_armor='umbra_armor',land_walk='landwalk',spell_mastery='spell_mastery',['doctor_s_companion']='doctors_companion',
    ['council_s_dilemma']='councils_dilemma'}
local cache=setmetatable({},{__mode='k'})
local function list(t)return type(t)=='table'and t or EMPTY end
local function outlinePolygon(...)love.graphics.polygon('line',...)end
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function hash(s)local h=0;for i=1,#tostring(s or'')do h=(h*31+tostring(s):byte(i))%65521 end;return h end
function FX.normalize(value)
    value=tostring(value or''):gsub('(%l)(%u)','%1_%2'):lower():gsub("['’]",'_'):gsub('[_%s%-]+','_'):gsub('^_+',''):gsub('_+$','')
    return aliases[value]or value
end
local function register(id,glyph,recipe,category,weight,coverage)
    profiles[id]={id=id,label=id:gsub('_',' '),glyph=glyph,recipe=recipe,category=category or'keyword',weight=weight or 1,
        coverage=coverage or'explicit',duration=.68,intensity=.7,bounds='edge',sorting='card_overlay',quality='bounded'}
end
local rows={
    {'flashback','return_ring','reform','alternative_cost',8},{'jump_start','fuel','electric','additional_cost',8},
    {'evoke','echo','unravel','alternative_cost',8},{'convoke','sockets','converge','payment',8},
    {'mutate','layers','interweave','alternative_cost',9},{'morph','shell','unfold','special_action',7},
    {'megamorph','shell_plus','unfold','special_action',7},{'disguise','mask','unfold','alternative_cost',7},
    {'manifest','fold','unfold','keyword_action',7},{'cloak','cloak','unfold','keyword_action',7},
    {'haste','streak','accelerate','keyword',6},{'extort','toll','collect','trigger',7},
    {'trample','chevron','overflow','keyword',6},{'reach','net','intercept','keyword',6},
    {'flying','wing','lift','keyword',6},{'vigilance','sentinel','sentinel','keyword',5},
    {'first_strike','slash','slash','keyword',5},{'double_strike','double_slash','double_slash','keyword',6},
    {'deathtouch','thorn','venom','keyword',5},{'lifelink','return_ribbon','restore','keyword',5},
    {'menace','fork','fork','keyword',5},{'defender','brace','brace','keyword',4},
    {'hexproof','lattice','lattice','keyword',5},{'shroud','closed_lattice','lattice','keyword',4},
    {'ward','toll_ring','toll','trigger',5},{'indestructible','facet','facet','keyword',5},
    {'protection','shield','shield','keyword',5},{'infect','needle','spore','keyword',5},
    {'toxic','poison','poison','keyword',5},{'wither','erode','erode','keyword',5},
    {'prowess','rise','rise','trigger',4},{'exalted','focus','focus','trigger',4},
    {'regeneration','restore_shell','restore','keyword_action',4},{'persist','return_minus','reassemble','trigger',5},
    {'undying','return_plus','reassemble','trigger',5},{'flash','timing','timing','permission',5},
    {'kicker','socket','charge','additional_cost',5},{'multikicker','multi_socket','charge','additional_cost',5},
    {'buyback','return_seal','return','additional_cost',6},{'bargain','offering','offering','additional_cost',6},
    {'casualty','offering_split','offering','additional_cost',6},{'improvise','gear','converge','payment',6},
    {'delve','fragments','subtract','payment',6},{'escape','broken_seal','reform','alternative_cost',6},
    {'overload','expand','expand','alternative_cost',6},{'dash','speed','temporary','alternative_cost',6},
    {'blitz','speed_echo','temporary','alternative_cost',6},{'emerge','unfurl','emerge','alternative_cost',6},
    {'spectacle','spotlight','unlock','alternative_cost',5},{'surge','surge','unlock','alternative_cost',5},
    {'prototype','construction','construct','alternative_cost',6},{'bestow','weave','weave','alternative_cost',6},
    {'cycling','cycle','cycle','activated',6},{'channel','extract','extract','activated',6},
    {'unearth','stairs','reassemble','activated',6},{'ninjutsu','exchange','exchange','activated',6},
    {'equip','attachment','attach','activated',4},{'reconfigure','components','attach','activated',5},
    {'crew','contributors','converge','activated',5},{'saddle','saddle','converge','activated',5},
    {'foretell','prepare','prepare','special_action',6},{'plot','plan','prepare','special_action',6},
    {'suspend','clock','time','special_action',6},{'rebound','rebound','return','trigger',5},
    {'adventure','routes','routes','permission',6},{'modal_double_faced','faces','unfold','permission',6},
    {'split','split','routes','permission',5},{'fuse','fuse','converge','permission',5},
    {'cascade','cascade','reveal','trigger',5},{'discover','discover','reveal','keyword_action',5},
    {'storm','echoes','copies','trigger',5},{'replicate','replicate','copies','additional_cost',5},
    {'transform','hinge','unfold','keyword_action',5},{'meld','assembly','assemble','keyword_action',5},
    {'phasing','phase','phase','keyword',5},{'scry','eye_up','reveal','keyword_action',5},
    {'surveil','eye_down','reveal','keyword_action',5},{'landfall','land_rune','pulse','ability_word',4},
    {'face_down','shell','neutral','state',9},
}
local unpackRows=table.unpack or unpack
for _,row in ipairs(rows)do register(unpackRows(row))end
local faceDownProfiles={profiles.face_down}
-- Composed profiles retain a named, parameterized glyph; coverage is not
-- claimed to be a hand-authored animation for each obscure engine keyword.
local families={
    {'counter','counter_chip','chip','keyword_action','adapt bolster evolve graft mentor modular outlast reinforce renown tribute unleash monstrosity fabricate support training backup amass proliferate acclimate'},
    {'cost','socket','charge','additional_cost','affinity convoke improvise convoke_mana delve convoke_cost bargain casualty offering convoke_alternative retrace escalate entwine splice strive squad offspring spree cleave spectacle surge bargain assist ferocious convoke_any'},
    {'return','return_ring','reform','trigger','aftermath disturb embalm eternalize encore retrace rebound recover retrace_cost resurrection modular_returns haunt soulshift deathbound scavenge dredge soulbond soulshift'},
    {'combat','chevron','accelerate','keyword','annihilator banding battalion battle_cry bloodthirst bloodrush bushido flanking frenzy horsemanship intimidate rampage provoke skulk shadow landwalk forestwalk islandwalk swampwalk mountainwalk plainswalk lure melee myriad dethrone enrage riot mobilize enlist boast double_team'},
    {'defense','facet','shield','keyword','absorb armor_totem umbra_armor daybound nightbound decayed indestructible battle_cry_after absorb_damage protection_from'},
    {'reveal','eye_up','reveal','keyword_action','explore investigate connive learn surveil mill manifest_dread clash dice_roll venture initiative monarch seek conjure draft loot support_scry'},
    {'resource','extract','extract','activated','bloodrush transmute transfigure typecycling landcycling wizardcycling mountaincycling islandcycling swampcycling plainscycling forestcycling basic_landcycling cycling_mana soulcycling replenish replenish_resource regenerate food'},
    {'transform','layers','interweave','keyword','augment host craft mutate meld transform disguise morph megamorph manifest cloak reconfigure level_up leveler mutate_merge living_weapon for_mirrodin bestow partner background choose_a_background friends_forever doctors_companion'},
    {'time','clock','time','keyword','echo fading vanishing cumulative_upkeep suspend daybound nightbound forecast exert exerted exert_cost rebirth foretell plot hideaway training_return'},
    {'trigger','rise','pulse','ability_word','adamant addendum alliance ascend celebration changeling chroma constellation converge council_s_dilemma delirium domain eminence fateful_hour ferocious formidable grandeur hellbent heroic imprint inspired join_forces kinship landfall lieutenant metalcraft morbid parley radiance raid rally revolt threshold undergrowth valiant magecraft pack_tactics magecraft_trigger survival eerie'},
}
for _,family in ipairs(families)do
    for name in family[5]:gmatch('%S+')do if not profiles[name]then register(name,family[2],family[3],family[4],2,'composed');profiles[name].family=family[1]end end
end
-- Reviewed native class variants. These reuse a meaningful visual family;
-- no dynamic card-name/rules-text interpretation is involved.
local nativeCompositions={
    {'socket','charge','alternative_cost','affinity_for_artifacts compleated freerunning miracle prowl undaunted'},
    {'return_ring','reform','permission','cast_from_graveyard mayhem mayhem_land madness harmonize'},
    {'counter_chip','chip','trigger','afflict afterlife amplify bounty increment ravenous repair sunburst'},
    {'exchange','exchange','alternative_cost','aura_swap beam_me_up sneak web_slinging'},
    {'eye_up','reveal','additional_cost','behold collect_evidence'},
    {'offering','offering','additional_cost','blight devour gift'},
    {'offering','offering','trigger','exploit'},
    {'contributors','converge','additional_cost','conspire teamwork waterbend'},
    {'construction','construct','alternative_cost','awaken'},
    {'fork','fork','keyword','bands_with_other cant_attack_or_block_alone daunt fear'},
    {'focus','focus','keyword','can_attack_only_alone'},
    {'net','intercept','keyword','can_block_spaceflight'},
    {'phase','phase','keyword','cant_be_blocked_source devoid'},
    {'clock','time','alternative_cost','impending'},
    {'stairs','construct','activated','class_level class_reminder station station_level tiered'},
    {'assembly','construct','activated','job_select power_up'},
    {'routes','routes','permission','companion partner_with'},
    {'echoes','copies','trigger','commander_storm demonstrate gravestorm ripple squirrellink'},
    {'attachment','attach','keyword','enchant champion'},
    {'gear','attach','activated','fortify exhaust'},
    {'streak','accelerate','trigger','firebending start_your_engines'},
    {'fragments','subtract','trigger','ingest'},
    {'gear','construct','keyword','living_metal'},
    {'cycle','cycle','activated','meditate artifact_landcycling'},
    {'layers','unfold','alternative_cost','more_than_meets_the_eye'},
    {'poison','poison','keyword','poisonous'},
    {'routes','reveal','keyword','read_ahead'},
    {'prepare','prepare','keyword','leyline split_second rulebreaker storied'},
    {'speed_echo','temporary','alternative_cost','warp'},
    {'lattice','lattice','keyword','hexproof_base hexproof_from_black hexproof_from_blue hexproof_from_each_color hexproof_from_green hexproof_from_instants hexproof_from_monocolored hexproof_from_multicolored hexproof_from_planeswalkers hexproof_from_red hexproof_from_white'},
    {'shield','shield','keyword','protection_from_each_opponent protection_from_everything'},
    {'multi_socket','charge','additional_cost','kicker_with_any_number_modes'},
    {'chevron','overflow','keyword','trample_over_planeswalkers'},
    {'wing','lift','keyword','spaceflight'},
}
for _,row in ipairs(nativeCompositions)do for name in row[4]:gmatch('%S+')do
    if not profiles[name]then register(name,row[1],row[2],row[3],2,'composed')end
end end
local unsupported={paradigm='Native ParadigmAbility is explicitly a TODO stub at the pinned engine revision.'}
FX.profiles=profiles
function FX.profile(value)
    local id=FX.normalize(type(value)=='table'and(value.id or value.name)or value)
    if profiles[id]then return profiles[id]end
    if unsupported[id]then return{id=id,label=type(value)=='table'and(value.name or id)or tostring(value),glyph='unknown',recipe='neutral',category='native_stub',coverage='unsupported',weight=0,limitation=unsupported[id]}end
    return{id=id,label=type(value)=='table'and(value.name or id:gsub('_',' '))or tostring(value),glyph='unknown',recipe='neutral',category=type(value)=='table'and value.category or'unknown',coverage='generic',weight=0,duration=.4,intensity=.3}
end
function FX.cardProfiles(card)
    if type(card)~='table'then return{}end
    if card.hidden and not card.faceDown then return EMPTY end
    if card.faceDown then return faceDownProfiles end
    local saved=cache[card]
    if saved and saved.mechanics==card.mechanics and saved.current==card.currentKeywords and saved.capabilities==card.mechanicCapabilities and saved.keywords==card.keywords and saved.revision==card.characteristicsRevision then return saved.profiles end
    local out,seen={},{}
    local source=card.mechanics
    if type(source)~='table'then
        source={}
        for _,value in ipairs(list(card.currentKeywords or card.keywords))do source[#source+1]=value end
        for _,value in ipairs(list(card.mechanicCapabilities))do source[#source+1]=value end
    end
    for _,value in ipairs(list(source))do
        local p=FX.profile(value)
        if type(value)=='table'and(value.parameter~=nil or value.name)then
            local instance={};for k,v in pairs(p)do instance[k]=v end
            instance.parameter=value.parameter;instance.label=value.name or p.label
            instance.nativeClass=value.nativeClass;instance.rule=value.rule
            p=instance
        end
        if p.id~=''and not seen[p.id]then seen[p.id]=true;out[#out+1]=p end
    end
    table.sort(out,function(a,b)return a.weight==b.weight and a.id<b.id or a.weight>b.weight end)
    cache[card]={profiles=out,mechanics=card.mechanics,current=card.currentKeywords,capabilities=card.mechanicCapabilities,keywords=card.keywords,revision=card.characteristicsRevision};return out
end
function FX.tooltip(card)
    local labels={};for _,p in ipairs(FX.cardProfiles(card))do labels[#labels+1]=p.label..(p.coverage=='generic'and' · static label; no authored effect'or p.coverage=='unsupported'and' · native implementation unavailable'or'')end
    return table.concat(labels,' · ')
end
local special={alternative_cost=true,additional_cost=true,payment=true,permission=true,activated=true,special_action=true}
function FX.hasOptions(card)
    if type(card)~='table'or card.hidden or card.faceDown then return false end
    for _,p in ipairs(FX.cardProfiles(card))do if special[p.category]then return true end end
    return false
end
function FX.settings(r)
    local s=r.model.settings or{}
    return s,clamp(tonumber(s.vfxIntensity)or .65,0,1),s.animations~=false and not s.reducedMotion and s.presentationPacing~='Minimal'
end
local function tint(c,a)love.graphics.setColor(c[1],c[2],c[3],a or 1)end
function FX.color(card)
    -- Only current object colors, never deck color identity or hidden printings.
    if type(card)~='table'or card.hidden or card.faceDown then return neutralColor end
    local colors=list(card.colors);if#colors>1 then return multicolor end
    return colorsByName[colors[1]]or colorless
end
local function ring(x,y,r,gap,turn)
    love.graphics.arc('line','open',x,y,r,(turn or 0)+(gap or .15),tau+(turn or 0)-(gap or .15),30)
end
function FX.glyph(p,x,y,size,phase)
    local g=type(p)=='table'and p.glyph or p;local r=size*.38;local cx,cy=x+size/2,y+size/2
    love.graphics.setLineWidth(math.max(1,size*.075));love.graphics.setLineJoin('bevel')
    local L=love.graphics.line
    local P=outlinePolygon
    if g=='card'then
        love.graphics.rectangle('line',cx-r*.7,cy-r,r*1.4,r*2,1,1);L(cx-r*.45,cy-r*.5,cx+r*.45,cy-r*.5)
    elseif g=='return_ring'or g=='return_minus'or g=='return_plus'or g=='return_seal'or g=='rebound'then
        ring(cx,cy,r,.53,-.3);L(cx+r*.8,cy-r*.7,cx+r*.95,cy-r*.04,cx+r*.3,cy-r*.16)
        if g=='return_plus'then L(cx-r*.25,cy,cx+r*.25,cy);L(cx,cy-r*.25,cx,cy+r*.25)elseif g=='return_minus'then L(cx-r*.25,cy,cx+r*.25,cy)end
    elseif g=='fuel'then ring(cx,cy,r,.60,.2);L(cx-r*.9,cy-r*.8,cx-r*.3,cy,cx-r*.8,cy+r*.65);L(cx+r*.1,cy-r*.8,cx+r*.5,cy-r*.1,cx,cy+r*.7)
    elseif g=='wing'or g=='net'then
        L(cx-r,cy+r*.5,cx-r*.7,cy-r*.6,cx,cy-r*.1,cx+r*.7,cy-r*.6,cx+r,cy+r*.5)
        if g=='net'then L(cx-r*.8,cy,cx+r*.8,cy);L(cx-r*.5,cy-r*.4,cx+r*.5,cy+r*.4);L(cx+r*.5,cy-r*.4,cx-r*.5,cy+r*.4)end
    elseif g=='streak'or g=='speed'or g=='speed_echo'or g=='surge'then
        for i=0,2 do L(cx-r+i*r*.19,cy-r*.6+i*r*.55,cx+r*.45,cy-r*.6+i*r*.55,cx+r,cy-r*.9+i*r*.55)end
        if g=='speed_echo'then L(cx-r*.9,cy+r*.9,cx+r*.5,cy+r*.9)end
    elseif g=='chevron'or g=='fork'or g=='exalted'then
        L(cx-r,cy+r*.6,cx,cy-r*.7,cx+r,cy+r*.6);L(cx-r*.7,cy+r,cx,cy-r*.05,cx+r*.7,cy+r)
        if g=='fork'then L(cx,cy-r*.7,cx,cy+r)end
    elseif g=='slash'or g=='double_slash'or g=='needle'then
        L(cx-r,cy+r,cx+r,cy-r);if g=='double_slash'then L(cx-r,cy+r*.25,cx+r*.25,cy-r)end
        if g=='needle'then P(cx-r,cy+r,cx+r*.5,cy-r*.8,cx+r,cy-r,cx+r*.8,cy-r*.5)end
    elseif g=='lattice'or g=='closed_lattice'or g=='facet'or g=='shield'or g=='restore_shell'then
        P(cx,cy-r,cx+r,cy-r*.45,cx+r*.7,cy+r*.55,cx,cy+r,cx-r*.7,cy+r*.55,cx-r,cy-r*.45)
        if g=='lattice'or g=='closed_lattice'then L(cx-r*.7,cy-r*.4,cx+r*.7,cy+r*.4);L(cx+r*.7,cy-r*.4,cx-r*.7,cy+r*.4)elseif g=='facet'then L(cx,cy-r,cx-r*.5,cy+r*.4,cx+r*.5,cy+r*.4,cx,cy-r)end
    elseif g=='layers'or g=='components'or g=='assembly'or g=='construction'or g=='faces'or g=='echo'then
        love.graphics.rectangle('line',cx-r,cy-r*.85,r*1.25,r*1.5,1,1)
        love.graphics.rectangle('line',cx-r*.25,cy-r*.4,r*1.25,r*1.5,1,1)
        if g=='assembly'or g=='components'then L(cx-r*.25,cy,cx+r*.25,cy)end
    elseif g=='shell'or g=='shell_plus'or g=='fold'or g=='mask'or g=='cloak'then
        P(cx,cy-r,cx+r,cy-r*.4,cx+r*.5,cy+r,cx-r*.5,cy+r,cx-r,cy-r*.4);L(cx-r,cy-r*.4,cx,cy+r,cx+r,cy-r*.4)
        if g=='mask'then L(cx-r*.45,cy-r*.15,cx-r*.1,cy-r*.05);L(cx+r*.1,cy-r*.05,cx+r*.45,cy-r*.15)end
        if g=='shell_plus'then L(cx-r*.3,cy+r*1.2,cx+r*.3,cy+r*1.2)end
    elseif g=='socket'or g=='multi_socket'or g=='sockets'or g=='contributors'or g=='gear'or g=='saddle'then
        for i=1,(g=='socket'and 1 or g=='multi_socket'and 4 or 3)do local a=i*tau/(g=='multi_socket'and 4 or 3);local px,py=cx+math.cos(a)*r*.75,cy+math.sin(a)*r*.75;love.graphics.circle('line',px,py,r*.25,8);L(px,py,cx,cy)end
        love.graphics.circle('line',cx,cy,r*.2,8)
    elseif g=='toll'or g=='toll_ring'or g=='clock'or g=='prepare'or g=='plan'then
        ring(cx,cy,r,.08);L(cx,cy-r*.62,cx,cy,cx+r*.55,cy+r*.35)
        if g=='toll'or g=='toll_ring'then L(cx-r*.6,cy+r*.9,cx+r*.6,cy+r*.9);love.graphics.circle('line',cx,cy-r*.15,r*.28,8)end
    elseif g=='attachment'or g=='weave'or g=='exchange'or g=='fuse'then
        love.graphics.ellipse('line',cx-r*.35,cy,r*.7,r*.42,14);love.graphics.ellipse('line',cx+r*.35,cy,r*.7,r*.42,14)
        if g=='exchange'then L(cx-r,cy-r*.8,cx+r,cy-r*.8,cx+r*.6,cy-r*1.1)end
    elseif g=='eye_up'or g=='eye_down'or g=='discover'or g=='spotlight'then
        P(cx-r,cy,cx,cy-r*.65,cx+r,cy,cx,cy+r*.65);love.graphics.circle('line',cx,cy,r*.25,10)
        L(cx-r*.3,cy+(g=='eye_down'and r or-r),cx,cy+(g=='eye_down'and r*1.3 or-r*1.3),cx+r*.3,cy+(g=='eye_down'and r or-r))
    elseif g=='timing'then L(cx-r,cy-r,cx-r,cy+r,cx+r*.6,cy+r);L(cx-r*.3,cy,cx+r*.9,cy-r*.8,cx+r*.2,cy-r*.9)
    elseif g=='brace'or g=='sentinel'then L(cx-r,cy+r,cx+r,cy+r);P(cx-r*.6,cy+r,cx-r*.6,cy-r*.6,cx,cy-r,cx+r*.6,cy-r*.6,cx+r*.6,cy+r)
    elseif g=='thorn'or g=='poison'then
        L(cx,cy+r,cx,cy-r);for i=0,2 do L(cx-r*.65,cy-r*.55+i*r*.5,cx,cy-r*.1+i*r*.5,cx+r*.65,cy-r*.55+i*r*.5)end
    elseif g=='return_ribbon'or g=='cycle'then ring(cx,cy,r,.28);L(cx-r*.7,cy-r*.7,cx,cy-r*.9,cx-r*.2,cy-r*.25);L(cx+r*.7,cy+r*.7,cx,cy+r*.9,cx+r*.2,cy+r*.25)
    elseif g=='phase'then for i=0,2 do L(cx-r+i*r*.75,cy-r,cx-r*.5+i*r*.75,cy+r)end
    elseif g=='offering'or g=='offering_split'or g=='extract'then P(cx,cy-r,cx+r*.5,cy,cx,cy+r*.6,cx-r*.5,cy);L(cx-r,cy+r,cx+r,cy+r);if g=='offering_split'then L(cx-r*.9,cy,cx+r*.9,cy)end
    elseif g=='stairs'then L(cx-r,cy+r,cx-r,cy+r*.3,cx-r*.35,cy+r*.3,cx-r*.35,cy-r*.3,cx+r*.35,cy-r*.3,cx+r*.35,cy-r,cx+r,cy-r)
    elseif g=='echoes'or g=='replicate'or g=='cascade'then for i=0,2 do love.graphics.rectangle('line',cx-r+i*r*.45,cy-r+i*r*.45,r*1.2,r*1.2,1,1)end
    elseif g=='hinge'or g=='routes'or g=='split'then L(cx,cy+r,cx,cy-r);L(cx,cy,cx-r,cy-r*.7);L(cx,cy,cx+r,cy-r*.7)
    elseif g=='counter_chip'then love.graphics.rectangle('line',cx-r*.75,cy-r*.75,r*1.5,r*1.5,2,2);L(cx-r*.4,cy,cx+r*.4,cy);L(cx,cy-r*.4,cx,cy+r*.4)
    elseif g=='broken_seal'or g=='fragments'or g=='erode'then for i=1,5 do local a=i*tau/5;love.graphics.rectangle('line',cx+math.cos(a)*r*.7,cy+math.sin(a)*r*.7,r*.3,r*.3)end
    elseif g=='rise'or g=='unfurl'or g=='land_rune'or g=='focus'or g=='expand'then P(cx,cy-r,cx+r,cy,cx,cy+r,cx-r,cy);L(cx-r*.5,cy,cx+r*.5,cy);if g=='rise'then L(cx,cy,cx,cy-r*1.4)end
    else
        -- Unknowns are honest static named sigils, never an invented mechanic.
        local n=3+hash(type(p)=='table'and p.id or g)%4
        for i=1,n do local a=i*tau/n;L(cx+math.cos(a)*r*.45,cy+math.sin(a)*r*.45,cx+math.cos(a)*r,cy+math.sin(a)*r)end
    end
end
local maskTint={1,1,1,1}
local function drawSurface(r,name,x,y,w,h,c,alpha)
    if r.assets and r.assets.surface then
        maskTint[1],maskTint[2],maskTint[3],maskTint[4]=c[1],c[2],c[3],alpha
        r.assets:surface(name,x,y,w,h,maskTint)
    end
end
function FX.cardUnderlay(r,card,x,y,w,h,options)
    if options and(options.presentationGhost or options.imageOnly)then return end
    local s,intensity,moving=FX.settings(r);if s.ambientKeywordFX==false or not moving or intensity<=0 then return end
    local p=FX.cardProfiles(card)[1];if not p or p.coverage=='generic'then return end
    local c=FX.color(card);local clock=r.fxClock or 0
    love.graphics.push('all')
    if p.coverage=='unsupported'then love.graphics.pop();return end
    if p.recipe=='lift'and s.parallax~=false then
        tint(c,.12*intensity);love.graphics.ellipse('line',x+w/2,y+h+4,w*.42,h*.065,28)
    elseif p.recipe=='unravel'or p.recipe=='interweave'then
        tint(c,.15*intensity);love.graphics.rectangle('line',x+3+math.sin(clock*1.7)*2,y-3,w,h,5,5)
        drawSurface(r,'halo',x-w*.14,y-h*.06,w*1.28,h*1.12,c,.10*intensity)
    elseif p.recipe=='reform'or p.recipe=='reassemble'then
        tint(c,.15*intensity);love.graphics.rectangle('line',x-3,y+3,w,h,6,6)
    elseif p.recipe=='lattice'or p.recipe=='facet'or p.recipe=='shield'then
        drawSurface(r,'hex-pattern',x-3,y-3,w+6,h+6,c,.10*intensity)
    end
    love.graphics.pop()
end
function FX.cardOverlay(r,card,x,y,w,h,options)
    if options and(options.presentationGhost or options.imageOnly)then return end
    if not card then return end
    local publicFaceDown=card.faceDown and options and(options.kind=='permanent'or options.kind=='attachment'or options.publicFaceDown)
    if card.hidden and not publicFaceDown then return end
    local ps=FX.cardProfiles(card);if#ps==0 then return end
    local s,intensity,moving=FX.settings(r);local c=FX.color(card);local clock=r.fxClock or 0
    local selectable=r.model.canSelect and r.model:canSelect(card.id)or false
    local badge=clamp(w*.16,14,23);local by=y+h-badge-4;local count=math.min(2,#ps)
    love.graphics.push('all')
    for i=1,count do
        local bx=x+4+(i-1)*(badge+3)
        love.graphics.setColor(.018,.027,.038,.94);love.graphics.rectangle('fill',bx-1,by-1,badge+2,badge+2,3,3)
        tint(c,i==1 and .95 or .66);FX.glyph(ps[i],bx,by,badge,clock)
    end
    if#ps>2 and r.text then r:text('+'..(#ps-2),x+5+count*(badge+3),by+2,math.min(13,badge*.7),c,28,'left')end
    if publicFaceDown then
        tint(c,.45);love.graphics.setLineWidth(1)
        love.graphics.line(x+7,y+h*.18,x+w*.5,y+h*.29,x+w-7,y+h*.18)
        love.graphics.line(x+7,y+h*.18,x+w*.5,y+h*.72,x+w-7,y+h*.18)
    end
    if FX.hasOptions(card)or selectable then
        local Actions=package.loaded['app.card_actions']
        local record=selectable and Actions and Actions.record and Actions.record(r.model,card)
        local count=record and type(record.options)=='table'and#record.options or 0
        local selected=r.model.cardActionSheet and r.model.cardActionSheet.objectId==card.id
        local cx,cy=x+w-15,y+15;local alpha=selectable and 1 or .42
        if selected then tint(c,.13);love.graphics.circle('fill',cx,cy,14)end
        tint(c,alpha);ring(cx,cy,10,.48,-.4);love.graphics.setLineWidth(1.8)
        love.graphics.line(cx,cy+5,cx,cy-4,cx-4,cy-7);love.graphics.line(cx,cy-1,cx+5,cy-5)
        if selectable then love.graphics.circle('fill',cx-4,cy-7,1.8);love.graphics.circle('fill',cx+5,cy-5,1.8)end
        if count>1 and r.text then r:text(tostring(count),cx+6,cy+2,10,c,16,'center')end
    end
    if s.ambientKeywordFX~=false and moving and intensity>0 and not card.faceDown then
        for i=1,math.min(2,#ps)do
            local p=ps[i];local alpha=(i==1 and .34 or .14)*intensity
            if p.coverage~='generic'and p.coverage~='unsupported'then
                tint(c,alpha);love.graphics.setLineWidth(1.4)
                local t=clock*(p.recipe=='accelerate'and 1.8 or .35)+hash(p.id)*.01
                if p.recipe=='accelerate'or p.recipe=='temporary'then
                    for j=1,3 do local shift=(t+j*.27)%1;love.graphics.line(x+w*.1,y+h-3-j*3,x+w*(.2+.62*shift),y+h-3-j*3)end
                    if selectable then tint(c,alpha*1.8);love.graphics.line(x+w*.72,y+h-10,x+w-3,y+h-10)end
                elseif p.recipe=='lift'or p.recipe=='intercept'then
                    for j=1,2 do local yy=y+h*.20-j*4+math.sin(t+j)*2;love.graphics.arc('line','open',x+w*.5,yy,w*.45,math.pi*1.15,math.pi*1.85,18)end
                elseif p.recipe=='lattice'or p.recipe=='shield'or p.recipe=='facet'then
                    for j=0,3 do local yy=y+h*.26+j*h*.14;love.graphics.line(x+2,yy,x+8,yy+7,x+2,yy+14);love.graphics.line(x+w-2,yy,x+w-8,yy+7,x+w-2,yy+14)end
                elseif p.recipe=='interweave'then
                    for side=0,1 do local xx=x+side*w;for j=0,3 do local yy=y+h*.2+j*h*.16;local shift=s.distortion~=false and(side==0 and 4 or-4)*math.sin(t+j)or 0;love.graphics.line(xx,yy,xx+shift,yy+h*.12)end end
                elseif p.recipe=='reform'or p.recipe=='electric'then
                    local yy=y+h*(.22+.55*((t*.45)%1));love.graphics.line(x-2,yy,x+3,yy-5,x+7,yy+2);love.graphics.line(x+w-7,yy+3,x+w-2,yy-5,x+w+2,yy)
                elseif p.recipe=='phase'then
                    for j=0,3 do local yy=y+h*.18+j*h*.19;love.graphics.line(x-2,yy,x+3,yy+h*.1);love.graphics.line(x+w-3,yy,x+w+2,yy+h*.1)end
                elseif p.recipe=='time'or p.recipe=='toll'then
                    love.graphics.arc('line','open',x+w-15,y+15,13,t,t+math.pi*.8,16)
                elseif p.recipe=='overflow'then
                    love.graphics.line(x+w*.27,y+h+1,x+w*.5,y+h+4,x+w*.73,y+h+1)
                    if card.attacking and s.particles~=false and(r.ambientParticleCount or 0)<48 then
                        for j=1,2 do local a=(clock*.7+j*.3)%1;tint(c,alpha*(1-a));love.graphics.circle('fill',x+w*.5+(j==1 and-1 or 1)*a*w*.24,y+h+3+a*7,1.2)end
                        r.ambientParticleCount=(r.ambientParticleCount or 0)+2
                    end
                else
                    -- Other named compositions use a restrained traveling edge.
                    local yy=y+h*.15+((t*.3)%1)*h*.65;love.graphics.line(x-2,yy,x-2,yy+math.min(22,h*.14))
                end
            end
        end
    end
    love.graphics.pop()
end
function FX.newDirector()
    return{events={},pool={},seen={},seenOrder={},pending={},pendingBatches={},clock=0,maxEffects=64,maxTrails=32,maxParticles=256,
        stats={accepted=0,dropped=0,pooled=0,maxActive=0,duplicate=0,unknownSemantics=0},identity=nil}
end
local function recycle(d,e)
    for key in pairs(e)do e[key]=nil end
    if#d.pool<d.maxEffects then d.pool[#d.pool+1]=e end
end
function FX.reset(d,identity)
    for i=#d.events,1,-1 do recycle(d,d.events[i]);d.events[i]=nil end
    for i=#d.pending,1,-1 do recycle(d,d.pending[i])end
    d.seen={};d.seenOrder={};d.pending={};d.pendingBatches={};d.major=nil;d.identity=identity;d.revision=nil;d.initialized=false
end
local function remember(d,key)
    if not key then return false end
    if d.seen[key]then d.stats.duplicate=d.stats.duplicate+1;return false end
    d.seen[key]=true;d.seenOrder[#d.seenOrder+1]=key
    if#d.seenOrder>512 then d.seen[table.remove(d.seenOrder,1)]=nil end
    return true
end
local operations={DESTROYED_PERMANENT='destroy',SACRIFICED_PERMANENT='sacrifice',TURNED_FACE_UP='face_up',TRANSFORMED='transform',TAPPED='tap',UNTAPPED='untap',SPELL_COUNTERED='counter',COUNTERED='counter',MERGED='merge',
    SPELL_CAST='cast',ACTIVATED_ABILITY='activation',TRIGGERED_ABILITY='trigger',DREW_CARD='draw',DISCARDED_CARD='discard',COUNTER_ADDED='counter_change',COUNTER_REMOVED='counter_change',ATTACHED='attachment',UNATTACHED='attachment',ATTACKER_DECLARED='attack',BLOCKER_DECLARED='block',GAINED_LIFE='life_gain',LOST_LIFE='life_loss'}
function FX.operation(event)
    if type(event.operation)=='string'then
        local op=FX.normalize(event.operation)
        if op=='enter_battlefield'then return'entry'end
        if op=='return_to_hand'then return'return'end
        if op=='mana_generated'then return'mana_added'end
        if op=='resolved'then return(event.successful==true or event.success==true)and'resolve'or nil end
        if op=='resolve'then return(event.successful==true or event.success==true)and'resolve'or'resolving'end
        if op=='ability'then return operations[event.nativeType]end
        if op~='zone'then return op end
    end
    if operations[event.nativeType]then return operations[event.nativeType]end
    if event.type=='zone'then
        if event.toZone=='EXILED'or event.toZone=='EXILE'then return'exile'end
        if event.toZone=='BATTLEFIELD'and event.fromZone~='BATTLEFIELD'then return'entry'end
        if event.toZone=='HAND'then return'return'end
        if event.toZone=='GRAVEYARD'then return'departure'end
    end
    if event.type=='damage'then return'damage'end
    if event.type=='impact'and event.entry==true then return'entry'end
    if event.type=='resolve'and event.success==true then return'resolve'end
    return event.type=='step'and'step'or nil
end
local boardOperationPriority={destroy=8,sacrifice=8,exile=7,['return']=6,tap=5,damage=4,entry=2,departure=1}
local function eventProfile(e,card,operation)
    if e.castMode and profiles[FX.normalize(e.castMode)]then return FX.profile(e.castMode)end
    local mechanics=e.mechanic and{e.mechanic}or e.mechanics or{}
    if mechanics[1]then return FX.profile(mechanics[1])end
    -- These are accents on a confirmed event by a currently keyworded native
    -- actor, never a claim that its keyword granted permission or caused damage.
    local contextual=operation=='attack'and{haste=true}or operation=='block'and{reach=true}
        or operation=='damage'and e.combat==true and(tonumber(e.amount)or 0)>0 and{trample=true,first_strike=true,double_strike=true,lifelink=true}
    if contextual then for _,p in ipairs(FX.cardProfiles(card))do if contextual[p.id]then return p end end end
end
function FX.queue(d,event,card,impact,origin)
    local operation=FX.operation(event)
    if not operation then d.stats.unknownSemantics=d.stats.unknownSemantics+1;return end
    if operation=='step'then return end
    if#d.events+#d.pending>=d.maxEffects then
        local score=boardOperationPriority[operation]or 0;local candidate,index,lowest
        for _,group in ipairs({d.pending,d.events})do for i,active in ipairs(group)do
            local priority=boardOperationPriority[active.operation]or 0
            if priority<score and(not lowest or priority<lowest)then candidate,index,lowest=group,i,priority end
        end end
        d.stats.dropped=d.stats.dropped+1
        if candidate then recycle(d,table.remove(candidate,index))else return end
    end
    local e=table.remove(d.pool)or{}
    for key in pairs(e)do e[key]=nil end
    e.id=event.id or event.sequence;e.operation=operation;e.sourceId=event.sourceId;e.targetId=event.targetId or event.sourceId
    e.causeSourceId=event.causeSourceId;e.paymentForId=event.paymentForId
    e.playerId=event.playerId;e.controllerId=event.controllerId;e.ownerId=event.ownerId or card and card.ownerId or event.playerId;e.card=card;e.profile=eventProfile(event,card,operation)
    e.stackId=event.stackId or event.stackObjectId;e.abilityId=event.abilityId
    e.fromZone=event.fromZone or origin and origin.fromZone;e.toZone=event.toZone;e.amount=event.amount;e.batchId=event.batchId or event.resolutionId
    e.hidden=card and(card.hidden or card.faceDown)or event.hidden==true;e.commander=not e.hidden and(event.commander==true or impact and impact.commander==true)
    if e.hidden then e.profile=nil end
    e.manaValue=not e.hidden and tonumber(impact and impact.manaValue or event.manaValue)or 0;e.combat=event.combat==true;e.step=event.step
    e.duration=operation=='entry'and(e.commander and .86 or(e.manaValue or 0)>5 and .72 or .38)or(operation=='merge'and .78 or .64)
    e.age=0;e.seed=hash(e.id);d.pending[#d.pending+1]=e;d.stats.accepted=d.stats.accepted+1
end
function FX.observe(d,game,cards,identity,seeking)
    if d.identity~=identity or seeking or(d.revision and(tonumber(game.revision)or 0)<d.revision)then FX.reset(d,identity)end
    local initial=not d.initialized
    local prompt=type(game.prompt)=='table'and game.prompt or nil
    local promptId=prompt and prompt.id
    if not initial and promptId and promptId~=d.promptId then
        -- The next native decision is immediate. Shorten decoration rather
        -- than making a target wait for its card's visual landing callback.
        for _,effect in ipairs(d.events)do effect.age=math.max(effect.age,effect.duration*.82)end
        if d.major then d.major.age=math.max(d.major.age,d.major.duration*.82)end
    end
    d.promptId=promptId
    local entries,impacts={},{}
    for _,event in ipairs(list(game.animationEvents))do
        local target=event.targetId or event.sourceId
        if target and event.type=='zone'and event.toZone=='BATTLEFIELD'and event.fromZone~='BATTLEFIELD'then entries[target]=true end
        if target and event.type=='impact'and(event.entry==true or event.operation=='entry')then impacts[target]=event end
    end
    local castOrigins={}
    for _,event in ipairs(list(game.animationEvents))do
        if event.type=='zone'and event.toZone=='STACK'then
            if event.targetId then castOrigins[event.targetId]=event end
            if event.sourceId then castOrigins[event.sourceId]=event end
        end
        local key=event.id or event.sequence
        if remember(d,key)and not initial then
            local op=FX.operation(event)
            local material=op=='entry'or op=='destroy'or op=='sacrifice'or op=='exile'or op=='departure'or op=='return'or op=='draw'or op=='discard'or op=='mill'or op=='face_up'or op=='merge'
            local sourceCard=cards[event.causeSourceId]or cards[event.sourceId]
            local card=material and(cards[event.targetId]or sourceCard)or sourceCard or cards[event.targetId]
            local target=event.targetId or event.sourceId
            local batchId=event.batchId or event.resolutionId
            local boardAffected=boardOperationPriority[op]and(op~='departure'and op~='exile'and op~='return'or event.fromZone=='BATTLEFIELD')
            if type(batchId)=='string'and type(target)=='string'and boardAffected then
                local batch=d.pendingBatches[batchId]
                if not batch then batch={id=batchId,operations={},targets={},count=0};d.pendingBatches[batchId]=batch end
                local group=batch.operations[op]or{count=0,targets={}};batch.operations[op]=group
                if not group.targets[target]then group.targets[target]=true;group.count=group.count+1 end
                if not batch.targets[target]then batch.targets[target]=true;batch.count=batch.count+1 end
            end
            -- A native zone entry and its post-resolution impact enrich one
            -- card arrival, rather than creating a duplicate rise/settle.
            if not(event.type=='impact'and target and entries[target])then FX.queue(d,event,card,impacts[target],op=='cast'and(castOrigins[event.causeSourceId]or castOrigins[event.sourceId]))end
        end
    end
    d.initialized=true;d.revision=tonumber(game.revision)or d.revision
end
function FX.update(d,dt,settings)
    d.clock=d.clock+dt
    local speed=settings.presentationPacing=='Fast'and 1.65 or settings.presentationPacing=='Minimal'and 4 or 1
    for i=#d.events,1,-1 do
        local e=d.events[i];e.age=e.age+math.max(0,dt)*speed
        if e.age>e.duration then
            if d.major==e then d.major=nil end
            table.remove(d.events,i);recycle(d,e);d.stats.pooled=d.stats.pooled+1
        end
    end
    if d.major then d.major.age=d.major.age+math.max(0,dt)*speed;if d.major.age>d.major.duration then d.major=nil end end
end
local function center(box)return box and{x=box.x+box.w/2,y=box.y+box.h/2}end
local function anchorPoint(anchor,key)return center(key and anchor(key))end
function FX.flush(d,anchor,previous,playerRects,zoneRects,previousZoneRects,stackRows,stack)
    local batches={}
    local function zone(rects,player,name)
        if not rects or type(player)~='string'or type(name)~='string'then return nil end
        local key=tostring(name):lower();if key=='exiled'then key='exile'end
        return(rects[player]and(rects[player][key]or rects[player][tostring(name):upper()]))or rects[player..':'..tostring(name):upper()]
    end
    local function stackBox(e)
        if not stackRows then return nil end
        local row=stackRows[e.stackId or e.abilityId]or stackRows[e.sourceId]
        if not row then for _,item in ipairs(list(stack))do
            if(item.sourceId==(e.paymentForId or e.causeSourceId or e.sourceId)or item.id==e.sourceId)and(e.operation~='cast'or item.kind=='spell'or item.kind==nil)then row=stackRows[item.id];if row then break end end
        end end
        if row and row.visible~=false then return row.box or row end
    end
    for _,e in ipairs(d.pending)do
        local old=previous and previous[e.targetId]
        e.from=anchorPoint(anchor,e.causeSourceId or e.sourceId)or anchorPoint(anchor,e.sourceId)or(old and center(old))
        local target=anchor(e.targetId)or(old and old)
        e.box=target;e.to=target and center(target)or anchorPoint(anchor,e.playerId or e.controllerId)
        local sourceZone=zone(previousZoneRects,e.ownerId,e.fromZone)or zone(zoneRects,e.ownerId,e.fromZone)
        local targetZone=zone(zoneRects,e.ownerId,e.toZone)
        local sourceCard=previous and(previous[e.causeSourceId]or previous[e.sourceId]or previous[e.targetId])
        if e.operation=='entry'then
            e.from=center(sourceCard or sourceZone)or e.from
        elseif e.operation=='cast'then
            local destination=stackBox(e)
            e.from=center(sourceCard or sourceZone)or e.from;e.to=center(destination)or e.to;e.box=destination or e.box
        elseif e.operation=='activation'or e.operation=='trigger'then
            local destination=stackBox(e)
            if destination then e.to=center(destination)end
        elseif e.operation=='attack'then
            e.box=anchor(e.sourceId);e.to=center(e.box)or e.from
        elseif e.operation=='draw'or e.operation=='discard'or e.operation=='mill'or e.operation=='return'then
            e.from=center(old or sourceZone)or e.from;e.to=center(target or targetZone)or e.to
            if e.profile and e.profile.id=='jump_start'and e.operation=='discard'then e.to=center(stackBox(e))or anchorPoint(anchor,e.sourceId)or e.to end
        elseif e.profile and e.profile.id=='extort'and e.operation=='life_loss'then
            local recipient=anchorPoint(anchor,e.playerId or e.targetId)
            if recipient then e.to=e.from;e.from=recipient end
        elseif e.profile and(e.profile.id=='convoke'or e.profile.id=='improvise'or e.profile.id=='crew'or e.profile.id=='saddle')and e.operation=='tap'then
            local contributor=e.to;e.to=center(stackBox(e))or e.from;e.from=contributor
        end
        if e.from or e.to then
            if e.operation=='entry'and e.box then e.intensity=e.commander and 1.1 or(e.manaValue or 0)>5 and .85 or .35 end
            if e.batchId then
                local batch=batches[e.batchId]or{count=0,operation=e.operation,targets={}};batches[e.batchId]=batch
                if not batch.targets[e.targetId]then batch.targets[e.targetId]=true;batch.count=batch.count+1 end
            end
            -- Only bounded trails are active; all authoritative state remains.
            local trail=e.operation=='draw'or e.operation=='cast'or e.operation=='return'or e.operation=='discard'or e.operation=='mill'
            local count=0;if trail then for _,active in ipairs(d.events)do if active.trail then count=count+1 end end end
            if not trail or count<d.maxTrails then e.trail=trail;d.events[#d.events+1]=e else recycle(d,e);d.stats.dropped=d.stats.dropped+1 end
        else recycle(d,e)end
    end
    local winner
    for key,batch in pairs(d.pendingBatches)do if batch.count>=5 and(not winner or batch.count>winner.count)then winner=batch end end
    if winner and not d.major then
        local chosen,most=nil,-1
        for op,group in pairs(winner.operations)do
            local score=group.count*10+(boardOperationPriority[op]or 0)
            if score>most then chosen,most=op,score end
        end
        d.major={id=winner.id,operation=chosen,age=0,duration=.9,count=winner.count}
    elseif not winner then for key,batch in pairs(batches)do
        if batch.count>=5 and not d.major then d.major={id=key,operation=batch.operation,age=0,duration=.9,count=batch.count}end
    end
    end
    d.pending={};d.pendingBatches={};d.stats.maxActive=math.max(d.stats.maxActive,#d.events)
end
function FX.offset(d,card,settings)
    if settings.animations==false or settings.reducedMotion or settings.presentationPacing=='Minimal'then return 0,0,0 end
    local dx,dy,angle=0,0,0
    for _,e in ipairs(d.events)do if e.targetId==card.id then
        local t=clamp(e.age/e.duration,0,1)
        if e.operation=='entry'then
            local hold=t<.20 and t/.20 or 1;local fall=t<.20 and .7*hold or t<.50 and .7*(1-((t-.20)/.30)^2)or-.12*math.sin((t-.50)/.50*math.pi)*math.exp(-(t-.50)*5)
            dy=dy-fall*math.min(44,((e.intensity or .35)*44));angle=angle+math.sin(t*math.pi)*.018
        elseif e.operation=='merge'then dx=dx+math.sin(t*tau)*(1-t)*6;angle=angle+math.sin(t*math.pi)*.025
        elseif e.operation=='face_up'or e.operation=='transform'then angle=angle+math.sin(t*math.pi)*.035
        end
    end end
    return clamp(dx,-12,12),clamp(dy,-44,12),clamp(angle,-.055,.055)
end
local function within(box,viewport)
    return not viewport or(box.x+box.w>=viewport.x and box.y+box.h>=viewport.y and box.x<=viewport.x+viewport.w and box.y<=viewport.y+viewport.h)
end
local function segment(a,b,t,offset)
    local x=a.x+(b.x-a.x)*t;local y=a.y+(b.y-a.y)*t-math.sin(t*math.pi)*(offset or 25);return x,y
end
local materialShader
local function materialEdge(r,box,c,alpha,progress,mode)
    if not r.assets or not r.assets.surfaces then return end
    local manifest=require('assets.kenney.runtime.manifest')
    local image=r.assets.surfaces:load((manifest.surfaces or{}).noise)
    if not image then return end
    if not materialShader then
        materialShader=love.graphics.newShader([[
            extern number progress;
            extern number recipe;
            vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
                number noise=Texel(texture,uv*vec2(2.0,2.0)).r;
                number plane=mix(noise,uv.x+uv.y*0.18,step(0.5,recipe));
                number body=smoothstep(progress-0.06,progress+0.04,plane);
                number edge=(1.0-smoothstep(0.01,0.10,abs(plane-progress)))*0.75;
                return vec4(color.rgb+edge*0.23,color.a*(body*0.45+edge));
            }
        ]])
    end
    love.graphics.push('all');love.graphics.setShader(materialShader);materialShader:send('progress',progress);materialShader:send('recipe',mode or 0);tint(c,alpha)
    local edge=math.max(3,math.min(9,box.w*.065));local iw,ih=image:getDimensions()
    -- Material work is confined to the outer frame. Names/costs/stats and
    -- the full scanned illustration are never warped or alpha-discarded.
    love.graphics.draw(image,box.x,box.y,0,box.w/iw,edge/ih)
    love.graphics.draw(image,box.x,box.y+box.h-edge,0,box.w/iw,edge/ih)
    love.graphics.draw(image,box.x,box.y+edge,0,edge/iw,(box.h-edge*2)/ih)
    love.graphics.draw(image,box.x+box.w-edge,box.y+edge,0,edge/iw,(box.h-edge*2)/ih)
    love.graphics.pop()
end
function FX.draw(d,r)
    local settings,intensity,moving=FX.settings(r);if intensity<=0 then return end
    local primitives=math.min(d.maxParticles,(r.ambientParticleCount or 0)+#((r.assets or{}).particles or{}))
    love.graphics.push('all')
    for _,e in ipairs(d.events)do
        local b=e.box;local at=e.to or e.from;local raw=clamp(e.age/e.duration,0,1);local t=moving and raw or .5;local alpha=(1-raw)^1.4*intensity
        if at and(not b or within(b,r.tableLayout and r.tableLayout.viewport))then
            local c=FX.color(e.card);local radius=b and math.min(b.w,b.h)*.45 or 28
            tint(c,alpha);love.graphics.setLineWidth(1.5)
            local op=e.operation
            if b and moving and settings.distortion~=false and(op=='destroy'or op=='exile'or op=='merge'or(op=='cast'and e.profile and(e.profile.id=='flashback'or e.profile.id=='jump_start')))then
                materialEdge(r,b,c,alpha*.65,op=='cast'and 1-t or t,op=='exile'and 1 or 0)
            end
            if op=='entry'then
                if t>.4 then
                    local impact=(t-.4)/.6;drawSurface(r,'halo',at.x-radius*(1+impact),at.y-radius*.38*(1+impact),radius*2*(1+impact),radius*.76*(1+impact),c,alpha*(e.intensity or .35))
                    love.graphics.ellipse('line',at.x,at.y+radius*.7,radius*(.45+impact*.85),radius*(.12+impact*.2),32)
                end
            elseif op=='destroy'then
                if settings.particles~=false then
                    for i=1,math.min(9,d.maxParticles-primitives)do local a=(e.seed%7+i*tau/9);local spread=radius*(.3+t*.9);local x,y=at.x+math.cos(a)*spread,at.y+math.sin(a)*spread;love.graphics.polygon('line',x,y,x+6*(1-t),y+2,x+2,y+10*(1-t));primitives=primitives+1 end
                end
            elseif op=='sacrifice'then
                ring(at.x,at.y,radius*(1-t*.75),.22,t*.8);for i=1,5 do local a=i*tau/5;love.graphics.line(at.x+math.cos(a)*radius*(1-t),at.y+math.sin(a)*radius*(1-t),at.x,at.y-radius*t*.4)end
            elseif op=='exile'then
                love.graphics.rectangle('line',at.x-radius*(1-t*.75),at.y-radius,radius*2*(1-t*.75),radius*2,2,2)
                for i=1,4 do local yy=at.y-radius+i*radius*.4;love.graphics.line(at.x-radius,yy,at.x+radius,yy)end
            elseif op=='departure'then
                -- Destination-only knowledge never becomes destruction/sacrifice.
                love.graphics.arc('line','open',at.x,at.y+radius*.2,radius*(1-t*.5),0,math.pi,24)
            elseif op=='merge'then
                for i=-1,1,2 do local shift=radius*.7*(1-t);love.graphics.rectangle('line',at.x-radius*.55+i*shift,at.y-radius*.65,radius*1.1,radius*1.4,4,4)end
                if settings.distortion~=false then drawSurface(r,'noise',at.x-radius*.7,at.y-radius*.8,radius*1.4,radius*1.6,c,alpha*.12)end
            elseif op=='face_up'or op=='transform'then
                local spread=radius*(.15+.85*math.abs(math.cos(t*math.pi)));love.graphics.polygon('line',at.x-spread,at.y-radius,at.x,at.y-radius*.7,at.x+spread,at.y-radius,at.x+spread,at.y+radius,at.x-spread,at.y+radius)
            elseif op=='life_gain'or op=='life_loss'then
                if e.profile and(e.profile.id=='extort'or e.profile.id=='lifelink')and e.from and e.to and moving and settings.particles~=false then
                    for j=0,math.min(2,d.maxParticles-primitives-1)do local a=clamp(t-j*.08,0,1);local x,y=segment(e.from,e.to,a,18+j*6);love.graphics.circle('fill',x,y,2-j*.4);primitives=primitives+1 end
                end
            elseif op=='activation'or op=='trigger'or op=='counter_change'or op=='attachment'or op=='mana_spent'or op=='mana_added'or op=='resolving'then
                local glyph=e.profile or(op=='counter_change'and{glyph='counter_chip'}or op=='attachment'and profiles.equip or{glyph='rise'})
                FX.glyph(glyph,at.x-radius*.4,at.y-radius*.4,radius*.8,t)
                if e.profile and e.profile.id=='extort'then ring(at.x,at.y,radius*.75,.3,t*.4)end
                if op=='trigger'and e.profile and(e.profile.id=='evoke'or e.profile.id=='extort'or e.profile.id=='ward')and e.from and e.to and moving then
                    love.graphics.setLineWidth(1);love.graphics.line(e.from.x,e.from.y,e.to.x,e.to.y)
                end
            elseif op=='block'and e.profile and e.profile.id=='reach'then
                local intercept=e.from or at
                FX.glyph(profiles.reach,intercept.x-radius*.6,intercept.y-radius*.6,radius*1.2,t)
            elseif op=='attack'then
                if e.profile and e.profile.id=='haste'then love.graphics.line(at.x-radius,at.y+6,at.x-radius*.2,at.y,at.x+radius*.7,at.y-4)end
            elseif op=='return'or op=='draw'or op=='cast'or op=='discard'or op=='mill'then
                if e.from and e.to and moving then
                    local lx,ly=e.from.x,e.from.y;for j=1,10 do local x,y=segment(e.from,e.to,j/10,op=='mill'and-20 or 30);love.graphics.line(lx,ly,x,y);lx,ly=x,y end
                    local x,y=segment(e.from,e.to,t,op=='mill'and-20 or 30);FX.glyph(e.profile or{glyph='card'},x-9,y-9,18,t)
                    if e.profile and e.profile.id=='flashback'and settings.particles~=false then
                        for i=1,math.min(6,d.maxParticles-primitives)do local a=i*tau/6;local distance=(1-t)*16;love.graphics.rectangle('line',x+math.cos(a)*distance,y+math.sin(a)*distance,3,5);primitives=primitives+1 end
                    elseif e.profile and e.profile.id=='jump_start'then
                        local lx,ly=e.from.x,e.from.y
                        for j=1,8 do local px,py=segment(e.from,e.to,j/8,24);local wiggle=math.sin(j*2.8+t*12)*5*(1-t);love.graphics.line(lx,ly,px,py+wiggle);lx,ly=px,py+wiggle end
                    elseif e.profile and e.profile.id=='evoke'then
                        for j=1,2 do love.graphics.rectangle('line',x-10-j*3,y-15+j*3,20,30,2,2)end
                    end
                else ring(at.x,at.y,radius*.55,.35,t)end
            elseif op=='counter'then
                for i=1,3 do local yy=at.y-radius*.5+i*radius*.25;love.graphics.line(at.x-radius,yy,at.x-radius*.2,yy-5,at.x+radius*.2,yy+4,at.x+radius,yy)end
            elseif op=='tap'or op=='untap'then
                love.graphics.arc('line','open',at.x,at.y,radius*.8,(op=='tap'and 0 or math.pi/2),math.pi*1.5,24)
                if e.profile and(e.profile.id=='convoke'or e.profile.id=='improvise'or e.profile.id=='crew'or e.profile.id=='saddle')and e.from and e.to and moving then
                    local x,y=segment(e.from,e.to,t,16)
                    love.graphics.line(e.from.x,e.from.y,x,y);FX.glyph(e.profile,x-7,y-7,14,t)
                end
            elseif op=='damage'then
                local p=e.profile
                if p and(p.id=='trample'or p.id=='first_strike'or p.id=='double_strike'or p.id=='reach'or p.id=='lifelink')then
                    if p.id=='trample'then love.graphics.line(at.x-radius,at.y,at.x,at.y-radius*.5,at.x+radius,at.y)
                    elseif p.id=='reach'then FX.glyph(profiles.reach,at.x-radius*.5,at.y-radius*.5,radius,t)
                    elseif p.id=='lifelink'and e.from then love.graphics.arc('line','open',at.x,at.y,radius*.8,t,t+math.pi,24)
                    else FX.glyph(p,at.x-radius*.65,at.y-radius*.65,radius*1.3,t)end
                end
            elseif e.profile and e.profile.coverage~='generic'then
                FX.glyph(e.profile,at.x-radius*.5,at.y-radius*.5,radius,t)
            end
        end
    end
    local major=d.major
    if major then
        local t=clamp(major.age/major.duration,0,1)
        if t>=1 then d.major=nil
        elseif moving and r.tableLayout then
            local v=r.tableLayout.viewport;local y=v.y+v.h*t
            local c=major.operation=='exile'and{.66,.77,.92}or major.operation=='sacrifice'and{.72,.59,.79}or{.83,.71,.49}
            tint(c,(1-t)*intensity*.36);love.graphics.setLineWidth(2)
            if major.operation=='destroy'then
                for i=0,12 do local x=v.x+i*v.w/12;love.graphics.line(x,y,x+v.w/28,y+math.sin(i*2.3)*16,x+v.w/16,y+24)end
            elseif major.operation=='exile'then
                love.graphics.line(v.x+8,y,v.x+v.w-8,y)
                for i=0,8 do local x=v.x+i*v.w/8;love.graphics.line(x,y-8,x+v.w/18,y-8)end
            elseif major.operation=='sacrifice'then
                for i=1,8 do local x=v.x+i*v.w/9;ring(x,y,18*(1-t*.5),.25,t)end
            elseif major.operation=='return'then
                for i=0,12 do local x=v.x+i*v.w/12;local nextX=x+v.w/12;love.graphics.line(x,y+math.sin(i*.8)*9,nextX,y+math.sin((i+1)*.8)*9)end
            elseif major.operation=='tap'then
                for i=1,12 do local x=v.x+i*v.w/13;love.graphics.polygon('line',x,y-6,x+5,y,x,y+6,x-5,y)end
            elseif major.operation=='damage'then
                love.graphics.setLineWidth(4);love.graphics.line(v.x+8,y,v.x+v.w-8,y)
            else love.graphics.line(v.x+8,y,v.x+v.w-8,y)end
            if r.text then r:text(tostring(major.count)..' affected',v.x+10,math.min(v.y+v.h-24,y+10),13,c,120,'left')end
        end
    end
    love.graphics.pop();d.stats.drawPrimitives=primitives
end
function FX.coverage(observed)
    local report={explicit={},composed={},generic={},unsupported={}}
    for _,value in ipairs(observed or{})do local p=FX.profile(value);report[p.coverage][#report[p.coverage]+1]={id=p.id,label=p.label,glyph=p.glyph,recipe=p.recipe,category=p.category}end
    return report
end
return FX
