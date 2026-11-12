package love2gathering;
import com.google.gson.*;
import java.nio.file.*;
import java.sql.*;

/** Simulates an owned recorder process exiting while its HTTP destination is down. */
public final class ReplayOutboxFixture {
    public static void main(String[] args)throws Exception {
        int port=Integer.parseInt(args[1]);Path marker=Paths.get(args[2]);
        if("write".equals(args[0])) {
            JsonObject metadata=new JsonObject();metadata.addProperty("title","SQLite outbox crash recovery fixture");metadata.addProperty("format","Fixture");metadata.addProperty("startedAt",System.currentTimeMillis());
            ReplayRecorder recorder=ReplayRecorder.create(port,metadata);recorder.port=Integer.parseInt(args[3]);
            recorder.event("frame",EngineBridge.map("running",true,"players",java.util.Collections.emptyList(),"prompt",null));
            recorder.event("action",EngineBridge.map("actor","human","input",EngineBridge.map("type","fixture")));
            recorder.event("log",EngineBridge.map("actor","system","category","system","text","Durability fixture"));
            recorder.flush(1200);
            long deadline=System.currentTimeMillis()+5000;while(recorder.error==null&&System.currentTimeMillis()<deadline)Thread.sleep(20);
            if(recorder.error==null||recorder.pending!=3)throw new AssertionError("Outage must surface an error while retaining every pending event");
            try(Connection c=ReplayRecorder.open(ReplayRecorder.databasePath());PreparedStatement s=c.prepareStatement("SELECT count(*) FROM replay_outbox_events WHERE replay_id=?")){s.setString(1,recorder.id);try(ResultSet r=s.executeQuery()){r.next();if(r.getInt(1)!=3)throw new AssertionError("All unsent events must already be durable in SQLite");}}
            Files.writeString(marker,EngineBridge.JSON.toJson(EngineBridge.map("id",recorder.id,"outageError",recorder.error,"durablePending",3)));
            Runtime.getRuntime().halt(0);
        } else {
            String id=JsonParser.parseString(Files.readString(marker)).getAsJsonObject().get("id").getAsString();
            ReplayRecorder.recoverPending(port);
            ReplayRecorder recorder=ReplayRecorder.LIVE.stream().filter(r->r.id.equals(id)).findFirst().orElseThrow(()->new AssertionError("Orphaned SQLite recording was not recovered"));
            if(!recorder.awaitFinished(15000)||!"aborted".equals(recorder.status)||recorder.pending!=0||recorder.error!=null)throw new AssertionError("Recovered recording must fully flush and finalize as aborted");
            System.out.println(EngineBridge.JSON.toJson(EngineBridge.map("passed",true,"id",id,"status",recorder.status,"savedSequence",recorder.savedSequence,"pending",recorder.pending)));
        }
    }
}
