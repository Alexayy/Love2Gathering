package love2gathering;

import mage.game.Game;
import mage.game.combat.CombatGroup;
import mage.game.permanent.Permanent;
import mage.util.MultiAmountMessage;
import java.util.*;
import static love2gathering.EngineBridge.map;

/** Match native combat dialog identities, failing closed for other distributions.
 * The pinned engine supplies labels rather than UUIDs for these amount rows.
 * Exact header AND every row must match its native formatter and live group. */
final class CombatPromptMetadata {
    static Map<String,Object> identify(EngineBridge.Session session,List<MultiAmountMessage> messages,String title,String header){
        Game game=session.game;List<Map<String,Object>> matches=new ArrayList<>();
        boolean attacking="Assign combat damage".equals(title)||"Assign combat damage (with trample)".equals(title);
        boolean blocking="Assign blocker combat damage".equals(title);
        if(!attacking&&!blocking)return null;
        for(CombatGroup group:game.getCombat().getGroups()){
            List<UUID> sources=attacking?group.getAttackers():group.getBlockers();
            List<UUID> targets=attacking?group.getBlockers():group.getAttackers();
            if(sources.isEmpty())continue;
            Permanent source=game.getPermanent(sources.get(0));if(source==null)continue;
            String expected=String.format(attacking?"Assign combat damage among creatures blocking %s, P/T: %d/%d":"Assign combat damage among creatures blocked by %s, P/T: %d/%d",source.getLogName(),source.getPower().getValue(),source.getToughness().getValue());
            if("Assign combat damage (with trample)".equals(title))expected+=" (Unassigned damage tramples through)";
            if(!expected.equals(header))continue;
            List<Permanent> live=new ArrayList<>();for(UUID id:targets){Permanent p=game.getPermanent(id);if(p!=null)live.add(p);}
            if(live.size()!=messages.size())continue;
            boolean exact=true;for(int i=0;i<live.size();i++){
                Permanent p=live.get(i);String label=String.format("%s, P/T: %d/%d",p.getLogName(),p.getPower().getValue(),p.getToughness().getValue());
                if(!label.equals(messages.get(i).message)){exact=false;break;}
            }
            if(!exact)continue;
            List<Map<String,Object>> rows=new ArrayList<>();for(int i=0;i<live.size();i++)rows.add(map("nativeIndex",i+1,"targetId",live.get(i).getId().toString(),"card",session.card(live.get(i))));
            matches.add(map("sourceId",source.getId().toString(),"sourceCard",session.card(source),"rows",rows,"role",attacking?"attacker_damage":"blocker_damage"));
        }
        return matches.size()==1?matches.get(0):null;
    }
}
