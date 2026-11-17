package love2gathering;

import com.google.gson.*;
import mage.abilities.ActivatedAbility;
import mage.cards.Card;
import mage.constants.Zone;
import mage.counters.CounterType;
import mage.game.PutToBattlefieldInfo;
import mage.game.permanent.Permanent;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.stream.Collectors;

/** Native integration regressions for the November 17 upstream update. Only initial zones/resources are fixtures. */
public final class UpstreamCompatibilityFixture {
    static final List<String> checks=new ArrayList<>();
    static void check(boolean value,String label){if(!value)throw new AssertionError(label);checks.add(label);}
    static void battlefield(EngineBridge.Session s,Card... cards){
        s.game.cheat(s.human.getId(),TriggerFixture.NONE,TriggerFixture.NONE,Arrays.stream(cards).map(c->new PutToBattlefieldInfo(c,false)).collect(Collectors.toList()),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
        s.game.applyEffects();s.game.getState().clearTriggeredAbilities();s.game.getStack().clear();
    }
    static void registry(){
        List<String> newCards=Arrays.asList("Abyssal Lotus","Archnemesis","Azog, Moria's Ruin","Borg Incursion","Calmwater Mentor","Dack Fayden, Helping Hand","Doom's Time Platform","Elrond, Moon-Reader","Extract Power","Eye of Duskmantle","Galactus, Devourer of Worlds","Glorious Purpose","H.E.R.B.I.E., Lovable Robot","Iron Monger, Sadistic Tycoon","Jace, Multiverse Architect","Jace's Machinations","Jhoira, Weatherlight Corsair","Living Laser","Political Triumph","Ring of Unity","Robot Domination","Salinae, the Ocean Mother","Sanctum Lurker","Sauron, Dino Devotee","Shimmering Citadel","Soundwave, Sonic Spy","Taskmaster, Mercenary Mimic","Tecton, Malignant Ruin","Teferi's Reproach","Typhoid Mary, Fractured","U.S.S. Voyager, Lone Wanderer","Uldaros Theorix","Ultron, Unlimited","Woodland Weavemaster");
        @SuppressWarnings("unchecked")List<String> installed=(List<String>)NativeCapabilities.cards().get("names");
        for(String name:newCards){Card card=TriggerFixture.card(name);check(name.equals(card.getName())&&installed.contains(name),"New concrete card is installed: "+name);}
        check("Nimble Obstructionist".equals(TriggerFixture.card("Nimble Obstructionist").getName()),"Unchanged cards link against updated native target-filter signatures");
        check("c5a5215fa086f487c793627446d5d27e81dfbc97".equals(NativeCapabilities.cards().get("engineRevision")),"Installed registry reports the exact updated revision");
        for(String set:Arrays.asList("NAU","NAC","PW27"))check(EngineBridge.cardMap.entrySet().stream().anyMatch(e->e.getValue().getAsJsonObject().getAsJsonObject("printings").has(set)),"Generated card map includes new set "+set);
    }
    static void manaEvent(){
        EngineBridge.Session s=ActionabilityFixture.setup();
        try{
            Card swamp=TriggerFixture.card("Swamp");battlefield(s,swamp);s.animationEvents.clear();
            ActivatedAbility ability=s.human.usableManaAbilities(s.game.getPermanent(swamp.getId()),s.game).values().iterator().next();
            check(s.human.activateAbility(ability,s.game),"Native ordinary mana activation succeeds");
            check(s.game.getStack().isEmpty()&&s.human.getManaPool().getBlack()==1,"Mana event needs no stack object and adds native mana");
            check(s.animationEvents.stream().anyMatch(e->"ACTIVATED_ABILITY".equals(e.get("nativeType"))&&swamp.getId().toString().equals(e.get("sourceId"))),"Bridge projects upstream mana ACTIVATED_ABILITY without a stack object");
            check(s.error==null,"Mana activation leaves the bridge healthy");
        }finally{s.stop();}
    }
    static void exhaustMana()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService executor=Executors.newSingleThreadExecutor(r->new Thread(r,"GAME upstream exhaust fixture"));
        try{
            Card loot=TriggerFixture.card("Loot, the Pathfinder"),forest=TriggerFixture.card("Forest");battlefield(s,loot,forest);
            check(s.human.activateAbility(s.human.usableManaAbilities(s.game.getPermanent(forest.getId()),s.game).values().iterator().next(),s.game),"Forest supplies native exhaust cost");
            ActivatedAbility exhaust=s.human.usableManaAbilities(s.game.getPermanent(loot.getId()),s.game).values().stream().filter(a->a.getClass().getSimpleName().equals("ExhaustManaAbility")).findFirst().orElseThrow();
            Future<Boolean> activation=executor.submit(()->s.human.activateAbility(exhaust,s.game));Map<String,Object> prompt=ActionabilityFixture.waitPrompt(s,-1);
            @SuppressWarnings("unchecked")Map<String,Object> wheel=(Map<String,Object>)prompt.get("manaWheel");
            check(wheel!=null&&"color".equals(wheel.get("kind"))&&loot.getId().toString().equals(wheel.get("sourceId")),"Upstream exhaust mana uses the generic entitled color wheel");
            JsonObject answer=new JsonObject();answer.addProperty("promptId",((Number)prompt.get("id")).longValue());answer.addProperty("type","string");answer.addProperty("value","Blue");s.action(answer);
            check(activation.get(10,TimeUnit.SECONDS),"Native exhaust accepts the offered color response");
            check(s.game.getStack().isEmpty()&&s.human.getManaPool().getBlue()==3,"Loot exhaust resolves as native mana, without the stack");
            check(s.error==null,"Updated exhaust mana leaves bridge healthy");
        }finally{executor.shutdownNow();s.stop();}
    }
    static void zeroLoyalty(){
        EngineBridge.Session s=ActionabilityFixture.setup();
        try{
            Card lurker=TriggerFixture.card("Sanctum Lurker"),liliana=TriggerFixture.card("Liliana of the Veil");battlefield(s,lurker,liliana);
            Permanent walker=s.game.getPermanent(liliana.getId());walker.removeCounters(CounterType.LOYALTY.getName(),3,null,s.game);s.game.applyEffects();s.game.checkStateAndTriggered();
            walker=s.game.getPermanent(liliana.getId());check(walker!=null&&walker.getCounters(s.game).getCount(CounterType.LOYALTY)==0,"Native Sanctum Lurker keeps the zero-loyalty planeswalker");
            Map<String,Object> view=s.card(walker);@SuppressWarnings("unchecked")Map<String,Object> counters=(Map<String,Object>)view.get("counters");
            check(counters.get(CounterType.LOYALTY.getName())==null||((Number)counters.get(CounterType.LOYALTY.getName())).intValue()==0,"Projection retains native zero loyalty without frontend death heuristics");
            s.game.getPermanent(lurker.getId()).moveToZone(Zone.GRAVEYARD,null,s.game,false);s.game.applyEffects();s.game.checkStateAndTriggered();
            check(s.game.getPermanent(liliana.getId())==null&&s.human.getGraveyard().contains(liliana.getId()),"Native state-based action removes the walker when Lurker leaves");
        }finally{s.stop();}
    }
    public static void main(String[] args)throws Exception{
        org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        Path root=Paths.get(args[0]);EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(UpstreamCompatibilityFixture.class.getClassLoader());
        registry();manaEvent();exhaustMana();zeroLoyalty();
        String report=EngineBridge.JSON.toJson(EngineBridge.map("passed",true,"engineRevision",NativeCapabilities.ENGINE_REVISION,"scope","Actual installed card classes, native mana events/ExhaustManaAbility color responses and Sanctum Lurker state-based actions with deterministic initial zones; no frontend UI or production match","checks",checks));
        Files.writeString(root.resolve("bridge/tests/upstream-compatibility-report.json"),report+"\n");System.out.println(report);
    }
}
