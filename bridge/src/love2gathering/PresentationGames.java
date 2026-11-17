package love2gathering;

import mage.constants.*;
import mage.game.*;
import mage.game.mulligan.Mulligan;
import mage.game.stack.*;
import mage.game.events.GameEvent;
import mage.abilities.Ability;
import java.util.UUID;
import java.util.Objects;
import java.util.function.Consumer;
import java.util.function.BooleanSupplier;
import java.util.function.BiConsumer;

/** Observe the completed native resolve call, without changing its rules. */
final class PresentationGames {
    private static final ThreadLocal<Resolution> RESOLVING=new ThreadLocal<>();
    private static final ThreadLocal<StackObject> RESOLVING_OBJECT=new ThreadLocal<>();
    static StackObject resolvingObject(){return RESOLVING_OBJECT.get();}
    static Resolution entering(UUID cardId){Resolution value=RESOLVING.get();return value!=null&&Objects.equals(value.sourceId,cardId)?value:null;}
    /** Publish native concessions; only local practice has a termination policy.
     * The hook runs after XMage has processed its real concession queue. */
    static final class Lifecycle {
        final Consumer<Game> afterConcede; final BooleanSupplier preserveResults;
        final Consumer<Game> beforeEffects;final BiConsumer<Game,GameEvent> beforeEvent;
        Lifecycle(Consumer<Game> afterConcede,BooleanSupplier preserveResults,Consumer<Game> beforeEffects,BiConsumer<Game,GameEvent> beforeEvent){this.afterConcede=afterConcede;this.preserveResults=preserveResults;this.beforeEffects=beforeEffects;this.beforeEvent=beforeEvent;}
        boolean real(Game game){return mage.util.ThreadUtils.isRunGameThread()&&!game.isSimulation()&&!game.inCheckPlayableState();}
        void conceded(Game game){if(real(game))afterConcede.accept(game);}
        void applying(Game game){if(real(game))beforeEffects.accept(game);}
        void replacing(Game game,GameEvent event){if(real(game))beforeEvent.accept(game,event);}
        boolean keepResults(){return preserveResults.getAsBoolean();}
    }
    static final class Resolution {
        final Spell spell; final UUID sourceId,controllerId; final String name;
        final int manaValue; final boolean commander;
        Resolution(Spell spell,Game game){
            this.spell=spell;sourceId=spell.getSourceId();controllerId=spell.getControllerId();name=spell.getName();manaValue=spell.getManaValue();
            // Commander identity belongs to the registered native card even
            // when another player controls/casts that spell.
            commander=game.getPlayers().values().stream().anyMatch(player->game.isCommanderObject(player,spell.getCard()));
        }
    }
    static void resolve(Game game,Consumer<Resolution> callback,Runnable nativeResolve){
        // Simulations must never replace or clear the live resolution's cause.
        if(game.isSimulation()||game.inCheckPlayableState()){nativeResolve.run();return;}
        Resolution previous=RESOLVING.get();StackObject previousObject=RESOLVING_OBJECT.get();
        StackObject object=game.getStack().peek();Resolution value=object instanceof Spell?new Resolution((Spell)object,game):null;
        RESOLVING_OBJECT.set(object);RESOLVING.set(value);
        try{
            nativeResolve.run();
            if(value!=null&&value.spell.isResolving()&&!value.spell.isCountered()&&callback!=null)callback.accept(value);
        }finally{
            // Restore nesting and clear context even when native execution or
            // an optional presentation callback fails.
            if(previous==null)RESOLVING.remove();else RESOLVING.set(previous);
            if(previousObject==null)RESOLVING_OBJECT.remove();else RESOLVING_OBJECT.set(previousObject);
        }
    }
    static final class Duel extends TwoPlayerDuel {
        private final Consumer<Resolution> callback;
        private final Lifecycle lifecycle;
        Duel(MultiplayerAttackOption attack,RangeOfInfluence range,Mulligan mulligan,int minimum,int life,int hand,Consumer<Resolution> callback,Lifecycle lifecycle){super(attack,range,mulligan,minimum,life,hand);this.callback=callback;this.lifecycle=lifecycle;}
        @Override protected void resolve(){PresentationGames.resolve(this,callback,super::resolve);}
        @Override public void checkConcede(boolean gameThread){super.checkConcede(gameThread);if(lifecycle!=null)lifecycle.conceded(this);}
        @Override public synchronized void applyEffects(){if(lifecycle!=null)lifecycle.applying(this);super.applyEffects();}
        @Override public boolean replaceEvent(GameEvent event){if(lifecycle!=null)lifecycle.replacing(this,event);return super.replaceEvent(event);}
        @Override public boolean replaceEvent(GameEvent event,Ability source){if(lifecycle!=null)lifecycle.replacing(this,event);return super.replaceEvent(event,source);}
        @Override protected UUID findWinnersAndLosers(){return lifecycle!=null&&lifecycle.keepResults()?null:super.findWinnersAndLosers();}
    }
    static final class Commander extends CommanderDuel {
        private final Consumer<Resolution> callback;
        private final Lifecycle lifecycle;
        Commander(MultiplayerAttackOption attack,RangeOfInfluence range,Mulligan mulligan,int life,int hand,Consumer<Resolution> callback,Lifecycle lifecycle){super(attack,range,mulligan,life,hand);this.callback=callback;this.lifecycle=lifecycle;}
        @Override protected void resolve(){PresentationGames.resolve(this,callback,super::resolve);}
        @Override public void checkConcede(boolean gameThread){super.checkConcede(gameThread);if(lifecycle!=null)lifecycle.conceded(this);}
        @Override public synchronized void applyEffects(){if(lifecycle!=null)lifecycle.applying(this);super.applyEffects();}
        @Override public boolean replaceEvent(GameEvent event){if(lifecycle!=null)lifecycle.replacing(this,event);return super.replaceEvent(event);}
        @Override public boolean replaceEvent(GameEvent event,Ability source){if(lifecycle!=null)lifecycle.replacing(this,event);return super.replaceEvent(event,source);}
        @Override protected UUID findWinnersAndLosers(){return lifecycle!=null&&lifecycle.keepResults()?null:super.findWinnersAndLosers();}
    }
    static final class Multiplayer extends CommanderFreeForAll {
        private final Consumer<Resolution> callback;
        private final Lifecycle lifecycle;
        Multiplayer(MultiplayerAttackOption attack,RangeOfInfluence range,Mulligan mulligan,int life,int hand,Consumer<Resolution> callback,Lifecycle lifecycle){super(attack,range,mulligan,life,hand);this.callback=callback;this.lifecycle=lifecycle;}
        @Override protected void resolve(){PresentationGames.resolve(this,callback,super::resolve);}
        @Override public void checkConcede(boolean gameThread){super.checkConcede(gameThread);if(lifecycle!=null)lifecycle.conceded(this);}
        @Override public synchronized void applyEffects(){if(lifecycle!=null)lifecycle.applying(this);super.applyEffects();}
        @Override public boolean replaceEvent(GameEvent event){if(lifecycle!=null)lifecycle.replacing(this,event);return super.replaceEvent(event);}
        @Override public boolean replaceEvent(GameEvent event,Ability source){if(lifecycle!=null)lifecycle.replacing(this,event);return super.replaceEvent(event,source);}
        // Ending local practice does not resolve a remaining bot-only contest.
        // Keep the authentic human loss; do not award an arbitrary bot a win.
        @Override protected UUID findWinnersAndLosers(){return lifecycle!=null&&lifecycle.keepResults()?null:super.findWinnersAndLosers();}
    }
}
