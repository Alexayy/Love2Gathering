package love2gathering;

import com.google.gson.*;
import mage.Mana;
import mage.abilities.*;
import mage.cards.*;
import mage.constants.*;
import mage.counters.CounterType;
import mage.game.*;
import mage.game.combat.CombatGroup;
import mage.game.events.PlayerQueryEvent;
import mage.game.events.GameEvent;
import mage.watchers.Watcher;
import java.util.concurrent.atomic.AtomicLong;
import mage.game.permanent.*;
import mage.game.turn.*;
import mage.players.Player;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.*;
import java.util.stream.*;

/** Deterministic zones/resources only. All effects, costs, combat and SBA run in XMage. */
public final class CoreMechanicsFixture {
    static final List<Card> NONE=Collections.emptyList();
    static Path output;
    static String currentScenario;
    static double stepSeconds=12;
    static long maxNativeEvents=1000,maxAcceptedActions=100,maxAttempts=110,maxObjects=100,maxStackResolutions=64,peakObjects;
    static long budgetLong(String name,long fallback){
        String property="love2gathering.test."+name,value=System.getProperty(property);
        long result=value==null?fallback:Long.parseLong(value);
        if(result<0)throw new IllegalArgumentException(property+" must be nonnegative");
        return result;
    }
    static void configureBudgets(){
        stepSeconds=Double.parseDouble(System.getProperty("love2gathering.test.stepSeconds","12"));
        if(!Double.isFinite(stepSeconds)||stepSeconds<=0||stepSeconds>TimeUnit.NANOSECONDS.toSeconds(Long.MAX_VALUE/2))throw new IllegalArgumentException("love2gathering.test.stepSeconds must be finite, positive and representable in nanoseconds");
        maxNativeEvents=budgetLong("nativeEvents","C36".equals(currentScenario)?2100000:1000);
        maxAcceptedActions=budgetLong("acceptedActions",100);maxAttempts=budgetLong("attempts",110);
        maxObjects=budgetLong("objects",100);maxStackResolutions=budgetLong("stackResolutions",64);
    }
    static Map<String,Object> appliedBudgets(){return EngineBridge.map("stepSeconds",stepSeconds,"nativeEvents",maxNativeEvents,"nativeEventScope","per registered actual native game; excludes simulation/playable checks","acceptedActions",maxAcceptedActions,"attempts",maxAttempts,"objects",maxObjects,"objectScope","simultaneous battlefield permanents plus stack objects in one native game, checked at completed operations and snapshots","stackResolutions",maxStackResolutions);}
    static void objectBudget(EngineBridge.Session s){
        long count=(long)s.game.getBattlefield().getAllActivePermanents().size()+s.game.getStack().size();peakObjects=Math.max(peakObjects,count);
        if(count>maxObjects)throw new CoreBudgetExceeded("Native battlefield/stack object test budget exceeded: "+count+">"+maxObjects);
    }
    static final Map<Game,CoreEventCounter> EVENT_COUNTS=Collections.synchronizedMap(new IdentityHashMap<>());
    static final class CoreEventCounter {final AtomicLong total=new AtomicLong();final Map<String,AtomicLong> types=new ConcurrentHashMap<>();}
    static final class CoreBudgetExceeded extends RuntimeException {CoreBudgetExceeded(String text){super(text);}}
    /** Stateless watcher copies use external identity-keyed totals: bookmarks do not reset observations. */
    static final class CoreNativeWatcher extends Watcher {
        CoreNativeWatcher(){super(WatcherScope.GAME);}
        @Override public void watch(GameEvent event,Game game){
            if(game.isSimulation()||game.inCheckPlayableState())return;
            CoreEventCounter value=EVENT_COUNTS.get(game);if(value==null)return;
            long total=value.total.incrementAndGet();value.types.computeIfAbsent(event.getType().name(),key->new AtomicLong()).incrementAndGet();
            if(total>maxNativeEvents)throw new CoreBudgetExceeded("Native fired-event test budget exceeded");
        }
        @Override public CoreNativeWatcher copy(){return new CoreNativeWatcher();}
    }
    static Map<String,Long> eventTypes(){Map<String,Long> result=new TreeMap<>();for(CoreEventCounter count:EVENT_COUNTS.values())count.types.forEach((key,value)->result.merge(key,value.get(),Long::sum));return result;}
    static long nativeEventTotal(){return EVENT_COUNTS.values().stream().mapToLong(value->value.total.get()).sum();}
    static int checks,accepted,attempts;
    static final List<Map<String,Object>> trace=new ArrayList<>();
    static final List<EngineBridge.Session> sessions=new ArrayList<>();
    static final ExecutorService GAME=Executors.newSingleThreadExecutor(r->new Thread(r,"GAME core operation"));
    static void check(boolean value,String text){if(!value)throw new AssertionError(text);checks++;trace.add(EngineBridge.map("kind","assertion","text",text));}
    @SuppressWarnings("unchecked")static Map<String,Object> obj(Object value){return(Map<String,Object>)value;}
    @SuppressWarnings("unchecked")static List<Map<String,Object>> list(Object value){return(List<Map<String,Object>>)value;}
    static Card card(String name){return TriggerFixture.card(name);}
    static EngineBridge.Session setup(){EngineBridge.Session s=ActionabilityFixture.setup();sessions.add(s);initialize(s);return s;}
    static void initialize(EngineBridge.Session s){
        EVENT_COUNTS.put(s.game,new CoreEventCounter());s.game.getState().addWatcher(new CoreNativeWatcher());
        s.game.setStartingPlayerId(s.human.getId());s.game.getState().setActivePlayerId(s.human.getId());s.game.getState().setPriorityPlayerId(s.human.getId());
        s.game.getTurn().setPhase(new PreCombatMainPhase());s.game.getPhase().setStep(new PreCombatMainStep());
        for(Player p:s.game.getPlayers().values())p.updateRange(s.game);
        try{java.lang.reflect.Field f=GameImpl.class.getDeclaredField("playerList");f.setAccessible(true);f.set(s.game,s.game.getState().getPlayerList(s.human.getId()));}catch(Exception e){throw new RuntimeException(e);}
    }
    static void battlefield(EngineBridge.Session s,UUID owner,Card... cards){s.game.cheat(owner,NONE,NONE,Arrays.stream(cards).map(c->new PutToBattlefieldInfo(c,false)).collect(Collectors.toList()),NONE,NONE,NONE);s.game.applyEffects();objectBudget(s);}
    static void hand(EngineBridge.Session s,Card... cards){s.game.cheat(s.human.getId(),NONE,Arrays.asList(cards),Collections.emptyList(),NONE,NONE,NONE);}
    static void library(EngineBridge.Session s,String... names){s.game.cheat(s.human.getId(),Arrays.stream(names).map(CoreMechanicsFixture::card).collect(Collectors.toList()),NONE,Collections.emptyList(),NONE,NONE,NONE);}
    static void clearSetup(EngineBridge.Session s){s.game.getStack().clear();s.game.getState().clearTriggeredAbilities();}
    static Permanent permanent(EngineBridge.Session s,Card c){return s.game.getPermanent(c.getId());}
    static void frame(EngineBridge.Session s,String label)throws Exception{objectBudget(s);s.publish();Files.writeString(output.resolve(label+".json"),EngineBridge.JSON.toJson(s.snapshot));}
    static long id(Map<String,Object> p){return((Number)p.get("id")).longValue();}
    static Map<String,Object> choice(Map<String,Object> p,String wanted){return list(p.get("choices")).stream().filter(c->wanted.equals(String.valueOf(c.get("id")))).findFirst().orElseThrow(()->new AssertionError("Missing offered choice "+wanted+": "+EngineBridge.JSON.toJson(p)));}
    static Map<String,Object> byLabel(Map<String,Object> p,String text){return list(p.get("choices")).stream().filter(c->String.valueOf(c.get("label")).toLowerCase(Locale.ROOT).contains(text.toLowerCase(Locale.ROOT))).findFirst().orElseThrow(()->new AssertionError("Missing offered label "+text+": "+EngineBridge.JSON.toJson(p)));}
    static void answer(EngineBridge.Session s,Map<String,Object> p,Map<String,Object> selected)throws Exception{
        attempts++;if(attempts>maxAttempts||accepted>=maxAcceptedActions)throw new CoreBudgetExceeded("Test action budget exceeded before native delivery");JsonObject a=new JsonObject();a.addProperty("promptId",id(p));a.addProperty("type",String.valueOf(selected.get("responseType")));a.add("value",EngineBridge.JSON.toJsonTree(selected.containsKey("value")?selected.get("value"):selected.get("id")));
        s.action(a);accepted++;trace.add(EngineBridge.map("kind","accepted_action","prompt",p,"answer",a));
    }
    static void amount(EngineBridge.Session s,Map<String,Object> p,int value)throws Exception{check("amount".equals(p.get("type"))||"get_amount".equals(p.get("type")),"Expected native amount prompt");int min=((Number)p.get("min")).intValue(),max=((Number)p.get("max")).intValue();check(value>=min&&value<=max,"Amount is inside offered native bounds");answer(s,p,EngineBridge.map("responseType","integer","value",value));}
    static void distribute(EngineBridge.Session s,Map<String,Object> p,List<Integer> values)throws Exception{check("multi_amount".equals(p.get("type")),"Expected native distribution prompt");answer(s,p,EngineBridge.map("responseType","multi_amount","value",values));}
    interface Handler{void accept(EngineBridge.Session s,Map<String,Object> prompt)throws Exception;}
    static <T>T run(EngineBridge.Session s,Callable<T> operation,Handler handler)throws Exception{
        long prior=s.prompt==null?-1:id(s.prompt),until=System.nanoTime()+(long)(stepSeconds*1000000000d);Future<T> future=GAME.submit(operation);
        while(!future.isDone()&&System.nanoTime()<until){Map<String,Object> p=s.prompt;if(p!=null&&id(p)!=prior){prior=id(p);Files.writeString(output.resolve("last-prompt.json"),EngineBridge.JSON.toJson(p));if(handler==null)throw new AssertionError("Unexpected native prompt: "+EngineBridge.JSON.toJson(p));handler.accept(s,p);}else Thread.sleep(2);}
        if(!future.isDone()){future.cancel(true);throw new CoreBudgetExceeded("Native operation exceeded stepSeconds="+stepSeconds);}
        T result=future.get();objectBudget(s);return result;
    }
    static Handler target(UUID target){return(s,p)->{check("pick_target".equals(p.get("type")),"Native operation asks for an offered target");answer(s,p,choice(p,target.toString()));};}
    static void mana(EngineBridge.Session s,Card source,Mana value){s.human.getManaPool().addMana(value,s.game,source.getSpellAbility());}
    static void cast(EngineBridge.Session s,Card spell,Mana funds,Handler handler)throws Exception{hand(s,spell);mana(s,spell,funds);check(run(s,()->s.human.cast(spell.getSpellAbility(),s.game,false,null),handler),"Native cast succeeds for "+spell.getName());}
    static void resolve(EngineBridge.Session s,Handler handler)throws Exception{check(!s.game.getStack().isEmpty(),"Native stack has object to resolve");trace.add(EngineBridge.map("kind","native_stack_resolve","id",s.game.getStack().peek().getId().toString(),"sourceId",String.valueOf(s.game.getStack().peek().getSourceId()),"controllerId",String.valueOf(s.game.getStack().peek().getControllerId())));frame(s,"stack-before-"+trace.size());run(s,()->{s.game.getStack().resolve(s.game);s.game.checkStateAndTriggered();return true;},handler);}
    static void settle(EngineBridge.Session s,Handler handler)throws Exception{run(s,()->{s.game.checkStateAndTriggered();return true;},handler);int count=0;while(!s.game.getStack().isEmpty()){if(++count>maxStackResolutions)throw new CoreBudgetExceeded("Native stack-resolution test budget exceeded");check(true,"Finite native trigger budget");resolve(s,handler);}}
    static void enter(EngineBridge.Session s,Card c)throws Exception{s.game.loadCards(Collections.singleton(c),s.human.getId());c.setZone(Zone.OUTSIDE,s.game);check(c.putOntoBattlefield(s.game,Zone.OUTSIDE,null,s.human.getId()),"Native creature really enters");}
    static Mana colors(int white,int blue,int black,int red,int green,int colorless){Mana m=new Mana();m.add(Mana.WhiteMana(white));m.add(Mana.BlueMana(blue));m.add(Mana.BlackMana(black));m.add(Mana.RedMana(red));m.add(Mana.GreenMana(green));m.add(Mana.ColorlessMana(colorless));return m;}

    static void characteristics(String scenario)throws Exception{
        EngineBridge.Session s=setup();Card bear=card("Grizzly Bears");
        switch(scenario){
        case "C01":{
            Card angel=card("Angel of Vitality");battlefield(s,s.human.getId(),angel);s.human.setLife(25,s.game,null);permanent(s,angel).addCounters(CounterType.P1P1.createInstance(),s.human.getId(),null,s.game);s.game.applyEffects();Map<String,Object> v=s.card(permanent(s,angel));
            check("5".equals(v.get("power"))&&"5".equals(v.get("toughness")),"Threshold plus counter projects native5/5");check("2".equals(obj(v.get("printing")).get("power")),"Printing remains independently2/2");s.human.setLife(24,s.game,null);s.game.applyEffects();check(permanent(s,angel).getPower().getValue()==3,"Conditional boost disappears below25 while counter remains");break;}
        case "C02":{
            battlefield(s,s.human.getId(),bear);Permanent p=permanent(s,bear);p.addCounters(CounterType.P1P1.createInstance(3),s.human.getId(),null,s.game);p.addCounters(CounterType.M1M1.createInstance(2),s.human.getId(),null,s.game);s.game.checkStateAndTriggered();
            check(p.getCounters(s.game).getCount(CounterType.P1P1)==1&&p.getCounters(s.game).getCount(CounterType.M1M1)==0,"Opposite counters annihilate through native SBA");s.game.applyEffects();check(p.getPower().getValue()==3&&p.getToughness().getValue()==3,"Remaining native counter modifies both live values");break;}
        case "C03":{
            Card myr=card("Darksteel Myr");battlefield(s,s.human.getId(),myr);Permanent p=permanent(s,myr);p.damage(8,bear.getId(),bear.getSpellAbility(),s.game,false,true);s.game.checkStateAndTriggered();check(permanent(s,myr)!=null&&p.getDamage()==8,"Indestructible survives lethal marked damage");p.addCounters(CounterType.M1M1.createInstance(2),s.human.getId(),null,s.game);s.game.applyEffects();check(p.getToughness().getValue()==-1,"Native toughness can become negative");s.game.checkStateAndTriggered();check(permanent(s,myr)==null&&s.human.getGraveyard().contains(myr.getId()),"Nonpositive toughness SBA ignores indestructible");break;}
        case "C04":{
            Card lord=card("Elvish Archdruid"),elf=card("Llanowar Elves");battlefield(s,s.human.getId(),lord,elf);check(permanent(s,elf).getPower().getValue()==2,"Continuous lord boosts another Elf");check(permanent(s,lord).getPower().getValue()==2,"Other-creature lord does not boost itself");permanent(s,lord).sacrifice(null,s.game);s.game.applyEffects();check(permanent(s,elf).getPower().getValue()==1,"Removing source removes continuous boost");break;}
        case "C05":{
            Card equipment=card("Bonesplitter"),aura=card("Rancor");battlefield(s,s.human.getId(),bear,equipment,aura);check(permanent(s,bear).addAttachment(equipment.getId(),equipment.getSpellAbility(),s.game),"Native equip attachment succeeds");check(permanent(s,bear).addAttachment(aura.getId(),aura.getSpellAbility(),s.game),"Native Aura attachment succeeds");s.game.applyEffects();Map<String,Object> v=s.card(permanent(s,bear));check("6".equals(v.get("power"))&&"2".equals(v.get("toughness")),"Equipment and Aura boost combine in live projection");check(permanent(s,bear).getAttachments().size()==2,"Native host retains both attachment identities");check(String.valueOf(v.get("keywords")).toLowerCase().contains("trample"),"Granted trample is projected");break;}
        case "C06":{
            battlefield(s,s.bot.getId(),bear);permanent(s,bear).tap(null,s.game);Card act=card("Act of Treason");cast(s,act,Mana.RedMana(3),target(bear.getId()));resolve(s,null);Map<String,Object> v=s.card(permanent(s,bear));check(s.bot.getId().toString().equals(v.get("ownerId"))&&s.human.getId().toString().equals(v.get("controllerId")),"Control change preserves original owner");check(!permanent(s,bear).isTapped()&&String.valueOf(v.get("keywords")).toLowerCase().contains("haste"),"Act really untaps and grants native haste");break;}
        case "C07":{
            Card equipment=card("Bonesplitter");battlefield(s,s.human.getId(),bear,equipment);permanent(s,bear).addAttachment(equipment.getId(),equipment.getSpellAbility(),s.game);permanent(s,bear).addCounters(CounterType.P1P1.createInstance(2),s.human.getId(),null,s.game);permanent(s,bear).damage(1,equipment.getId(),equipment.getSpellAbility(),s.game,false,true);int zcc=s.game.getState().getZoneChangeCounter(bear.getId());Card shift=card("Cloudshift");cast(s,shift,Mana.WhiteMana(1),target(bear.getId()));resolve(s,null);Permanent back=permanent(s,bear);check(back!=null&&s.game.getState().getZoneChangeCounter(bear.getId())>zcc,"Blink creates a new native zone-change object");check(back.getCounters(s.game).isEmpty()&&back.getDamage()==0&&back.getPower().getValue()==2,"New object loses old counters/damage/boost");check(back.getAttachments().isEmpty()&&permanent(s,equipment).getAttachedTo()==null,"Equipment stays behind unattached");break;}
        case "C08":{
            battlefield(s,s.human.getId(),bear);Card blade=card("Doom Blade"),shift=card("Cloudshift");cast(s,blade,Mana.BlackMana(2),target(bear.getId()));cast(s,shift,Mana.WhiteMana(1),target(bear.getId()));resolve(s,null);int zcc=s.game.getState().getZoneChangeCounter(bear.getId());resolve(s,null);check(permanent(s,bear)!=null&&s.game.getState().getZoneChangeCounter(bear.getId())==zcc,"Removal targeting old object cannot kill blinked object");check(s.game.getStack().isEmpty()&&s.human.getGraveyard().contains(blade.getId()),"Illegal-target spell leaves stack without applying removal");break;}
        }
        frame(s,"final-frame");
    }

    static void triggers(String scenario)throws Exception{
        EngineBridge.Session s="C13".equals(scenario)?room(2,false):setup();
        if("C09".equals(scenario)){
            Card w=card("Soul Warden"),p=card("Ajani's Pridemate");battlefield(s,s.human.getId(),w,p);clearSetup(s);enter(s,card("Grizzly Bears"));settle(s,null);check(s.human.getLife()==21,"Native ETB gains life");check(permanent(s,p).getCounters(s.game).getCount(CounterType.P1P1)==1,"Life-gain trigger generates a nested counter trigger");
        }else if("C10".equals(scenario)){
            Card artist=card("Blood Artist"),cut=card("Zulaport Cutthroat"),bear=card("Grizzly Bears");battlefield(s,s.human.getId(),artist,cut,bear);clearSetup(s);Card wrath=card("Wrath of God");cast(s,wrath,Mana.WhiteMana(4),null);resolve(s,target(s.bot.getId()));settle(s,target(s.bot.getId()));check(s.human.getGraveyard().containsAll(Arrays.asList(artist.getId(),cut.getId(),bear.getId())),"Mass death removes trigger sources and creature together");check(s.human.getLife()==26&&s.bot.getLife()==14,"LKI death triggers survive source loss and drain six");
        }else if("C11".equals(scenario)){
            Card w=card("Soul Warden"),o=card("Impassioned Orator"),p=card("Ajani's Pridemate"),a=card("Angel of Vitality");s.human.setLife(24,s.game,null);battlefield(s,s.human.getId(),w,o,p,a);clearSetup(s);s.manualTriggers=true;enter(s,card("Grizzly Bears"));
            Handler ordering=(session,prompt)->{check("order".equals(prompt.get("type")),"Simultaneous triggers offer explicit manual resolution order");List<Map<String,Object>> choices=list(prompt.get("choices"));check(choices.size()==2,"Two same-controller ETB triggers are independently offered");List<String> ids=choices.stream().sorted(Comparator.comparing(c->!o.getId().toString().equals(c.get("sourceId")))).map(c->c.get("id").toString()).collect(Collectors.toList());answer(session,prompt,EngineBridge.map("responseType","order","value",ids));};
            run(s,()->{s.game.checkStateAndTriggered();return true;},ordering);check(s.game.getStack().peek().getSourceId().equals(o.getId()),"Leftmost requested trigger actually resolves first");settle(s,ordering);check(s.human.getLife()==28&&permanent(s,p).getCounters(s.game).getCount(CounterType.P1P1)==2,"Two amplified life gains yield two nested counters");check(permanent(s,a).getPower().getValue()==4,"Threshold boost activates while nested triggers resolve");
        }else if("C12".equals(scenario)){
            Card attendant=card("Soul's Attendant");battlefield(s,s.human.getId(),attendant);clearSetup(s);enter(s,card("Grizzly Bears"));settle(s,(ss,p)->{check("ask".equals(p.get("type")),"Optional life gain exposes a boolean native choice");answer(ss,p,choice(p,"no"));});check(s.human.getLife()==20,"Declining optional trigger leaves life unchanged");enter(s,card("Llanowar Elves"));settle(s,(ss,p)->{check("ask".equals(p.get("type")),"Game continues to next independent optional trigger");answer(ss,p,choice(p,"yes"));});check(s.human.getLife()==21,"Subsequent optional yes still resolves after explicit exit");
        }else{
            EngineBridge.Session other=s.perspectives.get(1);Card one=card("Soul Warden"),two=card("Soul Warden");battlefield(s,s.human.getId(),one);battlefield(s,other.human.getId(),two);clearSetup(s);enter(s,card("Grizzly Bears"));s.game.checkStateAndTriggered();check(s.game.getStack().size()==2,"Two players' ETB triggers share the native stack");check(s.game.getStack().peek().getControllerId().equals(other.human.getId()),"Nonactive trigger is above active trigger under APNAP");settle(s,null);check(s.human.getLife()==21&&other.human.getLife()==21,"Both APNAP triggers resolve for their actual controllers");
        }
        frame(s,"final-frame");
    }

    static CombatGroup combatSetup(EngineBridge.Session s,Card attacker,Card... blockers){
        battlefield(s,s.bot.getId(),attacker);if(blockers.length>0)battlefield(s,s.human.getId(),blockers);clearSetup(s);s.game.getTurn().setPhase(new CombatPhase());s.game.getPhase().setStep(new DeclareBlockersStep());s.game.getState().setActivePlayerId(s.bot.getId());s.game.getState().setPriorityPlayerId(s.human.getId());s.game.getCombat().getDefenders().add(s.human.getId());s.game.getCombat().setAttacker(s.bot.getId());check(s.game.getCombat().addAttackerToCombat(attacker.getId(),s.human.getId(),s.game),"Real attacker registered in native combat");for(Card b:blockers){s.human.declareBlocker(s.human.getId(),b.getId(),attacker.getId(),s.game,false);check(s.game.getCombat().findGroup(attacker.getId()).getBlockers().contains(b.getId()),"Real blocker assigned by native declaration");}s.game.getCombat().acceptBlockers(s.game);return s.game.getCombat().findGroup(attacker.getId());
    }
    static void damage(EngineBridge.Session s,boolean first)throws Exception{s.game.getPhase().setStep(new CombatDamageStep(first));run(s,()->{s.game.getPhase().getStep().beginStep(s.game,s.bot.getId());/* Production Phase enters GameImpl.playPriority, which reapplies effects before SBA. */s.game.applyEffects();s.game.checkStateAndTriggered();return true;},null);}
    static void combat(String scenario)throws Exception{
        EngineBridge.Session s=setup();Card attacker=card("C16".equals(scenario)?"Colossal Dreadmaw":"C17".equals(scenario)?"White Knight":"C18".equals(scenario)?"Fencing Ace":"C19".equals(scenario)?"Vampire Nighthawk":"Grizzly Bears");Card blocker=card("C19".equals(scenario)?"Giant Spider":"Grizzly Bears");
        if("C20".equals(scenario)){
            Card flyer=card("Wind Drake"),walk=card("River Boa"),menace=card("Boggart Brute"),unblockable=card("Invisible Stalker"),reach=card("Giant Spider"),island=card("Island");battlefield(s,s.bot.getId(),flyer,walk,menace,unblockable);battlefield(s,s.human.getId(),blocker,reach,island);clearSetup(s);s.game.getTurn().setPhase(new CombatPhase());s.game.getPhase().setStep(new DeclareBlockersStep());s.game.getState().setActivePlayerId(s.bot.getId());s.game.getCombat().getDefenders().add(s.human.getId());s.game.getCombat().setAttacker(s.bot.getId());for(Card c:Arrays.asList(flyer,walk,menace,unblockable))check(s.game.getCombat().addAttackerToCombat(c.getId(),s.human.getId(),s.game),"Attacker enters native legality comparison");List<Map<String,Object>> options=NativeProjection.blockerOptions(s,Arrays.asList(blocker.getId(),reach.getId()));Map<String,Object> ground=options.stream().filter(x->blocker.getId().toString().equals(x.get("blockerId"))).findFirst().orElseThrow();Collection<?> allowed=(Collection<?>)ground.get("legalAttackerIds");check(!allowed.contains(flyer.getId().toString())&&!allowed.contains(walk.getId().toString())&&!allowed.contains(unblockable.getId().toString()),"Ground blocker rejected for flying/islandwalk/unblockable");Map<String,Object> spider=options.stream().filter(x->reach.getId().toString().equals(x.get("blockerId"))).findFirst().orElseThrow();check(((Collection<?>)spider.get("legalAttackerIds")).contains(flyer.getId().toString()),"Reach remains legal against flying");s.human.declareBlocker(s.human.getId(),blocker.getId(),menace.getId(),s.game,false);check(s.game.getCombat().findGroup(menace.getId()).getBlockers().contains(blocker.getId()),"Native pairwise menace assignment initially possible");check(!s.game.getCombat().findGroup(menace.getId()).checkBlockRestrictions(s.game,s.human,0),"Native group legality rejects lone menace blocker");
        }else{
            CombatGroup group=combatSetup(s,attacker,"C14".equals(scenario)?new Card[0]:new Card[]{blocker});
            if("C15".equals(scenario)||"C16".equals(scenario)){permanent(s,blocker).sacrifice(null,s.game);check(group.getBlocked()&&group.getBlockers().isEmpty(),"Confirmed blocked state survives losing blocker");damage(s,false);check(s.human.getLife()==("C16".equals(scenario)?14:20),"Only native trample reaches defender after blocker disappears");}
            else if("C17".equals(scenario)){damage(s,true);check(permanent(s,blocker)==null&&permanent(s,attacker)!=null,"First strike kills blocker before retaliation");damage(s,false);check(permanent(s,attacker)!=null&&permanent(s,attacker).getDamage()==0,"First striker receives no regular damage from dead blocker");}
            else if("C18".equals(scenario)){damage(s,true);check(permanent(s,blocker).getDamage()==1,"First double-strike hit marks one damage");damage(s,false);check(permanent(s,blocker)==null&&permanent(s,attacker)==null,"Double striker hits again while surviving blocker retaliates");}
            else if("C19".equals(scenario)){Card aura=card("Rancor");battlefield(s,s.bot.getId(),aura);check(permanent(s,attacker).addAttachment(aura.getId(),aura.getSpellAbility(),s.game),"Native Rancor attaches to lifelink/deathtouch attacker");s.game.applyEffects();damage(s,false);check(s.human.getLife()==17&&s.bot.getLife()==24,"Deathtouch needs one lethal blocker damage; trample3 and lifelink4 are native");check(permanent(s,blocker)==null&&permanent(s,attacker)!=null,"Blocker dies and modified Nighthawk survives");}
            else{damage(s,false);check(s.human.getLife()==18,"Unblocked normal combat deals native power to defender");}
        }
        frame(s,"final-frame");
        List<Map<String,Object>> damageEvents=s.animationEvents.stream().filter(e->"damage".equals(e.get("type"))&&Boolean.TRUE.equals(e.get("combat"))).collect(Collectors.toList());
        int defenderDamage=damageEvents.stream().filter(e->s.human.getId().toString().equals(e.get("targetId"))).mapToInt(e->((Number)e.get("amount")).intValue()).sum();
        int expectedDefender="C14".equals(scenario)?2:"C16".equals(scenario)?6:"C19".equals(scenario)?3:0;
        check(defenderDamage==expectedDefender,"Projected positive native damage events match actual defender loss");
        if("C15".equals(scenario)||"C20".equals(scenario))check(damageEvents.isEmpty(),"No fabricated combat hit when no native damage occurred");
        for(Map<String,Object> e:damageEvents)check(e.get("sourceId")!=null&&e.get("targetId")!=null&&((Number)e.get("amount")).intValue()>0,"Every combat animation event retains real positive source/target amount");
        if("C17".equals(scenario))check(damageEvents.size()==1&&"FIRST_COMBAT_DAMAGE".equals(damageEvents.get(0).get("step")),"First strike event never invents regular retaliation");
        if("C18".equals(scenario))check(damageEvents.stream().filter(e->attacker.getId().toString().equals(e.get("sourceId"))).map(e->String.valueOf(e.get("step"))).collect(Collectors.toSet()).equals(new HashSet<>(Arrays.asList("FIRST_COMBAT_DAMAGE","COMBAT_DAMAGE"))),"Double-strike source retains separate native damage-step identities");
    }

    static ActivatedAbility activated(EngineBridge.Session s,Card c,String rule){return(ActivatedAbility)permanent(s,c).getAbilities().stream().filter(a->a instanceof ActivatedAbility&&a.getRule().contains(rule)).findFirst().orElseThrow();}
    static void costs(String scenario)throws Exception{
        EngineBridge.Session s=setup();
        if("C21".equals(scenario)||"C22".equals(scenario)){
            Card strider=card("Woe Strider"),bear=card("Grizzly Bears");battlefield(s,s.human.getId(),strider,bear);clearSetup(s);ActivatedAbility a=activated(s,strider,"Scry");
            if("C21".equals(scenario)){boolean success=run(s,()->s.human.activateAbility(a,s.game),(ss,p)->{check(p.get("cancelChoice")!=null&&"pending_action".equals(p.get("cancelScope")),"Before sacrifice native cancellation is explicitly offered");answer(ss,p,obj(p.get("cancelChoice")));});check(!success&&permanent(s,bear)!=null&&s.game.getStack().isEmpty(),"Cancellation preserves unpaid creature/stack");}
            else{check(run(s,()->s.human.activateAbility(a,s.game),target(bear.getId())),"Sacrifice activation commits through offered UUID");check(permanent(s,bear)==null&&s.human.getGraveyard().contains(bear.getId()),"Sacrifice is an actual irreversible native cost");library(s,"Island");resolve(s,(ss,p)->{check(!"pending_action".equals(p.get("cancelScope")),"Resolved scry never offers activation undo");answer(ss,p,choice(p,"done"));});check(permanent(s,bear)==null,"Finishing effect cannot restore paid cost");}
        }else if("C23".equals(scenario)){
            Card looter=card("Merfolk Looter"),discard=card("Mountain");battlefield(s,s.human.getId(),looter);((PermanentImpl)permanent(s,looter)).removeSummoningSickness();hand(s,discard);library(s,"Island");clearSetup(s);check(run(s,()->s.human.activateAbility(activated(s,looter,"Draw"),s.game),null),"Tap ability activates natively");check(permanent(s,looter).isTapped(),"Tap cost is committed before resolution");resolve(s,target(discard.getId()));check(s.human.getGraveyard().contains(discard.getId())&&s.human.getHand().size()==1,"Native loot draws then discards chosen offered card");
        }else if("C24".equals(scenario)){
            Card city=card("City of Brass"),reef=card("Shivan Reef");battlefield(s,s.human.getId(),city,reef);clearSetup(s);List<ActivatedAbility> abilities=new ArrayList<>(s.human.usableManaAbilities(permanent(s,reef),s.game).values());s.query(PlayerQueryEvent.chooseAbilityEvent(s.human.getId(),"Choose mana ability",reef.getName(),abilities));Set<String> actual=new HashSet<>();for(Map<String,Object> c:list(s.prompt.get("choices")))for(Object color:(Collection<?>)c.get("manaColors"))actual.add(color.toString());check(actual.equals(new HashSet<>(Arrays.asList("C","U","R"))),"Mana projection exposes exactly native Reef colors");ActivatedAbility a=s.human.usableManaAbilities(permanent(s,city),s.game).values().iterator().next();check(run(s,()->s.human.activateAbility(a,s.game),(ss,p)->{check("color".equals(obj(p.get("manaWheel")).get("kind")),"Native color prompt includes source wheel");answer(ss,p,choice(p,"Blue"));}),"Native mana-color selection accepted");settle(s,null);check(s.human.getManaPool().getBlue()==1&&s.human.getLife()==19,"Chosen Blue mana and City damage both apply");
        }else if("C25".equals(scenario)){
            Card ball=card("Fireball");final int[] stage={0};cast(s,ball,Mana.RedMana(7),(ss,p)->{if("amount".equals(p.get("type"))||"get_amount".equals(p.get("type"))){amount(ss,p,6);stage[0]++;}else if("pick_target".equals(p.get("type"))){if(stage[0]==1){answer(ss,p,choice(p,ss.bot.getId().toString()));stage[0]++;}else answer(ss,p,choice(p,"done"));}else throw new AssertionError("Unexpected X prompt "+p);});resolve(s,null);check(stage[0]==2&&s.bot.getLife()==14,"Native X6 costs seven mana and deals six");
        }
        frame(s,"final-frame");
    }
    static void promptKinds(String scenario)throws Exception{
        EngineBridge.Session s=setup();
        if("C26".equals(scenario)){
            library(s,"Mountain","Forest","Island","Swamp","Plains");Card fof=card("Fact or Fiction");cast(s,fof,Mana.BlueMana(4),null);final Set<UUID> chosen=new HashSet<>();resolve(s,(ss,p)->{check(p.get("pile1")!=null&&p.get("pile2")!=null,"Real Fact or Fiction exposes both native piles");for(Map<String,Object> c:list(p.get("pile1")))chosen.add(UUID.fromString(c.get("id").toString()));check(list(p.get("pile1")).size()+list(p.get("pile2")).size()==5,"Exactly five real revealed cards are separated");answer(ss,p,choice(p,"pile1"));});check(s.human.getHand().containsAll(chosen)&&s.human.getHand().size()==chosen.size(),"Selected native pile becomes actual hand");check(s.human.getGraveyard().size()==6-chosen.size(),"Other pile plus resolved spell enter actual graveyard");
        }else if("C27".equals(scenario)){
            Card small=card("Grizzly Bears"),big=card("Colossal Dreadmaw"),artifact=card("Bonesplitter"),aura=card("Rancor");battlefield(s,s.human.getId(),small,big,artifact,aura);permanent(s,big).addAttachment(aura.getId(),aura.getSpellAbility(),s.game);clearSetup(s);Card command=card("Austere Command");final Set<String> modes=new HashSet<>();cast(s,command,Mana.WhiteMana(6),(ss,p)->{check("mode".equals(p.get("type"))||"choose_mode".equals(p.get("type")),"Modal card asks native mode choices");Map<String,Object> c=byLabel(p,modes.isEmpty()?"artifacts":"3 or less");modes.add(c.get("id").toString());answer(ss,p,c);});resolve(s,null);check(modes.size()==2,"Two distinct offered modes selected");check(permanent(s,small)==null&&permanent(s,artifact)==null,"Selected artifact/small-creature modes destroy matching objects");check(permanent(s,big)!=null&&permanent(s,aura)!=null,"Unselected large-creature/enchantment classes survive");
        }else{
            library(s,"Island");Card morph=card("Manamorphose");cast(s,morph,Mana.RedMana(2),null);final List<Integer> applied=new ArrayList<>();resolve(s,(ss,p)->{check("multi_amount".equals(p.get("type")),"Real spell requests native multi-color distribution");List<Integer> values=new ArrayList<>();for(Map<String,Object> m:list(p.get("amountMessages"))){String label=String.valueOf(m.get("message"));values.add(label.contains("B")||label.contains("G")?1:0);}check(values.stream().mapToInt(Integer::intValue).sum()==2,"Distribution targets actual offered B/G symbols");applied.addAll(values);distribute(ss,p,values);});check(s.human.getManaPool().getBlack()==1&&s.human.getManaPool().getGreen()==1,"Native distribution creates exactly B+G");check(s.human.getHand().size()==1,"Draw following mana distribution still resolves");
        }
        frame(s,"final-frame");
    }
    static EngineBridge.Session room(int count,boolean commander){
        JsonObject deck=JsonParser.parseString(commander?"{\"main\":[{\"name\":\"Mountain\",\"count\":99}],\"commander\":[{\"name\":\"Krenko, Mob Boss\",\"count\":1}]}":"{\"main\":[{\"name\":\"Plains\",\"count\":60}]}").getAsJsonObject();JsonObject body=new JsonObject();body.addProperty("format",commander?"Commander":"Modern");body.addProperty("recordingPort",0);JsonArray seats=new JsonArray();for(int i=0;i<count;i++){JsonObject seat=new JsonObject();seat.addProperty("seatId","core-seat-"+i);seat.addProperty("name","Core human "+i);seat.addProperty("type","human");seat.add("deck",deck);seats.add(seat);}body.add("seats",seats);EngineBridge.Session s=new EngineBridge.Session(body,true);sessions.add(s);initialize(s);return s;
    }
    static void privacy(String scenario)throws Exception{
        int count="C29".equals(scenario)?4:6;EngineBridge.Session s=room(count,true);check(s.game.getNumPlayers()==count&&s.match.getPlayers().size()==count,"Commander seats have real initialized match/game players");List<Card> secrets=new ArrayList<>();for(EngineBridge.Session view:s.perspectives){Card secret=card("Mountain");s.game.cheat(view.human.getId(),NONE,Collections.singletonList(secret),Collections.emptyList(),NONE,NONE,NONE);secrets.add(secret);}
        for(int i=0;i<count;i++){EngineBridge.Session view=s.perspectives.get(i);for(int j=0;j<count;j++){Map<String,Object> c=view.card(secrets.get(j));check(i==j?"Mountain".equals(c.get("name")):Boolean.TRUE.equals(c.get("hidden")),"Each native human perspective sees exactly its own hand");}Card opponent=secrets.get((i+1)%count);view.query(PlayerQueryEvent.targetEvent(view.human.getId(),"Choose hidden card",Collections.singleton(opponent.getId()),true));check("Hidden card".equals(list(view.prompt.get("choices")).get(0).get("label")),"Opponent name is redacted in native target label");}
        Card looked=secrets.get(1);s.game.getState().getLookedAt(s.human.getId()).put("core-private",new CardsImpl(looked));check("Mountain".equals(s.card(looked).get("name")),"Only actual looked-at owner obtains entitlement");check(Boolean.TRUE.equals(s.perspectives.get(2).card(looked).get("hidden")),"Third human gets no private look entitlement");s.game.getState().getLookedAt(s.human.getId()).remove("core-private");s.game.getState().getRevealed().put("core-public",new CardsImpl(looked));for(EngineBridge.Session view:s.perspectives)check("Mountain".equals(view.card(looked).get("name")),"Public reveal is entitled in every perspective");for(int i=0;i<count;i++)frame(s.perspectives.get(i),"perspective-"+i);
    }
    static void regression(String scenario)throws Exception{
        EngineBridge.Session s=setup();
        if("C31".equals(scenario)){
            Card wall=card("Wall of Omens");battlefield(s,s.human.getId(),wall);clearSetup(s);library(s,"Island","Forest");Card mutation=card("Darksteel Mutation");cast(s,mutation,Mana.WhiteMana(2),target(wall.getId()));resolve(s,null);check(permanent(s,wall).getPower().getValue()==0&&permanent(s,wall).getToughness().getValue()==1,"Mutation really suppresses Wall abilities and changes base stats");Card shift=card("Cloudshift");cast(s,shift,Mana.WhiteMana(1),target(wall.getId()));resolve(s,null);settle(s,null);check(s.human.getHand().size()==1,"Unsuppressed Wall ETB draws after immediate blink");check(permanent(s,wall).getToughness().getValue()==4&&s.human.getGraveyard().contains(mutation.getId()),"New Wall restores printed characteristics; unattached Aura reaches graveyard");
        }else if("C32".equals(scenario)){
            Card bear=card("Mind Stone");s.human.getUserData().setManaPoolAutomatic(false);s.human.getManaPool().setAutoPayment(false);final int[] paid={0};cast(s,bear,colors(0,1,0,1,1,0),(ss,p)->{check("play_mana".equals(p.get("type")),"Manual native payment requests explicit mana");Map<String,Object> offered=choice(p,paid[0]==0?"mana-G":"mana-U");check("mana".equals(offered.get("responseType")),"Mana response type comes from offered pool choice");answer(ss,p,offered);paid[0]++;});check(paid[0]==2&&s.human.getManaPool().count()==1&&s.human.getManaPool().getRed()==1,"Two offered payments spend selected G/U and leave Red unspent");resolve(s,null);check(permanent(s,bear)!=null,"Manually paid artifact resolves into real permanent");
        }else if("C33".equals(scenario)){
            Card discard=card("Mountain"),voice=card("Tormenting Voice"),counter=card("Counterspell");hand(s,discard);cast(s,voice,Mana.RedMana(2),target(discard.getId()));check(s.human.getGraveyard().contains(discard.getId()),"Additional discard is paid before spell enters stack");UUID spell=s.game.getStack().peek().getId();cast(s,counter,Mana.BlueMana(2),target(spell));resolve(s,null);check(s.game.getStack().isEmpty()&&s.human.getGraveyard().contains(voice.getId()),"Native Counterspell removes targeted draw spell");check(s.human.getGraveyard().contains(discard.getId())&&s.human.getHand().isEmpty(),"Countering spell never refunds its discard cost or draws");
        }
        frame(s,"final-frame");
    }
    static void thresholdCombat(String scenario)throws Exception{
        EngineBridge.Session s=setup();Card angel=card("Angel of Vitality");
        if("C36".equals(scenario)){
            Card bear=card("Grizzly Bears");battlefield(s,s.human.getId(),bear);clearSetup(s);permanent(s,bear).addCounters(CounterType.P1P1.createInstance(1000000),s.human.getId(),null,s.game);s.game.applyEffects();check(permanent(s,bear).getPower().getValue()==1000002,"One million native counters remain exact aggregate values");Card growth=card("Giant Growth");cast(s,growth,Mana.GreenMana(1),target(bear.getId()));resolve(s,null);Map<String,Object> view=s.card(permanent(s,bear));check("1000005".equals(view.get("power"))&&"1000005".equals(view.get("toughness")),"Large live P/T stays exact through a native temporary spell boost");check(((Number)obj(view.get("counters")).get("+1/+1")).intValue()==1000000,"Projection never wraps or truncates the large counter value");frame(s,"large-values");s.game.getTurn().setPhase(new EndPhase());s.game.getPhase().setStep(new CleanupStep());run(s,()->{s.game.getPhase().getStep().beginStep(s.game,s.human.getId());s.game.applyEffects();s.game.checkStateAndTriggered();return true;},null);check(permanent(s,bear).getPower().getValue()==1000002&&permanent(s,bear).getCounters(s.game).getCount(CounterType.P1P1)==1000000,"Native cleanup ends temporary boost while keeping every counter");
        }else if("C37".equals(scenario)){
            Card goyf=card("Tarmogoyf"),bolt=card("Lightning Bolt"),land=card("Mountain"),bear=card("Grizzly Bears");battlefield(s,s.human.getId(),goyf);s.game.cheat(s.human.getId(),NONE,NONE,Collections.emptyList(),Arrays.asList(bolt,land),NONE,NONE);s.game.cheat(s.bot.getId(),NONE,NONE,Collections.emptyList(),Collections.singletonList(bear),NONE,NONE);s.game.applyEffects();Map<String,Object> before=s.card(permanent(s,goyf));check("3".equals(before.get("power"))&&"4".equals(before.get("toughness")),"Native characteristic-defining ability counts three types across both graveyards");Map<String,Object> printing=new LinkedHashMap<>(obj(before.get("printing")));frame(s,"variable-three-types");check(bear.moveToExile(null,"Core variable characteristic",null,s.game),"Native zone change removes the opponent's only creature type from graveyard");s.game.applyEffects();Map<String,Object> after=s.card(permanent(s,goyf));check("2".equals(after.get("power"))&&"3".equals(after.get("toughness")),"Live CDA values update after the other graveyard changes");check(printing.equals(obj(after.get("printing"))),"Original native printing metadata remains separate from live CDA values");
        }else if("C34".equals(scenario)){
            Card nighthawk=card("Vampire Nighthawk"),drake=card("Wind Drake");s.bot.setLife(24,s.game,null);battlefield(s,s.bot.getId(),angel,nighthawk);battlefield(s,s.human.getId(),drake);clearSetup(s);
            s.game.getTurn().setPhase(new CombatPhase());s.game.getPhase().setStep(new DeclareBlockersStep());s.game.getState().setActivePlayerId(s.bot.getId());s.game.getState().setPriorityPlayerId(s.human.getId());s.game.getCombat().getDefenders().add(s.human.getId());s.game.getCombat().setAttacker(s.bot.getId());for(Card a:Arrays.asList(angel,nighthawk))check(s.game.getCombat().addAttackerToCombat(a.getId(),s.human.getId(),s.game),"Native flying attacker added");s.human.declareBlocker(s.human.getId(),drake.getId(),angel.getId(),s.game,false);s.game.getCombat().acceptBlockers(s.game);check(permanent(s,angel).getToughness().getValue()==2&&s.bot.getLife()==24,"Angel begins combat below native threshold");damage(s,false);check(s.bot.getLife()==27&&s.human.getLife()==18,"Simultaneous Nighthawk lifelink is amplified once by Angel");check(permanent(s,angel)!=null&&permanent(s,angel).getDamage()==2&&permanent(s,angel).getToughness().getValue()==4,"Life gain turns lethal marked2 into nonlethal4toughness before SBA");check(permanent(s,drake)==null,"Assignment before threshold dealt exactly2 to blocker");
        }else{
            s.human.setLife(25,s.game,null);battlefield(s,s.human.getId(),angel);clearSetup(s);Card shock=card("Shock"),bolt=card("Lightning Bolt");cast(s,shock,Mana.RedMana(1),target(angel.getId()));resolve(s,null);check(permanent(s,angel)!=null&&permanent(s,angel).getDamage()==2&&permanent(s,angel).getToughness().getValue()==4,"At25life Angel survives two marked damage");cast(s,bolt,Mana.RedMana(1),target(s.human.getId()));resolve(s,null);check(s.human.getLife()==22&&permanent(s,angel)==null&&s.human.getGraveyard().contains(angel.getId()),"Losing threshold makes old marked damage lethal under native SBA");
        }
        frame(s,"final-frame");
    }
    public static void main(String[] args)throws Exception{
        Thread.currentThread().setName("GAME core driver");Path root=Paths.get(args[0]);String scenario=args[1];currentScenario=scenario;output=Paths.get(args[2]);Files.createDirectories(output);long started=System.nanoTime();org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(CoreMechanicsFixture.class.getClassLoader());Map<String,Object> result=new LinkedHashMap<>();result.put("scenarioId",scenario);result.put("evidenceType","deterministic_native");result.put("initialization","Game.cheat initial zones/resources; native operations/effects/costs/SBA, no production shuffle or full match");int exit=0;
        try{configureBudgets();int n=Integer.parseInt(scenario.substring(1));if(n<=8)characteristics(scenario);else if(n<=13)triggers(scenario);else if(n<=20)combat(scenario);else if(n<=25)costs(scenario);else if(n<=28)promptKinds(scenario);else if(n<=30)privacy(scenario);else if(n<=33)regression(scenario);else thresholdCombat(scenario);result.put("status","pass");}
        catch(Throwable ex){exit=1;Throwable cause=ex;while(cause.getCause()!=null)cause=cause.getCause();result.put("status",cause instanceof CoreBudgetExceeded?"budget_exceeded":"fail");result.put("error",ex.toString());java.io.StringWriter sw=new java.io.StringWriter();ex.printStackTrace(new java.io.PrintWriter(sw));Files.writeString(output.resolve("exception.txt"),sw.toString());}
        finally{GAME.shutdownNow();for(EngineBridge.Session s:sessions){try{if(s.prompt!=null)Files.writeString(output.resolve("last-prompt-"+sessions.indexOf(s)+".json"),EngineBridge.JSON.toJson(s.prompt));frame(s,"last-session-"+sessions.indexOf(s));}catch(Throwable ex){result.put("cleanupError",ex.toString());}finally{try{s.stop();}catch(Throwable ex){result.put("stopError",ex.toString());}}}GAME.awaitTermination(1,TimeUnit.SECONDS);result.put("appliedBudgets",appliedBudgets());result.put("peakNativeBattlefieldAndStackObjects",peakObjects);result.put("checks",checks);result.put("attemptedActions",attempts);result.put("acceptedActions",accepted);result.put("nativeEvents",nativeEventTotal());result.put("nativeEventTypes",eventTypes());result.put("eventCountScope","Fired GameEvents since fixture initialize; excludes constructor, simulations and playable-action calculation; retained animation deque is a separate bounded presentation window");result.put("retainedAnimationEvents",sessions.stream().mapToInt(s->s.animationEvents.size()).sum());result.put("gameThreads",Thread.getAllStackTraces().keySet().stream().filter(t->t.getName().startsWith("GAME")&&t!=Thread.currentThread()).map(t->EngineBridge.map("name",t.getName(),"alive",t.isAlive(),"state",t.getState().toString())).collect(Collectors.toList()));result.put("durationMs",TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-started));Files.writeString(output.resolve("trace.json"),EngineBridge.JSON.toJson(trace));Files.writeString(output.resolve("result.json"),EngineBridge.JSON.toJson(result));System.out.println(EngineBridge.JSON.toJson(result));}
        System.exit(exit);
    }
}
