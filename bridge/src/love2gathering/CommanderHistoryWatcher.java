package love2gathering;

import mage.constants.*;
import mage.game.Game;
import mage.game.events.GameEvent;
import mage.game.events.ZoneChangeEvent;
import mage.util.CardUtil;
import mage.watchers.Watcher;
import java.util.*;

/** Presentation history derived only from actual native dies events. */
final class CommanderHistoryWatcher extends Watcher {
    final Map<UUID,Integer> deaths=new HashMap<>();
    CommanderHistoryWatcher(){super(WatcherScope.GAME);}
    private CommanderHistoryWatcher(CommanderHistoryWatcher original){super(original);deaths.putAll(original.deaths);}
    @Override public CommanderHistoryWatcher copy(){return new CommanderHistoryWatcher(this);}
    @Override public void reset(){} // Lifetime history, not a turn counter.
    @Override public void watch(GameEvent event,Game game){
        if(!(event instanceof ZoneChangeEvent)||!((ZoneChangeEvent)event).isDiesEvent())return;
        UUID main=CardUtil.getMainCardId(game,event.getTargetId());
        if(game.getPlayers().values().stream().anyMatch(p->game.getCommandersIds(p,CommanderCardType.COMMANDER_OR_OATHBREAKER,false).contains(main)))
            deaths.merge(main,1,Integer::sum);
    }
    int count(UUID commander){return deaths.getOrDefault(commander,0);}
}
