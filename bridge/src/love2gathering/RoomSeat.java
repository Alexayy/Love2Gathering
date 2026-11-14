package love2gathering;

import com.google.gson.*;
import java.util.*;

/** Coordinator-owned seat configuration; seatId remains stable across draft and game pairings. */
final class RoomSeat {
    final String seatId, name;
    final boolean human;
    final JsonObject deck, settings, priority, profile;

    RoomSeat(JsonObject source, int index) {
        seatId = EngineBridge.text(source, "seatId", "seat-" + index);
        String submittedName=EngineBridge.text(source, "name", "Player " + (index + 1));
        profile=profile(source.get("profile"),submittedName);name=profile.get("name").getAsString();
        String type = EngineBridge.text(source, "type", "human");
        if (!type.equals("human") && !type.equals("bot")) throw new IllegalArgumentException("Seat type must be human or bot");
        if (seatId.isBlank() || seatId.length() > 120 || name.isBlank() || name.codePointCount(0,name.length()) > 80) throw new IllegalArgumentException("Invalid seat ID or player name");
        human = type.equals("human");
        deck = source.has("deck") && source.get("deck").isJsonObject() ? source.getAsJsonObject("deck").deepCopy() : new JsonObject();
        settings = source.has("settings") && source.get("settings").isJsonObject() ? source.getAsJsonObject("settings").deepCopy() : new JsonObject();
        priority = source.has("priority") && source.get("priority").isJsonObject() ? source.getAsJsonObject("priority").deepCopy() : new JsonObject();
    }
    static JsonObject profile(JsonElement input,String fallback){
        if(input!=null&&!input.isJsonNull()&&!input.isJsonObject())throw new IllegalArgumentException("Profile must be an object");
        JsonObject raw=input==null||input.isJsonNull()?new JsonObject():input.getAsJsonObject();
        if(raw.toString().length()>4096||!new HashSet<>(Arrays.asList("name","avatar","playmat")).containsAll(raw.keySet()))throw new IllegalArgumentException("Profile supports bounded name, avatar and playmat only");
        if(raw.has("name")&&!raw.get("name").isJsonNull()&&(!raw.get("name").isJsonPrimitive()||!raw.getAsJsonPrimitive("name").isString()))throw new IllegalArgumentException("Profile name must be text");
        String name=EngineBridge.text(raw,"name",fallback).trim();
        if(name.isEmpty()||name.codePointCount(0,name.length())>80||name.chars().anyMatch(c->c<32||c==127))throw new IllegalArgumentException("Choose a name between1 and80 characters");
        JsonObject result=new JsonObject();result.addProperty("name",name);
        for(String slot:Arrays.asList("avatar","playmat")){
            JsonElement value=raw.get(slot);if(value==null||value.isJsonNull()){result.add(slot,JsonNull.INSTANCE);continue;}
            if(!value.isJsonObject())throw new IllegalArgumentException("Artwork must contain card identities");JsonObject ref=value.getAsJsonObject();
            if(!new HashSet<>(Arrays.asList("oracleId","printingId","face","name")).containsAll(ref.keySet()))throw new IllegalArgumentException("Artwork cannot contain URLs or extra fields");
            JsonObject card=new JsonObject();for(String key:Arrays.asList("oracleId","printingId")){
                String id=EngineBridge.text(ref,key,"");if(!id.matches("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"))throw new IllegalArgumentException("Artwork requires exact printing and Oracle UUIDs");
                card.addProperty(key,UUID.fromString(id).toString());
            }
            int face=0;if(ref.has("face")){try{if(!ref.get("face").isJsonPrimitive()||!ref.getAsJsonPrimitive("face").isNumber())throw new ArithmeticException();face=ref.get("face").getAsBigDecimal().intValueExact();}catch(RuntimeException ex){throw new IllegalArgumentException("Artwork face must be an integer0 to9");}}
            if(face<0||face>9)throw new IllegalArgumentException("Artwork face must be between0 and9");card.addProperty("face",face);
            if(ref.has("name")&&!ref.get("name").isJsonNull()){if(!ref.get("name").isJsonPrimitive()||!ref.getAsJsonPrimitive("name").isString())throw new IllegalArgumentException("Artwork name must be text");String label=EngineBridge.text(ref,"name","");if(label.isBlank()||label.codePointCount(0,label.length())>300||label.chars().anyMatch(c->c<32||c==127))throw new IllegalArgumentException("Invalid artwork card name");card.addProperty("name",label);}
            result.add(slot,card);
        }
        return result;
    }
}
