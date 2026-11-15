package love2gathering;

import mage.MageObject;
import mage.abilities.Ability;
import mage.abilities.effects.RestrictionEffect;
import mage.abilities.keyword.*;
import mage.abilities.effects.common.continuous.LookAtTopCardOfLibraryAnyTimeEffect;
import mage.cards.Card;
import mage.constants.*;
import mage.game.*;
import mage.game.combat.CombatGroup;
import mage.game.permanent.Permanent;
import mage.util.CardUtil;
import java.util.*;
import java.util.stream.Collectors;
import static love2gathering.EngineBridge.map;

/** Read-only native relationships and isolated native legality previews. */
final class NativeProjection {
    private static final LookAtTopCardOfLibraryAnyTimeEffect TOP_LOOK=new LookAtTopCardOfLibraryAnyTimeEffect();
    static boolean canLookAtLibraryTop(Game game){return TOP_LOOK.canLookAtNextTopLibraryCard(game);}
    static boolean currentlySeen(EngineBridge.Session session,UUID id){
        return session.game.getState().getRevealed().values().stream().anyMatch(cards->cards.contains(id))
            ||session.game.getState().getLookedAt(session.human.getId()).values().stream().anyMatch(cards->cards.contains(id));
    }
    static String libraryTopVisibility(EngineBridge.Session session,mage.players.Player owner){
        Card top=owner.getLibrary().getFromTop(session.game);
        if(top==null||!canLookAtLibraryTop(session.game))return null;
        if(owner.isTopCardRevealed()||session.game.getState().getRevealed().values().stream().anyMatch(cards->cards.contains(top.getId())))return "public";
        return top.getId().equals(session.libraryTopLooks.get(owner.getId()))?"private":null;
    }
    static Map<String,Object> libraryTop(EngineBridge.Session session,mage.players.Player owner){
        if(libraryTopVisibility(session,owner)==null)return null;
        Map<String,Object> card=session.card(owner.getLibrary().getFromTop(session.game),true);card.put("zone","LIBRARY");return card;
    }
    static boolean knownLibraryCard(EngineBridge.Session session,Card card){
        if(!canLookAtLibraryTop(session.game))return false;
        mage.players.Player owner=session.game.getPlayer(card.getOwnerId());
        Card top=owner==null?null:owner.getLibrary().getFromTop(session.game);
        return top!=null&&top.getId().equals(card.getId())&&libraryTopVisibility(session,owner)!=null||currentlySeen(session,card.getId());
    }
    // Display metadata from actual native ability identities, never an oracle
    // text parser or a substitute for native legality.
    private static final Map<Class<?>,String> KEYWORDS=new LinkedHashMap<>();
    static{
        KEYWORDS.put(TrampleAbility.class,"trample");KEYWORDS.put(FlyingAbility.class,"flying");
        KEYWORDS.put(FirstStrikeAbility.class,"first_strike");KEYWORDS.put(DoubleStrikeAbility.class,"double_strike");
        KEYWORDS.put(DeathtouchAbility.class,"deathtouch");KEYWORDS.put(LifelinkAbility.class,"lifelink");
        KEYWORDS.put(ReachAbility.class,"reach");KEYWORDS.put(MenaceAbility.class,"menace");
        KEYWORDS.put(VigilanceAbility.class,"vigilance");KEYWORDS.put(HasteAbility.class,"haste");
        KEYWORDS.put(HexproofAbility.class,"hexproof");KEYWORDS.put(IndestructibleAbility.class,"indestructible");
        KEYWORDS.put(ShroudAbility.class,"shroud");KEYWORDS.put(DefenderAbility.class,"defender");
    }
    static List<String> keywords(MageObject object){
        Set<String> result=new LinkedHashSet<>();
        for(Ability ability:object.getAbilities()){
            String key=KEYWORDS.get(ability.getClass());if(key!=null)result.add(key);
        }
        return new ArrayList<>(result);
    }
    static List<Map<String,Object>> abilityIcons(MageObject object,Game game){
        Map<String,Map<String,Object>> result=new LinkedHashMap<>();
        for(Ability ability:object.getAbilities())for(mage.abilities.icon.CardIcon icon:ability.getIcons(game)){
            String key=icon.getIconType().name()+":"+icon.getText()+":"+icon.getHint();
            result.putIfAbsent(key,map("type",icon.getIconType().name(),"text",EngineBridge.clean(icon.getText()),"hint",EngineBridge.clean(icon.getHint())));
        }
        return new ArrayList<>(result.values());
    }
    static String id(UUID value){return EngineBridge.Session.str(value);}
    static List<String> ids(Collection<UUID> values){return values.stream().map(NativeProjection::id).collect(Collectors.toList());}
    static Map<String,Object> combat(EngineBridge.Session session) {
        Game game=session.game;List<Map<String,Object>> groups=new ArrayList<>();
        for(CombatGroup group:game.getCombat().getGroups())for(UUID attackerId:group.getAttackers()) {
            Permanent attacker=game.getPermanent(attackerId);
            groups.add(map("attackerId",id(attackerId),"attackerIds",ids(group.getAttackers()),"defenderId",id(group.getDefenderId()),
                "attackingPlayerId",attacker==null?null:id(attacker.getControllerId()),"defendingPlayerId",id(group.getDefendingPlayerId()),"blockerIds",ids(group.getBlockers()),"blocked",group.getBlocked(),
                "declarationConfirmed",session.owner.confirmedBlockersPhase==game.getPhase()&&session.owner.confirmedBlockerDefenders.contains(group.getDefendingPlayerId()),
                "minBlockers",attacker==null?0:attacker.getMinBlockedBy(),"maxBlockers",attacker==null?0:attacker.getMaxBlockedBy()));
        }
        return map("step",game.getTurnStepType()==null?null:game.getTurnStepType().name(),"groups",groups,
            "attackerIds",ids(game.getCombat().getAttackers()),"blockerIds",ids(game.getCombat().getBlockers()));
    }
    static List<Map<String,Object>> linkedExile(EngineBridge.Session session,Permanent permanent) {
        Game game=session.game;Set<UUID> linked=new LinkedHashSet<>(permanent.getImprinted());
        // getExileZoneId creates a zone key: projection must only read one that
        // the rules engine has already created for this exact incarnation.
        String key=CardUtil.getObjectZoneString(CardUtil.SOURCE_EXILE_ZONE_TEXT,permanent,game);
        Object zoneId=game.getState().getValue(key);
        if(zoneId instanceof UUID){ExileZone zone=game.getExile().getExileZone((UUID)zoneId);if(zone!=null)linked.addAll(zone);}
        List<Map<String,Object>> cards=new ArrayList<>();
        for(UUID cardId:linked)if(game.getState().getZone(cardId)==Zone.EXILED){MageObject card=game.getCard(cardId);if(card!=null)cards.add(session.card(card));}
        return cards;
    }
    static List<Map<String,Object>> blockerOptions(EngineBridge.Session session,Collection<UUID> offered) {
        // Some native restrictions can ask a question. Run their real canBlock
        // implementation on a simulation copy, where HumanPlayer cannot emit
        // feedback, never on the live game while projecting a frame.
        Game copy=session.game.createSimulationForPlayableCalc();
        List<Map<String,Object>> result=new ArrayList<>();
        for(UUID blockerId:offered){Permanent blocker=copy.getPermanent(blockerId);if(blocker==null)continue;
            List<String> allowed=new ArrayList<>();List<Map<String,Object>> denied=new ArrayList<>();
            for(CombatGroup group:copy.getCombat().getGroups())for(UUID attackerId:group.getAttackers()){
                Permanent attacker=copy.getPermanent(attackerId);if(attacker==null)continue;
                if(group.canBlock(blocker,copy))allowed.add(id(attackerId));
                else denied.add(map("attackerId",id(attackerId),"reason","XMage does not offer this block","rules",restrictionRules(copy,attacker,blocker)));
            }
            result.add(map("blockerId",id(blockerId),"legalAttackerIds",allowed,"unavailable",denied,"preview",true));
        }
        return result;
    }
    static List<String> restrictionRules(Game game,Permanent attacker,Permanent blocker){
        Set<String> rules=new LinkedHashSet<>();
        for(Map.Entry<RestrictionEffect,Set<Ability>> entry:game.getContinuousEffects().getApplicableRestrictionEffects(attacker,game).entrySet())
            for(Ability ability:entry.getValue())if(!entry.getKey().canBeBlocked(attacker,blocker,ability,game,false))rules.add(EngineBridge.clean(ability.getRule()));
        for(Map.Entry<RestrictionEffect,Set<Ability>> entry:game.getContinuousEffects().getApplicableRestrictionEffects(blocker,game).entrySet())
            for(Ability ability:entry.getValue())if(!entry.getKey().canBlock(attacker,blocker,ability,game,false))rules.add(EngineBridge.clean(ability.getRule()));
        return new ArrayList<>(rules);
    }
}
