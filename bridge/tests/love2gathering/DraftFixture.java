package love2gathering;

import com.google.gson.*;
import mage.cards.Card;
import mage.game.draft.*;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** Real native packs/bots/picks, plus a deterministic native deadline test. No test-zone cards. */
public final class DraftFixture {
    static int checks;
    static JsonObject json(Object value){return EngineBridge.JSON.toJsonTree(value).getAsJsonObject();}
    static void check(boolean ok,String label){if(!ok)throw new AssertionError(label);checks++;}
    static List<RoomSeat> seats(int count,int humans){List<RoomSeat> result=new ArrayList<>();for(int i=0;i<count;i++){JsonObject member=new JsonObject();member.addProperty("seatId","draft-seat-"+i);member.addProperty("name","Native draft "+i);member.addProperty("type",i<humans?"human":"bot");result.add(new RoomSeat(member,i));}return result;}
    static JsonObject config(String profile){JsonObject c=new JsonObject();c.addProperty("profile",profile);c.addProperty("pairing","swiss");c.addProperty("timing","PROFESSIONAL");JsonArray codes=new JsonArray();if(profile.equals("random")){codes.add("M21");codes.add("M20");c.add("randomSets",codes);}else if(profile.equals("booster")){codes.add("M21");codes.add("M20");codes.add("M19");c.add("sets",codes);}else c.addProperty("cubeCode","PauperCube");return c;}
    static JsonObject waitPick(DraftSession session,String seat,long deadline)throws Exception{
        while(System.nanoTime()<deadline){JsonObject s=json(session.state(seat));if("failed".equals(s.get("status").getAsString()))throw new AssertionError(s);if(s.has("pickToken")&&!s.get("pickToken").isJsonNull()&&s.getAsJsonArray("pack").size()>0)return s;Thread.sleep(2);}throw new AssertionError("Timed out waiting for native pick: "+session.status+" "+session.error);
    }
    static Map<String,Object> finishDraft(String profile,int count,int humans,boolean custom,boolean deadlineFixture)throws Exception{return finishDraft(profile,count,humans,custom,deadlineFixture,false);}
    static Map<String,Object> finishDraft(String profile,int count,int humans,boolean custom,boolean deadlineFixture,boolean elimination)throws Exception{
        JsonObject options=config(profile);if(elimination)options.addProperty("pairing","elimination");if(custom){JsonObject cube=new JsonObject();JsonArray main=new JsonArray();JsonObject card=new JsonObject();card.addProperty("name","Forest");card.addProperty("count",120);main.add(card);cube.add("main",main);options.add("customCube",cube);}
        DraftSession session=new DraftSession(options,seats(count,humans));long deadline=System.nanoTime()+TimeUnit.MINUTES.toNanos(5);session.start();
        Set<String> tokens=new HashSet<>(),sets=new TreeSet<>();int picks=0;boolean stale=false,privacy=false,timeout=false;
        try{
            JsonObject first=waitPick(session,"draft-seat-0",deadline);String oldToken=first.get("pickToken").getAsString();String oldCard=first.getAsJsonArray("pack").get(0).getAsJsonObject().get("id").getAsString();
            check(first.getAsJsonArray("players").size()==count,"All native draft seats projected");
            for(JsonElement player:first.getAsJsonArray("players")){JsonObject p=player.getAsJsonObject();check(!p.has("pack")&&!p.has("pool")&&!p.has("deck"),"Other player's draft contents remain private");}privacy=true;
            if(deadlineFixture){
                while(json(session.state("draft-seat-0")).get("deadline").getAsLong()==0){Thread.sleep(2);}
                check(json(session.state("draft-seat-0")).get("secondsRemaining").getAsInt()>0,"Native pick timer exposes its remaining duration");
                session.lock.locked(()->{session.draft.getPlayer(session.players.get("draft-seat-0").getId()).setPickDeadline(System.currentTimeMillis()-5000);return null;});
                ((DraftImpl)session.draft).picksCheckDone();
                while(json(session.state("draft-seat-0")).getAsJsonArray("pool").size()==0&&System.nanoTime()<deadline)Thread.sleep(2);
                check(json(session.state("draft-seat-0")).getAsJsonArray("pool").size()==1,"XMage autopicks when its native deadline expires");timeout=true;
            }
            while(System.nanoTime()<deadline&&Arrays.asList("initializing","drafting").contains(session.status)){
                for(int i=0;i<humans;i++){
                    JsonObject state=json(session.state("draft-seat-"+i));
                    if(!state.get("status").getAsString().equals("drafting")||state.get("pickToken").isJsonNull()||state.getAsJsonArray("pack").isEmpty())continue;
                    String token=state.get("pickToken").getAsString();String identity=i+":"+token;if(!tokens.add(identity))continue;
                    JsonObject card=state.getAsJsonArray("pack").get(0).getAsJsonObject();sets.add(card.get("set").getAsString());
                    JsonObject pick=new JsonObject();pick.addProperty("pickToken",token);pick.addProperty("cardId",card.get("id").getAsString());
                    session.pick("draft-seat-"+i,pick);picks++;
                    if(!stale){try{session.pick("draft-seat-"+i,pick);throw new AssertionError("Duplicate pick accepted");}catch(IllegalArgumentException expected){stale=true;}}
                }
                Thread.sleep(2);
            }
            if(session.worker!=null)session.worker.join(10000);
            check(session.status.equals("building")||session.status.equals("ready"),"Native "+profile+" draft completes: "+session.error);
            check(stale,"Stale draft picks rejected");
            List<Integer> pools=new ArrayList<>();
            for(int i=0;i<count;i++){
                JsonObject own=json(session.state("draft-seat-"+i));int poolSize=own.getAsJsonArray("pool").size();pools.add(poolSize);check(poolSize==45,"Native three-pack pool has 45 concrete cards");
                if(i<humans){
                    JsonObject invalid=new JsonObject();JsonArray forged=new JsonArray();forged.add(UUID.randomUUID().toString());invalid.add("main",forged);
                    check(!json(session.submitDeck("draft-seat-"+i,invalid)).get("accepted").getAsBoolean(),"Undrafted instance ID rejected with structured validation errors");
                    JsonObject tooSmall=new JsonObject();tooSmall.add("main",new JsonArray());JsonObject rejected=json(session.submitDeck("draft-seat-"+i,tooSmall));check(!rejected.get("accepted").getAsBoolean()&&!rejected.getAsJsonArray("errors").isEmpty(),"Native Limited validator rejects undersized deck");
                    JsonObject deck=new JsonObject();JsonArray chosen=new JsonArray();for(int n=0;n<23;n++)chosen.add(own.getAsJsonArray("pool").get(n).getAsJsonObject().get("id").getAsString());deck.add("main",chosen);JsonObject basics=new JsonObject();basics.addProperty("Forest",17);deck.add("basics",basics);
                    check(json(session.submitDeck("draft-seat-"+i,deck)).get("accepted").getAsBoolean(),"Pool-selected deck plus native basic lands accepted");
                    JsonObject selection=json(session.state("draft-seat-"+i)).getAsJsonObject("selection");
                    check(selection.getAsJsonArray("main").size()==23&&selection.getAsJsonObject("basics").get("Forest").getAsInt()==17,"Reconnect state restores native pool instance selections and added basics");
                }
                check(session.deckSource("draft-seat-"+i).get("format").getAsString().equals("Limited"),"Every player has a validated playable native Limited deck");
            }
            check(session.status.equals("ready"),"Human and native bot decks all become ready");
            JsonObject round=json(session.nextRound());check(round.getAsJsonArray("matches").size()==(count+1)/2,"Native pairings and byes cover every seat");
            Set<String> pairedSeats=new HashSet<>();int byes=0;String byeSeat=null;
            for(JsonElement pairing:round.getAsJsonArray("matches")){
                JsonObject pair=pairing.getAsJsonObject();for(JsonElement seat:pair.getAsJsonArray("seatIds"))check(pairedSeats.add(seat.getAsString()),"Native round assigns each seat exactly once");
                if(pair.has("bye")&&pair.get("bye").getAsBoolean()){byes++;byeSeat=pair.getAsJsonArray("seatIds").get(0).getAsString();check(pair.getAsJsonArray("seatIds").size()==1&&pair.get("finished").getAsBoolean(),"Native bye is already complete without a game");}
                else session.recordResult(pair.get("id").getAsString(),pair.getAsJsonArray("seatIds").get(0).getAsString());
            }
            check(pairedSeats.size()==count&&byes==count%2,"Native round retains all seats with the correct odd-seat bye count");
            JsonObject result=json(session.pairings());check(result.get("finished").getAsBoolean(),"Native pairing result adapter finishes a round");
            long points=0;for(JsonElement standing:result.getAsJsonArray("standings")){JsonObject entry=standing.getAsJsonObject();points+=entry.get("points").getAsInt();if(entry.get("seatId").getAsString().equals(byeSeat))check(entry.get("points").getAsInt()==3,"XMage awards its native three-point bye score");}check(points==(count+1)/2*3L,"Native tournament scores authoritative accepted results and byes");
            JsonObject next=json(session.nextRound());check(next.get("round").getAsInt()==2,"Native Swiss pairing advances to a second round");
            if(elimination){
                check(next.getAsJsonArray("matches").size()==1,"Native elimination retains only first-round winners");
                JsonObject finalPair=next.getAsJsonArray("matches").get(0).getAsJsonObject();session.recordResult(finalPair.get("id").getAsString(),finalPair.getAsJsonArray("seatIds").get(0).getAsString());
                check(json(session.nextRound()).get("status").getAsString().equals("completed"),"Native elimination completes after its final pairing");
            }
            return EngineBridge.map("profile",profile,"pairing",elimination?"elimination":"swiss","players",count,"humans",humans,"nativeBotCount",count-humans,"customCube",custom,"poolSizes",pools,"acceptedHumanPicks",picks,"observedSets",sets,"hiddenPacksAndPools",privacy,"stalePickRejected",stale,"nativeTimeoutFixture",timeout,"nativeLimitedDecks",count,"nativePairings",count/2,"nativeByes",byes,"secondRound",2);
        }finally{session.stop();if(session.worker!=null)session.worker.join(5000);check(session.worker==null||!session.worker.isAlive(),"Draft worker is reclaimed after completion/stop");}
    }
    static Map<String,Object> forfeitCase()throws Exception{
        DraftSession session=new DraftSession(config("booster"),seats(4,2));session.start();long deadline=System.nanoTime()+TimeUnit.MINUTES.toNanos(5);
        try{
            JsonObject initial=waitPick(session,"draft-seat-1",deadline);String picked=initial.getAsJsonArray("pack").get(0).getAsJsonObject().get("id").getAsString();
            JsonObject answer=new JsonObject();answer.addProperty("pickToken",initial.get("pickToken").getAsString());answer.addProperty("cardId",picked);session.pick("draft-seat-1",answer);
            session.forfeit("draft-seat-1");
            try{session.forfeit("not-a-seat");throw new AssertionError("Unknown forfeit seat accepted");}catch(IllegalArgumentException expected){check(true,"Unknown forfeit seat rejected");}
            Set<String> answered=new HashSet<>();
            while(System.nanoTime()<deadline&&Arrays.asList("initializing","drafting").contains(session.status)){
                JsonObject state=json(session.state("draft-seat-0"));if(state.get("pickToken").isJsonNull()||state.getAsJsonArray("pack").isEmpty()){Thread.sleep(2);continue;}
                String token=state.get("pickToken").getAsString();if(!answered.add(token)){Thread.sleep(2);continue;}
                JsonObject pick=new JsonObject();pick.addProperty("pickToken",token);pick.addProperty("cardId",state.getAsJsonArray("pack").get(0).getAsJsonObject().get("id").getAsString());session.pick("draft-seat-0",pick);
            }
            session.worker.join(10000);check(session.status.equals("building"),"Leaving human seat does not stall native draft or deck construction");
            JsonObject left=json(session.state("draft-seat-1"));check(left.getAsJsonArray("pool").size()==45,"Forfeited seat retains its complete native drafted pool");
            check(left.getAsJsonArray("pool").asList().stream().anyMatch(card->card.getAsJsonObject().get("id").getAsString().equals(picked)),"Card picked before leaving remains in its native pool");
            check(session.deckSource("draft-seat-1").get("format").getAsString().equals("Limited"),"XMage builds a native-valid deck for the forfeited seat");
            check(left.getAsJsonArray("players").asList().stream().map(JsonElement::getAsJsonObject).anyMatch(p->p.get("seatId").getAsString().equals("draft-seat-1")&&p.get("forfeited").getAsBoolean()&&p.get("ready").getAsBoolean()),"Public state identifies the departed ready AI seat without disclosing its cards");
            try{session.pick("draft-seat-1",answer);throw new AssertionError("Departed client kept picking");}catch(IllegalArgumentException expected){check(true,"Departed client cannot race native autopicks");}
            return EngineBridge.map("profile","booster","players",4,"leftSeatPool",45,"preLeavePickPreserved",true,"nativeAutopickOnly",true,"nativeBotDeck",true);
        }finally{session.stop();session.worker.join(5000);session.forfeitWorker.join(5000);check(!session.worker.isAlive()&&!session.forfeitWorker.isAlive(),"Draft and departure monitor threads both stop");}
    }
    public static void main(String[] args)throws Exception{
        Path root=Paths.get(args[0]);org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);Copier.setLoader(DraftFixture.class.getClassLoader());
        EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();
        List<Map<String,Object>> cases=new ArrayList<>();String failure=null;
        try{
            JsonObject options=json(DraftSession.options());check(options.getAsJsonArray("profiles").size()==3,"Only actually supported native draft procedures advertised");check(options.getAsJsonArray("cubes").size()>10,"Native bundled cubes discovered");
            for(int count:new int[]{3,17})try{new DraftSession(config("booster"),seats(count,1));throw new AssertionError("Unsupported capacity accepted");}catch(IllegalArgumentException expected){check(true,"Native profile seat bounds enforced");}
            cases.add(finishDraft("booster",4,2,false,true));cases.add(finishDraft("random",4,1,false,false));cases.add(finishDraft("cube",4,1,false,false));cases.add(finishDraft("cube",4,1,true,false));cases.add(finishDraft("booster",16,1,false,false));cases.add(finishDraft("booster",5,1,false,false));cases.add(finishDraft("booster",4,1,false,false,true));cases.add(forfeitCase());
        }catch(Throwable ex){failure=ex.toString();ex.printStackTrace();}
        Files.writeString(root.resolve("bridge/tests/draft-native-report.json"),EngineBridge.JSON.toJson(EngineBridge.map("passed",failure==null,"checks",checks,"scope","Native production boosters/cubes, native bots, simultaneous human picks, native deadline advancement fixture, pool membership, Limited validation and native tournament pairings; result adapter uses fixture outcomes, actual game completion is tested separately","tests",cases,"failure",failure)));
        if(failure!=null)System.exit(1);System.out.println("DRAFT NATIVE COMPLETE "+checks+" checks");
    }
}
