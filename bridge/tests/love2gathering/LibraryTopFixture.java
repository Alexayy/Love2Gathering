package love2gathering;

import com.google.gson.*;
import mage.Mana;
import mage.cards.Card;
import mage.abilities.TriggeredAbility;
import mage.constants.*;
import mage.game.PutToBattlefieldInfo;
import mage.game.turn.PreCombatMainPhase;
import mage.game.turn.PreCombatMainStep;
import mage.players.Player;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

/** Real native library permissions/play; initial resources alone use Game.cheat. */
public final class LibraryTopFixture {
    static final List<Map<String,Object>> checks=new ArrayList<>();
    static void check(boolean value,String text){checks.add(EngineBridge.map("passed",value,"message",text));if(!value)throw new AssertionError(text);}
    @SuppressWarnings("unchecked")static Map<String,Object> own(EngineBridge.Session s){return ((List<Map<String,Object>>)s.snapshot.get("players")).stream().filter(p->s.human.getId().toString().equals(p.get("id"))).findFirst().orElseThrow();}
    @SuppressWarnings("unchecked")static Map<String,Object> player(EngineBridge.Session s,Player player){return ((List<Map<String,Object>>)s.snapshot.get("players")).stream().filter(p->player.getId().toString().equals(p.get("id"))).findFirst().orElseThrow();}
    @SuppressWarnings("unchecked")static Map<String,Object> object(Object value){return (Map<String,Object>)value;}
    static void battlefield(EngineBridge.Session s,UUID owner,Card...cards){s.game.cheat(owner,TriggerFixture.NONE,TriggerFixture.NONE,Arrays.stream(cards).map(c->new PutToBattlefieldInfo(c,false)).toList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);}
    static void library(EngineBridge.Session s,Player player,Card...cards){player.getLibrary().clear();List<Card> reversed=new ArrayList<>(Arrays.asList(cards));Collections.reverse(reversed);s.game.cheat(player.getId(),reversed,TriggerFixture.NONE,Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);}
    static Map<String,Object> publishedPrompt(EngineBridge.Session s,long previous)throws Exception{
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
        while(System.nanoTime()<deadline){
            Map<String,Object> waiting=s.prompt,frame=s.snapshot;
            Object raw=frame.get("players");
            boolean perspective=raw instanceof List<?> && ((List<?>)raw).stream().anyMatch(value->value instanceof Map<?,?>&&s.human.getId().toString().equals(((Map<?,?>)value).get("id")));
            if(waiting!=null&&((Number)waiting.get("id")).longValue()!=previous&&frame.get("prompt")==waiting&&s.game.getId().toString().equals(frame.get("gameId"))&&perspective)return waiting;
            if(s.error!=null)throw new AssertionError(s.error);
            Thread.sleep(2);
        }
        throw new AssertionError("Native prompt must have a complete same-game, same-perspective published snapshot before the fixture uses it");
    }
    static EngineBridge.Session room(){
        JsonObject body=new JsonObject();body.addProperty("format","Limited");body.addProperty("recordingPort",0);JsonArray seats=new JsonArray();
        for(int index=0;index<3;index++)seats.add(JsonParser.parseString("{\"seatId\":\"human-"+index+"\",\"name\":\"Human "+index+"\",\"type\":\"human\",\"deck\":{\"main\":[{\"name\":\"Plains\",\"count\":40}]}}"));
        body.add("seats",seats);EngineBridge.Session s=new EngineBridge.Session(body,true);s.game.setStartingPlayerId(s.human.getId());s.game.getState().setActivePlayerId(s.human.getId());s.game.getState().setPriorityPlayerId(s.human.getId());s.game.getTurn().setPhase(new PreCombatMainPhase());s.game.getPhase().setStep(new PreCombatMainStep());for(Player p:s.game.getPlayers().values())p.updateRange(s.game);return s;
    }
    static void baseline(Path output)throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();
        try{
            Card courser=TriggerFixture.card("Courser of Kruphix"),forest=TriggerFixture.card("Forest"),next=TriggerFixture.card("Lightning Bolt");
            library(s,s.human,forest,next);battlefield(s,s.human.getId(),courser);s.game.applyEffects();Set<String> nativeIds=ActionabilityFixture.priority(s);
            @SuppressWarnings("unchecked")List<Map<String,Object>> choices=(List<Map<String,Object>>)s.prompt.get("choices");
            Map<String,Object> offered=choices.stream().filter(c->forest.getId().toString().equals(c.get("id"))).findFirst().orElseThrow();
            Map<String,Object> observation=EngineBridge.map("nativeTopRevealed",s.human.isTopCardRevealed(),"nativeOfferedTop",nativeIds.contains(forest.getId().toString()),"nativeChoiceName",object(offered.get("card")).get("name"),"projectedLibraryTop",own(s).get("libraryTop"));
            Files.writeString(output.resolve("observation.json"),EngineBridge.JSON.toJson(observation));
            check(s.human.isTopCardRevealed()&&nativeIds.contains(forest.getId().toString()),"XMage already offers Courser's real library-top land");
            check(own(s).get("libraryTop")!=null,"A native-revealed Courser top must be exported as libraryTop");
            Files.writeString(output.resolve("courser-initial.json"),EngineBridge.JSON.toJson(s.snapshot));
        }finally{s.stop();}
    }
    static void courser(Path output)throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=Executors.newSingleThreadExecutor(r->new Thread(r,"GAME library land response"));
        try{
            Card courser=TriggerFixture.card("Courser of Kruphix"),forest=TriggerFixture.card("Forest"),next=TriggerFixture.card("Lightning Bolt"),hand=TriggerFixture.card("Mountain");
            library(s,s.human,forest,next);battlefield(s,s.human.getId(),courser);s.game.cheat(s.human.getId(),TriggerFixture.NONE,Collections.singletonList(hand),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            s.priority.configure(JsonParser.parseString("{\"autoPass\":false}").getAsJsonObject());s.game.applyEffects();s.game.saveState(false);
            Future<Boolean> choosing=worker.submit(()->s.human.priority(s.game));Map<String,Object> prompt=publishedPrompt(s,-1);
            check(Boolean.TRUE.equals(prompt.get("priority")),"Courser test reaches an actual native human priority prompt");
            check(forest.getId().toString().equals(object(own(s).get("libraryTop")).get("id")),"Courser's projected top is the actual library source, distinct from hand cards");
            Files.writeString(output.resolve("courser-playable.json"),EngineBridge.JSON.toJson(s.snapshot));
            @SuppressWarnings("unchecked")List<Map<String,Object>> choices=(List<Map<String,Object>>)prompt.get("choices");
            Map<String,Object> choice=choices.stream().filter(c->forest.getId().toString().equals(c.get("id"))).findFirst().orElseThrow();
            ActionabilityFixture.answer(s,prompt,choice);choosing.get(10,TimeUnit.SECONDS);
            check(s.game.getPermanent(forest.getId())!=null&&!s.human.getLibrary().getCardList().contains(forest.getId()),"The ordinary offered UUID response really plays the native library-top land");
            s.game.applyEffects();Set<String> offered=ActionabilityFixture.priority(s);
            check(next.getId().toString().equals(object(own(s).get("libraryTop")).get("id")),"Playing the top updates the projected native top");
            check(!offered.contains(next.getId().toString())&&!offered.contains(hand.getId().toString()),"Visible nonland Courser top and exhausted hand land are not playable");
            Files.writeString(output.resolve("courser-nonland.json"),EngineBridge.JSON.toJson(s.snapshot));
        }finally{worker.shutdownNow();s.stop();}
    }
    static void privateRoom(Path output)throws Exception{
        EngineBridge.Session s=room();EngineBridge.Session b=s.perspectives.get(1),c=s.perspectives.get(2);
        try{
            Card vizier=TriggerFixture.card("Vizier of the Menagerie"),top=TriggerFixture.card("Grizzly Bears"),other=TriggerFixture.card("Mountain");
            library(s,s.human,top);library(s,b.human,other);battlefield(s,s.human.getId(),vizier);s.game.applyEffects();s.publishAll();
            check(s.game.getState().getLookedAt(s.human.getId()).isEmpty(),"Native UPDATE clears its transient looked-at data after callbacks");
            check(top.getId().toString().equals(object(own(s).get("libraryTop")).get("id"))&&"private".equals(own(s).get("libraryTopVisibility")),"Exact native private top survives a later publish after transient look cleanup");
            check(player(b,s.human).get("libraryTop")==null&&player(c,s.human).get("libraryTop")==null&&!EngineBridge.JSON.toJson(b.snapshot).contains(top.getId().toString()),"Private top identity never reaches either other human perspective");
            check(own(b).get("libraryTop")==null,"Owning a library never grants its unseen top");
            s.human.getPlayableObjects(s.game,Zone.ALL);s.publishAll();
            check(own(s).get("libraryTop")!=null,"Native simulation/playable calculation never clears a live look generation");
            List<Map<String,Object>> shuffleFrames=new ArrayList<>();s.game.addTableEventListener(event->{if(event.getMessage()!=null&&event.getMessage().contains("library is shuffled"))shuffleFrames.add(new LinkedHashMap<>(own(s)));});
            s.human.shuffleLibrary(null,s.game);check(s.human.getLibrary().getFromTop(s.game).getId().equals(top.getId()),"One-card native shuffle makes same-UUID freshness regression deterministic");
            check(!shuffleFrames.isEmpty()&&shuffleFrames.stream().allMatch(p->p.get("libraryTop")==null),"Shuffle INFO already hides prior private top before LIBRARY_SHUFFLED fires");
            s.game.applyEffects();s.publishAll();check(own(s).get("libraryTop")!=null,"Fresh native look callback can restore the shuffled top entitlement");
            s.game.getPermanent(vizier.getId()).moveToZone(Zone.GRAVEYARD,null,s.game,false);s.game.applyEffects();s.publishAll();
            check(own(s).get("libraryTop")==null,"Removing the actual native private-look effect clears the live top");
            Card courser=TriggerFixture.card("Courser of Kruphix");battlefield(s,s.human.getId(),courser);s.game.applyEffects();s.publishAll();
            check("Grizzly Bears".equals(object(player(b,s.human).get("libraryTop")).get("name"))&&"Grizzly Bears".equals(b.card(top).get("name")),"Native public top flag grants every human both projection and inspected identity");
            s.game.getPermanent(courser.getId()).moveToZone(Zone.GRAVEYARD,null,s.game,false);s.game.applyEffects();s.publishAll();
            check(player(b,s.human).get("libraryTop")==null&&Boolean.TRUE.equals(b.card(top).get("hidden")),"Public permission removal hides the top without borrowing old reveal history");
            s.human.getLibrary().clear();s.publishAll();check(own(s).get("libraryTop")==null,"An empty library has no stale top object");
            Files.writeString(output.resolve("room-hidden.json"),EngineBridge.JSON.toJson(b.snapshot));
        }finally{s.stop();}
    }
    static void opponentLibrary(Path output)throws Exception{
        EngineBridge.Session s=room();EngineBridge.Session b=s.perspectives.get(1),c=s.perspectives.get(2);ExecutorService worker=Executors.newSingleThreadExecutor(r->new Thread(r,"GAME opponent library response"));
        try{
            Card xanathar=TriggerFixture.card("Xanathar, Guild Kingpin"),top=TriggerFixture.card("Forest"),next=TriggerFixture.card("Mountain");library(s,b.human,top,next);battlefield(s,s.human.getId(),xanathar);
            TriggeredAbility ability=(TriggeredAbility)s.game.getPermanent(xanathar.getId()).getAbilities().stream().filter(TriggeredAbility.class::isInstance).findFirst().orElseThrow().copy();
            ability.getTargets().get(0).addTarget(b.human.getId(),ability,s.game);check(ability.resolve(s.game),"Xanathar's real native targeted ability resolves its library permissions");s.game.applyEffects();s.publishAll();
            check(top.getId().toString().equals(object(player(s,b.human).get("libraryTop")).get("id"))&&"private".equals(player(s,b.human).get("libraryTopVisibility")),"Generic native look can expose another owner's top to its actual grantee");
            check(own(b).get("libraryTop")==null&&player(c,b.human).get("libraryTop")==null,"Neither library ownership nor a third seat inherits Xanathar's private entitlement");
            s.priority.configure(JsonParser.parseString("{\"autoPass\":false}").getAsJsonObject());s.game.saveState(false);Future<Boolean> choosing=worker.submit(()->s.human.priority(s.game));Map<String,Object> prompt=publishedPrompt(s,-1);
            @SuppressWarnings("unchecked")List<Map<String,Object>> choices=(List<Map<String,Object>>)prompt.get("choices");Map<String,Object> choice=choices.stream().filter(value->top.getId().toString().equals(value.get("id"))).findFirst().orElseThrow();
            check("Forest".equals(object(choice.get("card")).get("name")),"Engine-offered opponent-library UUID keeps its authorized real card label");
            Files.writeString(output.resolve("opponent-top-playable.json"),EngineBridge.JSON.toJson(s.snapshot));ActionabilityFixture.answer(s,prompt,choice);choosing.get(10,TimeUnit.SECONDS);
            check(s.game.getPermanent(top.getId())!=null&&s.game.getPermanent(top.getId()).isControlledBy(s.human.getId())&&s.game.getPermanent(top.getId()).isOwnedBy(b.human.getId()),"The ordinary offered response really plays the opponent-owned library land under its permitted controller");
            s.game.applyEffects();s.publishAll();check(next.getId().toString().equals(object(player(s,b.human).get("libraryTop")).get("id"))&&!EngineBridge.JSON.toJson(c.snapshot).contains(next.getId().toString()),"Changing the opponent's top preserves per-seat privacy and exact new source");
        }finally{worker.shutdownNow();s.stop();}
    }
    static void payment(Path output)throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=Executors.newSingleThreadExecutor(r->new Thread(r,"GAME library spell payment"));
        try{
            Card frenzy=TriggerFixture.card("Experimental Frenzy"),top=TriggerFixture.card("Grizzly Bears"),next=TriggerFixture.card("Mountain"),hand=TriggerFixture.card("Grizzly Bears"),one=TriggerFixture.card("Forest"),two=TriggerFixture.card("Forest");
            library(s,s.human,top,next);battlefield(s,s.human.getId(),frenzy,one,two);s.game.cheat(s.human.getId(),TriggerFixture.NONE,Collections.singletonList(hand),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            s.human.getUserData().setManaPoolAutomatic(false);s.human.getManaPool().setAutoPayment(false);s.game.applyEffects();s.game.saveState(false);
            Set<String> offered=ActionabilityFixture.priority(s);check(offered.contains(top.getId().toString())&&!offered.contains(hand.getId().toString()),"Native Frenzy offers the payable library creature and forbids the identical hand creature");
            long previous=((Number)s.prompt.get("id")).longValue();Future<Boolean> cast=worker.submit(()->s.human.cast(top.getSpellAbility(),s.game,false,null));Map<String,Object> prompt=publishedPrompt(s,previous);
            check("play_mana".equals(prompt.get("type"))&&!NativeProjection.canLookAtLibraryTop(s.game),"Real library spell reaches native unpaid mana boundary");s.publish();
            check(own(s).get("libraryTop")==null&&!EngineBridge.JSON.toJson(s.snapshot).contains(next.getId().toString()),"The next private top never leaks while a library spell is unpaid");
            check(s.knownObject(next.getId())==null,"Inspect/name enrichment also denies that unentitled next library card");
            @SuppressWarnings("unchecked")List<String> manaObjects=(List<String>)prompt.get("actionable");check(!manaObjects.contains(next.getId().toString())&&!manaObjects.contains(hand.getId().toString()),"Mana-payment actionable objects never inherit library/hand spell permissions");
            Files.writeString(output.resolve("library-unpaid.json"),EngineBridge.JSON.toJson(s.snapshot));
            int answers=0;
            while(!cast.isDone()&&answers<8){
                @SuppressWarnings("unchecked")List<Map<String,Object>> choices=(List<Map<String,Object>>)prompt.get("choices");
                Map<String,Object> selected=choices.stream().filter(value->"mana".equals(value.get("responseType"))).findFirst().orElse(null);
                if(selected==null)selected=choices.stream().filter(value->one.getId().toString().equals(value.get("id"))||two.getId().toString().equals(value.get("id"))).findFirst().orElseThrow();
                previous=((Number)prompt.get("id")).longValue();ActionabilityFixture.answer(s,prompt,selected);answers++;
                long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);
                while(!cast.isDone()&&(s.prompt==null||((Number)s.prompt.get("id")).longValue()==previous)&&System.nanoTime()<deadline)Thread.sleep(2);
                if(!cast.isDone()){check(s.prompt!=null&&((Number)s.prompt.get("id")).longValue()!=previous,"Native mana selection advances without fabricating an answer");prompt=publishedPrompt(s,previous);}
            }
            check(cast.get(5,TimeUnit.SECONDS),"Real tapped/pooled mana completes the native library spell cost");s.game.applyEffects();s.publish();
            check(next.getId().toString().equals(object(own(s).get("libraryTop")).get("id")),"Only a fresh native look exposes the next top after payment completes");
            s.game.getStack().resolve(s.game);s.game.checkStateAndTriggered();s.human.getManaPool().addMana(Mana.GreenMana(2),s.game,hand.getSpellAbility());
            offered=ActionabilityFixture.priority(s);check(offered.contains(next.getId().toString())&&!offered.contains(hand.getId().toString()),"After resolution Frenzy still offers top land and rejects an affordable identical hand spell");
            Files.writeString(output.resolve("library-paid.json"),EngineBridge.JSON.toJson(s.snapshot));
        }finally{worker.shutdownNow();s.stop();}
    }
    static void futureSight()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();
        try{
            Card sight=TriggerFixture.card("Future Sight"),bolt=TriggerFixture.card("Lightning Bolt");library(s,s.human,bolt);battlefield(s,s.human.getId(),sight);s.human.getManaPool().addMana(Mana.RedMana(1),s.game,bolt.getSpellAbility());s.game.applyEffects();
            check(ActionabilityFixture.priority(s).contains(bolt.getId().toString())&&"public".equals(own(s).get("libraryTopVisibility")),"Future Sight uses the same generic native projection while its real spell permission differs from Courser");
        }finally{s.stop();}
    }
    public static void main(String[] args)throws Exception{
        Path root=Paths.get(args[0]),output=Paths.get(args[1]);Files.createDirectories(output);
        org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(LibraryTopFixture.class.getClassLoader());
        ExecutorService game=Executors.newSingleThreadExecutor(r->new Thread(r,"GAME library-top fixture"));
        try{game.submit(()->{try{baseline(output);courser(output);privateRoom(output);opponentLibrary(output);payment(output);futureSight();}catch(Exception ex){throw new RuntimeException(ex);}}).get(45,TimeUnit.SECONDS);}
        finally{game.shutdownNow();}
        Files.writeString(output.resolve("result.json"),EngineBridge.JSON.toJson(EngineBridge.map("passed",true,"checks",checks,"scope","Real native pinned engine, initial zones injected; no external services or user data")));
    }
}
