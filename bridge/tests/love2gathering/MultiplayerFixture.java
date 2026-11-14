package love2gathering;

import com.google.gson.*;
import mage.Mana;
import mage.cards.Card;
import mage.cards.CardsImpl;
import mage.game.events.PlayerQueryEvent;
import mage.constants.*;
import mage.game.CommanderFreeForAll;
import mage.game.turn.PreCombatMainPhase;
import mage.game.turn.PreCombatMainStep;
import mage.players.Player;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

/** Native multiplayer targeting fixture; only initial resources/zones are injected. */
public final class MultiplayerFixture {
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }

    static Map<String,Object> targeting(Path root) throws Exception {
        JsonObject deck = JsonParser.parseString(Files.readString(root.resolve("decks/commander-krenko-goblins.json"))).getAsJsonObject();
        JsonObject body = new JsonObject();
        body.addProperty("format", "Commander"); body.addProperty("recordingPort", 0); body.add("deck", deck);
        JsonArray bots = new JsonArray();
        for (int i = 1; i <= 3; i++) { JsonObject bot = new JsonObject(); bot.addProperty("name", "Target Bot " + i); bot.add("deck", deck); bots.add(bot); }
        body.add("bots", bots);
        EngineBridge.Session session = new EngineBridge.Session(body);
        ExecutorService executor = Executors.newSingleThreadExecutor(r -> new Thread(r, "GAME multiplayer targeting fixture"));
        try {
            require(session.game instanceof CommanderFreeForAll, "Must use XMage's multiplayer Commander game");
            require(session.game.getNumPlayers() == 4 && session.match.getPlayers().size() == 4, "All seats need real game and match records");
            session.game.setStartingPlayerId(session.human.getId());
            session.game.getState().setActivePlayerId(session.human.getId());
            session.game.getState().setPriorityPlayerId(session.human.getId());
            session.game.getTurn().setPhase(new PreCombatMainPhase());
            session.game.getPhase().setStep(new PreCombatMainStep());
            for (Player player : session.game.getPlayers().values()) player.updateRange(session.game);
            List<Map<String,Object>> damage = new ArrayList<>();
            for (Player bot : session.bots) {
                Card bolt = TriggerFixture.card("Lightning Bolt");
                session.game.cheat(session.human.getId(), TriggerFixture.NONE, Collections.singletonList(bolt), Collections.emptyList(), TriggerFixture.NONE, TriggerFixture.NONE, TriggerFixture.NONE);
                session.human.getManaPool().addMana(Mana.RedMana(1), session.game, bolt.getSpellAbility());
                long previous = session.prompt == null ? -1 : ((Number) session.prompt.get("id")).longValue();
                Future<Boolean> cast = executor.submit(() -> session.human.cast(bolt.getSpellAbility(), session.game, false, null));
                Map<String,Object> prompt = ActionabilityFixture.waitPrompt(session, previous);
                require("pick_target".equals(prompt.get("type")), "Casting must produce native target selection");
                @SuppressWarnings("unchecked") List<Map<String,Object>> choices = (List<Map<String,Object>>) prompt.get("choices");
                for (Player opponent : session.bots) require(choices.stream().anyMatch(c -> opponent.getId().toString().equals(c.get("id"))), "Every opponent must be a valid engine target");
                Map<String,Object> choice = choices.stream().filter(c -> bot.getId().toString().equals(c.get("id"))).findFirst().orElseThrow();
                ActionabilityFixture.answer(session, prompt, choice);
                require(cast.get(10, TimeUnit.SECONDS), "Native engine must accept the selected opponent and pay for Lightning Bolt");
                int before = bot.getLife();
                session.game.getStack().resolve(session.game);
                session.game.checkStateAndTriggered();
                require(bot.getLife() == before - 3, "Lightning Bolt must resolve against the selected opponent");
                damage.add(EngineBridge.map("opponent", bot.getName(), "before", before, "after", bot.getLife(), "targetChoices", choices.size()));
            }
            for (Player bot : session.bots) {
                Card secret = TriggerFixture.card("Mountain");
                session.game.cheat(bot.getId(), TriggerFixture.NONE, Collections.singletonList(secret), Collections.emptyList(), TriggerFixture.NONE, TriggerFixture.NONE, TriggerFixture.NONE);
                session.query(PlayerQueryEvent.targetEvent(session.human.getId(), "Choose a hidden card", Collections.singleton(secret.getId()), true));
                @SuppressWarnings("unchecked") List<Map<String,Object>> choices = (List<Map<String,Object>>) session.prompt.get("choices");
                require("Hidden card".equals(choices.get(0).get("label")), "Hidden cards must stay hidden in every opponent's choice label");
                require("Hidden card".equals(session.card(secret).get("name")), "Hidden cards must stay hidden in card projections");
                session.game.getState().getRevealed().put("Public fixture", new CardsImpl(secret));
                require("Mountain".equals(session.card(secret).get("name")), "Publicly revealed opponent cards must remain inspectable");
                session.game.getState().getRevealed().remove("Public fixture");
                session.game.getState().getLookedAt(session.human.getId()).put("Looked-at fixture", new CardsImpl(secret));
                require("Mountain".equals(session.card(secret).get("name")), "The human's looked-at opponent cards must remain inspectable");
                session.game.getState().getLookedAt(session.human.getId()).remove("Looked-at fixture");
            }
            return EngineBridge.map("passed", true, "playerCount", 4, "nativeTargets", damage, "hiddenChoiceLabels", true, "publicRevealsVisible", true, "lookedAtVisible", true);
        } finally { executor.shutdownNow(); session.stop(); }
    }

    public static void main(String[] args) throws Exception {
        org.apache.log4j.BasicConfigurator.configure(); org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        Path root = Paths.get(args[0]);
        EngineBridge.cardMap = JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();
        Copier.setLoader(MultiplayerFixture.class.getClassLoader());
        Map<String,Object> report = EngineBridge.map("passed", true, "kind", "Real XMage deterministic fixture; initial zones and mana injected, genuine native spells/targets/payment/resolution; no frontend UI", "targeting", targeting(root));
        String json = EngineBridge.JSON.toJson(report);
        Files.writeString(root.resolve("bridge/tests/multiplayer-targeting-report.json"), json + "\n");
        System.out.println(json);
    }
}
