package love2gathering;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import mage.Mana;
import mage.abilities.ActivatedAbility;
import mage.cards.Card;
import mage.game.PutToBattlefieldInfo;
import mage.game.events.PlayerQueryEvent;
import mage.util.Copier;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/** Tests real source/color activation and native mana-pool payment on a GAME thread. */
public final class ManualManaFixture {
    private static void check(boolean result, String message) {
        if (!result) throw new AssertionError(message);
        System.out.println("PASS " + message);
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> choices(Map<String, Object> prompt) {
        return (List<Map<String, Object>>) prompt.get("choices");
    }

    private static Map<String, Object> choice(Map<String, Object> prompt, String id) {
        return choices(prompt).stream().filter(option -> id.equals(option.get("id"))).findFirst().orElseThrow();
    }

    private static Map<String, Object> sourceChoice(Map<String, Object> prompt, Card source, String color) {
        return choices(prompt).stream().filter(option -> source.getId().toString().equals(option.get("sourceId"))
                && List.of(color).equals(option.get("manaColors"))).findFirst().orElseThrow();
    }

    private static Map<String, Object> next(EngineBridge.Session session, Map<String, Object> previous) throws Exception {
        Map<String, Object> prompt = ActionabilityFixture.waitPrompt(session, previous == null ? -1 : ((Number) previous.get("id")).longValue());
        check("play_mana".equals(prompt.get("type")), "XMage requests manual mana payment");
        return prompt;
    }

    private static void payment(Path output) throws Exception {
        EngineBridge.Session session = ActionabilityFixture.setup();
        var worker = Executors.newSingleThreadExecutor(r -> new Thread(r, "GAME manual mana fixture"));
        try {
            session.human.getUserData().setManaPoolAutomatic(false);
            session.human.getManaPool().setAutoPayment(false);
            Card talisman = TriggerFixture.card("Talisman of Creativity"), reef = TriggerFixture.card("Shivan Reef");
            Card keep = TriggerFixture.card("Kher Keep"), city = TriggerFixture.card("City of Brass");
            Card omnath = TriggerFixture.card("Omnath, Locus of All");
            session.game.cheat(session.human.getId(), TriggerFixture.NONE, List.of(talisman),
                    List.of(reef, keep, city, omnath).stream().map(card -> new PutToBattlefieldInfo(card, false)).toList(),
                    TriggerFixture.NONE, TriggerFixture.NONE, TriggerFixture.NONE);
            session.game.applyEffects();
            var pool = session.human.getManaPool();
            pool.addMana(Mana.GreenMana(3), session.game, omnath.getSpellAbility());
            pool.emptyPool(session.game);
            check(pool.getBlack() == 3 && pool.getGreen() == 0, "Omnath's native retention converts the three floating mana to black");

            var cast = worker.submit(() -> session.human.cast(talisman.getSpellAbility(), session.game, false, null));
            var prompt = next(session, null);
            check(choice(prompt, "mana-B").get("manaCount").equals(3), "The payment window receives all three floating black mana");
            check(sourceChoice(prompt, keep, "C").get("manaColor") == null, "Kher Keep advertises colorless from its native mana ability");
            check(sourceChoice(prompt, reef, "C") != null && sourceChoice(prompt, reef, "U") != null
                    && sourceChoice(prompt, reef, "R") != null, "Shivan Reef advertises its three distinct native mana abilities");
            if (output != null) Files.writeString(output.resolve("manual-mana-prompt.json"), EngineBridge.JSON.toJson(prompt));

            var cityGreen = sourceChoice(prompt, city, "G");
            check("Green".equals(cityGreen.get("manaColor")), "City of Brass offers its native green choice inline");
            JsonObject invalid = new JsonObject();
            invalid.addProperty("promptId", ((Number) prompt.get("id")).longValue());
            invalid.addProperty("type", "mana_source");
            invalid.addProperty("value", cityGreen.get("id").toString().replace(":Green", ":Colorless"));
            boolean rejected = false;
            try { session.action(invalid); }
            catch (IllegalArgumentException expected) { rejected = true; }
            check(rejected && session.prompt == prompt, "An unoffered color cannot consume the native mana prompt");

            ActionabilityFixture.answer(session, prompt, cityGreen);
            prompt = next(session, prompt);
            check(session.game.getPermanent(city.getId()).isTapped() && pool.getGreen() == 1,
                    "One inline action really taps City for green with no second choice");

            int before = session.human.getLife();
            ActionabilityFixture.answer(session, prompt, sourceChoice(prompt, reef, "U"));
            prompt = next(session, prompt);
            check(session.game.getPermanent(reef.getId()).isTapped() && pool.getBlue() == 1 && session.human.getLife() == before - 1,
                    "Choosing Shivan Reef's blue mode applies its actual damage and adds blue");

            ActionabilityFixture.answer(session, prompt, choice(prompt, "mana-B"));
            prompt = next(session, prompt);
            check(choice(prompt, "mana-B").get("manaCount").equals(2), "Paying from Omnath's retained pool spends one selected mana");
            ActionabilityFixture.answer(session, prompt, choice(prompt, "mana-G"));
            check(cast.get(10, TimeUnit.SECONDS) && session.game.getStack().peek().getSourceId().equals(talisman.getId()),
                    "The real spell is cast after the two explicit pool payments");
            check(pool.getBlue() == 1 && pool.getBlack() == 2 && pool.getGreen() == 0,
                    "Unselected native pool mana remains floating");
        } finally {
            worker.shutdownNow();
            session.stop();
        }
    }

    private static void dynamicSourceColors() throws Exception {
        EngineBridge.Session session = ActionabilityFixture.setup();
        try {
            Card land = TriggerFixture.card("Cabal Stronghold"), swamp = TriggerFixture.card("Swamp");
            session.game.cheat(session.human.getId(), TriggerFixture.NONE, TriggerFixture.NONE,
                    List.of(new PutToBattlefieldInfo(land, false)), TriggerFixture.NONE, TriggerFixture.NONE, TriggerFixture.NONE);
            var source = session.game.getPermanent(land.getId());
            var manaAbility = session.human.usableManaAbilities(source, session.game).values().iterator().next();
            session.human.getManaPool().addMana(Mana.ColorlessMana(3), session.game, manaAbility);
            for (int swampCount = 0; swampCount <= 1; swampCount++) {
                if (swampCount == 1) {
                    session.game.cheat(session.human.getId(), TriggerFixture.NONE, TriggerFixture.NONE,
                            List.of(new PutToBattlefieldInfo(swamp, false)), TriggerFixture.NONE, TriggerFixture.NONE, TriggerFixture.NONE);
                }
                var permanent = session.game.getPermanent(land.getId());
                List<ActivatedAbility> abilities = new ArrayList<>(session.human.usableManaAbilities(permanent, session.game).values());
                var dynamic = abilities.stream().filter(ability -> !ability.getManaCosts().isEmpty()).findFirst().orElseThrow();
                String abilityId = dynamic.getId().toString();
                var expected = swampCount == 0 ? List.of() : List.of("B");
                session.query(PlayerQueryEvent.chooseAbilityEvent(session.human.getId(), "Choose mana ability", land.getName(), abilities));
                check(expected.equals(choice(session.prompt, abilityId).get("manaColors")),
                        "Ability picker shows Stronghold's actual output with " + swampCount + " basic Swamps");
                session.query(PlayerQueryEvent.playManaEvent(session.human.getId(), "Pay mana", new HashMap<>()));
                var option = choices(session.prompt).stream().filter(row -> abilityId.equals(row.get("abilityId"))).findFirst().orElseThrow();
                check(expected.equals(option.get("manaColors")), "Payment window matches the Stronghold ability picker");
                check(!permanent.isTapped() && session.human.getManaPool().getColorless() == 3,
                        "Previewing Stronghold leaves its source and activation cost available");
            }
        } finally {
            session.stop();
        }
    }

    private static void conditionalPool() throws Exception {
        EngineBridge.Session session = ActionabilityFixture.setup();
        var worker = Executors.newSingleThreadExecutor(r -> new Thread(r, "GAME conditional mana fixture"));
        try {
            session.human.getUserData().setManaPoolAutomatic(false);
            var pool = session.human.getManaPool();
            pool.setAutoPayment(false);
            Card ziggurat = TriggerFixture.card("Ancient Ziggurat"), bear = TriggerFixture.card("Grizzly Bears");
            session.game.cheat(session.human.getId(), TriggerFixture.NONE, List.of(bear),
                    List.of(new PutToBattlefieldInfo(ziggurat, false)), TriggerFixture.NONE, TriggerFixture.NONE, TriggerFixture.NONE);
            var permanent = session.game.getPermanent(ziggurat.getId());
            var ability = session.human.usableManaAbilities(permanent, session.game).values().iterator().next();
            var activation = worker.submit(() -> session.human.activateAbility(ability, session.game));
            var colorPrompt = ActionabilityFixture.waitPrompt(session, -1);
            ActionabilityFixture.answer(session, colorPrompt, choice(colorPrompt, "Green"));
            check(activation.get(10, TimeUnit.SECONDS) && pool.getGreen() == 0 && pool.getConditionalMana().size() == 1,
                    "Ancient Ziggurat produces real green mana that the ordinary pool getters exclude");
            pool.addMana(Mana.ColorlessMana(1), session.game, bear.getSpellAbility());
            var cast = worker.submit(() -> session.human.cast(bear.getSpellAbility(), session.game, false, null));
            var prompt = next(session, colorPrompt);
            check(choice(prompt, "mana-G").get("manaCount").equals(1), "The payment query exposes the native conditional pool choice");
            ActionabilityFixture.answer(session, prompt, choice(prompt, "mana-G"));
            prompt = next(session, prompt);
            check(!pool.conditionalManaHasManaType(mage.constants.ManaType.GREEN)
                            && choices(prompt).stream().noneMatch(option -> "mana-G".equals(option.get("id"))),
                    "XMage consumes the conditional green for its eligible creature spell");
            ActionabilityFixture.answer(session, prompt, choice(prompt, "mana-C"));
            check(cast.get(10, TimeUnit.SECONDS), "Conditional and ordinary pool choices complete a real creature cast");
        } finally {
            worker.shutdownNow();
            session.stop();
        }
    }

    public static void main(String[] args) throws Exception {
        Path root = Path.of(args[0]);
        org.apache.log4j.BasicConfigurator.configure();
        org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        EngineBridge.cardMap = JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();
        Copier.setLoader(EngineBridge.class.getClassLoader());
        payment(args.length > 1 ? Path.of(args[1]) : null);
        conditionalPool();
        dynamicSourceColors();
    }
}
