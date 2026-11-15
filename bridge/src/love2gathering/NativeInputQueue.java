package love2gathering;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import static love2gathering.EngineBridge.map;

/** Bounded CALL-thread delivery; GAME alone opens/executes native questions. */
final class NativeInputQueue {
    private final EngineBridge.Session session;
    private final AtomicInteger pending=new AtomicInteger();
    private final ThreadPoolExecutor executor;
    private volatile long promptId;
    private volatile String error;
    private volatile String deliveryId;
    volatile Map<String,Object> recoveredPrompt;
    NativeInputQueue(EngineBridge.Session session){
        this.session=session;
        executor=new ThreadPoolExecutor(0,1,1,TimeUnit.SECONDS,new ArrayBlockingQueue<>(1),r->{Thread t=new Thread(r,"bridge-native-input");t.setDaemon(true);return t;});
    }
    void submit(Map<String,Object> prompt,Runnable commit,Runnable deliver){
        long id=((Number)prompt.get("id")).longValue();String delivery=UUID.randomUUID().toString();
        CountDownLatch committed=new CountDownLatch(1);boolean[] accepted={false};pending.incrementAndGet();
        try{executor.execute(()->{
            try{
                committed.await();
                if(accepted[0]&&session.running&&!session.owner.stopRequested&&!session.human.hasLeft()){
                    if(!session.human.deliverNative(id,deliver))throw new IllegalStateException("Native question changed before delivery");
                    session.recordInputDelivery(delivery,id,"delivered");
                }
            }catch(InterruptedException interrupted){Thread.currentThread().interrupt();}
            catch(RuntimeException failed){if(delivery.equals(deliveryId)){error="Native input could not be delivered; refresh or retry the current choice";session.restoreInputPrompt(prompt);recoveredPrompt=prompt;}session.recordInputDelivery(delivery,id,"failed");}
            finally{pending.decrementAndGet();}
        });}catch(RejectedExecutionException full){pending.decrementAndGet();throw new IllegalArgumentException("A native answer is already queued or the game has ended");}
        try{commit.run();promptId=id;deliveryId=delivery;error=null;recoveredPrompt=null;accepted[0]=true;}finally{committed.countDown();}
    }
    Map<String,Object> view(){int count=pending.get();return map("pending",count>0,"count",count,"id",deliveryId,"promptId",deliveryId==null?null:promptId,"error",error);}
    void close(){pending.addAndGet(-executor.shutdownNow().size());}
}
