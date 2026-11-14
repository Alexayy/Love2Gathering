package love2gathering;

import mage.constants.*;
import mage.game.*;
import mage.game.mulligan.Mulligan;
import mage.game.stack.*;
import java.util.UUID;
import java.util.function.Consumer;

/** Observe the completed native resolve call, without changing its rules. */
final class PresentationGames {
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
    static Resolution before(Game game){
        if(game.isSimulation()||game.inCheckPlayableState())return null;
        StackObject object=game.getStack().peek();
        return object instanceof Spell?new Resolution((Spell)object,game):null;
    }
    static void after(Resolution value,Consumer<Resolution> callback){
        if(value!=null&&value.spell.isResolving()&&!value.spell.isCountered()&&callback!=null)callback.accept(value);
    }
    static final class Duel extends TwoPlayerDuel {
        private final Consumer<Resolution> callback;
        Duel(MultiplayerAttackOption attack,RangeOfInfluence range,Mulligan mulligan,int minimum,int life,int hand,Consumer<Resolution> callback){super(attack,range,mulligan,minimum,life,hand);this.callback=callback;}
        @Override protected void resolve(){Resolution value=before(this);super.resolve();after(value,callback);}
    }
    static final class Commander extends CommanderDuel {
        private final Consumer<Resolution> callback;
        Commander(MultiplayerAttackOption attack,RangeOfInfluence range,Mulligan mulligan,int life,int hand,Consumer<Resolution> callback){super(attack,range,mulligan,life,hand);this.callback=callback;}
        @Override protected void resolve(){Resolution value=before(this);super.resolve();after(value,callback);}
    }
    static final class Multiplayer extends CommanderFreeForAll {
        private final Consumer<Resolution> callback;
        Multiplayer(MultiplayerAttackOption attack,RangeOfInfluence range,Mulligan mulligan,int life,int hand,Consumer<Resolution> callback){super(attack,range,mulligan,life,hand);this.callback=callback;}
        @Override protected void resolve(){Resolution value=before(this);super.resolve();after(value,callback);}
    }
}
