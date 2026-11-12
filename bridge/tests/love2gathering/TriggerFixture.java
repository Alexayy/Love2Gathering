package love2gathering;

import com.google.gson.*;
import mage.cards.Card;
import mage.constants.*;
import mage.game.PutToBattlefieldInfo;
import mage.game.permanent.Permanent;
import mage.game.stack.StackObject;
import mage.game.turn.PreCombatMainPhase;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.stream.Collectors;

/** Deterministic real-engine fixture: only initial zone setup uses XMage's test helper. */
public final class TriggerFixture {
    static final List<Card> NONE=Collections.emptyList();
    static Card card(String name) {
        JsonObject d=new JsonObject();
        d.add("main",JsonParser.parseString("[{\"name\":"+EngineBridge.JSON.toJson(name)+",\"count\":1}]"));
        return EngineBridge.deck(d).getCards().iterator().next();
    }
    static void require(boolean value,String message) { if(!value) throw new AssertionError(message); }
    static EngineBridge.Session session() {
        JsonObject body=JsonParser.parseString("{\"format\":\"Modern\",\"recordingPort\":0,\"deck\":{\"main\":[{\"name\":\"Plains\",\"count\":60}]},\"botDeck\":{\"main\":[{\"name\":\"Plains\",\"count\":60}]}}").getAsJsonObject();
        EngineBridge.Session s=new EngineBridge.Session(body);
        s.game.setStartingPlayerId(s.human.getId());
        s.game.getState().setActivePlayerId(s.human.getId());
        s.game.getState().setPriorityPlayerId(s.human.getId());
        s.game.getTurn().setPhase(new PreCombatMainPhase());
        s.human.updateRange(s.game); s.bot.updateRange(s.game);
        return s;
    }
    static Map<String,Object> test(boolean manual,boolean reverse) throws Exception {
        EngineBridge.Session s=session();
        Card warden=card("Soul Warden"),orator=card("Impassioned Orator"),pridemate=card("Ajani's Pridemate");
        s.game.cheat(s.human.getId(),NONE,NONE,Arrays.asList(new PutToBattlefieldInfo(warden,false),new PutToBattlefieldInfo(orator,false),new PutToBattlefieldInfo(pridemate,false)),NONE,NONE,NONE);
        s.game.checkStateAndTriggered();
        s.game.getStack().clear();
        s.game.getState().clearTriggeredAbilities();
        require(s.human.getLife()==20,"Fixture setup must leave life unchanged");
        s.manualTriggers=manual;
        Card bear=card("Grizzly Bears");
        s.game.loadCards(Collections.singleton(bear),s.human.getId());
        bear.setZone(Zone.OUTSIDE,s.game);
        require(bear.putOntoBattlefield(s.game,Zone.OUTSIDE,null,s.human.getId()),"Grizzly Bears must really enter the battlefield");
        ExecutorService gameExecutor=Executors.newSingleThreadExecutor(r->new Thread(r,"GAME trigger fixture"));
        try {
            Future<?> placing=gameExecutor.submit(()->s.game.checkStateAndTriggered());
            UUID desiredFirst=reverse ? orator.getId() : warden.getId();
            if(manual) {
                long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
                while((s.prompt==null || !"order".equals(s.prompt.get("type"))) && System.nanoTime()<deadline) Thread.sleep(5);
                require(s.prompt!=null && "order".equals(s.prompt.get("type")),"Expected simultaneous trigger order prompt");
                @SuppressWarnings("unchecked") List<Map<String,Object>> choices=(List<Map<String,Object>>)s.prompt.get("choices");
                require(choices.size()==2,"Both independently generated triggers must appear");
                List<String> order=choices.stream().sorted(Comparator.comparing(c->!desiredFirst.toString().equals(c.get("sourceId")))).map(c->c.get("id").toString()).collect(Collectors.toList());
                JsonObject answer=new JsonObject(); answer.addProperty("promptId",((Number)s.prompt.get("id")).longValue());answer.addProperty("type","order");answer.add("value",EngineBridge.JSON.toJsonTree(order));
                s.action(answer);
            }
            placing.get(15,TimeUnit.SECONDS);
            require(s.game.getStack().size()==2,"XMage must put two real triggers onto the stack");
            if(manual) require(s.game.getStack().peek().getSourceId().equals(desiredFirst),"Leftmost trigger must be top of stack and resolve first");
            else require(s.prompt==null || !"order".equals(s.prompt.get("type")),"Automatic mode must not ask for ordering");
            List<String> resolved=new ArrayList<>();
            int guard=0;
            while(!s.game.getStack().isEmpty() && guard++<12) {
                StackObject top=s.game.getStack().peek();
                resolved.add(s.game.getObject(top.getSourceId()).getName());
                s.game.getStack().resolve(s.game);
                s.game.checkStateAndTriggered();
            }
            require(s.game.getStack().isEmpty(),"Nested trigger stack must finish");
            require(s.human.getLife()==22,"Both gain-life effects must resolve automatically");
            Permanent p=s.game.getPermanent(pridemate.getId());
            require(p.getCounters(s.game).getCount(mage.counters.CounterType.P1P1)==2,"Ajani's Pridemate must get both nested +1/+1 counters automatically");
            return EngineBridge.map("manual",manual,"reverse",reverse,"passed",true,"life",s.human.getLife(),"pridemateCounters",2,"resolutionOrder",resolved);
        } finally { gameExecutor.shutdownNow(); s.stop(); }
    }
    public static void main(String[] args) throws Exception {
        org.apache.log4j.BasicConfigurator.configure();
        org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        Path root=Paths.get(args[0]);
        EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();
        Copier.setLoader(TriggerFixture.class.getClassLoader());
        List<Map<String,Object>> results=Arrays.asList(test(false,false),test(true,false),test(true,true));
        String report=EngineBridge.JSON.toJson(EngineBridge.map("passed",true,"kind","Real XMage deterministic fixture with initial zones injected through Game.cheat; no frontend UI interaction","tests",results));
        Files.writeString(root.resolve("bridge/tests/trigger-report.json"),report+"\n");
        System.out.println(report);
    }
}
