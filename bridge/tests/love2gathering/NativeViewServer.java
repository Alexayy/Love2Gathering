package love2gathering;

import com.google.gson.*;
import com.sun.net.httpserver.*;
import mage.abilities.*;
import mage.cards.*;
import mage.constants.*;
import mage.counters.CounterType;
import mage.game.*;
import mage.game.permanent.Permanent;
import mage.game.turn.DeclareBlockersStep;
import mage.util.Copier;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.stream.Collectors;

/** Test-only HTTP facade over real HumanPlayer choices and deterministic zones.
 * Never compiled into the production bridge JAR or registered by EngineBridge.
 */
public final class NativeViewServer {
    static volatile Scene current;
    static final List<Scene> completed=new CopyOnWriteArrayList<>();
    static final class Scene {
        final String name;
        final EngineBridge.Session session;
        final List<Map<String,Object>> accepted=new CopyOnWriteArrayList<>();
        volatile Map<String,Object> result=EngineBridge.map("done",false);
        Scene(String name){this.name=name;session=ActionabilityFixture.setup();}
        void run(){
            try{
                if(name.equals("angel"))angel();
                else if(name.equals("scry")||name.equals("surveil"))arrange();
                else if(name.equals("cancel"))cancel();
                else if(name.equals("combat"))combat();
                else if(name.equals("look"))look();
                else throw new IllegalArgumentException("Unknown native fixture scene");
            }catch(Throwable ex){result=EngineBridge.map("done",true,"error",ex.toString());ex.printStackTrace();}
            finally{session.prompt=null;session.publish();completed.add(this);}
        }
        Map<String,Object> report(){return EngineBridge.map("scenario",name,"nativeResult",result,"acceptedActions",new ArrayList<>(accepted),"scope","Native deterministic initial zones; actual production Session.action and HumanPlayer responses; not a production-deck game");}
        void angel(){
            Card angel=TriggerFixture.card("Angel of Vitality");NativeViewFixture.battlefield(session,session.bot.getId(),angel);
            session.bot.setLife(25,session.game,null);Permanent p=session.game.getPermanent(angel.getId());p.addCounters(CounterType.P1P1.createInstance(),session.bot.getId(),null,session.game);session.game.applyEffects();session.publish();
            Map<String,Object> card=session.card(p);result=EngineBridge.map("done",true,"power",card.get("power"),"toughness",card.get("toughness"),"printedPower",NativeViewFixture.object(card.get("printing")).get("power"),"counters",card.get("counters"));
        }
        void arrange(){
            List<Card> library=Arrays.asList(TriggerFixture.card("Mountain"),TriggerFixture.card("Forest"),TriggerFixture.card("Island"),TriggerFixture.card("Swamp"));
            session.game.cheat(session.human.getId(),library,TriggerFixture.NONE,Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            if(name.equals("scry"))session.human.scry(3,null,session.game);else session.human.doSurveil(3,null,session.game);
            result=EngineBridge.map("done",true,"libraryTopToBottom",session.cards(session.human.getLibrary().getCards(session.game)),"graveyard",session.cards(session.human.getGraveyard().getCards(session.game)));
        }
        void cancel()throws Exception{
            java.lang.reflect.Field cursor=GameImpl.class.getDeclaredField("playerList");cursor.setAccessible(true);cursor.set(session.game,session.game.getState().getPlayerList(session.human.getId()));
            Card strider=TriggerFixture.card("Woe Strider");session.game.loadCards(Collections.singleton(strider),session.human.getId());strider.setZone(Zone.OUTSIDE,session.game);
            strider.putOntoBattlefield(session.game,Zone.OUTSIDE,null,session.human.getId());session.game.checkStateAndTriggered();session.game.getStack().resolve(session.game);session.game.applyEffects();
            Permanent goat=session.game.getBattlefield().getAllActivePermanents().stream().filter(Permanent::isToken).findFirst().orElseThrow();
            ActivatedAbility ability=(ActivatedAbility)session.game.getPermanent(strider.getId()).getAbilities().stream().filter(a->a instanceof ActivatedAbility&&a.getRule().contains("Scry")).findFirst().orElseThrow();
            boolean activated=session.human.activateAbility(ability,session.game);
            result=EngineBridge.map("done",true,"activationAccepted",activated,"sacrificeStillPresent",session.game.getPermanent(goat.getId())!=null,"striderStillPresent",session.game.getPermanent(strider.getId())!=null,"stackSize",session.game.getStack().size());
        }
        void look(){
            Card secret=TriggerFixture.card("Mountain");session.game.cheat(session.bot.getId(),TriggerFixture.NONE,Collections.singletonList(secret),Collections.emptyList(),TriggerFixture.NONE,TriggerFixture.NONE,TriggerFixture.NONE);
            session.human.lookAtCards("Native private look",new CardsImpl(secret),session.game);
            result=EngineBridge.map("done",true,"lookedAtCardId",secret.getId().toString(),"nativeTransientListCleared",session.game.getState().getLookedAt(session.human.getId()).isEmpty());
        }
        void combat(){
            List<Card> attackers=Arrays.asList(TriggerFixture.card("Wind Drake"),TriggerFixture.card("River Boa"),TriggerFixture.card("Boggart Brute"),TriggerFixture.card("Invisible Stalker"));
            List<Card> blockers=Arrays.asList(TriggerFixture.card("Grizzly Bears"),TriggerFixture.card("Giant Spider"),TriggerFixture.card("Wind Drake"),TriggerFixture.card("Island"));
            NativeViewFixture.battlefield(session,session.bot.getId(),attackers.toArray(new Card[0]));NativeViewFixture.battlefield(session,session.human.getId(),blockers.toArray(new Card[0]));
            session.game.getPhase().setStep(new DeclareBlockersStep());session.game.getState().setActivePlayerId(session.bot.getId());session.game.getCombat().setAttacker(session.bot.getId());session.game.getCombat().getDefenders().add(session.human.getId());
            for(Card card:attackers)session.game.getCombat().addAttackerToCombat(card.getId(),session.human.getId(),session.game);
            session.game.getCombat().selectBlockers(session.game);
            result=EngineBridge.map("done",true,"combat",NativeProjection.combat(session));
        }
    }
    static synchronized Scene setup(String name){
        if(!Arrays.asList("angel","scry","surveil","cancel","combat","look").contains(name))throw new IllegalArgumentException("Unknown native fixture scene");
        if(current!=null)current.session.stop();Scene next=new Scene(name);current=next;EngineBridge.current=next.session;
        Thread game=new Thread(next::run,"GAME native GUI fixture "+name);game.setDaemon(true);next.session.gameThread=game;game.start();return next;
    }
    static void respond(HttpExchange exchange,int status,Object result)throws IOException{
        byte[] body=EngineBridge.JSON.toJson(result).getBytes(StandardCharsets.UTF_8);exchange.getResponseHeaders().set("Content-Type","application/json");exchange.getResponseHeaders().set("Cache-Control","no-store");exchange.sendResponseHeaders(status,body.length);try(OutputStream out=exchange.getResponseBody()){out.write(body);}
    }
    static void fixture(HttpExchange exchange)throws IOException{
        try{
            if(exchange.getRequestHeaders().containsKey("Origin"))throw new SecurityException("Browser origins are unavailable in the fixture");
            String name=exchange.getRequestURI().getPath().substring("/fixture/".length());
            if(name.equals("result")&&exchange.getRequestMethod().equals("GET")){respond(exchange,200,current==null?EngineBridge.map("done",false):current.report());return;}
            if(name.equals("report")&&exchange.getRequestMethod().equals("GET")){respond(exchange,200,EngineBridge.map("completed",completed.stream().map(Scene::report).collect(Collectors.toList()),"current",current==null?null:current.report()));return;}
            if(!exchange.getRequestMethod().equals("POST"))throw new IllegalArgumentException("POST a fixture scene");
            Scene scene=setup(name);respond(exchange,200,EngineBridge.map("scenario",scene.name,"fixture",true));
        }catch(Throwable ex){respond(exchange,400,EngineBridge.map("error",ex.toString()));}
    }
    static void action(HttpExchange exchange)throws IOException{
        // Same validation/delivery method as EngineBridge.request. This facade
        // only keeps a test receipt after that production method accepts input.
        try{
            if(!exchange.getRequestMethod().equals("POST"))throw new IllegalArgumentException("POST an action");
            Scene scene=current;if(scene==null)throw new IllegalArgumentException("No fixture scene");JsonObject input=EngineBridge.readBody(exchange);
            scene.session.action(input);scene.accepted.add(EngineBridge.map("promptId",input.get("promptId"),"type",input.get("type"),"value",input.get("value")));
            respond(exchange,200,scene.session.state());
        }catch(Throwable ex){respond(exchange,400,EngineBridge.map("error",ex.toString()));}
    }
    public static void main(String[] args)throws Exception{
        Path root=Paths.get(args[0]).toAbsolutePath();int port=args.length>1?Integer.parseInt(args[1]):17464;
        if(port<17400)throw new IllegalArgumentException("Use an explicitly isolated test port");
        org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(NativeViewServer.class.getClassLoader());
        HttpServer server=HttpServer.create(new InetSocketAddress("127.0.0.1",port),16);server.createContext("/fixture/",NativeViewServer::fixture);server.createContext("/session/action",NativeViewServer::action);server.createContext("/",EngineBridge::request);server.setExecutor(Executors.newCachedThreadPool());
        Runtime.getRuntime().addShutdownHook(new Thread(()->{if(current!=null)current.session.stop();server.stop(0);},"Native GUI fixture cleanup"));server.start();
        System.out.println("Test-only native choice facade on loopback port "+port);
    }
}
