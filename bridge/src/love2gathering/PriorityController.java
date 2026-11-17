package love2gathering;

import com.google.gson.*;
import mage.abilities.ActivatedAbility;
import mage.abilities.SpecialAction;
import mage.constants.PhaseStep;
import mage.game.Game;
import mage.game.stack.StackObject;
import java.util.*;

/** Presentation-side priority policy. XMage supplies every legal ability and performs every pass.
 * This never answers a target, payment, combat, mulligan, or other non-priority choice.
 */
final class PriorityController {
    boolean autoPass, passWithOnlyMana, yielding, pending, paused, legalityKnown;
    final EnumSet<PhaseStep> own = EnumSet.noneOf(PhaseStep.class);
    final EnumSet<PhaseStep> opponent = EnumSet.noneOf(PhaseStep.class);
    String step, activePlayerId, key, acknowledgedKey, reason = "waiting", stopStep, stopPlayerId;
    int turn, yieldTurn, meaningfulActionCount, manaAbilityCount;
    String yieldActivePlayerId;
    Set<String> stackIds = Collections.emptySet(), yieldStackIds = Collections.emptySet();
    long autoPassCount;

    synchronized void configure(JsonObject value) {
        // Validate the complete update before changing the acknowledged configuration.
        boolean nextAuto = value.has("autoPass") ? value.get("autoPass").getAsBoolean() : autoPass;
        boolean nextMana = value.has("passWithOnlyMana") ? value.get("passWithOnlyMana").getAsBoolean() : passWithOnlyMana;
        EnumSet<PhaseStep> nextOwn = own.clone(), nextOpponent = opponent.clone();
        if (value.has("stops")) {
            if (!value.get("stops").isJsonObject()) throw new IllegalArgumentException("stops must contain own/opponent arrays");
            JsonObject stops = value.getAsJsonObject("stops");
            if (stops.has("own")) nextOwn = steps(stops.get("own"));
            if (stops.has("opponent")) nextOpponent = steps(stops.get("opponent"));
        }
        if (!own.equals(nextOwn) || !opponent.equals(nextOpponent)) acknowledgedKey = null;
        autoPass = nextAuto; passWithOnlyMana = nextMana; own.clear(); own.addAll(nextOwn); opponent.clear(); opponent.addAll(nextOpponent);
        if (!autoPass) yielding = false;
        pending = true; legalityKnown = false;
    }
    static EnumSet<PhaseStep> steps(JsonElement value) {
        if (!value.isJsonArray() || value.getAsJsonArray().size() > PhaseStep.values().length) throw new IllegalArgumentException("Each stop list must contain native step names");
        EnumSet<PhaseStep> result = EnumSet.noneOf(PhaseStep.class);
        for (JsonElement entry : value.getAsJsonArray()) {
            PhaseStep step;
            try { step = PhaseStep.valueOf(entry.getAsString()); }
            catch (RuntimeException ex) { throw new IllegalArgumentException("Unknown priority stop: " + entry); }
            if (step == PhaseStep.UNTAP) throw new IllegalArgumentException("Untap has no priority window; choose Upkeep");
            result.add(step);
        }
        return result;
    }
    synchronized void endTurn() {
        yielding = true; pending = true; paused = false; reason = "yield";
        yieldTurn = turn; yieldActivePlayerId = activePlayerId;
        yieldStackIds = new LinkedHashSet<>(stackIds);
        // Pressing End Turn explicitly acknowledges the current priority/stop.
        acknowledgedKey = key; stopStep = null; stopPlayerId = null;
    }
    synchronized void cancel() {
        yielding = false; pending = true; paused = false; legalityKnown = false; reason = "waiting";
    }
    synchronized void acknowledge(Map<String,Object> prompt) {
        if (prompt != null && Boolean.TRUE.equals(prompt.get("priority"))) {
            if ("stop".equals(prompt.get("priorityReason"))) acknowledgedKey = key;
            paused = false; legalityKnown = false; stopStep = null; stopPlayerId = null; reason = "waiting";
        }
    }
    synchronized void choice() {
        // End Turn never remains armed across a decision which needs a real answer.
        yielding = false; paused = true; legalityKnown = false; reason = "choice"; stopStep = null; stopPlayerId = null;
    }
    boolean decide(EngineBridge.Session session, EngineBridge.BridgeHuman player, Game game) {
        // getPlayable is XMage's native simulation of timing/costs/resources. A
        // false-positive (e.g. no legal target) conservatively leaves a prompt.
        int meaningful = 0, mana = 0;
        boolean known = false;
        try {
            if (game.getStep() == null || !Objects.equals(game.getState().getPriorityPlayerId(), player.getId()))
                throw new IllegalStateException("No current native priority window");
            List<ActivatedAbility> abilities = player.getPlayable(game, true);
            if (abilities != null) {
                for (ActivatedAbility ability : abilities) {
                    if (ability == null) throw new IllegalStateException("Incomplete native legality inventory");
                    if (ability.isManaAbility()) mana++; else meaningful++;
                }
                for (SpecialAction action : game.getState().getSpecialActions().getControlledBy(player.getId(), false).values())
                    if (action.canActivate(player.getId(), game).canActivate()) meaningful++;
                known = true;
            }
        } catch (RuntimeException unavailable) {
            // A failed native simulation is not proof of an empty window.
            // Preserve manual priority rather than silently losing a response.
        }
        Set<String> currentStack = new LinkedHashSet<>();
        for (StackObject object : game.getStack()) currentStack.add(object.getId().toString());
        PhaseStep currentStep = game.getTurnStepType();
        String currentActive = EngineBridge.Session.str(game.getActivePlayerId());
        int currentTurn = game.getTurnNum();
        synchronized (this) {
            turn = currentTurn; activePlayerId = currentActive;
            step = currentStep == null ? null : currentStep.name();
            // Extra combat/main/end phases have distinct native phase objects,
            // even when their enum and turn number match an earlier phase.
            key = currentTurn + ":" + currentActive + ":" + step + ":" + System.identityHashCode(game.getPhase());
            stackIds = currentStack; meaningfulActionCount = meaningful; manaAbilityCount = mana; legalityKnown = known; pending = false;
            stopStep = null; stopPlayerId = null;
            String interrupted = null;
            if (yielding && (yieldTurn != currentTurn || !Objects.equals(yieldActivePlayerId, currentActive))) {
                yielding = false; interrupted = "new_turn";
            }
            if (currentStep != null && (player.getId().equals(game.getActivePlayerId()) ? own : opponent).contains(currentStep) && !Objects.equals(acknowledgedKey, key)) {
                yielding = false; paused = true; reason = "stop"; stopStep = step; stopPlayerId = activePlayerId;
                return false;
            }
            if (!known) { yielding = false; paused = true; reason = "legality_unknown"; return false; }
            if (yielding && !yieldStackIds.containsAll(currentStack)) {
                yielding = false; interrupted = "new_stack";
            }
            if (interrupted != null && (!autoPass || meaningful > 0)) { paused = true; reason = interrupted; return false; }
            if (yielding) { paused = false; reason = "yield"; return true; }
            if (!autoPass) { paused = true; reason = "manual"; return false; }
            if (meaningful > 0) { paused = true; reason = "action"; return false; }
            if (mana > 0 && !passWithOnlyMana) { paused = true; reason = "mana_available"; return false; }
            paused = false; reason = "auto_pass"; return true;
        }
    }
    synchronized void passed() { autoPassCount++; }
    synchronized String reason() { return reason; }
    synchronized Map<String,Object> view(Map<String,Object> prompt) {
        boolean canEnd = prompt != null && Boolean.TRUE.equals(prompt.get("priority")) && paused && !pending;
        List<String> yourStops = new ArrayList<>(), theirStops = new ArrayList<>();
        for (PhaseStep value : own) yourStops.add(value.name());
        for (PhaseStep value : opponent) theirStops.add(value.name());
        String status;
        switch (reason) {
            case "stop": status = "Stopped at " + (stopStep == null ? "selected step" : PhaseStep.valueOf(stopStep).toString()); break;
            case "yield": status = "Ending turn"; break;
            case "new_stack": status = "New spell or ability — respond or pass"; break;
            case "new_turn": status = "New turn — respond or pass"; break;
            case "action": status = "Your action"; break;
            case "manual": status = "Full control"; break;
            case "mana_available": status = "Mana abilities available — respond or pass"; break;
            case "legality_unknown": status = "Native actions are not confirmed — respond or pass"; break;
            case "choice": status = "Choose an answer"; break;
            case "auto_pass": status = "Passing empty priority"; break;
            default: status = "Waiting for XMage";
        }
        return EngineBridge.map("autoPass", autoPass, "passWithOnlyMana", passWithOnlyMana, "manaOnlyPolicySupported", true,
                "stops", EngineBridge.map("own", yourStops, "opponent", theirStops),
                "yielding", yielding, "pending", pending, "paused", paused, "reason", reason, "status", status,
                "step", step, "turn", turn, "activePlayerId", activePlayerId, "stopStep", stopStep, "stopPlayerId", stopPlayerId,
                "meaningfulActionCount", meaningfulActionCount, "manaAbilityCount", manaAbilityCount,
                "legalityKnown", legalityKnown, "autoPassCount", autoPassCount, "canEndTurn", canEnd);
    }
}
