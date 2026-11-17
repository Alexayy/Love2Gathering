package love2gathering;

import com.google.gson.*;
import mage.cards.Card;
import mage.constants.*;
import mage.game.PutToBattlefieldInfo;
import mage.game.turn.*;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

/** Native priority decisions and real dialogs. Only initial zones/resources/turn positions are fixtures. */
public final class PriorityFixture {
    static final ExecutorService GAME = Executors.newSingleThreadExecutor(r -> new Thread(r, "GAME priority fixture"));
    static void require(boolean value, String text) { if (!value) throw new AssertionError(text); }
    static EngineBridge.Session setup() {
        EngineBridge.Session s = TriggerFixture.session();
        s.game.getPhase().setStep(new PreCombatMainStep());
        s.priority.configure(JsonParser.parseString("{\"autoPass\":true,\"passWithOnlyMana\":true}").getAsJsonObject());
        return s;
    }
    static void add(EngineBridge.Session s, boolean human, String name, boolean hand) {
        Card card = TriggerFixture.card(name);
        s.game.cheat(human ? s.human.getId() : s.bot.getId(), TriggerFixture.NONE,
                hand ? Collections.singletonList(card) : TriggerFixture.NONE,
                hand ? Collections.emptyList() : Collections.singletonList(new PutToBattlefieldInfo(card, false)),
                TriggerFixture.NONE, TriggerFixture.NONE, TriggerFixture.NONE);
    }
    static Map<String,Object> waitPrompt(EngineBridge.Session s, long previous) throws Exception { return ActionabilityFixture.waitPrompt(s, previous); }
    static Map<String,Object> choose(Map<String,Object> prompt, String id) {
        @SuppressWarnings("unchecked") List<Map<String,Object>> choices = (List<Map<String,Object>>)prompt.get("choices");
        return choices.stream().filter(c -> id.equals(c.get("id"))).findFirst().orElseThrow(() -> new AssertionError("Missing choice " + id + ": " + prompt));
    }
    static void done(EngineBridge.Session s, Map<String,Object> prompt) throws Exception { ActionabilityFixture.answer(s, prompt, choose(prompt, "done")); }
    static long promptId(EngineBridge.Session s) { return s.prompt == null ? -1 : ((Number)s.prompt.get("id")).longValue(); }
    static Future<Boolean> nativePriority(EngineBridge.Session s) { return GAME.submit(() -> s.human.priority(s.game)); }
    static JsonObject command(String command) { JsonObject result = new JsonObject(); result.addProperty("command", command); return result; }
    static void endTurn(EngineBridge.Session s, Map<String,Object> p) { JsonObject c = command("end_turn"); c.addProperty("promptId", ((Number)p.get("id")).longValue()); s.priorityCommand(c); }
    static void configure(EngineBridge.Session s, String json) { s.priority.configure(JsonParser.parseString(json).getAsJsonObject()); }
    static void endStep(EngineBridge.Session s, boolean own) {
        s.game.getState().setActivePlayerId(own ? s.human.getId() : s.bot.getId());
        s.game.getTurn().setPhase(new EndPhase()); s.game.getPhase().setStep(new EndStep());
    }
    static Map<String,Object> emptyAndMana() throws Exception {
        EngineBridge.Session s = setup();
        try {
            require(!nativePriority(s).get(10, TimeUnit.SECONDS) && s.human.isPassed(), "Empty priority must really pass through XMage");
            add(s, true, "Mountain", false);
            require(!nativePriority(s).get(10, TimeUnit.SECONDS), "A lone mana ability must not keep empty priority open");
            require(s.human.getManaPool().count() == 0, "Auto priority must never activate mana itself");
            require(s.game.getBattlefield().getAllActivePermanents().stream().noneMatch(p -> p.isTapped()), "Mana source must remain untapped");
            require(s.prompt == null && s.priority.autoPassCount == 2, "Automatic pass must not expose a stale manual prompt");
            return EngineBridge.map("passed", true, "emptyNativePass", true, "manaOnlyNativePass", true, "manaSourceUntouched", true);
        } finally { s.stop(); }
    }
    static Map<String,Object> manualAndManaPreference() throws Exception {
        EngineBridge.Session s = setup();
        try {
            PriorityController fresh = new PriorityController();
            require(!fresh.autoPass && !fresh.passWithOnlyMana, "A new player must retain manual priority unless a preference was saved");
            configure(s, "{\"autoPass\":true,\"passWithOnlyMana\":false}");
            add(s, true, "Mountain", false);
            Future<Boolean> waiting = nativePriority(s); Map<String,Object> prompt = waitPrompt(s, -1);
            require("mana_available".equals(prompt.get("priorityReason")) && !waiting.isDone(), "Mana-only windows stay open when that preference is off");
            require(s.priority.legalityKnown && s.priority.meaningfulActionCount == 0 && s.priority.manaAbilityCount == 1, "Only native legal mana abilities qualify for the separate preference");
            JsonObject update = command("configure"); update.addProperty("passWithOnlyMana", true); s.priorityCommand(update);
            require(waiting.get(10, TimeUnit.SECONDS), "Changing mana-only preference refreshes the real priority question");
            require(!nativePriority(s).get(10, TimeUnit.SECONDS), "Explicit mana-only preference passes through XMage");
            require(s.human.getManaPool().count() == 0 && s.game.getBattlefield().getAllActivePermanents().stream().noneMatch(p -> p.isTapped()), "Passing mana-only priority never generates mana or taps a land");
            configure(s, "{\"stops\":{\"own\":[\"PRECOMBAT_MAIN\"],\"opponent\":[]}}");
            long old = promptId(s); waiting = nativePriority(s); prompt = waitPrompt(s, old);
            require("stop".equals(prompt.get("priorityReason")) && !waiting.isDone(), "Explicit phase stops win over mana-only automatic passing");
            done(s, prompt); waiting.get(10, TimeUnit.SECONDS);
            return EngineBridge.map("passed", true, "manualDefault", true, "manaOnlyOptIn", true, "nativeManaCount", 1, "stopPreserved", true, "manaNotActivated", true);
        } finally { s.stop(); }
    }
    static Map<String,Object> unknownLegality() {
        EngineBridge.Session s = setup();
        try {
            mage.game.Game failed = (mage.game.Game)java.lang.reflect.Proxy.newProxyInstance(mage.game.Game.class.getClassLoader(), new Class<?>[]{mage.game.Game.class}, (proxy, method, args) -> {
                if (method.getName().equals("createSimulationForPlayableCalc")) throw new IllegalStateException("Native legality unavailable fixture");
                return method.invoke(s.game, args);
            });
            s.priority.endTurn();
            require(!s.priority.decide(s, s.human, failed), "A failed native legality simulation cannot authorize automatic passing");
            require(!s.priority.legalityKnown && !s.priority.yielding && "legality_unknown".equals(s.priority.reason()), "Unknown native actions cancel yielding and retain manual control");
            return EngineBridge.map("passed", true, "unavailableNativeLegalityDoesNotPass", true, "yieldCancelled", true);
        } finally { s.stop(); }
    }
    static Map<String,Object> instantAndFlash() throws Exception {
        List<String> held = new ArrayList<>();
        for (String card : Arrays.asList("Lightning Bolt", "Ambush Viper")) {
            EngineBridge.Session s = setup();
            try {
                if (card.equals("Lightning Bolt")) add(s, true, "Mountain", false);
                else { add(s, true, "Forest", false); add(s, true, "Forest", false); }
                add(s, true, card, true);
                endStep(s, false);
                Future<Boolean> waiting = nativePriority(s);
                Map<String,Object> p = waitPrompt(s, -1);
                require(Boolean.TRUE.equals(p.get("priority")) && "action".equals(p.get("priorityReason")), "A legal instant/flash spell must hold priority on an opponent's end step");
                require(!waiting.isDone() && s.priority.meaningfulActionCount > 0, "Native player must really be waiting");
                done(s, p); require(!waiting.get(10, TimeUnit.SECONDS), "Pass must be explicitly accepted"); held.add(card);
            } finally { s.stop(); }
        }
        return EngineBridge.map("passed", true, "nativeSpellsHeld", held);
    }
    static Map<String,Object> selectedStop() throws Exception {
        EngineBridge.Session s = setup();
        try {
            configure(s, "{\"stops\":{\"own\":[],\"opponent\":[\"END_TURN\"]}}"); endStep(s, false);
            Future<Boolean> waiting = nativePriority(s);
            Map<String,Object> p = waitPrompt(s, -1);
            Map<String,Object> view = s.priority.view(p);
            require("stop".equals(p.get("priorityReason")) && Boolean.TRUE.equals(view.get("paused")), "Selected empty end-step stop must pause visibly");
            require("END_TURN".equals(view.get("stopStep")) && s.bot.getId().toString().equals(view.get("stopPlayerId")), "Stop acknowledgement must identify the native step and active player");
            require(s.priority.meaningfulActionCount == 0 && !waiting.isDone(), "Empty hand must still allow bluffing at the selected stop");
            done(s, p); waiting.get(10, TimeUnit.SECONDS);
            require(!nativePriority(s).get(10, TimeUnit.SECONDS), "Acknowledged stop must not stop repeatedly in the same step");
            endStep(s, false); // A distinct native extra-phase object in the same turn.
            long old = promptId(s); waiting = nativePriority(s); p = waitPrompt(s, old);
            require("stop".equals(p.get("priorityReason")), "A repeated native end phase must get its own stop");
            done(s, p); waiting.get(10, TimeUnit.SECONDS);
            return EngineBridge.map("passed", true, "emptyOpponentEndStepHeld", true, "visibleStop", view, "acknowledgedOnce", true, "repeatedPhaseStopsAgain", true);
        } finally { s.stop(); }
    }
    static Map<String,Object> yieldInterrupt(String kind, boolean reaction) throws Exception {
        EngineBridge.Session s = setup();
        try {
            add(s, true, "Mountain", true); // A real legal land action which End Turn must intentionally yield.
            if (reaction) {
                if (kind.equals("new_stack")) { add(s, true, "Mountain", false); add(s, true, "Lightning Bolt", true); }
                else { add(s, true, "Forest", false); add(s, true, "Forest", false); add(s, true, "Ambush Viper", true); }
            }
            Future<Boolean> waiting = nativePriority(s);
            Map<String,Object> p = waitPrompt(s, -1); endTurn(s, p);
            require(waiting.get(10, TimeUnit.SECONDS), "Priority refresh must re-query instead of silently pass");
            require(!nativePriority(s).get(10, TimeUnit.SECONDS) && s.priority.yielding, "End Turn must yield through a legal land action");
            if (kind.equals("new_stack")) {
                add(s, false, "Mountain", false); add(s, false, "Shock", true);
                Card shock = s.bot.getHand().getCards(s.game).stream().filter(c -> c.getName().equals("Shock")).findFirst().orElseThrow();
                s.game.getState().setPriorityPlayerId(s.bot.getId());
                require(GAME.submit(() -> s.bot.cast(shock.getSpellAbility(), s.game, false, null)).get(10, TimeUnit.SECONDS), "Bot must natively cast its instant");
                require(s.game.getStack().size() == 1, "A real opponent spell must enter the stack");
                s.game.getState().setPriorityPlayerId(s.human.getId());
            } else if (kind.equals("stop")) {
                configure(s, "{\"stops\":{\"own\":[\"END_TURN\"],\"opponent\":[]}}"); endStep(s, true);
            } else {
                s.game.getState().setTurnNum(s.game.getTurnNum() + 1); endStep(s, false);
            }
            long old = promptId(s); waiting = nativePriority(s);
            if (kind.equals("stop") || reaction) {
                p = waitPrompt(s, old);
                require(kind.equals(p.get("priorityReason")) && !s.priority.yielding && !waiting.isDone(), "End Turn must cancel and hold when a real response or stop exists: " + kind);
                done(s, p); waiting.get(10, TimeUnit.SECONDS);
            } else {
                require(!waiting.get(10, TimeUnit.SECONDS) && !s.priority.yielding && s.prompt == null, "End Turn must cancel but automatically pass an empty interrupted window: " + kind);
                require("auto_pass".equals(s.priority.reason()) && s.priority.meaningfulActionCount == 0, "No reaction must mean no extra priority question");
            }
            return EngineBridge.map("passed", true, "interruption", kind, "reactionAvailable", reaction, "emptyWindowAutoPassed", !reaction && !kind.equals("stop"), "nativeStackObjects", s.game.getStack().size());
        } finally { s.stop(); }
    }
    static Map<String,Object> cancelYield() throws Exception {
        EngineBridge.Session s = setup();
        try {
            add(s, true, "Mountain", true);
            Future<Boolean> waiting = nativePriority(s); Map<String,Object> p = waitPrompt(s, -1);
            endTurn(s, p); waiting.get(10, TimeUnit.SECONDS);
            require(!nativePriority(s).get(10, TimeUnit.SECONDS) && s.priority.yielding, "Fixture must really yield first");
            s.priorityCommand(command("cancel"));
            long old = promptId(s); waiting = nativePriority(s); p = waitPrompt(s, old);
            require(!s.priority.yielding && "action".equals(p.get("priorityReason")) && !waiting.isDone(), "Cancel must restore available native actions");
            done(s, p); waiting.get(10, TimeUnit.SECONDS);
            return EngineBridge.map("passed", true, "yieldCancelled", true, "nativeActionRestored", true);
        } finally { s.stop(); }
    }
    static Map<String,Object> coherentSnapshots() throws Exception {
        EngineBridge.Session s = setup();
        try {
            add(s, true, "Mountain", true); s.publish();
            Map<String,Object> oldFrame = s.snapshot;
            Future<Boolean> waiting; Map<String,Object> p;
            synchronized (s) {
                // Gate only publication, exactly as a slow recording write can.
                // The real GAME callback has built a new prompt while HTTP
                // readers still have the preceding complete board projection.
                waiting = nativePriority(s); p = waitPrompt(s, -1);
                Map<String,Object> between = s.state();
                require(between.get("prompt") == null, "A new prompt must wait for its full GAME projection");
                require(Objects.equals(between.get("revision"), oldFrame.get("revision")), "HTTP must retain the preceding complete board while publication is gated");
                @SuppressWarnings("unchecked") Map<String,Object> controls = (Map<String,Object>)between.get("priority");
                require(Boolean.FALSE.equals(controls.get("canEndTurn")), "Old board must not expose a new action ID");
            }
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
            while (s.state().get("prompt") == null && System.nanoTime() < deadline) Thread.sleep(1);
            require(s.state().get("prompt") != null, "Published GAME projection must expose its matching real prompt");
            endTurn(s, p); require(waiting.get(10, TimeUnit.SECONDS), "End Turn must refresh the native priority wait");
            Map<String,Object> consumed = s.state();
            require(consumed.get("prompt") == null, "Consumed priority cannot reappear from a cached projection");
            @SuppressWarnings("unchecked") Map<String,Object> controls = (Map<String,Object>)consumed.get("priority");
            require(Boolean.FALSE.equals(controls.get("canEndTurn")), "Consumed prompt must disable priority actions immediately");
            return EngineBridge.map("passed", true, "newPromptWaitsForCompleteFrame", true, "consumedPromptHiddenImmediately", true, "coherentControlAvailability", true);
        } finally { s.stop(); }
    }
    static Map<String,Object> fullControl() throws Exception {
        EngineBridge.Session s = setup();
        try {
            configure(s, "{\"autoPass\":false}"); Future<Boolean> waiting = nativePriority(s);
            Map<String,Object> p = waitPrompt(s, -1);
            require("manual".equals(p.get("priorityReason")) && !waiting.isDone(), "Full control must hold even empty priority");
            JsonObject c = command("configure"); c.addProperty("autoPass", true); s.priorityCommand(c);
            require(waiting.get(10, TimeUnit.SECONDS), "Changing priority configuration must safely refresh the native wait");
            require(!nativePriority(s).get(10, TimeUnit.SECONDS), "Enabling auto priority must then pass an empty native window");
            return EngineBridge.map("passed", true, "manualEmptyHold", true, "safeConfigurationWake", true);
        } finally { s.stop(); }
    }
    static Map<String,Object> combatChoice() throws Exception {
        EngineBridge.Session s = setup();
        try {
            add(s, true, "Mountain", true);
            Future<Boolean> priority = nativePriority(s); Map<String,Object> p = waitPrompt(s, -1);
            endTurn(s, p); priority.get(10, TimeUnit.SECONDS);
            require(!nativePriority(s).get(10, TimeUnit.SECONDS) && s.priority.yielding, "Yield must be armed before native combat selection");
            long old = promptId(s);
            Future<?> selection = GAME.submit(() -> s.human.selectAttackers(s.game, s.human.getId()));
            p = waitPrompt(s, old);
            require("select".equals(p.get("type")) && !Boolean.TRUE.equals(p.get("priority")) && !selection.isDone(), "Combat SELECT must remain a real choice rather than auto priority");
            require(!s.priority.yielding && "choice".equals(s.priority.reason()), "Combat choice must cancel End Turn");
            done(s, p); selection.get(10, TimeUnit.SECONDS);
            return EngineBridge.map("passed", true, "nativeAttackerChoiceHeld", true, "yieldCancelled", true);
        } finally { s.stop(); }
    }
    static Map<String,Object> targetsAndPayment() throws Exception {
        EngineBridge.Session s = setup();
        try {
            add(s, true, "Mountain", false); add(s, true, "Lightning Bolt", true);
            Card bolt = s.human.getHand().getCards(s.game).stream().filter(c -> c.getName().equals("Lightning Bolt")).findFirst().orElseThrow();
            Future<Boolean> waiting = nativePriority(s); Map<String,Object> p = waitPrompt(s, -1);
            long old = ((Number)p.get("id")).longValue(); ActionabilityFixture.answer(s, p, choose(p, bolt.getId().toString()));
            p = waitPrompt(s, old);
            require("pick_target".equals(p.get("type")) && !Boolean.TRUE.equals(p.get("priority")), "Native target prompt must remain interactive");
            boolean rejected = false;
            try { endTurn(s, p); } catch (IllegalArgumentException ex) { rejected = true; }
            require(rejected, "End Turn must never answer a target prompt");
            old = ((Number)p.get("id")).longValue(); ActionabilityFixture.answer(s, p, choose(p, s.bot.getId().toString())); p = waitPrompt(s, old);
            require("play_mana".equals(p.get("type")) && !Boolean.TRUE.equals(p.get("priority")), "Native mana payment must remain interactive");
            String land = s.game.getBattlefield().getAllActivePermanents().stream().filter(c -> c.getName().equals("Mountain")).findFirst().orElseThrow().getId().toString();
            ActionabilityFixture.answer(s, p, choose(p, land)); require(waiting.get(10, TimeUnit.SECONDS), "Choosing the real mana source must cast the spell");
            require(s.game.getStack().size() == 1 && s.priority.autoPassCount == 0, "The policy must not auto-answer any target/payment prompt");
            return EngineBridge.map("passed", true, "nativeTargetsHeld", true, "nativeManaPaymentHeld", true, "endTurnRejectedDuringTarget", true, "spellReallyCast", true);
        } finally { s.stop(); }
    }
    public static void main(String[] args) throws Exception {
        org.apache.log4j.BasicConfigurator.configure(); org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        Path root = Paths.get(args[0]); EngineBridge.cardMap = JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject(); Copier.setLoader(PriorityFixture.class.getClassLoader());
        try {
            Map<String,Object> report = EngineBridge.map("passed", true, "kind", "Real native XMage priority passes, legal instant/flash opportunities, bot casts, targets and payment; deterministic initial zones/turn positions; no frontend UI",
                    "emptyAndMana", emptyAndMana(), "manualAndManaPreference", manualAndManaPreference(), "unknownLegality", unknownLegality(), "instantAndFlash", instantAndFlash(), "stop", selectedStop(), "fullControl", fullControl(),
                    "cancelYield", cancelYield(), "coherentSnapshots", coherentSnapshots(), "endTurn", Arrays.asList(yieldInterrupt("new_stack", false), yieldInterrupt("new_stack", true), yieldInterrupt("stop", false), yieldInterrupt("new_turn", false), yieldInterrupt("new_turn", true)), "combatChoice", combatChoice(), "mandatoryPrompts", targetsAndPayment());
            String json = EngineBridge.JSON.toJson(report); Files.writeString(root.resolve("bridge/tests/priority-report.json"), json + "\n"); System.out.println(json);
        } finally { GAME.shutdownNow(); }
    }
}
