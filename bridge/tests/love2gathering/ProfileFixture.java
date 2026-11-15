package love2gathering;

import com.google.gson.*;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;

/** Profile data changes presentation only; all life/decks/visibility stay native. */
public final class ProfileFixture {
    static int checks;
    static void require(boolean value,String label){if(!value)throw new AssertionError(label);checks++;}
    static JsonObject profile(String name){return JsonParser.parseString("{\"name\":"+EngineBridge.JSON.toJson(name)+",\"avatar\":{\"oracleId\":\"11111111-1111-4111-8111-111111111111\",\"printingId\":\"22222222-2222-4222-8222-222222222222\",\"face\":1,\"name\":\"Example back\"},\"playmat\":{\"oracleId\":\"33333333-3333-4333-8333-333333333333\",\"printingId\":\"44444444-4444-4444-8444-444444444444\",\"face\":0}}").getAsJsonObject();}
    static JsonObject deck(){return JsonParser.parseString("{\"name\":\"Profile deck\",\"format\":\"Modern\",\"coverCard\":\"Plains\",\"main\":[{\"name\":\"Plains\",\"count\":60}]}").getAsJsonObject();}
    @SuppressWarnings("unchecked") static List<Map<String,Object>> players(EngineBridge.Session s){return(List<Map<String,Object>>)s.snapshot.get("players");}
    public static void main(String[] args)throws Exception{
        org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);Path root=Paths.get(args[0]);
        EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(ProfileFixture.class.getClassLoader());
        JsonObject body=new JsonObject();body.addProperty("format","Modern");body.addProperty("recordingPort",0);body.addProperty("playerName","Legacy");body.add("profile",profile("Čarobnjak"));body.add("deck",deck());body.add("botDeck",deck());
        EngineBridge.Session local=new EngineBridge.Session(body);
        try{
            local.publish();require(local.human.getName().equals("Čarobnjak"),"Profile name initializes actual native human name");
            Map<String,Object> own=players(local).stream().filter(p->Boolean.TRUE.equals(p.get("human"))).findFirst().orElseThrow();JsonObject p=EngineBridge.JSON.toJsonTree(own.get("profile")).getAsJsonObject();
            require(p.getAsJsonObject("avatar").get("face").getAsInt()==1,"Practice snapshot preserves exact avatar face");
            require(p.getAsJsonObject("playmat").get("printingId").getAsString().startsWith("44444444"),"Practice snapshot preserves exact playmat printing");
            require(local.human.getLife()==20&&local.bot.getLife()==20,"Profile never overrides native starting life");
            Map<String,Object> bot=players(local).stream().filter(n->!Boolean.TRUE.equals(n.get("human"))).findFirst().orElseThrow();
            require(EngineBridge.JSON.toJsonTree(bot.get("avatarCard")).getAsJsonObject().get("name").getAsString().equals("Plains"),"Bot uses meaningful native deck cover fallback without fabricated printing UUID");
            require(local.participants().stream().allMatch(n->n.get("profile")!=null),"Replay/public participants retain profile identity");
        }finally{local.stop();}
        JsonArray seats=new JsonArray();for(int i=0;i<2;i++){JsonObject seat=new JsonObject();seat.addProperty("seatId","profile-human-"+i);seat.addProperty("name","Legacy "+i);seat.addProperty("type","human");seat.add("profile",profile("Human "+i));seat.add("deck",deck());seats.add(seat);}
        JsonObject room=new JsonObject();room.addProperty("format","Modern");room.addProperty("recordingPort",0);room.add("seats",seats);EngineBridge.Session game=new EngineBridge.Session(room,true);
        try{game.publishAll();for(EngineBridge.Session view:game.perspectives){require(players(view).size()==2,"Two real human seats are projected");require(players(view).stream().allMatch(p->EngineBridge.JSON.toJsonTree(p.get("profile")).getAsJsonObject().has("playmat")),"Every perspective sees both public playmats");require(view.human.getLife()==20,"Room profile keeps native life");}}
        finally{game.stop();}
        for(String invalid:Arrays.asList("{\"name\":\"X\",\"hp\":99}","{\"name\":\"X\",\"avatar\":{\"url\":\"https://example.com\"}}","{\"name\":42}")){
            boolean rejected=false;try{RoomSeat.profile(JsonParser.parseString(invalid),"Fallback");}catch(IllegalArgumentException ex){rejected=true;}require(rejected,"Untrusted native profile fields are rejected");
        }
        List<RoomSeat> draftSeats=new ArrayList<>();for(int i=0;i<4;i++){JsonObject seat=new JsonObject();seat.addProperty("seatId","draft-profile-"+i);seat.addProperty("name","Drafter"+i);seat.add("profile",profile("Drafter"+i));draftSeats.add(new RoomSeat(seat,i));}
        DraftSession draft=new DraftSession(JsonParser.parseString("{\"profile\":\"booster\",\"sets\":[\"M21\",\"M21\",\"M21\"]}").getAsJsonObject(),draftSeats);
        try{@SuppressWarnings("unchecked")List<Map<String,Object>> pub=(List<Map<String,Object>>)draft.state("draft-profile-0").get("players");require(pub.stream().allMatch(p->p.get("profile")!=null),"Native draft public rows carry bounded card-art profiles");}finally{draft.stop();}
        Map<String,Object> result=EngineBridge.map("passed",true,"checks",checks,"scope","Real native practice/two-human/draft seat projections; profile identity and exact art faces; native life retained; no frontend UI or real catalog lookup");
        Files.writeString(root.resolve("bridge/tests/profile-native-report.json"),EngineBridge.JSON.toJson(result)+"\n");System.out.println(EngineBridge.JSON.toJson(result));
    }
}
