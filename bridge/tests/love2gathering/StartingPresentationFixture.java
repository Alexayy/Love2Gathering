package love2gathering;

import com.google.gson.*;
import mage.Mana;
import mage.cards.Card;
import mage.constants.*;
import mage.game.GameImpl;
import mage.game.stack.Spell;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static love2gathering.EngineBridge.map;

/** Native starts/resolution; only initial zones/mana and deterministic dice are fixtures. */
public final class StartingPresentationFixture {
    static int checks;
    static void check(boolean value,String message){if(!value)throw new AssertionError(message);checks++;}
    static List<Map<String,Object>> seats(){return Arrays.asList(map("playerId","a","seatId","local","seat",0,"name","A"),map("playerId","b","seatId","bot-1","seat",1,"name","B"),map("playerId","c","seatId","bot-2","seat",2,"name","C"));}
    @SuppressWarnings("unchecked") static void rolls(){
        int[] values={6,6,6,6,1,1,3,4,2,2};AtomicInteger cursor=new AtomicInteger();
        Map<String,Object> result=StartingOrder.choose(seats(),"dice",false,()->values[cursor.getAndIncrement()]);
        check("a".equals(result.get("winnerId")),"Highest rerolled total wins");
        List<Map<String,Object>> rounds=(List<Map<String,Object>>)result.get("rounds");
        check(rounds.size()==2&&((List<?>)rounds.get(1).get("rolls")).size()==2,"Only tied leaders reroll");
        check(cursor.get()==10,"Each contender rolls exactly two d6");
        result=StartingOrder.choose(seats(),"bot-1",false,()->{throw new AssertionError("Chosen practice seat must not roll");});
        check("chosen".equals(result.get("mode"))&&"b".equals(result.get("winnerId")),"Practice can choose a real bot seat");
        int[] roomDice={1,1,6,6,2,2};cursor.set(0);
        result=StartingOrder.choose(seats(),"local",true,()->roomDice[cursor.getAndIncrement()]);
        check("2d6".equals(result.get("mode"))&&"b".equals(result.get("winnerId")),"Room ignores requested first seat and rolls on server");
        boolean refused=false;try{StartingOrder.choose(seats(),"unknown",false);}catch(IllegalArgumentException expected){refused=true;}
        check(refused,"Unknown practice seats are rejected");
    }
    static void nativeStart(Path root)throws Exception{
        JsonObject deck=JsonParser.parseString(Files.readString(root.resolve("decks/commander-krenko-goblins.json"))).getAsJsonObject();
        JsonObject body=new JsonObject();body.addProperty("format","Commander");body.addProperty("recordingPort",0);body.addProperty("startingSeatId","bot-1");body.add("deck",deck);body.add("botDeck",deck);
        EngineBridge.Session practice=new EngineBridge.Session(body);
        try{
            check(practice.game.getStartingPlayerId().equals(practice.bot.getId()),"Native game receives selected practice starter");
            Map<String,Object> mat=practice.playmatCard(practice.bot);String name=(String)mat.get("name");
            check(name.equals("Mountain")||name.equals("Krenko, Mob Boss"),"Native mono-red bot playmat is actual commander or red basic");
            check(Boolean.valueOf(name.equals("Mountain")).equals(mat.get("preferFullArt")),"Only a basic-land playmat requests full-art selection");
            check(practice.game.copy().getClass()!=practice.game.getClass(),"Native simulation copies omit presentation callbacks");
        }finally{practice.stop();}
        JsonObject room=new JsonObject();room.addProperty("format","Commander");room.addProperty("startingSeatId","forged-seat");room.addProperty("recordingPort",0);
        JsonArray players=new JsonArray();for(int i=0;i<2;i++){JsonObject seat=new JsonObject();seat.addProperty("seatId","seat-"+i);seat.addProperty("type","human");seat.addProperty("name","Seat "+i);seat.add("deck",deck);players.add(seat);}room.add("seats",players);
        EngineBridge.Session online=new EngineBridge.Session(room,true);
        try{
            check("2d6".equals(online.openingRoll.get("mode")),"Actual authenticated room setup always uses 2d6");
            check(online.game.getStartingPlayerId().toString().equals(online.openingRoll.get("winnerId")),"Native room starter matches public roll winner");
        }finally{online.stop();}
    }
    static Map<String,Object> resolution(String name,int x,boolean commander,boolean counter)throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=NativeViewFixture.executor();
        try{
            java.lang.reflect.Field cursor=GameImpl.class.getDeclaredField("playerList");cursor.setAccessible(true);cursor.set(s.game,s.game.getState().getPlayerList(s.human.getId()));
            Card card=TriggerFixture.card(name);
            s.game.cheat(s.human.getId(),TriggerFixture.NONE,Collections.singletonList(card),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            if(commander)s.human.addCommanderId(card.getId());
            s.human.getManaPool().addMana(Mana.GreenMana(12),s.game,card.getSpellAbility());s.human.getManaPool().addMana(Mana.WhiteMana(12),s.game,card.getSpellAbility());
            Future<Boolean> cast=worker.submit(()->s.human.cast(card.getSpellAbility(),s.game,false,null));
            if(x>=0){
                Map<String,Object> prompt=ActionabilityFixture.waitPrompt(s,-1);
                check(prompt.get("type").equals("amount"),"Native X cast requests its announced amount");
                JsonObject answer=new JsonObject();answer.addProperty("promptId",((Number)prompt.get("id")).longValue());answer.addProperty("type","integer");answer.addProperty("value",x);s.action(answer);
            }
            check(cast.get(15,TimeUnit.SECONDS),"Native cast succeeds for "+name);
            Spell spell=(Spell)s.game.getStack().peek();int nativeValue=spell.getManaValue();
            if(commander){spell.setControllerId(s.bot.getId());check(spell.getControllerId().equals(s.bot.getId()),"Native commander identity survives a changed spell controller");}
            check(s.animationEvents.stream().noneMatch(e->"impact".equals(e.get("type"))),"Casting alone never shakes the board");
            if(counter){spell.counter(null,s.game);check(s.animationEvents.stream().noneMatch(e->"impact".equals(e.get("type"))),"Countering a large spell never produces resolution impact");}
            else{
                java.lang.reflect.Method resolve=GameImpl.class.getDeclaredMethod("resolve");resolve.setAccessible(true);worker.submit(()->{try{resolve.invoke(s.game);}catch(Exception e){throw new RuntimeException(e);}}).get(15,TimeUnit.SECONDS);
                boolean expected=commander||nativeValue>5;Map<String,Object> event=s.animationEvents.stream().filter(e->"impact".equals(e.get("type"))).findFirst().orElse(null);
                check((event!=null)==expected,"Impact follows actual native resolution threshold");
                if(event!=null){check(((Number)event.get("manaValue")).intValue()==nativeValue,"Impact carries stack mana value including X");check(Boolean.valueOf(commander).equals(event.get("commander")),"Impact preserves actual commander identity");}
                check(s.game.getPermanent(card.getId())!=null,"Resolved creature really enters battlefield");
            }
            return map("name",name,"nativeManaValue",nativeValue,"commander",commander,"countered",counter,"passed",true);
        }finally{worker.shutdownNow();s.stop();}
    }
    public static void main(String[] args)throws Exception{
        Path root=Paths.get(args[0]);org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(StartingPresentationFixture.class.getClassLoader());
        rolls();nativeStart(root);
        List<Map<String,Object>> results=Arrays.asList(resolution("Colossal Dreadmaw",-1,false,false),resolution("Grizzly Bears",-1,false,false),resolution("Giada, Font of Hope",-1,true,false),resolution("Endless One",7,false,false),resolution("Endless One",5,false,false),resolution("Colossal Dreadmaw",-1,false,true));
        String report=EngineBridge.JSON.toJson(map("passed",true,"checks",checks,"scope","Native server-owned 2d6/selected starting seats and actual XMage cast/resolve/counter with deterministic initial zones/resources; no frontend gameplay or WAN claim","resolutions",results));
        Files.writeString(root.resolve("bridge/tests/starting-presentation-report.json"),report+"\n");System.out.println(report);
    }
}
