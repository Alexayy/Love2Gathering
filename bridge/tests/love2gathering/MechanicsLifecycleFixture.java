package love2gathering;

import com.google.gson.*;
import mage.util.Copier;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Diagnostic transport/lifecycle fixtures around a real initialized Session.
 * Held GAME and offered prompt maps are explicit fault injections, not Magic mechanics. */
public final class MechanicsLifecycleFixture {
    static volatile Thread decisionThread;
    static final ExecutorService DECISIONS=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"GAME diagnostic native decision");t.setDaemon(true);decisionThread=t;return t;});
    static void check(boolean value,String text){if(!value)throw new AssertionError(text);}
    static EngineBridge.Session session(){return TriggerFixture.session();}
    static Map<String,Object> ask(long id){return EngineBridge.map("id",id,"type","ask","choices",Arrays.asList(EngineBridge.map("id","yes","responseType","boolean","value",true),EngineBridge.map("id","no","responseType","boolean","value",false)));}
    static JsonObject answer(long id,String type,Object value){return EngineBridge.JSON.toJsonTree(EngineBridge.map("promptId",id,"type",type,"value",value)).getAsJsonObject();}
    static long nativeAsk(EngineBridge.Session s,boolean amount)throws Exception{
        DECISIONS.submit(()->{if(amount)s.human.getAmount(1,3,"Diagnostic amount",null,s.game);else s.human.chooseUse(mage.constants.Outcome.Benefit,"Diagnostic offered boolean",null,s.game);});
        Map<String,Object> prompt=ActionabilityFixture.waitPrompt(s,-1);
        Field opened=mage.player.human.HumanPlayer.class.getDeclaredField("responseOpenedForAnswer");opened.setAccessible(true);
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(3);
        while(!Boolean.TRUE.equals(opened.get(s.human))&&System.nanoTime()<deadline)Thread.sleep(2);
        check(Boolean.TRUE.equals(opened.get(s.human)),"Native decision must actually be waiting before transport input");
        return((Number)prompt.get("id")).longValue();
    }
    static void recording(EngineBridge.Session s){
        JsonObject metadata=new JsonObject();metadata.addProperty("title","Mechanics transport fault fixture");metadata.addProperty("format","Fixture");metadata.addProperty("startedAt",System.currentTimeMillis());
        s.recorder=ReplayRecorder.create(Integer.parseInt(System.getenv("LOVE2GATHERING_CATALOG_PORT")),metadata);
    }
    static void rejected(EngineBridge.Session s,JsonObject input)throws Exception{
        long before=s.recorder.nextSequence;Map<String,Object> prompt=s.prompt;boolean rejected=false;
        try{s.action(input);}catch(IllegalArgumentException ex){rejected=true;}
        check(rejected,"Unowned/unoffered/malformed input must be rejected");
        check(s.prompt==prompt&&s.recorder.nextSequence==before,"Rejected input must preserve prompt and accepted recording sequence");
    }
    public static void main(String[] args)throws Exception{
        Path root=Paths.get(args[0]),out=Paths.get(args[2]);Files.createDirectories(out);
        org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(MechanicsLifecycleFixture.class.getClassLoader());
        String id=args[1];Map<String,Object> details=new LinkedHashMap<>();EngineBridge.Session s=session();long started=System.nanoTime();
        try{
            switch(id){
                case "life-stop-held":{
                    CountDownLatch release=new CountDownLatch(1);
                    s.gameThread=new Thread(()->{try{while(release.getCount()>0)try{release.await();}catch(InterruptedException ignored){}}finally{s.running=false;}},"GAME deliberately held diagnostic");
                    s.gameThread.setDaemon(true);s.gameThread.start();
                    try{
                        s.stop();Map<?,?> execution=(Map<?,?>)s.state().get("execution");
                        check(s.gameThread.isAlive(),"Fault injection must genuinely retain GAME after Stop returned");
                        check(execution!=null&&Boolean.TRUE.equals(execution.get("threadAlive"))&&!Boolean.TRUE.equals(execution.get("terminationConfirmed")),"Stop return must not claim GAME termination");
                        check(Boolean.TRUE.equals(s.state().get("running"))&&s.state().get("prompt")==null,"Held native execution stays stopping with no interactive obsolete prompt");
                        details.put("stopping",s.state());
                    }finally{release.countDown();s.gameThread.join(2000);}
                    check(!s.gameThread.isAlive(),"Released diagnostic GAME must terminate");
                    check(Boolean.TRUE.equals(((Map<?,?>)s.state().get("execution")).get("terminationConfirmed")),"Termination is confirmed only after actual thread exit");
                    break;
                }
                case "life-stale-game":{
                    EngineBridge.current=s;JsonObject wrong=new JsonObject();wrong.addProperty("expectedGameId",UUID.randomUUID().toString());
                    boolean rejected=false;
                    try{Method method=EngineBridge.class.getDeclaredMethod("expectedSession",JsonObject.class);method.setAccessible(true);method.invoke(null,wrong);}catch(InvocationTargetException ex){rejected=ex.getCause()instanceof IllegalArgumentException;}
                    check(rejected,"A delayed old-game control must reject before touching current Session");
                    check(!s.stopRequested&&s.running,"Wrong-game control leaves current game intact");break;
                }
                case "life-concede-held-answer":{
                    CountDownLatch held=new CountDownLatch(1),release=new CountDownLatch(1);
                    Thread holder=new Thread(()->{synchronized(s.answerLock){held.countDown();try{release.await();}catch(InterruptedException ex){Thread.currentThread().interrupt();}}},"diagnostic held answer lane");holder.setDaemon(true);holder.start();held.await();
                    ExecutorService control=Executors.newSingleThreadExecutor();long began=System.nanoTime();
                    try{
                        Future<?> answer=control.submit(()->{try{s.action(JsonParser.parseString("{\"type\":\"concede\"}").getAsJsonObject());}catch(Exception ex){throw new RuntimeException(ex);}});
                        answer.get(500,TimeUnit.MILLISECONDS);
                        details.put("concedeLatencyMs",(System.nanoTime()-began)/1e6);
                        check(holder.isAlive()&&release.getCount()==1,"Concede must return while the ordinary answer lane is genuinely held");
                        check(s.prompt==null,"Native concession signal clears obsolete choices without inventing a terminal result");
                    }finally{release.countDown();holder.join(1000);control.shutdownNow();control.awaitTermination(1,TimeUnit.SECONDS);}
                    break;
                }
                case "life-concurrent-answer":{
                    recording(s);long idValue=nativeAsk(s,false);long before=s.recorder.nextSequence;
                    ExecutorService pool=Executors.newFixedThreadPool(16,r->{Thread t=new Thread(r,"diagnostic duplicate answer");t.setDaemon(true);return t;});CountDownLatch gate=new CountDownLatch(1);AtomicInteger accepted=new AtomicInteger();List<Future<?>> attempts=new ArrayList<>();
                    try{
                        for(int i=0;i<16;i++)attempts.add(pool.submit(()->{try{gate.await();s.action(answer(idValue,"boolean",true));accepted.incrementAndGet();}catch(IllegalArgumentException expected){}catch(Exception ex){throw new RuntimeException(ex);}}));
                        gate.countDown();for(Future<?> attempt:attempts)attempt.get(3,TimeUnit.SECONDS);
                    }finally{pool.shutdownNow();details.put("attempts",16);details.put("accepted",accepted.get());details.put("sequenceAdvance",s.recorder.nextSequence-before);details.put("replayId",s.recorder.id);}
                    check(accepted.get()==1,"Concurrent duplicate answers must have exactly one accepted action");
                    check(s.recorder.flush(5000),"Accepted response must flush to authoritative catalog");
                    java.net.HttpURLConnection connection=(java.net.HttpURLConnection)new java.net.URL("http://127.0.0.1:"+System.getenv("LOVE2GATHERING_CATALOG_PORT")+"/replays/"+s.recorder.id).openConnection();connection.setConnectTimeout(2000);connection.setReadTimeout(3000);
                    try(java.io.Reader reader=new java.io.InputStreamReader(connection.getInputStream(),java.nio.charset.StandardCharsets.UTF_8)){
                        JsonObject meta=JsonParser.parseReader(reader).getAsJsonObject();check(meta.get("actionCount").getAsInt()==1,"Exactly one accepted response is stored by the actual catalog");details.put("catalogAcceptedActionCount",meta.get("actionCount").getAsInt());
                    }finally{connection.disconnect();}break;
                }
                case "life-unoffered-uuid":{
                    recording(s);long prompt=nativeAsk(s,false);rejected(s,answer(prompt,"uuid",s.bot.getId().toString()));break;
                }
                case "life-typed-boolean":{recording(s);long prompt=nativeAsk(s,false);rejected(s,answer(prompt,"boolean","true"));break;}
                case "life-amount-bounds":{
                    recording(s);long prompt=nativeAsk(s,true);rejected(s,answer(prompt,"integer",4));rejected(s,answer(prompt,"integer",1.5));break;
                }
                case "life-empty-actionable":{
                    recording(s);long prompt=nativeAsk(s,false);s.prompt.put("actionable",Collections.emptyList());
                    rejected(s,answer(prompt,"uuid",s.human.getId().toString()));s.action(answer(prompt,"boolean",true));check(s.prompt==null,"Offered boolean still works when no object is actionable");break;
                }
                case "life-stale-answer":{recording(s);long prompt=nativeAsk(s,false);rejected(s,answer(prompt-1,"boolean",true));s.action(answer(prompt,"boolean",true));boolean duplicate=false;try{s.action(answer(prompt,"boolean",true));}catch(IllegalArgumentException ex){duplicate=true;}check(duplicate,"Lost-response retry cannot consume a later decision");break;}
                default:throw new IllegalArgumentException("Unknown lifecycle scenario "+id);
            }
            Files.writeString(out.resolve("result.json"),EngineBridge.JSON.toJson(EngineBridge.map("scenarioId",id,"status","pass","evidenceType","bridge_transport_fault_fixture","details",details,"wallMs",(System.nanoTime()-started)/1e6)));
        }catch(Throwable ex){Files.writeString(out.resolve("result.json"),EngineBridge.JSON.toJson(EngineBridge.map("scenarioId",id,"status","fail","evidenceType","bridge_transport_fault_fixture","error",ex.toString(),"details",details)));throw ex;
        }finally{
            if(s.recorder!=null)s.recorder.finish("aborted",EngineBridge.map("reason","diagnostic fixture cleanup"),null);
            s.stop();DECISIONS.shutdownNow();boolean terminated=DECISIONS.awaitTermination(2,TimeUnit.SECONDS);
            Files.writeString(out.resolve("cleanup.json"),EngineBridge.JSON.toJson(EngineBridge.map("decisionExecutorTerminated",terminated,"gameThreadAlive",decisionThread!=null&&decisionThread.isAlive(),"sessionGameThreadAlive",s.gameThread!=null&&s.gameThread.isAlive())));
            EngineBridge.current=null;
        }
    }
}
