package love2gathering;

import com.google.gson.*;
import mage.Mana;
import mage.abilities.*;
import mage.abilities.effects.keyword.ManifestEffect;
import mage.cards.Card;
import mage.constants.*;
import mage.game.*;
import mage.game.combat.CombatGroup;
import mage.game.permanent.Permanent;
import mage.game.turn.*;
import mage.players.Player;
import mage.util.Copier;
import mage.util.MultiAmountMessage;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

/** Real native combat/responses/watchers; deterministic initial resources only. */
public final class GameplayPresentationFixture {
    static final List<Map<String,Object>> checks=new ArrayList<>();static Path output;
    static void check(boolean value,String label){checks.add(EngineBridge.map("passed",value,"message",label));System.out.println((value?"PASS ":"FAIL ")+label);if(!value)throw new AssertionError(label);}
    @SuppressWarnings("unchecked")static Map<String,Object> object(Object v){return (Map<String,Object>)v;}
    @SuppressWarnings("unchecked")static List<Map<String,Object>> list(Object v){return (List<Map<String,Object>>)v;}
    static long id(Map<String,Object> p){return ((Number)p.get("id")).longValue();}
    static ExecutorService executor(){return Executors.newSingleThreadExecutor(r->new Thread(r,"GAME gameplay presentation fixture"));}
    static void field(EngineBridge.Session s,Player p,Card...cards){s.game.cheat(p.getId(),TriggerFixture.NONE,TriggerFixture.NONE,Arrays.stream(cards).map(c->new PutToBattlefieldInfo(c,false)).toList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);}
    static Map<String,Object> prompt(EngineBridge.Session s,long previous)throws Exception{
        long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(8);while(System.nanoTime()<end){Map<String,Object> p=s.prompt;if(p!=null&&id(p)!=previous&&s.snapshot.get("prompt")==p)return p;Thread.sleep(2);}throw new AssertionError("Native prompt timed out");
    }
    static void answer(EngineBridge.Session s,Map<String,Object> p,String type,Object value)throws Exception{
        JsonObject a=new JsonObject();a.addProperty("promptId",id(p));a.addProperty("expectedGameId",s.game.getId().toString());a.addProperty("type",type);a.add("value",EngineBridge.JSON.toJsonTree(value));s.action(a);
    }
    static void save(String name,EngineBridge.Session s)throws Exception{s.publishAll();Files.writeString(output.resolve(name+".json"),EngineBridge.JSON.toJson(s.snapshot));}
    static Map<String,Object> own(EngineBridge.Session s){return list(s.snapshot.get("players")).stream().filter(p->s.human.getId().toString().equals(p.get("id"))).findFirst().orElseThrow();}
    static <T>T nativeCall(EngineBridge.Session s,Callable<T> call,boolean yes)throws Exception{
        ExecutorService worker=executor();try{Future<T> future=worker.submit(call);long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);long last=-1;
            while(!future.isDone()&&System.nanoTime()<deadline){Map<String,Object> p=s.prompt;if(p!=null&&s.snapshot.get("prompt")==p&&id(p)!=last){
                String type=String.valueOf(p.get("type"));List<Map<String,Object>> choices=list(p.get("choices"));Map<String,Object> selected=null;
                if("ask".equals(type))selected=choices.stream().filter(c->Boolean.valueOf(yes).equals(c.get("value"))).findFirst().orElseThrow();
                else if("play_mana".equals(type))selected=choices.stream().filter(c->"mana".equals(c.get("responseType"))).findFirst().orElseThrow();
                else if("choose_ability".equals(type))selected=choices.stream().filter(c->"uuid".equals(c.get("responseType"))).findFirst().orElseThrow();
                else throw new AssertionError("Unexpected commander fixture prompt: "+EngineBridge.JSON.toJson(p));
                last=id(p);answer(s,p,String.valueOf(selected.get("responseType")),selected.getOrDefault("value",selected.get("id")));
            }else Thread.sleep(2);}return future.get(1,TimeUnit.SECONDS);
        }finally{worker.shutdownNow();}
    }
    static void attackers()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=executor();
        try{Card a=TriggerFixture.card("Raging Goblin"),b=TriggerFixture.card("Goblin Chariot");field(s,s.human,a,b);s.game.applyEffects();s.game.getCombat().setAttacker(s.human.getId());s.game.getCombat().getDefenders().add(s.bot.getId());s.game.getPhase().setStep(new DeclareAttackersStep());
            Future<?> selecting=worker.submit(()->s.human.selectAttackers(s.game,s.human.getId()));Map<String,Object> p=prompt(s,-1);
            check(p.get("combat") instanceof Map&&"attackers".equals(object(p.get("combat")).get("role")),"Native individual-attacker prompt exposes attacker role");
            check(((Collection<?>)p.get("actionable")).contains(a.getId().toString())&&((Collection<?>)p.get("actionable")).contains(b.getId().toString()),"Both actual eligible attackers retain native selectable UUIDs");
            answer(s,p,"uuid",a.getId().toString());p=prompt(s,id(p));
            check(s.game.getCombat().getAttackers().equals(Collections.singleton(a.getId())),"Selecting one UUID declares exactly one actual attacker");
            check(((Collection<?>)object(p.get("combat")).get("selectedAttackerIds")).equals(Collections.singletonList(a.getId().toString())),"Refreshed selection marks the exact native attacker");
            save("individual-attacker",s);answer(s,p,"boolean",true);selecting.get(8,TimeUnit.SECONDS);
        }finally{worker.shutdownNow();s.stop();}
    }
    static void combat()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=executor();
        try{Card a=TriggerFixture.card("Boggart Brute"),b=TriggerFixture.card("Grizzly Bears"),c=TriggerFixture.card("Runeclaw Bear");field(s,s.human,a);field(s,s.bot,b,c);s.game.applyEffects();s.game.getCombat().setAttacker(s.human.getId());s.game.getCombat().getDefenders().add(s.bot.getId());s.game.getPhase().setStep(new DeclareBlockersStep());
            check(s.game.getCombat().addAttackerToCombat(a.getId(),s.bot.getId(),s.game),"Native menace creature joins combat");CombatGroup group=s.game.getCombat().getGroups().get(0);group.addBlocker(b.getId(),s.bot.getId(),s.game);
            check(!s.game.getCombat().checkBlockRestrictions(s.bot,s.game),"Native menace rejects exactly one blocker");group.addBlocker(b.getId(),s.bot.getId(),s.game);group.addBlocker(c.getId(),s.bot.getId(),s.game);check(s.game.getCombat().checkBlockRestrictions(s.bot,s.game),"Native menace accepts two distinct blockers");
            s.game.getPhase().setStep(new CombatDamageStep(false));Future<?> damage=worker.submit(()->group.assignDamageToBlockers(false,s.game));Map<String,Object> p=prompt(s,-1);List<Map<String,Object>> rows=list(p.get("amountMessages"));
            check("multi_amount".equals(p.get("type"))&&rows.size()==2&&a.getId().toString().equals(p.get("damageSourceId")),"Actual native multiple-blocker damage exports its source and two rows");
            check(rows.get(0).get("nativeIndex").equals(1)&&rows.get(1).get("nativeIndex").equals(2)&&rows.get(0).get("targetId").equals(b.getId().toString())&&rows.get(1).get("targetId").equals(c.getId().toString()),"Amount indices remain exactly the native blocker order");
            save("combat-damage",s);boolean rejected=false;try{answer(s,p,"multi_amount",Arrays.asList(3,3));}catch(IllegalArgumentException ex){rejected=true;}
            check(rejected&&s.prompt==p&&!damage.isDone(),"Invalid sum cannot consume the native amount prompt");answer(s,p,"multi_amount",Arrays.asList(1,2));damage.get(8,TimeUnit.SECONDS);
            check(s.game.getPermanent(b.getId()).getDamage()==1&&s.game.getPermanent(c.getId()).getDamage()==2,"Native damage applies user-chosen amounts to their exact row identities");
            boolean stale=false;try{answer(s,p,"multi_amount",Arrays.asList(1,2));}catch(IllegalArgumentException ex){stale=true;}check(stale,"Answered combat distribution cannot be submitted twice");
            s.prompt=null;Future<List<Integer>> generic=worker.submit(()->s.human.getMultiAmountWithIndividualConstraints(Outcome.Damage,Arrays.asList(new MultiAmountMessage("A",0,3),new MultiAmountMessage("B",0,3)),3,3,MultiAmountType.DAMAGE,s.game));p=prompt(s,-1);check(p.get("damageSourceId")==null&&!list(p.get("amountMessages")).get(0).containsKey("targetId"),"Generic amount prompt never inherits former combat source/targets");answer(s,p,"multi_amount",Arrays.asList(2,1));check(generic.get(8,TimeUnit.SECONDS).equals(Arrays.asList(2,1)),"Generic native amount distribution remains covered");
        }finally{worker.shutdownNow();s.stop();}
    }
    static EngineBridge.Session room(){
        JsonObject b=new JsonObject();b.addProperty("format","Limited");b.addProperty("recordingPort",0);JsonArray seats=new JsonArray();for(int i=0;i<3;i++)seats.add(JsonParser.parseString("{\"seatId\":\"human-"+i+"\",\"name\":\"Human "+i+"\",\"type\":\"human\",\"deck\":{\"main\":[{\"name\":\"Plains\",\"count\":40}]}}"));b.add("seats",seats);EngineBridge.Session s=new EngineBridge.Session(b,true);s.game.setStartingPlayerId(s.human.getId());s.game.getState().setActivePlayerId(s.human.getId());s.game.getState().setPriorityPlayerId(s.human.getId());s.game.getTurn().setPhase(new PreCombatMainPhase());s.game.getPhase().setStep(new PreCombatMainStep());for(Player p:s.game.getPlayers().values())p.updateRange(s.game);return s;
    }
    static void faceDown()throws Exception{
        EngineBridge.Session s=room();try{Card card=TriggerFixture.card("Willbender");s.game.cheat(s.human.getId(),Collections.singletonList(card),TriggerFixture.NONE,Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);SpellAbility source=card.getSpellAbility().copy();source.setControllerId(s.human.getId());List<Permanent> manifested=ManifestEffect.doManifestCards(s.game,source,s.human,new HashSet<>(Collections.singletonList(card)));s.game.applyEffects();check(manifested.size()==1&&manifested.get(0).isFaceDown(s.game),"Actual native manifest creates face-down permanent");Permanent permanent=s.game.getPermanent(card.getId());Map<String,Object> self=s.card(permanent);
            check(Boolean.TRUE.equals(self.get("faceDown"))&&"Willbender".equals(object(self.get("faceDownIdentity")).get("name")),"Entitled controller gets separate original identity while battlefield stays face-down");check("2".equals(self.get("power"))&&"2".equals(self.get("toughness")),"Inspection cannot overwrite native face-down 2/2 characteristics");
            for(EngineBridge.Session peer:s.perspectives)if(peer!=s){Map<String,Object> hidden=peer.card(permanent);String json=EngineBridge.JSON.toJson(hidden);check("2".equals(hidden.get("power"))&&"2".equals(hidden.get("toughness"))&&hidden.get("damage").equals(0),"Other human retains native public face-down stats without private artwork");check(Boolean.TRUE.equals(hidden.get("hidden"))&&!hidden.containsKey("faceDownIdentity")&&!hidden.containsKey("printing")&&!json.contains("Willbender"),"Other human face-down view contains no underlying identity/artwork");}
            save("manifest-owner",s);save("manifest-opponent",s.perspectives.get(1));
        }finally{s.stop();}
    }
    static void landSearch()throws Exception{
        EngineBridge.Session s=ActionabilityFixture.setup();ExecutorService worker=executor();try{Card source=TriggerFixture.card("Evolving Wilds"),forest=TriggerFixture.card("Forest"),island=TriggerFixture.card("Island"),nonbasic=TriggerFixture.card("Temple Garden"),creature=TriggerFixture.card("Grizzly Bears");field(s,s.human,source);s.human.getLibrary().clear();s.game.cheat(s.human.getId(),Arrays.asList(forest,island,nonbasic,creature),TriggerFixture.NONE,Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);s.game.applyEffects();ActivatedAbility ability=s.game.getPermanent(source.getId()).getAbilities().getActivatedAbilities(Zone.BATTLEFIELD).stream().filter(a->!a.isManaAbility()).findFirst().orElseThrow();check(nativeCall(s,()->s.human.activateAbility(ability,s.game),true),"Real Evolving Wilds activation pays its sacrifice before library choice");s.game.processAction();Future<?> resolving=worker.submit(()->s.game.getStack().resolve(s.game));Map<String,Object> p=prompt(s,-1);Map<String,Object> panel=object(p.get("cardPanel"));check(panel!=null&&"LIBRARY".equals(panel.get("zone")),"Actual native land search opens a library card panel");List<Map<String,Object>> cards=list(panel.get("cards"));Map<String,Object> basic=cards.stream().filter(c->forest.getId().toString().equals(c.get("id"))).findFirst().orElseThrow();Map<String,Object> invalid=cards.stream().filter(c->nonbasic.getId().toString().equals(c.get("id"))).findFirst().orElseThrow();check(Boolean.TRUE.equals(basic.get("selectable"))&&Boolean.FALSE.equals(invalid.get("selectable")),"Native search shows entitled basic and nonbasic candidates with exact legality flags");check(((Collection<?>)basic.get("supertypes")).contains("Basic")&&((Collection<?>)object(basic.get("printing")).get("supertypes")).contains("Basic")&&!((Collection<?>)invalid.get("supertypes")).contains("Basic"),"Native Basic supertype is explicit for land sorting, distinct from nonbasic subtype names");save("land-search",s);answer(s,p,"uuid",forest.getId().toString());resolving.get(8,TimeUnit.SECONDS);s.game.processAction();check(s.game.getPermanent(forest.getId())!=null&&s.game.getPermanent(forest.getId()).isTapped(),"Native search accepts the offered Forest UUID and puts it onto battlefield tapped");
        }finally{worker.shutdownNow();s.stop();}
    }
    static EngineBridge.Session commander(boolean damage)throws Exception{
        JsonObject body=new JsonObject();body.addProperty("format","Commander");body.addProperty("recordingPort",0);body.addProperty("commanderDamage",damage);JsonObject deck=new JsonObject();deck.add("commander",JsonParser.parseString("[{\"name\":\"Goreclaw, Terror of Qal Sisma\",\"count\":1}]"));deck.add("main",JsonParser.parseString("[{\"name\":\"Forest\",\"count\":99}]"));body.add("deck",deck);body.add("botDeck",deck.deepCopy());EngineBridge.Session s=new EngineBridge.Session(body);s.game.setStartingPlayerId(s.human.getId());s.game.getState().setActivePlayerId(s.human.getId());s.game.getState().setPriorityPlayerId(s.human.getId());s.game.getTurn().setPhase(new PreCombatMainPhase());s.game.getPhase().setStep(new PreCombatMainStep());for(Player p:s.game.getPlayers().values())p.updateRange(s.game);return s;
    }
    static void commanders(boolean enabled)throws Exception{
        EngineBridge.Session s=commander(enabled);try{GameCommanderImpl game=(GameCommanderImpl)s.game;check(game.isCheckCommanderDamage()==enabled,"Requested commander-damage option configures the actual native game");Card card=TriggerFixture.card("Goreclaw, Terror of Qal Sisma");game.loadCards(Collections.singleton(card),s.human.getId());game.addCommander(card,s.human);game.initCommander(card,s.human);s.publishAll();Map<String,Object> row=list(own(s).get("commanders")).stream().filter(r->card.getId().toString().equals(r.get("id"))).findFirst().orElseThrow();check(row.get("commandZonePlays").equals(0)&&row.get("deaths").equals(0),"Commander ledger starts with separate native plays and deaths");
            s.human.getManaPool().addMana(Mana.GreenMana(12),s.game,card.getSpellAbility());SpellAbility cast=(SpellAbility)game.getObject(card.getId()).getAbilities().stream().filter(a->a instanceof SpellAbility&&a.getZone()==Zone.COMMAND).findFirst().orElseThrow();check(nativeCall(s,()->s.human.cast(cast,s.game,false,null),true),"Actual native commander cast succeeds from command zone");game.getStack().resolve(game);game.applyEffects();s.publishAll();row=list(own(s).get("commanders")).stream().filter(r->card.getId().toString().equals(r.get("id"))).findFirst().orElseThrow();check(row.get("commandZonePlays").equals(1)&&"{2}".equals(object(row.get("additionalTax")).get("manaCost")),"Successful native command-zone cast increments true count and native tax");
            Permanent permanent=game.getPermanent(card.getId());s.bot.damage(7,permanent.getId(),null,game,false,true);s.publishAll();Map<String,Object> victim=list(s.snapshot.get("players")).stream().filter(p->s.bot.getId().toString().equals(p.get("id"))).findFirst().orElseThrow();Map<String,Object> received=list(victim.get("commanderDamageReceived")).stream().filter(r->card.getId().toString().equals(r.get("commanderId"))).findFirst().orElseThrow();check(received.get("amount").equals(0),"Noncombat commander damage never increments native commander combat ledger");
            s.bot.damage(6,permanent.getId(),null,game,true,true);s.publishAll();victim=list(s.snapshot.get("players")).stream().filter(p->s.bot.getId().toString().equals(p.get("id"))).findFirst().orElseThrow();received=list(victim.get("commanderDamageReceived")).stream().filter(r->card.getId().toString().equals(r.get("commanderId"))).findFirst().orElseThrow();check(received.get("amount").equals(enabled?6:0),"Combat ledger follows native enabled/disabled commander watcher");
            // A non-creature state change to another zone is not a death.
            nativeCall(s,()->permanent.moveToZone(Zone.HAND,null,game,false),false);s.publishAll();row=list(own(s).get("commanders")).stream().filter(r->card.getId().toString().equals(r.get("id"))).findFirst().orElseThrow();check(row.get("deaths").equals(0)&&row.get("commandZonePlays").equals(1),"Bounce is neither a death nor another command-zone play");save(enabled?"commander-enabled":"commander-disabled",s);
            s.human.getManaPool().addMana(Mana.GreenMana(8),game,card.getSpellAbility());check(nativeCall(s,()->s.human.cast(card.getSpellAbility(),game,false,null),true),"Native commander recast from hand succeeds");game.getStack().resolve(game);game.applyEffects();
            check(nativeCall(s,()->game.getPermanent(card.getId()).destroy(card.getSpellAbility(),game),false),"Native commander destruction moves creature to graveyard");game.processAction();s.publishAll();row=list(own(s).get("commanders")).stream().filter(r->card.getId().toString().equals(r.get("id"))).findFirst().orElseThrow();check(row.get("deaths").equals(1)&&row.get("commandZonePlays").equals(1),"Actual death increments death history while hand cast leaves tax count unchanged");
            Game copy=game.createSimulationForPlayableCalc();CommanderHistoryWatcher copyHistory=copy.getState().getWatcher(CommanderHistoryWatcher.class);copyHistory.deaths.put(card.getId(),99);check(game.getState().getWatcher(CommanderHistoryWatcher.class).count(card.getId())==1,"Native simulation owns a detached death history rather than mutating the live watcher");save(enabled?"commander-death-enabled":"commander-death-disabled",s);
        }finally{s.stop();}
    }
    static void threshold(boolean enabled)throws Exception{
        EngineBridge.Session s=commander(enabled);try{GameCommanderImpl game=(GameCommanderImpl)s.game;Card card=TriggerFixture.card("Goreclaw, Terror of Qal Sisma");game.loadCards(Collections.singleton(card),s.human.getId());game.addCommander(card,s.human);game.initCommander(card,s.human);nativeCall(s,()->card.moveToZone(Zone.BATTLEFIELD,null,game,false),false);game.applyEffects();
            s.bot.damage(21,card.getId(),null,game,true,true);game.checkStateAndTriggered();check(s.bot.getLife()>0&&s.bot.hasLost()==enabled,"Native 21-commander-combat loss is "+(enabled?"enabled":"disabled")+" while life remains positive");save(enabled?"commander-threshold-enabled":"commander-threshold-disabled",s);
        }finally{s.stop();}
    }
    static void specialTax()throws Exception{
        EngineBridge.Session s=commander(true);try{GameCommanderImpl game=(GameCommanderImpl)s.game;Card card=TriggerFixture.card("Liesa, Shroud of Dusk");game.loadCards(Collections.singleton(card),s.human.getId());game.addCommander(card,s.human);game.initCommander(card,s.human);s.human.getManaPool().addMana(Mana.WhiteMana(4),game,card.getSpellAbility());s.human.getManaPool().addMana(Mana.BlackMana(4),game,card.getSpellAbility());SpellAbility ability=(SpellAbility)game.getObject(card.getId()).getAbilities().stream().filter(a->a instanceof SpellAbility&&a.getZone()==Zone.COMMAND).findFirst().orElseThrow();check(nativeCall(s,()->s.human.cast(ability,game,false,null),true),"Native Liesa cast establishes a real command-zone play count");game.getStack().resolve(game);game.applyEffects();s.publishAll();Map<String,Object> row=list(own(s).get("commanders")).stream().filter(r->card.getId().toString().equals(r.get("id"))).findFirst().orElseThrow();Map<String,Object> tax=object(row.get("additionalTax"));check(row.get("commandZonePlays").equals(1)&&"".equals(tax.get("manaCost"))&&tax.get("otherCosts").toString().contains("2 life"),"Native Liesa tax is life, not an invented generic-mana multiplier");save("commander-liesa-tax",s);
        }finally{s.stop();}
    }
    public static void main(String[] args)throws Exception{
        Thread.currentThread().setName("GAME gameplay main fixture");org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);Path root=Paths.get(args[0]);output=Paths.get(args[1]);Files.createDirectories(output);EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(GameplayPresentationFixture.class.getClassLoader());String failure=null;
        try{attackers();if(args.length<3||!args[2].equals("baseline")){combat();faceDown();landSearch();commanders(true);commanders(false);threshold(true);threshold(false);specialTax();}}catch(Throwable ex){failure=ex.toString();ex.printStackTrace();}
        Files.writeString(output.resolve("result.json"),EngineBridge.JSON.toJson(EngineBridge.map("passed",failure==null,"failure",failure,"checks",checks)));System.exit(failure==null?0:1);
    }
}
