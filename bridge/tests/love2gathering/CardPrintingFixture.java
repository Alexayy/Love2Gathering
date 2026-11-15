package love2gathering;

import com.google.gson.*;
import mage.cards.*;
import mage.util.Copier;
import java.nio.file.*;
import java.util.*;

/** Native two-human entitlement boundaries; selected edition is metadata only. */
public final class CardPrintingFixture {
    static int checks;
    static void check(boolean value,String text){if(!value)throw new AssertionError(text);checks++;}
    static JsonObject deck(String printing){return JsonParser.parseString("{\"format\":\"Modern\",\"main\":[{\"name\":\"Forest\",\"count\":60}],\"printingSelections\":[{\"name\":\"Forest\",\"zone\":\"main\",\"count\":60,\"printingId\":\""+printing+"\"}]}").getAsJsonObject();}
    public static void main(String[]args)throws Exception{
        Path root=Path.of(args[0]);org.apache.log4j.BasicConfigurator.configure();org.apache.log4j.Logger.getRootLogger().setLevel(org.apache.log4j.Level.WARN);
        EngineBridge.cardMap=JsonParser.parseString(Files.readString(root.resolve("bridge/card-map.json"))).getAsJsonObject();Copier.setLoader(CardPrintingFixture.class.getClassLoader());
        JsonObject body=new JsonObject();body.addProperty("format","Modern");body.addProperty("recordingPort",0);JsonArray seats=new JsonArray();
        for(int i=0;i<2;i++){JsonObject seat=new JsonObject();seat.addProperty("seatId","printing-seat-"+i);seat.addProperty("name","Printing human "+i);seat.addProperty("type","human");seat.add("deck",deck("forest-art-"+i));seats.add(seat);}body.add("seats",seats);
        EngineBridge.Session owner=new EngineBridge.Session(body,true);
        try{
            EngineBridge.Session first=owner.perspectives.get(0),second=owner.perspectives.get(1);
            Card card=first.human.getLibrary().getCards(first.game).iterator().next();
            Map<String,Object> own=first.card(card);check("forest-art-0".equals(own.get("selectedPrintingId")),"Owner sees its exact chosen printing");
            check("Forest".equals(own.get("name"))&&own.get("printing")!=null,"Native identity and original printing descriptor remain intact");
            Map<String,Object> hidden=second.card(card);check(Boolean.TRUE.equals(hidden.get("hidden"))&&!hidden.containsKey("selectedPrintingId"),"A hidden opponent card does not disclose an edition or card name");
            owner.game.getState().getRevealed().put("Printing fixture",new CardsImpl(card));
            Map<String,Object> publicCard=second.card(card);check("forest-art-0".equals(publicCard.get("selectedPrintingId")),"Another real human sees the public card owner's chosen edition");
            check(!publicCard.containsKey("printingSelections"),"No complete deck artwork list enters a visible card");
            String recorded=EngineBridge.JSON.toJson(publicCard);check(recorded.contains("selectedPrintingId")&&!recorded.contains("forest-art-1"),"Recorded visible projections retain only this card's chosen edition");
            Card other=second.human.getLibrary().getCards(second.game).iterator().next();check("forest-art-1".equals(second.card(other).get("selectedPrintingId")),"Each seat's edition preference stays independent");
            owner.game.getState().getRevealed().clear();owner.publishAll();
            check(!EngineBridge.JSON.toJson(second.snapshot).contains("forest-art-0"),"Unrevealed library artwork never appears elsewhere in another perspective");
            JsonObject malformed=deck("foreign/url");check(CardPrintingProjection.selected(malformed,"Forest","seed")==null,"Untrusted printing IDs cannot carry URLs");
            check(CardPrintingProjection.selected(deck("edition"),"Plains","seed")==null,"A preference is applied to its card name only");
        }finally{owner.stop();}
        Map<String,Object> result=EngineBridge.map("passed",true,"checks",checks,"scope","Real initialized native two-human sessions and entitled card projections; no runtime card/rule mutation, full game, HTTP catalog lookup or UI assertion");
        Files.writeString(root.resolve("bridge/tests/card-printings-native-report.json"),EngineBridge.JSON.toJson(result)+"\n");System.out.println(EngineBridge.JSON.toJson(result));
    }
}
