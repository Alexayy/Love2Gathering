package love2gathering;

import mage.constants.MultiplayerAttackOption;
import mage.constants.RangeOfInfluence;
import mage.game.GameImpl;
import mage.game.FreeForAllType;
import mage.game.match.MatchType;
import mage.game.mulligan.Mulligan;

/** Stock XMage free-for-all execution with the Limited deck-size configuration. */
final class LimitedFreeForAll extends GameImpl {
    private final java.util.function.Consumer<PresentationGames.Resolution> callback;
    private final PresentationGames.Lifecycle lifecycle;
    private final int players;
    LimitedFreeForAll(int players, Mulligan mulligan) { this(players,mulligan,null); }
    LimitedFreeForAll(int players, Mulligan mulligan, java.util.function.Consumer<PresentationGames.Resolution> callback) {
        this(players,mulligan,callback,null);
    }
    LimitedFreeForAll(int players, Mulligan mulligan, java.util.function.Consumer<PresentationGames.Resolution> callback,PresentationGames.Lifecycle lifecycle) {
        super(MultiplayerAttackOption.MULTIPLE, RangeOfInfluence.ALL, mulligan, 40, 20, 7);
        this.players = players;this.callback=callback;this.lifecycle=lifecycle;
    }
    LimitedFreeForAll(LimitedFreeForAll original) { super(original); players = original.players; callback=null;lifecycle=null; }
    @Override protected void resolve(){PresentationGames.resolve(this,callback,super::resolve);}
    @Override public void checkConcede(boolean gameThread){super.checkConcede(gameThread);if(lifecycle!=null)lifecycle.conceded(this);}
    @Override public synchronized void applyEffects(){if(lifecycle!=null)lifecycle.applying(this);super.applyEffects();}
    @Override public boolean replaceEvent(mage.game.events.GameEvent event){if(lifecycle!=null)lifecycle.replacing(this,event);return super.replaceEvent(event);}
    @Override public boolean replaceEvent(mage.game.events.GameEvent event,mage.abilities.Ability source){if(lifecycle!=null)lifecycle.replacing(this,event);return super.replaceEvent(event,source);}
    @Override protected java.util.UUID findWinnersAndLosers(){return lifecycle!=null&&lifecycle.keepResults()?null:super.findWinnersAndLosers();}
    @Override public int getNumPlayers() { return players; }
    @Override public MatchType getGameType() { return new FreeForAllType(); }
    @Override public LimitedFreeForAll copy() { return new LimitedFreeForAll(this); }
}
