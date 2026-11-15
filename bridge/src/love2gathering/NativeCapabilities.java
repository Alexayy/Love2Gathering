package love2gathering;

import com.google.gson.*;
import mage.cards.decks.*;
import mage.util.ClassScanner;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import static love2gathering.EngineBridge.map;

/** Installed implementation inventory, never a card-legality claim. */
final class NativeCapabilities {
    static final String ENGINE_REVISION="d9b266fc981024873ac7ec5f90ee7121a060725e";
    private static Map<String,Class<? extends DeckValidator>> validators;
    private static List<Map<String,Object>> descriptors;
    private static JsonObject registrySource;
    private static Map<String,Object> registry;
    static synchronized List<Map<String,Object>> formats(){
        if(descriptors!=null)return descriptors;
        Map<String,Class<? extends DeckValidator>> found=new TreeMap<>();List<Map<String,Object>> rows=new ArrayList<>();
        for(Class<?> type:ClassScanner.findClasses(NativeCapabilities.class.getClassLoader(),Collections.singletonList("mage.deck"),DeckValidator.class)){
            if(Modifier.isAbstract(type.getModifiers()))continue;
            try{
                DeckValidator validator=(DeckValidator)type.getConstructor().newInstance();String id=type.getSimpleName();
                boolean commander=id.equals("Commander"),limited=id.equals("Limited");
                boolean ordinary=(Constructed.class.isAssignableFrom(type)||id.equals("Freeform")||id.equals("FreeformUnlimited"))&&!id.contains("Commander")&&!id.equals("Brawl")&&!id.equals("TinyLeaders")&&!id.equals("Oathbreaker");
                boolean supported=commander||limited||ordinary;
                Map<String,Object> row=map("id",id,"name",validator.getShortName(),"label",validator.getShortName(),"validatorClass",type.getName(),"minDeckSize",validator.getDeckMinSize(),"sideboardMinSize",validator.getSideboardMinSize(),"minPlayers",2,"maxPlayers",commander?new mage.game.CommanderFreeForAllType().getMaxPlayers():limited?new mage.game.FreeForAllType().getMaxPlayers():new mage.game.TwoPlayerDuelType().getMaxPlayers(),"construction",limited?"limited":commander?"commander":"constructed","supported",supported);
                if(!supported)row.put("reason","Requires a game variant or setup not provided by this bridge");else found.put(id,type.asSubclass(DeckValidator.class));
                rows.add(Collections.unmodifiableMap(row));
            }catch(ReflectiveOperationException|LinkageError invalid){/* An unavailable constructor is not an offered format. */}
        }
        rows.sort(Comparator.comparing(row->String.valueOf(row.get("id"))));validators=Collections.unmodifiableMap(found);descriptors=Collections.unmodifiableList(rows);return descriptors;
    }
    static List<String> supportedFormats(){List<String> ids=new ArrayList<>();for(Map<String,Object> row:formats())if(Boolean.TRUE.equals(row.get("supported")))ids.add(row.get("id").toString());return ids;}
    static DeckValidator validator(String id){
        formats();for(Map.Entry<String,Class<? extends DeckValidator>> entry:validators.entrySet())if(entry.getKey().equalsIgnoreCase(id))try{return entry.getValue().getConstructor().newInstance();}catch(ReflectiveOperationException ex){throw new IllegalArgumentException("Native format is unavailable: "+id,ex);}
        throw new IllegalArgumentException("Unsupported native format or unavailable game type: "+id);
    }
    static synchronized Map<String,Object> cards(){
        if(registry!=null&&registrySource==EngineBridge.cardMap)return registry;
        TreeMap<String,String> installed=new TreeMap<>();ClassLoader loader=NativeCapabilities.class.getClassLoader();
        for(Map.Entry<String,JsonElement> entry:EngineBridge.cardMap.entrySet()){
            JsonObject card=entry.getValue().getAsJsonObject();String className=card.get("class").getAsString();
            if(loader.getResource(className.replace('.','/')+".class")!=null)installed.put(card.get("name").getAsString(),className);
        }
        try{
            MessageDigest hash=MessageDigest.getInstance("SHA-256");for(Map.Entry<String,String> entry:installed.entrySet())hash.update((entry.getKey()+"\0"+entry.getValue()+"\n").getBytes(StandardCharsets.UTF_8));
            String revision=HexFormat.of().formatHex(hash.digest());
            registry=Collections.unmodifiableMap(map("engineRevision",ENGINE_REVISION,"registryRevision",revision,"names",Collections.unmodifiableList(new ArrayList<>(installed.keySet())),"splitNameFallback",true,"legalityChecked",false));registrySource=EngineBridge.cardMap;return registry;
        }catch(java.security.NoSuchAlgorithmException impossible){throw new IllegalStateException(impossible);}
    }
}
