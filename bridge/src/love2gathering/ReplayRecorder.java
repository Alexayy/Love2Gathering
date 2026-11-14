package love2gathering;

import com.google.gson.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.sql.*;
import java.util.*;
import java.util.concurrent.CopyOnWriteArrayList;

/** Durable SQLite outbox feeding the catalog's authoritative replay database. */
final class ReplayRecorder {
    static final List<ReplayRecorder> LIVE=new CopyOnWriteArrayList<>();
    final String id;
    final Path database;
    final JsonObject metadata;
    final Deque<String> unsaved=new ArrayDeque<>();
    volatile int port;
    volatile String status="recording", error;
    volatile long pending, savedSequence=-1;
    long nextSequence;
    Connection connection;
    volatile JsonObject finish;
    volatile boolean remoteReady;
    final Thread worker;

    static Path databasePath() {
        String configured=System.getenv("LOVE2GATHERING_DATA_DIR");
        Path data=configured!=null&&!configured.isEmpty() ? Paths.get(configured) : Paths.get(Optional.ofNullable(System.getenv("XDG_DATA_HOME")).orElse(Paths.get(System.getProperty("user.home"),".local","share").toString()),"love2gathering");
        return data.toAbsolutePath().resolve("replay-outbox.sqlite");
    }
    static Connection open(Path path) throws Exception {
        Files.createDirectories(path.getParent());
        Class.forName("org.sqlite.JDBC");
        Connection c=DriverManager.getConnection("jdbc:sqlite:"+path);
        try(Statement s=c.createStatement()) {
            s.execute("PRAGMA busy_timeout=5000");s.execute("PRAGMA journal_mode=WAL");s.execute("PRAGMA synchronous=FULL");
            s.execute("CREATE TABLE IF NOT EXISTS replay_outbox(id TEXT PRIMARY KEY,port INTEGER NOT NULL,owner_pid INTEGER NOT NULL,metadata TEXT NOT NULL,next_sequence INTEGER NOT NULL DEFAULT 0,finish TEXT,status TEXT NOT NULL DEFAULT 'recording',last_error TEXT,updated INTEGER NOT NULL)");
            s.execute("CREATE TABLE IF NOT EXISTS replay_outbox_events(replay_id TEXT NOT NULL,sequence INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(replay_id,sequence))");
            s.execute("CREATE TABLE IF NOT EXISTS replay_outbox_control(key TEXT PRIMARY KEY,value TEXT NOT NULL)");
        }
        return c;
    }
    static ReplayRecorder create(int port,JsonObject metadata) {
        try {
            recoverPending(port);
            Path path=databasePath();
            // Verify durable buffering is available before creating the public record.
            try(Connection ignored=open(path)) { }
            if(!metadata.has("id"))metadata.addProperty("id","game-"+UUID.randomUUID());
            ReplayRecorder recorder=new ReplayRecorder(path,port,metadata.get("id").getAsString(),metadata,false);
            LIVE.add(recorder);
            try {request(port,"/replays",metadata);recorder.remoteReady=true;}
            catch(Exception ex){recorder.error="Replay creation pending: "+ex.getMessage();recorder.finish("failed",EngineBridge.map("reason","Game did not start because replay creation failed"),recorder.error);recorder.worker.start();throw ex;}
            recorder.worker.start();return recorder;
        } catch(Exception ex) { throw new IllegalStateException("Cannot create saved replay: "+ex.getMessage(),ex); }
    }
    ReplayRecorder(Path database,int port,String id,JsonObject metadata,boolean recovery) throws Exception {
        this.id=id;this.database=database;this.port=port;this.metadata=metadata.deepCopy();connection=open(database);
        try(Statement transaction=connection.createStatement()) {
            // The migration's final outbox backup/retirement takes the same
            // writer lock. Either this recording wins and migration refuses
            // its active row, or retirement wins and this insert is rejected.
            transaction.execute("BEGIN IMMEDIATE");
            try {
                checkLocation(connection);registerOwnerProtocol(connection);
                if(!recovery)try(PreparedStatement s=connection.prepareStatement("INSERT INTO replay_outbox(id,port,owner_pid,metadata,updated) VALUES(?,?,?,?,?)")) {
                    s.setString(1,id);s.setInt(2,port);s.setLong(3,ProcessHandle.current().pid());s.setString(4,EngineBridge.JSON.toJson(metadata));s.setLong(5,System.currentTimeMillis());s.executeUpdate();
                }
                try(PreparedStatement s=connection.prepareStatement("SELECT next_sequence,finish FROM replay_outbox WHERE id=?")) {
                    s.setString(1,id);try(ResultSet r=s.executeQuery()){if(r.next()){nextSequence=r.getLong(1);String f=r.getString(2);if(f!=null)finish=JsonParser.parseString(f).getAsJsonObject();}}
                }
                try(PreparedStatement s=connection.prepareStatement("SELECT count(*) FROM replay_outbox_events WHERE replay_id=?")) {s.setString(1,id);try(ResultSet r=s.executeQuery()){r.next();pending=r.getLong(1);}}
                transaction.execute("COMMIT");
            } catch(Exception ex) {
                try{transaction.execute("ROLLBACK");}catch(Exception ignored){}
                try{connection.close();}catch(Exception ignored){}
                throw ex;
            }
        }catch(Exception ex){try{connection.close();}catch(Exception ignored){}throw ex;}
        savedSequence=nextSequence-pending-1;
        worker=new Thread(this::drain,"Replay SQLite outbox "+id);worker.setDaemon(true);
    }
    static void registerOwnerProtocol(Connection connection) throws SQLException {
        String pid=Long.toString(ProcessHandle.current().pid());
        long started=ProcessHandle.current().info().startInstant().map(java.time.Instant::toEpochMilli).orElse(0L);
        try(PreparedStatement statement=connection.prepareStatement("INSERT INTO replay_outbox_control(key,value) VALUES(?,?) ON CONFLICT(key)DO UPDATE SET value=excluded.value")) {
            statement.setString(1,"owner_protocol:"+pid);statement.setString(2,"1");statement.executeUpdate();
            statement.setString(1,"owner_started:"+pid);statement.setString(2,Long.toString(started));statement.executeUpdate();
        }
    }
    static boolean relocated(Connection connection) throws SQLException {
        try(PreparedStatement query=connection.prepareStatement("SELECT value FROM replay_outbox_control WHERE key='relocated'");ResultSet row=query.executeQuery()) { return row.next(); }
    }
    static void checkLocation(Connection connection) throws SQLException {
        if(relocated(connection))throw new SQLException("The data directory was relocated. Restart the application before recording another game.");
    }
    static synchronized void recoverPending(int catalogPort) {
        Path path=databasePath();if(!Files.exists(path))return;
        try(Connection c=open(path);Statement s=c.createStatement();ResultSet rows=s.executeQuery("SELECT id,owner_pid,metadata FROM replay_outbox WHERE status NOT IN ('completed','failed','aborted')")) {
            if(relocated(c))return;
            List<JsonObject> orphaned=new ArrayList<>();
            while(rows.next()) {
                long pid=rows.getLong("owner_pid");
                if(ProcessHandle.of(pid).map(ProcessHandle::isAlive).orElse(false))continue;
                JsonObject row=new JsonObject();row.addProperty("id",rows.getString("id"));row.addProperty("owner",pid);row.add("metadata",JsonParser.parseString(rows.getString("metadata")));orphaned.add(row);
            }
            for(JsonObject row:orphaned) {
                String id=row.get("id").getAsString();
                boolean claimed=false;
                try(Statement transaction=c.createStatement()) {
                    transaction.execute("BEGIN IMMEDIATE");
                    try {
                        checkLocation(c);registerOwnerProtocol(c);
                        try(PreparedStatement claim=c.prepareStatement("UPDATE replay_outbox SET owner_pid=?,port=?,updated=? WHERE id=? AND owner_pid=? AND status NOT IN ('completed','failed','aborted')")) {
                            claim.setLong(1,ProcessHandle.current().pid());claim.setInt(2,catalogPort);claim.setLong(3,System.currentTimeMillis());claim.setString(4,id);claim.setLong(5,row.get("owner").getAsLong());claimed=claim.executeUpdate()==1;
                        }
                        transaction.execute("COMMIT");
                    }catch(Exception ex){try{transaction.execute("ROLLBACK");}catch(Exception ignored){}throw ex;}
                }
                if(!claimed)continue;
                ReplayRecorder recorder=new ReplayRecorder(path,catalogPort,id,row.getAsJsonObject("metadata"),true);
                if(recorder.finish==null)recorder.finish("aborted",EngineBridge.map("reason","Recovered after the game engine exited"),null);
                LIVE.add(recorder);recorder.worker.start();
            }
        } catch(Exception ex) { System.err.println("Replay recovery pending: "+ex); }
    }
    synchronized void event(String type,Object data) {
        if(finish!=null||isFinished())return;
        JsonObject event=new JsonObject();event.addProperty("sequence",nextSequence++);event.addProperty("type",type);event.addProperty("timestamp",System.currentTimeMillis());event.add("data",EngineBridge.JSON.toJsonTree(data));
        String payload=EngineBridge.JSON.toJson(event);pending++;
        try { persist(payload); }
        catch(Exception ex) { unsaved.addLast(payload);error="Replay buffering pending: "+ex.getMessage(); }
        notifyAll();
    }
    void persist(String payload) throws Exception {
        JsonObject event=JsonParser.parseString(payload).getAsJsonObject();
        connection.setAutoCommit(false);
        try {
            try(PreparedStatement s=connection.prepareStatement("INSERT OR IGNORE INTO replay_outbox_events(replay_id,sequence,payload) VALUES(?,?,?)")) {s.setString(1,id);s.setLong(2,event.get("sequence").getAsLong());s.setString(3,payload);s.executeUpdate();}
            try(PreparedStatement s=connection.prepareStatement("UPDATE replay_outbox SET next_sequence=?,updated=? WHERE id=?")) {s.setLong(1,nextSequence);s.setLong(2,System.currentTimeMillis());s.setString(3,id);s.executeUpdate();}
            connection.commit();
        } catch(Exception ex){connection.rollback();throw ex;}finally{connection.setAutoCommit(true);}
    }
    synchronized List<String> batch() throws Exception {
        while(!unsaved.isEmpty()){persist(unsaved.peekFirst());unsaved.removeFirst();}
        List<String> batch=new ArrayList<>();int bytes=0;
        try(PreparedStatement s=connection.prepareStatement("SELECT payload FROM replay_outbox_events WHERE replay_id=? ORDER BY sequence LIMIT 16")) {s.setString(1,id);try(ResultSet r=s.executeQuery()){while(r.next()){String item=r.getString(1);if(!batch.isEmpty()&&bytes+item.length()>1024*1024)break;batch.add(item);bytes+=item.length();}}}
        return batch;
    }
    synchronized void acknowledged(List<String> batch) throws Exception {
        long sequence=JsonParser.parseString(batch.get(batch.size()-1)).getAsJsonObject().get("sequence").getAsLong();
        try(PreparedStatement s=connection.prepareStatement("DELETE FROM replay_outbox_events WHERE replay_id=? AND sequence<=?")){s.setString(1,id);s.setLong(2,sequence);pending-=s.executeUpdate();}
        savedSequence=sequence;error=null;notifyAll();
    }
    synchronized void finish(String finalStatus,Object result,String failure) {
        if(finish!=null)return;
        finish=new JsonObject();finish.addProperty("status",finalStatus);finish.addProperty("finishedAt",System.currentTimeMillis());finish.add("result",EngineBridge.JSON.toJsonTree(result));if(failure!=null)finish.addProperty("error",failure);
        try(PreparedStatement s=connection.prepareStatement("UPDATE replay_outbox SET finish=?,updated=? WHERE id=?")){s.setString(1,EngineBridge.JSON.toJson(finish));s.setLong(2,System.currentTimeMillis());s.setString(3,id);s.executeUpdate();}
        catch(Exception ex){error="Replay finalization pending: "+ex.getMessage();}
        notifyAll();
    }
    void drain() {
        int failures=0;
        while(true) {
            try {
                if(!remoteReady){request(port,"/replays",metadata);remoteReady=true;}
                List<String> batch=batch();
                if(!batch.isEmpty()) {
                    JsonArray events=new JsonArray();for(String item:batch)events.add(JsonParser.parseString(item));JsonObject body=new JsonObject();body.add("events",events);
                    request(port,"/replays/"+id+"/events",body);acknowledged(batch);failures=0;continue;
                }
                JsonObject end;
                synchronized(this){end=finish;if(end==null||pending>0){wait(200);continue;}}
                request(port,"/replays/"+id+"/finish",end);
                synchronized(this){status=end.get("status").getAsString();error=null;try(PreparedStatement s=connection.prepareStatement("UPDATE replay_outbox SET status=?,last_error=NULL,updated=? WHERE id=?")){s.setString(1,status);s.setLong(2,System.currentTimeMillis());s.setString(3,id);s.executeUpdate();}connection.close();notifyAll();}
                return;
            } catch(Exception ex) {
                synchronized(this){error="Replay saving pending: "+ex.getMessage();try(PreparedStatement s=connection.prepareStatement("UPDATE replay_outbox SET last_error=?,updated=? WHERE id=?")){s.setString(1,error);s.setLong(2,System.currentTimeMillis());s.setString(3,id);s.executeUpdate();}catch(Exception ignored){}notifyAll();}
                try{Thread.sleep(Math.min(5000,250L*(1<<Math.min(5,failures++))));}catch(InterruptedException ignored){}
            }
        }
    }
    synchronized boolean awaitFinished(long timeoutMs) {
        long end=System.currentTimeMillis()+timeoutMs;
        while(!isFinished()&&System.currentTimeMillis()<end)try{wait(Math.max(1,Math.min(100,end-System.currentTimeMillis())));}catch(InterruptedException ex){Thread.currentThread().interrupt();break;}
        return isFinished();
    }
    synchronized boolean flush(long timeoutMs) {
        long target=nextSequence-1,end=System.currentTimeMillis()+timeoutMs;notifyAll();
        while(savedSequence<target&&!isFinished()&&System.currentTimeMillis()<end)try{wait(Math.max(1,Math.min(100,end-System.currentTimeMillis())));}catch(InterruptedException ex){Thread.currentThread().interrupt();break;}
        return savedSequence>=target;
    }
    boolean isFinished(){return "completed".equals(status)||"failed".equals(status)||"aborted".equals(status);}
    static String errors(){String value=LIVE.stream().map(r->r.error).filter(Objects::nonNull).distinct().limit(3).collect(java.util.stream.Collectors.joining("; "));return value.isEmpty()?null:value;}
    Map<String,Object> state(){return EngineBridge.map("replayId",id,"replayStatus",finish!=null&&!isFinished()?"saving":status,"recordingError",error,"replayPendingEvents",pending,"replaySavedSequence",savedSequence);}
    static JsonObject request(int port,String path,JsonObject body) throws Exception {
        HttpURLConnection connection=(HttpURLConnection)new URL("http://127.0.0.1:"+port+path).openConnection();connection.setConnectTimeout(2000);connection.setReadTimeout(5000);connection.setRequestMethod("POST");connection.setDoOutput(true);connection.setRequestProperty("Content-Type","application/json; charset=utf-8");
        byte[] payload=EngineBridge.JSON.toJson(body).getBytes(StandardCharsets.UTF_8);connection.setFixedLengthStreamingMode(payload.length);
        try(OutputStream out=connection.getOutputStream()){out.write(payload);}
        int code=connection.getResponseCode();InputStream stream=code>=400?connection.getErrorStream():connection.getInputStream();String text=stream==null?"":new String(stream.readAllBytes(),StandardCharsets.UTF_8);connection.disconnect();
        if(code<200||code>=300)throw new IOException("Catalog HTTP "+code+": "+text);
        return JsonParser.parseString(text).getAsJsonObject();
    }
}
