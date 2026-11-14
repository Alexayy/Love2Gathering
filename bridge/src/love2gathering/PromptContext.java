package love2gathering;

import mage.abilities.Ability;
import mage.game.events.PlayerQueryEvent;
import java.util.*;
import java.util.function.Supplier;
import static love2gathering.EngineBridge.map;

/** Labels native operations; responses and ordering remain HumanPlayer's own. */
final class PromptContext {
    final EngineBridge.Session session;
    final Deque<Context> contexts = new ArrayDeque<>();
    static final class Context {
        final long id; final String kind, stage, destination, remaining; final UUID sourceId;
        Context(long id,String kind,String stage,String destination,String remaining,UUID sourceId) {
            this.id=id;this.kind=kind;this.stage=stage;this.destination=destination;this.remaining=remaining;this.sourceId=sourceId;
        }
    }
    PromptContext(EngineBridge.Session session){this.session=session;}
    <T> T run(String kind,String stage,String destination,String remaining,Ability source,Supplier<T> operation) {
        Context parent=contexts.peek();
        Context next=new Context(parent==null?session.ids.incrementAndGet():parent.id,
            kind==null?(parent==null?"select":parent.kind):kind,stage,destination,remaining,
            source==null?(parent==null?null:parent.sourceId):source.getSourceId());
        contexts.push(next);try{return operation.get();}finally{contexts.pop();}
    }
    void enrich(Map<String,Object> prompt,PlayerQueryEvent event,List<Map<String,Object>> choices) {
        Context context=contexts.peek();
        if(context==null&&event.getCards()==null&&event.getPile1()==null)return;
        List<Map<String,Object>> cards=new ArrayList<>();
        for(Map<String,Object> choice:choices)if(choice.get("card") instanceof Map<?,?>) {
            @SuppressWarnings("unchecked") Map<String,Object> card=new LinkedHashMap<>((Map<String,Object>)choice.get("card"));
            card.put("choiceId",choice.get("id"));card.put("responseType",choice.get("responseType"));
            card.put("value",choice.getOrDefault("value",choice.get("id")));card.put("selected",choice.getOrDefault("selected",false));
            card.put("selectable",choice.getOrDefault("selectable",true));cards.add(card);
        }
        Map<String,Object> done=choices.stream().filter(c->"done".equals(c.get("id"))).findFirst().orElse(null);
        Object zone=event.getOptions()==null?null:event.getOptions().get("targetZone");
        String destination=context==null?null:context.destination;
        prompt.put("cardPanel",map("interactionId",context==null?prompt.get("id"):context.id,
            "kind",context==null?(event.getPile1()!=null?"piles":"select"):context.kind,
            "stage",context==null?"select":context.stage,"cards",cards,"sourceId",context==null?null:EngineBridge.Session.str(context.sourceId),
            "zone",zone instanceof Enum<?>?((Enum<?>)zone).name():zone==null?null:zone.toString(),"selectionDestination",destination,
            "remainingDestination",context==null?null:context.remaining,"orderDestination",context!=null&&"order".equals(context.stage)?destination:null,
            "orderDirection",context!=null&&"order".equals(context.stage)?("top".equals(destination)?"last_chosen_topmost":"last_chosen_bottommost"):null,
            "doneChoice",done));
    }
}
