package love2gathering;

import com.google.gson.*;
import mage.cards.Card;
import mage.constants.*;
import mage.game.GameImpl;
import mage.game.combat.CombatGroup;
import mage.game.turn.*;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

/** Actual native declarations, bridge answers, Ayara costs and combat damage.
 * Only initial zones/turn resources are deterministic fixtures. */
public final class CombatTimingFixture {
    static int checks;
    static void check(boolean value,String message){if(!value)throw new AssertionError(message);checks++;}
    static long id(Map<String,Object> p){return ((Number)p.get("id")).longValue();}
    static void choose(EngineBridge.Session s,Map<String,Object> p,String choice)throws Exception{NativeViewFixture.answer(s,p,choice);}
    static Map<String,Object> prompt(EngineBridge.Session s,long previous)throws Exception{return ActionabilityFixture.waitPrompt(s,previous);}
    static Map<String,Object> run(String scenario,boolean before,boolean trample,boolean afterFirst)throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=NativeViewFixture.executor();
        try{
            java.lang.reflect.Field cursor=GameImpl.class.getDeclaredField("playerList");cursor.setAccessible(true);cursor.set(s.game,s.game.getState().getPlayerList(s.human.getId()));
            Card ayara=TriggerFixture.card("Ayara, First of Locthwain"),rat=TriggerFixture.card("Relentless Rats");
            Card attacker=TriggerFixture.card(trample?"Colossal Dreadmaw":afterFirst?"Fencing Ace":"Grizzly Bears");
            NativeViewFixture.battlefield(s,s.human.getId(),ayara,rat);NativeViewFixture.battlefield(s,s.bot.getId(),attacker);
            s.game.cheat(s.human.getId(),Collections.singletonList(TriggerFixture.card("Forest")),TriggerFixture.NONE,Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            ((mage.game.permanent.PermanentImpl)s.game.getPermanent(ayara.getId())).removeSummoningSickness();
            s.game.getState().clearTriggeredAbilities();s.game.getStack().clear();
            s.game.getTurn().setPhase(new CombatPhase());s.game.getPhase().setStep(before?new DeclareAttackersStep():new DeclareBlockersStep());
            s.game.getState().setActivePlayerId(s.bot.getId());s.game.getState().setPriorityPlayerId(s.human.getId());
            s.game.getCombat().getDefenders().add(s.human.getId());s.game.getCombat().setAttacker(s.bot.getId());
            check(s.game.getCombat().addAttackerToCombat(attacker.getId(),s.human.getId(),s.game),"Native attacker enters combat");
            CombatGroup group=s.game.getCombat().findGroup(attacker.getId());
            long previous=-1;
            if(!before){
                Future<?> declaration=worker.submit(()->s.game.getCombat().selectBlockers(s.game));
                Map<String,Object> p=prompt(s,previous);check(Boolean.FALSE.equals(NativeViewFixture.object(p.get("combat")).get("declarationConfirmed")),"Block choice is explicitly provisional");
                check(!Boolean.TRUE.equals(NativeViewFixture.list(NativeProjection.combat(s).get("groups")).get(0).get("declarationConfirmed")),"No confirmed block before native declaration completes");
                previous=id(p);choose(s,p,rat.getId().toString());p=prompt(s,previous);
                check(group.getBlocked()&&group.getBlockers().contains(rat.getId()),"Native assignment exists while still provisional");
                check(!Boolean.TRUE.equals(NativeViewFixture.list(NativeProjection.combat(s).get("groups")).get(0).get("declarationConfirmed")),"Selected blocker alone is not confirmation");
                previous=id(p);choose(s,p,"done");declaration.get(10,TimeUnit.SECONDS);s.game.getCombat().acceptBlockers(s.game);
                check(Boolean.TRUE.equals(NativeViewFixture.list(NativeProjection.combat(s).get("groups")).get(0).get("declarationConfirmed")),"Actual DECLARED_BLOCKERS acknowledges confirmed block");
            }
            if(afterFirst){
                s.game.getPhase().setStep(new CombatDamageStep(true));
                worker.submit(()->s.game.getPhase().getStep().beginStep(s.game,s.bot.getId())).get(10,TimeUnit.SECONDS);
                check(s.game.getPermanent(rat.getId()).getDamage()==1&&s.human.getLife()==20,"Native first strike damages the Rat, not defending player");
                s.game.getPhase().setStep(new CombatDamageStep(true));
            }
            JsonObject priority=JsonParser.parseString("{\"autoPass\":true,\"stops\":{\"opponent\":[\"DECLARE_BLOCKERS\"]}}").getAsJsonObject();
            priority.addProperty("command","configure");s.priorityCommand(priority);
            Future<Boolean> response=worker.submit(()->s.human.priority(s.game));Map<String,Object> p=prompt(s,previous);
            check(Boolean.TRUE.equals(p.get("priority"))&&((Collection<?>)p.get("actionable")).contains(ayara.getId().toString()),"Native priority offers Ayara's genuinely payable ability");
            if(!before&&!afterFirst)check("stop".equals(p.get("priorityReason")),"Configured stop holds after confirmed blockers and before damage");
            previous=id(p);choose(s,p,ayara.getId().toString());p=prompt(s,previous);
            if("choose_ability".equals(p.get("type"))){
                check(NativeViewFixture.list(p.get("choices")).size()==1,"Native Ayara ability selector offers only actual activated ability");
                previous=id(p);ActionabilityFixture.answer(s,p,NativeViewFixture.list(p.get("choices")).get(0));p=prompt(s,previous);
            }
            check(p.get("pendingAction")!=null&&!Boolean.TRUE.equals(p.get("priority")),"Sacrifice is a native cost choice, never automatic priority: "+EngineBridge.JSON.toJson(p));
            check(((Collection<?>)p.get("actionable")).contains(rat.getId().toString()),"Native cost offers the actual black Rat");
            previous=id(p);choose(s,p,rat.getId().toString());response.get(10,TimeUnit.SECONDS);
            check(s.game.getPermanent(rat.getId())==null&&s.human.getGraveyard().contains(rat.getId()),"Production bridge answer actually sacrifices Rat");
            check(s.game.getPermanent(ayara.getId()).isTapped()&&s.game.getStack().size()==1,"Native activation pays tap cost and puts draw ability on stack");
            check(group.getBlocked()==!before&&group.getBlockers().isEmpty(),"Sacrifice preserves confirmed blocked state without a blocker");
            int handBefore=s.human.getHand().size();worker.submit(()->s.game.getStack().resolve(s.game)).get(10,TimeUnit.SECONDS);
            check(s.game.getStack().isEmpty()&&s.human.getHand().size()==handBefore+1,"Native draw ability resolves before combat can advance");
            if(before){
                s.game.getPhase().setStep(new DeclareBlockersStep());Future<?> declaration=worker.submit(()->s.game.getCombat().selectBlockers(s.game));
                declaration.get(10,TimeUnit.SECONDS);s.game.getCombat().acceptBlockers(s.game);
                check(!group.getBlocked(),"Sacrificing before declaration creates no block");
            }
            int life=s.human.getLife();
            s.game.getPhase().setStep(new CombatDamageStep(false));
            worker.submit(()->s.game.getPhase().getStep().beginStep(s.game,s.bot.getId())).get(10,TimeUnit.SECONDS);
            int damage=life-s.human.getLife(),expected=trample?6:before?2:0;
            check(damage==expected,"Native combat damage: "+scenario+" expected "+expected+", got "+damage);
            s.publish();Files.writeString(Paths.get("/tmp/love2gathering-combat-"+scenario+"-frame.json"),EngineBridge.JSON.toJson(s.snapshot));
            return EngineBridge.map("scenario",scenario,"passed",true,"confirmedBlockBeforeSacrifice",!before,"blockedAfterSacrifice",group.getBlocked(),"blockersRemaining",group.getBlockers().size(),"nativeDamageToDefender",damage,"lifeAfter",s.human.getLife(),"nativeFirstStrikeDamageToRat",afterFirst?1:0);
        }finally{worker.shutdownNow();s.stop();}
    }
    static Map<String,Object> emptyStop()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=NativeViewFixture.executor();
        try{
            s.game.getTurn().setPhase(new CombatPhase());s.game.getPhase().setStep(new DeclareBlockersStep());
            s.game.getState().setActivePlayerId(s.bot.getId());s.game.getState().setPriorityPlayerId(s.human.getId());
            JsonObject c=JsonParser.parseString("{\"command\":\"configure\",\"autoPass\":true,\"stops\":{\"opponent\":[\"DECLARE_BLOCKERS\"]}}").getAsJsonObject();s.priorityCommand(c);
            Future<Boolean> response=worker.submit(()->s.human.priority(s.game));Map<String,Object> p=prompt(s,-1);
            check("stop".equals(p.get("priorityReason"))&&s.priority.meaningfulActionCount==0,"Before-damage stop holds a real empty bluff window");
            check(Boolean.TRUE.equals(s.priority.view(p).get("canEndTurn"))&&"DECLARE_BLOCKERS".equals(s.priority.view(p).get("stopStep")),"Stop is visibly acknowledged at actual native blocker step");
            choose(s,p,"done");check(!response.get(10,TimeUnit.SECONDS)&&s.human.isPassed(),"Only explicit Pass releases empty selected stop");
            return EngineBridge.map("passed",true,"step","DECLARE_BLOCKERS","meaningfulActions",0,"explicitPassRequired",true);
        }finally{worker.shutdownNow();s.stop();}
    }
    static Map<String,Object> tokenEligibility(){
        EngineBridge.Session s=ActionabilityFixture.setup();
        try{
            Card source=TriggerFixture.card("Ayara, First of Locthwain"),attacker=TriggerFixture.card("Grizzly Bears");
            NativeViewFixture.battlefield(s,s.human.getId(),source);NativeViewFixture.battlefield(s,s.bot.getId(),attacker);
            new mage.game.permanent.token.RatToken().putOntoBattlefield(1,s.game,source.getSpellAbility(),s.human.getId());
            new mage.game.permanent.token.RatCantBlockToken().putOntoBattlefield(1,s.game,source.getSpellAbility(),s.human.getId());s.game.applyEffects();
            s.game.getCombat().getDefenders().add(s.human.getId());s.game.getCombat().addAttackerToCombat(attacker.getId(),s.human.getId(),s.game);
            List<mage.game.permanent.Permanent> rats=new ArrayList<>();for(mage.game.permanent.Permanent p:s.game.getBattlefield().getAllActivePermanents())if(p.isToken())rats.add(p);
            check(rats.size()==2,"Both native Rat token variants were actually created");
            int legal=0,illegal=0;for(mage.game.permanent.Permanent rat:rats){
                Map<String,Object> preview=NativeProjection.blockerOptions(s,Collections.singleton(rat.getId())).get(0);
                if(((Collection<?>)preview.get("legalAttackerIds")).contains(attacker.getId().toString()))legal++;
                else{illegal++;check(!NativeViewFixture.list(preview.get("unavailable")).isEmpty(),"Rat that cannot block exposes native unavailability reason");}
            }
            check(legal==1&&illegal==1,"Native canBlock distinguishes normal Rat from 'This token can't block' Rat");
            return EngineBridge.map("passed",true,"normalRatCanBlock",true,"cantBlockRatCanBlock",false);
        }finally{s.stop();}
    }
    static Map<String,Object> gainedKeywords()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=NativeViewFixture.executor();
        try{
            Card goreclaw=TriggerFixture.card("Goreclaw, Terror of Qal Sisma"),sage=TriggerFixture.card("Primordial Sage"),small=TriggerFixture.card("Grizzly Bears");
            NativeViewFixture.battlefield(s,s.bot.getId(),goreclaw,sage,small);
            s.game.getTurn().setPhase(new CombatPhase());s.game.getPhase().setStep(new DeclareAttackersStep());s.game.getState().setActivePlayerId(s.bot.getId());
            s.game.getCombat().setAttacker(s.bot.getId());s.game.getCombat().getDefenders().add(s.human.getId());
            for(Card card:Arrays.asList(goreclaw,sage,small))s.game.getCombat().declareAttacker(card.getId(),s.human.getId(),s.bot.getId(),s.game);
            worker.submit(()->{s.game.getCombat().resumeSelectAttackers(s.game);s.game.getState().handleSimultaneousEvent(s.game);s.game.checkStateAndTriggered();}).get(10,TimeUnit.SECONDS);
            check(s.game.getStack().size()==1,"Actual Goreclaw declaration creates its native attack trigger");
            worker.submit(()->s.game.getStack().resolve(s.game)).get(10,TimeUnit.SECONDS);s.game.applyEffects();
            for(Card card:Arrays.asList(goreclaw,sage)){
                Map<String,Object> view=s.card(s.game.getPermanent(card.getId()));
                check(((Collection<?>)view.get("keywords")).contains("trample"),"Native gained Trample projects actual ability identity on "+card.getName());
                check(view.get("currentRules").toString().lines().anyMatch("trample"::equals),"Live currentRules includes granted Trample independently of printed catalog text");
                check(!((Collection<?>)NativeViewFixture.object(view.get("printing")).get("keywords")).contains("trample"),"Original printing correctly has no inherent Trample");
                check(NativeViewFixture.list(view.get("abilityIcons")).stream().anyMatch(i->"ABILITY_TRAMPLE".equals(i.get("type"))),"Native ability icon identifies granted Trample for display");
            }
            check(!((Collection<?>)s.card(s.game.getPermanent(small.getId())).get("keywords")).contains("trample"),"Goreclaw's native power restriction excludes small attacker");
            s.publish();Files.writeString(Paths.get("/tmp/love2gathering-native-goreclaw-keywords-frame.json"),EngineBridge.JSON.toJson(s.snapshot));
            worker.submit(()->s.game.getState().removeEotEffects(s.game)).get(10,TimeUnit.SECONDS);
            check(!((Collection<?>)s.card(s.game.getPermanent(sage.getId())).get("keywords")).contains("trample"),"Native end-of-turn cleanup removes temporary keyword projection");
            return EngineBridge.map("passed",true,"trigger","Goreclaw attack","gainedKeywords",Collections.singletonList("trample"),"removedAtNativeEndOfTurn",true);
        }finally{worker.shutdownNow();s.stop();}
    }
    public static void main(String[] args)throws Exception{
        org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        Path root=Paths.get(args[0]);EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(CombatTimingFixture.class.getClassLoader());
        List<Map<String,Object>> results=Arrays.asList(run("confirmed-no-trample",false,false,false),run("before-declaration",true,false,false),run("confirmed-trample",false,true,false),run("after-first-strike",false,false,true));
        Map<String,Object> bluff=emptyStop(),rats=tokenEligibility(),keywords=gainedKeywords();
        String report=EngineBridge.JSON.toJson(EngineBridge.map("passed",true,"checks",checks,"scope","Real native rules with initial test zones and production Session.action answers; no Lua rule replacement","cases",results,"emptyBeforeDamageStop",bluff,"nativeRatTokenVariants",rats,"temporaryKeywords",keywords));
        Files.writeString(root.resolve("bridge/tests/combat-timing-report.json"),report+"\n");System.out.println(report);
    }
}
