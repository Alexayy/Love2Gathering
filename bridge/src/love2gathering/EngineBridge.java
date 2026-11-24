package love2gathering;

import com.google.gson.*;
import com.sun.net.httpserver.*;
import mage.MageObject;
import mage.ApprovingObject;
import mage.abilities.*;
import mage.abilities.costs.mana.ManaCost;
import mage.abilities.mana.ActivatedManaAbilityImpl;
import mage.abilities.mana.ManaAbility;
import mage.cards.*;
import mage.cards.decks.Deck;
import mage.cards.decks.Constructed;
import mage.cards.decks.DeckValidator;
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
import mage.players.net.SkipPrioritySteps;
import mage.util.Copier;
import mage.util.CardUtil;
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
    static final String INSTANCE_ID=UUID.randomUUID().toString();

    public static void main(String[] args) throws Exception {
        org.apache.log4j.BasicConfigurator.configure();
        org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        int port = args.length > 0 ? Integer.parseInt(args[0]) : 17371;
        Path base = Paths.get(System.getProperty("love2gathering.root", ".")).toAbsolutePath();
        cardMap = JsonParser.parseString(new String(Files.readAllBytes(base.resolve("bridge/card-map.json")), StandardCharsets.UTF_8)).getAsJsonObject();
        Copier.setLoader(EngineBridge.class.getClassLoader());
        String recordingPort=System.getenv("LOVE2GATHERING_CATALOG_PORT");
        if(recordingPort!=null)ReplayRecorder.recoverPending(Integer.parseInt(recordingPort));
        Runtime.getRuntime().addShutdownHook(new Thread(()->{if(current!=null)current.stop(); MultiplayerBridge.stopAll();},"Replay shutdown flush"));
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
            if (path.startsWith("/multiplayer/") || path.startsWith("/draft/")) {
                result = MultiplayerBridge.request(exchange, path, method);
            } else if ("/health".equals(path)) {
                result = map("ok", true, "engine", "XMage", "version", "1.4.63", "implementedCards", cardMap.size(),"recordingError",ReplayRecorder.errors(),"storageRelocationProtocol",1,"instanceId",INSTANCE_ID,"engineRevision",NativeCapabilities.ENGINE_REVISION);
            } else if("/capabilities/cards".equals(path)&&"GET".equals(method)){
                result=NativeCapabilities.cards();
            } else if("/capabilities".equals(path)&&"GET".equals(method)){
                result=MultiplayerBridge.capabilities();
            } else if ("/session/start".equals(path) && "POST".equals(method)) {
                JsonObject body = readBody(exchange);
                synchronized (EngineBridge.class) {
                    Session next=new Session(body);
                    if (current != null) {
                        current.stop();
                        if(current.executionAlive())throw new IllegalStateException("The previous GAME thread is still stopping; a new match was not started");
                    }
                    next.prepareRecording();
                    current = next;current.start();
                    result = current.state();
                }
            } else if ("/session/state".equals(path)) {
                Session session=current;
                result = session == null ? map("running", false, "players", Collections.emptyList(), "log", Collections.emptyList()) : session.state();
            } else if ("/session/action".equals(path) && "POST".equals(method)) {
                JsonObject body=readBody(exchange);Session session=expectedSession(body);
                session.action(body);
                result = session.state();
            } else if ("/session/priority".equals(path) && "POST".equals(method)) {
                JsonObject body=readBody(exchange);Session session=expectedSession(body);
                session.priorityCommand(body);
                result = session.state();
            } else if("/session/replay/save".equals(path)&&"POST".equals(method)) {
                Session session=expectedSession(readBody(exchange));
                if(session.recorder==null)throw new IllegalArgumentException("No active recorded game");
                session.recordAction(map("type","save_replay"));
                boolean saved=session.recorder.flush(5000);
                result=new LinkedHashMap<>(session.recorder.state());((Map<String,Object>)result).put("savedSequence",session.recorder.savedSequence);((Map<String,Object>)result).put("saved",saved);
                if(!saved&&session.recorder.error==null)((Map<String,Object>)result).put("recordingError","Replay is still saving; events remain buffered in SQLite");
            } else if ("/session/stop".equals(path) && "POST".equals(method)) {
                JsonObject body=readBody(exchange);Session session=current;
                if(session!=null){session=expectedSession(body);session.recordAction(map("type","stop"));session.stop();}
                else if(body.has("expectedGameId"))throw new IllegalArgumentException("This game is no longer active");
                result = session==null?map("ok",true):session.state();
            } else if ("/session/settings".equals(path) && "POST".equals(method)) {
                JsonObject settings=readBody(exchange);Session session=expectedSession(settings);session.recordAction(map("type","settings","value",settings));session.manualTriggers = bool(settings, "manualTriggers", false);
                result = map("ok", true);
            } else { status = 404; result = map("error", "Unknown endpoint"); }
        } catch (Throwable ex) {
            status = ex instanceof SecurityException ? 403 : 400;
            result = map("error", ex.getMessage() == null ? ex.toString() : ex.getMessage());
            ex.printStackTrace();
        }
        byte[] bytes = JSON.toJson(result).getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        exchange.getResponseHeaders().set("Cache-Control", "no-store");
        exchange.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = exchange.getResponseBody()) { out.write(bytes); }
    }

    static Session expectedSession(JsonObject body) {
        Session session=current;
        if(session==null)throw new IllegalArgumentException("No active game");
        if(body.has("expectedGameId")&&!session.game.getId().toString().equals(text(body,"expectedGameId","")))
            throw new IllegalArgumentException("This game is outdated; refresh the current match");
        return session;
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
        Player bot; // First opponent retained for deterministic duel fixtures.
        final Session owner;
        final boolean room;
        final String roomSeatId;
        final List<Session> perspectives;
        final List<Player> seatPlayers;
        final List<RoomSeat> seatConfigs;
        final Map<UUID,Session> humans;
        final List<Player> bots = new ArrayList<>();
        final List<JsonObject> botSources = new ArrayList<>();
        final String format;
        final PriorityController priority = new PriorityController();
        final PromptContext promptContext = new PromptContext(this);
        final Deque<Map<String,Object>> animationEvents = new ArrayDeque<>();
        Map<String,Object> openingRoll;
        final Map<UUID,Map<String,Object>> botPlaymats = new HashMap<>();
        final Map<UUID,UUID> tokenSources = new HashMap<>();
        final Deque<Map<String,Object>> rememberedLookedAt = new ArrayDeque<>();
        final Map<String,Cards> lookedAtReferences = new LinkedHashMap<>();
        final Map<UUID,UUID> libraryTopLooks=new HashMap<>(); // current native look generation, never look history
        volatile long decisionStartedAt, priorityStartedAt;
        volatile UUID decisionPlayerId, timedPriorityPlayerId;
        // A selected block is provisional until XMage validates the complete
        // declaration and emits DECLARED_BLOCKERS for that defending player.
        final Set<UUID> confirmedBlockerDefenders = new HashSet<>();
        Object confirmedBlockersPhase;
        int nativePriorityDepth;
        final AtomicLong ids;
        final Deque<Map<String,Object>> log = new ArrayDeque<>();
        final AtomicLong logIds=new AtomicLong();
        final JsonObject request;
        final int recordingPort;
        volatile ReplayRecorder recorder;
        volatile boolean stopRequested;
        volatile boolean practiceConcedeRequested, practiceConcedeProcessed, practiceConcedeEnded;
        final Set<UUID> publishedDepartures=new HashSet<>(); // GAME only
        final BlockingQueue<List<String>> triggerAnswers = new ArrayBlockingQueue<>(1);
        final Queue<UUID> pendingConcedes = new ConcurrentLinkedQueue<>();
        final Object answerLock=new Object();
        final NativeInputQueue inputQueue=new NativeInputQueue(this);
        volatile long nativePromptId;
        volatile Map<String, Object> snapshot = map("running", true, "status", "Starting XMage", "players", Collections.emptyList(), "log", Collections.emptyList());
        volatile Map<String, Object> prompt;
        volatile Integer undoBookmark;
        volatile boolean running = true;
        volatile boolean manualTriggers;
        volatile String error;
        volatile String projectionError;
        volatile Thread gameThread;

        Session(JsonObject body) { this(body, false); }
        Session(JsonObject body, boolean room) {
            this.owner = this; this.room = room; request = body.deepCopy();
            ids = new AtomicLong(); perspectives = new ArrayList<>(); seatPlayers = new ArrayList<>();
            seatConfigs = new ArrayList<>(); humans = new LinkedHashMap<>();
            format = text(body, "format", "Modern");
            if (room) {
                if (!body.has("seats") || !body.get("seats").isJsonArray()) throw new IllegalArgumentException("Room seats are required");
                JsonArray submitted = body.getAsJsonArray("seats");
                if (submitted.size() < 2 || submitted.size() > 10) throw new IllegalArgumentException("Choose 2 to 10 room seats");
                Set<String> seen = new HashSet<>();
                for (int i = 0; i < submitted.size(); i++) {
                    RoomSeat seat = new RoomSeat(submitted.get(i).getAsJsonObject(), i);
                    if (!seen.add(seat.seatId)) throw new IllegalArgumentException("Duplicate room seat ID");
                    seatConfigs.add(seat);
                }
            } else {
                JsonObject primary = new JsonObject(); primary.addProperty("seatId", "local"); primary.addProperty("type", "human");
                primary.addProperty("name", text(body, "playerName", "You")); primary.add("deck", body.get("deck"));
                if (body.has("settings")) primary.add("settings", body.get("settings"));
                if (body.has("priority")) primary.add("priority", body.get("priority"));
                if (body.has("profile")) primary.add("profile",body.get("profile"));
                seatConfigs.add(new RoomSeat(primary, 0));
                JsonArray submitted = new JsonArray();
                if (body.has("bots")) {
                    if (!body.get("bots").isJsonArray()) throw new IllegalArgumentException("bots must be an array");
                    submitted = body.getAsJsonArray("bots");
                    if (submitted.size() < 1 || submitted.size() > 5) throw new IllegalArgumentException("Choose 1 to 5 bots");
                } else {
                    JsonObject bot = new JsonObject(); bot.addProperty("name", text(body, "botName", "XMage Bot")); bot.add("deck", body.get("botDeck")); submitted.add(bot);
                }
                for (int i = 0; i < submitted.size(); i++) {
                    JsonObject bot = submitted.get(i).getAsJsonObject().deepCopy();
                    if (!bot.has("deck") || !bot.get("deck").isJsonObject()) throw new IllegalArgumentException("Every bot needs a deck");
                    if (!bot.has("name")) bot.addProperty("name", submitted.size() == 1 ? "XMage Bot" : "XMage Bot " + (i + 1));
                    bot.addProperty("type", "bot"); bot.addProperty("seatId", "bot-" + (i + 1)); seatConfigs.add(new RoomSeat(bot, i + 1));
                }
            }
            RoomSeat primary = seatConfigs.stream().filter(seat -> seat.human).findFirst().orElse(null);
            boolean observer = primary == null;
            if (observer) {
                JsonObject config = new JsonObject(); config.addProperty("seatId", "observer"); config.addProperty("name", "Public observer");
                primary = new RoomSeat(config, -1);
            }
            roomSeatId = primary.seatId;
            recordingPort = recordingPort(body, room, primary.seatId);
            DeckValidator validator=NativeCapabilities.validator(format);
            boolean commander = format.equalsIgnoreCase("Commander"), limited = format.equalsIgnoreCase("Limited");
            int count = seatConfigs.size();
            if (count > 2 && !commander && !limited) throw new IllegalArgumentException(room ? "More than two players require Commander or Limited" : "Multiple bots require Commander");
            PresentationGames.Lifecycle lifecycle=new PresentationGames.Lifecycle(this::afterNativeConcede,()->practiceConcedeEnded,this::beforeNativeEffects,this::beforeNativeEvent);
            if (commander && count > 2) {
                CommanderFreeForAll multiplayer = new PresentationGames.Multiplayer(MultiplayerAttackOption.MULTIPLE, RangeOfInfluence.ALL, new LondonMulligan(1), 40, 7, this::spellResolved,lifecycle);
                multiplayer.setNumPlayers(count); game = multiplayer;
            } else if (limited && count > 2) game = new LimitedFreeForAll(count, new LondonMulligan(1), this::spellResolved,lifecycle);
            else game = commander ? new PresentationGames.Commander(MultiplayerAttackOption.MULTIPLE, RangeOfInfluence.ALL, new LondonMulligan(1), 40, 7, this::spellResolved,lifecycle)
                    : new PresentationGames.Duel(MultiplayerAttackOption.MULTIPLE, RangeOfInfluence.ALL, new LondonMulligan(0), validator.getDeckMinSize(), 20, 7, this::spellResolved,lifecycle);
            GameOptions options = new GameOptions(); options.rollbackTurnsAllowed = false; game.setGameOptions(options);
            if(body.has("commanderDamage")&&(!body.get("commanderDamage").isJsonPrimitive()||!body.getAsJsonPrimitive("commanderDamage").isBoolean()))throw new IllegalArgumentException("Commander damage must be true or false");
            if(game instanceof GameCommanderImpl)((GameCommanderImpl)game).setCheckCommanderDamage(!body.has("commanderDamage")||body.get("commanderDamage").getAsBoolean());
            MatchOptions matchOptions = new MatchOptions(room ? "Room match" : "Local practice", game.getGameType().getName(), false);
            matchOptions.setDeckType(validator.getName()); matchOptions.setWinsNeeded(1); matchOptions.setFreeMulligans(commander || count > 2 ? 1 : 0);
            match = commander ? count > 2 ? new CommanderFreeForAllMatch(matchOptions) : new CommanderDuelMatch(matchOptions)
                    : count > 2 ? new FreeForAllMatch(matchOptions) : new TwoPlayerMatch(matchOptions);
            human = new BridgeHuman(primary.name, this); configureHuman(primary);
            perspectives.add(this); if (!observer) humans.put(human.getId(), this);
            Map<String,Deck> decks = new LinkedHashMap<>();
            List<String> legalSets = validator instanceof Constructed ? ((Constructed)validator).getSetCodes() : Collections.emptyList();
            for (int i = 0; i < seatConfigs.size(); i++) {
                RoomSeat seat = seatConfigs.get(i);
                Deck selected = deck(seat.deck, legalSets);
                if (!validator.validate(selected)) {
                    String label = room ? seat.name + " deck: " : i == 0 ? "Your deck: " : "Bot " + i + " deck: ";
                    throw new IllegalArgumentException(label + validator.getErrorsListInfo());
                }
                decks.put(seat.seatId, selected);
            }
            for (RoomSeat seat : seatConfigs) {
                Player player;
                if (seat == primary) player = human;
                else if (seat.human) {
                    Session perspective = new Session(this, seat); perspectives.add(perspective); humans.put(perspective.human.getId(), perspective); player = perspective.human;
                } else {
                    player = new ComputerPlayer7(seat.name, RangeOfInfluence.ALL, 1); bots.add(player);
                    JsonObject source = new JsonObject(); source.addProperty("name", seat.name); source.add("deck", seat.deck); botSources.add(source);
                }
                seatPlayers.add(player); match.addPlayer(player, decks.get(seat.seatId));
            }
            game.setTableId(match.getId());
            for (int i = 0; i < seatPlayers.size(); i++) registerPlayer(seatPlayers.get(i), decks.get(seatConfigs.get(i).seatId));
            openingRoll=StartingOrder.choose(participants(),text(body,"startingSeatId","dice"),room);
            game.setStartingPlayerId(UUID.fromString(String.valueOf(openingRoll.get("winnerId"))));
            chooseBotPlaymats(decks);
            for (Session perspective : perspectives) {
                if (perspective != this) { perspective.bots.addAll(bots); perspective.botSources.addAll(botSources); }
                perspective.bot = seatPlayers.stream().filter(player -> !player.getId().equals(perspective.human.getId())).findFirst().orElse(null);
            }
            game.getState().addWatcher(new CommanderHistoryWatcher());
            game.getState().addWatcher(new NativeLogWatcher(this));
            game.addPlayerQueryEventListener(event -> { Session perspective = humans.get(event.getPlayerId()); if (perspective != null) perspective.query(event); });
            game.addTableEventListener(event -> {
                for (Session perspective : perspectives) {
                    if (event.getMessage() != null) perspective.addLog(clean(event.getMessage()), event.getPlayerId(), tableCategory(clean(event.getMessage())), null, null, "table");
                    if (event.getEventType() == TableEvent.EventType.ERROR) perspective.error = event.getException() != null ? event.getException().toString() : clean(event.getMessage());
                    if (event.getEventType() == TableEvent.EventType.ERROR && perspective.recorder != null) perspective.recorder.event("error", map("text", perspective.error, "origin", "engine"));
                    if (event.getMessage() != null && event.getMessage().toLowerCase(Locale.ROOT).contains("critical error")) perspective.error = clean(event.getMessage());
                    if (event.getEventType() == TableEvent.EventType.END_GAME_INFO || event.getEventType() == TableEvent.EventType.END) perspective.running = false;
                    perspective.publish();
                }
            });
        }
        Session(Session owner, RoomSeat seat) {
            this.owner = owner; room = true; roomSeatId = seat.seatId; game = owner.game; match = owner.match;
            request = owner.request; format = owner.format; ids = owner.ids;
            perspectives = owner.perspectives; seatPlayers = owner.seatPlayers; seatConfigs = owner.seatConfigs; humans = owner.humans;
            recordingPort = recordingPort(request, true, seat.seatId);
            human = new BridgeHuman(seat.name, this); configureHuman(seat);
        }
        static int recordingPort(JsonObject body, boolean room, String seatId) {
            if (room && !seatId.equals(text(body, "recordingSeatId", ""))) return 0;
            int port = body.has("recordingPort") ? body.get("recordingPort").getAsInt() : room ? 0 : 17370;
            if (port != 0 && (port < 1024 || port > 65535)) throw new IllegalArgumentException("Invalid recording port");
            return port;
        }
        void configureHuman(RoomSeat seat) {
            manualTriggers = bool(seat.settings, "manualTriggers", false); if (!seat.priority.entrySet().isEmpty()) priority.configure(seat.priority);
            UserData data = UserData.getDefaultUserDataView(); data.setAutoOrderTrigger(false); data.setConfirmEmptyManaPool(false);data.setAutoTargetLevel(0);
            for (SkipPrioritySteps steps : Arrays.asList(data.getUserSkipPrioritySteps().getYourTurn(), data.getUserSkipPrioritySteps().getOpponentTurn())) {
                steps.setUpkeep(true); steps.setDraw(true); steps.setMain1(true); steps.setBeforeCombat(true); steps.setEndOfCombat(true); steps.setMain2(true); steps.setEndOfTurn(true);
            }
            data.setPassPriorityCast(false); data.setPassPriorityActivation(false); data.setManaPoolAutomatic(bool(seat.settings, "autoMana", true)); data.setManaPoolAutomaticRestricted(false); human.setUserData(data);
        }
        int seatOf(Player player) { for (int i = 0; i < seatPlayers.size(); i++) if (seatPlayers.get(i).getId().equals(player.getId())) return i; return -1; }
        JsonObject playerProfile(Player player){int seat=seatOf(player);return seat<0?RoomSeat.profile(null,player.getName()):seatConfigs.get(seat).profile.deepCopy();}
        Map<String,Object> avatarCard(Player player){
            if(player instanceof BridgeHuman)return null;int index=seatOf(player);if(index<0)return null;JsonObject deck=seatConfigs.get(index).deck;
            List<String> names=new ArrayList<>();String commander=null;
            for(String zone:Arrays.asList("commander","main","sideboard"))if(deck.has(zone)&&deck.get(zone).isJsonArray())for(JsonElement entry:deck.getAsJsonArray(zone)){
                String name=entry.isJsonPrimitive()?entry.getAsString():text(entry.getAsJsonObject(),"name","");if(!name.isBlank()){names.add(name);if(commander==null&&zone.equals("commander"))commander=name;}
            }
            String cover=text(deck,"coverCard","");String chosen=names.contains(cover)?cover:commander!=null?commander:names.isEmpty()?null:names.get(0);
            return chosen==null?null:map("name",chosen,"portrait",true);
        }
        void chooseBotPlaymats(Map<String,Deck> decks){
            for(Player player:seatPlayers){
                if(player instanceof BridgeHuman)continue;
                int seat=seatOf(player);Deck deck=decks.get(seatConfigs.get(seat).seatId);
                List<Card> identities=new ArrayList<>(deck.getCards());identities.addAll(deck.getSideboard());
                Set<String> basics=new LinkedHashSet<>();
                for(Card card:identities){
                    mage.filter.FilterMana identity=card.getColorIdentity();
                    if(identity.isWhite())basics.add("Plains");if(identity.isBlue())basics.add("Island");if(identity.isBlack())basics.add("Swamp");if(identity.isRed())basics.add("Mountain");if(identity.isGreen())basics.add("Forest");
                }
                if(basics.isEmpty())basics.add("Wastes");
                List<String> candidates=new ArrayList<>(basics);
                JsonObject source=seatConfigs.get(seat).deck;
                if(source.has("commander")&&source.get("commander").isJsonArray())for(JsonElement entry:source.getAsJsonArray("commander")){
                    String name=entry.isJsonPrimitive()?entry.getAsString():text(entry.getAsJsonObject(),"name","");if(!name.isBlank())candidates.add(name);
                }
                String chosen=candidates.get(java.util.concurrent.ThreadLocalRandom.current().nextInt(candidates.size()));
                botPlaymats.put(player.getId(),map("name",chosen,"preferFullArt",basics.contains(chosen),"botPlaymat",true));
            }
        }
        Map<String,Object> playmatCard(Player player){return owner.botPlaymats.get(player.getId());}
        void spellResolved(PresentationGames.Resolution spell){
            for(Session view:perspectives){
                MageObject visibleObject=view.knownObject(spell.sourceId);
                if(visibleObject==null&&!spell.spell.isCopy())continue;
                Map<String,Object> identity=visibleObject==null?null:view.card(visibleObject);
                boolean neutral=identity!=null&&(Boolean.TRUE.equals(identity.get("hidden"))||Boolean.TRUE.equals(identity.get("faceDown")));
                long sequence=ids.incrementAndGet();
                view.animationEvents.addLast(map("id",game.getId()+"-impact-"+sequence,"sequence",sequence,"type","resolution","nativeType","SPELL_RESOLVED","operation","resolved","successful",true,
                    "sourceId",str(spell.sourceId),"sourceName",neutral?"Face-down card":spell.name,"playerId",str(spell.controllerId),"commander",!neutral&&spell.commander,"manaValue",neutral?0:spell.manaValue,"hidden",neutral,"timestamp",System.currentTimeMillis()));
                while(view.animationEvents.size()>128)view.animationEvents.removeFirst();view.publish();
            }
        }
        String seatIdOf(Player player) { int index = seatOf(player); return index < 0 ? null : seatConfigs.get(index).seatId; }
        Session perspective(String playerId) {
            Session view;
            try { view = humans.get(UUID.fromString(playerId)); } catch (RuntimeException ex) { throw new IllegalArgumentException("Unknown human player"); }
            if (view == null) throw new IllegalArgumentException("Unknown human player"); return view;
        }
        List<Map<String,Object>> participants() {
            List<Map<String,Object>> result = new ArrayList<>();
            for (Player player : seatPlayers) {
                JsonObject source=seatConfigs.get(seatOf(player)).deck;
                result.add(map("seatId", seatIdOf(player), "playerId", str(player.getId()), "id", str(player.getId()), "name", player.getName(), "human", player instanceof BridgeHuman, "seat", seatOf(player),
                    "profile",seatConfigs.get(seatOf(player)).profile.deepCopy(),"deck",map("id",text(source,"id",""),"name",text(source,"name","Deck"),"format",text(source,"format",format))));
            }
            return result;
        }
        void registerPlayer(Player player, Deck deck) {
            player.init(game);
            // Match stock GameController: register concrete cards before useDeck.
            game.loadCards(deck.getCards(), player.getId());
            game.loadCards(deck.getSideboard(), player.getId());
            game.addPlayer(player, deck);
        }
        void start() {
            if (owner != this) throw new IllegalStateException("Only the shared game owner can start execution");
            try { for (Session view : perspectives) view.prepareRecording(); }
            catch(RuntimeException ex) {
                for(Session view:perspectives){view.running=false;view.error=ex.getMessage();view.prompt=null;view.publish();}
                throw ex;
            }
            gameThread = new Thread(() -> {
                try { game.start(seatPlayers.get(0).getId()); }
                catch (Throwable ex) {
                    ex.printStackTrace();
                    for (Session view : perspectives) { view.error = ex.toString(); view.addLog("Engine error: " + view.error); if (view.recorder != null) view.recorder.event("error", map("text", view.error, "origin", "engine")); }
                } finally {
                    for (Session view : perspectives) {
                        view.running = false; view.prompt = null; view.publish();
                        view.inputQueue.close();
                        if (view.recorder != null) view.recorder.finish(stopRequested ? "aborted" : view.error != null ? "failed" : "completed", view.result(), view.error);
                    }
                }
            }, "GAME " + game.getId());
            gameThread.setDaemon(true); gameThread.start();
        }
        void stop() {
            if (owner != this) { requestConcede(); return; }
            if (running) stopRequested = true;
            for (Session view : perspectives) {
                view.stopRequested = stopRequested;view.prompt=null;view.priority.cancel();
                // A requested stop is not proof that native execution ended.
                if(gameThread==null||!gameThread.isAlive())view.running=false;
            }
            if (gameThread != null) gameThread.interrupt();
            // Cancellation is input only; the single GAME thread ends execution.
            for (Player player : seatPlayers) player.abort();
            for(Session view:perspectives)view.inputQueue.close();
            if (gameThread != null && gameThread != Thread.currentThread()) try { gameThread.join(3000); } catch (InterruptedException ex) { Thread.currentThread().interrupt(); }
            for (Session view : perspectives) if (view.recorder != null) {
                if (gameThread == null) view.recorder.finish("aborted", map("reason", "Stopped before game start"), null);
                if(!executionAlive())view.recorder.awaitFinished(5000);
            }
        }
        boolean executionAlive(){Thread thread=owner.gameThread;return thread!=null&&thread.isAlive();}
        Map<String,Object> executionState(){
            Thread thread=owner.gameThread;boolean alive=thread!=null&&thread.isAlive();
            return map("threadAlive",alive,"stopRequested",owner.stopRequested,"terminationConfirmed",thread!=null&&!alive,
                "concedeRequested",owner.practiceConcedeRequested,"terminationReason",owner.practiceConcedeProcessed?"practice_conceded":owner.stopRequested?"stopped":null,
                "status",alive?(owner.stopRequested?"stop_requested":"running"):thread==null?"not_started":"terminated");
        }
        Map<String,Object> result() {
            List<Map<String,Object>> players = new ArrayList<>(); List<String> winners = new ArrayList<>();
            for (Player player : game.getPlayers().values()) {
                players.add(map("id", str(player.getId()), "seatId", seatIdOf(player), "name", player.getName(), "life", player.getLife(), "won", player.hasWon(), "lost", player.hasLost()));
                if (player.hasWon()) winners.add(seatIdOf(player));
            }
            boolean completed=!running&&!stopRequested&&error==null&&game.hasEnded();Player perspective=game.getPlayer(human.getId());
            return map("gameId", str(game.getId()), "running", running, "error", error, "turn", game.getTurnNum(), "players", players, "winnerSeatIds", winners,
                "winnerIds",game.getPlayers().values().stream().filter(Player::hasWon).map(p->str(p.getId())).collect(Collectors.toList()),"perspectivePlayerId",str(human.getId()),"completed",completed,
                "terminationReason",practiceConcedeProcessed?"practice_conceded":stopRequested?"stopped":null,
                "outcome",completed?(perspective==null?"observer":perspective.hasWon()?"win":perspective.hasLost()?"loss":"draw"):running?"running":error!=null?"failed":"aborted");
        }
        Map<String,Object> publicResult() {
            Map<String,Object> frame = snapshot; List<Map<String,Object>> players = new ArrayList<>(); List<String> winners = new ArrayList<>();
            Object list = frame.get("players");
            if (list instanceof List<?>) for (Object value : (List<?>)list) {
                @SuppressWarnings("unchecked") Map<String,Object> player = (Map<String,Object>)value;
                players.add(map("id", player.get("id"), "seatId", player.get("seatId"), "name", player.get("name"), "life", player.get("life"), "won", player.get("won"), "lost", player.get("lost")));
                if (Boolean.TRUE.equals(player.get("won"))) winners.add(String.valueOf(player.get("seatId")));
            }
            return map("gameId", str(game.getId()), "running", frame.getOrDefault("running", running), "error", frame.getOrDefault("error", error), "turn", frame.getOrDefault("turn", 0), "players", players, "winnerSeatIds", winners);
        }
        synchronized void prepareRecording() {
            if (recorder != null || recordingPort == 0) return;
            JsonObject metadata = new JsonObject();
            metadata.addProperty("id", "game-" + game.getId() + (room ? "-" + roomSeatId : ""));
            metadata.addProperty("title", room ? human.getName() + " — Room match" : human.getName() + " vs " + (bots.size() == 1 ? bot.getName() : bots.size() + " XMage bots"));
            metadata.addProperty("format", format); metadata.addProperty("playerName", human.getName()); metadata.addProperty("botName", bot == null ? "" : bot.getName());
            metadata.addProperty("playerCount", seatPlayers.size()); metadata.addProperty("startedAt", System.currentTimeMillis());
            RoomSeat own = seatConfigs.stream().filter(seat -> seat.seatId.equals(roomSeatId)).findFirst().orElse(null);
            metadata.add("playerDeck", own == null ? new JsonObject() : own.deck);
            if (!room) { metadata.add("botDeck", botSources.get(0).get("deck")); metadata.add("bots", JSON.toJsonTree(botSources)); }
            metadata.add("settings", own == null ? new JsonObject() : own.settings); metadata.add("priority", JSON.toJsonTree(priority.view(null)));
            metadata.add("metadata", JSON.toJsonTree(map("gameId", str(game.getId()), "players", participants(), "perspective", "human", "perspectivePlayerId", str(human.getId()), "perspectiveSeatId", roomSeatId, "room", room, "engine", "XMage 1.4.63")));
            recorder = ReplayRecorder.create(recordingPort, metadata);
        }
        Session recordingView() { for (Session view : perspectives) if (view.recorder != null) return view; return null; }
        void publishAll() { for (Session view : perspectives) view.publish(); }
        Map<String,Object> state() {
            if(!running&&recorder!=null)recorder.awaitFinished(1200);
            Map<String,Object> projected = snapshot;
            Map<String,Object> waiting = prompt;
            Object projectedPrompt = projected.get("prompt");
            // A cleared answer must disappear immediately. Conversely, a new
            // prompt cannot accompany the previous board before GAME publishes
            // its complete projection. Published prompt maps are immutable.
            Map<String,Object> visible = projectedPrompt == waiting || inputQueue.recoveredPrompt==waiting ? waiting : null;
            if(owner.stopRequested||owner.practiceConcedeRequested)visible=null;
            Map<String,Object> controls = priority.view(visible);
            if (visible != null && Boolean.TRUE.equals(visible.get("priority")) && !Boolean.TRUE.equals(controls.get("canEndTurn"))) {
                visible = null; controls = priority.view(null);
            }
            Map<String,Object> result=new LinkedHashMap<>(projected);
            result.put("execution",executionState());
            result.put("inputDelivery",inputQueue.view());
            if(owner.stopRequested)result.put("running",executionAlive());
            if(recorder!=null)result.putAll(recorder.state());
            result.put("prompt", visible);
            result.put("priority", controls);
            Session decision=owner.humans.get(owner.decisionPlayerId);
            if(decision!=null&&decision.prompt==null)result.put("decisionStartedAt",null);
            result.put("replayAvailable", recorder != null);
            if (room && recorder == null) result.put("replayUnavailableReason", "Room replay is saved by the host");
            return result;
        }
        void requestConcede() {
            if(!room)practiceConcedeRequested=true;
            prompt = null; priority.cancel();
            if (game.getPriorityPlayerId() == null && game.getState().getChoosingPlayerId() == null) owner.pendingConcedes.add(human.getId());
            else game.setConcedingPlayer(human.getId());
            // Native setConcedingPlayer queues the correct seat. Wake the
            // currently waiting human, including a different player's dialog;
            // native waitForResponse processes the queue on GAME and resumes
            // the same unanswered dialog if the game continues.
            for (Session view : perspectives) {
                view.human.signalPlayerConcede(true);
                // Manual trigger ordering has its own bridge queue instead of
                // HumanPlayer's response monitor. Wake it to process the same
                // native concession, preserving another human's unanswered order.
                synchronized(view.triggerAnswers) {
                    if(view.triggerAnswers.isEmpty())view.triggerAnswers.offer(Collections.emptyList());
                }
            }
        }
        void afterNativeConcede(Game context) {
            if(context!=game)return;
            boolean changed=false;
            for(Player player:game.getPlayers().values())if(player.hasLeft()&&publishedDepartures.add(player.getId()))changed=true;
            afterPracticeConcede();
            // Native leave need not emit a table event, especially during an
            // unchanged opponent mulligan/order dialog. Publish the completed
            // native departure, preserving that other player's exact prompt.
            if(changed)publishAll();
        }
        void beforeNativeEffects(Game context){
            if(context==game)for(Session view:perspectives)view.libraryTopLooks.clear();
        }
        void beforeNativeEvent(Game context,GameEvent event){
            if(context==game&&event.getType()==GameEvent.EventType.SHUFFLE_LIBRARY)
                for(Session view:perspectives)view.libraryTopLooks.remove(event.getPlayerId());
        }
        void observeLibraryLook(Collection<Card> cards,Game context){
            if(context!=game||!mage.util.ThreadUtils.isRunGameThread()||context.isSimulation()||context.inCheckPlayableState()||!NativeProjection.canLookAtLibraryTop(game))return;
            for(Card card:cards){
                if(card==null)continue;
                Player owner=game.getPlayer(card.getOwnerId());Card top=owner==null?null:owner.getLibrary().getFromTop(game);
                if(top!=null&&top.getId().equals(card.getId()))libraryTopLooks.put(owner.getId(),card.getId());
            }
        }
        void afterPracticeConcede() {
            if(room||!practiceConcedeRequested)return;
            Player player=game.getPlayer(human.getId());
            if(player==null||!player.hasLost()||!player.hasLeft())return;
            // The stock concession queue has already marked the human lost.
            // End only this local practice on GAME; the bots' unfinished contest
            // has no invented winner and does not become an aborted human loss.
            mage.util.ThreadUtils.ensureRunInGameThread();
            practiceConcedeProcessed=true;
            if(!game.hasEnded()) {
                practiceConcedeEnded=true;
                addLog("Local practice ended after "+human.getName()+" conceded");
                game.end();
            }
        }
        void flushPendingConcedes() {
            UUID id; while ((id = owner.pendingConcedes.poll()) != null) game.setConcedingPlayer(id);
        }
        void priorityCommand(JsonObject command) {
            synchronized(answerLock){applyPriorityCommand(command);}
        }
        void applyPriorityCommand(JsonObject command) {
            if (!running) throw new IllegalArgumentException("No running game");
            String type = text(command, "command", "configure");
            Map<String,Object> waiting = prompt;
            boolean canWake = waiting != null && Boolean.TRUE.equals(waiting.get("priority"));
            switch (type) {
                case "configure": priority.configure(command); break;
                case "cancel": priority.cancel(); break;
                case "end_turn":
                    if (!canWake || !command.has("promptId") || command.get("promptId").getAsLong() != ((Number)waiting.get("id")).longValue())
                        throw new IllegalArgumentException("End Turn requires the current priority prompt");
                    priority.endTurn(); break;
                default: throw new IllegalArgumentException("Unknown priority command: " + type);
            }
            recordAction(map("type", "priority", "command", command));
            if (canWake && prompt == waiting) {
                prompt = null;
                // Unknown strings make native priority return without passing;
                // the GAME loop re-evaluates state and asks priority again.
                human.setResponseString("bridge-priority-refresh");
            }
        }
        void addLog(String message){addLog(message,null,tableCategory(message),null,null,"table");}
        synchronized void addLog(String message,UUID actorId,String category,UUID sourceId,String sourceName,String origin) {
            if (message.isEmpty()) return;
            message=message.replaceAll("\\s+"," ").trim();
            if(actorId==null){
                // Longest unambiguous name prefix also handles Bot 1 / Bot 10.
                Player candidate = null;
                boolean ambiguous = false;
                for (Player player : game.getPlayers().values()) {
                    String name = player.getName();
                    if (!message.startsWith(name + " ") && !message.startsWith(name + "'")) continue;
                    if (candidate == null || name.length() > candidate.getName().length()) { candidate = player; ambiguous = false; }
                    else if (name.length() == candidate.getName().length()) ambiguous = true;
                }
                if (candidate != null && !ambiguous) actorId = candidate.getId();
            }
            Map<String,Object> previous=log.peekLast();if(previous!=null&&message.equals(previous.get("text"))&&Objects.equals(str(actorId),previous.get("actorId")))return;
            long sequence=logIds.incrementAndGet();Map<String,Object> entry=map("id",game.getId()+"-log-"+sequence,"sequence",sequence,"actorId",str(actorId),"actorName",actorId==null?"System":game.getPlayer(actorId)!=null?game.getPlayer(actorId).getName():"Player","actor",human.getId().equals(actorId)?"human":actorId!=null&&game.getPlayer(actorId)!=null?"bot":"system","category",category,"text",message,"sourceId",str(sourceId),"sourceName",sourceName,"origin",origin,"timestamp",System.currentTimeMillis());
            MageObject logSource=knownObject(sourceId);
            entry.put("sourceCard",logSource==null?null:card(logSource));
            entry.put("stackEvent",Arrays.asList("cast","resolve","trigger","mana").contains(category));
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
            if(card!=null&&zone==Zone.LIBRARY&&!NativeProjection.knownLibraryCard(this,card))return null;
            if(card!=null&&!human.getId().equals(card.getOwnerId())&&zone==Zone.HAND) {
                boolean revealed=game.getState().getRevealed().values().stream().anyMatch(c->c.contains(id))||(game.getState().getLookedAt(human.getId())!=null&&game.getState().getLookedAt(human.getId()).values().stream().anyMatch(c->c.contains(id)));
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
            if(event.getType()==GameEvent.EventType.DECLARE_BLOCKERS_STEP_PRE){owner.confirmedBlockerDefenders.clear();owner.confirmedBlockersPhase=game.getPhase();}
            if(event.getType()==GameEvent.EventType.DECLARED_BLOCKERS){
                if(owner.confirmedBlockersPhase!=game.getPhase()){owner.confirmedBlockerDefenders.clear();owner.confirmedBlockersPhase=game.getPhase();}
                owner.confirmedBlockerDefenders.add(event.getPlayerId());
            }
            UUID actor=event.getPlayerId(),sourceId=event.getSourceId();MageObject source=knownObject(sourceId);
            String sourceName=source!=null?String.valueOf(card(source).get("name")):null;
            boolean visual=visualEvent(event,source);
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
                default:if(visual)publish();return;
            }
            addLog(message,actor,category,source!=null?sourceId:null,sourceName,"game");publish();
        }
        boolean visualEvent(GameEvent event,MageObject source) {
            String type;
            switch(event.getType()){
                case SPELL_CAST:type="cast";break;
                case ACTIVATED_ABILITY:case TRIGGERED_ABILITY:type="ability";break;
                case RESOLVING_ABILITY:type="resolve";break;
                case DAMAGED_PLAYER:case DAMAGED_PERMANENT:type="damage";break;
                case GAINED_LIFE:type="life_gain";break;
                case LOST_LIFE:type="life_loss";break;
                case ATTACKER_DECLARED:type="attack";break;
                case BLOCKER_DECLARED:type="block";break;
                case COUNTER_ADDED:case COUNTER_REMOVED:type="counter";break;
                case ATTACHED:case UNATTACHED:type="attachment";break;
                case ZONE_CHANGE:type="zone";break;
                case STEP_CHANGED:case COMBAT_DAMAGE_STEP_PRE:type="step";break;
                case DESTROYED_PERMANENT:case SACRIFICED_PERMANENT:type="departure";break;
                case TAPPED:case UNTAPPED:type="tap";break;
                case TURNED_FACE_UP:case TURNED_FACE_DOWN:case TRANSFORMED:case CREATURE_MUTATED:case PHASED_IN:case PHASED_OUT:type="material";break;
                case DREW_CARD:case DISCARDED_CARD:case MILLED_CARD:type="transfer";break;
                case COUNTERED:type="countered";break;
                case MANA_ADDED:case MANA_PAID:type="payment";break;
                case SCRIED:case SURVEILED:case CYCLED_CARD:case EXPLORED:case DISCOVERED:type="mechanic";break;
                default:return false;
            }
            if(event instanceof ZoneChangeEvent&&((ZoneChangeEvent)event).getToZone()==Zone.BATTLEFIELD){
                Permanent entered=game.getPermanent(event.getTargetId());
                if(entered!=null&&entered.isToken()&&event.getSourceId()!=null)tokenSources.put(entered.getId(),event.getSourceId());
            }
            UUID targetId=event.getTargetId();MageObject target=knownObject(targetId);
            boolean targetVisible=target!=null||game.getPlayer(targetId)!=null;
            long sequence=ids.incrementAndGet();
            Map<String,Object> visual=map("id",game.getId()+"-event-"+sequence,"sequence",sequence,"type",type,"nativeType",event.getType().name(),
                "sourceId",source==null?null:str(source.getId()),"sourceName",source==null?null:visibleName(source.getId()),"targetId",targetVisible?str(targetId):null,
                "playerId",str(event.getPlayerId()),"amount",event.getAmount(),"combat",event instanceof DamagedEvent&&((DamagedEvent)event).isCombatDamage(),
                "step",game.getTurnStepType()==null?null:game.getTurnStepType().name(),"timestamp",System.currentTimeMillis());
            if(event instanceof ZoneChangeEvent){visual.put("fromZone",((ZoneChangeEvent)event).getFromZone().name());visual.put("toZone",((ZoneChangeEvent)event).getToZone().name());}
            NativeMechanics.event(this,event,source,visual);
            if(event instanceof ZoneChangeEvent&&((ZoneChangeEvent)event).getToZone()==Zone.BATTLEFIELD&&((ZoneChangeEvent)event).isPermanentMoved()){
                Permanent entered=((ZoneChangeEvent)event).getTarget();Map<String,Object> enteredView=card(entered);
                boolean hidden=Boolean.TRUE.equals(enteredView.get("hidden"))||Boolean.TRUE.equals(enteredView.get("faceDown"));
                PresentationGames.Resolution resolving=PresentationGames.entering(entered.getId());
                int manaValue=hidden?0:resolving==null?entered.getManaValue():resolving.manaValue;
                boolean commander=!hidden&&(resolving!=null?resolving.commander:game.getPlayers().values().stream().anyMatch(player->game.isCommanderObject(player,entered)));
                visual.put("type",commander||manaValue>5?"impact":"entry");visual.put("operation","enter_battlefield");
                visual.put("entry",true);visual.put("entryId",visual.get("id"));visual.put("sourceId",str(entered.getId()));visual.put("targetId",str(entered.getId()));visual.put("commander",commander);visual.put("manaValue",manaValue);visual.put("hidden",hidden);
            }
            animationEvents.addLast(visual);while(animationEvents.size()>128)animationEvents.removeFirst();
            return true;
        }
        void query(PlayerQueryEvent event) {
            if (!event.getPlayerId().equals(human.getId())) return;
            owner.flushPendingConcedes();
            if(game.hasEnded()||human.hasLeft())return;
            if (event.getQueryType() == PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) { addLog(clean(event.getMessage())); publish(); return; }
            long started=System.currentTimeMillis();owner.decisionStartedAt=started;owner.decisionPlayerId=human.getId();
            Map<String, Object> p = map("id", ids.incrementAndGet(), "playerId",str(human.getId()),"startedAt",started,"type", event.getQueryType().name().toLowerCase(Locale.ROOT), "message", clean(event.getMessage()), "min", event.getMin(), "max", event.getMax(), "required", event.isRequired());
            nativePromptId=((Number)p.get("id")).longValue();
            human.nativeOfferedAbilities=null;
            List<Map<String, Object>> choices = new ArrayList<>();
            Set<String> targets = new LinkedHashSet<>();
            if (event.getTargets() != null) for (UUID id : event.getTargets()) addObjectChoice(choices, targets, id);
            if (event.getCards() != null) for (UUID id : event.getCards()) addObjectChoice(choices, targets, id, true);
            if (event.getPerms() != null) for (Permanent perm : event.getPerms()) addObjectChoice(choices, targets, perm.getId());
            NativeManaPayment.Sources manaSources = new NativeManaPayment.Sources(this);
            if (event.getAbilities() != null) {
                boolean allMana=!event.getAbilities().isEmpty() && event.getAbilities().stream().allMatch(Ability::isManaAbility);
                for (Ability a : event.getAbilities()) {
                    Map<String,Object> choice=map("id", a.getId().toString(), "sourceId", str(a.getSourceId()), "label", clean(a.getRule()), "responseType", "uuid");
                    if(a instanceof SpellAbility) {
                        SpellAbility spell=(SpellAbility)a;
                        // A permanent spell's ordinary rules label can be empty.
                        String rule=(String)choice.get("label");
                        choice.put("label",clean(spell.getName()));
                        choice.put("manaCost",spell.getManaCosts().getText());
                        if(!rule.isBlank())choice.put("detail",rule);
                    }
                    if(a instanceof ManaAbility) choice.put("manaColors",manaSources.colors(a));
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
                @SuppressWarnings("unchecked") List<Map<String,Object>> rows=(List<Map<String,Object>>)p.get("amountMessages");
                for(int i=0;i<rows.size();i++)rows.get(i).put("nativeIndex",i+1);
                Map<String,Object> damage=human.combatDamageContext;
                if(damage!=null){
                    @SuppressWarnings("unchecked") List<Map<String,Object>> details=(List<Map<String,Object>>)damage.get("rows");
                    if(details.size()==rows.size())for(int i=0;i<rows.size();i++)rows.get(i).putAll(details.get(i));
                    p.put("damageSourceId",damage.get("sourceId"));p.put("damageSourceCard",damage.get("sourceCard"));
                    p.put("combat",map("role",damage.get("role"),"sourceId",damage.get("sourceId"),"nativeAmountOrder",true));
                }
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
                    boolean payment = event.getQueryType() == PlayerQueryEvent.QueryType.PLAY_MANA;
                    if (payment) NativeManaPayment.addPoolChoices(choices, human.getManaPool());
                    for (UUID id : actionableObjects(event, manaSources)) {
                        Map<String,Object> card = addObjectChoice(choices, targets, id);
                        if (payment && card != null && !Boolean.TRUE.equals(card.get("hidden"))) {
                            choices.addAll(manaSources.choices(id, (String)card.get("name")));
                        }
                    }
                    choices.add(map("id", "done", "label", payment ? "Cancel payment" : "Pass / Done", "responseType", "boolean", "value", true));
                    if (event.getOptions() != null && event.getOptions().containsKey("specialButton")) choices.add(map("id", "special", "label", clean(event.getOptions().get("specialButton").toString()), "responseType", "string"));
                    else if(!game.getState().getSpecialActions().getControlledBy(human.getId(),event.getQueryType()==PlayerQueryEvent.QueryType.PLAY_MANA).isEmpty()) choices.add(map("id","special","label","Special action (delve / convoke / other)","responseType","string"));
                    break;
                default: break;
            }
            if (!event.isRequired() && event.getQueryType() == PlayerQueryEvent.QueryType.PICK_TARGET) choices.add(map("id", "done", "label", "Done / Cancel", "responseType", "boolean", "value", false));
            Map<String,Serializable> nativeOptions=event.getOptions();
            if(nativeOptions!=null&&nativeOptions.containsKey("possibleTargets")||human.activeTarget!=null&&event.getQueryType()==PlayerQueryEvent.QueryType.PICK_TARGET){
                Set<UUID> offered=new LinkedHashSet<>(),chosen=new LinkedHashSet<>();
                if(nativeOptions!=null){addIds(offered,nativeOptions.get("possibleTargets"));addIds(chosen,nativeOptions.get("chosenTargets"));}
                if(human.activeTarget!=null){
                    if(nativeOptions==null||!nativeOptions.containsKey("possibleTargets"))offered.addAll(human.activeTarget.possibleTargets(human.activeTarget.getAffectedAbilityControllerId(human.getId()),human.activeTargetSource,game,human.activeTargetCards));
                    chosen.addAll(human.activeTarget.getTargets());p.put("min",human.activeTarget.getMinNumberOfTargets());p.put("max",human.activeTarget.getMaxNumberOfTargets());
                }
                targets.clear();for(Map<String,Object> choice:choices)if("uuid".equals(choice.get("responseType")))try{
                    UUID id=UUID.fromString(choice.get("id").toString());boolean selected=chosen.contains(id),selectable=offered.contains(id)||selected;
                    choice.put("selected",selected);choice.put("selectable",selectable);if(selectable)targets.add(id.toString());
                }catch(IllegalArgumentException ignored){}
            }
            boolean priorityPrompt = nativePriorityDepth > 0 && event.getQueryType() == PlayerQueryEvent.QueryType.SELECT
                    && (event.getOptions() == null || !event.getOptions().containsKey("possibleAttackers") && !event.getOptions().containsKey("possibleBlockers"));
            if (priorityPrompt) { p.put("priority", true); p.put("priorityReason", priority.reason()); }
            else priority.choice();
            if((priorityPrompt||event.getQueryType()==PlayerQueryEvent.QueryType.PLAY_MANA)&&human.getStoredBookmark()>=0){
                Map<String,Object> undo=map("id","undo","label","Undo last mana action","responseType","undo","value",true);
                p.put("undoChoice",undo);p.put("nativeUndoBookmark",human.getStoredBookmark());choices.add(undo);
            }
            Map<String,Object> cancel=choices.stream().filter(c2->"cancel-choice".equals(c2.get("id"))||"done".equals(c2.get("id"))&&event.getQueryType()==PlayerQueryEvent.QueryType.PICK_TARGET&&!event.isRequired()||"done".equals(c2.get("id"))&&event.getQueryType()==PlayerQueryEvent.QueryType.PLAY_MANA).findFirst().orElse(null);
            p.put("cancelChoice",cancel);
            p.put("cancelScope",human.pendingActionKind!=null?"pending_action":"choice");
            if(human.pendingActionKind!=null)p.put("pendingAction",map("kind",human.pendingActionKind,"sourceId",str(human.pendingActionSource),"canCancel",cancel!=null));
            promptContext.enrich(p,event,choices);
            if(nativeOptions!=null&&nativeOptions.containsKey("possibleAttackers")){
                p.put("combat",map("role","attackers","selectedAttackerIds",NativeProjection.ids(game.getCombat().getAttackers()),"declarationConfirmed",false));
            }else if(nativeOptions!=null&&nativeOptions.containsKey("possibleBlockers")){
                Set<UUID> blockers=new LinkedHashSet<>();addIds(blockers,nativeOptions.get("possibleBlockers"));
                try{p.put("combat",map("role","blockers","declarationConfirmed",false,"message","Blocks are not confirmed yet. Select blockers, then choose Done to confirm before activating abilities.","blockers",NativeProjection.blockerOptions(this,blockers)));}
                catch(RuntimeException previewError){
                    // Optional explanatory projection must never abort a real
                    // blocker decision. Actual engine choices remain intact.
                    p.put("combat",map("role","blockers","declarationConfirmed",false,"message","Blocks are not confirmed yet. Choose Done to confirm.","blockers",Collections.emptyList(),"blockerIds",NativeProjection.ids(blockers),"previewUnavailable",true));
                }
            }else if(human.selectedBlockerId!=null)p.put("combat",map("role","block_target","declarationConfirmed",false,"message","Choose the attacker to block, then choose Done to confirm all blocks.","blockerId",str(human.selectedBlockerId),"legalAttackerIds",new ArrayList<>(targets)));
            p.put("choices", choices);
            p.put("targets", targets);
            p.put("actionable",new ArrayList<>(targets));
            if(priorityPrompt||event.getQueryType()==PlayerQueryEvent.QueryType.PLAY_MANA){
                try{p.put("cardActions",NativeCardActions.offered(this,choices,event.getQueryType()==PlayerQueryEvent.QueryType.PLAY_MANA ? manaSources : null));}
                catch(RuntimeException unavailable){p.put("cardActions",Collections.emptyList());p.put("actionDetailsKnown",false);}
            }
            p.put("options", safeOptions(event.getOptions()));
            prompt = p;
            owner.publishAll();
        }
        Set<UUID> actionableObjects(PlayerQueryEvent event, NativeManaPayment.Sources manaSources) {
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
                for(MageObject object:visible) if(manaSources.collect(object)) ids.add(object.getId());
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
            if (options != null) options.forEach((k,v) -> { if (v instanceof String || v instanceof Number || v instanceof Boolean) out.put(k,v);else if(v instanceof Enum<?>)out.put(k,((Enum<?>)v).name()); });
            return out;
        }
        Map<String,Object> addObjectChoice(List<Map<String, Object>> choices, Set<String> targets, UUID id) {
            return addObjectChoice(choices,targets,id,false);
        }
        Map<String,Object> addObjectChoice(List<Map<String, Object>> choices, Set<String> targets, UUID id,boolean granted) {
            if (!targets.add(id.toString())) return null;
            MageObject object = game.getObject(id);
            if(object==null&&granted)object=game.getCard(id);
            Player p = game.getPlayer(id);
            Map<String,Object> view=object!=null ? card(object,granted) : null;
            choices.add(map("id", id.toString(), "label", view != null ? view.get("name") : p != null ? p.getName() : id.toString(), "responseType", "uuid", "card", view));
            return view;
        }
        void action(JsonObject action) throws Exception {
            if("concede".equals(text(action,"type",""))){
                if(action.has("expectedGameId")&&!game.getId().toString().equals(text(action,"expectedGameId","")))throw new IllegalArgumentException("This game is outdated; refresh the current match");
                // Control signals must remain available while an ordinary
                // native answer is waiting for its response window to open.
                recordAction(action.deepCopy());requestConcede();return;
            }
            // Claim a prompt once before recording/delivery. The lock is not
            // the projection monitor, so a long publish cannot block Concede.
            synchronized(answerLock){deliverAction(action);}
        }
        void deliverAction(JsonObject action) throws Exception {
            if(action.has("expectedGameId")&&!game.getId().toString().equals(text(action,"expectedGameId","")))
                throw new IllegalArgumentException("This game is outdated; refresh the current match");
            Map<String, Object> p = prompt;
            String type = text(action, "type", "");
            if ("concede".equals(type)) { recordAction(action.deepCopy()); requestConcede(); return; }
            if (p == null) throw new IllegalArgumentException("XMage is not waiting for a choice");
            if (!action.has("promptId") || action.get("promptId").getAsLong() != ((Number)p.get("id")).longValue()) throw new IllegalArgumentException("This choice is outdated; refresh the game");
            JsonElement value = action.get("value");
            if (value == null) throw new IllegalArgumentException("Missing answer value");
            if("undo".equals(type)){
                if(!(p.get("nativeUndoBookmark") instanceof Number)||!value.isJsonPrimitive()||!value.getAsJsonPrimitive().isBoolean()||!value.getAsBoolean())throw new IllegalArgumentException("Native undo is not offered here");
                int bookmark=((Number)p.get("nativeUndoBookmark")).intValue();
                inputQueue.submit(p,()->{recordAction(action.deepCopy());prompt=null;},()->human.setUndoResponse(bookmark));return;
            }
            if ("order".equals(type)) {
                if (!"order".equals(p.get("type"))) throw new IllegalArgumentException("Not a trigger ordering prompt");
                List<String> order = new ArrayList<>();
                for (JsonElement e : value.getAsJsonArray()) order.add(e.getAsString());
                @SuppressWarnings("unchecked") List<Map<String,Object>> choices = (List<Map<String,Object>>)p.get("choices");
                Set<String> required = choices.stream().map(x -> x.get("id").toString()).collect(Collectors.toSet());
                if (order.size() != required.size() || !new HashSet<>(order).equals(required)) throw new IllegalArgumentException("Include every trigger once");
                synchronized(triggerAnswers) {
                    // A native concession wake carries no chosen trigger IDs.
                    // Replace only that marker, so a simultaneous genuine
                    // answer cannot disappear behind the bounded queue.
                    triggerAnswers.remove(Collections.emptyList());
                    if(!triggerAnswers.isEmpty())throw new IllegalArgumentException("This trigger order is already answered");
                    recordAction(action.deepCopy());
                    prompt = null;
                    triggerAnswers.add(order);
                }
                return;
            }
            // Validate transport values before recording or consuming the prompt.
            // Rejected stale/malformed attempts are not accepted replay actions.
            validateAnswer(p,type,value);
            Runnable deliver;
            switch (type) {
                case "uuid": { UUID answer = UUID.fromString(value.getAsString()); deliver = () -> human.setResponseUUID(answer); break; }
                case "boolean": { boolean answer = value.getAsBoolean(); deliver = () -> human.setResponseBoolean(answer); break; }
                case "integer": { int answer = value.getAsInt(); deliver = () -> human.setResponseInteger(answer); break; }
                case "string": { String answer = value.getAsString(); deliver = () -> human.setResponseString(answer); break; }
                case "multi_amount": {
                    if (!"multi_amount".equals(p.get("type"))) throw new IllegalArgumentException("Not an amount distribution prompt");
                    List<Integer> amounts = new ArrayList<>();
                    for (JsonElement v : value.getAsJsonArray()) amounts.add(exactInteger(v));
                    @SuppressWarnings("unchecked") List<Map<String,Object>> limits=(List<Map<String,Object>>)p.get("amountMessages");
                    if (limits==null || amounts.size()!=limits.size()) throw new IllegalArgumentException("Answer every amount");
                    long total=0;
                    for(int i=0;i<amounts.size();i++) {
                        int n=amounts.get(i); Map<String,Object> limit=limits.get(i);
                        if(n<((Number)limit.get("min")).intValue() || n>((Number)limit.get("max")).intValue()) throw new IllegalArgumentException("Amount outside allowed range");
                        total+=n;
                    }
                    if(total<((Number)p.get("min")).intValue() || total>((Number)p.get("max")).intValue()) throw new IllegalArgumentException("Amount total outside allowed range");
                    String answer = amounts.stream().map(Object::toString).collect(Collectors.joining(" "));
                    deliver = () -> human.setResponseString(answer); break;
                }
                case "mana": { ManaType answer = ManaType.valueOf(value.getAsString().toUpperCase(Locale.ROOT)); deliver = () -> human.setResponseManaType(human.getId(), answer); break; }
                case NativeManaPayment.SOURCE_RESPONSE: {
                    NativeManaPayment.SourceSelection answer = NativeManaPayment.selection(value.getAsString());
                    deliver = () -> human.setManaSourceResponse(answer);
                    break;
                }
                default: throw new IllegalArgumentException("Unknown response type: " + type);
            }
            inputQueue.submit(p,()->{recordAction(action.deepCopy());priority.acknowledge(p);prompt=null;},deliver);
        }
        void restoreInputPrompt(Map<String,Object> original){synchronized(answerLock){if(prompt==null&&nativePromptId==((Number)original.get("id")).longValue()&&running&&!owner.stopRequested&&!human.hasLeft())prompt=original;}}
        void recordInputDelivery(String delivery,long promptId,String status){Session saved=recordingView();if(saved!=null&&!saved.recorder.isFinished())try{saved.recorder.event("log",map("type","input_delivery","category","transport","text","Native input "+status,"id",delivery,"actorId",str(human.getId()),"promptId",saved==this?promptId:null,"status",status));}catch(RuntimeException failed){saved.projectionError="Input delivery status recording failed: "+failed;}}
        static int exactInteger(JsonElement value){
            if(!value.isJsonPrimitive()||!value.getAsJsonPrimitive().isNumber())throw new IllegalArgumentException("An integer answer is required");
            try{return value.getAsBigDecimal().intValueExact();}
            catch(ArithmeticException ex){throw new IllegalArgumentException("An integer answer is required");}
        }
        static void validateAnswer(Map<String,Object> prompt,String type,JsonElement value){
            if("multi_amount".equals(type)){
                if(!value.isJsonArray())throw new IllegalArgumentException("An amount array is required");
                return; // Per-entry and total native bounds are checked below.
            }
            if("integer".equals(type)){
                int amount=exactInteger(value);String kind=String.valueOf(prompt.get("type"));
                if(!"amount".equals(kind)&&!"get_amount".equals(kind))throw new IllegalArgumentException("Not an amount prompt");
                if(!(prompt.get("min")instanceof Number)||!(prompt.get("max")instanceof Number)
                    ||amount<((Number)prompt.get("min")).intValue()||amount>((Number)prompt.get("max")).intValue())throw new IllegalArgumentException("Amount outside native allowed range");
                return;
            }
            if(!value.isJsonPrimitive()||("boolean".equals(type)?!value.getAsJsonPrimitive().isBoolean():!value.getAsJsonPrimitive().isString()))
                throw new IllegalArgumentException("Answer type does not match the offered choice");
            Object offered=prompt.get("choices");
            if(offered instanceof List<?>)for(Object entry:(List<?>)offered){
                if(!(entry instanceof Map<?,?>))continue;Map<?,?> choice=(Map<?,?>)entry;
                if(!type.equals(choice.get("responseType"))||Boolean.FALSE.equals(choice.get("selectable")))continue;
                Object answer=choice.containsKey("value")?choice.get("value"):choice.get("id");
                if(JSON.toJsonTree(answer).equals(value))return;
            }
            throw new IllegalArgumentException("This answer was not offered by the native prompt");
        }
        void recordAction(Object input) {
            Session saved = recordingView();
            if (saved == null || saved.recorder.isFinished()) return;
            Object visible = input;
            if (saved != this) {
                // Opponents' private choice values never enter the host replay.
                JsonElement data = JSON.toJsonTree(input);
                String response = data.isJsonObject() ? text(data.getAsJsonObject(), "type", "choice") : "choice";
                visible = map("type", "remote_action", "responseType", response);
            }
            saved.recorder.event("action", map("actorId", str(human.getId()), "actor", "human", "input", visible, "promptId", saved == this && prompt != null ? prompt.get("id") : null));
        }
        synchronized void publish() {
            try {
                List<Map<String, Object>> players = new ArrayList<>();
                for (Player p : game.getPlayers().values()) {
                    List<Map<String,Object>> battlefield = new ArrayList<>();
                    for (Permanent permanent : game.getBattlefield().getAllActivePermanents()) if (p.getId().equals(permanent.getControllerId())) battlefield.add(card(permanent));
                    players.add(map("id", p.getId().toString(), "seat", seatOf(p), "seatId", seatIdOf(p), "name", p.getName(), "isHuman", p instanceof BridgeHuman, "isLocal", p.getId().equals(human.getId()), "human", p.getId().equals(human.getId()), "profile", playerProfile(p), "avatarCard", avatarCard(p), "playmatCard",playmatCard(p), "life", p.getLife(), "hand", p.getId().equals(human.getId()) ? cards(p.getHand().getCards(game)) : Collections.emptyList(), "handCount", p.getHand().size(), "libraryCount", p.getLibrary().size(), "libraryTop",NativeProjection.libraryTop(this,p),"libraryTopVisibility",NativeProjection.libraryTopVisibility(this,p), "sideboardCount",p.getSideboard().size(), "graveyard", cards(p.getGraveyard().getCards(game)), "battlefield", battlefield, "command", cards(game.getCommanderCardsFromCommandZone(p, CommanderCardType.ANY)), "exile",cards(game.getExile().getAllCards(game).stream().filter(c -> p.getId().equals(c.getOwnerId())).collect(Collectors.toList())),"mana", NativeManaPayment.pool(p.getManaPool()), "won",p.hasWon(),"lost",p.hasLost(),"attachmentIds",NativeProjection.ids(p.getAttachments())));
                }
                for(Map<String,Object> view:players){Player nativePlayer=game.getPlayer(UUID.fromString(view.get("id").toString()));view.put("commanders",NativeProjection.commanders(this,nativePlayer));view.put("commanderDamageReceived",NativeProjection.commanderDamageReceived(this,nativePlayer));}
                List<Map<String,Object>> stack = new ArrayList<>();
                int stackIndex=0;for (StackObject o : game.getStack()) {Map<String,Object> view=stackCard(o);view.put("stackIndex",stackIndex);view.put("isTop",stackIndex++==0);stack.add(view);}
                List<Map<String,Object>> exiled = cards(game.getExile().getAllCards(game));
                List<Map<String,Object>> revealed=new ArrayList<>(),lookedAt=new ArrayList<>();
                game.getState().getRevealed().forEach((label,list)->revealed.add(map("label",clean(label),"cards",cards(list.getCards(game)))));
                if(game.getState().getLookedAt(human.getId())!=null) game.getState().getLookedAt(human.getId()).forEach((label,list)->{
                    if(lookedAtReferences.get(label)!=list){
                        lookedAtReferences.put(label,list);
                        while(lookedAtReferences.size()>16)lookedAtReferences.remove(lookedAtReferences.keySet().iterator().next());
                        rememberedLookedAt.addLast(map("id",game.getId()+"-look-"+ids.incrementAndGet(),"label",clean(label),"cards",cards(list.getCards(game))));
                        while(rememberedLookedAt.size()>8)rememberedLookedAt.removeFirst();
                    }
                });
                lookedAt.addAll(rememberedLookedAt);
                Map<String,Object> next = map("running", running, "format", format, "playerCount", seatPlayers.size(), "error", error, "revision", ids.incrementAndGet(), "gameId", game.getId().toString(), "turn", game.getTurnNum(), "phase", game.getTurn() != null && game.getTurn().getPhase() != null ? String.valueOf(game.getTurn().getPhase().getType()) : "", "step", String.valueOf(game.getTurnStepType()), "activePlayerId", str(game.getActivePlayerId()), "priorityPlayerId", str(game.getPriorityPlayerId()), "players", players, "stack", stack, "exile", exiled,"revealed",revealed,"lookedAt",lookedAt, "prompt", prompt, "log", new ArrayList<>(log), "manualTriggers", manualTriggers);
                next.put("logEntries",new ArrayList<>(log));next.put("logText",log.stream().map(e->e.get("text")).collect(Collectors.toList()));
                next.put("projectionError",projectionError);
                if(!running)next.put("result",result());
                next.put("openingRoll",owner.openingRoll);next.put("combat",NativeProjection.combat(this));next.put("animationEvents",new ArrayList<>(animationEvents));
                next.put("commanderDamageEnabled",game instanceof GameCommanderImpl?((GameCommanderImpl)game).isCheckCommanderDamage():null);
                next.put("decisionPlayerId",str(owner.decisionPlayerId));next.put("decisionStartedAt",owner.decisionStartedAt==0?null:owner.decisionStartedAt);
                next.put("priorityStartedAt",Objects.equals(owner.timedPriorityPlayerId,game.getPriorityPlayerId())?owner.priorityStartedAt:null);
                next.put("clock",map("enabled",false,"limitSeconds",null,"remainingSeconds",null,"penalty",null));
                next.put("capabilities",map("cancelPendingAction",true,"automaticManaPoolPayment",true,"automaticSourceTapping",false));
                next.put("priority",priority.view(prompt));
                if(recorder!=null){next.putAll(recorder.state());if(!recorder.isFinished())recorder.event("frame",next);}
                // Publish only a complete projection. HTTP readers must never
                // serialize a map while this GAME callback is still filling it.
                snapshot = next;
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
            List<Target> allTargets=new ArrayList<>(object.getStackAbility().getAllSelectedTargets());allTargets.addAll(object.getStackAbility().getTargets());
            for(Target target:allTargets)for(UUID id:target.getTargets())if(seen.add(id)){
                boolean changed=target.hasChangedZones(id,game);targets.add(map("id",str(id),"name",changed?"Target changed zones":visibleName(id),"changedZones",changed));
            }
            List<String> modes=new ArrayList<>();for(UUID modeId:object.getStackAbility().getModes().getSelectedModes()){
                mage.abilities.Mode mode=object.getStackAbility().getModes().get(modeId);if(mode!=null)modes.add(clean(mode.toString()));
            }
            view.put("modes",modes);view.put("paidOptions",object.getStackAbility().getCosts().stream().filter(cost->cost.isPaid()).map(cost->clean(cost.getText())).collect(Collectors.toList()));
            view.put("castMode",object.getStackAbility()instanceof SpellAbility?((SpellAbility)object.getStackAbility()).getSpellAbilityCastMode().name().toLowerCase(Locale.ROOT):null);
            if(sourceView!=null&&!Boolean.TRUE.equals(sourceView.get("hidden"))&&!Boolean.TRUE.equals(sourceView.get("faceDown"))){
                view.put("paidMechanics",NativeMechanics.paidMechanics(this,object.getStackAbility()));
                view.put("contributors",NativeMechanics.convokers(this,object.getStackAbility()));
                view.put("nativeManaCostsToPay",object.getStackAbility().getManaCostsToPay().getText());
            }
            view.put("targets",targets);view.put("targetIds",targets.stream().filter(t->!Boolean.TRUE.equals(t.get("changedZones"))).map(t->t.get("id")).collect(Collectors.toList()));return view;
        }
        String visibleName(UUID id){Player player=game.getPlayer(id);if(player!=null)return player.getName();MageObject object=knownObject(id);return object==null?"Hidden card":String.valueOf(card(object).get("name"));}
        List<Map<String,Object>> cards(Collection<? extends MageObject> cards) { return cards.stream().map(this::card).collect(Collectors.toList()); }
        Map<String,Object> card(MageObject c) {
            return card(c,false);
        }
        Map<String,Object> card(MageObject c,boolean granted) {
            if (!granted && c instanceof Card && (game.getState().getZone(c.getId())==Zone.LIBRARY||!human.getId().equals(((Card)c).getOwnerId())) && knownObject(c.getId()) == null)
                return map("id",c.getId().toString(),"name","Hidden card","hidden",true,"manaCost","","type","","rules","","power","","toughness","");
            boolean explicitlySeen=game.getState().getRevealed().values().stream().anyMatch(list->list.contains(c.getId()))||game.getState().getLookedAt(human.getId())!=null&&game.getState().getLookedAt(human.getId()).values().stream().anyMatch(list->list.contains(c.getId()));
            if(c instanceof Card && ((Card)c).isFaceDown(game) && !mage.util.CardUtil.canShowAsControlled((Card)c,human.getId())&&!explicitlySeen){
                Map<String,Object> hidden=map("id",c.getId().toString(),"name","Face-down card","faceDown",true,"hidden",true,"manaCost","","type","","rules","","power","","toughness","");
                if(c instanceof Permanent){
                    Permanent permanent=(Permanent)c;Map<String,Object> counters=new LinkedHashMap<>();permanent.getCounters(game).forEach((name,counter)->counters.put(name,counter.getCount()));
                    hidden.put("power",permanent.getPower()==mage.MageInt.EmptyMageInt?"":Integer.toString(permanent.getPower().getValue()));hidden.put("toughness",permanent.getToughness()==mage.MageInt.EmptyMageInt?"":Integer.toString(permanent.getToughness().getValue()));
                    hidden.put("damage",permanent.getDamage());hidden.put("tapped",permanent.isTapped());hidden.put("controllerId",str(permanent.getControllerId()));hidden.put("ownerId",str(permanent.getOwnerId()));hidden.put("counters",counters);
                    hidden.put("attacking",permanent.isAttacking());hidden.put("blocking",game.getCombat().getBlockers().contains(permanent.getId()));
                }
                return hidden;
            }
            Map<String,Object> m = map("id",c.getId().toString(),"name",c.getName(),"manaCost",c.getManaCost().getText(),"type",c.getCardType(game).toString(),"rules",c.getAbilities().stream().map(a -> clean(a.getRule())).filter(s -> !s.isEmpty()).distinct().collect(Collectors.joining("\n")),"power",c.getPower().toString(),"toughness",c.getToughness().toString(),"set",c.getExpansionSetCode(),"number",c.getCardNumber());
            m.put("currentRules",m.get("rules"));m.put("keywords",NativeProjection.keywords(c));m.put("abilityIcons",NativeProjection.abilityIcons(c,game));m.put("supertypes",c.getSuperType(game).stream().map(Object::toString).collect(Collectors.toList()));
            List<Map<String,Object>> mechanics=NativeMechanics.current(c,game);
            m.put("currentKeywords",mechanics);m.put("mechanicCapabilities",mechanics);
            m.put("nativeInteractions",NativeMechanics.interactions(c,game));
            Set<String> keywordNames=new LinkedHashSet<>();for(Map<String,Object> mechanic:mechanics)keywordNames.add(String.valueOf(mechanic.get("id")));m.put("keywords",new ArrayList<>(keywordNames));
            Zone currentZone=game.getState().getZone(c.getId());if(currentZone!=null)m.put("zone",currentZone.name());
            if(c instanceof Card) { Map<String,Object> counters=new LinkedHashMap<>(); ((Card)c).getCounters(game).forEach((name,counter)->counters.put(name,counter.getCount())); m.put("counters",counters); }
            MageObject printed=c instanceof mage.game.permanent.PermanentToken?((mage.game.permanent.PermanentToken)c).getToken():game.getCard(c.getId());
            if(c instanceof mage.game.permanent.PermanentToken&&((Permanent)c).isTransformed()&&((mage.game.permanent.PermanentToken)c).getToken().getBackFace()!=null)printed=((mage.game.permanent.PermanentToken)c).getToken().getBackFace();
            MageObject mergedTop=MergedProjection.top(this,c);if(mergedTop!=null)printed=mergedTop;
            if(printed==null&&c instanceof Card)printed=c;
            if(printed!=null){
                List<String> subtypes=printed.getSubtype(null).stream().map(Object::toString).collect(Collectors.toList());
                String type=printed.getCardType(null).stream().map(Object::toString).collect(Collectors.joining(" "));
                m.put("printing",map("name",printed.getName(),"power",printed.getPower().toString(),"toughness",printed.getToughness().toString(),"set",printed.getExpansionSetCode(),"number",printed.getCardNumber(),
                    "colors",colorNames(printed.getColor()),"type",type,"type_line",type+(subtypes.isEmpty()?"":" — "+String.join(" ",subtypes)),"subtypes",subtypes,"supertypes",printed.getSuperType().stream().map(Object::toString).collect(Collectors.toList()),"keywords",NativeProjection.keywords(printed)));
            }
            if(c instanceof mage.game.permanent.token.Token){
                Card copySource=((mage.game.permanent.token.Token)c).getCopySourceCard();
                if(copySource!=null&&!(copySource instanceof Permanent))m.put("copySourceCard",card(copySource,true));
            }
            if(c instanceof Card){
                Card nativeCard=(Card)c;m.put("ownerId",str(nativeCard.getOwnerId()));
                // Only this already-entitled visible card's choice is public.
                // The complete deck printingSelections never enters a frame.
                if(!(c instanceof Permanent)||!((Permanent)c).isToken()){
                    Player originalOwner=game.getPlayer(nativeCard.getOwnerId());int seat=originalOwner==null?-1:seatOf(originalOwner);
                    Card original=printed instanceof Card?(Card)printed:game.getCard(c.getId());if(original==null)original=nativeCard;
                    Card main=original.getMainCard();String name=main==null?original.getName():main.getName();
                    String chosen=seat<0?null:CardPrintingProjection.selected(seatConfigs.get(seat).deck,name,str(original.getId()));
                    if(chosen!=null)m.put("selectedPrintingId",chosen);
                }
            }
            m.put("colors",colorNames(c.getColor(game)));m.put("subtypes",c.getSubtype(game).toString());
            if (c instanceof Permanent) {
                Permanent p = (Permanent)c;
                String power=p.getPower()==mage.MageInt.EmptyMageInt?"":Integer.toString(p.getPower().getValue());
                String toughness=p.getToughness()==mage.MageInt.EmptyMageInt?"":Integer.toString(p.getToughness().getValue());
                m.put("power",power);m.put("toughness",toughness);m.put("tapped",p.isTapped());m.put("damage",p.getDamage());m.put("attacking",p.isAttacking());m.put("blocking",game.getCombat().getBlockers().contains(p.getId()));m.put("controllerId",str(p.getControllerId()));
                m.put("permanent",map("power",power,"toughness",toughness,"damage",p.getDamage(),"counters",m.get("counters"),"tapped",p.isTapped()));
                m.put("attachedToId",str(p.getAttachedTo()));m.put("attachedToPlayerId",game.getPlayer(p.getAttachedTo())==null?null:str(p.getAttachedTo()));m.put("attachmentIds",NativeProjection.ids(p.getAttachments()));
                m.put("linkedExile",NativeProjection.linkedExile(this,p));m.put("token",p.isToken());m.put("isToken",p.isToken());
                if(p instanceof mage.game.permanent.PermanentToken){
                    mage.game.permanent.token.Token template=((mage.game.permanent.PermanentToken)p).getToken();
                    if(p.isTransformed()&&template.getBackFace()!=null){
                        m.put("originalTokenTemplate",card(template,true));template=template.getBackFace();
                    }
                    // Preserve the original native token template separately
                    // from a merged top's printing and current live values.
                    // Ordinary tokens already carry this exact template in
                    // printing. Avoid duplicating it in every recorded frame.
                    if(p.getMutateCount()>0||p.isTransformed()||template.getCopySourceCard()!=null){
                        Map<String,Object> templateView=card(template,true);templateView.put("token",true);templateView.put("isToken",true);
                        m.put("tokenTemplate",templateView);
                        // The engine supplies this exact original Card reference.
                        // Never infer a copy's artwork from its current name/P-T.
                        if(templateView.containsKey("copySourceCard"))m.put("copySourceCard",templateView.get("copySourceCard"));
                    }
                }
                Map<String,Object> merged=MergedProjection.view(this,p);if(merged!=null)m.put("mutate",merged);
                UUID tokenSource=tokenSources.get(p.getId());MageObject source=knownObject(tokenSource);
                m.put("tokenSourceId",source==null?null:str(tokenSource));m.put("tokenSourceName",source==null?null:visibleName(tokenSource));
                m.put("minBlockers",p.getMinBlockedBy());m.put("maxBlockers",p.getMaxBlockedBy());
            }
            if (c instanceof StackObject) m.put("sourceId",str(((StackObject)c).getSourceId()));
            if(c instanceof Card&&((Card)c).isFaceDown(game)){
                m.put("faceDown",true);
                // This branch is reached only after the native face-down
                // visibility guard. Keep the live object's 2/2 characteristics
                // separate from the controller's inspection-only original.
                if(printed!=null&&CardUtil.canShowAsControlled((Card)c,human.getId())){
                    Map<String,Object> peek=new LinkedHashMap<>(m);
                    peek.put("name",printed.getName());peek.put("manaCost",printed.getManaCost().getText());
                    peek.put("rules",printed.getAbilities().stream().map(a->clean(a.getRule())).filter(s->!s.isEmpty()).distinct().collect(Collectors.joining("\n")));
                    peek.put("type",printed.getCardType(null).toString());peek.put("power",printed.getPower().toString());peek.put("toughness",printed.getToughness().toString());
                    peek.put("supertypes",printed.getSuperType().stream().map(Object::toString).collect(Collectors.toList()));
                    peek.put("faceDown",false);peek.put("inspectionOnly",true);m.put("faceDownIdentity",peek);
                }
                m.put("keywords",Collections.emptyList());m.put("currentKeywords",Collections.emptyList());m.put("mechanicCapabilities",Collections.emptyList());m.put("nativeInteractions",Collections.emptyList());
            }
            return m;
        }
        static List<String> colorNames(mage.ObjectColor color){
            List<String> result=new ArrayList<>();if(color.isWhite())result.add("W");if(color.isBlue())result.add("U");if(color.isBlack())result.add("B");if(color.isRed())result.add("R");if(color.isGreen())result.add("G");return result;
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
            priority.choice();
            List<Map<String,Object>> choices = new ArrayList<>();
            for (TriggeredAbility a : abilities) choices.add(map("id",a.getId().toString(),"sourceId",str(a.getSourceId()),"label",clean(a.getRule()),"responseType","uuid"));
            prompt = map("id", ids.incrementAndGet(), "type", "order", "message", "Drag triggers left to right: resolves first → resolves last", "choices", choices,"targets",Collections.emptyList(),"required",true);
            owner.publishAll();
            try {
                List<String> chosen;
                do {
                    chosen=triggerAnswers.take();
                    owner.flushPendingConcedes();((GameImpl)game).checkConcede();
                    if(game.hasEnded()||human.hasLeft())return abilities.get(0);
                }while(chosen.isEmpty());
                Collections.reverse(chosen); // bottom of stack is placed first
                synchronized (human.triggerOrder) { for (String id : chosen) human.triggerOrder.add(UUID.fromString(id)); }
                return orderTriggers(abilities, context);
            } catch (InterruptedException ex) { Thread.currentThread().interrupt(); return abilities.get(0); }
        }
    }

    static final class NativeLogWatcher extends Watcher {
        final transient Session session;
        NativeLogWatcher(Session session){super(WatcherScope.GAME);this.session=session;}
        @Override public void watch(GameEvent event,Game game) {
            if (session == null) return;
            for (Session view : session.perspectives) try { view.nativeEvent(event, game); }
            catch (RuntimeException ex) { view.projectionError = "Game log projection: " + ex; System.err.println(view.projectionError); }
        }
        @Override public NativeLogWatcher copy(){return new NativeLogWatcher(session);}
    }

    static final class BridgeHuman extends HumanPlayer {
        final transient Session session;
        final transient Deque<UUID> triggerOrder;
        transient UUID activeManaSource;
        private transient NativeManaPayment.SourceSelection deliveredManaSource;
        private transient NativeManaPayment.SourceSelection paymentManaSource;
        private transient UUID requestedManaAbility;
        transient boolean choosingManaColor;
        transient UUID selectedBlockerId;
        transient String pendingActionKind;
        transient UUID pendingActionSource;
        transient Target activeTarget;
        transient Map<String,Object> combatDamageContext;
        transient Cards activeTargetCards;
        transient Ability activeTargetSource;
        transient List<ActivatedAbility> nativeOfferedAbilities;
        transient Ability activeNativeAbility;
        @Override public List<ActivatedAbility> getPlayable(Game originalGame,boolean hidden,Zone fromZone,boolean hideDuplicates){
            List<ActivatedAbility> result=super.getPlayable(originalGame,hidden,fromZone,hideDuplicates);
            if(real(originalGame)&&hidden&&fromZone==Zone.ALL&&!hideDuplicates)nativeOfferedAbilities=result;
            return result;
        }
        static final class Delivery {final long prompt;boolean accepted;Integer undoBookmark;NativeManaPayment.SourceSelection manaSource;Delivery(long prompt){this.prompt=prompt;}}
        private final transient ThreadLocal<Delivery> deliveryPrompt=new ThreadLocal<>();
        BridgeHuman(String name, Session session) { super(name,RangeOfInfluence.ALL,1); this.session=session; this.triggerOrder=new ArrayDeque<>(); }
        BridgeHuman(BridgeHuman original) { super(original); session=original.session; triggerOrder=original.triggerOrder; }
        @Override public BridgeHuman copy() { return new BridgeHuman(this); }
        boolean deliverNative(long id,Runnable action){Delivery expected=new Delivery(id);deliveryPrompt.set(expected);try{if(session!=null&&session.nativePromptId==id)action.run();return expected.accepted;}finally{deliveryPrompt.remove();}}
        void setUndoResponse(int bookmark){Delivery expected=deliveryPrompt.get();if(expected==null)throw new IllegalStateException("Undo requires a fenced native delivery");expected.undoBookmark=bookmark;setResponseString("bridge-native-undo");}
        void setManaSourceResponse(NativeManaPayment.SourceSelection source) {
            Delivery expected = deliveryPrompt.get();
            if (expected == null) throw new IllegalStateException("Mana source requires a fenced native delivery");
            expected.manaSource = source;
            setResponseUUID(source.sourceId());
        }
        @Override protected boolean waitResponseOpen(){
            boolean ready=super.waitResponseOpen();Delivery expected=deliveryPrompt.get();
            boolean accepted=ready&&(expected==null||session!=null&&session.nativePromptId==expected.prompt&&session.running&&!session.owner.stopRequested&&!hasLeft());
            if(expected!=null){
                expected.accepted=accepted;
                if(accepted&&expected.undoBookmark!=null)session.undoBookmark=expected.undoBookmark;
                if(accepted&&expected.manaSource!=null)deliveredManaSource=expected.manaSource;
            }
            return accepted;
        }
        @Override protected void waitForResponse(Game game){
            super.waitForResponse(game);
            if(real(game)&&session.undoBookmark!=null){
                Integer bookmark=session.undoBookmark;session.undoBookmark=null;
                if(!game.hasEnded()&&!hasLeft()&&getStoredBookmark()==bookmark)game.undo(getId());
            }
        }
        @Override public void lookAtCards(String title,Card card,Game game){if(session!=null)session.observeLibraryLook(Collections.singletonList(card),game);super.lookAtCards(title,card,game);}
        @Override public void lookAtCards(Ability source,String title,Cards cards,Game game){if(session!=null)session.observeLibraryLook(cards.getCards(game),game);super.lookAtCards(source,title,cards,game);}
        @Override public boolean priority(Game game) {
            if (session == null || game != session.game || game.isSimulation() || game.inCheckPlayableState()) return super.priority(game);
            session.owner.timedPriorityPlayerId=getId();session.owner.priorityStartedAt=System.currentTimeMillis();
            if (session.priority.decide(session, this, game) && passWithManaPoolCheck(game)) {
                session.prompt = null;
                session.priority.passed();
                session.recordAction(map("type", "auto_priority", "reason", session.priority.reason()));
                session.publish();
                return false;
            }
            session.nativePriorityDepth++;
            try { return super.priority(game); }
            finally { session.nativePriorityDepth--; }
        }
        @Override public List<Integer> getMultiAmountWithIndividualConstraints(Outcome outcome,List<mage.util.MultiAmountMessage> messages,int totalMin,int totalMax,MultiAmountType type,Game game){
            if(!real(game))return super.getMultiAmountWithIndividualConstraints(outcome,messages,totalMin,totalMax,type,game);
            Map<String,Object> previous=combatDamageContext;
            try{combatDamageContext=CombatPromptMetadata.identify(session,messages,type.getTitle(),type.getHeader());}catch(RuntimeException optionalMetadataError){combatDamageContext=null;}
            try{return super.getMultiAmountWithIndividualConstraints(outcome,messages,totalMin,totalMax,type,game);}finally{combatDamageContext=previous;}
        }
        @Override public TriggeredAbility chooseTriggeredAbility(List<TriggeredAbility> abilities, Game game) { return session == null ? abilities.get(0) : session.orderTriggers(abilities, game); }
        Map<UUID,ActivatedManaAbilityImpl> usableManaAbilities(MageObject object,Game game) {
            Zone zone=game.getState().getZone(object.getId());
            return zone==null ? Collections.emptyMap() : getUseableManaAbilities(object,zone,game);
        }
        @Override protected boolean playManaHandling(Ability abilityToCast, ManaCost unpaid, String promptText, Game game) {
            try { return super.playManaHandling(abilityToCast, unpaid, promptText, game); }
            finally { deliveredManaSource = null; }
        }
        @Override protected void playManaAbilities(UUID objectId, Ability abilityToCast, ManaCost unpaid, Game game) {
            NativeManaPayment.SourceSelection selection = deliveredManaSource;
            deliveredManaSource = null;
            NativeManaPayment.SourceSelection previous = paymentManaSource;
            UUID previousAbility = requestedManaAbility;
            paymentManaSource = selection != null && objectId.equals(selection.sourceId()) ? selection : null;
            requestedManaAbility = paymentManaSource == null ? null : paymentManaSource.abilityId();
            try { super.playManaAbilities(objectId, abilityToCast, unpaid, game); }
            finally { paymentManaSource = previous; requestedManaAbility = previousAbility; }
        }
        @Override protected Map<UUID, ActivatedManaAbilityImpl> getUseableManaAbilities(MageObject object, Zone zone, Game game) {
            Map<UUID, ActivatedManaAbilityImpl> nativeAbilities = super.getUseableManaAbilities(object, zone, game);
            if (requestedManaAbility == null || !real(game) || !paymentManaSource.sourceId().equals(object.getId())) return nativeAbilities;
            // The native payment path still checks phase, availability and costs. Limit only its
            // first source lookup to the user's exact offered ability before native auto-selection.
            UUID id = requestedManaAbility;
            requestedManaAbility = null;
            nativeAbilities.keySet().retainAll(Collections.singleton(id));
            return nativeAbilities;
        }
        @Override public boolean activateAbility(ActivatedAbility ability,Game game) {
            UUID previous=activeManaSource;
            Ability previousNative=activeNativeAbility;if(real(game))activeNativeAbility=ability;
            String previousKind=pendingActionKind;UUID previousSource=pendingActionSource;
            if(ability.isManaAbility()) activeManaSource=ability.getSourceId();
            if(real(game)&&!ability.isManaAbility()){pendingActionKind="activation";pendingActionSource=ability.getSourceId();}
            try { return super.activateAbility(ability,game); }
            finally { activeManaSource=previous;activeNativeAbility=previousNative;pendingActionKind=previousKind;pendingActionSource=previousSource; }
        }
        @Override public boolean cast(SpellAbility ability,Game game,boolean noMana,ApprovingObject approvingObject){
            String previous=pendingActionKind;UUID previousSource=pendingActionSource;
            Ability previousNative=activeNativeAbility;if(real(game))activeNativeAbility=ability;
            if(real(game)){pendingActionKind="cast";pendingActionSource=ability.getSourceId();}
            try{return super.cast(ability,game,noMana,approvingObject);}finally{activeNativeAbility=previousNative;pendingActionKind=previous;pendingActionSource=previousSource;}
        }
        @Override public boolean choose(Outcome outcome,Choice choice,Game game) {
            boolean previous=choosingManaColor;
            choosingManaColor=outcome==Outcome.PutManaInPool;
            try {
                NativeManaPayment.SourceSelection selection = paymentManaSource;
                if (real(game) && canRespond() && selection != null && selection.color() != null
                        && choosingManaColor && choice.isManaColorChoice() && !choice.isKeyChoice()
                        && activeNativeAbility != null && selection.abilityId().equals(activeNativeAbility.getId())
                        && choice.getChoices().contains(selection.color())) {
                    // Follow the native choice lifecycle with the answer already picked in the payment window.
                    paymentManaSource = null;
                    choice.onChooseStart(game, getId());
                    choice.setChoice(selection.color());
                    choice.onChooseEnd(game, getId(), selection.color());
                    return true;
                }
                return super.choose(outcome,choice,game);
            }
            finally { choosingManaColor=previous; }
        }
        boolean real(Game game){return session!=null&&game==session.game&&!game.isSimulation()&&!game.inCheckPlayableState();}
        boolean withTarget(Target target,Cards cards,Ability source,Game game,java.util.function.Supplier<Boolean> operation){
            if(!real(game))return operation.get();
            Target previous=activeTarget;Cards previousCards=activeTargetCards;Ability previousSource=activeTargetSource;
            activeTarget=target;activeTargetCards=cards;activeTargetSource=source;
            try{return session.promptContext.contexts.isEmpty()
                ?session.promptContext.run("select","select",null,null,source,operation):operation.get();}
            finally{activeTarget=previous;activeTargetCards=previousCards;activeTargetSource=previousSource;}
        }
        @Override public boolean choose(Outcome outcome,Target target,Ability source,Game game,Map<String,Serializable> options){return withTarget(target,null,source,game,()->super.choose(outcome,target,source,game,options));}
        @Override public boolean chooseTarget(Outcome outcome,Target target,Ability source,Game game){return withTarget(target,null,source,game,()->super.chooseTarget(outcome,target,source,game));}
        @Override public boolean choose(Outcome outcome,Cards cards,mage.target.TargetCard target,Ability source,Game game){return withTarget(target,cards,source,game,()->super.choose(outcome,cards,target,source,game));}
        @Override public boolean chooseTarget(Outcome outcome,Cards cards,mage.target.TargetCard target,Ability source,Game game){return withTarget(target,cards,source,game,()->super.chooseTarget(outcome,cards,target,source,game));}
        @Override public boolean scry(int amount,Ability source,Game game){
            if(!real(game))return super.scry(amount,source,game);
            return session.promptContext.run("scry","select","bottom","top",source,()->super.scry(amount,source,game));
        }
        @Override public Player.SurveilResult doSurveil(int amount,Ability source,Game game){
            if(!real(game))return super.doSurveil(amount,source,game);
            return session.promptContext.run("surveil","select","graveyard","top",source,()->super.doSurveil(amount,source,game));
        }
        @Override public boolean putCardsOnTopOfLibrary(Cards cards,Game game,Ability source,boolean anyOrder){
            if(!real(game)||!anyOrder)return super.putCardsOnTopOfLibrary(cards,game,source,anyOrder);
            return session.promptContext.run(null,"order","top",null,source,()->super.putCardsOnTopOfLibrary(cards,game,source,anyOrder));
        }
        @Override public boolean putCardsOnBottomOfLibrary(Cards cards,Game game,Ability source,boolean anyOrder){
            if(!real(game)||!anyOrder)return super.putCardsOnBottomOfLibrary(cards,game,source,anyOrder);
            return session.promptContext.run(null,"order","bottom",null,source,()->super.putCardsOnBottomOfLibrary(cards,game,source,anyOrder));
        }
        @Override protected void selectCombatGroup(UUID defenderId,UUID blockerId,Game game){
            UUID previous=selectedBlockerId;selectedBlockerId=blockerId;
            try{super.selectCombatGroup(defenderId,blockerId,game);}finally{selectedBlockerId=previous;}
        }
    }
}
