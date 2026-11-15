package love2gathering;
import com.google.gson.*;
import java.nio.file.*;
import java.sql.*;
import java.util.*;

/** Recovery of the actual stress outbox, using only its isolated DATA directory. */
public final class MechanicsOutboxRecovery {
    static class RecoveryBudget extends RuntimeException{RecoveryBudget(String value){super(value);}}
    public static void main(String[] args)throws Exception{
        Path out=Paths.get(args[2]);Files.createDirectories(out);int port=Integer.parseInt(System.getenv("LOVE2GATHERING_CATALOG_PORT"));
        Map<String,Long> expected=new LinkedHashMap<>();long pendingBefore;
        try(Connection c=ReplayRecorder.open(ReplayRecorder.databasePath());Statement s=c.createStatement()){
            try(ResultSet rows=s.executeQuery("SELECT id,next_sequence FROM replay_outbox")){while(rows.next())expected.put(rows.getString(1),rows.getLong(2));}
            try(ResultSet rows=s.executeQuery("SELECT count(*) FROM replay_outbox_events")){rows.next();pendingBefore=rows.getLong(1);}
        }
        long budget=Long.getLong("love2gathering.test.recoveryMillis",60000L);if(budget<1)throw new IllegalArgumentException("Recovery budget must be positive");
        try{
        ReplayRecorder.recoverPending(port);long deadline=System.currentTimeMillis()+budget;
        for(ReplayRecorder recorder:ReplayRecorder.LIVE)if(!recorder.awaitFinished(Math.max(1,deadline-System.currentTimeMillis())))throw new RecoveryBudget("Stress outbox recovery exceeded "+budget+" milliseconds");
        List<Object> records=new ArrayList<>();
        for(Map.Entry<String,Long> entry:expected.entrySet()){
            java.net.HttpURLConnection c=(java.net.HttpURLConnection)new java.net.URL("http://127.0.0.1:"+port+"/replays/"+entry.getKey()).openConnection();c.setConnectTimeout(2000);c.setReadTimeout(5000);
            JsonObject meta;try(java.io.Reader reader=new java.io.InputStreamReader(c.getInputStream(),java.nio.charset.StandardCharsets.UTF_8)){meta=JsonParser.parseReader(reader).getAsJsonObject();}finally{c.disconnect();}
            if(meta.get("eventCount").getAsLong()!=entry.getValue()||meta.get("lastSequence").getAsLong()!=entry.getValue()-1)throw new AssertionError("Stress recording sequence was lost or duplicated");
            if(!"aborted".equals(meta.get("status").getAsString()))throw new AssertionError("Diagnostic stress recording must finalize as aborted, never a game result");
            records.add(EngineBridge.map("id",entry.getKey(),"expectedEventCount",entry.getValue(),"metadata",meta));
        }
        Files.writeString(out.resolve("result.json"),EngineBridge.JSON.toJson(EngineBridge.map("status","pass","evidenceType","actual_stress_recording_recovery","durablePendingBefore",pendingBefore,"records",records,"gameOutcome",null)));
        }catch(Throwable ex){
            Files.writeString(out.resolve("result.json"),EngineBridge.JSON.toJson(EngineBridge.map("status",ex instanceof RecoveryBudget?"budget_exceeded":"fail","error",ex.toString(),"durablePendingBefore",pendingBefore,"expectedSequences",expected,"recoveryMillis",budget,"gameOutcome",null)));
            throw ex;
        }
    }
}
