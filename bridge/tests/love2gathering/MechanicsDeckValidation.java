package love2gathering;
import com.google.gson.*;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;

/** Validates generated lists through the normal Session constructor, no cheat zones. */
public final class MechanicsDeckValidation {
    public static void main(String[] args)throws Exception{
        Path root=Paths.get(args[0]),generation=Paths.get(args[1]),out=Paths.get(args[2]);Files.createDirectories(out);
        org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(MechanicsDeckValidation.class.getClassLoader());
        JsonObject data=JsonParser.parseString(Files.readString(generation)).getAsJsonObject();List<Map<String,Object>> results=new ArrayList<>();
        for(JsonElement entry:data.getAsJsonArray("decks")){
            JsonObject description=entry.getAsJsonObject();JsonObject deck=JsonParser.parseString(Files.readString(Paths.get(description.get("path").getAsString()))).getAsJsonObject();
            JsonObject request=new JsonObject();request.addProperty("format",deck.get("format").getAsString());request.addProperty("recordingPort",0);request.add("deck",deck);request.add("botDeck",deck.deepCopy());
            try{
                EngineBridge.Session session=new EngineBridge.Session(request);
                results.add(EngineBridge.map("id",description.get("id").getAsString(),"nativeValidation","accepted","format",session.format,"productionEligible",true));session.stop();
            }catch(IllegalArgumentException ex){results.add(EngineBridge.map("id",description.get("id").getAsString(),"nativeValidation","rejected","productionEligible",false,"error",ex.getMessage(),"scope","fixture-only resources; never start an invalid production list"));}
        }
        Files.writeString(out.resolve("result.json"),EngineBridge.JSON.toJson(EngineBridge.map("status","pass","evidenceType","production_setup_validation","decks",results,"scope","Native format validation only; these games were not started")));
    }
}
