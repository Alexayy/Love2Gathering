package love2gathering;

import mage.MageObject;
import mage.abilities.*;
import mage.cards.Card;
import mage.constants.Zone;
import mage.game.stack.StackObject;
import java.util.*;
import java.util.stream.Collectors;
import static love2gathering.EngineBridge.map;

/** Describes native offers for this viewer's current prompt, never executable shortcuts. */
final class NativeCardActions {
    static String costText(mage.abilities.costs.Cost cost){
        String text=EngineBridge.clean(cost.getText());if(!text.isBlank())return text;
        if(cost instanceof mage.abilities.costs.common.DiscardTargetCost){
            int amount=cost.getTargets().stream().mapToInt(t->t.getMinNumberOfTargets()).sum();return "Discard "+amount+(amount==1?" card":" cards");
        }
        return cost.getClass().getSimpleName().replaceAll("([a-z])([A-Z])","$1 $2");
    }
    static List<Map<String,Object>> offered(EngineBridge.Session session,List<Map<String,Object>> choices,NativeManaPayment.Sources payment){
        // getPlayableObjects already ran XMage's full native computation for
        // this exact query. BridgeHuman retains that detached result; do not
        // repeat the expensive simulation for presentation metadata.
        List<ActivatedAbility> abilities=payment!=null||session.human.nativeOfferedAbilities==null?Collections.emptyList():session.human.nativeOfferedAbilities;
        List<Map<String,Object>> result=new ArrayList<>();
        for(Map<String,Object> choice:choices){
            if(!"uuid".equals(choice.get("responseType")) || Boolean.FALSE.equals(choice.get("selectable"))
                    || !(choice.get("card") instanceof Map<?,?> card)
                    || Boolean.TRUE.equals(card.get("hidden")))continue;
            String key=choice.get("id").toString();
            UUID id=UUID.fromString(key);
            Zone zone=session.game.getState().getZone(id);
            Collection<? extends ActivatedAbility> nativeOptions=payment!=null?payment.abilities(id):abilities.stream().filter(a->belongs(session,a,id)).collect(Collectors.toList());
            List<Map<String,Object>> options=new ArrayList<>();
            for(ActivatedAbility ability:nativeOptions){
                String kind=ability.isManaAbility()?"mana":ability instanceof PlayLandAbility?"land":ability instanceof SpellAbility?"spell":ability instanceof SpecialAction?"special_action":"activated";
                List<Map<String,Object>> mechanics=new ArrayList<>();Map<String,Object> direct=NativeMechanics.mechanic(ability);if(direct!=null)mechanics.add(direct);
                options.add(map("id",ability.getId().toString(),"sourceId",EngineBridge.Session.str(ability.getSourceId()),"label",EngineBridge.clean(ability.toString()),
                    "kind",kind,"sourceZone",zone==null?null:zone.name(),"manaCost",ability.getManaCosts().getText(),
                    "otherCosts",ability.getCosts().stream().map(NativeCardActions::costText).collect(Collectors.toList()),
                    "costRequirements",ability.getCosts().stream().map(c->map("nativeClass",c.getClass().getName(),"label",costText(c),"targetMin",c.getTargets().stream().mapToInt(t->t.getMinNumberOfTargets()).sum())).collect(Collectors.toList()),
                    "requiresTargets",!ability.getTargets().isEmpty(),"usesStack",ability.isUsesStack(),"mechanics",mechanics,
                    "costFinal",false,"costNote","Native targets, optional costs and payment are chosen after selecting the object"));
            }
            result.add(map("objectId",key,"sourceZone",zone==null?null:zone.name(),"available",true,"actionCount",options.size(),"options",options));
        }
        return result;
    }
    static boolean belongs(EngineBridge.Session session,ActivatedAbility ability,UUID id){
        if(id.equals(ability.getSourceId()))return true;
        Card source=session.game.getCard(ability.getSourceId());
        if(source!=null&&source.getMainCard()!=null&&id.equals(source.getMainCard().getId()))return true;
        MageObject object=session.game.getObject(id);
        return object instanceof StackObject&&Objects.equals(((StackObject)object).getSourceId(),ability.getSourceId());
    }
}
