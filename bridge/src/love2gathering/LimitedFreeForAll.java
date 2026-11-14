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
    private final int players;
    LimitedFreeForAll(int players, Mulligan mulligan) { this(players,mulligan,null); }
    LimitedFreeForAll(int players, Mulligan mulligan, java.util.function.Consumer<PresentationGames.Resolution> callback) {
        super(MultiplayerAttackOption.MULTIPLE, RangeOfInfluence.ALL, mulligan, 40, 20, 7);
        this.players = players;this.callback=callback;
    }
    LimitedFreeForAll(LimitedFreeForAll original) { super(original); players = original.players; callback=null; }
    @Override protected void resolve(){PresentationGames.Resolution value=PresentationGames.before(this);super.resolve();PresentationGames.after(value,callback);}
    @Override public int getNumPlayers() { return players; }
    @Override public MatchType getGameType() { return new FreeForAllType(); }
    @Override public LimitedFreeForAll copy() { return new LimitedFreeForAll(this); }
}
