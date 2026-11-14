-- Short display reminders, never a source of legality or game decisions.
-- Sources: https://magic.wizards.com/en/keyword-glossary and the supplied
-- assets/MagicCompRules 20260807.pdf, section 702. Reviewed 2026-11-14.
local Keywords={}
local reminders={
    flying='Blocked only by creatures with flying or reach.',
    reach='Can block creatures with flying.',
    ['first strike']='Deals combat damage in the earlier damage step.',
    ['double strike']='Deals combat damage in both damage steps.',
    deathtouch='Its positive damage to creatures is lethal.',
    lifelink='Its damage also gains its controller that much life.',
    vigilance='Attacking does not tap it.',
    haste='Ignores summoning sickness.',
    menace='Requires at least two blockers.',
    defender='Cannot attack.',
    trample='Can assign excess combat damage beyond its blockers to what it attacks.',
    hexproof='Opponents cannot target it with spells or abilities.',
    shroud='Cannot be targeted by spells or abilities.',
    indestructible='Cannot be destroyed; other removal can still work.',
    flash='Can be cast when an instant could be cast.',
    ward='Opposing targeted spells or abilities are countered unless the ward cost is paid.',
}
local walks={forestwalk='Forest',islandwalk='Island',mountainwalk='Mountain',swampwalk='Swamp',plainswalk='Plains'}
function Keywords.reminder(value)
    local key=value:lower():gsub('^%s+',''):gsub('%s+$','')
    if reminders[key]then return reminders[key]end
    if key:match('^ward[%s—]')then return reminders.ward end
    if walks[key]then return'Cannot be blocked while the defending player controls a '..walks[key]..'.'end
end
function Keywords.annotate(text,enabled)
    if type(text)=='table'then text=table.concat(text,'\n')end
    text=tostring(text or'');if enabled==false then return text end
    local lines={}
    for line in(text..'\n'):gmatch('(.-)\n')do
        if not line:find('(',1,true)then
            local parts,known={},true
            for part in line:gmatch('[^,]+')do
                local reminder=Keywords.reminder(part)
                if not reminder then known=false;break end
                parts[#parts+1]=part:gsub('^%s+','')..' ('..reminder..')'
            end
            if known and#parts>0 then line=table.concat(parts,', ')end
        end
        lines[#lines+1]=line
    end
    return table.concat(lines,'\n')
end
return Keywords
