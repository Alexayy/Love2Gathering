package love2gathering;

import com.google.gson.*;
import java.util.*;

/** Bounded presentation metadata; never publishes a deck list or changes a native card. */
final class CardPrintingProjection {
    static String selected(JsonObject deck,String name,String seed) {
        if(deck==null||name==null||!deck.has("printingSelections")||!deck.get("printingSelections").isJsonArray())return null;
        JsonArray selections=deck.getAsJsonArray("printingSelections");if(selections.size()>900)return null;
        List<String> ids=new ArrayList<>();List<Integer> weights=new ArrayList<>();int total=0;
        for(JsonElement element:selections) {
            if(!element.isJsonObject())continue;JsonObject value=element.getAsJsonObject();
            try {
                if(!value.has("name")||!value.get("name").getAsString().equalsIgnoreCase(name)||!value.has("printingId"))continue;
                String id=value.get("printingId").getAsString();if(!id.matches("[A-Za-z0-9_-]{1,100}"))continue;
                if(!value.has("count")||!value.get("count").isJsonPrimitive()||!value.getAsJsonPrimitive("count").isNumber())continue;
                int count=value.get("count").getAsBigDecimal().intValueExact();if(count<1||count>250)continue;
                ids.add(id);weights.add(count);total+=count;
            } catch(RuntimeException ignored) { /* Ignore malformed optional presentation data. */ }
        }
        if(total==0)return null;
        int index=Math.floorMod(Objects.toString(seed,name).hashCode(),total);
        for(int i=0;i<ids.size();i++){index-=weights.get(i);if(index<0)return ids.get(i);}
        return null;
    }
}
