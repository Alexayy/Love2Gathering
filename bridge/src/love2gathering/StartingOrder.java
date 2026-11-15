package love2gathering;

import java.security.SecureRandom;
import java.util.*;
import java.util.function.IntSupplier;
import static love2gathering.EngineBridge.map;

/** Server-owned pregame presentation; native Game still executes turn order. */
final class StartingOrder {
    private static final SecureRandom RANDOM = new SecureRandom();
    static Map<String,Object> choose(List<Map<String,Object>> seats, String requested, boolean room) {
        return choose(seats, requested, room, () -> RANDOM.nextInt(6) + 1);
    }
    static Map<String,Object> choose(List<Map<String,Object>> seats, String requested, boolean room, IntSupplier die) {
        if (seats.size() < 2) throw new IllegalArgumentException("Starting order needs at least two players");
        if (!room && requested != null && !requested.equals("dice")) {
            Map<String,Object> chosen = seats.stream().filter(s -> requested.equals(s.get("seatId"))).findFirst()
                .orElseThrow(() -> new IllegalArgumentException("Choose an actual practice seat or 2d6"));
            return map("mode","chosen","winnerId",chosen.get("playerId"),"rounds",Collections.emptyList(),"createdAt",System.currentTimeMillis());
        }
        List<Map<String,Object>> contenders = new ArrayList<>(seats);
        List<Map<String,Object>> rounds = new ArrayList<>();
        for (int attempt=0; attempt<128; attempt++) {
            List<Map<String,Object>> rolls = new ArrayList<>(), leaders = new ArrayList<>();
            int highest = 0;
            for (Map<String,Object> seat : contenders) {
                int first=die.getAsInt(), second=die.getAsInt();
                if(first<1||first>6||second<1||second>6)throw new IllegalArgumentException("A d6 result must be between one and six");
                int total=first+second;
                rolls.add(map("playerId",seat.get("playerId"),"seat",seat.get("seat"),"seatId",seat.get("seatId"),"name",seat.get("name"),"dice",Arrays.asList(first,second),"total",total));
                if(total>highest){highest=total;leaders.clear();}
                if(total==highest)leaders.add(seat);
            }
            rounds.add(map("rolls",rolls,"highest",highest));
            if(leaders.size()==1)return map("mode","2d6","winnerId",leaders.get(0).get("playerId"),"rounds",rounds,"createdAt",System.currentTimeMillis());
            contenders=leaders; // Only tied highest rollers reroll.
        }
        throw new IllegalStateException("The starting roll remained tied; start again");
    }
}
