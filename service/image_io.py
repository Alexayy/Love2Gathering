"""Bound disk work and let visible/selected images precede bulk cache work."""
from contextlib import contextmanager
import sqlite3
import errno
import os
from pathlib import Path
import filelocks
import threading
import time


class ImageIOCancelled(RuntimeError):
    pass


class ImageIO:
    def __init__(self,root=None):
        self.condition=threading.Condition();self.local=threading.local()
        self.waiters=[];self.sequence=0;self.busy=False;self.foreground_count=0
        self.metrics={'operations':0,'waitSeconds':0.,'maxWaitSeconds':0.,'backgroundYields':0,'selectedOperations':0}
        self.stages={}
        self.root=Path(root)if root is not None else None

    def _foreground_file(self):
        if self.root is None:return None
        return os.open(self.root/'.foreground-images.lock',os.O_RDWR|os.O_CREAT|getattr(os,'O_NOFOLLOW',0),0o600)

    def _external_foreground(self):
        descriptor=self._foreground_file()
        if descriptor is None:return False
        try:
            try:filelocks.flock(descriptor,filelocks.LOCK_EX|filelocks.LOCK_NB);return False
            except OSError as exc:
                if exc.errno in(errno.EAGAIN,errno.EACCES):return True
                raise
        finally:os.close(descriptor)

    def note_stage(self,name,elapsed):
        if name not in('sql','disk','catalog','local','network','thumbnailDecode','thumbnailRead','thumbnailWrite','imageQueue'):raise ValueError('Unknown image timing stage')
        with self.condition:
            value=self.stages.setdefault(name,{'count':0,'seconds':0.,'maxSeconds':0.})
            value['count']+=1;value['seconds']+=max(0,elapsed);value['maxSeconds']=max(value['maxSeconds'],elapsed)

    @contextmanager
    def measure(self,name):
        started=time.monotonic()
        try:yield
        finally:self.note_stage(name,time.monotonic()-started)

    @contextmanager
    def _priority(self,value,cancel=None):
        previous=getattr(self.local,'priority',None);old_cancel=getattr(self.local,'cancel',None)
        self.local.priority=min(previous,value)if previous is not None else value
        self.local.cancel=cancel if cancel is not None else old_cancel
        try:yield
        finally:
            self.local.priority=previous;self.local.cancel=old_cancel

    @contextmanager
    def foreground(self,selected=False):
        with self.condition:self.foreground_count+=1
        descriptor=None
        try:
            descriptor=self._foreground_file()
            if descriptor is not None:filelocks.flock(descriptor,filelocks.LOCK_SH)
            with self._priority(0 if selected else 1):yield
        finally:
            if descriptor is not None:os.close(descriptor)
            with self.condition:self.foreground_count-=1;self.condition.notify_all()

    def background(self,cancel=None):
        return self._priority(2,cancel)

    def is_background(self):return getattr(self.local,'priority',None)==2

    def _cancelled(self):
        event=getattr(self.local,'cancel',None)
        if event is not None and event.is_set():raise ImageIOCancelled('Background image work was cancelled')

    def checkpoint(self):
        if getattr(self.local,'priority',None)!=2:return
        with self.condition:
            yielded=False
            while self.foreground_count or any(item[0]<2 for item in self.waiters)or self._external_foreground():
                self._cancelled()
                if not yielded:self.metrics['backgroundYields']+=1;yielded=True
                self.condition.wait(.025)
            self._cancelled()

    @contextmanager
    def operation(self,timeout=30,label='disk'):
        if getattr(self.local,'depth',0):
            self.local.depth+=1
            try:yield
            finally:self.local.depth-=1
            return
        value=getattr(self.local,'priority',None);priority=1 if value is None else value
        started=time.monotonic();deadline=started+timeout;ticket=None
        with self.condition:
            self.sequence+=1;ticket=(priority,self.sequence);self.waiters.append(ticket)
            try:
                while self.busy or ticket!=min(self.waiters)or(priority==2 and(self.foreground_count or self._external_foreground())):
                    self._cancelled();remaining=deadline-time.monotonic()
                    if remaining<=0:raise sqlite3.OperationalError('Local image I/O is busy; retry shortly')
                    self.condition.wait(min(.025,remaining))
                self._cancelled();self.busy=True;self.local.depth=1
                waited=time.monotonic()-started;self.metrics['operations']+=1;self.metrics['waitSeconds']+=waited
                self.metrics['maxWaitSeconds']=max(self.metrics['maxWaitSeconds'],waited)
                if priority==0:self.metrics['selectedOperations']+=1
            finally:self.waiters.remove(ticket)
        active=time.monotonic()
        try:yield
        finally:
            self.note_stage(label,time.monotonic()-active)
            with self.condition:self.local.depth=0;self.busy=False;self.condition.notify_all()

    def status(self):
        with self.condition:
            return dict(self.metrics,active=int(self.busy),waiting=len(self.waiters),foregroundRequests=self.foreground_count,maxConcurrentDiskOperations=1,stages={key:dict(value)for key,value in self.stages.items()})
