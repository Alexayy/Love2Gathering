package love2gathering;

import com.google.gson.*;
import com.sun.net.httpserver.*;
import mage.MageObject;
import mage.abilities.*;
import mage.abilities.mana.ActivatedManaAbilityImpl;
import mage.abilities.mana.ManaAbility;
import mage.cards.*;
import mage.cards.decks.Deck;
import mage.cards.decks.Constructed;
import mage.choices.Choice;
import mage.constants.*;
import mage.game.*;
import mage.game.events.*;
import mage.game.mulligan.LondonMulligan;
import mage.game.match.Match;
import mage.game.match.MatchOptions;
import mage.game.permanent.Permanent;
import mage.game.stack.StackObject;
import mage.game.stack.Spell;
import mage.target.Target;
import mage.watchers.Watcher;
import mage.player.ai.ComputerPlayer7;
import mage.player.human.HumanPlayer;
import mage.players.*;
import mage.players.net.UserData;
import mage.util.Copier;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.Collectors;

/** A loopback transport adapter. Every game mutation is performed by XMage. */
public final class EngineBridge {
    static final Gson JSON = new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
    static JsonObject cardMap;
    static volatile Session current;

    public static void main(String[] args) throws Exception {
        org.apache.log4j.BasicConfigurator.configure();
        org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        int port = args.length > 0 ? Integer.parseInt(args[0]) : 17371;
        Path base = Paths.get(System.getProperty("love2gathering.root", ".")).toAbsolutePath();
        cardMap = JsonParser.parseString(new String(Files.readAllBytes(base.resolve("bridge/card-map.json")), StandardCharsets.UTF_8)).getAsJsonObject();
        Copier.setLoader(EngineBridge.class.getClassLoader());
        String recordingPort=System.getenv("LOVE2GATHERING_CATALOG_PORT");
        if(recordingPort!=null)ReplayRecorder.recoverPending(Integer.parseInt(recordingPort));
        Runtime.getRuntime().addShutdownHook(new Thread(()->{if(current!=null)current.stop();},"Replay shutdown flush"));
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 16);
        server.createContext("/", EngineBridge::request);
        server.setExecutor(Executors.newCachedThreadPool(r -> { Thread t = new Thread(r, "bridge-http"); t.setDaemon(true); return t; }));
        server.start();
        System.out.println("Love2Gathering XMage bridge listening on http://127.0.0.1:" + port);
    }

    static void request(HttpExchange exchange) throws IOException {
        Object result;
        int status = 200;
        try {
            String path = exchange.getRequestURI().getPath();
            String method = exchange.getRequestMethod();
            if ("OPTIONS".equals(method)) { exchange.sendResponseHeaders(204, -1); return; }
            if ("/health".equals(path)) {
                result = map("ok", true, "engine", "XMage", "version", "1.4.63", "implementedCards", cardMap.size(),"recordingError",ReplayRecorder.errors());
            } else if ("/session/start".equals(path) && "POST".equals(method)) {
                JsonObject body = readBody(exchange);
                synchronized (EngineBridge.class) {
                    Session next=new Session(body);next.prepareRecording();
                    if (current != null) current.stop();
                    current = next;current.start();
                    result = current.state();
                }
            } else if ("/session/state".equals(path)) {
                result = current == null ? map("running", false, "players", Collections.emptyList(), "log", Collections.emptyList()) : current.state();
            } else if ("/session/action".equals(path) && "POST".equals(method)) {
                if (current == null) throw new IllegalArgumentException("No active game");
                current.action(readBody(exchange));
                result = current.state();
            } else if("/session/replay/save".equals(path)&&"POST".equals(method)) {
                if(current==null||current.recorder==null)throw new IllegalArgumentException("No active recorded game");
                current.recordAction(map("type","save_replay"));
                boolean saved=current.recorder.flush(5000);
                result=new LinkedHashMap<>(current.recorder.state());((Map<String,Object>)result).put("savedSequence",current.recorder.savedSequence);((Map<String,Object>)result).put("saved",saved);
                if(!saved&&current.recorder.error==null)((Map<String,Object>)result).put("recordingError","Replay is still saving; events remain buffered in SQLite");
            } else if ("/session/stop".equals(path) && "POST".equals(method)) {
                if (current != null){current.recordAction(map("type","stop"));current.stop();}
                result = current==null?map("ok",true):current.state();
            } else if ("/session/settings".equals(path) && "POST".equals(method)) {
                if (current == null) throw new IllegalArgumentException("No active game");
                JsonObject settings=readBody(exchange);current.recordAction(map("type","settings","value",settings));current.manualTriggers = bool(settings, "manualTriggers", false);
                result = map("ok", true);
            } else { status = 404; result = map("error", "Unknown endpoint"); }
        } catch (Throwable ex) {
            status = 400;
            result = map("error", ex.getMessage() == null ? ex.toString() : ex.getMessage());
            ex.printStackTrace();
        }
        byte[] bytes = JSON.toJson(result).getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        exchange.getResponseHeaders().set("Cache-Control", "no-store");
        exchange.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = exchange.getResponseBody()) { out.write(bytes); }
    }

    static JsonObject readBody(HttpExchange x) throws IOException {
        try (Reader r = new InputStreamReader(x.getRequestBody(), StandardCharsets.UTF_8)) { return JsonParser.parseReader(r).getAsJsonObject(); }
    }
    static Map<String, Object> map(Object... pairs) {
        Map<String, Object> m = new LinkedHashMap<>();
        for (int i = 0; i < pairs.length; i += 2) m.put(pairs[i].toString(), pairs[i + 1]);
        return m;
    }
    static String text(JsonObject o, String key, String fallback) { return o.has(key) && !o.get(key).isJsonNull() ? o.get(key).getAsString() : fallback; }
    static boolean bool(JsonObject o, String key, boolean fallback) { return o.has(key) && !o.get(key).isJsonNull() ? o.get(key).getAsBoolean() : fallback; }
    static String clean(String str) { return str == null ? "" : str.replaceAll("<[^>]*>", " ").replace("&nbsp;", " ").replace("&amp;", "&").trim(); }

    static Deck deck(JsonObject source) {
        return deck(source, Collections.emptyList());
    }
    static Deck deck(JsonObject source, List<String> legalSets) {
        Deck d = new Deck();
        d.setName(text(source, "name", "Deck"));
        addCards(d.getCards(), source.getAsJsonArray("main"), legalSets);
        // XMage's Commander game moves the submitted commander sideboard to command zone.
        if (source.has("commander") && !source.get("commander").isJsonNull() && source.getAsJsonArray("commander").size() > 0) addCards(d.getSideboard(), source.getAsJsonArray("commander"), legalSets);
        else addCards(d.getSideboard(), source.getAsJsonArray("sideboard"), legalSets);
        return d;
    }
    static void addCards(Set<Card> destination, JsonArray entries, List<String> legalSets) {
        if (entries == null) return;
        for (JsonElement el : entries) {
            JsonObject entry = el.isJsonPrimitive() ? new JsonObject() : el.getAsJsonObject();
            String name = el.isJsonPrimitive() ? el.getAsString() : text(entry, "name", "");
            JsonElement infoElement = cardMap.get(name.toLowerCase(Locale.ROOT));
            if (infoElement == null && name.contains(" // ")) infoElement = cardMap.get(name.split(" // ")[0].toLowerCase(Locale.ROOT));
            if (infoElement == null) throw new IllegalArgumentException("XMage has no implementation for: " + name);
            JsonObject info = infoElement.getAsJsonObject();
            String set = info.get("set").getAsString();
            String number = info.get("number").getAsString();
            String rarity = info.get("rarity").getAsString();
            JsonObject printings = info.getAsJsonObject("printings");
            if (printings != null && !legalSets.isEmpty()) for (String candidate : legalSets) if (printings.has(candidate)) {
                JsonObject printing=printings.getAsJsonObject(candidate);
                set=candidate; number=printing.get("number").getAsString(); rarity=printing.get("rarity").getAsString(); break;
            }
            int count = entry.has("count") ? entry.get("count").getAsInt() : 1;
            if (count < 1 || count > 250) throw new IllegalArgumentException("Input supports 1 to 250 copies per card: " + name);
            for (int i = 0; i < count; i++) {
                Card c = CardImpl.createCard(info.get("class").getAsString(), new CardSetInfo(info.get("name").getAsString(), set, number, Rarity.valueOf(rarity)));
                if (c == null) throw new IllegalArgumentException("Cannot instantiate XMage card: " + name);
                destination.add(c);
            }
        }
    }

    static final class Session {
        final Game game;
        final Match match;
        final BridgeHuman human;
        final Player bot;
        final AtomicLong ids = new AtomicLong();
        final Deque<Map<String,Object>> log = new ArrayDeque<>();
        final AtomicLong logIds=new AtomicLong();
        final JsonObject request;
        final int recordingPort;
        volatile ReplayRecorder recorder;
        volatile boolean stopRequested;
        final BlockingQueue<List<String>> triggerAnswers = new ArrayBlockingQueue<>(1);
        volatile Map<String, Object> snapshot = map("running", true, "status", "Starting XMage", "players", Collections.emptyList(), "log", Collections.emptyList());
        volatile Map<String, Object> prompt;
        volatile boolean running = true;
        volatile boolean manualTriggers;
        volatile String error;
        volatile String projectionError;
        Thread gameThread;

        Session(JsonObject body) {
            request=body.deepCopy();recordingPort=body.has("recordingPort")?body.get("recordingPort").getAsInt():17370;
            if(recordingPort!=0&&(recordingPort<1024||recordingPort>65535))throw new IllegalArgumentException("Invalid recording port");
            String format = text(body, "format", "Modern");
            Constructed validator;
            switch(format.toLowerCase(Locale.ROOT)) {
                case "modern": validator=new mage.deck.Modern(); break;
                case "standard": validator=new mage.deck.Standard(); break;
                case "pioneer": validator=new mage.deck.Pioneer(); break;
                case "commander": validator=new mage.deck.Commander(); break;
                default: throw new IllegalArgumentException("Choose Modern, Standard, Pioneer or Commander");
            }
            boolean commander = format.equalsIgnoreCase("Commander");
            JsonObject settings = body.has("settings") ? body.getAsJsonObject("settings") : new JsonObject();
            manualTriggers = bool(settings, "manualTriggers", false);
            human = new BridgeHuman(text(body, "playerName", "You"), this);
            UserData data = UserData.getDefaultUserDataView();
            data.setAutoOrderTrigger(false);
            data.setConfirmEmptyManaPool(false);
            data.setManaPoolAutomatic(bool(settings, "autoMana", true));
            data.setManaPoolAutomaticRestricted(false);
            human.setUserData(data);
            bot = new ComputerPlayer7(text(body, "botName", "XMage Bot"), RangeOfInfluence.ALL, 1);
            game = commander
                    ? new CommanderDuel(MultiplayerAttackOption.MULTIPLE, RangeOfInfluence.ALL, new LondonMulligan(1), 40, 7)
                    : new TwoPlayerDuel(MultiplayerAttackOption.MULTIPLE, RangeOfInfluence.ALL, new LondonMulligan(0), 60, 20, 7);
            GameOptions options = new GameOptions();
            options.rollbackTurnsAllowed = false;
            game.setGameOptions(options);
            Deck humanDeck = deck(body.getAsJsonObject("deck"),validator.getSetCodes());
            Deck aiDeck = deck(body.getAsJsonObject("botDeck"),validator.getSetCodes());
            if (!validator.validate(humanDeck)) throw new IllegalArgumentException("Your deck: "+validator.getErrorsListInfo());
            if (!validator.validate(aiDeck)) throw new IllegalArgumentException("Bot deck: "+validator.getErrorsListInfo());
            MatchOptions matchOptions=new MatchOptions("Local practice",game.getGameType().getName(),false);
            matchOptions.setDeckType(validator.getName());
            matchOptions.setWinsNeeded(1);
            matchOptions.setFreeMulligans(commander ? 1 : 0);
            match=commander ? new CommanderDuelMatch(matchOptions) : new TwoPlayerMatch(matchOptions);
            match.addPlayer(human,humanDeck);
            match.addPlayer(bot,aiDeck);
            game.setTableId(match.getId());
            human.init(game);
            bot.init(game);
            // Match the stock GameController: register concrete cards before useDeck
            // stores their IDs in the player's library and sideboard.
            game.loadCards(humanDeck.getCards(), human.getId());
            game.loadCards(humanDeck.getSideboard(), human.getId());
            game.loadCards(aiDeck.getCards(), bot.getId());
            game.loadCards(aiDeck.getSideboard(), bot.getId());
            game.addPlayer(human, humanDeck);
            game.addPlayer(bot, aiDeck);
            game.getState().addWatcher(new NativeLogWatcher(this));
            game.addPlayerQueryEventListener(this::query);
            game.addTableEventListener(event -> {
                if (event.getMessage() != null) addLog(clean(event.getMessage()),event.getPlayerId(),tableCategory(clean(event.getMessage())),null,null,"table");
                if (event.getEventType()==TableEvent.EventType.ERROR) error=event.getException()!=null ? event.getException().toString() : clean(event.getMessage());
                if(event.getEventType()==TableEvent.EventType.ERROR&&recorder!=null)recorder.event("error",map("text",error,"origin","engine"));
                if (event.getMessage()!=null && event.getMessage().toLowerCase(Locale.ROOT).contains("critical error")) error=clean(event.getMessage());
                if (event.getEventType() == TableEvent.EventType.END_GAME_INFO || event.getEventType() == TableEvent.EventType.END) running = false;
                publish();
            });
        }
        void start() {
            prepareRecording();
            gameThread = new Thread(() -> {
                try { game.start(human.getId()); }
                catch (Throwable ex) { error = ex.toString(); ex.printStackTrace(); addLog("Engine error: " + error);if(recorder!=null)recorder.event("error",map("text",error,"origin","engine")); }
                finally {
                    running = false; prompt = null; publish();
                    if(recorder!=null)recorder.finish(stopRequested?"aborted":error!=null?"failed":"completed",map("turn",game.getTurnNum(),"players",game.getPlayers().values().stream().map(p->map("id",str(p.getId()),"name",p.getName(),"life",p.getLife(),"won",p.hasWon(),"lost",p.hasLost())).collect(Collectors.toList())),error);
                }
            }, "GAME " + game.getId());
            gameThread.setDaemon(true);
            gameThread.start();
        }
        void stop() {
            if(running)stopRequested=true;
            running = false;
            if (gameThread != null) gameThread.interrupt();
            human.abort();
            if(gameThread!=null&&gameThread!=Thread.currentThread())try{gameThread.join(3000);}catch(InterruptedException ex){Thread.currentThread().interrupt();}
            if(recorder!=null){if(gameThread==null)recorder.finish("aborted",map("reason","Stopped before game start"),null);recorder.awaitFinished(5000);}
        }
        synchronized void prepareRecording() {
            if(recorder!=null||recordingPort==0)return;
            JsonObject metadata=new JsonObject();metadata.addProperty("id","game-"+game.getId());metadata.addProperty("title",human.getName()+" vs "+bot.getName());metadata.addProperty("format",text(request,"format","Modern"));metadata.addProperty("playerName",human.getName());metadata.addProperty("botName",bot.getName());metadata.addProperty("startedAt",System.currentTimeMillis());
            metadata.add("playerDeck",request.get("deck"));metadata.add("botDeck",request.get("botDeck"));metadata.add("settings",request.has("settings")?request.get("settings"):new JsonObject());metadata.add("metadata",JSON.toJsonTree(map("gameId",str(game.getId()),"players",Arrays.asList(map("id",str(human.getId()),"name",human.getName(),"human",true),map("id",str(bot.getId()),"name",bot.getName(),"human",false)),"perspective","human","engine","XMage 1.4.63")));
            recorder=ReplayRecorder.create(recordingPort,metadata);
        }
        Map<String,Object> state() {
            if(!running&&recorder!=null)recorder.awaitFinished(1200);
            Map<String,Object> result=new LinkedHashMap<>(snapshot);
            if(recorder!=null)result.putAll(recorder.state());
            return result;
        }
        void addLog(String message){addLog(message,null,tableCategory(message),null,null,"table");}
        synchronized void addLog(String message,UUID actorId,String category,UUID sourceId,String sourceName,String origin) {
            if (message.isEmpty()) return;
            message=message.replaceAll("\\s+"," ").trim();
            if(actorId==null){
                boolean h=message.startsWith(human.getName()+" ")||message.startsWith(human.getName()+"'");
                boolean b=message.startsWith(bot.getName()+" ")||message.startsWith(bot.getName()+"'");
                if(h&&!b||h&&b&&human.getName().length()>bot.getName().length())actorId=human.getId();
                else if(b&&!h||h&&b&&bot.getName().length()>human.getName().length())actorId=bot.getId();
            }
            Map<String,Object> previous=log.peekLast();if(previous!=null&&message.equals(previous.get("text"))&&Objects.equals(str(actorId),previous.get("actorId")))return;
            long sequence=logIds.incrementAndGet();Map<String,Object> entry=map("id",game.getId()+"-log-"+sequence,"sequence",sequence,"actorId",str(actorId),"actorName",actorId==null?"System":game.getPlayer(actorId)!=null?game.getPlayer(actorId).getName():"Player","actor",human.getId().equals(actorId)?"human":bot.getId().equals(actorId)?"bot":"system","category",category,"text",message,"sourceId",str(sourceId),"sourceName",sourceName,"origin",origin,"timestamp",System.currentTimeMillis());
            log.addLast(entry);
            while (log.size() > 160) log.removeFirst();
            if(recorder!=null&&!recorder.isFinished())recorder.event("log",entry);
        }
        static String tableCategory(String text) {
            String value=text.toLowerCase(Locale.ROOT);
            if(value.contains(" casts "))return "cast";if(value.contains("resolv"))return "resolve";if(value.startsWith("turn "))return "turn";if(value.contains(" draws "))return "draw";if(value.contains(" attacks "))return "attack";if(value.contains("damage")||value.contains("life"))return "damage";if(value.contains(" triggers "))return "trigger";return "system";
        }
        MageObject knownObject(UUID id) {
            if(id==null)return null;
            MageObject object=game.getObject(id);if(object==null)object=game.getCard(id);
            Card card=game.getCard(id);Zone zone=game.getState().getZone(id);
            if(card!=null&&!human.getId().equals(card.getOwnerId())&&(zone==Zone.HAND||zone==Zone.LIBRARY)) {
                boolean revealed=game.getState().getRevealed().values().stream().anyMatch(c->c.contains(id))||game.getState().getLookedAt(human.getId()).values().stream().anyMatch(c->c.contains(id));
                if(!revealed)return null;
            }
            return object;
        }
        UUID controller(MageObject source,UUID fallback) {
            if(source instanceof Controllable)return ((Controllable)source).getControllerId();
            if(source instanceof Card)return ((Card)source).getOwnerId();
            return fallback;
        }
        void nativeEvent(GameEvent event,Game context) {
            if(context!=game||context.isSimulation()||context.inCheckPlayableState())return;
            if(event.getType().isBatch())return; // Individual members were observed separately.
            UUID actor=event.getPlayerId(),sourceId=event.getSourceId();MageObject source=knownObject(sourceId);
            String sourceName=source!=null?String.valueOf(card(source).get("name")):null;
            String actorName=game.getPlayer(actor)!=null?game.getPlayer(actor).getName():"Game";
            String category,message;
            switch(event.getType()) {
                case SPELL_CAST: category="cast";message=actorName+" casts "+(sourceName!=null?sourceName:"a spell");break;
                case LAND_PLAYED:
                    category="land";sourceId=event.getTargetId();source=knownObject(sourceId);sourceName=source!=null?String.valueOf(card(source).get("name")):"a land";message=actorName+" plays "+sourceName;break;
                case DREW_CARD: category="draw";message=actorName+" draws a card";break;
                case PLAY_TURN: category="turn";message="TURN "+game.getTurnNum()+" for "+actorName;break;
                case ATTACKER_DECLARED: category="attack";message=actorName+" attacks "+visibleName(event.getTargetId())+" with "+(sourceName!=null?sourceName:"a creature");break;
                case DAMAGED_PLAYER:
                case DAMAGED_PERMANENT:
                    actor=controller(source,actor);actorName=game.getPlayer(actor)!=null?game.getPlayer(actor).getName():"Game";category="damage";message=actorName+" — "+(sourceName!=null?sourceName:"a source")+" deals "+event.getAmount()+" damage to "+visibleName(event.getTargetId());break;
                case LOST_LIFE: category="damage";message=actorName+" loses "+event.getAmount()+" life";break;
                case GAINED_LIFE: category="damage";message=actorName+" gains "+event.getAmount()+" life";break;
                case TRIGGERED_ABILITY: category="trigger";message=actorName+" — "+(sourceName!=null?sourceName:"an ability")+" triggers";break;
                case RESOLVING_ABILITY:
                    boolean mana=source!=null&&source.getAbilities().stream().anyMatch(a->a.getOriginalId().equals(event.getTargetId())&&a.isManaAbility());
                    category=mana?"mana":"resolve";message=actorName+" resolving "+(sourceName!=null?sourceName:"an ability");break;
                case MANA_ADDED: category="mana";message=actorName+" adds "+(event instanceof ManaEvent?((ManaEvent)event).getMana().toString():event.getAmount()+" mana");break;
                case ZONE_CHANGE:
                    if(!(event instanceof ZoneChangeEvent))return;
                    ZoneChangeEvent change=(ZoneChangeEvent)event;
                    if(change.getFromZone()==Zone.OUTSIDE&&change.getToZone()==Zone.LIBRARY)return;
                    MageObject target=knownObject(event.getTargetId());String targetName=target!=null?String.valueOf(card(target).get("name")):"a card";
                    category="zone";message=actorName+" — "+targetName+": "+change.getFromZone()+" → "+change.getToZone();break;
                default:return;
            }
            addLog(message,actor,category,source!=null?sourceId:null,sourceName,"game");publish();
        }
        void query(PlayerQueryEvent event) {
            if (!event.getPlayerId().equals(human.getId())) return;
            if (event.getQueryType() == PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) { addLog(clean(event.getMessage())); publish(); return; }
            Map<String, Object> p = map("id", ids.incrementAndGet(), "type", event.getQueryType().name().toLowerCase(Locale.ROOT), "message", clean(event.getMessage()), "min", event.getMin(), "max", event.getMax(), "required", event.isRequired());
            List<Map<String, Object>> choices = new ArrayList<>();
            Set<String> targets = new LinkedHashSet<>();
            if (event.getTargets() != null) for (UUID id : event.getTargets()) addObjectChoice(choices, targets, id);
            if (event.getCards() != null) for (UUID id : event.getCards()) addObjectChoice(choices, targets, id);
            if (event.getPerms() != null) for (Permanent perm : event.getPerms()) addObjectChoice(choices, targets, perm.getId());
            if (event.getAbilities() != null) {
                boolean allMana=!event.getAbilities().isEmpty() && event.getAbilities().stream().allMatch(Ability::isManaAbility);
                for (Ability a : event.getAbilities()) {
                    Map<String,Object> choice=map("id", a.getId().toString(), "sourceId", str(a.getSourceId()), "label", clean(a.getRule()), "responseType", "uuid");
                    if(a instanceof ManaAbility) choice.put("manaColors",manaColors(((ManaAbility)a).getProducableManaTypes(game)));
                    choices.add(choice);
                }
                if(allMana) p.put("manaWheel",manaWheel(event.getAbilities().get(0).getSourceId(),"ability"));
            }
            if (event.getModes() != null) event.getModes().forEach((id,label) -> choices.add(map("id", id.toString(), "label", clean(label), "responseType", "uuid")));
            // CHOOSE_ABILITY's string set carries its source object's display
            // name, not a selectable response (the actual choices are abilities).
            if (event.getChoices()!=null&&!event.getChoices().isEmpty()) p.put("objectName",clean(event.getChoices().iterator().next()));
            Choice c = event.getChoice();
            if (c != null) {
                p.put("message", clean(c.getMessage()));
                p.put("required", c.isRequired());
                if (c.isKeyChoice()) c.getKeyChoices().forEach((id,label) -> choices.add(map("id", id, "label", clean(label), "responseType", "string")));
                else for (String s : c.getChoices()) choices.add(map("id", s, "label", clean(s), "responseType", "string"));
                if(!c.isRequired()) choices.add(map("id","cancel-choice","label","Cancel","responseType","string","value",""));
                if(human.choosingManaColor && c.isManaColorChoice()) {
                    p.put("manaWheel",manaWheel(human.activeManaSource,"color"));
                    for(Map<String,Object> choice:choices) {
                        ManaType manaType=ManaType.findByName(choice.get("label").toString());
                        if(manaType!=null) choice.put("manaColors",manaColors(Collections.singleton(manaType)));
                    }
                }
            }
            if (event.getPile1() != null) {
                p.put("pile1", event.getPile1().stream().map(this::card).collect(Collectors.toList()));
                p.put("pile2", event.getPile2().stream().map(this::card).collect(Collectors.toList()));
                choices.add(map("id", "pile1", "label", "Pile 1", "responseType", "boolean", "value", true));
                choices.add(map("id", "pile2", "label", "Pile 2", "responseType", "boolean", "value", false));
            }
            if (event.getMessages() != null) {
                p.put("message", event.getOptions() != null ? clean(String.valueOf(event.getOptions().getOrDefault("header", "Distribute amounts"))) : "Distribute amounts");
                p.put("amountMessages", event.getMessages().stream().map(m -> map("message", clean(m.message), "label", clean(m.message), "min", m.min, "max", m.max, "defaultValue", m.defaultValue)).collect(Collectors.toList()));
                if(event.getOptions()!=null && Boolean.TRUE.equals(event.getOptions().get("canCancel"))) choices.add(map("id","cancel","label","Cancel","responseType","boolean","value",false));
            }
            switch (event.getQueryType()) {
                case ASK:
                    String trueLabel=event.getOptions()!=null ? String.valueOf(event.getOptions().getOrDefault("UI.left.btn.text","Yes")) : "Yes";
                    String falseLabel=event.getOptions()!=null ? String.valueOf(event.getOptions().getOrDefault("UI.right.btn.text","No")) : "No";
                    Map<String,Object> trueChoice=map("id", "yes", "label", clean(trueLabel), "responseType", "boolean", "value", true);
                    Map<String,Object> falseChoice=map("id", "no", "label", clean(falseLabel), "responseType", "boolean", "value", false);
                    choices.add(trueChoice);
                    choices.add(falseChoice);
                    if("Mulligan".equals(trueLabel) && "Keep".equals(falseLabel)) {
                        int downTo=game.mulliganDownTo(human.getId());
                        p.put("mulligan",map("keepChoice",falseChoice,"mulliganChoice",trueChoice,"downTo",downTo,"currentHandSize",human.getHand().size(),"free",downTo>=human.getHand().size()));
                    }
                    break;
                case SELECT:
                case PLAY_MANA:
                    // These are XMage's actual playable objects, rather than all
                    // visible cards. Timing, costs, mana and land limits stay in XMage.
                    for(UUID id:actionableObjects(event)) addObjectChoice(choices,targets,id);
                    choices.add(map("id", "done", "label", event.getQueryType() == PlayerQueryEvent.QueryType.PLAY_MANA ? "Cancel payment" : "Pass / Done", "responseType", "boolean", "value", true));
                    if (event.getQueryType() == PlayerQueryEvent.QueryType.PLAY_MANA) {
                        ManaPool pool = human.getManaPool();
                        String[] types = {"WHITE", "BLUE", "BLACK", "RED", "GREEN", "COLORLESS"};
                        String[] symbols = {"W", "U", "B", "R", "G", "C"};
                        int[] counts = {pool.getWhite(),pool.getBlue(),pool.getBlack(),pool.getRed(),pool.getGreen(),pool.getColorless()};
                        for (int i=0;i<types.length;i++) if (counts[i]>0) choices.add(map("id","mana-"+symbols[i],"label","Pay {"+symbols[i]+"} from pool ("+counts[i]+")","responseType","mana","value",types[i]));
                    }
                    if (event.getOptions() != null && event.getOptions().containsKey("specialButton")) choices.add(map("id", "special", "label", clean(event.getOptions().get("specialButton").toString()), "responseType", "string"));
                    else if(!game.getState().getSpecialActions().getControlledBy(human.getId(),event.getQueryType()==PlayerQueryEvent.QueryType.PLAY_MANA).isEmpty()) choices.add(map("id","special","label","Special action (delve / convoke / other)","responseType","string"));
                    break;
                default: break;
            }
            if (!event.isRequired() && event.getQueryType() == PlayerQueryEvent.QueryType.PICK_TARGET) choices.add(map("id", "done", "label", "Done / Cancel", "responseType", "boolean", "value", false));
            p.put("choices", choices);
            p.put("targets", targets);
            p.put("actionable",new ArrayList<>(targets));
            p.put("options", safeOptions(event.getOptions()));
            prompt = p;
            publish();
        }
        Set<UUID> actionableObjects(PlayerQueryEvent event) {
            Set<UUID> ids=new LinkedHashSet<>();
            Map<String,Serializable> options=event.getOptions();
            if(event.getQueryType()==PlayerQueryEvent.QueryType.SELECT) {
                if(options!=null && options.containsKey("possibleAttackers")) {
                    addIds(ids,options.get("possibleAttackers"));
                    ids.addAll(game.getCombat().getAttackers());
                } else if(options!=null && options.containsKey("possibleBlockers")) {
                    addIds(ids,options.get("possibleBlockers"));
                    ids.addAll(game.getCombat().getBlockers());
                } else if(human.getId().equals(game.getPriorityPlayerId())) {
                    ids.addAll(human.getPlayableObjects(game,Zone.ALL).getObjects().keySet());
                }
            } else if(event.getQueryType()==PlayerQueryEvent.QueryType.PLAY_MANA) {
                List<MageObject> visible=new ArrayList<>();
                visible.addAll(human.getHand().getCards(game));
                visible.addAll(game.getBattlefield().getAllActivePermanents());
                visible.addAll(human.getGraveyard().getCards(game));
                visible.addAll(game.getExile().getAllCards(game));
                visible.addAll(game.getCommanderCardsFromCommandZone(human,CommanderCardType.ANY));
                for(MageObject object:visible) if(!human.usableManaAbilities(object,game).isEmpty()) ids.add(object.getId());
            }
            return ids;
        }
        void addIds(Set<UUID> ids,Object input) {
            if(input instanceof Collection<?>) for(Object id:(Collection<?>)input) if(id instanceof UUID) ids.add((UUID)id);
        }
        Map<String,Object> manaWheel(UUID sourceId,String kind) {
            MageObject source=sourceId!=null ? game.getObject(sourceId) : null;
            return map("sourceId",str(sourceId),"sourceName",source!=null ? source.getName() : "Mana","kind",kind);
        }
        List<String> manaColors(Set<ManaType> types) {
            List<String> colors=new ArrayList<>();
            ManaType[] order={ManaType.WHITE,ManaType.BLUE,ManaType.BLACK,ManaType.RED,ManaType.GREEN,ManaType.COLORLESS};
            String[] symbols={"W","U","B","R","G","C"};
            for(int i=0;i<order.length;i++) if(types.contains(order[i])) colors.add(symbols[i]);
            return colors;
        }
        Map<String, Object> safeOptions(Map<String, ? extends Object> options) {
            Map<String, Object> out = new LinkedHashMap<>();
            if (options != null) options.forEach((k,v) -> { if (v instanceof String || v instanceof Number || v instanceof Boolean) out.put(k,v); });
            return out;
        }
        void addObjectChoice(List<Map<String, Object>> choices, Set<String> targets, UUID id) {
            if (!targets.add(id.toString())) return;
            MageObject object = game.getObject(id);
            Player p = game.getPlayer(id);
            Map<String,Object> view=object!=null ? card(object) : null;
            choices.add(map("id", id.toString(), "label", view != null ? view.get("name") : p != null ? p.getName() : id.toString(), "responseType", "uuid", "card", view));
        }
        void action(JsonObject action) throws Exception {
            recordAction(action.deepCopy());
            Map<String, Object> p = prompt;
            String type = text(action, "type", "");
            if ("concede".equals(type)) { human.signalPlayerConcede(true); return; }
            if (p == null) throw new IllegalArgumentException("XMage is not waiting for a choice");
            if (!action.has("promptId") || action.get("promptId").getAsLong() != ((Number)p.get("id")).longValue()) throw new IllegalArgumentException("This choice is outdated; refresh the game");
            JsonElement value = action.get("value");
            if (value == null) throw new IllegalArgumentException("Missing answer value");
            if ("order".equals(type)) {
                if (!"order".equals(p.get("type"))) throw new IllegalArgumentException("Not a trigger ordering prompt");
                List<String> order = new ArrayList<>();
                for (JsonElement e : value.getAsJsonArray()) order.add(e.getAsString());
                @SuppressWarnings("unchecked") List<Map<String,Object>> choices = (List<Map<String,Object>>)p.get("choices");
                Set<String> required = choices.stream().map(x -> x.get("id").toString()).collect(Collectors.toSet());
                if (order.size() != required.size() || !new HashSet<>(order).equals(required)) throw new IllegalArgumentException("Include every trigger once");
                prompt = null;
                triggerAnswers.offer(order);
                return;
            }
            // Prompt ID prevents double-clicks from spilling into the next engine question.
            prompt = null;
            try { switch (type) {
                case "uuid": human.setResponseUUID(UUID.fromString(value.getAsString())); break;
                case "boolean": human.setResponseBoolean(value.getAsBoolean()); break;
                case "integer": human.setResponseInteger(value.getAsInt()); break;
                case "string": human.setResponseString(value.getAsString()); break;
                case "multi_amount": {
                    if (!"multi_amount".equals(p.get("type"))) throw new IllegalArgumentException("Not an amount distribution prompt");
                    List<Integer> amounts = new ArrayList<>();
                    for (JsonElement v : value.getAsJsonArray()) amounts.add(v.getAsInt());
                    @SuppressWarnings("unchecked") List<Map<String,Object>> limits=(List<Map<String,Object>>)p.get("amountMessages");
                    if (limits==null || amounts.size()!=limits.size()) throw new IllegalArgumentException("Answer every amount");
                    long total=0;
                    for(int i=0;i<amounts.size();i++) {
                        int n=amounts.get(i); Map<String,Object> limit=limits.get(i);
                        if(n<((Number)limit.get("min")).intValue() || n>((Number)limit.get("max")).intValue()) throw new IllegalArgumentException("Amount outside allowed range");
                        total+=n;
                    }
                    if(total<((Number)p.get("min")).intValue() || total>((Number)p.get("max")).intValue()) throw new IllegalArgumentException("Amount total outside allowed range");
                    human.setResponseString(amounts.stream().map(Object::toString).collect(Collectors.joining(" ")));
                    break;
                }
                case "mana": human.setResponseManaType(human.getId(), ManaType.valueOf(value.getAsString().toUpperCase(Locale.ROOT))); break;
                default: prompt = p; throw new IllegalArgumentException("Unknown response type: " + type);
            } } catch (RuntimeException ex) { if(prompt==null) prompt=p; throw ex; }
        }
        void recordAction(Object input){if(recorder!=null&&!recorder.isFinished())recorder.event("action",map("actorId",str(human.getId()),"actor","human","input",input,"promptId",prompt!=null?prompt.get("id"):null));}
        synchronized void publish() {
            try {
                List<Map<String, Object>> players = new ArrayList<>();
                for (Player p : game.getPlayers().values()) {
                    List<Map<String,Object>> battlefield = new ArrayList<>();
                    for (Permanent permanent : game.getBattlefield().getAllActivePermanents()) if (p.getId().equals(permanent.getControllerId())) battlefield.add(card(permanent));
                    ManaPool mana = p.getManaPool();
                    players.add(map("id", p.getId().toString(), "name", p.getName(), "human", p.getId().equals(human.getId()), "life", p.getLife(), "hand", p.getId().equals(human.getId()) ? cards(p.getHand().getCards(game)) : Collections.emptyList(), "handCount", p.getHand().size(), "libraryCount", p.getLibrary().size(), "sideboardCount",p.getSideboard().size(), "graveyard", cards(p.getGraveyard().getCards(game)), "battlefield", battlefield, "command", cards(game.getCommanderCardsFromCommandZone(p, CommanderCardType.ANY)), "exile",cards(game.getExile().getAllCards(game).stream().filter(c -> p.getId().equals(c.getOwnerId())).collect(Collectors.toList())),"mana", map("W",mana.getWhite(),"U",mana.getBlue(),"B",mana.getBlack(),"R",mana.getRed(),"G",mana.getGreen(),"C",mana.getColorless()), "won",p.hasWon(),"lost",p.hasLost()));
                }
                List<Map<String,Object>> stack = new ArrayList<>();
                int stackIndex=0;for (StackObject o : game.getStack()) {Map<String,Object> view=stackCard(o);view.put("stackIndex",stackIndex);view.put("isTop",stackIndex++==0);stack.add(view);}
                List<Map<String,Object>> exiled = cards(game.getExile().getAllCards(game));
                List<Map<String,Object>> revealed=new ArrayList<>(),lookedAt=new ArrayList<>();
                game.getState().getRevealed().forEach((label,list)->revealed.add(map("label",clean(label),"cards",cards(list.getCards(game)))));
                if(game.getState().getLookedAt(human.getId())!=null) game.getState().getLookedAt(human.getId()).forEach((label,list)->lookedAt.add(map("label",clean(label),"cards",cards(list.getCards(game)))));
                snapshot = map("running", running, "error", error, "revision", ids.incrementAndGet(), "gameId", game.getId().toString(), "turn", game.getTurnNum(), "phase", game.getTurn() != null && game.getTurn().getPhase() != null ? String.valueOf(game.getTurn().getPhase().getType()) : "", "step", String.valueOf(game.getTurnStepType()), "activePlayerId", str(game.getActivePlayerId()), "priorityPlayerId", str(game.getPriorityPlayerId()), "players", players, "stack", stack, "exile", exiled,"revealed",revealed,"lookedAt",lookedAt, "prompt", prompt, "log", new ArrayList<>(log), "manualTriggers", manualTriggers);
                snapshot.put("logEntries",new ArrayList<>(log));snapshot.put("logText",log.stream().map(e->e.get("text")).collect(Collectors.toList()));
                snapshot.put("projectionError",projectionError);
                if(recorder!=null){snapshot.putAll(recorder.state());if(!recorder.isFinished())recorder.event("frame",snapshot);}
            } catch (RuntimeException ex) {
                // Snapshots are generated only from game callbacks. A transient setup
                // callback can precede initialization of the turn; the next replaces it.
                if (error != null) snapshot = map("running",false,"error",error,"log",new ArrayList<>(log));
            }
        }
        static String str(UUID id) { return id == null ? null : id.toString(); }
        Map<String,Object> stackCard(StackObject object) {
            Map<String,Object> view=card(object);MageObject source=game.getObject(object.getSourceId());
            if(source==null)source=game.getCard(object.getSourceId());
            if(source==null)source=game.getLastKnownInformation(object.getSourceId(),Zone.BATTLEFIELD);
            Map<String,Object> sourceView=source!=null?card(source):null;
            String name=sourceView!=null?String.valueOf(sourceView.get("name")):object.getName();
            String rule=clean(object.getStackAbility().getRule());
            if(rule.isEmpty()&&sourceView!=null)rule=String.valueOf(sourceView.get("rules"));
            if(rule.isEmpty())rule=String.valueOf(view.get("type"));
            view.put("sourceCard",sourceView);view.put("sourceName",name);view.put("artName",name);view.put("controllerId",str(object.getControllerId()));view.put("kind",object instanceof Spell?"spell":"ability");view.put("rules",rule);
            if(!(object instanceof Spell))view.put("name",name+" — ability");
            List<Map<String,Object>> targets=new ArrayList<>();Set<UUID> seen=new HashSet<>();
            for(Target target:object.getStackAbility().getTargets())for(UUID id:target.getTargets())if(seen.add(id))targets.add(map("id",str(id),"name",visibleName(id)));
            view.put("targets",targets);return view;
        }
        String visibleName(UUID id){Player player=game.getPlayer(id);if(player!=null)return player.getName();MageObject object=knownObject(id);return object==null?"Hidden card":String.valueOf(card(object).get("name"));}
        List<Map<String,Object>> cards(Collection<? extends MageObject> cards) { return cards.stream().map(this::card).collect(Collectors.toList()); }
        Map<String,Object> card(MageObject c) {
            if(c instanceof Card && ((Card)c).isFaceDown(game) && !human.getId().equals(((Card)c).getOwnerId())) return map("id",c.getId().toString(),"name","Face-down card","faceDown",true,"manaCost","","type","","rules","","power","","toughness","");
            Map<String,Object> m = map("id",c.getId().toString(),"name",c.getName(),"manaCost",c.getManaCost().getText(),"type",c.getCardType(game).toString(),"rules",c.getAbilities().stream().map(a -> clean(a.getRule())).filter(s -> !s.isEmpty()).distinct().collect(Collectors.joining("\n")),"power",c.getPower().toString(),"toughness",c.getToughness().toString(),"set",c.getExpansionSetCode(),"number",c.getCardNumber());
            if(c instanceof Card) { Map<String,Object> counters=new LinkedHashMap<>(); ((Card)c).getCounters(game).forEach((name,counter)->counters.put(name,counter.getCount())); m.put("counters",counters); }
            if (c instanceof Permanent) { Permanent p = (Permanent)c; m.put("tapped",p.isTapped()); m.put("damage",p.getDamage()); m.put("attacking",p.isAttacking()); m.put("controllerId",str(p.getControllerId())); }
            if (c instanceof StackObject) m.put("sourceId",str(((StackObject)c).getSourceId()));
            return m;
        }
        TriggeredAbility orderTriggers(List<TriggeredAbility> abilities, Game context) {
            if (!manualTriggers || context.isSimulation() || context.inCheckPlayableState() || abilities.size() < 2) return abilities.get(0);
            // queued IDs are stored on the shared session, surviving XMage bookmarks.
            synchronized (human.triggerOrder) {
                while (!human.triggerOrder.isEmpty()) {
                    UUID id = human.triggerOrder.removeFirst();
                    for (TriggeredAbility a : abilities) if (a.getId().equals(id)) return a;
                }
            }
            List<Map<String,Object>> choices = new ArrayList<>();
            for (TriggeredAbility a : abilities) choices.add(map("id",a.getId().toString(),"sourceId",str(a.getSourceId()),"label",clean(a.getRule()),"responseType","uuid"));
            prompt = map("id", ids.incrementAndGet(), "type", "order", "message", "Drag triggers left to right: resolves first → resolves last", "choices", choices,"targets",Collections.emptyList(),"required",true);
            publish();
            try {
                List<String> chosen = triggerAnswers.take();
                Collections.reverse(chosen); // bottom of stack is placed first
                synchronized (human.triggerOrder) { for (String id : chosen) human.triggerOrder.add(UUID.fromString(id)); }
                return orderTriggers(abilities, context);
            } catch (InterruptedException ex) { Thread.currentThread().interrupt(); return abilities.get(0); }
        }
    }

    static final class NativeLogWatcher extends Watcher {
        final transient Session session;
        NativeLogWatcher(Session session){super(WatcherScope.GAME);this.session=session;}
        @Override public void watch(GameEvent event,Game game){if(session!=null)try{session.nativeEvent(event,game);}catch(RuntimeException ex){session.projectionError="Game log projection: "+ex;System.err.println(session.projectionError);}}
        @Override public NativeLogWatcher copy(){return new NativeLogWatcher(session);}
    }

    static final class BridgeHuman extends HumanPlayer {
        final transient Session session;
        final transient Deque<UUID> triggerOrder;
        transient UUID activeManaSource;
        transient boolean choosingManaColor;
        BridgeHuman(String name, Session session) { super(name,RangeOfInfluence.ALL,1); this.session=session; this.triggerOrder=new ArrayDeque<>(); }
        BridgeHuman(BridgeHuman original) { super(original); session=original.session; triggerOrder=original.triggerOrder; }
        @Override public BridgeHuman copy() { return new BridgeHuman(this); }
        @Override public TriggeredAbility chooseTriggeredAbility(List<TriggeredAbility> abilities, Game game) { return session == null ? abilities.get(0) : session.orderTriggers(abilities, game); }
        Map<UUID,ActivatedManaAbilityImpl> usableManaAbilities(MageObject object,Game game) {
            Zone zone=game.getState().getZone(object.getId());
            return zone==null ? Collections.emptyMap() : getUseableManaAbilities(object,zone,game);
        }
        @Override public boolean activateAbility(ActivatedAbility ability,Game game) {
            UUID previous=activeManaSource;
            if(ability.isManaAbility()) activeManaSource=ability.getSourceId();
            try { return super.activateAbility(ability,game); }
            finally { activeManaSource=previous; }
        }
        @Override public boolean choose(Outcome outcome,Choice choice,Game game) {
            boolean previous=choosingManaColor;
            choosingManaColor=outcome==Outcome.PutManaInPool;
            try { return super.choose(outcome,choice,game); }
            finally { choosingManaColor=previous; }
        }
    }
}
