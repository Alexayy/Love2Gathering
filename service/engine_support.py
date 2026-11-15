"""Read-only, asynchronous implementation coverage for the installed engine.

This is deliberately separate from format legality and native deck validation.
Only a locally supplied installed-class registry can turn an unknown result
into available/unavailable; no source JSONL or user saves are modified.
"""
from collections import OrderedDict
from contextlib import nullcontext
import hashlib
import json
import re
import threading

ZONES = ('main', 'sideboard', 'commander', 'planes', 'schemes')


def composition(deck):
    rows = [(zone, str(entry['name']), int(entry.get('count', 1)))
            for zone in ZONES for entry in deck.get(zone, [])]
    fingerprint = hashlib.sha256(json.dumps(sorted(rows), ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
    return fingerprint, sorted({name for _, name, _ in rows}, key=str.casefold)


class EngineSupport:
    def __init__(self, storage):
        self.storage = storage
        self.lock = threading.RLock()
        self.wake = threading.Event()
        self.stop = threading.Event()
        self.generation = 0
        self.registry = None
        self.results = OrderedDict()
        self.result_bytes = 0
        self.result_sizes = {}
        self.identities = OrderedDict()
        self.pending = OrderedDict()
        self.pending_ids = OrderedDict()
        self.scan = None
        self.scanned = self.total = 0
        self.error = None
        self.source = None
        self.thread = None

    def register(self, value):
        allowed = {'engineRevision', 'registryRevision', 'names', 'splitNameFallback', 'legalityChecked'}
        if not isinstance(value, dict) or set(value) - allowed:
            raise ValueError('Supply only the installed engine implementation registry')
        for key, length in (('engineRevision', 40), ('registryRevision', 64)):
            if not isinstance(value.get(key), str) or not re.fullmatch('[0-9a-f]{' + str(length) + '}', value[key]):
                raise ValueError('Invalid installed engine revision')
        names = value.get('names')
        if not isinstance(names, list) or not 1 <= len(names) <= 100000:
            raise ValueError('Installed implementation names must contain 1 to 100000 entries')
        if any(not isinstance(name, str) or not 1 <= len(name) <= 300 or any(ord(c) < 32 for c in name) for name in names):
            raise ValueError('Invalid installed implementation name')
        if (value.get('splitNameFallback') is not None and not isinstance(value['splitNameFallback'], bool)) or value.get('legalityChecked') is not None and value['legalityChecked'] is not False:
            raise ValueError('An implementation registry is not a legality result')
        names = frozenset(name.lower() for name in names)
        digest = hashlib.sha256(json.dumps(sorted(names), ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
        registry = dict(engineRevision=value['engineRevision'], registryRevision=value['registryRevision'],
                        names=names, digest=digest, splitNameFallback=value.get('splitNameFallback') is True)
        with self.lock:
            if self.stop.is_set():raise ValueError('Engine support checks have stopped')
            if self.registry and registry['registryRevision'] == self.registry['registryRevision'] and registry['engineRevision'] == self.registry['engineRevision']:
                if registry['digest'] != self.registry['digest'] or registry['splitNameFallback'] != self.registry['splitNameFallback']:
                    raise ValueError('The same registry revision cannot describe different implementations')
                return self.status()
            self.registry = registry
            self.generation += 1
            self.results.clear();self.result_sizes.clear();self.result_bytes = 0;self.identities.clear();self.pending.clear();self.pending_ids.clear()
            self.source = getattr(self.storage, '_precon_signature', None)
            self.scan = '';self.scanned = self.total = 0;self.error = None
            if self.thread is None:
                self.thread = threading.Thread(target=self._work, name='installed-deck-support', daemon=True)
                self.thread.start()
            self.wake.set()
            return self.status()

    def _base(self, state):
        result = {'state': state, 'generation': self.generation, 'legalityChecked': False, 'missingNames': []}
        if self.registry:
            result.update(engineRevision=self.registry['engineRevision'], registryRevision=self.registry['registryRevision'])
        return result

    def _source_changed(self):
        current = getattr(self.storage, '_precon_signature', None)
        if self.registry and self.source != current:
            self.source = current;self.generation += 1
            self.results.clear();self.result_sizes.clear();self.result_bytes = 0;self.identities.clear();self.pending.clear();self.pending_ids.clear()
            self.scan = '';self.scanned = self.total = 0;self.error = None;self.wake.set()

    def status(self):
        with self.lock:
            self._source_changed()
            value = self._base('unknown' if not self.registry else 'checking' if self.scan is not None or self.pending or self.pending_ids else 'ready')
            value.update(scanned=self.scanned, total=self.total, cached=len(self.results), error=self.error)
            return value

    def for_deck(self, deck):
        fingerprint, names = composition(deck)
        with self.lock:
            self._source_changed()
            if not self.registry:return self._base('unknown')
            if deck.get('id'):self._remember_identity(deck['id'], fingerprint)
            result = self.results.get(fingerprint)
            if result:
                self.results.move_to_end(fingerprint)
                return dict(result, missingNames=list(result['missingNames']))
            if len(self.pending) < 256:self.pending[fingerprint] = names
            self.wake.set()
            return dict(self._base('checking'), fingerprint=fingerprint)

    def for_id(self, identifier):
        with self.lock:
            self._source_changed()
            if not self.registry:return self._base('unknown')
            fingerprint = self.identities.get(identifier)
            result = self.results.get(fingerprint)
            if result:return dict(result, missingNames=list(result['missingNames']))
            if fingerprint not in self.pending and len(self.pending_ids) < 256:self.pending_ids[identifier] = True;self.wake.set()
            return dict(self._base('checking'), **({'fingerprint': fingerprint} if fingerprint else {}))

    def _remember_identity(self, identifier, fingerprint):
        self.identities[identifier] = fingerprint;self.identities.move_to_end(identifier)
        while len(self.identities) > 8192:self.identities.popitem(last=False)

    def decorate(self, decks):
        for deck in decks:
            deck['engineSupport'] = self.for_deck(deck) if 'main' in deck else self.for_id(deck['id'])
        return decks

    def batch(self, identifiers):
        if not isinstance(identifiers, list) or len(identifiers) > 60:
            raise ValueError('Check up to 60 deck identities at once')
        for identifier in identifiers:self.storage.check_id(identifier)
        return {'status': self.status(), 'decks': {identifier: self.for_id(identifier) for identifier in identifiers}}

    def _check(self, fingerprint, names, registry, generation):
        def known(name):
            key = name.lower()
            return key in registry['names'] or (registry['splitNameFallback'] and ' // ' in key and key.split(' // ', 1)[0] in registry['names'])
        missing = [name for name in names if not known(name)]
        with self.lock:
            if self.generation != generation or self.registry is not registry:return
            result = dict(self._base('unavailable' if missing else 'ready'), fingerprint=fingerprint,
                          available=not missing, checkedNames=len(names), missingNames=missing)
            self.result_bytes -= self.result_sizes.get(fingerprint, 0)
            self.result_sizes[fingerprint] = len(json.dumps(result, ensure_ascii=False).encode())
            self.result_bytes += self.result_sizes[fingerprint]
            self.results[fingerprint] = result;self.results.move_to_end(fingerprint)
            while len(self.results) > 4096 or self.result_bytes > 8 * 1024 * 1024:
                oldest, _ = self.results.popitem(last=False)
                self.result_bytes -= self.result_sizes.pop(oldest)

    def _read_page(self, after):
        scope = self.storage.interactive_access(timeout=.5) if hasattr(self.storage, 'interactive_access') else nullcontext()
        with scope, self.storage.connection() as connection:
            total = connection.execute("SELECT count(*) FROM preconstructed WHERE active=1 AND category IN ('deck','packet')").fetchone()[0]
            rows = list(connection.execute("SELECT id,payload FROM preconstructed WHERE active=1 AND category IN ('deck','packet') AND id>? ORDER BY id LIMIT 24", (after,)))
        return total, rows

    def _work(self):
        while not self.stop.is_set():
            self.wake.wait(.5);self.wake.clear()
            while not self.stop.is_set():
                with self.lock:
                    registry, generation = self.registry, self.generation
                    if not registry:break
                    task = self.pending.popitem(last=False) if self.pending else None
                    identifier = self.pending_ids.popitem(last=False)[0] if not task and self.pending_ids else None
                    after = self.scan
                try:
                    if task:self._check(task[0], task[1], registry, generation);continue
                    if identifier:
                        scope = self.storage.interactive_access(timeout=.5) if hasattr(self.storage, 'interactive_access') else nullcontext()
                        with scope:deck = self.storage.get_deck(identifier)
                        if deck:self.for_deck(deck)
                        continue
                    if after is None:break
                    total, rows = self._read_page(after)
                    with self.lock:
                        if self.generation == generation:self.error = None
                    for row in rows:
                        if self.stop.is_set():break
                        deck = json.loads(row['payload']);fingerprint, names = composition(deck)
                        self._check(fingerprint, names, registry, generation)
                        with self.lock:
                            if self.generation != generation:break
                            self._remember_identity(row['id'], fingerprint);self.scanned += 1
                    with self.lock:
                        if self.generation == generation:
                            self.total = total;self.scan = rows[-1]['id'] if rows else None
                except Exception as exc:
                    with self.lock:
                        if self.generation == generation:self.error = str(exc)
                    # Maintenance, relocation and transient reads remain unknown
                    # rather than being mislabeled as unimplemented cards.
                    self.stop.wait(.5)
                    self.wake.set();break

    def close(self):
        self.stop.set();self.wake.set()
        if self.thread is not None:self.thread.join(timeout=2)
