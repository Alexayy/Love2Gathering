package love2gathering;

import com.google.gson.*;
import mage.Mana;
import mage.cards.Card;
import mage.cards.CardsImpl;
import mage.constants.*;
import mage.game.PutToBattlefieldInfo;
import mage.game.turn.*;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

/** Real multi-HumanPlayer target/visibility/priority fixture; only initial resources are injected. */
public final class RoomMultiplayerFixture {
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static Map<String,Object> run(Path root) throws Exception {
        JsonObject body = new JsonObject(); body.addProperty("format", "Commander"); body.addProperty("recordingPort", 0);
        JsonObject deck = JsonParser.parseString(Files.readString(root.resolve("decks/commander-krenko-goblins.json"))).getAsJsonObject();
        JsonArray seats = new JsonArray();
        for (int i = 0; i < 4; i++) { JsonObject seat = new JsonObject(); seat.addProperty("seatId", "human-" + i); seat.addProperty("name", "Human " + i); seat.addProperty("type", "human"); seat.add("deck", deck); seats.add(seat); }
        body.add("seats", seats); EngineBridge.Session owner = new EngineBridge.Session(body, true);
        ExecutorService executor = Executors.newSingleThreadExecutor(r -> new Thread(r, "GAME room fixture"));
        try {
            require(owner.match.getPlayers().size() == 4 && owner.bots.isEmpty() && owner.humans.size() == 4, "Every human needs a real MatchPlayer and separate response context");
            EngineBridge.Session a = owner.perspectives.get(0), b = owner.perspectives.get(1), c = owner.perspectives.get(2);
            owner.game.setStartingPlayerId(a.human.getId()); owner.game.getState().setActivePlayerId(b.human.getId()); owner.game.getState().setPriorityPlayerId(b.human.getId());
            owner.game.getTurn().setPhase(new PreCombatMainPhase()); owner.game.getPhase().setStep(new PreCombatMainStep());
            for (EngineBridge.Session view : owner.perspectives) view.human.updateRange(owner.game);
            Card bolt = TriggerFixture.card("Lightning Bolt"), secret = TriggerFixture.card("Mountain");
            owner.game.cheat(b.human.getId(), TriggerFixture.NONE, Collections.singletonList(bolt), Collections.emptyList(), TriggerFixture.NONE, TriggerFixture.NONE, TriggerFixture.NONE);
            owner.game.cheat(c.human.getId(), TriggerFixture.NONE, Collections.singletonList(secret), Collections.emptyList(), TriggerFixture.NONE, TriggerFixture.NONE, TriggerFixture.NONE);
            require("Hidden card".equals(a.card(bolt).get("name")) && "Lightning Bolt".equals(b.card(bolt).get("name")), "Another real human's hand must stay private");
            owner.game.getState().getLookedAt(b.human.getId()).put("Private look", new CardsImpl(secret));
            require("Mountain".equals(b.card(secret).get("name")) && "Hidden card".equals(a.card(secret).get("name")), "Looked-at entitlement must belong only to the inspecting human");
            owner.game.getState().getRevealed().put("Public", new CardsImpl(secret));
            require("Mountain".equals(a.card(secret).get("name")), "Public reveals must remain visible to every human");
            owner.game.getState().getRevealed().remove("Public"); owner.game.getState().getLookedAt(b.human.getId()).clear();
            b.human.getManaPool().addMana(Mana.RedMana(1), owner.game, bolt.getSpellAbility());
            Future<Boolean> cast = executor.submit(() -> b.human.cast(bolt.getSpellAbility(), owner.game, false, null));
            Map<String,Object> prompt = ActionabilityFixture.waitPrompt(b, -1);
            require(a.prompt == null && c.prompt == null && "pick_target".equals(prompt.get("type")), "Native questions must route exclusively to the entitled human");
            long frameDeadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
            while(!b.human.getId().toString().equals(a.state().get("decisionPlayerId"))&&System.nanoTime()<frameDeadline)Thread.sleep(2);
            require(b.human.getId().toString().equals(a.state().get("decisionPlayerId"))&&a.state().get("decisionStartedAt") instanceof Number,"Another perspective can display the actual human decision owner and start time without receiving its prompt");
            JsonObject forged = new JsonObject(); forged.addProperty("promptId", ((Number)prompt.get("id")).longValue()); forged.addProperty("type", "uuid"); forged.addProperty("value", c.human.getId().toString());
            boolean rejected = false; try { a.action(forged); } catch (IllegalArgumentException ex) { rejected = true; }
            require(rejected && !cast.isDone(), "A different human must not answer the caster's question");
            @SuppressWarnings("unchecked") List<Map<String,Object>> choices = (List<Map<String,Object>>)prompt.get("choices");
            for (EngineBridge.Session view : owner.perspectives) require(choices.stream().anyMatch(value -> view.human.getId().toString().equals(value.get("id"))), "Every native player target must be offered");
            Map<String,Object> target = choices.stream().filter(value -> c.human.getId().toString().equals(value.get("id"))).findFirst().orElseThrow();
            ActionabilityFixture.answer(b, prompt, target); require(cast.get(10, TimeUnit.SECONDS), "The entitled human must really cast Lightning Bolt");
            int before = c.human.getLife(); owner.game.getStack().resolve(owner.game); owner.game.checkStateAndTriggered(); require(c.human.getLife() == before - 3, "Native damage must reach the selected real human");
            JsonObject settings = JsonParser.parseString("{\"autoPass\":true,\"stops\":{\"own\":[\"END_TURN\"],\"opponent\":[]}}").getAsJsonObject(); a.priority.configure(settings);
            require(b.priority.own.isEmpty() && !b.priority.yielding, "One human's stops must not change another human's controls");
            owner.game.getState().setActivePlayerId(a.human.getId()); owner.game.getState().setPriorityPlayerId(a.human.getId()); owner.game.getTurn().setPhase(new EndPhase()); owner.game.getPhase().setStep(new EndStep());
            Future<Boolean> waiting = executor.submit(() -> a.human.priority(owner.game)); prompt = ActionabilityFixture.waitPrompt(a, -1);
            require("stop".equals(prompt.get("priorityReason")) && b.prompt == null, "A selected stop must pause only its own human");
            frameDeadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);while(!(b.state().get("priorityStartedAt") instanceof Number)&&System.nanoTime()<frameDeadline)Thread.sleep(2);
            require(b.state().get("priorityStartedAt") instanceof Number&&((Number)b.state().get("priorityStartedAt")).longValue()>0,"Held priority start time is shared with other perspectives");
            JsonObject end = new JsonObject(); end.addProperty("command", "end_turn"); end.addProperty("promptId", ((Number)prompt.get("id")).longValue()); a.priorityCommand(end); require(waiting.get(10, TimeUnit.SECONDS), "End Turn must safely refresh that human's own native wait");
            require(a.priority.yielding && !b.priority.yielding, "End Turn must be isolated per human");
            owner.publishAll();
            for (EngineBridge.Session viewer : owner.perspectives) {
                @SuppressWarnings("unchecked") List<Map<String,Object>> players = (List<Map<String,Object>>)viewer.snapshot.get("players");
                require(players.stream().filter(player -> Boolean.TRUE.equals(player.get("human"))).count() == 1, "Exactly the local viewer gets the legacy human flag");
                require(players.stream().allMatch(player -> Boolean.TRUE.equals(player.get("isHuman"))), "Every actual HumanPlayer must retain its public kind");
                require(players.stream().filter(player -> !Boolean.TRUE.equals(player.get("human"))).allMatch(player -> ((List<?>)player.get("hand")).isEmpty()), "Every opponent hand must be redacted");
            }
            return EngineBridge.map("passed", true, "realHumanMatchPlayers", 4, "separateNativePrompts", true, "foreignAnswersRejected", true, "nativeTargetAndDamage", true, "privateHandsAndLooks", true, "publicReveals", true, "perHumanStopsAndYield", true);
        } finally { executor.shutdownNow(); owner.stop(); }
    }
    public static void main(String[] args) throws Exception {
        org.apache.log4j.BasicConfigurator.configure(); org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        Path root = Paths.get(args[0]); EngineBridge.cardMap = JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject(); Copier.setLoader(RoomMultiplayerFixture.class.getClassLoader());
        Map<String,Object> report = EngineBridge.map("passed", true, "kind", "Real native four-human XMage targets, damage, privacy and separate priority controls; only initial resources/turn position are fixtures", "checks", run(root));
        String json = EngineBridge.JSON.toJson(report); Files.writeString(root.resolve("bridge/tests/room-multiplayer-native-report.json"), json + "\n"); System.out.println(json);
    }
}
