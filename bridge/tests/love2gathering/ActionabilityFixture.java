package love2gathering;

import com.google.gson.*;
import mage.Mana;
import mage.MageObject;
import mage.abilities.*;
import mage.cards.Card;
import mage.constants.*;
import mage.game.PutToBattlefieldInfo;
import mage.game.events.PlayerQueryEvent;
import mage.game.permanent.Permanent;
import mage.game.turn.PreCombatMainStep;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.stream.Collectors;

/** Real-engine playability and prompt tests; only the initial zones/resources are fixtures. */
public final class ActionabilityFixture {
    static void require(boolean b,String message) { if(!b)throw new AssertionError(message); }
    static EngineBridge.Session setup() {
        EngineBridge.Session s=TriggerFixture.session();
        s.game.getPhase().setStep(new PreCombatMainStep());
        return s;
    }
    static Set<String> priority(EngineBridge.Session s) {
        s.game.firePriorityEvent(s.human.getId());
        @SuppressWarnings("unchecked") List<String> ids=(List<String>)s.prompt.get("actionable");
        return new LinkedHashSet<>(ids);
    }
    static Map<String,Object> playability() throws Exception {
        EngineBridge.Session s=setup();
        try {
            Card land=TriggerFixture.card("Swamp"),land2=TriggerFixture.card("Swamp"),artist=TriggerFixture.card("Blood Artist"),stone=TriggerFixture.card("Mind Stone"),solemn=TriggerFixture.card("Solemn Simulacrum"),bolt=TriggerFixture.card("Lightning Bolt");
            s.game.cheat(s.human.getId(),TriggerFixture.NONE,Arrays.asList(land,land2,artist,stone,solemn,bolt),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            Set<String> initial=priority(s);
            require(initial.contains(land.getId().toString()) && initial.contains(land2.getId().toString()),"Both basic lands must be legal on an empty board");
            require(!initial.contains(artist.getId().toString())&&!initial.contains(stone.getId().toString())&&!initial.contains(solemn.getId().toString()),"Blood Artist, Mind Stone and Solemn must not be playable with no mana sources");
            require(s.human.playLand(land,s.game,false),"XMage must accept the first land");
            Set<String> afterLand=priority(s);
            require(!afterLand.contains(land2.getId().toString()),"XMage's land-per-turn limit must remove the second land");
            require(afterLand.contains(land.getId().toString()),"Untapped Swamp must remain actionable as a mana source");
            require(!afterLand.contains(artist.getId().toString())&&!afterLand.contains(stone.getId().toString()),"One Swamp cannot pay either two-mana spell");
            Card secondSwamp=TriggerFixture.card("Swamp");
            s.game.cheat(s.human.getId(),TriggerFixture.NONE,TriggerFixture.NONE,Collections.singletonList(new PutToBattlefieldInfo(secondSwamp,false)),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            Set<String> twoMana=priority(s);
            require(twoMana.contains(artist.getId().toString())&&twoMana.contains(stone.getId().toString()),"Two untapped Swamps must make Blood Artist and Mind Stone payable");
            require(!twoMana.contains(solemn.getId().toString()),"Four-mana Solemn must remain unavailable");
            for(Card card:Arrays.asList(land,secondSwamp)) {
                Permanent permanent=s.game.getPermanent(card.getId());
                ActivatedAbility mana=s.human.usableManaAbilities(permanent,s.game).values().iterator().next();
                require(s.human.activateAbility(mana,s.game),"Engine must tap Swamp for black mana");
            }
            require(s.human.getManaPool().getBlack()==2,"Tapping two Swamps must produce exactly two black mana");
            s.query(PlayerQueryEvent.playManaEvent(s.human.getId(),"Pay mana",new HashMap<>()));
            @SuppressWarnings("unchecked") List<String> payIds=(List<String>)s.prompt.get("actionable");
            require(!payIds.contains(land.getId().toString())&&!payIds.contains(secondSwamp.getId().toString()),"Tapped lands must not remain available for mana payment");
            require(s.human.cast(artist.getSpellAbility(),s.game,false,null),"Engine must cast Blood Artist and pay its cost from the pool");
            require(s.human.getManaPool().getBlack()==0,"XMage must spend both black mana");
            List<Card> extraMana=Arrays.asList(TriggerFixture.card("Mountain"),TriggerFixture.card("Swamp"),TriggerFixture.card("Swamp"),TriggerFixture.card("Swamp"));
            s.game.cheat(s.human.getId(),TriggerFixture.NONE,TriggerFixture.NONE,extraMana.stream().map(c->new PutToBattlefieldInfo(c,false)).collect(Collectors.toList()),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            for(Card card:extraMana) require(s.human.activateAbility(s.human.usableManaAbilities(s.game.getPermanent(card.getId()),s.game).values().iterator().next(),s.game),"Fixture mana sources must activate through the real engine");
            Set<String> stack=priority(s);
            require(!stack.contains(stone.getId().toString())&&!stack.contains(solemn.getId().toString()),"A nonempty stack must prevent artifact spells even with enough mana");
            require(stack.contains(bolt.getId().toString()),"Lightning Bolt must remain available as an instant with red mana");
            s.game.getStack().resolve(s.game); s.game.checkStateAndTriggered();
            require(priority(s).contains(stone.getId().toString()),"Artifact spell must become playable after the stack resolves");
            s.game.getState().setActivePlayerId(s.bot.getId());
            require(!priority(s).contains(stone.getId().toString())&&priority(s).contains(bolt.getId().toString()),"Opponent turn must allow the instant and prevent sorcery-speed artifacts");
            s.game.getState().setPriorityPlayerId(s.bot.getId());
            require(priority(s).isEmpty(),"No human card may glow when the bot has priority");
            s.game.getState().setActivePlayerId(s.human.getId());s.game.getState().setPriorityPlayerId(s.human.getId());s.human.resetLandsPlayed();
            Card nextLand=TriggerFixture.card("Swamp");
            s.game.cheat(s.human.getId(),TriggerFixture.NONE,Collections.singletonList(nextLand),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            require(priority(s).contains(nextLand.getId().toString()),"Next-turn land reset must restore legal land play");
            return EngineBridge.map("passed",true,"gates",Arrays.asList("empty-board costs","land limit","untapped/tapped mana sources","native cost payment","stack timing","opponent turn","priority owner","next-turn land reset"));
        } finally { s.stop(); }
    }
    static Map<String,Object> manaWheels() throws Exception {
        EngineBridge.Session s=setup();
        ExecutorService executor=Executors.newSingleThreadExecutor(r->new Thread(r,"GAME mana wheel fixture"));
        try {
            Card reef=TriggerFixture.card("Shivan Reef"),city=TriggerFixture.card("City of Brass");
            s.game.cheat(s.human.getId(),TriggerFixture.NONE,TriggerFixture.NONE,Arrays.asList(new PutToBattlefieldInfo(reef,false),new PutToBattlefieldInfo(city,false)),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            MageObject reefObject=s.game.getPermanent(reef.getId());
            List<ActivatedAbility> choices=new ArrayList<>(s.human.usableManaAbilities(reefObject,s.game).values());
            require(choices.size()>=3,"Shivan Reef must expose its native colorless/blue/red mana abilities");
            s.query(PlayerQueryEvent.chooseAbilityEvent(s.human.getId(),"Choose mana ability",reef.getName(),choices));
            @SuppressWarnings("unchecked") Map<String,Object> wheel=(Map<String,Object>)s.prompt.get("manaWheel");
            require(wheel!=null && "ability".equals(wheel.get("kind"))&&reef.getId().toString().equals(wheel.get("sourceId")),"Ability wheel must identify the actual source");
            @SuppressWarnings("unchecked") List<Map<String,Object>> exposed=(List<Map<String,Object>>)s.prompt.get("choices");
            Set<String> colors=new HashSet<>();for(Map<String,Object> option:exposed)for(Object color:(Collection<?>)option.get("manaColors"))colors.add(color.toString());
            require(colors.equals(new HashSet<>(Arrays.asList("C","U","R"))),"Wheel colors must come from exactly Shivan Reef's native mana options");
            ActivatedAbility cityMana=s.human.usableManaAbilities(s.game.getPermanent(city.getId()),s.game).values().iterator().next();
            long oldId=((Number)s.prompt.get("id")).longValue();
            Future<Boolean> activation=executor.submit(()->s.human.activateAbility(cityMana,s.game));
            Map<String,Object> prompt=waitPrompt(s,oldId);
            @SuppressWarnings("unchecked") Map<String,Object> colorWheel=(Map<String,Object>)prompt.get("manaWheel");
            require(colorWheel!=null&&"color".equals(colorWheel.get("kind"))&&city.getId().toString().equals(colorWheel.get("sourceId")),"Real choose-color prompt must keep City of Brass source metadata");
            JsonObject answer=new JsonObject();answer.addProperty("promptId",((Number)prompt.get("id")).longValue());answer.addProperty("type","string");answer.addProperty("value","Blue");s.action(answer);
            require(activation.get(10,TimeUnit.SECONDS),"Engine must accept the wheel's color answer");
            require(s.human.getManaPool().getBlue()==1&&s.game.getPermanent(city.getId()).isTapped(),"Choosing Blue must really tap City and add one blue mana");
            return EngineBridge.map("passed",true,"abilityColors",colors,"selectedColor","U","nativeManaAdded",1);
        } finally { executor.shutdownNow();s.stop(); }
    }
    static Map<String,Object> waitPrompt(EngineBridge.Session s,long previous) throws Exception {
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(15);
        while(System.nanoTime()<deadline) {
            if(s.error!=null)throw new AssertionError(s.error);
            Map<String,Object> prompt=s.prompt;
            if(prompt!=null&&((Number)prompt.get("id")).longValue()!=previous)return prompt;
            Thread.sleep(5);
        }
        throw new AssertionError("Timed out waiting for engine prompt");
    }
    static void answer(EngineBridge.Session s,Map<String,Object> prompt,Map<String,Object> choice) throws Exception {
        JsonObject a=new JsonObject();a.addProperty("promptId",((Number)prompt.get("id")).longValue());a.addProperty("type",choice.get("responseType").toString());a.add("value",EngineBridge.JSON.toJsonTree(choice.containsKey("value")?choice.get("value"):choice.get("id")));s.action(a);
    }
    static Map<String,Object> mulligans(Path root,boolean commander) throws Exception {
        EngineBridge.Session s;
        if(commander) {
            JsonObject deck=JsonParser.parseString(Files.readString(root.resolve("decks/commander-krenko-goblins.json"))).getAsJsonObject();
            JsonObject body=new JsonObject();body.addProperty("format","Commander");body.addProperty("recordingPort",0);body.add("deck",deck);body.add("botDeck",deck);s=new EngineBridge.Session(body);
        } else s=TriggerFixture.session();
        try {
            // TriggerFixture preselects its starter; reset so the ordinary pregame path runs.
            s.game.setStartingPlayerId(null); s.start();
            Map<String,Object> p=waitPrompt(s,-1);
            if(!p.containsKey("mulligan")) {
                @SuppressWarnings("unchecked") List<Map<String,Object>> choices=(List<Map<String,Object>>)p.get("choices");
                Map<String,Object> starter=choices.stream().filter(c->s.human.getId().toString().equals(c.get("id"))).findFirst().orElseThrow();
                answer(s,p,starter);p=waitPrompt(s,((Number)p.get("id")).longValue());
            }
            @SuppressWarnings("unchecked") Map<String,Object> first=(Map<String,Object>)p.get("mulligan");
            require(first!=null,"Opening hand must have explicit engine mulligan metadata");
            require(((Number)first.get("downTo")).intValue()==(commander?7:6),"First mulligan size must match Commander/free or ordinary London rules");
            require(Boolean.valueOf(commander).equals(first.get("free")),"Free-mulligan flag must match actual engine policy");
            @SuppressWarnings("unchecked") Map<String,Object> doMulligan=(Map<String,Object>)first.get("mulliganChoice");
            long previous=((Number)p.get("id")).longValue();answer(s,p,doMulligan);p=waitPrompt(s,previous);
            // XMage asks which card to bottom immediately after a paid London
            // redraw, before offering the next keep/mulligan decision.
            for(int i=0;!p.containsKey("mulligan")&&i<7;i++) {
                require("pick_target".equals(p.get("type")),"Expected the engine's London bottom-card choice");
                @SuppressWarnings("unchecked") List<Map<String,Object>> bottomChoices=(List<Map<String,Object>>)p.get("choices");
                previous=((Number)p.get("id")).longValue();answer(s,p,bottomChoices.get(0));p=waitPrompt(s,previous);
            }
            @SuppressWarnings("unchecked") Map<String,Object> second=(Map<String,Object>)p.get("mulligan");
            require(second!=null&&((Number)second.get("downTo")).intValue()==(commander?6:5),"Next mulligan must reduce the kept-hand size through the real engine");
            return EngineBridge.map("passed",true,"format",commander?"Commander":"Modern","firstDownTo",first.get("downTo"),"firstFree",first.get("free"),"nextDownTo",second.get("downTo"));
        } finally { s.stop();if(s.gameThread!=null)s.gameThread.join(1000); }
    }
    public static void main(String[] args) throws Exception {
        org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        Path root=Paths.get(args[0]);EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(ActionabilityFixture.class.getClassLoader());
        Map<String,Object> report=EngineBridge.map("passed",true,"kind","Real XMage fixture states and genuine engine ability/mulligan prompts; no frontend interaction","playability",playability(),"manaWheels",manaWheels(),"mulligans",Arrays.asList(mulligans(root,false),mulligans(root,true)));
        String json=EngineBridge.JSON.toJson(report);Files.writeString(root.resolve("bridge/tests/actionability-report.json"),json+"\n");System.out.println(json);
    }
}
