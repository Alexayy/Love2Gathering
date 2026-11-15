"""Bounded detached metadata results for an atomically replaced local index."""
from collections import OrderedDict
from functools import wraps
import json
import threading


class QueryCache:
    def __init__(self, path, entries=256, max_bytes=8 * 1024 * 1024):
        self.path = path
        self.entries, self.max_bytes = entries, max_bytes
        self.lock = threading.Lock()
        self.values = OrderedDict()
        self.bytes = 0
        self.generation = None

    def identity(self):
        try:
            value = self.path.stat()
            return value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns
        except OSError:
            return None

    def get(self, key, generation):
        with self.lock:
            if self.generation != generation:
                self.values.clear()
                self.bytes = 0
                self.generation = generation
            payload = self.values.get(key)
            if payload is not None:
                self.values.move_to_end(key)
        # Every caller owns its result; gallery/cache flags cannot contaminate
        # another printing, deck selection or later search response.
        return (True, json.loads(payload)) if payload is not None else (False, None)

    def put(self, key, value, generation):
        payload = json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        size = len(key) + len(payload)
        if size > self.max_bytes or self.identity() != generation:
            return
        with self.lock:
            if self.generation != generation:
                return
            old = self.values.pop(key, None)
            if old is not None:
                self.bytes -= len(key) + len(old)
            self.values[key] = payload
            self.bytes += size
            while len(self.values) > self.entries or self.bytes > self.max_bytes:
                dropped, contents = self.values.popitem(last=False)
                self.bytes -= len(dropped) + len(contents)


def cached_query(function):
    @wraps(function)
    def query(self, *args, **kwargs):
        cache = self.query_cache
        generation = cache.identity()
        key = json.dumps((function.__name__, args, kwargs), sort_keys=True, ensure_ascii=False).encode('utf-8')
        found, value = cache.get(key, generation)
        if found:
            return value
        value = function(self, *args, **kwargs)
        cache.put(key, value, generation)
        return value
    return query
