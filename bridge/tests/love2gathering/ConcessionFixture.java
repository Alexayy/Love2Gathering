package love2gathering;

import com.google.gson.*;
import mage.cards.Card;
import mage.constants.*;
import mage.game.PutToBattlefieldInfo;
import mage.game.turn.PreCombatMainPhase;
import mage.players.Player;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

/** Real simultaneous triggers with injected initial zones; no running user game. */
public final class ConcessionFixture {
    static void check(boolean value,String text){if(!value)throw new AssertionError(text);}
    static final class GatedAnswers extends ArrayBlockingQueue<List<String>> {
        final CountDownLatch beforeTake=new CountDownLatch(1),allowTake=new CountDownLatch(1);
        GatedAnswers(){super(1);}
        @Override public List<String> take()throws InterruptedException{
            beforeTake.countDown();allowTake.await();return super.take();
        }
    }
    static EngineBridge.Session room(){
        JsonArray seats=new JsonArray();
        for(int index=0;index<4;index++)seats.add(JsonParser.parseString("{\"seatId\":\"seat-"+index+"\",\"name\":\"Human "+index+"\",\"type\":\"human\",\"deck\":{\"main\":[{\"name\":\"Plains\",\"count\":40}]}}"));
        JsonObject body=new JsonObject();body.addProperty("format","Limited");body.addProperty("recordingPort",0);body.add("seats",seats);
        return new EngineBridge.Session(body,true);
    }
    static Thread ordering(EngineBridge.Session s,Throwable[] failure){
        s.game.setStartingPlayerId(s.human.getId());s.game.getState().setActivePlayerId(s.human.getId());s.game.getState().setPriorityPlayerId(s.human.getId());s.game.getTurn().setPhase(new PreCombatMainPhase());
        for(Player player:s.game.getPlayers().values())player.updateRange(s.game);
        Card warden=TriggerFixture.card("Soul Warden"),orator=TriggerFixture.card("Impassioned Orator"),bear=TriggerFixture.card("Grizzly Bears");
        s.game.cheat(s.human.getId(),TriggerFixture.NONE,TriggerFixture.NONE,Arrays.asList(new PutToBattlefieldInfo(warden,false),new PutToBattlefieldInfo(orator,false)),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
        s.game.checkStateAndTriggered();s.game.getStack().clear();s.game.getState().clearTriggeredAbilities();s.manualTriggers=true;
        s.game.loadCards(Collections.singleton(bear),s.human.getId());bear.setZone(Zone.OUTSIDE,s.game);
        check(bear.putOntoBattlefield(s.game,Zone.OUTSIDE,null,s.human.getId()),"Real creature entry creates the simultaneous triggers");
        Thread thread=new Thread(()->{try{s.game.checkStateAndTriggered();}catch(Throwable ex){failure[0]=ex;}},"GAME concession trigger fixture");
        thread.setDaemon(true);s.gameThread=thread;thread.start();return thread;
    }
    static void await(java.util.function.BooleanSupplier ready,String text)throws Exception{
        long deadline=System.nanoTime()+3_000_000_000L;while(!ready.getAsBoolean()&&System.nanoTime()<deadline)Thread.sleep(2);check(ready.getAsBoolean(),text);
    }
    static boolean projectedLoss(EngineBridge.Session s,UUID id){
        @SuppressWarnings("unchecked")List<Map<String,Object>> players=(List<Map<String,Object>>)s.state().get("players");
        return players!=null&&players.stream().anyMatch(p->id.toString().equals(p.get("id"))&&Boolean.TRUE.equals(p.get("lost")));
    }
    static Map<String,Object> test(boolean multiplayer,boolean race)throws Exception{
        EngineBridge.Session s=multiplayer?room():TriggerFixture.session();Throwable[] failure={null};Thread thread=null;GatedAnswers gated=null;
        try{
            if(race){
                // Gate only the bridge transport, never native rules. This
                // deterministically delivers a genuine order while a wake is
                // still queued, before GAME can consume either value.
                gated=new GatedAnswers();java.lang.reflect.Field field=EngineBridge.Session.class.getDeclaredField("triggerAnswers");field.setAccessible(true);field.set(s,gated);
            }
            thread=ordering(s,failure);final Thread active=thread;
            await(()->s.prompt!=null&&"order".equals(s.prompt.get("type")),"Native simultaneous trigger order really waits");
            if(gated!=null)check(gated.beforeTake.await(3,TimeUnit.SECONDS),"GAME reaches the gated transport wait");
            Map<String,Object> original=s.prompt;EngineBridge.Session actor=multiplayer?s.perspectives.get(1):s;
            JsonObject concession=new JsonObject();concession.addProperty("type","concede");concession.addProperty("expectedGameId",s.game.getId().toString());actor.action(concession);
            if(!race)await(()->s.game.getPlayer(actor.human.getId()).hasLost(),"The native queue marks the conceding player lost while an order is pending");
            if(multiplayer){
                check(!s.game.hasEnded()&&active.isAlive()&&s.prompt==original,"Another human's exact unanswered ordering stays open");
                if(!race)check(projectedLoss(s,actor.human.getId()),"Another human sees the actual native defeat while their unchanged order still waits");
                @SuppressWarnings("unchecked")List<Map<String,Object>> choices=(List<Map<String,Object>>)original.get("choices");
                JsonObject answer=new JsonObject();answer.addProperty("promptId",((Number)original.get("id")).longValue());answer.addProperty("type","order");
                answer.add("value",EngineBridge.JSON.toJsonTree(choices.stream().map(c->c.get("id").toString()).toList()));s.action(answer);
                if(gated!=null){check(gated.peek()!=null&&!gated.peek().isEmpty(),"A queued native wake never drops the genuine trigger answer");gated.allowTake.countDown();}
                thread.join(3000);check(!thread.isAlive()&&failure[0]==null&&!s.game.hasEnded()&&s.game.getStack().size()==2,"The surviving human's real trigger order completes and the room game continues");
            }else{
                thread.join(3000);check(!thread.isAlive()&&failure[0]==null&&s.game.hasEnded(),"Concession wakes and terminates native manual trigger ordering");
                check(s.game.getPlayer(s.human.getId()).hasLost(),"The practice result comes from native defeat");
            }
            check(s.game.getPlayer(actor.human.getId()).hasLost(),"Queued native concession is processed even when a genuine order replaced its wake");
            check(projectedLoss(s,actor.human.getId()),"The published projection retains the native seat defeat");
            return EngineBridge.map("scenario",race?"room-queued-wake-races-real-order":multiplayer?"room-other-seat-during-trigger-order":"practice-during-trigger-order","passed",true,"gameEnded",s.game.hasEnded(),"humanLost",s.game.getPlayer(actor.human.getId()).hasLost(),"threadTerminated",!thread.isAlive());
        }finally{if(gated!=null)gated.allowTake.countDown();s.stop();if(thread!=null)check(!thread.isAlive(),"Owned fixture GAME thread must stop");}
    }
    static Map<String,Object> observer(){
        JsonObject body=JsonParser.parseString("{\"format\":\"Modern\",\"recordingPort\":0,\"recordingSeatId\":\"observer\",\"seats\":[{\"seatId\":\"bot-a\",\"type\":\"bot\",\"deck\":{\"main\":[{\"name\":\"Plains\",\"count\":60}]}},{\"seatId\":\"bot-b\",\"type\":\"bot\",\"deck\":{\"main\":[{\"name\":\"Plains\",\"count\":60}]}}]}").getAsJsonObject();
        EngineBridge.Session s=new EngineBridge.Session(body,true);
        try{s.game.end();s.running=false;Map<String,Object> result=s.result();check(Boolean.TRUE.equals(result.get("completed"))&&"observer".equals(result.get("outcome")),"A public observer is not a missing player or a fabricated drawn seat");return EngineBridge.map("scenario","non-seat-observer-result","passed",true,"outcome",result.get("outcome"));}
        finally{s.stop();}
    }
    public static void main(String[] args)throws Exception{
        Path root=Paths.get(args[0]),output=Paths.get(args[1]);Files.createDirectories(output);
        org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(ConcessionFixture.class.getClassLoader());
        List<Map<String,Object>> results=Arrays.asList(test(false,false),test(true,false),test(true,true),observer());
        Files.writeString(output.resolve("result.json"),EngineBridge.JSON.toJson(EngineBridge.map("passed",true,"results",results,"scope","Real native simultaneous-trigger/concession processing; initial zones injected by Game.cheat, separate from production HTTP games")));
    }
}
