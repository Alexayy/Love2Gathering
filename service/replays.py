"""Immutable, idempotent replay events stored transactionally in the app DB."""
import hashlib
import json
import time
import uuid

def encode(value):
    return json.dumps(value,ensure_ascii=False,separators=(",",":"),sort_keys=True,allow_nan=False)

def now(): return int(time.time()*1000)

class ConflictError(ValueError): pass

class ReplayStore:
    def create_replay(self,value):
        if not isinstance(value,dict): raise ValueError("Replay metadata must be an object")
        identifier=self.check_id(value.get("id") or "replay-"+uuid.uuid4().hex)
        payload={key:item for key,item in value.items() if key not in ("status","eventCount","lastSequence")}
        payload["id"]=identifier
        if len(encode(payload))>1024*1024: raise ValueError("Replay metadata exceeds 1 MB")
        with self.connection(write=True) as c:
            previous=c.execute("SELECT payload FROM replays WHERE id=?",(identifier,)).fetchone()
            if previous:
                if previous[0]!=encode(payload): raise ConflictError("Replay ID has different metadata")
            else:
                stamp=now();c.execute("INSERT INTO replays VALUES (?,?,'recording',?,?,NULL)",(identifier,encode(payload),stamp,stamp))
        return self.get_replay(identifier)

    def _replay(self,c,identifier):
        row=c.execute("SELECT * FROM replays WHERE id=?",(identifier,)).fetchone()
        if not row:return None
        result=json.loads(row["payload"])
        counts=c.execute("SELECT count(*) AS total,max(sequence) AS latest,sum(type='frame') AS frames,sum(type='action') AS actions,sum(type='log') AS logs,sum(type='error') AS errors FROM replay_events WHERE replay_id=?",(identifier,)).fetchone()
        result.update(id=identifier,status=row["status"],createdAt=row["created_at"],updatedAt=row["updated_at"],finishedAt=row["finished_at"],eventCount=counts["total"],lastSequence=counts["latest"],frameCount=counts["frames"] or 0,actionCount=counts["actions"] or 0,logCount=counts["logs"] or 0,errorCount=counts["errors"] or 0)
        return result

    def get_replay(self,identifier):
        self.check_id(identifier)
        with self.connection() as c:return self._replay(c,identifier)

    def list_replays(self,limit=50,offset=0):
        with self.connection() as c:
            total=c.execute("SELECT count(*) FROM replays").fetchone()[0]
            ids=[row[0] for row in c.execute("SELECT id FROM replays ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?",(limit,offset))]
            items=[self._replay(c,identifier) for identifier in ids]
        return {"replays":items,"total":total,"limit":limit,"offset":offset}

    def append_replay_events(self,identifier,events):
        self.check_id(identifier)
        if not isinstance(events,list) or not 1<=len(events)<=2000:raise ValueError("Send 1 to 2000 replay events per batch")
        prepared=[]
        for event in events:
            if not isinstance(event,dict):raise ValueError("Invalid replay event")
            seq,kind=event.get("sequence"),event.get("type")
            if isinstance(seq,bool) or not isinstance(seq,int) or not 0<=seq<=9223372036854775807:raise ValueError("Replay sequence must be a nonnegative integer")
            if kind not in ("frame","action","log","error") or "data" not in event:raise ValueError("Event needs type frame/action/log/error and data")
            stamp=event.get("timestamp")
            if stamp is not None and (isinstance(stamp,bool) or not isinstance(stamp,(str,int,float))):raise ValueError("Invalid event timestamp")
            canonical=encode({"type":kind,"timestamp":stamp,"data":event["data"]})
            prepared.append((seq,kind,encode(stamp) if stamp is not None else None,encode(event["data"]),hashlib.sha256(canonical.encode()).hexdigest()))
        inserted=0
        with self.connection(write=True) as c:
            replay=c.execute("SELECT status FROM replays WHERE id=?",(identifier,)).fetchone()
            if not replay:raise KeyError("Replay not found")
            for seq,kind,stamp,body,digest in prepared:
                previous=c.execute("SELECT digest FROM replay_events WHERE replay_id=? AND sequence=?",(identifier,seq)).fetchone()
                if previous:
                    if previous[0]!=digest:raise ConflictError("Replay sequence contains different data: "+str(seq))
                    continue
                if replay["status"]!="recording":raise ConflictError("Cannot append new events to a finished replay")
                c.execute("INSERT INTO replay_events VALUES (?,?,?,?,?,?)",(identifier,seq,kind,stamp,body,digest));inserted+=1
            if inserted:c.execute("UPDATE replays SET updated_at=? WHERE id=?",(now(),identifier))
            result=self._replay(c,identifier)
        return {"id":identifier,"inserted":inserted,"eventCount":result["eventCount"],"frameCount":result["frameCount"],"lastSequence":result["lastSequence"]}

    def replay_events(self,identifier,limit=100,offset=0,frames_only=False):
        self.check_id(identifier);where="replay_id=?"+(" AND type='frame'" if frames_only else "")
        with self.connection() as c:
            if not c.execute("SELECT 1 FROM replays WHERE id=?",(identifier,)).fetchone():raise KeyError("Replay not found")
            total=c.execute("SELECT count(*) FROM replay_events WHERE "+where,(identifier,)).fetchone()[0]
            rows=c.execute("SELECT * FROM replay_events WHERE "+where+" ORDER BY sequence LIMIT ? OFFSET ?",(identifier,limit,offset))
            events=[{"sequence":r["sequence"],"type":r["type"],"timestamp":json.loads(r["timestamp"]) if r["timestamp"] else None,"data":json.loads(r["payload"])} for r in rows]
        return {"frames" if frames_only else "events":events,"total":total,"limit":limit,"offset":offset}

    def finish_replay(self,identifier,value):
        self.check_id(identifier)
        if not isinstance(value,dict) or value.get("status","completed") not in ("completed","failed","aborted"):raise ValueError("Replay status must be completed, failed or aborted")
        status=value.get("status","completed")
        with self.connection(write=True) as c:
            row=c.execute("SELECT payload,status FROM replays WHERE id=?",(identifier,)).fetchone()
            if not row:raise KeyError("Replay not found")
            payload=json.loads(row["payload"])
            if row["status"]!="recording":
                if row["status"]!=status:raise ConflictError("Replay already finished with a different status")
                if any(key in value and payload.get(key)!=value[key] for key in ("result","error","finishedAt")):raise ConflictError("Replay already finished with different details")
                return self._replay(c,identifier)
            for key in ("result","error","finishedAt"):
                if key in value:payload[key]=value[key]
            stamp=now();c.execute("UPDATE replays SET payload=?,status=?,updated_at=?,finished_at=COALESCE(finished_at,?) WHERE id=?",(encode(payload),status,stamp,stamp,identifier))
        return self.get_replay(identifier)

    def delete_replay(self,identifier):
        self.check_id(identifier)
        with self.connection(write=True) as c:return c.execute("DELETE FROM replays WHERE id=?",(identifier,)).rowcount>0
