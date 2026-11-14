package love2gathering;

import com.google.gson.*;
import mage.cards.*;
import mage.cards.decks.*;
import mage.cards.repository.CardScanner;
import mage.constants.RangeOfInfluence;
import mage.deck.Limited;
import mage.game.TwoPlayerMatch;
import mage.game.draft.*;
import mage.game.match.*;
import mage.game.tournament.*;
import mage.player.ai.ComputerPlayer;
import mage.player.ai.ComputerPlayer7;
import mage.player.human.HumanPlayer;
import mage.players.Player;
import mage.players.PlayerType;
import mage.tournament.*;
import mage.tournament.cubes.CubeFromDeck;
import mage.util.ClassScanner;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;
import java.util.stream.Collectors;
import static love2gathering.EngineBridge.map;
import static love2gathering.EngineBridge.text;

/** Native draft/tournament transport. Packs, rotations, bots, timers and legality belong to XMage. */
final class DraftSession {
    final String id = UUID.randomUUID().toString();
    final String profile, pairing;
    final List<RoomSeat> seats;
    final Map<String, Player> players = new LinkedHashMap<>();
    final Map<UUID, String> seatByPlayer = new LinkedHashMap<>();
    final Map<String, Deck> submitted = new ConcurrentHashMap<>();
    final Set<String> forfeited = ConcurrentHashMap.newKeySet();
    final Draft draft;
    final NativeLock lock;
    final Tournament tournament;
    volatile String status = "initializing", error;
    volatile Thread worker;
    volatile Thread forfeitWorker;
    volatile boolean stopped;
    static volatile boolean repositoryReady;
    private static Map<String, Class<? extends DraftCube>> cubeClasses;

    interface NativeLock { <T> T locked(Supplier<T> operation); void closeNative(); }
    static final class Standard extends BoosterDraft implements NativeLock {
        Standard(DraftOptions o,List<ExpansionSet> s){super(o,s);}
        public <T>T locked(Supplier<T> fn){synchronized(players){return fn.get();}}
        public void closeNative(){setAbort(true);picksCheckDone();boosterSendingEndDraft();}
    }
    static final class RandomDraft extends RandomBoosterDraft implements NativeLock {
        RandomDraft(DraftOptions o,List<ExpansionSet> s){super(o,s);}
        public <T>T locked(Supplier<T> fn){synchronized(players){return fn.get();}}
        public void closeNative(){setAbort(true);picksCheckDone();boosterSendingEndDraft();}
    }
    static final class Swiss extends BoosterDraftSwissTournament {
        Swiss(TournamentOptions o){super(o);}
        Round nextNativeRound(){return createRoundSwiss();}
        int activeCount(){return getActivePlayers().size();}
    }
    static final class Elimination extends BoosterDraftEliminationTournament {
        Elimination(TournamentOptions o){super(o);}
        Round nextNativeRound(){return createRoundRandom();}
        int activeCount(){return getActivePlayers().size();}
    }
    /** Accepted result of an already finished engine game, mapped back to draft player IDs. */
    static final class ResultMatch extends TwoPlayerMatch {
        ResultMatch(MatchOptions o){super(o);}
        void finishDraw(){addDraw();endTime=new Date();}
    }

    DraftSession(JsonObject config,List<RoomSeat> members) {
        profile=text(config,"profile","booster");pairing=text(config,"pairing","swiss");
        if(!Arrays.asList("booster","random","cube").contains(profile))throw new IllegalArgumentException("Choose native booster, random or cube draft");
        if(!Arrays.asList("swiss","elimination").contains(pairing))throw new IllegalArgumentException("Choose Swiss or single elimination");
        TournamentType type=type(profile,pairing);
        if(members.size()<type.getMinPlayers()||members.size()>type.getMaxPlayers())throw new IllegalArgumentException("Native draft supports "+type.getMinPlayers()+" to "+type.getMaxPlayers()+" seats");
        seats=new ArrayList<>(members);
        DraftOptions opts=new DraftOptions();opts.setNumberBoosters(type.getNumBoosters());
        try{opts.setTiming(DraftOptions.TimingOption.valueOf(text(config,"timing","REGULAR")));}
        catch(IllegalArgumentException ex){throw new IllegalArgumentException("Choose a supported native pick timer");}
        if(opts.getTiming()==DraftOptions.TimingOption.NONE)throw new IllegalArgumentException("Choose beginner, regular or professional timing");
        List<ExpansionSet> sets=new ArrayList<>();
        if(profile.equals("cube")) {
            DraftCube cube;
            if(config.has("customCube")&&config.get("customCube").isJsonObject()) {
                Deck custom=EngineBridge.deck(config.getAsJsonObject("customCube"));
                if(custom.getCards().size()>10000)throw new IllegalArgumentException("Custom cube exceeds the 10000-card application resource bound");
                cube=new CubeFromDeck(custom);
            } else {
                Class<? extends DraftCube> clazz=cubes().get(text(config,"cubeCode","VintageCube"));
                if(clazz==null)throw new IllegalArgumentException("Choose a supplied native cube or a custom cube list");
                try{cube=clazz.getConstructor().newInstance();}catch(Exception ex){throw new IllegalArgumentException("Cannot create native cube",ex);}
            }
            cube.validateData();opts.setDraftCube(cube);
        } else {
            JsonArray selected=config.has(profile.equals("random")?"randomSets":"sets")?config.getAsJsonArray(profile.equals("random")?"randomSets":"sets"):null;
            if(profile.equals("random")&&(selected==null||selected.isEmpty())) {
                Sets.getInstance().values().stream().filter(ExpansionSet::hasBoosters).sorted(Comparator.comparing(ExpansionSet::getCode)).forEach(sets::add);
            } else {
                if(selected==null||selected.isEmpty())throw new IllegalArgumentException("Choose a native booster set for every pack");
                if(profile.equals("booster")&&selected.size()!=opts.getNumberBoosters())throw new IllegalArgumentException("Choose "+opts.getNumberBoosters()+" booster sets in pack order");
                for(JsonElement el:selected){ExpansionSet set=Sets.findSet(el.getAsString().toUpperCase(Locale.ROOT));if(set==null||!set.hasBoosters())throw new IllegalArgumentException("Set has no native booster: "+el.getAsString());sets.add(set);}
            }
            sets.forEach(s->opts.getSetCodes().add(s.getCode()));
        }
        draft=profile.equals("random")?new RandomDraft(opts,sets):new Standard(opts,sets);lock=(NativeLock)draft;
        draft.setTableId(UUID.randomUUID());
        TournamentOptions tournamentOptions=new TournamentOptions("Room draft","Two Player Duel",false);
        tournamentOptions.setLimitedOptions(opts);tournamentOptions.setNumberRounds(config.has("rounds")?config.get("rounds").getAsInt():3);
        if(tournamentOptions.getNumberRounds()<1||tournamentOptions.getNumberRounds()>16)throw new IllegalArgumentException("Choose 1 to 16 Swiss rounds");
        tournamentOptions.getMatchOptions().setDeckType("Limited");tournamentOptions.getMatchOptions().setLimited(true);tournamentOptions.getMatchOptions().setWinsNeeded(1);
        tournament=pairing.equals("swiss")?new Swiss(tournamentOptions):new Elimination(tournamentOptions);tournament.setTournamentType(type);
        for(RoomSeat member:seats){
            if(players.containsKey(member.seatId))throw new IllegalArgumentException("Duplicate draft seat ID");
            Player p=member.human?new HumanPlayer(member.name,RangeOfInfluence.ALL,1):new ComputerPlayer7(member.name,RangeOfInfluence.ALL,1);
            players.put(member.seatId,p);seatByPlayer.put(p.getId(),member.seatId);draft.addPlayer(p);draft.getPlayer(p.getId()).setJoined();
            tournament.addPlayer(p,member.human?PlayerType.HUMAN:PlayerType.COMPUTER_MAD);
        }
    }

    static TournamentType type(String profile,String pairing){
        if(profile.equals("random"))return pairing.equals("swiss")?new RandomBoosterDraftSwissTournamentType():new RandomBoosterDraftEliminationTournamentType();
        if(profile.equals("cube"))return pairing.equals("swiss")?new BoosterDraftSwissCubeTournamentType():new BoosterDraftEliminationCubeTournamentType();
        return pairing.equals("swiss")?new BoosterDraftSwissTournamentType():new BoosterDraftEliminationTournamentType();
    }
    static synchronized Map<String,Class<? extends DraftCube>> cubes(){
        if(cubeClasses==null){
            Map<String,Class<? extends DraftCube>> found=new TreeMap<>();
            for(Class<?> clazz:ClassScanner.findClasses(DraftSession.class.getClassLoader(),Collections.singletonList("mage.tournament.cubes"),DraftCube.class)){
                if(clazz==CubeFromDeck.class)continue;
                try{DraftCube c=(DraftCube)clazz.getConstructor().newInstance();if(!c.getCubeCards().isEmpty())found.put(c.getCode(),clazz.asSubclass(DraftCube.class));}catch(Exception ignored){}
            }
            cubeClasses=Collections.unmodifiableMap(found);
        }
        return cubeClasses;
    }
    static Map<String,Object> options(){
        List<Map<String,Object>> profiles=new ArrayList<>();
        for(String id:Arrays.asList("booster","random","cube")){TournamentType t=type(id,"swiss");profiles.add(map("id",id,"label",id.equals("booster")?"Booster draft":id.equals("random")?"Random booster draft":"Cube draft","minPlayers",t.getMinPlayers(),"maxPlayers",t.getMaxPlayers(),"packCount",t.getNumBoosters(),"minDeckSize",new Limited().getDeckMinSize()));}
        List<Map<String,Object>> cubeOptions=new ArrayList<>();
        cubes().forEach((code,clazz)->{try{DraftCube c=clazz.getConstructor().newInstance();cubeOptions.add(map("code",code,"name",c.getName(),"size",c.getCubeCards().size()));}catch(Exception ignored){}});
        List<Map<String,Object>> timings=Arrays.stream(DraftOptions.TimingOption.values()).filter(t->t!=DraftOptions.TimingOption.NONE).map(t->map("id",t.name(),"label",t.getName())).collect(Collectors.toList());
        return map("profiles",profiles,"pairings",Arrays.asList(map("id","swiss","label","Swiss"),map("id","elimination","label","Single elimination")),
            "sets",Sets.getInstance().values().stream().filter(ExpansionSet::hasBoosters).sorted(Comparator.comparing(ExpansionSet::getName)).map(s->map("code",s.getCode(),"name",s.getName())).collect(Collectors.toList()),
            "cubes",cubeOptions,"customCube",true,"timings",timings,"basicLands",basics(),"deckProfiles",Collections.singletonList(map("id","Limited","label","Limited","minDeckSize",new Limited().getDeckMinSize())),"repositoryReady",repositoryReady);
    }
    static List<Map<String,Object>> basics(){
        String[] names={"Plains","Island","Swamp","Mountain","Forest"},symbols={"W","U","B","R","G"};List<Map<String,Object>> result=new ArrayList<>();
        for(int i=0;i<names.length;i++)if(DeckValidator.MAIN_BASIC_LAND_NAMES.contains(names[i]))result.add(map("name",names[i],"manaSymbol",symbols[i]));return result;
    }
    static synchronized void ensureRepository(){if(!repositoryReady){CardScanner.scan();repositoryReady=true;}}

    synchronized void start(){
        if(worker!=null)throw new IllegalArgumentException("Draft already started");
        forfeitWorker=new Thread(()->{
            while(!stopped&&Arrays.asList("initializing","drafting").contains(status)){
                for(String seatId:forfeited)synchronized(draft){draft.autoPick(players.get(seatId).getId());}
                try{Thread.sleep(50);}catch(InterruptedException ex){return;}
            }
        },"TOURNEY_DRAFT_FORFEIT "+id);forfeitWorker.setDaemon(true);forfeitWorker.start();
        worker=new Thread(()->{try{ensureRepository();if(stopped)return;status="drafting";draft.setStarted();draft.start();
            if(stopped||draft.isAbort()){status="aborted";return;}
            synchronized(this){status="building";for(RoomSeat seat:seats)if(!seat.human||forfeited.contains(seat.seatId))buildBotDeck(seat.seatId);updateReady();}
        }catch(Throwable ex){error=ex.toString();status="failed";lock.closeNative();ex.printStackTrace();}},"TOURNEY_DRAFT "+id);
        worker.setDaemon(true);worker.start();
    }
    synchronized void stop(){stopped=true;status="aborted";lock.closeNative();if(worker!=null)worker.interrupt();if(forfeitWorker!=null)forfeitWorker.interrupt();}
    synchronized Map<String,Object> forfeit(String seatId){
        requireSeat(seatId);forfeited.add(seatId);
        if(status.equals("building")||status.equals("ready")){buildBotDeck(seatId);updateReady();}
        return state(seatId);
    }
    private void buildBotDeck(String seatId){
        List<Card> pool=draft.getPlayerSnapshot(players.get(seatId).getId()).getPicks();
        Deck built=ComputerPlayer.buildDeck(new Limited().getDeckMinSize(),new ArrayList<>(pool),RateCard.chooseDeckColors(pool));
        validatePool(built,pool);submitted.put(seatId,built);tournament.submitDeck(players.get(seatId).getId(),built);
    }
    String token(DraftPlayerSnapshot snapshot){return id+":"+snapshot.getBoosterNum()+":"+snapshot.getCardNum();}
    Player requireSeat(String seatId){Player p=players.get(seatId);if(p==null)throw new IllegalArgumentException("Unknown draft seat");return p;}
    Map<String,Object> state(String seatId){
        Player player=requireSeat(seatId);
        return lock.locked(()->{DraftPlayerSnapshot own=draft.getPlayerSnapshot(player.getId());
            List<Map<String,Object>> publicSeats=new ArrayList<>();
            for(RoomSeat seat:seats){DraftPlayerSnapshot s=draft.getPlayerSnapshot(players.get(seat.seatId).getId());publicSeats.add(map("id",seat.seatId,"seatId",seat.seatId,"playerId",players.get(seat.seatId).getId().toString(),"name",seat.name,"profile",seat.profile.deepCopy(),"human",seat.human&&!forfeited.contains(seat.seatId),"forfeited",forfeited.contains(seat.seatId),"picking",s.isPicking(),"poolCount",s.getPicks().size(),"ready",submitted.containsKey(seat.seatId)));}
            DraftPlayer nativePlayer=draft.getPlayer(player.getId());
            return map("id",id,"status",status,"error",error,"profile",profile,"pairing",pairing,"players",publicSeats,"packNumber",own.getBoosterNum(),"pickNumber",own.getCardNum(),"packCount",draft.getNumberBoosters(),
                "pack",status.equals("drafting")&&own.isPicking()?cards(own.getBooster()):Collections.emptyList(),"pool",cards(own.getPicks()),"pickToken",own.isPicking()?token(own):null,"secondsRemaining",own.isPicking()?draft.getPickTimeout(player.getId()):0,"deadline",nativePlayer.getPickDeadline(),"minDeckSize",new Limited().getDeckMinSize(),"basicLands",basics(),"deck",submitted.containsKey(seatId)?deckJson(submitted.get(seatId)):null,"selection",submitted.containsKey(seatId)?selection(submitted.get(seatId),own.getPicks()):null);
        });
    }
    Map<String,Object> pick(String seatId,JsonObject request){
        Player player=requireSeat(seatId);if(!player.isHuman()||forfeited.contains(seatId))throw new IllegalArgumentException("Bot draft picks are owned by XMage");
        UUID cardId=lock.locked(()->{DraftPlayerSnapshot snapshot=draft.getPlayerSnapshot(player.getId());
            if(!status.equals("drafting")||!snapshot.isPicking()||!token(snapshot).equals(text(request,"pickToken","")))throw new IllegalArgumentException("Outdated draft pick; refresh the current pack");
            UUID card;try{card=UUID.fromString(text(request,"cardId",""));}catch(Exception ex){throw new IllegalArgumentException("Choose a card in your current pack");}
            return card;
        });
        // Native addPick rechecks membership/picking under the native lock, then
        // notifies its draft thread after releasing that lock. Do not hold it
        // across the call: picksWait takes the notification lock first.
        if(draft.addPick(player.getId(),cardId,null)==null)throw new IllegalArgumentException("Card is not in your current pack");
        return state(seatId);
    }
    synchronized Map<String,Object> submitDeck(String seatId,JsonObject request){
        Player player=requireSeat(seatId);if(!Arrays.asList("building","ready").contains(status))throw new IllegalArgumentException("Finish drafting before building decks");
        if(forfeited.contains(seatId))throw new IllegalArgumentException("This seat has left the draft");
        if(!tournament.getRounds().isEmpty())throw new IllegalArgumentException("Decks are locked after the first round starts");
        try{return submitCheckedDeck(seatId,player,request);}
        catch(IllegalArgumentException ex){return map("accepted",false,"errors",Collections.singletonList(ex.getMessage()),"state",state(seatId));}
    }
    private Map<String,Object> submitCheckedDeck(String seatId,Player player,JsonObject request){
        List<Card> pool=draft.getPlayerSnapshot(player.getId()).getPicks();Map<UUID,Card> available=pool.stream().collect(Collectors.toMap(Card::getId,c->c));Deck deck=new Deck();deck.setName(player.getName()+" — draft");
        JsonArray main=request.has("main")?request.getAsJsonArray("main"):new JsonArray();
        for(JsonElement element:main){UUID cardId;try{cardId=UUID.fromString(element.getAsString());}catch(Exception ex){throw new IllegalArgumentException("Main deck must contain picked card instance IDs");}Card card=available.remove(cardId);if(card==null)throw new IllegalArgumentException("Card was not drafted by this player, or was selected twice: "+cardId);deck.getCards().add(card);}
        deck.getSideboard().addAll(available.values());
        if(request.has("basics")){
            JsonElement value=request.get("basics");
            if(value.isJsonObject())for(Map.Entry<String,JsonElement> entry:value.getAsJsonObject().entrySet())addBasics(deck,entry.getKey(),quantity(entry.getValue()));
            else if(value.isJsonArray())for(JsonElement el:value.getAsJsonArray()){JsonObject b=el.getAsJsonObject();addBasics(deck,text(b,"name",""),quantity(b.get("count")));}
            else throw new IllegalArgumentException("Basic lands must be names and quantities");
        }
        validatePool(deck,pool);
        submitted.put(seatId,deck);tournament.submitDeck(player.getId(),deck);updateReady();return map("accepted",true,"errors",Collections.emptyList(),"deck",deckJson(deck),"state",state(seatId));
    }
    static void addBasics(Deck deck,String name,int count){
        if(!DeckValidator.MAIN_BASIC_LAND_NAMES.contains(name))throw new IllegalArgumentException("Basic land is not offered by native Limited: "+name);
        if(count<0||count>250||deck.getCards().size()+count>1000)throw new IllegalArgumentException("Basic land quantities exceed the application resource bound");
        if(count==0)return;JsonArray entries=new JsonArray();JsonObject entry=new JsonObject();entry.addProperty("name",name);entry.addProperty("count",count);entries.add(entry);EngineBridge.addCards(deck.getCards(),entries,Collections.emptyList());
    }
    static int quantity(JsonElement value){
        if(value==null||!value.isJsonPrimitive()||!value.getAsJsonPrimitive().isNumber())throw new IllegalArgumentException("Basic land quantity must be an integer");
        try{return value.getAsBigDecimal().intValueExact();}catch(ArithmeticException ex){throw new IllegalArgumentException("Basic land quantity must be an integer");}
    }
    static void validatePool(Deck deck,List<Card> pool){
        Map<String,Long> counts=pool.stream().collect(Collectors.groupingBy(Card::getName,Collectors.counting()));
        List<Card> all=new ArrayList<>(deck.getCards());all.addAll(deck.getSideboard());
        for(Card card:all)if(!DeckValidator.MAIN_BASIC_LAND_NAMES.contains(card.getName())){long left=counts.getOrDefault(card.getName(),0L)-1;if(left<0)throw new IllegalArgumentException("Deck contains a card outside its drafted pool: "+card.getName());counts.put(card.getName(),left);}
        Limited validator=new Limited();if(!validator.validate(deck))throw new IllegalArgumentException(validator.getErrorsListInfo());
    }
    void updateReady(){if(submitted.size()==seats.size())status="ready";}
    static Map<String,Object> selection(Deck deck,List<Card> pool){
        Set<UUID> picked=pool.stream().map(Card::getId).collect(Collectors.toSet());List<String> main=new ArrayList<>();Map<String,Integer> basics=new TreeMap<>();
        for(Card card:deck.getCards())if(picked.contains(card.getId()))main.add(card.getId().toString());else if(DeckValidator.MAIN_BASIC_LAND_NAMES.contains(card.getName()))basics.merge(card.getName(),1,Integer::sum);
        return map("main",main,"basics",basics);
    }
    synchronized JsonObject deckSource(String seatId){requireSeat(seatId);Deck d=submitted.get(seatId);if(d==null)throw new IllegalArgumentException("Player has not submitted a valid Limited deck");return deckJson(d);}
    static JsonObject deckJson(Deck deck){JsonObject out=new JsonObject();out.addProperty("name",deck.getName());out.addProperty("format","Limited");out.add("main",entries(deck.getCards()));out.add("sideboard",entries(deck.getSideboard()));out.add("commander",new JsonArray());return out;}
    static JsonArray entries(Collection<Card> cards){JsonArray out=new JsonArray();Map<String,Long> counts=cards.stream().collect(Collectors.groupingBy(Card::getName,TreeMap::new,Collectors.counting()));counts.forEach((name,count)->{JsonObject entry=new JsonObject();entry.addProperty("name",name);entry.addProperty("count",count);out.add(entry);});return out;}
    static List<Map<String,Object>> cards(Collection<Card> cards){return cards.stream().map(c->map("id",c.getId().toString(),"name",c.getName(),"manaCost",c.getManaCost().getText(),"type",c.getCardType().toString(),"rules",c.getAbilities().stream().map(a->EngineBridge.clean(a.getRule())).collect(Collectors.joining("\n")),"set",c.getExpansionSetCode(),"number",c.getCardNumber(),"power",c.getPower().toString(),"toughness",c.getToughness().toString())).collect(Collectors.toList());}

    synchronized Map<String,Object> nextRound(){
        if(!status.equals("ready")&&!status.equals("competing"))throw new IllegalArgumentException("Every player must submit a native-valid deck before pairings");
        for(Round round:tournament.getRounds())for(TournamentPairing pair:round.getPairs())if(pair.getMatch()==null||!pair.getMatch().hasEnded())throw new IllegalArgumentException("Finish the current native matches before the next round");
        boolean finished=pairing.equals("swiss")?tournament.getRounds().size()>=tournament.getNumberRounds():((Elimination)tournament).activeCount()<=1;
        if(finished){status="completed";return pairings();}
        if(pairing.equals("swiss"))((Swiss)tournament).nextNativeRound();else ((Elimination)tournament).nextNativeRound();status="competing";return pairings();
    }
    synchronized Map<String,Object> pairings(){
        List<Map<String,Object>> rounds=new ArrayList<>();
        for(Round round:tournament.getRounds())rounds.add(map("round",round.getRoundNumber(),"pairs",round.getPairs().stream().map(pair->map("id",pair.getId().toString(),"seat1",seatByPlayer.get(pair.getPlayer1().getPlayer().getId()),"seat2",seatByPlayer.get(pair.getPlayer2().getPlayer().getId()),"finished",pair.getMatch()!=null&&pair.getMatch().hasEnded())).collect(Collectors.toList()),"byes",round.getPlayerByes().stream().map(p->seatByPlayer.get(p.getPlayer().getId())).collect(Collectors.toList())));
        Round latest=tournament.getRounds().stream().reduce((a,b)->b).orElse(null);
        List<Map<String,Object>> matches=new ArrayList<>();
        if(latest!=null){
            for(TournamentPairing pair:latest.getPairs())matches.add(map("id",pair.getId().toString(),"matchId",pair.getId().toString(),"seatIds",Arrays.asList(seatByPlayer.get(pair.getPlayer1().getPlayer().getId()),seatByPlayer.get(pair.getPlayer2().getPlayer().getId())),"finished",pair.getMatch()!=null&&pair.getMatch().hasEnded()));
            for(TournamentPlayer bye:latest.getPlayerByes())matches.add(map("id","bye-"+latest.getRoundNumber()+"-"+bye.getPlayer().getId(),"seatIds",Collections.singletonList(seatByPlayer.get(bye.getPlayer().getId())),"bye",true,"finished",true));
        }
        boolean finished=latest!=null&&latest.getPairs().stream().allMatch(p->p.getMatch()!=null&&p.getMatch().hasEnded());
        return map("draftId",id,"status",status,"pairing",pairing,"round",latest==null?0:latest.getRoundNumber(),"matches",matches,"finished",finished,"rounds",rounds,"standings",tournament.getPlayers().stream().map(p->map("seatId",seatByPlayer.get(p.getPlayer().getId()),"name",p.getPlayer().getName(),"points",p.getPoints(),"eliminated",p.isEliminated(),"results",p.getResults())).collect(Collectors.toList()));
    }
    synchronized void recordResult(String pairId,String winnerSeatId){
        TournamentPairing pair=null;for(Round round:tournament.getRounds())for(TournamentPairing candidate:round.getPairs())if(candidate.getId().toString().equals(pairId))pair=candidate;
        if(pair==null)throw new IllegalArgumentException("Unknown native pairing");
        if(pair.getMatch()!=null&&pair.getMatch().hasEnded())throw new IllegalArgumentException("Pairing result already recorded");
        Player winner=winnerSeatId==null?null:requireSeat(winnerSeatId);
        if(winner==null&&pairing.equals("elimination"))throw new IllegalArgumentException("A drawn elimination game requires a rematch");
        if(winner!=null&&!winner.getId().equals(pair.getPlayer1().getPlayer().getId())&&!winner.getId().equals(pair.getPlayer2().getPlayer().getId()))throw new IllegalArgumentException("Winner is not a player in this pairing");
        ResultMatch match=new ResultMatch(tournament.getOptions().getMatchOptions());match.addPlayer(pair.getPlayer1().getPlayer(),pair.getPlayer1().getDeck());match.addPlayer(pair.getPlayer2().getPlayer(),pair.getPlayer2().getDeck());
        if(winner==null)match.finishDraw();else{match.getPlayer(winner.getId()).addWin();match.checkIfMatchEnds();}
        pair.setMatchAndTable(match,match.getId());tournament.updateResults();if(pairing.equals("elimination"))pair.eliminatePlayers();
    }
}
