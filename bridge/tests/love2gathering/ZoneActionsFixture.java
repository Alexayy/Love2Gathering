package love2gathering;

import com.google.gson.*;
import mage.Mana;
import mage.abilities.*;
import mage.abilities.effects.common.continuous.*;
import mage.abilities.keyword.HasteAbility;
import mage.cards.Card;
import mage.constants.*;
import mage.game.*;
import mage.game.stack.Spell;
import mage.util.Copier;
import mage.target.targetpointer.FixedTarget;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

/** Real native casts/choices/permissions, with deterministic initial zones/resources only. */
public final class ZoneActionsFixture {
    static final List<Map<String,Object>> checks=new ArrayList<>();static Path output;
    static void check(boolean value,String label){checks.add(EngineBridge.map("passed",value,"message",label));if(!value)throw new AssertionError(label);System.out.println("PASS "+label);}
    @SuppressWarnings("unchecked")static Map<String,Object> object(Object value){return(Map<String,Object>)value;}
    @SuppressWarnings("unchecked")static List<Map<String,Object>> list(Object value){return(List<Map<String,Object>>)value;}
    static long id(Map<String,Object> p){return((Number)p.get("id")).longValue();}
    static ExecutorService worker(){return Executors.newSingleThreadExecutor(r->new Thread(r,"GAME zone actions fixture"));}
    static Map<String,Object> waitPrompt(EngineBridge.Session s,long previous)throws Exception{return GameplayPresentationFixture.prompt(s,previous);}
    static void answer(EngineBridge.Session s,Map<String,Object> p,Map<String,Object> choice)throws Exception{GameplayPresentationFixture.answer(s,p,String.valueOf(choice.getOrDefault("responseType","uuid")),choice.getOrDefault("value",choice.get("id")));}
    static <T>T run(EngineBridge.Session s,Callable<T> operation)throws Exception{
        ExecutorService executor=worker();try{
            long last=s.prompt==null?-1:id(s.prompt);Future<T> future=executor.submit(operation);long until=System.nanoTime()+TimeUnit.SECONDS.toNanos(15);
            while(!future.isDone()&&System.nanoTime()<until){Map<String,Object> p=s.prompt;
                if(p!=null&&s.snapshot.get("prompt")==p&&id(p)!=last){
                    Map<String,Object> choice=null;List<Map<String,Object>> choices=list(p.get("choices"));String type=String.valueOf(p.get("type"));
                    if("play_mana".equals(type))choice=choices.stream().filter(c->"mana".equals(c.get("responseType"))).findFirst().orElse(null);
                    else if("ask".equals(type))choice=choices.stream().filter(c->Boolean.TRUE.equals(c.get("value"))).findFirst().orElse(null);
                    else if("choose_ability".equals(type))choice=choices.stream().filter(c->"uuid".equals(c.get("responseType"))).findFirst().orElse(null);
                    else if("pick_target".equals(type))choice=choices.stream().filter(c->s.bot.getId().toString().equals(c.get("id"))).findFirst().orElseGet(()->choices.stream().filter(c->"uuid".equals(c.get("responseType"))&&!Boolean.FALSE.equals(c.get("selectable"))).findFirst().orElse(null));
                    if(choice==null)throw new AssertionError("Unhandled real prompt "+EngineBridge.JSON.toJson(p));
                    last=id(p);answer(s,p,choice);
                }else Thread.sleep(2);
            }
            return future.get(1,TimeUnit.SECONDS);
        }finally{executor.shutdownNow();}
    }
    static Map<String,Object> offered(EngineBridge.Session s,Card card){
        // Mirror BridgeHuman.priority before the query, including its manual
        // acknowledgement, so exported frames are coherent client snapshots.
        s.priority.decide(s,s.human,s.game);
        s.nativePriorityDepth++;try{ActionabilityFixture.priority(s);}finally{s.nativePriorityDepth--;}
        return list(s.prompt.get("cardActions")).stream().filter(c->card.getId().toString().equals(c.get("objectId"))).findFirst().orElse(null);
    }
    static ActivatedAbility ability(EngineBridge.Session s,Card card){return s.human.getPlayable(s.game,true,Zone.ALL,false).stream().filter(a->card.getId().equals(a.getSourceId())).findFirst().orElseThrow();}
    static void save(String name,EngineBridge.Session s)throws Exception{Files.writeString(output.resolve(name+".json"),EngineBridge.JSON.toJson(s.snapshot));}
    static void flashback(boolean countered)throws Exception{
        EngineBridge.Session s=GameplayPresentationFixture.room();ExecutorService executor=worker();
        try{
            Card memory=TriggerFixture.card("Memory Deluge");List<Card> library=new ArrayList<>();
            for(String name:Arrays.asList("Plains","Island","Mountain","Swamp","Forest","Opt","Grizzly Bears"))library.add(TriggerFixture.card(name));
            Card counter=TriggerFixture.card("Counterspell");
            s.human.getLibrary().clear();s.game.cheat(s.human.getId(),library,countered?Collections.singletonList(counter):TriggerFixture.NONE,Collections.emptyList(),Collections.singletonList(memory),TriggerFixture.NONE,TriggerFixture.NONE);
            s.human.getManaPool().addMana(Mana.BlueMana(countered?9:7),s.game,memory.getSpellAbility());s.game.applyEffects();
            Map<String,Object> actions=offered(s,memory);
            check(actions!=null&&"GRAVEYARD".equals(actions.get("sourceZone")),"Native priority offers Memory Deluge from graveyard");
            check(EngineBridge.JSON.toJson(actions).contains("{5}{U}{U}")&&EngineBridge.JSON.toJson(actions).contains("flashback"),"Shared action sheet receives native flashback cost and mechanic identity");
            s.priority.configure(JsonParser.parseString("{\"autoPass\":true,\"passWithOnlyMana\":true}").getAsJsonObject());
            check(!s.priority.decide(s,s.human,s.game),"Mana-only preference cannot auto-pass a real graveyard cast");
            check(s.priority.legalityKnown&&s.priority.meaningfulActionCount>0,"Priority's native inventory counts the actual graveyard action as meaningful");
            save(countered?"flashback-counter-offer":"flashback-offer",s);
            ActivatedAbility cast=ability(s,memory);check(run(s,()->s.human.activateAbility(cast,s.game)),"XMage accepts the actual native flashback ability and payment");
            Spell spell=(Spell)s.game.getStack().peek();check(spell.getSpellAbility().getSpellAbilityCastMode()==SpellAbilityCastMode.FLASHBACK,"Actual spell carries native FLASHBACK cast mode");
            if(countered){
                check(run(s,()->s.human.cast(counter.getSpellAbility(),s.game,false,null)),"A real Counterspell cast targets the actual flashback spell on the stack");
                s.game.getStack().resolve(s.game);s.game.processAction();s.publishAll();
                check(s.game.getState().getZone(memory.getId())==Zone.EXILED,"Countered flashback spell follows native exile replacement");
                check(s.animationEvents.stream().anyMatch(e->"COUNTERED".equals(e.get("nativeType"))&&"counter".equals(e.get("operation"))),"Countering has a distinct confirmed native outcome event");
                check(s.animationEvents.stream().noneMatch(e->"resolution".equals(e.get("type"))||"impact".equals(e.get("type"))),"Countered flashback never celebrates successful resolution or permanent entry");
                save("flashback-countered",s);return;
            }
            long beforeResolve=s.prompt==null?-1:id(s.prompt);Future<?> resolving=executor.submit(()->s.game.getStack().resolve(s.game));
            Map<String,Object> p0=waitPrompt(s,beforeResolve),panel0=object(p0.get("cardPanel"));
            check("multiple".equals(panel0.get("selectionMode"))&&((Number)panel0.get("min")).intValue()==2&&((Number)panel0.get("max")).intValue()==2,"Memory Deluge exposes exact native select-two bounds for staged confirmation");
            List<Map<String,Object>> cards=list(panel0.get("cards"));check(cards.size()==7,"Flashback looks at seven cards from the actual paid mana");
            String first=String.valueOf(cards.get(0).get("id")),second=String.valueOf(cards.get(1).get("id"));save("memory-deluge-before-selection",s);
            for(EngineBridge.Session peer:s.perspectives)if(peer!=s){String json=EngineBridge.JSON.toJson(peer.snapshot);check(!json.contains(first)&&!json.contains(second),"Another human receives no looked-at card IDs or selection markers");}
            answer(s,p0,cards.get(0));Map<String,Object> p1=waitPrompt(s,id(p0)),panel1=object(p1.get("cardPanel"));
            check(panel0.get("interactionId").equals(panel1.get("interactionId")),"Multi-card native operation keeps its panel identity across query IDs");
            check(((Number)panel1.get("selectedCount")).intValue()==1&&list(panel1.get("cards")).stream().anyMatch(c->first.equals(c.get("id"))&&Boolean.TRUE.equals(c.get("selected"))),"Native next query retains the first selected card and explicit selected state");
            save("memory-deluge-one-selected",s);
            answer(s,p1,list(panel1.get("cards")).stream().filter(c->second.equals(c.get("id"))).findFirst().orElseThrow());resolving.get(10,TimeUnit.SECONDS);s.game.processAction();s.publishAll();
            check(s.human.getHand().contains(UUID.fromString(first))&&s.human.getHand().contains(UUID.fromString(second)),"Only the confirmed two actual UUIDs enter the hand");
            check(s.human.getLibrary().size()==5&&s.game.getState().getZone(memory.getId())==Zone.EXILED,"Remaining looked-at cards stay in library; resolved flashback follows native exile");
            save("memory-deluge-complete",s);
        }finally{executor.shutdownNow();s.stop();}
    }
    static void exile()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();try{
            Card impulse=TriggerFixture.card("Act on Impulse"),bolt=TriggerFixture.card("Lightning Bolt"),mountain=TriggerFixture.card("Mountain"),island=TriggerFixture.card("Island");
            s.human.getLibrary().clear();s.game.cheat(s.human.getId(),Arrays.asList(bolt,mountain,island),Collections.singletonList(impulse),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            s.human.getManaPool().addMana(Mana.RedMana(4),s.game,impulse.getSpellAbility());
            check(run(s,()->s.human.cast(impulse.getSpellAbility(),s.game,false,null)),"Real Act on Impulse cast pays its native cost");
            s.game.getStack().resolve(s.game);s.game.applyEffects();
            Map<String,Object> boltOffer=offered(s,bolt),landOffer=offered(s,mountain);
            check(boltOffer!=null&&landOffer!=null&&"EXILED".equals(boltOffer.get("sourceZone")),"Native temporary exile permission offers both a spell and a legal land");
            s.priority.configure(JsonParser.parseString("{\"autoPass\":true,\"passWithOnlyMana\":true}").getAsJsonObject());check(!s.priority.decide(s,s.human,s.game),"Mana-only auto-pass preserves actual exile spell/land actions");save("exile-extension-offered",s);
            check(s.priority.legalityKnown&&s.priority.meaningfulActionCount>0,"Priority's native inventory includes temporary exile permissions");
            ActivatedAbility play=ability(s,mountain);check(run(s,()->s.human.activateAbility(play,s.game)),"Actual offered exiled land plays through native activation");
            check(s.game.getPermanent(mountain.getId())!=null&&!ActionabilityFixture.priority(s).contains(island.getId().toString()),"Native land-per-turn restriction removes the other exiled land offer");
            ActivatedAbility cast=ability(s,bolt);check(run(s,()->s.human.activateAbility(cast,s.game)),"Actual native exiled spell cast retains its permission and target/payment choices");s.game.getStack().resolve(s.game);
            check(s.bot.getLife()==17&&s.game.getState().getZone(bolt.getId())==Zone.GRAVEYARD,"Exiled Lightning Bolt really resolves and uses its normal destination");
            s.human.resetLandsPlayed();check(ActionabilityFixture.priority(s).contains(island.getId().toString()),"Reset initial fixture land allowance confirms remaining temporary permission");
            s.game.getContinuousEffects().removeEndOfTurnEffects(s.game);s.game.applyEffects();
            check(!ActionabilityFixture.priority(s).contains(island.getId().toString())&&s.game.getState().getZone(island.getId())==Zone.EXILED,"Native end-of-turn cleanup expires permission without moving the visible exiled card");save("exile-permission-expired",s);
        }finally{s.stop();}
    }
    static boolean keyword(Map<String,Object> card,String key){return list(card.get("currentKeywords")).stream().anyMatch(row->key.equals(row.get("id")));}
    static void jumpStart()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();try{
            Card insight=TriggerFixture.card("Chemister's Insight"),fuel=TriggerFixture.card("Island");
            s.human.getLibrary().clear();s.game.cheat(s.human.getId(),Arrays.asList(TriggerFixture.card("Opt"),TriggerFixture.card("Plains")),Collections.singletonList(fuel),Collections.emptyList(),Collections.singletonList(insight),TriggerFixture.NONE,TriggerFixture.NONE);
            s.human.getManaPool().addMana(Mana.BlueMana(4),s.game,insight.getSpellAbility());
            Map<String,Object> action=offered(s,insight);check(action!=null&&EngineBridge.JSON.toJson(action).contains("Discard 1 card"),"Jump-start sheet explicitly retains its native discard cost even when the native cost text is suppressed");
            save("jump-start-offer",s);
            check(run(s,()->s.human.activateAbility(ability(s,insight),s.game)),"Native jump-start accepts the offered discard and full mana payment");
            check(s.game.getState().getZone(fuel.getId())==Zone.GRAVEYARD&&s.game.getState().getZone(insight.getId())==Zone.STACK,"Jump-start's discard and stack commitment are separate native transitions");
            check(s.animationEvents.stream().anyMatch(e->"discard".equals(e.get("operation"))),"Accepted discard emits its own actual operation");
            s.game.getStack().resolve(s.game);s.game.processAction();s.publishAll();
            check(s.human.getHand().size()==2&&s.game.getState().getZone(insight.getId())==Zone.EXILED,"Jump-start really draws two then follows native exile replacement");save("jump-start-complete",s);
        }finally{s.stop();}
    }
    static void largeWipe()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();try{
            List<Card> human=new ArrayList<>(),enemy=new ArrayList<>();
            for(int i=0;i<60;i++)(i%2==0?human:enemy).add(TriggerFixture.card("Grizzly Bears"));
            Card survivor=TriggerFixture.card("Darksteel Myr"),wrath=TriggerFixture.card("Wrath of God");human.add(survivor);
            s.game.cheat(s.human.getId(),TriggerFixture.NONE,Collections.singletonList(wrath),human.stream().map(c->new PutToBattlefieldInfo(c,false)).toList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            s.game.cheat(s.bot.getId(),TriggerFixture.NONE,TriggerFixture.NONE,enemy.stream().map(c->new PutToBattlefieldInfo(c,false)).toList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            s.game.applyEffects();s.game.getState().clearTriggeredAbilities();s.animationEvents.clear();s.publishAll();save("wipe-before",s);
            s.human.getManaPool().addMana(Mana.WhiteMana(4),s.game,wrath.getSpellAbility());check(run(s,()->s.human.cast(wrath.getSpellAbility(),s.game,false,null)),"Real Wrath of God cast commits its native cost against sixty-one creatures");
            java.lang.reflect.Method resolve=GameImpl.class.getDeclaredMethod("resolve");resolve.setAccessible(true);
            ExecutorService executor=worker();try{executor.submit(()->{try{resolve.invoke(s.game);}catch(Exception error){throw new RuntimeException(error);}}).get(20,TimeUnit.SECONDS);}finally{executor.shutdownNow();}
            s.game.applyEffects();s.game.checkStateAndTriggered();s.publishAll();
            check(s.game.getBattlefield().getAllActivePermanents().size()==1&&s.game.getPermanent(survivor.getId())!=null,"Actual sixty-creature destruction leaves the indestructible survivor visible");
            List<Map<String,Object>> destroyed=s.animationEvents.stream().filter(e->"destroy".equals(e.get("operation"))).toList();
            check(destroyed.size()==60&&destroyed.stream().noneMatch(e->survivor.getId().toString().equals(e.get("targetId"))),"Exactly sixty confirmed native destroy outcomes exclude the survivor");
            Set<Object> batches=new HashSet<>();for(Map<String,Object> event:destroyed)batches.add(event.get("batchId"));
            check(batches.size()==1&&!batches.contains(null),"Simultaneous wipe events share the real native resolution identity");
            check(s.human.getGraveyard().size()+s.bot.getGraveyard().size()==61,"Sixty destroyed creatures plus resolved Wrath reach their actual graveyards");save("wipe-after",s);
        }finally{s.stop();}
    }
    static void targetIncarnation()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();try{
            Card doom=TriggerFixture.card("Doom Blade"),bear=TriggerFixture.card("Grizzly Bears");
            s.game.cheat(s.human.getId(),TriggerFixture.NONE,Collections.singletonList(doom),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            GameplayPresentationFixture.field(s,s.bot,bear);s.human.getManaPool().addMana(Mana.BlackMana(2),s.game,doom.getSpellAbility());s.game.applyEffects();
            check(run(s,()->s.human.cast(doom.getSpellAbility(),s.game,false,null)),"Actual Doom Blade cast retains its selected native permanent target");
            s.publishAll();Map<String,Object> stack=list(s.snapshot.get("stack")).get(0);
            check(((Collection<?>)stack.get("targetIds")).contains(bear.getId().toString()),"Live native stack target has its exact public object anchor ID");save("stack-target-live",s);
            s.game.getPermanent(bear.getId()).moveToZone(Zone.HAND,null,s.game,false);
            s.game.getCard(bear.getId()).moveToZone(Zone.BATTLEFIELD,null,s.game,false);s.game.applyEffects();s.publishAll();
            stack=list(s.snapshot.get("stack")).get(0);
            check(s.game.getPermanent(bear.getId())!=null&&((Collection<?>)stack.get("targetIds")).isEmpty()&&Boolean.TRUE.equals(list(stack.get("targets")).get(0).get("changedZones")),"Leaving and returning cannot redirect a stack arrow to a different native object incarnation");save("stack-target-changed-zones",s);
        }finally{s.stop();}
    }
    static void foretell()throws Exception{
        EngineBridge.Session s=GameplayPresentationFixture.room();try{
            Card card=TriggerFixture.card("Doomskar");s.game.cheat(s.human.getId(),TriggerFixture.NONE,Collections.singletonList(card),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            s.human.getManaPool().addMana(Mana.WhiteMana(7),s.game,card.getSpellAbility());s.game.applyEffects();
            ActivatedAbility foretell=s.human.getPlayable(s.game,true,Zone.ALL,false).stream().filter(a->a instanceof mage.abilities.keyword.ForetellAbility&&card.getId().equals(a.getSourceId())).findFirst().orElseThrow();
            check(run(s,()->s.human.activateAbility(foretell,s.game)),"Native Foretell pays its special action and exiles the card face down");s.game.applyEffects();
            check(offered(s,card)==null,"Native Foretell disallows casting in the turn it was foretold");
            // Explicit deterministic turn boundary; native Foretell controls the permission.
            s.game.getState().setTurnNum(s.game.getTurnNum()+1);s.game.applyEffects();Map<String,Object> action=offered(s,card);
            check(action!=null&&EngineBridge.JSON.toJson(action).contains("{1}{W}{W}")&&EngineBridge.JSON.toJson(action).contains("foretell"),"On the later turn native Foretell offers its actual exile cost");
            Map<String,Object> owner=s.card(s.game.getCard(card.getId()));check(Boolean.TRUE.equals(owner.get("faceDown"))&&"Doomskar".equals(object(owner.get("faceDownIdentity")).get("name")),"Foretold owner receives an explicit private identity for their exile extension");
            for(EngineBridge.Session peer:s.perspectives)if(peer!=s){Map<String,Object> hidden=peer.card(s.game.getCard(card.getId()));check(Boolean.TRUE.equals(hidden.get("hidden"))&&!hidden.containsKey("faceDownIdentity")&&!EngineBridge.JSON.toJson(hidden).contains("Doomskar"),"Other human never receives the foretold card identity or cost ability");}
            save("foretell-offered-owner",s);save("foretell-hidden-opponent",s.perspectives.get(1));
            check(run(s,()->s.human.activateAbility(ability(s,card),s.game)),"Owner's actual native foretell offer casts successfully from face-down exile");s.game.getStack().resolve(s.game);s.game.processAction();s.publishAll();
            check(s.game.getState().getZone(card.getId())==Zone.GRAVEYARD,"Foretold spell follows its normal native resolved destination");save("foretell-complete",s);
        }finally{s.stop();}
    }
    static void currentKeywords()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();try{
            Card angel=TriggerFixture.card("Serra Angel");GameplayPresentationFixture.field(s,s.human,angel);s.game.applyEffects();
            check(keyword(s.card(s.game.getPermanent(angel.getId())),"flying"),"Current native keyword projection starts with actual Flying");
            GainAbilityTargetEffect gain=new GainAbilityTargetEffect(HasteAbility.getInstance(),Duration.EndOfTurn);gain.setTargetPointer(new FixedTarget(angel.getId(),s.game));s.game.addEffect(gain,angel.getSpellAbility());s.game.applyEffects();
            check(keyword(s.card(s.game.getPermanent(angel.getId())),"haste"),"Native gained Haste appears immediately in effective keyword metadata");
            s.publishAll();save("effective-keywords-gained",s);
            LoseAllAbilitiesTargetEffect lose=new LoseAllAbilitiesTargetEffect(Duration.EndOfTurn);lose.setTargetPointer(new FixedTarget(angel.getId(),s.game));s.game.addEffect(lose,angel.getSpellAbility());s.game.applyEffects();
            Map<String,Object> stripped=s.card(s.game.getPermanent(angel.getId()));check(!keyword(stripped,"flying")&&!keyword(stripped,"haste"),"Native lost abilities remove ambient/current keyword signatures");
            check(((Collection<?>)object(stripped.get("printing")).get("keywords")).contains("flying"),"Original printing keywords remain separately inspectable");save("effective-keywords-stripped",s);
        }finally{s.stop();}
    }
    public static void main(String[] args)throws Exception{
        Thread.currentThread().setName("GAME zone fixture main");org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        Path root=Paths.get(args[0]);output=Paths.get(args[1]);Files.createDirectories(output);EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(ZoneActionsFixture.class.getClassLoader());
        String failure=null;try{flashback(false);flashback(true);exile();jumpStart();foretell();currentKeywords();largeWipe();targetIncarnation();}catch(Throwable problem){failure=problem.toString();problem.printStackTrace();}
        Files.writeString(output.resolve("result.json"),EngineBridge.JSON.toJson(EngineBridge.map("passed",failure==null,"failure",failure,"checks",checks,"scope","Real native Flashback/Memory Deluge, private multipick, Jump-start discard/payment, exiled spell/land offers and expiry through native cleanup, effective gained/lost abilities, and sixty-creature Wrath with an indestructible survivor and actual resolution batch. Deterministic initial zones/resources and explicit cleanup boundary; no complete shuffled-game or GUI claim.")));
        System.exit(failure==null?0:1);
    }
}
