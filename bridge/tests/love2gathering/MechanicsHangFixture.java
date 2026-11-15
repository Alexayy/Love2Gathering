package love2gathering;

import java.lang.management.ManagementFactory;
import java.nio.file.*;
import java.util.concurrent.*;

/** Deliberate diagnostic faults, never a simulated Magic game or outcome. */
public final class MechanicsHangFixture {
    public static void main(String[] args)throws Exception{
        String mode=args[0];Path output=Paths.get(args[1]);Files.createDirectories(output);
        if("busy".equals(mode)){
            Thread worker=new Thread(()->{long value=1;while(true){value=value*1664525+1013904223;if(value==0)System.out.print("");}},"GAME diagnostic busy calculation");
            worker.start();
        }else if("deadlock".equals(mode)){
            Object a=new Object(),b=new Object();CountDownLatch held=new CountDownLatch(2);
            new Thread(()->{synchronized(a){held.countDown();await(held);synchronized(b){throw new AssertionError("Unreachable diagnostic lock");}}},"GAME diagnostic deadlock A").start();
            new Thread(()->{synchronized(b){held.countDown();await(held);synchronized(a){throw new AssertionError("Unreachable diagnostic lock");}}},"GAME diagnostic deadlock B").start();
            held.await();long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(2);
            while(ManagementFactory.getThreadMXBean().findDeadlockedThreads()==null&&System.nanoTime()<end)Thread.sleep(5);
            if(ManagementFactory.getThreadMXBean().findDeadlockedThreads()==null)throw new AssertionError("Fault injection did not form a real Java monitor deadlock");
        }else throw new IllegalArgumentException(mode);
        Files.writeString(output.resolve("fault.json"),"{\"evidenceType\":\"diagnostic_process_fault_fixture\",\"mode\":\""+mode+"\",\"gameOutcome\":null}");
        new CountDownLatch(1).await();
    }
    static void await(CountDownLatch latch){try{latch.await();}catch(InterruptedException ex){Thread.currentThread().interrupt();}}
}
