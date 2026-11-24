package love2gathering;

import mage.MageObject;
import mage.abilities.Ability;
import mage.abilities.effects.mana.AddManaOfAnyColorEffect;
import mage.abilities.mana.ActivatedManaAbilityImpl;
import mage.abilities.mana.ManaAbility;
import mage.choices.ChoiceColor;
import mage.constants.ManaType;
import mage.game.Game;
import mage.players.ManaPool;
import mage.view.ManaPoolView;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static love2gathering.EngineBridge.map;

/** Presentation and input tokens for XMage's existing manual mana query. */
final class NativeManaPayment {
    static final String SOURCE_RESPONSE = "mana_source";
    private static final String[] SYMBOLS = {"W", "U", "B", "R", "G", "C"};
    private static final ManaType[] TYPES = {ManaType.WHITE, ManaType.BLUE, ManaType.BLACK, ManaType.RED, ManaType.GREEN, ManaType.COLORLESS};

    record SourceSelection(UUID sourceId, UUID abilityId, String color) {}

    static Map<String, Object> pool(ManaPool pool) {
        ManaPoolView view = new ManaPoolView(pool);
        return map("W", view.getWhite(), "U", view.getBlue(), "B", view.getBlack(),
                "R", view.getRed(), "G", view.getGreen(), "C", view.getColorless());
    }

    static void addPoolChoices(List<Map<String, Object>> choices, ManaPool pool) {
        Map<String, Object> balances = pool(pool);
        for (int index = 0; index < SYMBOLS.length; index++) {
            String symbol = SYMBOLS[index];
            int count = (int) balances.get(symbol);
            if (count > 0) {
                choices.add(map("id", "mana-" + symbol, "label", "Pay {" + symbol + "} from pool (" + count + ")",
                        "responseType", "mana", "value", TYPES[index].name(), "manaSymbol", symbol, "manaCount", count));
            }
        }
    }

    static final class Sources {
        private final EngineBridge.Session session;
        private final Map<UUID, Collection<ActivatedManaAbilityImpl>> available = new HashMap<>();
        private Game preview;

        Sources(EngineBridge.Session session) { this.session = session; }

        boolean collect(MageObject object) {
            Collection<ActivatedManaAbilityImpl> abilities = session.human.usableManaAbilities(object, session.game).values();
            if (abilities.isEmpty()) return false;
            available.put(object.getId(), abilities);
            return true;
        }

        Collection<ActivatedManaAbilityImpl> abilities(UUID id) {
            return available.getOrDefault(id, List.of());
        }

        List<String> colors(Ability ability) {
            // Native prediction may evaluate effects. Only run it on a detached playable-state
            // copy, shared by all options of this prompt and never reused by another prompt.
            try {
                if (preview == null) preview = session.game.createSimulationForPlayableCalc();
                ManaAbility copy = (ManaAbility) ability.copy();
                return session.manaColors(ManaType.getManaTypesFromManaList(copy.getNetMana(preview)));
            } catch (RuntimeException unavailable) {
                return List.of();
            }
        }

        List<Map<String, Object>> choices(UUID sourceId, String sourceName) {
            List<Map<String, Object>> options = new ArrayList<>();
            for (ActivatedManaAbilityImpl ability : abilities(sourceId)) {
                String label = EngineBridge.clean(ability.getRule(sourceName));
                if (ability.getEffects().size() == 1 && ability.getEffects().get(0).getClass() == AddManaOfAnyColorEffect.class) {
                    // This native effect always offers precisely ChoiceColor's five named colors.
                    for (String color : ChoiceColor.getBaseColors()) {
                        List<String> symbol = session.manaColors(Set.of(ManaType.findByName(color)));
                        options.add(option(sourceId, ability, label, symbol, color));
                    }
                } else {
                    options.add(option(sourceId, ability, label, colors(ability), null));
                }
            }
            return options;
        }
    }

    private static Map<String, Object> option(UUID source, ActivatedManaAbilityImpl ability, String label, List<String> colors, String color) {
        String id = source + ":" + ability.getId() + (color == null ? "" : ":" + color);
        return map("id", id, "responseType", SOURCE_RESPONSE, "label", label, "manaColors", colors,
                "sourceId", source.toString(), "abilityId", ability.getId().toString(), "manaColor", color);
    }

    static SourceSelection selection(String answer) {
        // Transport validation already matched this exact token to the active prompt.
        String[] parts = answer.split(":", 3);
        return new SourceSelection(UUID.fromString(parts[0]), UUID.fromString(parts[1]), parts.length == 3 ? parts[2] : null);
    }
}
