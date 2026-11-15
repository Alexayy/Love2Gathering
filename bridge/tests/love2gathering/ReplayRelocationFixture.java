package love2gathering;

import com.google.gson.JsonObject;
import java.nio.file.*;
import java.sql.*;
import java.util.*;
import java.util.concurrent.*;
import static love2gathering.EngineBridge.map;

/** Actual JDBC contention against a fresh temporary outbox, no remote catalog. */
public final class ReplayRelocationFixture {
    static int checks;
    static void check(boolean value,String label){if(!value)throw new AssertionError(label);checks++;}
    static void marker(Connection connection,String target)throws Exception{
        try(PreparedStatement statement=connection.prepareStatement("INSERT INTO replay_outbox_control VALUES('relocated',?)")){statement.setString(1,target);statement.executeUpdate();}
    }
    static JsonObject metadata(String id){JsonObject value=new JsonObject();value.addProperty("id",id);value.addProperty("title","Owned relocation fixture");return value;}
    public static void main(String[] args)throws Exception{
        Path root=Paths.get(args[0]);Path temp=Files.createTempDirectory("love2gathering-native-relocation-");Path source=temp.resolve("replay-outbox.sqlite");
        ExecutorService worker=Executors.newSingleThreadExecutor();
        try{
            ReplayRecorder recorder=new ReplayRecorder(source,17399,"initial",metadata("initial"),false);recorder.connection.close();
            try(Connection c=ReplayRecorder.open(source);Statement s=c.createStatement()){
                check(!ReplayRecorder.relocated(c),"Fresh outbox has relocation protocol without being retired");
                try(ResultSet proof=s.executeQuery("SELECT value FROM replay_outbox_control WHERE key='owner_protocol:"+ProcessHandle.current().pid()+"'")){check(proof.next()&&proof.getString(1).equals("1"),"Native recorder registers cooperative owner protocol atomically");}
                try(ResultSet proof=s.executeQuery("SELECT value FROM replay_outbox_control WHERE key='owner_started:"+ProcessHandle.current().pid()+"'")){check(proof.next()&&Long.parseLong(proof.getString(1))>0,"Native owner proof includes process start time for PID reuse safety");}
                s.execute("UPDATE replay_outbox SET finish='{}',status='completed' WHERE id='initial'");
                s.execute("BEGIN IMMEDIATE");marker(c,temp.resolve("destination").toString());
                CountDownLatch attempted=new CountDownLatch(1);
                Future<Boolean> rejected=worker.submit(()->{attempted.countDown();try{ReplayRecorder created=new ReplayRecorder(source,17399,"late",metadata("late"),false);created.connection.close();return false;}catch(Exception expected){return expected.getMessage().contains("Restart the application");}});
                attempted.await(2,TimeUnit.SECONDS);Thread.sleep(120);
                check(!rejected.isDone(),"A new recorder waits behind the migration's SQLite writer lock");
                s.execute("COMMIT");check(rejected.get(8,TimeUnit.SECONDS),"Late recorder sees retirement and requests restart");
                try(ResultSet rows=s.executeQuery("SELECT count(*) FROM replay_outbox WHERE id='late'")){rows.next();check(rows.getInt(1)==0,"Rejected recorder never creates a post-backup recording row");}
                check(ReplayRecorder.relocated(c),"Source keeps its durable retirement marker");
                s.execute("DELETE FROM replay_outbox_control WHERE key='relocated'");
            }
            ReplayRecorder selected=new ReplayRecorder(source,17399,"selected",metadata("selected"),false);
            try(Connection c=ReplayRecorder.open(source);Statement s=c.createStatement();ResultSet rows=s.executeQuery("SELECT status,owner_pid FROM replay_outbox WHERE id='selected'")){
                rows.next();check(rows.getString(1).equals("recording")&&rows.getLong(2)==ProcessHandle.current().pid(),"Recorder that wins before migration is durably visible as active");
            }finally{selected.connection.close();}
            String report=EngineBridge.JSON.toJson(map("passed",true,"checks",checks,"scope","Actual SQLite JDBC writer contention and retired-source guard in temporary storage; no user files or network calls","storageRelocationProtocol",1));
            Files.writeString(root.resolve("bridge/tests/replay-relocation-report.json"),report+"\n");System.out.println(report);
        }finally{worker.shutdownNow();try(java.util.stream.Stream<Path> paths=Files.walk(temp)){paths.sorted(Comparator.reverseOrder()).forEach(path->{try{Files.deleteIfExists(path);}catch(Exception ignored){}});}}
    }
}
