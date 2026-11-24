package love2gathering;

import com.google.gson.*;
import mage.util.Copier;

import java.nio.file.*;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

/** Production practice sessions. Each legal deck draws only one kind of basic land. */
public final class BotCommanderFixture {
    private static JsonObject deck(String land, String... commanders) {
        JsonObject deck = new JsonObject();
        deck.addProperty("name", String.join(" + ", commanders));
        JsonArray command = new JsonArray();
        for (String name : commanders) command.add(name);
        deck.add("commander", command);
        JsonObject basic = new JsonObject();
        basic.addProperty("name", land);
        basic.addProperty("count", 100 - commanders.length);
        JsonArray main = new JsonArray();
        main.add(basic);
        deck.add("main", main);
        return deck;
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> rows(Map<String, Object> view, String key) {
        return (List<Map<String, Object>>) view.get(key);
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    @SuppressWarnings("unchecked")
    private static void run(JsonObject... decks) throws Exception {
        JsonObject request = new JsonObject();
        request.addProperty("format", "Commander");
        request.addProperty("recordingPort", 0);
        request.addProperty("startingSeatId", "bot-1");
        request.add("deck", deck("Mountain", "Krenko, Mob Boss"));
        Map<String, Set<String>> expected = new LinkedHashMap<>();
        JsonArray bots = new JsonArray();
        for (int index = 0; index < decks.length; index++) {
            JsonObject deck = decks[index];
            Set<String> names = new HashSet<>();
            for (JsonElement name : deck.getAsJsonArray("commander")) names.add(name.getAsString());
            expected.put("bot-" + (index + 1), names);
            JsonObject seat = new JsonObject();
            seat.addProperty("name", "Bot " + (index + 1));
            seat.add("deck", deck);
            bots.add(seat);
        }
        if (decks.length == 1) request.add("botDeck", decks[0]);
        else request.add("bots", bots);

        EngineBridge.Session session = new EngineBridge.Session(request);
        Set<String> startingCards = new HashSet<>(), onStack = new HashSet<>(), resolved = new HashSet<>();
        long lastPrompt = -1, deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45);
        try {
            session.start();
            while (System.nanoTime() < deadline && session.running && session.error == null) {
                Map<String, Object> frame = session.snapshot;
                Map<String, Object> prompt = frame == null ? null : (Map<String, Object>) frame.get("prompt");
                if (prompt == null || ((Number) prompt.get("id")).longValue() == lastPrompt) {
                    Thread.sleep(3);
                    continue;
                }
                lastPrompt = ((Number) prompt.get("id")).longValue();
                int turn = ((Number) frame.get("turn")).intValue();
                require(turn <= decks.length + 2, "Missed the expected first round of commander casts by turn " + turn);
                for (Map<String, Object> player : rows(frame, "players")) {
                    Set<String> names = expected.get(player.get("seatId"));
                    if (names == null) continue;
                    List<Map<String, Object>> commanders = rows(player, "commanders");
                    require(names.equals(commanders.stream().map(c -> c.get("name")).collect(Collectors.toSet())),
                            "Pregame must bind the selected commanders to their individual bot seats");
                    for (Map<String, Object> commander : commanders) {
                        String id = (String) commander.get("id");
                        String zone = (String) commander.get("zone");
                        if ("COMMAND".equals(zone)) startingCards.add(id);
                        if ("STACK".equals(zone) && rows(frame, "stack").stream().anyMatch(spell ->
                                "spell".equals(spell.get("kind")) && player.get("id").equals(spell.get("controllerId"))
                                && commander.get("name").equals(spell.get("sourceName")))) onStack.add(id);
                        if ("BATTLEFIELD".equals(zone)) {
                            require(((Number) commander.get("commandZonePlays")).intValue() == 1,
                                    "Native watcher must see exactly one cast from command for " + commander.get("name"));
                            require(rows(player, "battlefield").stream().anyMatch(card -> id.equals(card.get("id"))
                                            && player.get("id").equals(card.get("controllerId"))),
                                    "The resolved permanent must belong to the casting bot");
                            resolved.add(id);
                        }
                    }
                }
                int count = expected.values().stream().mapToInt(Set::size).sum();
                if (resolved.size() == count) {
                    require(startingCards.equals(resolved) && onStack.equals(resolved),
                            "Each resolved commander must have been seen in its own command zone and on the native stack");
                    System.out.println("Passed: " + decks.length + " practice bot(s), turn " + turn + ", " + expected.values());
                    return;
                }
                // The human only keeps, passes and discards excess Mountains.
                // Every land play, payment and cast comes from the native bots.
                Map<String, Object> answer = rows(prompt, "choices").stream()
                        .filter(c -> "done".equals(c.get("id")) || "no".equals(c.get("id"))
                                || ("Select a card to discard".equals(prompt.get("message")) && "uuid".equals(c.get("responseType"))))
                        .findFirst().orElseThrow(() -> new AssertionError("Unexpected human prompt " + prompt.get("message")));
                ActionabilityFixture.answer(session, prompt, answer);
            }
            throw new AssertionError("Native bots did not finish casting: " + resolved + ", game error: " + session.error);
        } finally {
            session.stop();
        }
    }

    public static void main(String[] args) throws Exception {
        org.apache.log4j.BasicConfigurator.configure();
        org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        EngineBridge.cardMap = JsonParser.parseString(Files.readString(Paths.get(args[0], "bridge/card-map.json"))).getAsJsonObject();
        Copier.setLoader(BotCommanderFixture.class.getClassLoader());
        run(deck("Plains", "Yoshimaru, Ever Faithful", "Rograkh, Son of Rohgahh"));
        run(deck("Mountain", "Zurgo Bellstriker"), deck("Forest", "Oviya Pashiri, Sage Lifecrafter"),
                deck("Plains", "Isamaru, Hound of Konda"));
    }
}
