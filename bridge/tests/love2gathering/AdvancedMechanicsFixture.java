package love2gathering;

import com.google.gson.*;
import mage.Mana;
import mage.abilities.*;
import mage.abilities.effects.common.*;
import mage.abilities.keyword.*;
import mage.cards.*;
import mage.constants.*;
import mage.counters.CounterType;
import mage.game.*;
import mage.game.events.*;
import mage.game.permanent.*;
import mage.game.permanent.token.*;
import mage.game.stack.*;
import mage.target.targetpointer.FixedTarget;
import mage.util.Copier;
import mage.watchers.Watcher;
import mage.util.functions.EmptyCopyApplier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.*;
import java.util.stream.*;

/** Initial test zones/resources only are prepared; all transformations/effects are native XMage operations. */
public final class AdvancedMechanicsFixture {
    static Path output;
    static double stepSeconds=12;
    static long maxNativeEvents=10000,maxAcceptedActions=100,maxNativeResolutions=80;
    static long budgetLong(String name,long fallback){
        String property="love2gathering.test."+name,value=System.getProperty(property);
        long result=value==null?fallback:Long.parseLong(value);
        if(result<0)throw new IllegalArgumentException(property+" must be nonnegative");
        return result;
    }
    static void configureBudgets(){
        stepSeconds=Double.parseDouble(System.getProperty("love2gathering.test.stepSeconds","12"));
        if(!Double.isFinite(stepSeconds)||stepSeconds<=0||stepSeconds>TimeUnit.NANOSECONDS.toSeconds(Long.MAX_VALUE/2))throw new IllegalArgumentException("love2gathering.test.stepSeconds must be finite, positive and representable in nanoseconds");
        maxNativeEvents=budgetLong("nativeEvents",10000);
        maxAcceptedActions=budgetLong("acceptedActions",100);
        maxNativeResolutions=budgetLong("nativeResolutions",80);
    }
    static Map<String,Object> appliedBudgets(){return EngineBridge.map("stepSeconds",stepSeconds,"nativeEvents",maxNativeEvents,"acceptedActions",maxAcceptedActions,"nativeResolutions",maxNativeResolutions,"nativeEventScope",EVENT_SCOPE);}
    static final Map<Game,AdvancedEventCounter> EVENT_COUNTS=Collections.synchronizedMap(new IdentityHashMap<>());
    static final class AdvancedEventCounter {
        final AtomicLong total=new AtomicLong();
        final Map<String,AtomicLong> types=new ConcurrentHashMap<>();
        volatile Map<String,Object> last;
    }
    /** Observations live outside serialized native state so bookmarks do not reset counts. */
    static final class AdvancedNativeWatcher extends Watcher {
        AdvancedNativeWatcher(){super(WatcherScope.GAME);}
        @Override public void watch(GameEvent event,Game game){
            if(game.isSimulation()||game.inCheckPlayableState())return;
            AdvancedEventCounter counter=EVENT_COUNTS.get(game);if(counter==null)return;
            long sequence=counter.total.incrementAndGet();counter.types.computeIfAbsent(event.getType().name(),key->new AtomicLong()).incrementAndGet();
            counter.last=EngineBridge.map("sequence",sequence,"type",event.getType().name(),"eventClass",event.getClass().getName(),"batch",event instanceof BatchEvent);
            if(sequence>maxNativeEvents)throw new BudgetReached("Native fired-event test budget exceeded "+maxNativeEvents);
        }
        @Override public AdvancedNativeWatcher copy(){return new AdvancedNativeWatcher();}
    }
    static void observe(Game game){EVENT_COUNTS.put(game,new AdvancedEventCounter());game.getState().addWatcher(new AdvancedNativeWatcher());}
    static long eventTotal(){synchronized(EVENT_COUNTS){return EVENT_COUNTS.values().stream().mapToLong(counter->counter.total.get()).sum();}}
    static Map<String,Long> eventTypes(){Map<String,Long> result=new TreeMap<>();synchronized(EVENT_COUNTS){for(AdvancedEventCounter counter:EVENT_COUNTS.values())counter.types.forEach((type,count)->result.merge(type,count.get(),Long::sum));}return result;}
    static Map<String,Object> lastEvent(){AdvancedEventCounter counter=current==null?null:EVENT_COUNTS.get(current.game);return counter==null?null:counter.last;}
    static final String EVENT_SCOPE="Fired native GameEvents after fixture Session initialization, including prepared zones/actions/cleanup; excludes constructor, simulations and playable-action calculation. Counts are separate from retained structured logs and animation window.";

    static int checks,accepted,resolutions;
    static final List<Map<String,Object>> trace=new ArrayList<>();
    static EngineBridge.Session current;
    static ExecutorService gameWorker;
    @SuppressWarnings("unchecked") static List<Map<String,Object>> choices(Map<String,Object> p){return(List<Map<String,Object>>)p.getOrDefault("choices",Collections.emptyList());}
    static void require(boolean b,String label){if(!b)throw new AssertionError(label);checks++;}
    static Card card(String name){return TriggerFixture.card(name);}
    static EngineBridge.Session setup()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();current=s;observe(s.game);
        java.lang.reflect.Field cursor=GameImpl.class.getDeclaredField("playerList");cursor.setAccessible(true);cursor.set(s.game,s.game.getState().getPlayerList(s.human.getId()));
        gameWorker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"GAME advanced mechanics");t.setDaemon(true);return t;});return s;
    }
    static void save(String name,Object value)throws Exception{Files.writeString(output.resolve(name),EngineBridge.JSON.toJson(value)+"\n");}
    static Map<String,Object> byLabel(Map<String,Object> p,String value){return choices(p).stream().filter(c->value.equalsIgnoreCase(String.valueOf(c.get("label")))).findFirst().orElse(null);}
    static Map<String,Object> byId(Map<String,Object> p,UUID id){return choices(p).stream().filter(c->id.toString().equals(String.valueOf(c.get("id")))).findFirst().orElse(null);}
    static Map<String,Object> replacement(Map<String,Object> p){
        String message=String.valueOf(p.get("message")).toLowerCase(Locale.ROOT);
        if(!message.contains("replacement")&&!message.contains("apply first")&&!message.contains("effect to apply"))return null;
        for(String label:Arrays.asList("Parallel Lives","Doubling Season","Academy Manufactor","Branching Evolution","Nine Lives","Vigor")){
            Map<String,Object> c=choices(p).stream().filter(x->String.valueOf(x.get("label")).contains(label)).findFirst().orElse(null);if(c!=null)return c;
        }return null;
    }
    static <T>T run(Callable<T> task,Function<Map<String,Object>,Map<String,Object>> policy)throws Exception{
        long old=current.prompt==null?-1:((Number)current.prompt.get("id")).longValue();Future<T> f=gameWorker.submit(task);long until=System.nanoTime()+(long)(stepSeconds*1000000000d);
        while(!f.isDone()&&System.nanoTime()<until){
            Map<String,Object> p=current.prompt;
            if(p!=null&&((Number)p.get("id")).longValue()!=old){
                old=((Number)p.get("id")).longValue();save("last-prompt.json",p);
                Map<String,Object> chosen=policy==null?null:policy.apply(p);if(chosen==null)chosen=replacement(p);
                require(chosen!=null,"Uncovered native prompt: "+EngineBridge.JSON.toJson(p));
                Object actionable=p.get("actionable");if("uuid".equals(chosen.get("responseType"))&&actionable instanceof Collection)require(((Collection<?>)actionable).contains(chosen.get("id")),"UUID answer remains in present native actionable set");
                if(accepted>=maxAcceptedActions)throw new BudgetReached("Native accepted-response test budget reached "+maxAcceptedActions);
                trace.add(EngineBridge.map("promptId",old,"type",p.get("type"),"message",p.get("message"),"choice",chosen));
                ActionabilityFixture.answer(current,p,chosen);accepted++;save("action-trace.json",trace);
            }Thread.sleep(2);
        }
        if(!f.isDone()){f.cancel(true);throw new BudgetReached("Native task exceeded stepSeconds="+stepSeconds);}
        try{return f.get();}catch(ExecutionException e){Throwable cause=e.getCause();if(cause instanceof Error)throw(Error)cause;if(cause instanceof Exception)throw(Exception)cause;throw e;}
    }
    static <T>T run(Callable<T> task)throws Exception{return run(task,null);}
    static void field(Card...cards)throws Exception{run(()->{current.game.cheat(current.human.getId(),TriggerFixture.NONE,TriggerFixture.NONE,Arrays.stream(cards).map(c->new PutToBattlefieldInfo(c,false)).collect(Collectors.toList()),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);current.game.applyEffects();return true;});}
    static void enter(Card c)throws Exception{enter(c,null);}
    static void enter(Card c,Function<Map<String,Object>,Map<String,Object>> policy)throws Exception{current.game.loadCards(Collections.singleton(c),current.human.getId());c.setZone(Zone.OUTSIDE,current.game);require(run(()->c.putOntoBattlefield(current.game,Zone.OUTSIDE,null,current.human.getId()),policy),"Card actually enters through native zone transition: "+c.getName());current.game.applyEffects();}
    static Permanent permanent(Card c){Permanent p=current.game.getPermanent(c.getId());require(p!=null,"Native permanent exists: "+c.getName());return p;}
    static Ability source(Permanent p){return p.getSpellAbility();}
    static void resetTriggers(){current.game.getStack().clear();current.game.getState().clearTriggeredAbilities();}
    static void nativeResolve()throws Exception{if(resolutions>=maxNativeResolutions)throw new BudgetReached("Native resolution test budget reached "+maxNativeResolutions);java.lang.reflect.Method m=GameImpl.class.getDeclaredMethod("resolve");m.setAccessible(true);try{m.invoke(current.game);resolutions++;}catch(java.lang.reflect.InvocationTargetException e){if(e.getCause()instanceof Error)throw(Error)e.getCause();if(e.getCause()instanceof Exception)throw(Exception)e.getCause();throw e;}}
    static void settle(int budget)throws Exception{settle(budget,null);}
    static void settle(int budget,Function<Map<String,Object>,Map<String,Object>> policy)throws Exception{run(()->{current.game.checkStateAndTriggered();return true;},policy);int n=0;while(!current.game.getStack().isEmpty()){
        require(++n<=budget,"Native finite stack stays inside resolution budget "+budget);run(()->{nativeResolve();current.game.checkStateAndTriggered();return true;},policy);
    }}
    static Permanent mutate(Permanent host,String name,boolean under)throws Exception{
        Card mutation=card(name);current.game.loadCards(Collections.singleton(mutation),current.human.getId());mutation.setZone(Zone.STACK,current.game);
        MutateAbility ability=(MutateAbility)mutation.getAbilities().stream().filter(MutateAbility.class::isInstance).findFirst().orElseThrow();ability=ability.copy();ability.setControllerId(current.human.getId());ability.getTargets().get(0).addTarget(host.getId(),ability,current.game);
        Spell spell=new Spell(mutation,ability,current.human.getId(),Zone.HAND,current.game);current.game.getStack().push(current.game,spell);
        run(()->{nativeResolve();return true;},p->byLabel(p,under?"Under":"Over"));
        require(current.game.getStack().getStackObject(spell.getId())==null,"Native mutating spell actually finishes resolution");current.game.applyEffects();return current.game.getPermanent(host.getId());
    }
    static Spell stack(String name,UUID target)throws Exception{return stack(name,target,current.human.getId());}
    static Spell stack(String name,UUID target,UUID controller)throws Exception{
        Card c=card(name);current.game.loadCards(Collections.singleton(c),controller);c.setZone(Zone.STACK,current.game);SpellAbility a=c.getSpellAbility().copy();a.setControllerId(controller);
        if(target!=null){require(!a.getTargets().isEmpty(),"Native spell actually offers a target: "+name);a.getTargets().get(0).addTarget(target,a,current.game);}
        Spell spell=new Spell(c,a,controller,Zone.HAND,current.game);current.game.getStack().push(current.game,spell);return spell;
    }
    static List<Permanent> controlled(){return current.game.getBattlefield().getAllActivePermanents(current.human.getId());}
    static List<Permanent> tokens(){return controlled().stream().filter(Permanent::isToken).collect(Collectors.toList());}
    static void token(Token token,int count)throws Exception{Card witness=card("Grizzly Bears");current.game.loadCards(Collections.singleton(witness),current.human.getId());Ability src=witness.getSpellAbility();src.setControllerId(current.human.getId());run(()->token.putOntoBattlefield(count,current.game,src,current.human.getId()));current.game.applyEffects();}
    static void snapshot(String name)throws Exception{current.publish();save(name,current.snapshot);}
    static void pt(Permanent p,int power,int toughness){require(p.getPower().getValue()==power&&p.getToughness().getValue()==toughness,"Native P/T expected "+power+"/"+toughness+", got "+p.getPower()+"/"+p.getToughness());Map<String,Object> view=current.card(p);require(String.valueOf(power).equals(view.get("power"))&&String.valueOf(toughness).equals(view.get("toughness")),"Bridge projects the native current P/T");}
    static void mutateCase(String id)throws Exception{
        setup();Card bear=card("Grizzly Bears");Card warden=null;
        if(id.equals("adv-mutate-no-etb")){warden=card("Soul Warden");field(warden,bear);resetTriggers();}else field(bear);
        Permanent host=permanent(bear);UUID original=host.getId();int life=current.human.getLife();
        if(id.equals("adv-mutate-counters-damage")){host.addCounters(CounterType.P1P1.createInstance(2),current.human.getId(),null,current.game);host.setTapped(true);host.damage(1,host.getSpellAbility(),current.game);}
        boolean under=id.equals("adv-mutate-under");host=mutate(host,"Gemrazer",under);require(host.getId().equals(original)&&host.getMutateCount()==1,"Merging preserves original object ID and records component");
        if(under){pt(host,2,2);require(host.getAbilities().contains(TrampleAbility.getInstance())&&host.getAbilities().contains(ReachAbility.getInstance()),"Under component grants both printed abilities");}
        else if(id.equals("adv-mutate-counters-damage")){pt(host,6,6);require(host.isTapped()&&host.getDamage()==1&&host.getCounters(current.game).getCount(CounterType.P1P1)==2,"Merge retains tapped state, marked damage and counters");}
        else pt(host,4,4);
        if(id.equals("adv-mutate-no-etb")){settle(8);require(current.human.getLife()==life,"Mutate does not retrigger Soul Warden enters ability");}
        if(id.equals("adv-mutate-repeat")){host=mutate(host,"Sea-Dasher Octopus",true);require(host.getMutateCount()==2&&host.getMutateForView().size()==3,"Two native merges retain all three component identities");pt(host,4,4);require(host.getAbilities().stream().anyMatch(a->a.getRule().contains("combat damage")&&a.getRule().contains("draw")),"Under Octopus grants real native combat-draw ability");}
        if(id.equals("adv-mutate-bounce")){UUID merged=host.getId();Permanent finalHost=host;run(()->current.human.moveCards(finalHost,Zone.HAND,bear.getSpellAbility(),current.game));require(current.human.getHand().size()==2&&current.game.getPermanent(merged)==null,"Bouncing merged creature separates both physical cards into hand");}
        if(id.equals("adv-mutate-blink")){stack("Cloudshift",host.getId());settle(10);require(controlled().size()==2&&controlled().stream().allMatch(p->p.getMutateCount()==0),"Blink returns separate unmerged creature cards");require(controlled().stream().map(Permanent::getName).collect(Collectors.toSet()).equals(new HashSet<>(Arrays.asList("Grizzly Bears","Gemrazer"))),"Blink retains both card identities");}
        if(id.equals("adv-mutate-control")){stack("Act of Treason",host.getId(),current.bot.getId());settle(8);host=current.game.getPermanent(original);require(host.getControllerId().equals(current.bot.getId())&&host.getOwnerId().equals(current.human.getId()),"Native Act of Treason changes controller while retaining original owner");Permanent finalHost=host;run(()->current.bot.moveCards(finalHost,Zone.HAND,bear.getSpellAbility(),current.game));require(current.human.getHand().size()==2&&current.bot.getHand().isEmpty(),"Zone change returns all merged cards to original owner after control change");}
        snapshot("final-frame.json");
    }
    static void tokenMutate(String id)throws Exception{
        setup();token(new BearToken(),1);Permanent host=tokens().get(0);UUID idBefore=host.getId();boolean under=id.equals("adv-mutate-token-under");host=mutate(host,"Gemrazer",under);
        require(host.getId().equals(idBefore)&&host.getMutateCount()==1,"Token merge retains native original permanent and component count");require(host.isToken()==under,"Token status follows topmost native component");pt(host,under?2:4,under?2:4);
        if(id.equals("adv-mutate-token-copy")){
            Permanent merged=host;UUID original=host.getId();stack("Rite of Replication",host.getId());settle(10);
            List<Permanent> copies=controlled().stream().filter(p->!p.getId().equals(original)).collect(Collectors.toList());require(copies.size()==1,"Exactly one independent copy token is created");Permanent copy=copies.get(0);pt(copy,4,4);
            require(copy.isToken()&&"Gemrazer".equals(copy.getName()),"Copy of merged creature is a token with top component characteristics");require(current.game.getPermanent(original)!=null&&current.game.getPermanent(original).getMutateCount()==1,"Copy does not overwrite or unlink original merged token host");require(!copy.getId().equals(merged.getId()),"Copied merged object has independent native identity");
        }
        snapshot("final-frame.json");
    }
    static void copyCases(String id)throws Exception{
        setup();Card bear=card("Grizzly Bears");field(bear);Permanent original=permanent(bear);
        if(id.equals("adv-copy-counters-not-copiable")){original.addCounters(CounterType.P1P1.createInstance(3),current.human.getId(),null,current.game);original.damage(1,bear.getSpellAbility(),current.game);original.setTapped(true);current.game.applyEffects();stack("Rite of Replication",original.getId());settle(8);Permanent copy=tokens().get(0);pt(copy,2,2);require(copy.getDamage()==0&&!copy.isTapped()&&copy.getCounters(current.game).isEmpty(),"Permanent copy excludes counters, marked damage and tapped state");pt(original,5,5);}
        if(id.equals("adv-copy-mutate-derived")){original=mutate(original,"Gemrazer",false);original=mutate(original,"Sea-Dasher Octopus",true);original.addCounters(CounterType.P1P1.createInstance(2),current.human.getId(),null,current.game);current.game.applyEffects();stack("Rite of Replication",original.getId());settle(10);Permanent copy=tokens().get(0);pt(copy,4,4);require(copy.getAbilities().stream().anyMatch(a->a.getRule().contains("combat damage")&&a.getRule().contains("draw")),"Copy retains copiable ability from under merged component");require(copy.getCounters(current.game).isEmpty(),"Merged-copy effect excludes counters");require(current.game.getPermanent(bear.getId()).getMutateCount()==2,"Copy leaves both original mutate components intact");}
        if(id.equals("adv-copy-spell")){Spell bolt=stack("Lightning Bolt",current.bot.getId());UUID originalSpell=bolt.getId();run(()->{bolt.createCopyOnStack(current.game,bear.getSpellAbility(),current.human.getId(),false);return true;});require(current.game.getStack().size()==2&&current.game.getStack().peek().isCopy(),"Native stack contains original plus marked spell copy");require(!current.game.getStack().peek().getId().equals(originalSpell),"Spell copy gets distinct stack identity");int life=current.bot.getLife();settle(6);require(current.bot.getLife()==life-6,"Original and copied Bolt each resolve their native damage");}
        if(id.equals("adv-copy-triggered")){Card warden=card("Soul Warden");field(warden);resetTriggers();Card next=card("Grizzly Bears");enter(next);run(()->{current.game.checkStateAndTriggered();return true;});require(current.game.getStack().size()==1,"Exactly one native ETB life trigger is on stack");StackObject trigger=current.game.getStack().peek();run(()->{trigger.createCopyOnStack(current.game,bear.getSpellAbility(),current.human.getId(),false);return true;});require(current.game.getStack().size()==2,"Native trigger copy is separate stack object");int life=current.human.getLife();settle(5);require(current.human.getLife()==life+2,"Copied life-gain trigger resolves independently");}
        if(id.equals("adv-copy-activated")){Card pyro=card("Prodigal Pyromancer");field(pyro);Permanent p=permanent(pyro);((PermanentImpl)p).removeSummoningSickness();ActivatedAbility a=p.getAbilities().stream().filter(x->x instanceof ActivatedAbility&&x.getRule().contains("1 damage")).map(x->(ActivatedAbility)x).findFirst().orElseThrow();require(run(()->current.human.activateAbility(a,current.game),q->byId(q,current.bot.getId())),"Native tap-damage ability pays its actual cost");require(p.isTapped()&&current.game.getStack().size()==1,"One tap cost creates one ability");StackObject ability=current.game.getStack().peek();run(()->{ability.createCopyOnStack(current.game,bear.getSpellAbility(),current.human.getId(),false);return true;});int life=current.bot.getLife();settle(6);require(current.bot.getLife()==life-2&&p.isTapped(),"Ability copy repeats effect without another tap cost");}
        snapshot("final-frame.json");
    }
    @SuppressWarnings("unchecked") static void legendaryCopy()throws Exception{
        setup();Card legend=card("Isamaru, Hound of Konda");enter(legend);UUID original=legend.getId();snapshot("legend-before-copy-frame.json");
        Function<Map<String,Object>,Map<String,Object>> keepCopy=p->{
            if(!String.valueOf(p.get("message")).toLowerCase(Locale.ROOT).contains("legendary rule"))return null;
            List<Permanent> copies=tokens().stream().filter(x->"Isamaru, Hound of Konda".equals(x.getName())).collect(Collectors.toList());require(copies.size()==1,"Native legend choice has exactly one new copy token");
            Map<String,Object> offered=byId(p,copies.get(0).getId());require(offered!=null&&"uuid".equals(offered.get("responseType")),"Keep-copy response uses its actual offered native UUID");return offered;
        };
        stack("Rite of Replication",original);settle(8,keepCopy);
        require(current.human.getGraveyard().contains(original)&&current.game.getPermanent(original)==null,"Native legend SBA puts the original physical card into its owner's graveyard");
        require(controlled().size()==1&&tokens().size()==1,"Exactly one legendary copy survives native SBA");Permanent kept=tokens().get(0);pt(kept,2,2);
        require(kept.getOwnerId().equals(legend.getOwnerId())&&kept.getControllerId().equals(current.human.getId())&&kept.getMutateCount()==0,"Surviving legendary copy keeps native ownership/controller and is not physically merged");
        Card nativeSource=((PermanentToken)kept).getToken().getCopySourceCard();Map<String,Object> view=current.card(kept);Map<String,Object> provenance=(Map<String,Object>)view.get("copySourceCard");
        require(nativeSource!=null&&original.equals(nativeSource.getId())&&provenance!=null&&original.toString().equals(provenance.get("id"))&&"Isamaru, Hound of Konda".equals(provenance.get("name"))&&!view.containsKey("mutate"),"Legendary copy preserves exact native original-card provenance without merged components");
        require(trace.stream().anyMatch(t->String.valueOf(t.get("message")).toLowerCase(Locale.ROOT).contains("legendary rule")&&kept.getId().toString().equals(((Map<?,?>)t.get("choice")).get("id"))),"An actual native legend choice selected the surviving copy");
        save("legend-copy-state.json",EngineBridge.map("originalCardId",original.toString(),"keptCopyId",kept.getId().toString(),"originalInGraveyard",current.human.getGraveyard().contains(original),"copy",view));snapshot("final-frame.json");
    }
    @SuppressWarnings("unchecked") static void mutateAttachments()throws Exception{
        setup();token(new BearToken(),1);final Permanent initial=tokens().get(0);UUID original=initial.getId();Card equipment=card("Bonesplitter");enter(equipment);
        require(run(()->initial.addAttachment(equipment.getId(),equipment.getSpellAbility(),current.game)),"Native fixture attachment places Bonesplitter on the Bear host");
        stack("Rancor",original);settle(8);Permanent aura=controlled().stream().filter(p->"Rancor".equals(p.getName())).findFirst().orElseThrow();
        require(original.equals(aura.getAttachedTo())&&initial.getAttachments().contains(aura.getId()),"Native Rancor spell resolves as an attached Aura");
        run(()->{initial.addCounters(CounterType.P1P1.createInstance(2),current.human.getId(),equipment.getSpellAbility(),current.game);initial.damage(1,equipment.getSpellAbility(),current.game);initial.setTapped(true);current.game.applyEffects();return true;});pt(initial,8,4);
        Set<UUID> attached=new HashSet<>(initial.getAttachments());require(attached.equals(new HashSet<>(Arrays.asList(equipment.getId(),aura.getId()))),"Prepared host has exactly the Equipment and Aura native attachment IDs");snapshot("attachments-before-mutate-frame.json");
        Card gem=card("Gemrazer");run(()->{current.game.cheat(current.human.getId(),TriggerFixture.NONE,Collections.singletonList(gem),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);return true;});
        MutateAbility alternative=(MutateAbility)gem.getAbilities().stream().filter(MutateAbility.class::isInstance).findFirst().orElseThrow();String printedCost=gem.getManaCost().getText(),alternateCost=alternative.getManaCostsToPay().getText();
        current.human.getUserData().setManaPoolAutomatic(true);current.human.getManaPool().setAutoPayment(true);current.human.getManaPool().addMana(Mana.GreenMana(3),current.game,gem.getSpellAbility());int manaBefore=current.human.getManaPool().count();
        require(manaBefore==3&&"{3}{G}".equals(printedCost)&&"{1}{G}{G}".equals(alternateCost),"Only three green fixture mana are available for native Gemrazer's alternative1GG versus printed3G");
        require(run(()->current.human.cast(alternative,current.game,false,null),p->byId(p,original)),"Actual native cast accepts the offered Bear target and pays Gemrazer's mutate alternative cost");
        require(current.human.getManaPool().count()==0&&current.human.getManaPool().getGreen()==0,"Native alternative-cost casting spends all three supplied green mana");
        require(current.game.getStack().peek() instanceof Spell&&((Spell)current.game.getStack().peek()).getSpellAbility() instanceof MutateAbility&&gem.getId().equals(current.game.getStack().peek().getSourceId()),"Actual cast puts the native MutateAbility spell on stack");
        save("alternative-cost-payment.json",EngineBridge.map("printedNativeCost",printedCost,"nativeAlternativeCost",alternateCost,"manaBefore",manaBefore,"manaAfter",current.human.getManaPool().count(),"sourceCardId",gem.getId().toString(),"offeredTargetId",original.toString(),"scope","Actual native human.cast(MutateAbility) and native pool payment; initial resources are fixtures"));
        settle(8,p->byLabel(p,"Over"));Permanent host=current.game.getPermanent(original);require(host!=null&&host.getMutateCount()==1,"Native paid mutating spell keeps the original host ID");pt(host,10,6);
        require(host.getAttachments().containsAll(attached)&&host.getAttachments().size()==2&&original.equals(permanent(equipment).getAttachedTo())&&original.equals(aura.getAttachedTo()),"Equipment/Aura attachments and their attachedTo native host ID survive Gemrazer-over");
        require(host.isTapped()&&host.getDamage()==1&&host.getCounters(current.game).getCount(CounterType.P1P1)==2,"Native mutation retains tap state, one marked damage and two counters");
        require(host.getAbilities().contains(ReachAbility.getInstance())&&host.getAbilities().contains(TrampleAbility.getInstance()),"Merged native creature retains reach and trample with attachment effects applied");
        Map<String,Object> view=current.card(host),template=(Map<String,Object>)view.get("tokenTemplate");require(template!=null&&"Bear Token".equals(template.get("name"))&&"2".equals(String.valueOf(template.get("power")))&&"2".equals(String.valueOf(template.get("toughness"))),"Original native Bear token template stays2/2 beneath live10/6");
        require(new HashSet<>((List<String>)view.get("attachmentIds")).equals(attached.stream().map(UUID::toString).collect(Collectors.toSet())),"Bridge attachment ID projection matches exact retained native attachments");
        save("mutate-attachment-state.json",EngineBridge.map("host",view,"equipment",current.card(permanent(equipment)),"aura",current.card(aura),"originalHostId",original.toString()));snapshot("final-frame.json");
    }
    static void replacementCases(String id)throws Exception{
        setup();Card bear=card("Grizzly Bears");
        if(id.equals("adv-replace-tokens-single")){field(card("Parallel Lives"));token(new BearToken(),1);require(tokens().size()==2,"Parallel Lives doubles one native token event");}
        if(id.equals("adv-replace-tokens-stacked")){field(card("Parallel Lives"),card("Doubling Season"));token(new BearToken(),1);require(tokens().size()==4,"Independent token replacement effects each apply once, yielding four");}
        if(id.equals("adv-replace-manufactor")){field(card("Parallel Lives"),card("Academy Manufactor"));token(new TreasureToken(),1);require(tokens().size()==6,"Manufactor and token doubling create six native objects");for(SubType type:Arrays.asList(SubType.FOOD,SubType.CLUE,SubType.TREASURE))require(tokens().stream().filter(p->p.hasSubtype(type,current.game)).count()==2,"Exactly two "+type+" tokens exist");}
        if(id.equals("adv-replace-counters-stacked")){field(card("Doubling Season"),card("Branching Evolution"),bear);Permanent p=permanent(bear);run(()->{p.addCounters(CounterType.P1P1.createInstance(1),current.human.getId(),bear.getSpellAbility(),current.game);return true;});current.game.applyEffects();require(p.getCounters(current.game).getCount(CounterType.P1P1)==4,"Counter replacements multiply one effect counter to four without recursive reapplication");pt(p,6,6);}
        if(id.startsWith("adv-prevent-unpreventable")){Card nine=card("Nine Lives");field(nine);int life=current.human.getLife();boolean banefire=id.endsWith("banefire");Spell spell=stack(banefire?"Banefire":"Skullcrack",current.human.getId());if(banefire){spell.getSpellAbility().setCostsTag("X",5);spell.getSpellAbility().getManaCostsToPay().setX(5,5);}settle(8);require(current.human.getLife()==life-(banefire?5:3),"Native unpreventable damage is actually dealt");save("unpreventable-observed.json",EngineBridge.map("nativeDamage",life-current.human.getLife(),"incarnationCounters",permanent(nine).getCounters(current.game).getCount(CounterType.INCARNATION),"expectedCounters",1,"ruleSource","https://magic.wizards.com/en/news/feature/core-set-2021-and-jumpstart-release-notes-2020-06-20","fixturePaidX",banefire?5:null));require(permanent(nine).getCounters(current.game).getCount(CounterType.INCARNATION)==1,"Nine Lives still receives one incarnation counter from unpreventable damage per official ruling");}
        if(id.equals("adv-prevent-nine-lives")){Card nine=card("Nine Lives");field(nine);int life=current.human.getLife();stack("Lightning Bolt",current.human.getId());settle(8);require(current.human.getLife()==life&&permanent(nine).getCounters(current.game).getCount(CounterType.INCARNATION)==1,"Nine Lives prevents a native Bolt and receives one incarnation counter");}
        if(id.equals("adv-lock-solemnity-nine-lives")){Card nine=card("Nine Lives");field(nine,card("Solemnity"));int life=current.human.getLife();for(int i=0;i<3;i++){stack("Lightning Bolt",current.human.getId());settle(8);}require(current.human.getLife()==life&&permanent(nine).getCounters(current.game).getCount(CounterType.INCARNATION)==0,"Legal prevention lock handles three separate damage events with zero prohibited counters");require(current.game.getStack().isEmpty()&&!current.game.hasEnded(),"Legal lock remains live rather than false loop/draw");}
        if(id.equals("adv-prevent-vigor")){field(card("Vigor"),bear);Permanent p=permanent(bear);run(()->p.damage(3,bear.getSpellAbility(),current.game));current.game.applyEffects();require(p.getDamage()==0&&p.getCounters(current.game).getCount(CounterType.P1P1)==3,"Vigor prevents damage and replaces it with three counters");pt(p,5,5);}
        if(id.equals("adv-replace-solemnity-vigor")){field(card("Vigor"),card("Solemnity"),bear);Permanent p=permanent(bear);run(()->p.damage(3,bear.getSpellAbility(),current.game));current.game.applyEffects();require(p.getDamage()==0&&p.getCounters(current.game).isEmpty(),"Vigor prevention still works when Solemnity forbids its counters");pt(p,2,2);}
        snapshot("final-frame.json");
    }
    static void loopCases(String id)throws Exception{
        setup();
        if(id.equals("adv-finite-scute-chain")){
            Card scute=card("Scute Swarm");field(scute,card("Forest"),card("Forest"),card("Forest"),card("Forest"),card("Forest"));resetTriggers();
            enter(card("Forest"));settle(12);require(controlled().stream().filter(p->p.getName().equals("Scute Swarm")).count()==2,"Sixth land produces one actual Scute copy");
            enter(card("Forest"));settle(16);require(controlled().stream().filter(p->p.getName().equals("Scute Swarm")).count()==4,"Seventh land produces two more copies then finite stack empties");require(current.game.getStack().isEmpty(),"Finite exponential-looking sequence ends natively");
        }else{
            if(id.equals("adv-loop-mandatory-sporemound")){field(card("Sporemound"),card("Life and Limb"));resetTriggers();enter(card("Forest"));}
            else{field(card("Marauding Raptor"));resetTriggers();enter(card("Polyraptor"));}
            run(()->{current.game.checkStateAndTriggered();return true;});int before=controlled().size();
            for(int i=0;i<24&&!current.game.hasEnded();i++){
                require(!current.game.getStack().isEmpty(),"Mandatory cycle retains a native pending trigger");
                run(()->{nativeResolve();current.game.checkStateAndTriggered();current.game.checkIfGameIsOver();return true;},p->String.valueOf(p.get("message")).toLowerCase(Locale.ROOT).contains("infinite looping")?byLabel(p,"Yes"):null);
                save("loop-progress.json",EngineBridge.map("resolutions",resolutions,"nativePermanents",controlled().size(),"stack",current.game.getStack().size(),"nativeEnded",current.game.hasEnded(),"note","Test resolution budget, never a declared game outcome"));
            }
            if(current.game.hasEnded()){require(current.game.isADraw(),"Only a native draw is accepted as the mandatory loop outcome");save("capability.json",EngineBridge.map("nativeLoopOutcomeObserved",true,"nativeDraw",true,"pendingStack",current.game.getStack().size(),"objects",controlled().size()));snapshot("final-frame.json");return;}
            require(controlled().size()>before,"Mandatory trigger cycle demonstrably grows native objects");
            snapshot("checkpoint-frame.json");save("capability.json",EngineBridge.map("nativeLoopOutcomeObserved",current.game.hasEnded(),"pendingStack",current.game.getStack().size(),"objects",controlled().size(),"classification","mandatory_growing_loop","testStoppedAtResolutionBudget",true));
            throw new BudgetReached("24 native resolutions observed; no native terminal outcome; external test budget stopped progression");
        }
        snapshot("final-frame.json");
    }
    static final class BudgetReached extends RuntimeException{BudgetReached(String m){super(m);}}
    static void illegalMutate()throws Exception{
        setup();Card bear=card("Grizzly Bears"),warden=card("Soul Warden");field(warden,bear);resetTriggers();
        Card mutation=card("Gemrazer");current.game.loadCards(Collections.singleton(mutation),current.human.getId());mutation.setZone(Zone.STACK,current.game);
        MutateAbility a=(MutateAbility)mutation.getAbilities().stream().filter(MutateAbility.class::isInstance).findFirst().orElseThrow();a=a.copy();a.setControllerId(current.human.getId());a.getTargets().get(0).addTarget(bear.getId(),a,current.game);
        Spell spell=new Spell(mutation,a,current.human.getId(),Zone.HAND,current.game);current.game.getStack().push(current.game,spell);
        run(()->current.human.moveCards(permanent(bear),Zone.HAND,warden.getSpellAbility(),current.game));int life=current.human.getLife();settle(10);
        require(current.human.getHand().contains(bear.getId())&&current.game.getPermanent(mutation.getId())!=null,"Invalid mutate target returns to hand; mutating spell resolves as an ordinary creature");
        Permanent gem=permanent(mutation);pt(gem,4,4);require(gem.getMutateCount()==0&&current.human.getLife()==life+1,"Fallback enters normally, triggers Soul Warden and has no mutation count");snapshot("final-frame.json");
    }
    static void retargetCopy()throws Exception{
        setup();Card witness=card("Grizzly Bears");field(witness);Spell spell=stack("Lightning Bolt",current.bot.getId());
        Function<Map<String,Object>,Map<String,Object>> policy=p->{Map<String,Object> option=byLabel(p,"Yes");if(option!=null&&String.valueOf(p.get("message")).toLowerCase(Locale.ROOT).contains("target"))return option;return byId(p,current.human.getId());};
        run(()->{spell.createCopyOnStack(current.game,witness.getSpellAbility(),current.human.getId(),true);return true;},policy);
        int own=current.human.getLife(),opponent=current.bot.getLife();settle(5);require(current.human.getLife()==own-3&&current.bot.getLife()==opponent-3,"Retargeted copy damages its new target; original retains its own target");snapshot("final-frame.json");
    }
    static void optionalLoop(String id)throws Exception{
        setup();
        if(id.equals("adv-loop-optional-renewal")){
            Card renewal=card("Enduring Renewal"),altar=card("Ashnod's Altar"),orni=card("Ornithopter");field(renewal,altar,orni);resetTriggers();int mana=current.human.getManaPool().getColorless();
            for(int i=0;i<3;i++){
                ActivatedAbility ability=(ActivatedAbility)permanent(altar).getAbilities().stream().filter(a->a instanceof ActivatedAbility&&a.getRule().contains("Sacrifice")).findFirst().orElseThrow();
                require(run(()->current.human.activateAbility(ability,current.game),p->byId(p,orni.getId())),"Altar pays an offered native sacrifice cost");settle(8);
                require(current.human.getHand().contains(orni.getId()),"Native Renewal trigger returns the sacrificed card to hand");require(run(()->current.human.cast(current.game.getCard(orni.getId()).getSpellAbility(),current.game,false,null)),"Native zero-cost Ornithopter cast succeeds");settle(8);
            }
            require(current.human.getManaPool().getColorless()==mana+6&&current.game.getPermanent(orni.getId())!=null,"Three optional no-win cycles preserve the creature and add six mana");
        }else{
            Card kiki=card("Kiki-Jiki, Mirror Breaker"),conscripts=card("Zealous Conscripts"),impact=card("Impact Tremors");field(kiki,conscripts,impact);resetTriggers();int before=current.bot.getLife();
            for(int i=0;i<3;i++){
                ActivatedAbility a=permanent(kiki).getAbilities().stream().filter(x->x instanceof ActivatedAbility&&x.getRule().contains("Create a token")).map(x->(ActivatedAbility)x).findFirst().orElseThrow();
                require(run(()->current.human.activateAbility(a,current.game),p->byId(p,conscripts.getId())),"Kiki activation uses its offered native copy target");settle(12,p->byId(p,kiki.getId()));require(!permanent(kiki).isTapped(),"Native Conscripts trigger untaps Kiki for another optional cycle");
            }
            require(tokens().size()==3&&current.bot.getLife()==before-3,"Each explicitly activated cycle creates one hasty copy and one native Impact Tremors damage");
        }
        current.priorityCommand(JsonParser.parseString("{\"command\":\"configure\",\"autoPass\":false}").getAsJsonObject());
        boolean result=run(()->current.human.priority(current.game),p->choices(p).stream().filter(c->"done".equals(c.get("id"))).findFirst().orElse(null));
        require(!result&&current.game.getStack().isEmpty()&&!current.game.hasEnded(),"Explicit native Pass exits optional repetition without an invented terminal result");snapshot("final-frame.json");
    }
    static void feedbackLoop()throws Exception{
        setup();Card shield=card("Pariah's Shield"),doll=card("Stuffy Doll");field(shield);enter(doll,p->byId(p,current.human.getId()));
        Permanent p=permanent(doll);require(p.addAttachment(shield.getId(),shield.getSpellAbility(),current.game),"Native initial legal Equipment attachment succeeds");current.game.applyEffects();
        stack("Lightning Bolt",p.getId());int life=current.human.getLife();run(()->{current.game.checkStateAndTriggered();return true;});
        for(int i=0;i<24&&!current.game.hasEnded();i++){
            require(!current.game.getStack().isEmpty(),"Mandatory damage feedback retains native pending work");run(()->{nativeResolve();current.game.checkStateAndTriggered();current.game.checkIfGameIsOver();return true;},q->String.valueOf(q.get("message")).toLowerCase(Locale.ROOT).contains("infinite looping")?byLabel(q,"Yes"):null);
            save("loop-progress.json",EngineBridge.map("resolutions",resolutions,"nativePermanents",controlled().size(),"life",current.human.getLife(),"markedDamage",p.getDamage(),"nativeEnded",current.game.hasEnded()));
        }
        require(current.human.getLife()==life&&controlled().size()==2,"Feedback preserves life and object quantities; marked damage is separately recorded");
        if(!current.game.hasEnded())throw new BudgetReached("Native mandatory damage feedback remains pending after24resolutions; no invented draw");require(current.game.isADraw(),"Only native engine declares the loop draw");snapshot("final-frame.json");
    }
    @SuppressWarnings("unchecked") static void projectionToken()throws Exception{
        JsonObject body=JsonParser.parseString("{\"format\":\"Modern\",\"recordingPort\":0,\"seats\":[{\"seatId\":\"advanced-owner\",\"name\":\"Advanced owner\",\"type\":\"human\",\"deck\":{\"main\":[{\"name\":\"Plains\",\"count\":60}]}},{\"seatId\":\"advanced-peer\",\"name\":\"Advanced peer\",\"type\":\"human\",\"deck\":{\"main\":[{\"name\":\"Plains\",\"count\":60}]}}]}").getAsJsonObject();
        current=new EngineBridge.Session(body,true);observe(current.game);current.game.setStartingPlayerId(current.human.getId());current.game.getState().setActivePlayerId(current.human.getId());current.game.getState().setPriorityPlayerId(current.human.getId());current.game.getTurn().setPhase(new mage.game.turn.PreCombatMainPhase());current.game.getPhase().setStep(new mage.game.turn.PreCombatMainStep());for(mage.players.Player player:current.game.getPlayers().values())player.updateRange(current.game);
        java.lang.reflect.Field cursor=GameImpl.class.getDeclaredField("playerList");cursor.setAccessible(true);cursor.set(current.game,current.game.getState().getPlayerList(current.human.getId()));gameWorker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"GAME advanced projection");t.setDaemon(true);return t;});
        EngineBridge.Session peer=current.perspectives.get(1);token(new BearToken(),1);Permanent host=tokens().get(0);UUID original=host.getId();String nativeTokenName=((PermanentToken)host).getToken().getName();
        host=mutate(host,"Gemrazer",false);host=mutate(host,"Sea-Dasher Octopus",true);List<UUID> nativeIds=host.getMutateForView();
        Map<String,Object> view=current.card(host);save("visible-merged-card.json",view);Map<String,Object> merged=(Map<String,Object>)view.get("mutate");require(merged!=null,"Bridge exposes actual native merged component metadata");
        require(((Number)merged.get("count")).intValue()==host.getMutateCount()&&original.toString().equals(merged.get("originalObjectId")),"Projected merge count/original object agree with native state");
        require(nativeIds.get(0).toString().equals(merged.get("topId")),"Projected top component is the native ordered top ID");
        List<Map<String,Object>> components=(List<Map<String,Object>>)merged.get("components");require(components.size()==3,"All three components, including base token, remain inspectable");
        for(int i=0;i<nativeIds.size();i++)require(nativeIds.get(i).toString().equals(components.get(i).get("id")),"Component ID/order is native at index "+i);
        Map<String,Object> originalComponent=components.stream().filter(c->original.toString().equals(c.get("id"))).findFirst().orElseThrow();require(nativeTokenName.equals(originalComponent.get("name"))&&"2".equals(String.valueOf(originalComponent.get("power"))),"Base token component retains original template name/P/T rather than merged values");
        require("Gemrazer".equals(view.get("name"))&&"Gemrazer".equals(((Map<String,Object>)view.get("printing")).get("name")),"Live host and current top printing remain Gemrazer");
        Token nativeTemplate=((PermanentToken)host).getToken();Map<String,Object> template=(Map<String,Object>)view.get("tokenTemplate");
        require(template!=null&&nativeTemplate.getId().toString().equals(template.get("id"))&&nativeTokenName.equals(template.get("name"))&&"2".equals(String.valueOf(template.get("power")))&&"2".equals(String.valueOf(template.get("toughness"))),"Host tokenTemplate retains exact original native Bear identity and printed2/2 separately from live Gemrazer");
        require("Gemrazer".equals(components.get(0).get("name"))&&!Objects.equals(template.get("name"),components.get(0).get("name")),"Native top component and original token template are distinct artwork identities");
        require(peer.card(host).get("mutate")!=null,"Another real human may inspect a publicly visible merged creature");snapshot("visible-merged-frame.json");
        stack("Rite of Replication",host.getId());settle(10);Permanent copy=tokens().stream().filter(p->!p.getId().equals(original)).findFirst().orElseThrow();require(copy.getMutateCount()==0,"A copy of merged characteristics is not itself a physically merged permanent");Map<String,Object> copied=current.card(copy);save("copied-merged-characteristics.json",copied);Map<String,Object> copiedMerge=(Map<String,Object>)copied.get("mutate");require(copiedMerge==null||((Number)copiedMerge.get("count")).intValue()==0,"Copy projection cannot borrow original merged component identities");
        Card mergedCopySource=((PermanentToken)copy).getToken().getCopySourceCard();
        require(mergedCopySource==null&&!copied.containsKey("copySourceCard"),"Native merged-copy branch has no original Card reference; bridge leaves provenance unavailable rather than guessing artwork from its name");
        save("merged-copy-provenance.json",EngineBridge.map("nativeCopySourceCardAvailable",false,"projectedCopySourceCardAvailable",copied.containsKey("copySourceCard"),"scope","Pinned CopyTokenFunction mutated branch copies characteristics without setCopySourceCard; unavailable provenance is retained without name-based inference"));
        Card ordinary=card("Grizzly Bears");enter(ordinary);Permanent ordinaryHost=permanent(ordinary);Card nativeOriginal=((PermanentCard)ordinaryHost).getCard();Set<UUID> beforeOrdinaryCopy=tokens().stream().map(Permanent::getId).collect(Collectors.toSet());
        stack("Rite of Replication",ordinaryHost.getId());settle(10);List<Permanent> ordinaryCopies=tokens().stream().filter(p->!beforeOrdinaryCopy.contains(p.getId())).collect(Collectors.toList());require(ordinaryCopies.size()==1,"Ordinary Grizzly Bears control creates exactly one additional native Rite copy");
        Permanent ordinaryCopy=ordinaryCopies.get(0);Card nativeCopySource=((PermanentToken)ordinaryCopy).getToken().getCopySourceCard();
        require(nativeCopySource!=null&&!(nativeCopySource instanceof Permanent)&&nativeOriginal.getId().equals(nativeCopySource.getId()),"Ordinary copied token retains exact native original Card reference");
        Map<String,Object> ordinaryView=current.card(ordinaryCopy);Map<String,Object> copySource=(Map<String,Object>)ordinaryView.get("copySourceCard");
        require(copySource!=null&&"Grizzly Bears".equals(copySource.get("name"))&&nativeOriginal.getId().toString().equals(copySource.get("id")),"Ordinary copySourceCard projects Grizzly Bears with its exact native original card ID");
        require(ordinaryCopy.getMutateCount()==0&&!ordinaryView.containsKey("mutate"),"Ordinary copied permanent has no physical merged components");
        save("ordinary-card-copy-provenance.json",EngineBridge.map("nativeOriginalCardId",nativeOriginal.getId().toString(),"nativeCopySourceCardId",nativeCopySource.getId().toString(),"copy",ordinaryView));
        UUID copiedHostId=ordinaryCopy.getId(),copiedTemplateId=((PermanentToken)ordinaryCopy).getToken().getId();int permanentsBeforeCopyMerge=current.game.getBattlefield().getAllActivePermanents().size();
        ordinaryCopy=mutate(ordinaryCopy,"Sea-Dasher Octopus",true);List<UUID> copiedNativeIds=ordinaryCopy.getMutateForView();Token copiedNativeTemplate=((PermanentToken)ordinaryCopy).getToken();Card copiedNativeSource=copiedNativeTemplate.getCopySourceCard();
        require(copiedHostId.equals(ordinaryCopy.getId())&&ordinaryCopy.isToken()&&ordinaryCopy.getMutateCount()==1,"Octopus-under preserves the ordinary copied token host, token status and native merge count");
        require(copiedNativeSource!=null&&nativeOriginal.getId().equals(copiedNativeSource.getId())&&copiedTemplateId.equals(copiedNativeTemplate.getId())&&"Grizzly Bears".equals(copiedNativeTemplate.getName()),"Merged copied-token host retains its exact original normal-copy template and Card provenance");
        Map<String,Object> copiedTopView=current.card(ordinaryCopy);Map<String,Object> copiedTopMerge=(Map<String,Object>)copiedTopView.get("mutate");require(copiedTopMerge!=null,"Merged ordinary copied token exposes native component metadata");
        List<Map<String,Object>> copiedTopComponents=(List<Map<String,Object>>)copiedTopMerge.get("components");
        require(copiedNativeIds.size()==2&&copiedTopComponents.size()==2&&copiedHostId.equals(copiedNativeIds.get(0))&&copiedHostId.toString().equals(copiedTopMerge.get("topId"))&&copiedHostId.toString().equals(copiedTopMerge.get("originalObjectId")),"Top component and original host IDs remain exact native copied-token identity");
        for(int i=0;i<copiedNativeIds.size();i++)require(copiedNativeIds.get(i).toString().equals(copiedTopComponents.get(i).get("id")),"Copied-token top/under component UUID ordering remains native at index "+i);
        Map<String,Object> topCopySource=(Map<String,Object>)copiedTopComponents.get(0).get("copySourceCard");Map<String,Object> copiedHostTemplate=(Map<String,Object>)copiedTopView.get("tokenTemplate");Map<String,Object> copiedHostTemplateSource=copiedHostTemplate==null?null:(Map<String,Object>)copiedHostTemplate.get("copySourceCard");
        require(topCopySource!=null&&"Grizzly Bears".equals(topCopySource.get("name"))&&copiedNativeSource.getId().toString().equals(topCopySource.get("id")),"Native top Token component projects exact copySourceCard identity for artwork");
        require(copiedHostTemplateSource!=null&&copiedNativeSource.getId().toString().equals(copiedHostTemplateSource.get("id"))&&"Grizzly Bears".equals(copiedHostTemplate.get("name")),"Host tokenTemplate remains the normal Grizzly Bears copy after Octopus-under");
        require(current.game.getBattlefield().getAllActivePermanents().size()==permanentsBeforeCopyMerge&&current.game.getPermanent(copiedNativeIds.get(1))==null,"Under-component metadata does not create an independent native permanent target");
        save("copied-token-top-card.json",EngineBridge.map("nativeHostId",copiedHostId.toString(),"nativeComponentIds",copiedNativeIds.stream().map(UUID::toString).collect(Collectors.toList()),"nativeCopySourceCardId",copiedNativeSource.getId().toString(),"card",copiedTopView));snapshot("copied-token-top-frame.json");
        Card peerSecret=peer.human.getLibrary().getCards(peer.game).iterator().next();Map<String,Object> hiddenLibrary=current.card(peerSecret);require(Boolean.TRUE.equals(hiddenLibrary.get("hidden"))&&!hiddenLibrary.containsKey("mutate")&&!hiddenLibrary.containsKey("tokenTemplate")&&!hiddenLibrary.containsKey("copySourceCard"),"Unentitled opponent library card has no component or artwork-provenance metadata");
        host.setFaceDown(true,current.game);Map<String,Object> hidden=peer.card(host);save("hidden-merged-card.json",hidden);String serialized=EngineBridge.JSON.toJson(hidden);require(Boolean.TRUE.equals(hidden.get("hidden"))&&!hidden.containsKey("mutate")&&!hidden.containsKey("tokenTemplate")&&!hidden.containsKey("copySourceCard")&&!serialized.contains("Gemrazer")&&!serialized.contains("Octopus"),"Face-down privacy guard redacts merged components from the other human");snapshot("final-frame.json");
    }
    static void execute(String id)throws Exception{
        if(id.equals("adv-copy-legend"))legendaryCopy();
        else if(id.equals("adv-mutate-token-attachments"))mutateAttachments();
        else if(id.equals("adv-mutate-projection-token"))projectionToken();
        else if(id.equals("adv-loop-mandatory-feedback"))feedbackLoop();
        else if(id.equals("adv-mutate-illegal-target"))illegalMutate();
        else if(id.equals("adv-copy-retarget"))retargetCopy();
        else if(id.startsWith("adv-loop-optional"))optionalLoop(id);
        else if(id.startsWith("adv-mutate-token"))tokenMutate(id);
        else if(id.startsWith("adv-mutate-"))mutateCase(id);
        else if(id.startsWith("adv-copy-"))copyCases(id);
        else if(id.startsWith("adv-replace-")||id.startsWith("adv-prevent-")||id.startsWith("adv-lock-"))replacementCases(id);
        else if(id.startsWith("adv-loop-")||id.equals("adv-finite-scute-chain"))loopCases(id);
        else throw new IllegalArgumentException("Unknown scenario: "+id);
    }
    public static void main(String[] args)throws Exception{
        Path root=Paths.get(args[0]);String id=args[1];output=Paths.get(args[2]);Files.createDirectories(output);
        org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(AdvancedMechanicsFixture.class.getClassLoader());
        long started=System.nanoTime();String status="pass",error=null;
        try{configureBudgets();execute(id);}catch(Throwable t){status=t instanceof BudgetReached?"budget_exceeded":"fail";error=t.toString();Files.writeString(output.resolve("error.txt"),t+"\n"+Arrays.stream(t.getStackTrace()).map(Object::toString).collect(Collectors.joining("\n")));}
        finally{if(current!=null){try{snapshot("last-frame.json");save("native-structured-log.json",new ArrayList<>(current.log));}catch(Throwable ignored){}current.stop();}if(gameWorker!=null){gameWorker.shutdownNow();gameWorker.awaitTermination(2,TimeUnit.SECONDS);}}
        Map<String,Object> report=EngineBridge.map("scenarioId",id,"status",status,"evidenceKind","deterministic_native","fixtureInitialZones",true,"checks",checks,"acceptedActions",accepted,"nativeResolutions",resolutions,"stepSeconds",stepSeconds,"appliedBudgets",appliedBudgets(),"checksScope","Deterministic native resolution/state/projection assertions; prepared zones and injected pre-paid spells do not prove production casting or cost payment. Native tasks and event/response/resolution counts use reported configurable test budgets.","durationMs",(System.nanoTime()-started)/1000000,"error",error,"gameThreadAlive",gameWorker!=null&&!gameWorker.isTerminated(),"lastPrompt",current==null?null:current.prompt,"nativeEnded",current!=null&&current.game.hasEnded(),"nativeDraw",current!=null&&current.game.isADraw(),"nativeEventCount",eventTotal(),"nativeEventTypes",eventTypes(),"lastNativeEvent",lastEvent(),"eventCountScope",EVENT_SCOPE,"nativeStructuredLogCount",current==null?0:current.logIds.get(),"retainedStructuredLogs",current==null?0:current.log.size(),"retainedAnimationEvents",current==null?0:current.animationEvents.size(),"gameId",current==null?null:current.game.getId().toString(),"recordingOutbox","disabled_for_deterministic_fixture");save("native-events.json",EngineBridge.map("format","native_event_count_summary","count",eventTotal(),"perType",eventTypes(),"lastNativeEvent",lastEvent(),"scope",EVENT_SCOPE));save("result.json",report);System.out.println(EngineBridge.JSON.toJson(report));if(status.equals("fail"))System.exit(1);
    }
}
