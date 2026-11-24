package love2gathering;

import mage.MageObject;
import mage.abilities.*;
import mage.cards.Card;
import mage.game.Game;
import mage.game.events.*;
import mage.game.stack.StackObject;
import java.util.*;
import static love2gathering.EngineBridge.map;

/** Viewer-entitled native identities; never parses English rules for legality or causes. */
final class NativeMechanics {
    private static final java.lang.reflect.Field ABILITY_WORD=abilityWordField();
    private static final java.lang.reflect.Field INTERVENING_IF=interveningField();
    private static java.lang.reflect.Field interveningField(){
        try{java.lang.reflect.Field field=TriggeredAbilityImpl.class.getDeclaredField("interveningIfCondition");field.setAccessible(true);return field;}
        catch(ReflectiveOperationException|RuntimeException unavailable){return null;}
    }
    private static java.lang.reflect.Field abilityWordField(){
        try{java.lang.reflect.Field field=AbilityImpl.class.getDeclaredField("abilityWord");field.setAccessible(true);return field;}
        catch(ReflectiveOperationException|RuntimeException unavailable){return null;}
    }
    static mage.constants.AbilityWord abilityWord(Ability ability){
        try{return ABILITY_WORD!=null&&ability instanceof AbilityImpl?(mage.constants.AbilityWord)ABILITY_WORD.get(ability):null;}
        catch(IllegalAccessException|RuntimeException unavailable){return null;}
    }
    static final Map<String,String> ALIASES=new LinkedHashMap<>();
    static {
        for(String name:Arrays.asList("Flying","Vigilance","FirstStrike","DoubleStrike","Deathtouch","Lifelink","Menace","Defender","Hexproof","Ward","Indestructible","Protection","Infect","Toxic","Wither","Prowess","Exalted","Regeneration","Persist","Undying","Flash","Haste","Trample","Reach","Shroud","Flashback","JumpStart","Evoke","Convoke","Mutate","Morph","Megamorph","Disguise","Manifest","Cloak","Extort","Kicker","Multikicker","Buyback","Bargain","Casualty","Improvise","Delve","Escape","Overload","Dash","Blitz","Emerge","Spectacle","Surge","Prototype","Bestow","Cycling","Channel","Unearth","Ninjutsu","Equip","Reconfigure","Crew","Saddle","Foretell","Plot","Suspend","Rebound","Adventure","Cascade","Discover","Storm","Replicate","Transform","Meld","Phasing","Scry","Surveil","Landfall","Exhaust"))
            ALIASES.put(name+"Ability",snake(name));
        ALIASES.put("ExhaustManaAbility","exhaust");ALIASES.put("MultikickerAbility","multikicker");
        ALIASES.put("CastFromGraveyardAbility","graveyard_return");
        ALIASES.put("ForetellCostAbility","foretell");
        ALIASES.put("ConvokeSpecialAction","convoke");ALIASES.put("EvokeTriggeredAbility","evoke");
    }
    static String snake(String name){return name.replaceAll("([a-z0-9])([A-Z])","$1_$2").toLowerCase(Locale.ROOT);}
    static String identity(Ability ability){
        try{if(INTERVENING_IF!=null&&ability instanceof TriggeredAbilityImpl&&INTERVENING_IF.get(ability)==mage.abilities.condition.common.EvokedCondition.instance)return "evoke";}
        catch(IllegalAccessException|RuntimeException unavailable){/* Unknown is a generic interaction. */}
        for(Class<?> type=ability.getClass();type!=null;type=type.getSuperclass()){
            String mapped=ALIASES.get(type.getSimpleName());if(mapped!=null)return mapped;
        }
        Package pkg=ability.getClass().getPackage();
        if(pkg!=null&&pkg.getName().startsWith("mage.abilities.keyword"))return snake(ability.getClass().getSimpleName().replaceFirst("Ability$",""));
        return null;
    }
    static List<Ability> abilities(MageObject object,Game game){
        return new ArrayList<>(object instanceof Card?((Card)object).getAbilities(game):object.getAbilities());
    }
    static String category(String id){
        if(Arrays.asList("flashback","evoke","mutate","overload","dash","blitz","emerge","prototype","bestow").contains(id))return "alternative_cost";
        if(Arrays.asList("kicker","multikicker","buyback","bargain","casualty","jump_start").contains(id))return "additional_cost";
        if(Arrays.asList("convoke","improvise","delve").contains(id))return "payment_method";
        if(Arrays.asList("cycling","channel","unearth","equip","reconfigure","crew","saddle","exhaust").contains(id))return "activated_ability";
        if(Arrays.asList("morph","megamorph","disguise","foretell","plot").contains(id))return "special_action";
        if(Arrays.asList("extort","ward","prowess","exalted","persist","undying","cascade","storm","rebound").contains(id))return "triggered_interaction";
        return "keyword";
    }
    static Map<String,Object> mechanic(Ability ability){
        String id=identity(ability);if(id==null)return null;
        String nativeName=ability.getClass().getSimpleName();
        List<String> categories=new ArrayList<>();categories.add(category(id));
        if(Arrays.asList("flashback","jump_start","escape","unearth","rebound","adventure").contains(id))categories.add("zone_permission");
        if("jump_start".equals(id))categories.add("alternative_cost");
        return map("id",id,"name",id.replace('_',' '),"kind",Arrays.asList("landfall","heroic").contains(id)?"ability_word":"keyword","category",category(id),"categories",categories,
            "nativeClass",ability.getClass().getName(),"source","native","rule",EngineBridge.clean(ability.getRule()),
            "parameter",EngineBridge.clean(ability.getRule()),"coverage",ALIASES.containsKey(nativeName)?"explicit":"native_generic");
    }
    static List<Map<String,Object>> current(MageObject object,Game game){
        Map<String,Map<String,Object>> rows=new LinkedHashMap<>();
        for(Ability ability:abilities(object,game)){
            Map<String,Object> entry=mechanic(ability);if(entry!=null)rows.putIfAbsent(entry.get("id")+":"+entry.get("rule"),entry);
            mage.constants.AbilityWord word=abilityWord(ability);
            if(word!=null){String id=word.name().toLowerCase(Locale.ROOT);rows.putIfAbsent("word:"+id,map("id",id,"name",word.toString(),"kind","ability_word","category","ability_word","nativeClass",ability.getClass().getName(),"source","native","coverage","native_identity","rule",EngineBridge.clean(ability.getRule())));}
            for(Mode mode:ability.getModes().values())for(mage.abilities.effects.Effect effect:mode.getEffects()){
                if(!effect.getClass().getPackageName().startsWith("mage.abilities.effects.keyword"))continue;
                String id=snake(effect.getClass().getSimpleName().replaceFirst("(?:Target|Source)?Effect$",""));
                rows.putIfAbsent("action:"+id,map("id",id,"name",id.replace('_',' '),"kind","keyword_action","category","keyword_action","nativeClass",effect.getClass().getName(),"source","native","coverage","native_identity","rule",EngineBridge.clean(effect.getText(mode))));
            }
        }
        return new ArrayList<>(rows.values());
    }
    static List<Map<String,Object>> interactions(MageObject object,Game game){
        List<Map<String,Object>> rows=new ArrayList<>();for(Ability ability:abilities(object,game))if(identity(ability)==null&&ability.getRuleVisible()){
            String rule=EngineBridge.clean(ability.getRule());if(rule.isBlank())continue;
            rows.add(map("id",EngineBridge.Session.str(ability.getOriginalId()),"kind",ability instanceof SpellAbility?"spell":ability instanceof ActivatedAbility?"activated":ability instanceof TriggeredAbility?"triggered":"static",
                "nativeClass",ability.getClass().getName(),"rule",rule,"source","native","keyword",false));
        }return rows;
    }
    static Ability eventAbility(EngineBridge.Session session,GameEvent event,MageObject source){
        if(event instanceof ZoneChangeEvent)return ((ZoneChangeEvent)event).getSource();
        MageObject target=session.game.getObject(event.getTargetId());
        if(target instanceof StackObject)return ((StackObject)target).getStackAbility();
        // GameEvent keeps only sourceId, so only use an actual active/resolving
        // native ability when its source exactly matches that event's source.
        if(event.getSourceId()!=null){
            for(EngineBridge.Session perspective:session.owner.perspectives){Ability active=perspective.human.activeNativeAbility;
                if(active!=null&&Objects.equals(active.getSourceId(),event.getSourceId()))return active;
            }
            StackObject resolving=PresentationGames.resolvingObject();
            if(resolving!=null&&Objects.equals(resolving.getStackAbility().getSourceId(),event.getSourceId()))return resolving.getStackAbility();
        }
        if(source!=null)for(Ability ability:abilities(source,session.game))if(Objects.equals(ability.getId(),event.getTargetId())||Objects.equals(ability.getOriginalId(),event.getTargetId()))return ability;
        return null;
    }
    static List<Map<String,Object>> paidMechanics(EngineBridge.Session session,Ability casting){
        List<Map<String,Object>> paid=new ArrayList<>();mage.cards.Card card=session.game.getCard(casting.getSourceId());if(card==null)return paid;
        for(Ability ability:card.getAbilities(session.game))if(ability instanceof mage.abilities.costs.AlternativeSourceCosts){
            boolean activated;try{activated=((mage.abilities.costs.AlternativeSourceCosts)ability).isActivated(casting,session.game);}catch(RuntimeException unavailable){continue;}
            if(activated){
                Map<String,Object> descriptor=mechanic(ability);if(descriptor!=null){descriptor.put("costPaid",true);paid.add(descriptor);}
            }
        }
        return paid;
    }
    static List<String> convokers(EngineBridge.Session session,Ability casting){
        Set<mage.MageObjectReference> references;try{references=mage.util.CardUtil.getSourceCostsTag(session.game,casting,mage.abilities.keyword.ConvokeAbility.convokingCreaturesKey,new HashSet<>());}catch(RuntimeException unavailable){return Collections.emptyList();}
        List<String> ids=new ArrayList<>();for(mage.MageObjectReference reference:references){
            mage.game.permanent.Permanent permanent=reference.getPermanent(session.game);
            if(permanent!=null&&session.knownObject(permanent.getId())!=null)ids.add(permanent.getId().toString());
        }return ids;
    }
    static void event(EngineBridge.Session session,GameEvent event,MageObject source,Map<String,Object> view){
        view.put("nativeEventId",event.getId().toString());
        if(event.getType()==GameEvent.EventType.COUNTERED&&session.game.getLastKnownInformation(event.getTargetId(),mage.constants.Zone.STACK)instanceof StackObject)
            view.put("targetId",EngineBridge.Session.str(event.getTargetId()));
        if(source!=null)view.put("controllerId",EngineBridge.Session.str(session.controller(source,event.getPlayerId())));
        StackObject resolving=PresentationGames.resolvingObject();
        if(resolving!=null){view.put("resolutionId",resolving.getId().toString());view.put("batchId",session.game.getId()+"-resolution-"+resolving.getId());}
        String operation;
        switch(event.getType()){
            case DESTROYED_PERMANENT:operation="destroy";break;
            case SACRIFICED_PERMANENT:operation="sacrifice";break;
            case TAPPED:operation="tap";break;case UNTAPPED:operation="untap";break;
            case TURNED_FACE_UP:operation="face_up";break;case TURNED_FACE_DOWN:operation="face_down";break;
            case CREATURE_MUTATED:operation="merge";break;
            case TRANSFORMED:operation="transform";break;
            case PHASED_OUT:operation="phase_out";break;case PHASED_IN:operation="phase_in";break;
            case DREW_CARD:operation="draw";break;case DISCARDED_CARD:operation="discard";break;
            case MILLED_CARD:operation="mill";break;case COUNTERED:operation="counter";break;
            case COUNTER_ADDED:case COUNTER_REMOVED:operation="counter_change";break;
            case MANA_ADDED:operation="mana_generated";break;case MANA_PAID:operation="mana_spent";break;
            case SCRIED:operation="scry";view.put("mechanic","scry");break;
            case SURVEILED:operation="surveil";view.put("mechanic","surveil");break;
            case CYCLED_CARD:operation="cycling";view.put("mechanic","cycling");break;
            case EXPLORED:operation="explore";view.put("mechanic","explore");break;
            case DISCOVERED:operation="discover";view.put("mechanic","discover");break;
            case ACTIVATED_ABILITY:operation="activation";break;case TRIGGERED_ABILITY:operation="trigger";break;
            default:operation=String.valueOf(view.get("type"));
        }
        view.put("operation",operation);
        if(event instanceof ZoneChangeEvent){
            ZoneChangeEvent z=(ZoneChangeEvent)event;
            view.put("operation",z.getToZone()==mage.constants.Zone.EXILED?"exile":z.getToZone()==mage.constants.Zone.HAND?"return_to_hand":z.getToZone()==mage.constants.Zone.BATTLEFIELD?"enter_battlefield":"zone");
        }
        if(source!=null){
            Map<String,Object> visible=session.card(source);
            if(!Boolean.TRUE.equals(visible.get("hidden"))&&!Boolean.TRUE.equals(visible.get("faceDown"))){
                Ability ability=eventAbility(session,event,source);
                if(ability!=null){
                    view.put("abilityId",EngineBridge.Session.str(ability.getId()));
                    view.put("abilityNativeClass",ability.getClass().getName());view.put("causeSourceId",EngineBridge.Session.str(ability.getSourceId()));
                    Map<String,Object> identity=mechanic(ability);
                    if(identity!=null){view.put("mechanic",identity.get("id"));view.put("mechanics",Collections.singletonList(identity));}
                    if("convoke".equals(view.get("mechanic"))&&event.getType()==GameEvent.EventType.TAPPED){view.put("contributorId",EngineBridge.Session.str(event.getTargetId()));view.put("paymentForId",EngineBridge.Session.str(ability.getSourceId()));}
                    if(ability instanceof SpellAbility){
                        view.put("castMode",((SpellAbility)ability).getSpellAbilityCastMode().name().toLowerCase(Locale.ROOT));
                        List<Map<String,Object>> paid=paidMechanics(session,ability);if(!paid.isEmpty()){
                            view.put("paidMechanics",paid);if(identity==null){view.put("mechanic",paid.get(0).get("id"));view.put("mechanics",paid);}
                        }
                        if(event.getType()==GameEvent.EventType.SPELL_CAST){List<String> contributors=convokers(session,ability);if(!contributors.isEmpty()){view.put("contributors",contributors);view.put("paymentMechanic","convoke");}}
                    }
                }
            }
        }
    }
}
