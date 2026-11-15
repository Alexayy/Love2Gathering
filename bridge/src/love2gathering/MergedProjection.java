package love2gathering;

import mage.MageObject;
import mage.cards.Card;
import mage.game.permanent.Permanent;
import mage.game.permanent.PermanentToken;
import java.util.*;

/** Native merge identity only. Components are inspectable metadata, not targets. */
final class MergedProjection {
    static MageObject original(EngineBridge.Session session,Permanent permanent,UUID component){
        if(component.equals(permanent.getId())&&permanent instanceof PermanentToken)
            return ((PermanentToken)permanent).getToken();
        return session.game.getCard(component);
    }
    static MageObject top(EngineBridge.Session session,MageObject object){
        if(!(object instanceof Permanent))return null;
        Permanent permanent=(Permanent)object;
        List<UUID> components=permanent.getMutateForView();
        return permanent.getMutateCount()>0&&!components.isEmpty()?original(session,permanent,components.get(0)):null;
    }
    static Map<String,Object> view(EngineBridge.Session session,Permanent permanent){
        List<UUID> ids=permanent.getMutateForView();
        if(permanent.getMutateCount()==0||ids.isEmpty())return null;
        List<Map<String,Object>> components=new ArrayList<>();
        for(UUID id:ids){
            MageObject original=original(session,permanent,id);
            Map<String,Object> item;
            if(original==null)item=EngineBridge.map("id",id.toString(),"name","Unavailable native component","metadataUnavailable",true);
            else{
                item=new LinkedHashMap<>(session.card(original,true));item.put("id",id.toString());
                if(original instanceof mage.game.permanent.token.Token){
                    item.put("token",true);item.put("isToken",true);item.put("ownerId",EngineBridge.Session.str(permanent.getOwnerId()));
                    String type=original.getCardType(null).stream().map(Object::toString).collect(java.util.stream.Collectors.joining(" "));
                    String subtypes=original.getSubtype(null).stream().map(Object::toString).collect(java.util.stream.Collectors.joining(" "));
                    item.put("printing",EngineBridge.map("name",original.getName(),"power",original.getPower().toString(),"toughness",original.getToughness().toString(),"type_line",type+(subtypes.isEmpty()?"":" — "+subtypes),"colors",EngineBridge.Session.colorNames(original.getColor())));
                }
            }
            item.put("mergeComponent",true);item.put("isTopComponent",id.equals(ids.get(0)));components.add(item);
        }
        return EngineBridge.map("count",permanent.getMutateCount(),"topId",ids.get(0).toString(),"originalObjectId",permanent.getId().toString(),"components",components);
    }
}
