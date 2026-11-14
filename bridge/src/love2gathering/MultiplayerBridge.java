package love2gathering;

import com.google.gson.*;
import com.sun.net.httpserver.HttpExchange;
import mage.game.CommanderFreeForAllType;
import mage.game.FreeForAllType;
import mage.game.TwoPlayerDuelType;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;

/** Authenticated loopback coordinator boundary. Room invite authentication belongs to the gateway. */
final class MultiplayerBridge {
    static final Map<String,EngineBridge.Session> GAMES = new ConcurrentHashMap<>();
    static final Map<String,DraftSession> DRAFTS = new ConcurrentHashMap<>();
    static final Map<String,String> RESULT_GAMES = new ConcurrentHashMap<>();
    static final Object START_LOCK = new Object();
    static final Map<String,StartReceipt> GAME_STARTS = new LinkedHashMap<>(), DRAFT_STARTS = new LinkedHashMap<>();
    static final Map<String,StartReceipt> ROUND_RECEIPTS = new ConcurrentHashMap<>();
    static final int MAX_START_RECEIPTS = 4096;
    static final class StartReceipt {
        final String fingerprint, id;
        final Map<String,Object> response;
        StartReceipt(String fingerprint, String id, Map<String,Object> response) { this.fingerprint = fingerprint; this.id = id; this.response = response; }
    }
    static JsonElement canonical(JsonElement value) {
        if (value.isJsonObject()) {
            JsonObject result = new JsonObject(); TreeSet<String> keys = new TreeSet<>(value.getAsJsonObject().keySet());
            for (String key : keys) result.add(key, canonical(value.getAsJsonObject().get(key))); return result;
        }
        if (value.isJsonArray()) { JsonArray result = new JsonArray(); for (JsonElement entry : value.getAsJsonArray()) result.add(canonical(entry)); return result; }
        return value;
    }
    static String fingerprint(JsonObject body) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(EngineBridge.JSON.toJson(canonical(body)).getBytes(StandardCharsets.UTF_8))); }
        catch (java.security.NoSuchAlgorithmException impossible) { throw new AssertionError(impossible); }
    }
    static Map<String,Object> startOnce(boolean game, JsonObject body, Supplier<Map<String,Object>> create) {
        if (!body.has("idempotencyKey")) return create.get();
        String key = EngineBridge.text(body, "idempotencyKey", "");
        if (key.isBlank() || key.length() > 200) throw new IllegalArgumentException("Invalid start idempotency key");
        String fingerprint = fingerprint(body);
        Map<String,StartReceipt> receipts = game ? GAME_STARTS : DRAFT_STARTS;
        synchronized (START_LOCK) {
            StartReceipt previous = receipts.get(key);
            if (previous != null) {
                if (previous.fingerprint == null) throw new IllegalArgumentException("This idempotent start has already been closed");
                if (!previous.fingerprint.equals(fingerprint)) throw new IllegalArgumentException("Start idempotency key has different input");
                if (!(game ? GAMES.containsKey(previous.id) : DRAFTS.containsKey(previous.id))) throw new IllegalArgumentException("This idempotent start has already been closed");
                return new LinkedHashMap<>(previous.response);
            }
            if (receipts.size() >= MAX_START_RECEIPTS) throw new IllegalArgumentException("Coordinator start receipt resource limit reached");
            Map<String,Object> response = create.get();
            receipts.put(key, new StartReceipt(fingerprint, String.valueOf(response.get(game ? "gameId" : "draftId")), response));
            return response;
        }
    }

    static String stopIdentity(boolean game, JsonObject body, Map<String,String> parameters) {
        String field = game ? "gameId" : "draftId", id = EngineBridge.text(body, field, parameters.getOrDefault(field, ""));
        String key = EngineBridge.text(body, "idempotencyKey", parameters.getOrDefault("idempotencyKey", ""));
        if (key.isEmpty()) { if (id.isBlank()) throw new IllegalArgumentException("Missing " + field); return id; }
        if (key.isBlank() || key.length() > 200) throw new IllegalArgumentException("Invalid start idempotency key");
        synchronized (START_LOCK) {
            Map<String,StartReceipt> receipts = game ? GAME_STARTS : DRAFT_STARTS;
            StartReceipt previous = receipts.get(key);
            if (previous == null) {
                if (!id.isEmpty()) throw new IllegalArgumentException("Unknown start idempotency key");
                if (receipts.size() >= MAX_START_RECEIPTS) throw new IllegalArgumentException("Coordinator start receipt resource limit reached");
                // A close can beat an in-flight start request to this server.
                // Tombstone the key so that late request cannot create a game.
                receipts.put(key, new StartReceipt(null, null, Collections.emptyMap())); return null;
            }
            if (!id.isEmpty() && !id.equals(previous.id)) throw new IllegalArgumentException("Stop identity does not match its idempotent start");
            return previous.id;
        }
    }
    static Map<String,Object> nextRoundOnce(DraftSession draft, JsonObject body) {
        if (!body.has("idempotencyKey")) return draft.nextRound();
        String supplied = EngineBridge.text(body, "idempotencyKey", "");
        if (supplied.isBlank() || supplied.length() > 200) throw new IllegalArgumentException("Invalid round idempotency key");
        String key = draft.id + ":" + supplied, fingerprint = fingerprint(body);
        synchronized (START_LOCK) {
            StartReceipt previous = ROUND_RECEIPTS.get(key);
            if (previous != null) {
                if (!previous.fingerprint.equals(fingerprint)) throw new IllegalArgumentException("Round idempotency key has different input");
                return new LinkedHashMap<>(previous.response);
            }
            if (ROUND_RECEIPTS.size() >= MAX_START_RECEIPTS) throw new IllegalArgumentException("Coordinator round receipt resource limit reached");
            Map<String,Object> response = draft.nextRound();
            ROUND_RECEIPTS.put(key, new StartReceipt(fingerprint, draft.id, response)); return response;
        }
    }
    static void authorize(HttpExchange exchange) {
        String token = System.getenv("LOVE2GATHERING_COORDINATOR_TOKEN");
        String header = exchange.getRequestHeaders().getFirst("Authorization");
        if (!exchange.getRemoteAddress().getAddress().isLoopbackAddress() || token == null || token.length() < 24 || header == null
                || !MessageDigest.isEqual(("Bearer " + token).getBytes(StandardCharsets.UTF_8), header.getBytes(StandardCharsets.UTF_8)))
            throw new SecurityException("Room coordinator authentication required");
    }
    static Map<String,String> query(HttpExchange exchange) {
        Map<String,String> result = new HashMap<>(); String source = exchange.getRequestURI().getRawQuery();
        if (source != null) for (String part : source.split("&")) {
            String[] pair = part.split("=", 2); result.put(URLDecoder.decode(pair[0], StandardCharsets.UTF_8), pair.length > 1 ? URLDecoder.decode(pair[1], StandardCharsets.UTF_8) : "");
        }
        return result;
    }
    static String required(JsonObject body, Map<String,String> query, String key) {
        String value = EngineBridge.text(body, key, query.getOrDefault(key, ""));
        if (value.isBlank()) throw new IllegalArgumentException("Missing " + key); return value;
    }
    static EngineBridge.Session game(String id) { EngineBridge.Session game = GAMES.get(id); if (game == null) throw new IllegalArgumentException("Unknown room game"); return game; }
    static DraftSession draft(String id) { DraftSession draft = DRAFTS.get(id); if (draft == null) throw new IllegalArgumentException("Unknown draft"); return draft; }
    static Map<String,Object> capabilities() {
        return EngineBridge.map("protocol", 1, "coordinatorAuthentication", "bearer", "formats", Arrays.asList("Modern", "Standard", "Pioneer", "Commander", "Limited"),
                "games", Arrays.asList(EngineBridge.map("format", "Commander", "minPlayers", 2, "maxPlayers", new CommanderFreeForAllType().getMaxPlayers()),
                        EngineBridge.map("format", "Limited", "minPlayers", 2, "maxPlayers", new FreeForAllType().getMaxPlayers()),
                        EngineBridge.map("format", "Constructed", "minPlayers", 2, "maxPlayers", new TwoPlayerDuelType().getMaxPlayers())),
                "draft", DraftSession.options(), "recordings", "designated-host-perspective");
    }
    static Object request(HttpExchange exchange, String path, String method) throws Exception {
        authorize(exchange);
        Map<String,String> parameters = query(exchange);
        JsonObject body = method.equals("POST") ? EngineBridge.readBody(exchange) : new JsonObject();
        if (path.equals("/multiplayer/capabilities") && method.equals("GET")) return capabilities();
        if (path.equals("/multiplayer/start") && method.equals("POST")) return startOnce(true, body, () -> {
            if (body.has("draftId")) {
                DraftSession source = draft(required(body, parameters, "draftId"));
                String pairingId = required(body, parameters, "pairingId");
                @SuppressWarnings("unchecked") List<Map<String,Object>> pairs = (List<Map<String,Object>>)source.pairings().get("matches");
                Map<String,Object> pair = pairs.stream().filter(value -> pairingId.equals(value.get("id"))).findFirst().orElseThrow(() -> new IllegalArgumentException("Unknown current draft pairing"));
                if (Boolean.TRUE.equals(pair.get("finished")) || Boolean.TRUE.equals(pair.get("bye"))) throw new IllegalArgumentException("Draft pairing is already finished");
                @SuppressWarnings("unchecked") List<String> expected = (List<String>)pair.get("seatIds");
                Set<String> actual = new HashSet<>();
                if (!body.has("seats") || !body.get("seats").isJsonArray() || body.getAsJsonArray("seats").size() != expected.size()) throw new IllegalArgumentException("Draft game must contain its paired seats");
                for (JsonElement value : body.getAsJsonArray("seats")) {
                    JsonObject seat = value.getAsJsonObject(); String id = EngineBridge.text(seat, "seatId", ""); actual.add(id);
                    seat.add("deck", source.deckSource(id));
                }
                if (!actual.equals(new HashSet<>(expected))) throw new IllegalArgumentException("Draft game must contain its paired seats");
                body.addProperty("format", "Limited");
            }
            EngineBridge.Session session = new EngineBridge.Session(body, true);
            for (EngineBridge.Session view : session.perspectives) view.prepareRecording();
            String id = session.game.getId().toString(); GAMES.put(id, session); session.start();
            return EngineBridge.map("gameId", id, "seats", session.participants(), "running", true);
        });
        if (path.startsWith("/multiplayer/")) {
            if (path.equals("/multiplayer/stop") && method.equals("POST")) {
                String gameId = stopIdentity(true, body, parameters);
                EngineBridge.Session closing = gameId == null ? null : GAMES.get(gameId);
                if (closing == null) return EngineBridge.map("gameId", gameId, "running", false, "alreadyStopped", true);
                closing.stop(); Map<String,Object> result = closing.publicResult(); GAMES.remove(gameId, closing); return result;
            }
            String gameId = required(body, parameters, "gameId");
            EngineBridge.Session session = game(gameId);
            if (path.equals("/multiplayer/result") && method.equals("GET")) return session.publicResult();
            EngineBridge.Session view = session.perspective(required(body, parameters, "playerId"));
            if (path.equals("/multiplayer/state") && method.equals("GET")) return view.state();
            if (path.equals("/multiplayer/action") && method.equals("POST")) { view.action(body); return view.state(); }
            if (path.equals("/multiplayer/priority") && method.equals("POST")) { view.priorityCommand(body); return view.state(); }
            if (path.equals("/multiplayer/replay/save") && method.equals("POST")) {
                if (view.recorder == null) throw new SecurityException("Room replay is saved by the host");
                view.recordAction(EngineBridge.map("type", "save_replay")); boolean saved = view.recorder.flush(5000);
                Map<String,Object> result = new LinkedHashMap<>(view.recorder.state()); result.put("saved", saved); result.put("savedSequence", view.recorder.savedSequence); return result;
            }
            throw new IllegalArgumentException("Unknown room-game operation");
        }
        if (path.equals("/draft/options") && method.equals("GET")) return DraftSession.options();
        if (path.equals("/draft/start") && method.equals("POST")) return startOnce(false, body, () -> {
            if (!body.has("seats") || !body.get("seats").isJsonArray()) throw new IllegalArgumentException("Draft seats required");
            List<RoomSeat> seats = new ArrayList<>(); Set<String> seen = new HashSet<>();
            for (JsonElement value : body.getAsJsonArray("seats")) { RoomSeat seat = new RoomSeat(value.getAsJsonObject(), seats.size()); if (!seen.add(seat.seatId)) throw new IllegalArgumentException("Duplicate seat ID"); seats.add(seat); }
            DraftSession session = new DraftSession(body.has("config") ? body.getAsJsonObject("config") : body, seats);
            DRAFTS.put(session.id, session); session.start(); return EngineBridge.map("draftId", session.id, "status", "initializing");
        });
        if (path.equals("/draft/stop") && method.equals("POST")) {
            String draftId = stopIdentity(false, body, parameters);
            if (draftId == null) return EngineBridge.map("ok", true, "alreadyStopped", true);
            for (Map.Entry<String,EngineBridge.Session> entry : GAMES.entrySet()) if (draftId.equals(EngineBridge.text(entry.getValue().request, "draftId", ""))) { entry.getValue().stop(); GAMES.remove(entry.getKey(), entry.getValue()); }
            DraftSession closing = DRAFTS.get(draftId); if (closing != null) { closing.stop(); DRAFTS.remove(draftId, closing); }
            RESULT_GAMES.keySet().removeIf(key -> key.startsWith(draftId + ":"));
            ROUND_RECEIPTS.keySet().removeIf(key -> key.startsWith(draftId + ":"));
            return EngineBridge.map("ok", true, "alreadyStopped", closing == null);
        }
        String draftId = required(body, parameters, "draftId");
        DraftSession draft = draft(draftId);
        if (path.equals("/draft/pairings") && method.equals("GET")) return draft.pairings();
        if (path.equals("/draft/next-round") && method.equals("POST")) return nextRoundOnce(draft, body);
        if (path.equals("/draft/deck-source") && method.equals("GET")) return draft.deckSource(required(body, parameters, "seatId"));
        if (path.equals("/draft/result") && method.equals("POST")) {
            String pairingId = required(body, parameters, "pairingId"), gameId = required(body, parameters, "gameId");
            synchronized (draft) {
                String key = draft.id + ":" + pairingId, previous = RESULT_GAMES.get(key);
                if (previous != null) {
                    if (!previous.equals(gameId)) throw new IllegalArgumentException("Pairing result is already bound to another native game");
                    return draft.pairings();
                }
                // No external winner is accepted: only this bound game's
                // completed native result can award tournament points.
                EngineBridge.Session played = game(gameId); Map<String,Object> result = played.publicResult();
                if (!draft.id.equals(EngineBridge.text(played.request, "draftId", "")) || !pairingId.equals(EngineBridge.text(played.request, "pairingId", "")))
                    throw new IllegalArgumentException("Native game does not belong to this draft pairing");
                if (!Boolean.FALSE.equals(result.get("running")) || result.get("error") != null || played.stopRequested) throw new IllegalArgumentException("A completed native game is required");
                @SuppressWarnings("unchecked") List<String> winners = (List<String>)result.get("winnerSeatIds");
                draft.recordResult(pairingId, winners.size() == 1 ? winners.get(0) : null);
                RESULT_GAMES.put(key, gameId); return draft.pairings();
            }
        }
        String seatId = required(body, parameters, "seatId");
        if (path.equals("/draft/state") && method.equals("GET")) return draft.state(seatId);
        if (path.equals("/draft/pick") && method.equals("POST")) return draft.pick(seatId, body);
        if (path.equals("/draft/forfeit") && method.equals("POST")) return draft.forfeit(seatId);
        if (path.equals("/draft/deck") && method.equals("POST")) return draft.submitDeck(seatId, body);
        throw new IllegalArgumentException("Unknown native draft operation");
    }
    static void stopAll() {
        for (EngineBridge.Session session : GAMES.values()) session.stop();
        for (DraftSession session : DRAFTS.values()) session.stop();
    }
}
