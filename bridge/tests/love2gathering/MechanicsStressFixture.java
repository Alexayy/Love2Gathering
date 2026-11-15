package love2gathering;

import com.google.gson.*;
import mage.cards.Card;
import mage.counters.CounterType;
import mage.game.permanent.Permanent;
import mage.game.permanent.token.Token;
import mage.game.permanent.token.WolfToken;
import mage.util.Copier;
import mage.watchers.Watcher;
import mage.constants.WatcherScope;
import mage.game.Game;
import mage.game.events.GameEvent;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;

/** Native creation/projection/recording measurement, not a production starting position. */
public final class MechanicsStressFixture {
    static final long EVENT_BUDGET=Long.getLong("love2gathering.test.nativeEvents",200000L);
    static final double STEP_SECONDS=Double.parseDouble(System.getProperty("love2gathering.test.stepSeconds","80"));
    static final long FLUSH_MILLIS=Long.getLong("love2gathering.test.flushMillis",8000L);
    static class BudgetReached extends RuntimeException{BudgetReached(String message){super(message);}}
    static Game observed;static final AtomicLong eventCount=new AtomicLong();
    static final Map<String,AtomicLong> eventTypes=new ConcurrentHashMap<>();
    static final class EventCounter extends Watcher{
        EventCounter(){super(WatcherScope.GAME);}
        @Override public void watch(GameEvent event,Game game){if(game!=observed||game.isSimulation()||game.inCheckPlayableState())return;long count=eventCount.incrementAndGet();eventTypes.computeIfAbsent(event.getType().name(),key->new AtomicLong()).incrementAndGet();if(count>EVENT_BUDGET)throw new BudgetReached("Native stress event budget");}
        @Override public EventCounter copy(){return new EventCounter();}
    }
    static long nanos(){return System.nanoTime();}
    static double milliseconds(long started){return (nanos()-started)/1e6;}
    static long bytes(Path root)throws Exception {
        try(var paths=Files.walk(root)){return paths.filter(Files::isRegularFile).mapToLong(p->{try{return Files.size(p);}catch(Exception ex){return 0;}}).sum();}
    }
    public static void main(String[] args)throws Exception {
        if(!Double.isFinite(STEP_SECONDS)||STEP_SECONDS<=0||STEP_SECONDS>Long.MAX_VALUE/1000.0||EVENT_BUDGET<0||FLUSH_MILLIS<1)throw new IllegalArgumentException("Invalid diagnostic step/event/flush budget");
        Path root=Paths.get(args[0]),out=Paths.get(args[2]);Files.createDirectories(out);
        org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(MechanicsStressFixture.class.getClassLoader());
        String id=args[1];boolean varied=id.contains("varied"),split=id.contains("split");
        int count=Integer.parseInt(id.replaceAll("[^0-9]",""));
        if(!Arrays.asList(1,10,100,500,1000,5000).contains(count))throw new IllegalArgumentException("Unplanned stress level");
        JsonObject body=JsonParser.parseString("{\"format\":\"Modern\",\"recordingPort\":0,\"deck\":{\"main\":[{\"name\":\"Plains\",\"count\":60}]},\"botDeck\":{\"main\":[{\"name\":\"Plains\",\"count\":60}]}}").getAsJsonObject();
        String port=System.getenv("LOVE2GATHERING_CATALOG_PORT");if(port!=null&&!port.isEmpty())body.addProperty("recordingPort",Integer.parseInt(port));
        EngineBridge.Session s=new EngineBridge.Session(body);s.game.setStartingPlayerId(s.human.getId());s.game.getState().setActivePlayerId(s.human.getId());s.game.getState().setPriorityPlayerId(s.human.getId());
        s.game.getTurn().setPhase(new mage.game.turn.PreCombatMainPhase());s.human.updateRange(s.game);s.bot.updateRange(s.game);
        java.lang.reflect.Field cursor=mage.game.GameImpl.class.getDeclaredField("playerList");cursor.setAccessible(true);cursor.set(s.game,s.game.getState().getPlayerList(s.human.getId()));
        observed=s.game;s.game.getState().addWatcher(new EventCounter());
        ExecutorService worker=Executors.newSingleThreadExecutor(r->new Thread(r,"GAME mechanics stress"));
        Map<String,Object> metrics=new LinkedHashMap<>();long start=nanos();
        metrics.put("appliedBudgets",EngineBridge.map("stepSeconds",STEP_SECONDS,"nativeEvents",EVENT_BUDGET,"flushMillis",FLUSH_MILLIS));
        try {
            s.prepareRecording();long diskBefore=bytes(Paths.get(System.getenv("LOVE2GATHERING_DATA_DIR")));
            String catalogPath=System.getenv("LOVE2GATHERING_TEST_CATALOG_DIRECTORY");long catalogBefore=catalogPath==null?0:bytes(Paths.get(catalogPath));
            metrics.put("heapUsedBefore",Runtime.getRuntime().totalMemory()-Runtime.getRuntime().freeMemory());
            long create=nanos();
            Future<?> task=worker.submit(()->{
                Card source=TriggerFixture.card("Grizzly Bears");s.game.loadCards(Collections.singleton(source),s.human.getId());
                Token token=new WolfToken();int first=split?count/2:count;
                token.putOntoBattlefield(first,s.game,source.getSpellAbility(),s.human.getId());
                if(split)new WolfToken().putOntoBattlefield(count-first,s.game,source.getSpellAbility(),s.bot.getId());
                if(varied){int index=0;for(Permanent permanent:s.game.getBattlefield().getAllActivePermanents()){
                    if(index%2==0)permanent.setTapped(true);
                    if(index%3==0)permanent.addCounters(CounterType.P1P1.createInstance(2),permanent.getControllerId(),source.getSpellAbility(),s.game);
                    if(index%5==0)permanent.damage(1,source.getId(),source.getSpellAbility(),s.game,false,true);
                    index++;
                }}
                s.game.applyEffects();
                // Token ETB/created events are batched by XMage. Flush them
                // through its ordinary state/trigger processing before metrics.
                s.game.checkStateAndTriggered();
            });
            try{task.get(Math.max(1,(long)(STEP_SECONDS*1000)),TimeUnit.MILLISECONDS);}catch(TimeoutException ex){task.cancel(true);throw new BudgetReached("Native creation/effects step exceeded "+STEP_SECONDS+" seconds");}
            metrics.put("nativeCreateAndEffectsMs",milliseconds(create));
            int actual=s.game.getBattlefield().getAllActivePermanents().size();
            if(eventCount.get()==0)throw new AssertionError("Native token events were not observed after state/trigger processing");
            int expected=split?Math.min(count/2,500)+Math.min(count-count/2,500):Math.min(count,500);
            if(actual!=expected)throw new AssertionError("Native token quantity differs from predeclared pin cap: expected "+expected+", actual "+actual);
            long projection=nanos();s.publish();metrics.put("projectionMs",milliseconds(projection));
            Map<String,Object> frame=s.state();long encode=nanos();String json=EngineBridge.JSON.toJson(frame);metrics.put("jsonEncodeMs",milliseconds(encode));
            Files.writeString(out.resolve("projection.json"),json);
            Set<String> projected=new HashSet<>();int projectedCount=0;
            for(Object value:(List<?>)frame.get("players"))for(Object card:(List<?>)((Map<?,?>)value).get("battlefield")){
                projected.add(String.valueOf(((Map<?,?>)card).get("id")));projectedCount++;
            }
            if(projectedCount!=actual||projected.size()!=actual)throw new AssertionError("Projection dropped or merged native identities");
            long flush=nanos();boolean flushed=s.recorder==null||s.recorder.flush(FLUSH_MILLIS);metrics.put("recordingFlushMs",milliseconds(flush));
            metrics.put("recordingFlushed",flushed);metrics.put("outboxAndSqlBytesBefore",diskBefore);metrics.put("outboxAndSqlBytesAfter",bytes(Paths.get(System.getenv("LOVE2GATHERING_DATA_DIR"))));
            metrics.put("catalogSqlBytesBefore",catalogBefore);metrics.put("catalogSqlBytesAfter",catalogPath==null?null:bytes(Paths.get(catalogPath)));
            metrics.put("heapUsedAfter",Runtime.getRuntime().totalMemory()-Runtime.getRuntime().freeMemory());metrics.put("nativeEvents",eventCount.get());
            Map<String,Long> counted=new TreeMap<>();eventTypes.forEach((key,value)->counted.put(key,value.get()));metrics.put("nativeEventTypes",counted);
            metrics.put("eventCountScope","Fired native GameEvents after fixture setup; excludes simulations/playability; separate from recorded sequence and retained animation deque");
            metrics.put("jsonBytes",json.getBytes(java.nio.charset.StandardCharsets.UTF_8).length);metrics.put("nativeRequested",count);metrics.put("nativeActual",actual);metrics.put("projectedObjects",projectedCount);metrics.put("splitControllers",split);metrics.put("variedCharacteristics",varied);
            metrics.put("nativePerControllerImplementationCap",500);metrics.put("gameId",s.game.getId().toString());metrics.put("recording",s.recorder==null?null:s.recorder.state());
            metrics.put("totalMs",milliseconds(start));
            if(!flushed)throw new BudgetReached("Native/projection quantities passed, but recording did not flush within its declared budget");
            Files.writeString(out.resolve("result.json"),EngineBridge.JSON.toJson(EngineBridge.map("scenarioId",id,"status",actual<count?"native_limit_observed":"pass","evidenceType","deterministic_native","metrics",metrics,"expected",EngineBridge.map("requested",count,"actual",expected),"scope","Configured native token-creation operation with real effects/events/projection; fixture initial state, not a production game")));
            System.out.println("STRESS "+id+" requested="+count+" actual="+actual+" bytes="+metrics.get("jsonBytes"));
        }catch(Throwable ex){
            Throwable cause=ex;while(cause.getCause()!=null)cause=cause.getCause();
            Files.writeString(out.resolve("result.json"),EngineBridge.JSON.toJson(EngineBridge.map("scenarioId",id,"status",cause instanceof BudgetReached?"budget_exceeded":"fail","error",ex.toString(),"metrics",metrics)));throw ex;
        }finally{
            worker.shutdownNow();s.stop();boolean terminated=worker.awaitTermination(2,TimeUnit.SECONDS);
            Files.writeString(out.resolve("cleanup.json"),EngineBridge.JSON.toJson(EngineBridge.map("nativeExecutorTerminated",terminated,"gameThreadAlive",!terminated)));
        }
    }
}
