package love2gathering;

import com.google.gson.*;
import mage.Mana;
import mage.abilities.*;
import mage.abilities.condition.common.EvokedCondition;
import mage.cards.Card;
import mage.constants.Zone;
import mage.game.GameImpl;
import mage.game.stack.Spell;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

/** Accepted native casts/costs and actual effects; only initial zones/resources are prepared. */
public final class MechanicCauseFixture {
    static Path output;static final List<Map<String,Object>> checks=new ArrayList<>();
    static void check(boolean value,String label){checks.add(EngineBridge.map("passed",value,"message",label));System.out.println((value?"PASS ":"FAIL ")+label);if(!value)throw new AssertionError(label);}
    @SuppressWarnings("unchecked")static List<Map<String,Object>> rows(Object value){return(List<Map<String,Object>>)value;}
    static void save(String name,EngineBridge.Session s)throws Exception{s.publishAll();Files.writeString(output.resolve(name+".json"),EngineBridge.JSON.toJson(s.snapshot));}
    static <T>T run(EngineBridge.Session s,Callable<T> operation)throws Exception{
        ExecutorService worker=ZoneActionsFixture.worker();try{
            long last=s.prompt==null?-1:ZoneActionsFixture.id(s.prompt);Future<T> future=worker.submit(operation);long until=System.nanoTime()+TimeUnit.SECONDS.toNanos(20);
            while(!future.isDone()&&System.nanoTime()<until){Map<String,Object> p=s.prompt;
                if(p!=null&&s.snapshot.get("prompt")==p&&ZoneActionsFixture.id(p)!=last){
                    List<Map<String,Object>> choices=rows(p.get("choices"));String type=String.valueOf(p.get("type"));Map<String,Object> selected=null;
                    System.out.println("PROMPT "+p.get("id")+" "+type+" "+p.get("message"));
                    if("play_mana".equals(type))selected=choices.stream().filter(c->"special".equals(c.get("id"))).findFirst().orElseGet(()->choices.stream().filter(c->"mana".equals(c.get("responseType"))).findFirst().orElse(null));
                    else if("ask".equals(type))selected=choices.stream().filter(c->Boolean.TRUE.equals(c.get("value"))).findFirst().orElse(null);
                    else if("choose_ability".equals(type))selected=choices.stream().filter(c->"uuid".equals(c.get("responseType"))).findFirst().orElse(null);
                    else if("choose_choice".equals(type))selected=choices.stream().filter(c->"string".equals(c.get("responseType"))&&!"cancel-choice".equals(c.get("id"))).findFirst().orElse(null);
                    else if("pick_target".equals(type))selected=choices.stream().filter(c->"uuid".equals(c.get("responseType"))&&!Boolean.TRUE.equals(c.get("selected"))&&!Boolean.FALSE.equals(c.get("selectable"))).findFirst().orElseGet(()->choices.stream().filter(c->"boolean".equals(c.get("responseType"))).findFirst().orElse(null));
                    else if("select".equals(type)){
                        Object combat=p.get("combat"),attackers=combat instanceof Map?((Map<?,?>)combat).get("selectedAttackerIds"):null;boolean declared=attackers instanceof Collection&&!((Collection<?>)attackers).isEmpty();
                        selected=choices.stream().filter(c->(declared?"boolean":"uuid").equals(c.get("responseType"))).findFirst().orElse(null);
                    }
                    else if("multi_amount".equals(type)){
                        last=ZoneActionsFixture.id(p);GameplayPresentationFixture.answer(s,p,"multi_amount",rows(p.get("amountMessages")).stream().map(m->m.getOrDefault("defaultValue",m.get("min"))).toList());continue;
                    }
                    if(selected==null)throw new AssertionError("Unhandled mechanic prompt "+EngineBridge.JSON.toJson(p));
                    last=ZoneActionsFixture.id(p);ZoneActionsFixture.answer(s,p,selected);
                }else Thread.sleep(2);
            }return future.get(1,TimeUnit.SECONDS);
        }finally{worker.shutdownNow();}
    }
    static void resolve(EngineBridge.Session s)throws Exception{
        java.lang.reflect.Method resolve=GameImpl.class.getDeclaredMethod("resolve");resolve.setAccessible(true);
        run(s,()->{resolve.invoke(s.game);return true;});s.game.applyEffects();s.game.processAction();s.game.checkStateAndTriggered();s.publishAll();
    }
    static boolean event(EngineBridge.Session s,String operation,String mechanic){return s.animationEvents.stream().anyMatch(e->operation.equals(e.get("operation"))&&(mechanic==null||mechanic.equals(e.get("mechanic"))));}
    static void evoke()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();try{
            Card card=TriggerFixture.card("Mulldrifter");s.human.getLibrary().clear();
            s.game.cheat(s.human.getId(),Arrays.asList(TriggerFixture.card("Island"),TriggerFixture.card("Forest"),TriggerFixture.card("Mountain")),Collections.singletonList(card),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            s.human.getManaPool().addMana(Mana.BlueMana(3),s.game,card.getSpellAbility());s.game.applyEffects();s.animationEvents.clear();save("evoke-before",s);
            check(run(s,()->s.human.cast(card.getSpellAbility(),s.game,false,null)),"Actual Mulldrifter accepts native Evoke cost with only three mana");
            Spell spell=(Spell)s.game.getStack().peek();check(EvokedCondition.instance.apply(s.game,spell.getSpellAbility()),"Native spell records the paid Evoke costs tag");
            check(event(s,"cast","evoke"),"Actual paid Evoke identity reaches the cast animation event");save("evoke-cast",s);
            resolve(s);check(s.game.getPermanent(card.getId())!=null,"Evoked permanent really enters before its sacrifice trigger resolves");save("evoke-entered",s);
            for(int i=0;i<5&&!s.game.getStack().isEmpty();i++)resolve(s);
            check(s.game.getState().getZone(card.getId())==Zone.GRAVEYARD,"Actual native Evoke sacrifice resolves after entry");
            check(event(s,"sacrifice","evoke"),"Actual Evoke sacrifice retains its exact native cause identity");save("evoke-complete",s);
        }finally{s.stop();}
    }
    static void extort()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();try{
            Card extort=TriggerFixture.card("Basilica Screecher"),spell=TriggerFixture.card("Memnite");GameplayPresentationFixture.field(s,s.human,extort);
            s.game.cheat(s.human.getId(),TriggerFixture.NONE,Collections.singletonList(spell),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            s.game.applyEffects();s.game.getState().clearTriggeredAbilities();s.human.getManaPool().addMana(Mana.WhiteMana(1),s.game,spell.getSpellAbility());s.animationEvents.clear();save("extort-before",s);
            check(run(s,()->s.human.cast(spell.getSpellAbility(),s.game,false,null)),"Real Memnite cast causes native Extort trigger");s.game.checkStateAndTriggered();save("extort-trigger",s);
            check(s.game.getStack().peek().getStackAbility() instanceof mage.abilities.keyword.ExtortAbility,"Native Extort ability is the actual resolving stack object");
            check(s.animationEvents.stream().anyMatch(e->"TRIGGERED_ABILITY".equals(e.get("nativeType"))&&"extort".equals(e.get("mechanic"))),"Native Extort trigger retains its exact ability identity");resolve(s);
            check(s.human.getLife()==21&&s.bot.getLife()==19,"Accepted Extort payment causes actual one-life transfer");
            check(event(s,"life_loss","extort")&&event(s,"life_gain","extort"),"Actual life loss and gain both retain the resolving native Extort cause");save("extort-complete",s);
        }finally{s.stop();}
    }
    static void convoke()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();try{
            Card spell=TriggerFixture.card("Scatter the Seeds");Card[] creatures=new Card[5];for(int i=0;i<5;i++)creatures[i]=TriggerFixture.card("Grizzly Bears");GameplayPresentationFixture.field(s,s.human,creatures);
            s.game.cheat(s.human.getId(),TriggerFixture.NONE,Collections.singletonList(spell),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            s.game.applyEffects();s.game.getState().clearTriggeredAbilities();s.animationEvents.clear();save("convoke-before",s);
            check(run(s,()->s.human.cast(spell.getSpellAbility(),s.game,false,null)),"Actual Scatter the Seeds pays all five mana via native Convoke");
            check(Arrays.stream(creatures).allMatch(c->s.game.getPermanent(c.getId()).isTapped()),"Exactly the five accepted native contributors are tapped");
            check(s.human.getManaPool().count()==0,"Convoke does not fabricate mana in the pool");
            check(s.animationEvents.stream().filter(e->"tap".equals(e.get("operation"))&&"convoke".equals(e.get("mechanic"))&&spell.getId().toString().equals(e.get("paymentForId"))).count()==5,"Exactly five accepted Convoke tap events point to their real spell payment");
            check(s.animationEvents.stream().anyMatch(e->"SPELL_CAST".equals(e.get("nativeType"))&&"convoke".equals(e.get("paymentMechanic"))&&((Collection<?>)e.get("contributors")).size()==5),"Committed spell exports five authoritative native costs-tag contributors");save("convoke-cast",s);resolve(s);
            check(s.game.getBattlefield().getAllActivePermanents().size()==8,"Native Convoke spell really resolves into three Saprolings");save("convoke-complete",s);
        }finally{s.stop();}
    }
    static void mutate()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();try{
            Card bear=TriggerFixture.card("Grizzly Bears"),octopus=TriggerFixture.card("Sea-Dasher Octopus");GameplayPresentationFixture.field(s,s.human,bear);
            s.game.cheat(s.human.getId(),TriggerFixture.NONE,Collections.singletonList(octopus),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            s.human.getManaPool().addMana(Mana.BlueMana(2),s.game,octopus.getSpellAbility());s.game.applyEffects();s.game.getState().clearTriggeredAbilities();s.animationEvents.clear();save("mutate-before",s);
            ActivatedAbility mutate=s.human.getPlayable(s.game,true,Zone.ALL,false).stream().filter(a->a instanceof mage.abilities.keyword.MutateAbility&&octopus.getId().equals(a.getSourceId())).findFirst().orElseThrow();
            check(run(s,()->s.human.activateAbility(mutate,s.game)),"Actual native Mutate ability selects its legal non-Human target and pays two mana");save("mutate-cast",s);resolve(s);
            check(event(s,"merge",null),"Successful native Mutate emits its actual CREATURE_MUTATED merge outcome");
            check(s.game.getBattlefield().getAllActivePermanents().size()==1&&s.animationEvents.stream().noneMatch(e->Boolean.TRUE.equals(e.get("entry"))),"Mutating onto an existing permanent creates no battlefield entry or duplicate permanent");save("mutate-complete",s);
        }finally{s.stop();}
    }
    static void faceUp()throws Exception{
        EngineBridge.Session s=GameplayPresentationFixture.room();try{
            Card card=TriggerFixture.card("Monastery Flock");s.game.cheat(s.human.getId(),TriggerFixture.NONE,Collections.singletonList(card),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            s.human.getManaPool().addMana(Mana.BlueMana(5),s.game,card.getSpellAbility());s.game.applyEffects();s.animationEvents.clear();save("morph-before",s);
            ActivatedAbility morph=s.human.getPlayable(s.game,true,Zone.ALL,false).stream().filter(a->a instanceof mage.abilities.keyword.MorphAbility&&card.getId().equals(a.getSourceId())).findFirst().orElseThrow();
            check(run(s,()->s.human.activateAbility(morph,s.game)),"Actual native Morph ability casts its face-down spell for three mana");resolve(s);
            check(s.game.getPermanent(card.getId()).isFaceDown(s.game),"Native resolved Morph permanent stays face down before its special action");save("morph-face-down",s);
            for(EngineBridge.Session peer:s.perspectives)if(peer!=s){Map<String,Object> visible=peer.card(s.game.getPermanent(card.getId()));check(Boolean.TRUE.equals(visible.get("hidden"))&&!EngineBridge.JSON.toJson(visible).contains("Monastery Flock"),"Other native viewer sees no hidden face or mechanics before face-up");}
            long entries=s.animationEvents.stream().filter(e->Boolean.TRUE.equals(e.get("entry"))).count();
            ActivatedAbility faceUp=s.human.getPlayable(s.game,true,Zone.ALL,false).stream().filter(a->a instanceof mage.abilities.common.TurnFaceUpAbility&&card.getId().equals(a.getSourceId())).findFirst().orElseThrow();
            check(run(s,()->s.human.activateAbility(faceUp,s.game)),"Actual native turn-face-up special action pays its own cost immediately");s.game.applyEffects();s.game.processAction();s.game.checkStateAndTriggered();
            check(!s.game.getPermanent(card.getId()).isFaceDown(s.game)&&event(s,"face_up",null),"Accepted native face-up action emits its public material operation");
            check(s.animationEvents.stream().filter(e->Boolean.TRUE.equals(e.get("entry"))).count()==entries,"Turning face up creates no phantom entry or entry slam");save("morph-face-up",s);
        }finally{s.stop();}
    }
    static void combatTraits()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();try{
            Card flyer=TriggerFixture.card("Skyknight Legionnaire"),spider=TriggerFixture.card("Giant Spider");GameplayPresentationFixture.field(s,s.human,flyer);GameplayPresentationFixture.field(s,s.bot,spider);s.game.applyEffects();s.animationEvents.clear();
            s.game.getCombat().setAttacker(s.human.getId());s.game.getCombat().getDefenders().add(s.bot.getId());s.game.getPhase().setStep(new mage.game.turn.DeclareAttackersStep());save("haste-before",s);
            final EngineBridge.Session haste=s;run(s,()->{haste.game.getCombat().selectAttackers(haste.game);return true;});s.game.processAction();
            check(s.game.getCombat().getAttackers().contains(flyer.getId()),"Newly entered native Haste creature accepts actual attacker selection");
            check(s.animationEvents.stream().anyMatch(e->"ATTACKER_DECLARED".equals(e.get("nativeType"))&&flyer.getId().toString().equals(e.get("sourceId"))),"Accepted native Haste attack emits its exact actor identity");save("haste-attacking",s);
            s.game.getPhase().setStep(new mage.game.turn.DeclareBlockersStep());
            check(s.game.getPermanent(spider.getId()).canBlock(flyer.getId(),s.game),"Native Reach blocker can legally intercept this actual Flying attacker");
            mage.game.combat.CombatGroup group=s.game.getCombat().getGroups().get(0);group.addBlocker(spider.getId(),s.bot.getId(),s.game);group.acceptBlockers(s.game);s.game.processAction();
            check(s.animationEvents.stream().anyMatch(e->"BLOCKER_DECLARED".equals(e.get("nativeType"))&&spider.getId().toString().equals(e.get("sourceId"))&&flyer.getId().toString().equals(e.get("targetId"))),"Native Reach block retains exact blocker and incoming attacker identities");save("reach-blocking",s);
        }finally{s.stop();}
        s=ActionabilityFixture.setup();try{
            Card trample=TriggerFixture.card("Colossal Dreadmaw"),bear=TriggerFixture.card("Grizzly Bears");GameplayPresentationFixture.field(s,s.human,trample);GameplayPresentationFixture.field(s,s.bot,bear);s.game.applyEffects();s.animationEvents.clear();
            s.game.getCombat().setAttacker(s.human.getId());s.game.getCombat().getDefenders().add(s.bot.getId());s.game.getCombat().addAttackerToCombat(trample.getId(),s.bot.getId(),s.game);mage.game.combat.CombatGroup group=s.game.getCombat().getGroups().get(0);group.addBlocker(bear.getId(),s.bot.getId(),s.game);group.acceptBlockers(s.game);s.game.getPhase().setStep(new mage.game.turn.CombatDamageStep(false));save("trample-before",s);
            final EngineBridge.Session current=s;run(s,()->{group.assignDamageToBlockers(false,current.game);return true;});s.game.processAction();
            check(s.bot.getLife()==16&&s.game.getPermanent(bear.getId()).getDamage()==2,"Native prepared Trample combat applies chosen lethal damage and exact four player damage");
            check(s.animationEvents.stream().anyMatch(e->"damage".equals(e.get("type"))&&Boolean.TRUE.equals(e.get("combat"))&&trample.getId().toString().equals(e.get("sourceId"))&&current.bot.getId().toString().equals(e.get("targetId"))),"Actual positive native Trample combat event exposes its public actor and player target");save("trample-complete",s);
        }finally{s.stop();}
    }
    public static void main(String[]args)throws Exception{
        Thread.currentThread().setName("GAME mechanic cause main");org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        Path root=Paths.get(args[0]);output=Paths.get(args[1]);Files.createDirectories(output);EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(MechanicCauseFixture.class.getClassLoader());
        String failure=null;try{evoke();extort();convoke();mutate();faceUp();combatTraits();}catch(Throwable error){failure=error.toString();error.printStackTrace();}
        Files.writeString(output.resolve("result.json"),EngineBridge.JSON.toJson(EngineBridge.map("passed",failure==null,"failure",failure,"checks",checks,"scope","Actual native accepted Evoke, Extort, Convoke, Mutate and Morph/face-up casts, costs and resolutions; native Haste attack/Reach block and prepared Trample combat damage on GAME threads. Prepared initial zones/resources/Trample group only; no production match/UI or every composed mechanic claim.")));System.exit(failure==null?0:1);
    }
}
