package love2gathering;

import com.google.gson.*;
import mage.abilities.*;
import mage.cards.*;
import mage.constants.*;
import mage.counters.CounterType;
import mage.game.*;
import mage.game.combat.CombatGroup;
import mage.game.permanent.Permanent;
import mage.game.turn.DeclareBlockersStep;
import mage.target.Target;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.stream.Collectors;

/** Native rules/choices with deterministic initial test zones; no UI or mocked rules. */
public final class NativeViewFixture {
    static int checks;
    static void require(boolean value,String label){if(!value)throw new AssertionError(label);checks++;}
    @SuppressWarnings("unchecked") static Map<String,Object> object(Object value){return (Map<String,Object>)value;}
    @SuppressWarnings("unchecked") static List<Map<String,Object>> list(Object value){return (List<Map<String,Object>>)value;}
    static ExecutorService executor(){return Executors.newSingleThreadExecutor(r->new Thread(r,"GAME native view fixture"));}
    static void frame(String name,EngineBridge.Session session){session.publish();try{Files.writeString(Paths.get("/tmp/love2gathering-native-"+name+"-frame.json"),EngineBridge.JSON.toJson(session.snapshot));}catch(java.io.IOException ex){throw new java.io.UncheckedIOException(ex);}}
    static void battlefield(EngineBridge.Session s,UUID owner,Card... cards){s.game.cheat(owner,TriggerFixture.NONE,TriggerFixture.NONE,Arrays.stream(cards).map(c->new PutToBattlefieldInfo(c,false)).collect(Collectors.toList()),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);s.game.applyEffects();}
    static Map<String,Object> next(EngineBridge.Session s,long previous)throws Exception{return ActionabilityFixture.waitPrompt(s,previous);}
    static void answer(EngineBridge.Session s,Map<String,Object> p,String id)throws Exception{
        Map<String,Object> choice=list(p.get("choices")).stream().filter(c->id.equals(c.get("id"))).findFirst().orElseThrow();ActionabilityFixture.answer(s,p,choice);
    }
    static long promptId(Map<String,Object> p){return ((Number)p.get("id")).longValue();}
    static void angel(){
        EngineBridge.Session s=ActionabilityFixture.setup();
        try{
            Card angel=TriggerFixture.card("Angel of Vitality");battlefield(s,s.bot.getId(),angel);Permanent live=s.game.getPermanent(angel.getId());
            s.bot.setLife(25,s.game,null);live.addCounters(CounterType.P1P1.createInstance(),s.bot.getId(),null,s.game);s.game.applyEffects();
            Map<String,Object> view=s.card(live);
            require("5".equals(view.get("power"))&&"5".equals(view.get("toughness")),"Angel at25life pluscounter must project native5/5");
            require("2".equals(object(view.get("printing")).get("power")),"Printed Angel remains2/2 independently");
            require(((Number)object(view.get("counters")).get("+1/+1")).intValue()==1,"Native +1/+1 counter is visible");
            frame("angel",s);
            s.bot.setLife(24,s.game,null);s.game.applyEffects();view=s.card(s.game.getPermanent(angel.getId()));
            require("3".equals(view.get("power")),"Native condition removal changes displayed5/5 to3/3");
            require(s.bot.getId().toString().equals(view.get("ownerId"))&&s.bot.getId().toString().equals(view.get("controllerId")),"Owner/controller identity survives projection");
        }finally{s.stop();}
    }
    static void scrySurveil(boolean surveil)throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=executor();
        try{
            List<Card> library=Arrays.asList(TriggerFixture.card("Mountain"),TriggerFixture.card("Forest"),TriggerFixture.card("Island"),TriggerFixture.card("Swamp"));
            s.game.cheat(s.human.getId(),library,TriggerFixture.NONE,Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            Set<UUID> top=s.human.getLibrary().getTopCards(s.game,3).stream().map(Card::getId).collect(Collectors.toSet());
            Future<?> action=worker.submit(()->{if(surveil)s.human.doSurveil(3,null,s.game);else s.human.scry(3,null,s.game);});
            Map<String,Object> p=next(s,-1),panel=object(p.get("cardPanel"));long interaction=((Number)panel.get("interactionId")).longValue();
            Files.writeString(Paths.get(surveil?"/tmp/love2gathering-native-surveil-prompt.json":"/tmp/love2gathering-native-scry-prompt.json"),EngineBridge.JSON.toJson(p));
            frame(surveil?"surveil":"scry",s);
            require((surveil?"surveil":"scry").equals(panel.get("kind")),"Native operation labels card panel without text parsing");
            require((surveil?"graveyard":"bottom").equals(panel.get("selectionDestination"))&&"top".equals(panel.get("remainingDestination")),"Native destination metadata is exact");
            require(list(panel.get("cards")).size()==3,"All three offered top cards are visible to their chooser");
            require(p.get("startedAt") instanceof Number&&s.human.getId().toString().equals(p.get("playerId")),"Prompt includes actual owner and creation time");
            Map<String,Object> chosen=list(panel.get("cards")).get(0);UUID moved=UUID.fromString(chosen.get("choiceId").toString());
            require(top.contains(moved)&&"uuid".equals(chosen.get("responseType")),"Card panel uses native offered response IDs");
            long previous=promptId(p);answer(s,p,moved.toString());p=next(s,previous);panel=object(p.get("cardPanel"));
            require(((Number)panel.get("interactionId")).longValue()==interaction,"One interaction retains identity over native subset prompts");
            require(list(panel.get("cards")).stream().anyMatch(c->moved.toString().equals(c.get("id"))&&Boolean.TRUE.equals(c.get("selected"))),"Native selected state is retained without moving an uncommitted selection");
            previous=promptId(p);answer(s,p,"done");p=next(s,previous);panel=object(p.get("cardPanel"));
            require("order".equals(panel.get("stage"))&&"top".equals(panel.get("orderDestination"))&&"last_chosen_topmost".equals(panel.get("orderDirection")),"Native remaining-card ordering direction is explicit");
            List<Map<String,Object>> orderCards=list(panel.get("cards"));String ordered=orderCards.get(0).get("choiceId").toString();
            String finalTop=orderCards.get(1).get("choiceId").toString();answer(s,p,ordered);action.get(10,TimeUnit.SECONDS);
            require(surveil?s.human.getGraveyard().contains(moved):s.human.getLibrary().getFromBottom(s.game).getId().equals(moved),"Native destination actually receives selected card");
            require(s.human.getLibrary().getFromTop(s.game).getId().toString().equals(finalTop),"Native last remaining automatically placed card is topmost");
            require(s.game.getState().getLookedAt(s.bot.getId()).values().stream().noneMatch(c->c.contains(moved)),"Other seat receives no private looked-at entitlement");
        }finally{worker.shutdownNow();s.stop();}
    }
    static void cancellation()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=executor();
        try{
            // Normal Game.start creates this native iteration cursor; this
            // deterministic zone fixture starts after pregame instead.
            java.lang.reflect.Field cursor=GameImpl.class.getDeclaredField("playerList");cursor.setAccessible(true);cursor.set(s.game,s.game.getState().getPlayerList(s.human.getId()));
            Card strider=TriggerFixture.card("Woe Strider"),creature=TriggerFixture.card("Grizzly Bears");battlefield(s,s.human.getId(),strider,creature);
            s.game.getState().clearTriggeredAbilities();s.game.getStack().clear();
            ActivatedAbility ability=(ActivatedAbility)s.game.getPermanent(strider.getId()).getAbilities().stream().filter(a->a instanceof ActivatedAbility&&a.getRule().contains("Scry")).findFirst().orElseThrow();
            Future<Boolean> activation=worker.submit(()->s.human.activateAbility(ability,s.game));Map<String,Object> p=next(s,-1);
            require(p.get("cancelChoice")!=null&&"pending_action".equals(p.get("cancelScope")),"Woe Strider exposes native pre-sacrifice cancellation");
            frame("cancel",s);
            ActionabilityFixture.answer(s,p,object(p.get("cancelChoice")));require(!activation.get(10,TimeUnit.SECONDS),"Native cancellation rejects incomplete activation");
            require(s.game.getPermanent(creature.getId())!=null&&s.game.getStack().isEmpty(),"Native activation bookmark restores creature and stack");
            long previous=promptId(p);ActivatedAbility again=(ActivatedAbility)s.game.getPermanent(strider.getId()).getAbilities().stream().filter(a->a instanceof ActivatedAbility&&a.getRule().contains("Scry")).findFirst().orElseThrow();
            activation=worker.submit(()->s.human.activateAbility(again,s.game));p=next(s,previous);answer(s,p,creature.getId().toString());
            require(activation.get(10,TimeUnit.SECONDS)&&s.game.getPermanent(creature.getId())==null&&s.game.getStack().size()==1,"Committed native sacrifice is not undone after activation");
            Card top=TriggerFixture.card("Island");s.game.cheat(s.human.getId(),Collections.singletonList(top),TriggerFixture.NONE,Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            previous=promptId(p);Future<?> resolution=worker.submit(()->s.game.getStack().resolve(s.game));p=next(s,previous);
            require("choice".equals(p.get("cancelScope"))&&p.get("pendingAction")==null,"Resolved scry cannot advertise activation undo");
            answer(s,p,"done");resolution.get(10,TimeUnit.SECONDS);
            require(s.game.getPermanent(creature.getId())==null&&s.human.getGraveyard().contains(creature.getId()),"Finishing scry cannot restore a paid sacrifice");
        }finally{worker.shutdownNow();s.stop();}
    }
    static void combat()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=executor();
        try{
            Card flying=TriggerFixture.card("Wind Drake"),walk=TriggerFixture.card("River Boa"),menace=TriggerFixture.card("Boggart Brute"),unblockable=TriggerFixture.card("Invisible Stalker");
            Card ground=TriggerFixture.card("Grizzly Bears"),reach=TriggerFixture.card("Giant Spider"),air=TriggerFixture.card("Wind Drake"),island=TriggerFixture.card("Island");
            battlefield(s,s.bot.getId(),flying,walk,menace,unblockable);battlefield(s,s.human.getId(),ground,reach,air,island);
            s.game.getPhase().setStep(new DeclareBlockersStep());s.game.getState().setActivePlayerId(s.bot.getId());
            s.game.getCombat().getDefenders().add(s.human.getId());
            for(Card card:Arrays.asList(flying,walk,menace,unblockable))require(s.game.getCombat().addAttackerToCombat(card.getId(),s.human.getId(),s.game),"Native deterministic attacker is added to combat");
            List<Map<String,Object>> options=NativeProjection.blockerOptions(s,Arrays.asList(ground.getId(),reach.getId(),air.getId()));
            Map<String,Object> groundView=options.stream().filter(o->ground.getId().toString().equals(o.get("blockerId"))).findFirst().orElseThrow();
            Collection<?> groundAllowed=(Collection<?>)groundView.get("legalAttackerIds");
            require(!groundAllowed.contains(flying.getId().toString())&&!groundAllowed.contains(walk.getId().toString())&&!groundAllowed.contains(unblockable.getId().toString()),"Native blocker preview rejects flying, islandwalk and unblockable attacks for ground creature");
            require(groundAllowed.contains(menace.getId().toString()),"Menace remains pairwise legal before group constraint: "+EngineBridge.JSON.toJson(options));
            for(Map<String,Object> option:options)if(!ground.getId().toString().equals(option.get("blockerId")))require(((Collection<?>)option.get("legalAttackerIds")).contains(flying.getId().toString()),"Native reach/flying creatures may block flyer");
            Map<String,Object> combat=NativeProjection.combat(s);Map<String,Object> menaceView=list(combat.get("groups")).stream().filter(g->menace.getId().toString().equals(g.get("attackerId"))).findFirst().orElseThrow();
            require(((Number)menaceView.get("minBlockers")).intValue()==2,"Native menace minimum is distinct from pairwise legality");
            require(s.prompt==null,"Legality preview cannot open a live choice or mutate pending prompt");
            Future<?> nativeSelection=worker.submit(()->s.human.selectBlockers(null,s.game,s.human.getId()));Map<String,Object> prompt=next(s,-1);
            require("blockers".equals(object(prompt.get("combat")).get("role")),"Actual native blocker prompt includes native preview metadata");
            frame("combat",s);answer(s,prompt,"done");nativeSelection.get(10,TimeUnit.SECONDS);
            s.human.declareBlocker(s.human.getId(),ground.getId(),menace.getId(),s.game,false);
            require(s.game.getCombat().findGroup(menace.getId()).getBlockers().contains(ground.getId()),"Native declaration records actual blocker relationship");
            require(!s.game.getCombat().findGroup(menace.getId()).checkBlockRestrictions(s.game,s.human,0),"Native menace rejects lone blocker");
        }finally{worker.shutdownNow();s.stop();}
    }
    static void attachments(){
        EngineBridge.Session s=ActionabilityFixture.setup();
        try{
            Card bear=TriggerFixture.card("Grizzly Bears"),equipment=TriggerFixture.card("Bonesplitter"),aura=TriggerFixture.card("Utopia Sprawl"),forest=TriggerFixture.card("Forest"),curse=TriggerFixture.card("Curse of Opulence"),ring=TriggerFixture.card("Oblivion Ring"),exile=TriggerFixture.card("Mountain");
            battlefield(s,s.human.getId(),bear,equipment,forest,ring);battlefield(s,s.bot.getId(),aura,curse);
            // Initial attachment setup deliberately bypasses ETB choice resolution.
            s.game.getPermanent(equipment.getId()).attachTo(bear.getId(),null,s.game);
            s.game.getPermanent(aura.getId()).attachTo(forest.getId(),null,s.game);
            s.game.getPermanent(curse.getId()).attachTo(s.human.getId(),null,s.game);
            require(bear.getId().toString().equals(s.card(s.game.getPermanent(equipment.getId())).get("attachedToId")),"Equipment projects native attachment target");
            require(forest.getId().toString().equals(s.card(s.game.getPermanent(aura.getId())).get("attachedToId")),"Opponent-controlled land aura retains its attachment target");
            require(s.human.getId().toString().equals(s.card(s.game.getPermanent(curse.getId())).get("attachedToPlayerId")),"Native curse exposes player attachment separately");
            s.game.loadCards(Collections.singleton(exile),s.bot.getId());exile.setZone(Zone.OUTSIDE,s.game);
            UUID zone=mage.util.CardUtil.getExileZoneId(s.game,ring.getId(),s.game.getPermanent(ring.getId()).getZoneChangeCounter(s.game));
            s.bot.moveCardsToExile(exile,null,s.game,true,zone,"Oblivion Ring");
            List<Map<String,Object>> linked=list(s.card(s.game.getPermanent(ring.getId())).get("linkedExile"));
            require(linked.size()==1&&"Mountain".equals(linked.get(0).get("name")),"Existing native source exile zone is linked without creating projection state");
            exile.setFaceDown(true,s.game);linked=list(s.card(s.game.getPermanent(ring.getId())).get("linkedExile"));
            require(Boolean.TRUE.equals(linked.get(0).get("hidden"))&&!"Mountain".equals(linked.get(0).get("name")),"Unentitled face-down linked exile stays anonymous");
            s.game.getState().getLookedAt(s.human.getId()).put("Entitled exile",new CardsImpl(exile));
            require("Mountain".equals(list(s.card(s.game.getPermanent(ring.getId())).get("linkedExile")).get(0).get("name")),"Explicit native look-at entitlement makes linked face-down card inspectable");
        }finally{s.stop();}
    }
    static void stackEvents()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=executor();
        try{
            Card bolt=TriggerFixture.card("Lightning Bolt");s.game.cheat(s.human.getId(),TriggerFixture.NONE,Collections.singletonList(bolt),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            s.human.getManaPool().addMana(mage.Mana.RedMana(1),s.game,bolt.getSpellAbility());
            Future<Boolean> cast=worker.submit(()->s.human.cast(bolt.getSpellAbility(),s.game,false,null));Map<String,Object> p=next(s,-1);answer(s,p,s.bot.getId().toString());require(cast.get(10,TimeUnit.SECONDS),"Native instant really casts");
            Map<String,Object> stack=s.stackCard(s.game.getStack().peek());
            require(((Collection<?>)stack.get("targetIds")).contains(s.bot.getId().toString())&&bolt.getId().toString().equals(stack.get("sourceId")),"Public stack preserves exact source-to-target IDs");
            worker.submit(()->s.game.getStack().resolve(s.game)).get(10,TimeUnit.SECONDS);
            s.human.gainLife(2,s.game,bolt.getSpellAbility());s.publish();
            List<Map<String,Object>> events=list(s.snapshot.get("animationEvents"));
            require(events.stream().anyMatch(e->"damage".equals(e.get("type"))&&((Number)e.get("amount")).intValue()==3&&s.bot.getId().toString().equals(e.get("targetId"))),"Real native Bolt damage has target/amount animation event");
            require(events.stream().anyMatch(e->"life_gain".equals(e.get("type"))&&((Number)e.get("amount")).intValue()==2),"Real native life gain has a separate structured event");
            require(events.stream().map(e->e.get("id")).distinct().count()==events.size(),"Native event ring keeps distinct stable IDs");
            require(s.log.stream().anyMatch(e->e.get("sourceCard")!=null&&Boolean.TRUE.equals(e.get("stackEvent"))),"Native log supplies entitled source card and stack category");
            s.human.lookAtCards("Private top card",new CardsImpl(bolt),s.game);s.publish();
            require(!list(s.snapshot.get("lookedAt")).isEmpty(),"Native look-at callback produces inspectable private popup data");
            require(Boolean.FALSE.equals(object(s.snapshot.get("clock")).get("enabled")),"Untimed match cannot invent a timeout penalty");
        }finally{worker.shutdownNow();s.stop();}
    }
    static void tokens(){
        EngineBridge.Session s=ActionabilityFixture.setup();
        try{
            Card strider=TriggerFixture.card("Woe Strider");s.game.loadCards(Collections.singleton(strider),s.human.getId());strider.setZone(Zone.OUTSIDE,s.game);
            require(strider.putOntoBattlefield(s.game,Zone.OUTSIDE,null,s.human.getId()),"Woe Strider really enters for its token trigger");s.game.checkStateAndTriggered();
            require(!s.game.getStack().isEmpty(),"Native Woe Strider token trigger reaches stack");s.game.getStack().resolve(s.game);s.game.applyEffects();
            Permanent goat=s.game.getBattlefield().getAllActivePermanents().stream().filter(Permanent::isToken).findFirst().orElseThrow();Map<String,Object> view=s.card(goat);
            require(Boolean.TRUE.equals(view.get("token"))&&Boolean.TRUE.equals(view.get("isToken")),"Real native token is marked separately from printing artwork");
            require("0".equals(view.get("power"))&&"1".equals(view.get("toughness"))&&((Collection<?>)view.get("colors")).contains("W"),"Native Goat token retains actual P/T and color");
            require(s.human.getId().toString().equals(view.get("ownerId")),"Native token owner is preserved");
            goat.addCounters(CounterType.P1P1.createInstance(),s.human.getId(),null,s.game);s.game.applyEffects();view=s.card(s.game.getPermanent(goat.getId()));
            require("1".equals(view.get("power"))&&"0".equals(object(view.get("printing")).get("power")),"Token counters update live P/T without changing original artwork identity");
            require(((Collection<?>)object(view.get("printing")).get("colors")).contains("W")&&object(view.get("printing")).get("type_line").toString().contains("Goat"),"Token original template supplies colors/type/subtype for artwork matching");
            mage.abilities.effects.common.continuous.BecomesColorTargetEffect color=new mage.abilities.effects.common.continuous.BecomesColorTargetEffect(mage.ObjectColor.RED,Duration.EndOfTurn);
            color.setTargetPointer(new mage.target.targetpointer.FixedTarget(goat.getId(),s.game));s.game.addEffect(color,strider.getSpellAbility());s.game.applyEffects();view=s.card(s.game.getPermanent(goat.getId()));
            require(((Collection<?>)view.get("colors")).contains("R")&&!((Collection<?>)view.get("colors")).contains("W")&&((Collection<?>)object(view.get("printing")).get("colors")).contains("W"),"Native color-changing effect does not change token printing artwork identity");
        }finally{s.stop();}
    }
    public static void main(String[] args)throws Exception{
        org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        Path root=Paths.get(args[0]);EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(NativeViewFixture.class.getClassLoader());
        angel();scrySurveil(false);scrySurveil(true);cancellation();combat();attachments();stackEvents();tokens();
        Map<String,Object> report=EngineBridge.map("passed",true,"checks",checks,"scope","Real native fixture with deterministic initial zones: boosted P/T/counters, sequential scry/surveil placement/order, precommit activation cancellation, native blocker restrictions, attachments and source-linked exile. No frontend interaction.");
        Files.writeString(root.resolve("bridge/tests/native-view-report.json"),EngineBridge.JSON.toJson(report)+"\n");System.out.println(EngineBridge.JSON.toJson(report));
    }
}
