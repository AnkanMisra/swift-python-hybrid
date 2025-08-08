import asyncio
import hashlib
import json
import pickle
import time
import threading
from abc import ABC, abstractmethod
from collections import OrderedDict
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from functools import wraps
from typing import Any, Dict, List, Optional, Union, Callable, TypeVar, Generic
from weakref import WeakValueDictionary
import logging

T = TypeVar('T')

class CacheBackend(Enum):
    MEMORY = "memory"
    REDIS = "redis"
    MEMCACHED = "memcached"
    FILE = "file"
    HYBRID = "hybrid"

class EvictionPolicy(Enum):
    LRU = "lru"
    LFU = "lfu"
    FIFO = "fifo"
    TTL = "ttl"
    RANDOM = "random"

class CacheLevel(Enum):
    L1 = 1
    L2 = 2
    L3 = 3

@dataclass
class CacheEntry:
    key: str
    value: Any
    created_at: float
    last_accessed: float
    access_count: int = 0
    ttl: Optional[float] = None
    size: int = 0
    tags: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)

    def __post_init__(self):
        if self.size == 0:
            self.size = self._calculate_size()

    def _calculate_size(self) -> int:
        try:
            return len(pickle.dumps(self.value))
        except:
            return len(str(self.value).encode('utf-8'))

    def is_expired(self) -> bool:
        if self.ttl is None:
            return False
        return time.time() - self.created_at > self.ttl

    def touch(self):
        self.last_accessed = time.time()
        self.access_count += 1

@dataclass
class CacheStats:
    hits: int = 0
    misses: int = 0
    evictions: int = 0
    total_size: int = 0
    entry_count: int = 0
    hit_rate: float = 0.0
    average_access_time: float = 0.0
    memory_usage: int = 0

    def update_hit_rate(self):
        total = self.hits + self.misses
        self.hit_rate = self.hits / total if total > 0 else 0.0

class CacheInterface(ABC):
    @abstractmethod
    def get(self, key: str) -> Optional[Any]:
        pass

    @abstractmethod
    def set(self, key: str, value: Any, ttl: Optional[float] = None) -> bool:
        pass

    @abstractmethod
    def delete(self, key: str) -> bool:
        pass

    @abstractmethod
    def clear(self) -> bool:
        pass

    @abstractmethod
    def exists(self, key: str) -> bool:
        pass

    @abstractmethod
    def get_stats(self) -> CacheStats:
        pass

class MemoryCache(CacheInterface):
    def __init__(self, max_size: int = 1000, max_memory: int = 100 * 1024 * 1024,
                 eviction_policy: EvictionPolicy = EvictionPolicy.LRU):
        self.max_size = max_size
        self.max_memory = max_memory
        self.eviction_policy = eviction_policy
        self._cache: Dict[str, CacheEntry] = {}
        self._access_order: OrderedDict = OrderedDict()
        self._stats = CacheStats()
        self._lock = threading.RLock()
        self._cleanup_thread = None
        self._start_cleanup_thread()

    def get(self, key: str) -> Optional[Any]:
        start_time = time.time()

        with self._lock:
            if key not in self._cache:
                self._stats.misses += 1
                return None

            entry = self._cache[key]

            if entry.is_expired():
                del self._cache[key]
                if key in self._access_order:
                    del self._access_order[key]
                self._stats.misses += 1
                self._stats.evictions += 1
                return None

            entry.touch()
            self._update_access_order(key)
            self._stats.hits += 1

            access_time = time.time() - start_time
            self._update_average_access_time(access_time)

            return entry.value

    def set(self, key: str, value: Any, ttl: Optional[float] = None,
            tags: List[str] = None) -> bool:
        with self._lock:
            entry = CacheEntry(
                key=key,
                value=value,
                created_at=time.time(),
                last_accessed=time.time(),
                ttl=ttl,
                tags=tags or []
            )

            if key in self._cache:
                old_entry = self._cache[key]
                self._stats.total_size -= old_entry.size
            else:
                self._stats.entry_count += 1

            self._cache[key] = entry
            self._access_order[key] = True
            self._stats.total_size += entry.size

            self._enforce_limits()
            self._stats.update_hit_rate()

            return True

    def delete(self, key: str) -> bool:
        with self._lock:
            if key in self._cache:
                entry = self._cache[key]
                del self._cache[key]
                if key in self._access_order:
                    del self._access_order[key]
                self._stats.total_size -= entry.size
                self._stats.entry_count -= 1
                return True
            return False

    def clear(self) -> bool:
        with self._lock:
            self._cache.clear()
            self._access_order.clear()
            self._stats = CacheStats()
            return True

    def exists(self, key: str) -> bool:
        with self._lock:
            if key not in self._cache:
                return False
            return not self._cache[key].is_expired()

    def get_stats(self) -> CacheStats:
        with self._lock:
            self._stats.memory_usage = sum(entry.size for entry in self._cache.values())
            return self._stats

    def get_by_tags(self, tags: List[str]) -> Dict[str, Any]:
        with self._lock:
            result = {}
            for key, entry in self._cache.items():
                if not entry.is_expired() and any(tag in entry.tags for tag in tags):
                    result[key] = entry.value
            return result

    def delete_by_tags(self, tags: List[str]) -> int:
        with self._lock:
            keys_to_delete = []
            for key, entry in self._cache.items():
                if any(tag in entry.tags for tag in tags):
                    keys_to_delete.append(key)

            for key in keys_to_delete:
                self.delete(key)

            return len(keys_to_delete)

    def _update_access_order(self, key: str):
        if self.eviction_policy == EvictionPolicy.LRU:
            self._access_order.move_to_end(key)

    def _enforce_limits(self):
        while (len(self._cache) > self.max_size or
               self._stats.total_size > self.max_memory):
            self._evict_one()

    def _evict_one(self):
        if not self._cache:
            return

        if self.eviction_policy == EvictionPolicy.LRU:
            key = next(iter(self._access_order))
        elif self.eviction_policy == EvictionPolicy.LFU:
            key = min(self._cache.keys(),
                     key=lambda k: self._cache[k].access_count)
        elif self.eviction_policy == EvictionPolicy.FIFO:
            key = min(self._cache.keys(),
                     key=lambda k: self._cache[k].created_at)
        elif self.eviction_policy == EvictionPolicy.TTL:
            expired_keys = [k for k, v in self._cache.items() if v.is_expired()]
            if expired_keys:
                key = expired_keys[0]
            else:
                key = next(iter(self._cache))
        else:
            import random
            key = random.choice(list(self._cache.keys()))

        self.delete(key)
        self._stats.evictions += 1

    def _cleanup_expired(self):
        with self._lock:
            expired_keys = [k for k, v in self._cache.items() if v.is_expired()]
            for key in expired_keys:
                self.delete(key)
                self._stats.evictions += 1

    def _start_cleanup_thread(self):
        def cleanup_worker():
            while True:
                time.sleep(60)
                self._cleanup_expired()

        self._cleanup_thread = threading.Thread(target=cleanup_worker, daemon=True)
        self._cleanup_thread.start()

    def _update_average_access_time(self, access_time: float):
        total_accesses = self._stats.hits + self._stats.misses
        if total_accesses > 0:
            self._stats.average_access_time = (
                (self._stats.average_access_time * (total_accesses - 1) + access_time)
                / total_accesses
            )

class MultiLevelCache:
    def __init__(self):
        self.levels: Dict[CacheLevel, CacheInterface] = {}
        self._stats = CacheStats()

    def add_level(self, level: CacheLevel, cache: CacheInterface):
        self.levels[level] = cache

    def get(self, key: str) -> Optional[Any]:
        for level in sorted(self.levels.keys(), key=lambda x: x.value):
            cache = self.levels[level]
            value = cache.get(key)
            if value is not None:
                self._promote_to_higher_levels(key, value, level)
                self._stats.hits += 1
                return value

        self._stats.misses += 1
        return None

    def set(self, key: str, value: Any, ttl: Optional[float] = None) -> bool:
        success = True
        for cache in self.levels.values():
            success &= cache.set(key, value, ttl)
        return success

    def delete(self, key: str) -> bool:
        success = True
        for cache in self.levels.values():
            success &= cache.delete(key)
        return success

    def clear(self) -> bool:
        success = True
        for cache in self.levels.values():
            success &= cache.clear()
        return success

    def exists(self, key: str) -> bool:
        return any(cache.exists(key) for cache in self.levels.values())

    def get_stats(self) -> Dict[CacheLevel, CacheStats]:
        return {level: cache.get_stats() for level, cache in self.levels.items()}

    def _promote_to_higher_levels(self, key: str, value: Any, found_level: CacheLevel):
        for level in sorted(self.levels.keys(), key=lambda x: x.value):
            if level.value < found_level.value:
                self.levels[level].set(key, value)

class CacheManager:
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self):
        if not hasattr(self, 'initialized'):
            self.caches: Dict[str, CacheInterface] = {}
            self.default_cache = MemoryCache()
            self.caches['default'] = self.default_cache
            self.initialized = True

    def create_cache(self, name: str, backend: CacheBackend = CacheBackend.MEMORY,
                    **kwargs) -> CacheInterface:
        if backend == CacheBackend.MEMORY:
            cache = MemoryCache(**kwargs)
        elif backend == CacheBackend.HYBRID:
            cache = MultiLevelCache()
            cache.add_level(CacheLevel.L1, MemoryCache(max_size=100))
            cache.add_level(CacheLevel.L2, MemoryCache(max_size=1000))
        else:
            raise NotImplementedError(f"Backend {backend} not implemented")

        self.caches[name] = cache
        return cache

    def get_cache(self, name: str = 'default') -> CacheInterface:
        return self.caches.get(name, self.default_cache)

    def delete_cache(self, name: str) -> bool:
        if name in self.caches and name != 'default':
            del self.caches[name]
            return True
        return False

    def get_all_stats(self) -> Dict[str, CacheStats]:
        return {name: cache.get_stats() for name, cache in self.caches.items()}

def cache_result(cache_name: str = 'default', ttl: Optional[float] = None,
                key_func: Optional[Callable] = None, tags: List[str] = None):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            cache = CacheManager().get_cache(cache_name)

            if key_func:
                cache_key = key_func(*args, **kwargs)
            else:
                cache_key = _generate_cache_key(func.__name__, args, kwargs)

            result = cache.get(cache_key)
            if result is not None:
                return result

            result = func(*args, **kwargs)
            if hasattr(cache, 'set'):
                if hasattr(cache, '_cache') and hasattr(cache._cache.get(cache_key, None), 'tags'):
                    cache.set(cache_key, result, ttl, tags)
                else:
                    cache.set(cache_key, result, ttl)

            return result
        return wrapper
    return decorator

def async_cache_result(cache_name: str = 'default', ttl: Optional[float] = None,
                      key_func: Optional[Callable] = None):
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            cache = CacheManager().get_cache(cache_name)

            if key_func:
                cache_key = key_func(*args, **kwargs)
            else:
                cache_key = _generate_cache_key(func.__name__, args, kwargs)

            result = cache.get(cache_key)
            if result is not None:
                return result

            result = await func(*args, **kwargs)
            cache.set(cache_key, result, ttl)

            return result
        return wrapper
    return decorator

def _generate_cache_key(func_name: str, args: tuple, kwargs: dict) -> str:
    key_data = {
        'func': func_name,
        'args': args,
        'kwargs': sorted(kwargs.items())
    }

    key_string = json.dumps(key_data, sort_keys=True, default=str)
    return hashlib.md5(key_string.encode()).hexdigest()

class CacheWarmer:
    def __init__(self, cache: CacheInterface):
        self.cache = cache
        self.warming_tasks: List[Callable] = []

    def add_warming_task(self, func: Callable, *args, **kwargs):
        self.warming_tasks.append(lambda: func(*args, **kwargs))

    def warm_cache(self, parallel: bool = True):
        if parallel:
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor() as executor:
                futures = [executor.submit(task) for task in self.warming_tasks]
                concurrent.futures.wait(futures)
        else:
            for task in self.warming_tasks:
                task()

class CacheMonitor:
    def __init__(self, cache_manager: CacheManager):
        self.cache_manager = cache_manager
        self.monitoring = False
        self.monitor_thread = None

    def start_monitoring(self, interval: float = 60.0):
        if self.monitoring:
            return

        self.monitoring = True

        def monitor_worker():
            while self.monitoring:
                stats = self.cache_manager.get_all_stats()
                self._log_stats(stats)
                time.sleep(interval)

        self.monitor_thread = threading.Thread(target=monitor_worker, daemon=True)
        self.monitor_thread.start()

    def stop_monitoring(self):
        self.monitoring = False
        if self.monitor_thread:
            self.monitor_thread.join()

    def _log_stats(self, stats: Dict[str, CacheStats]):
        for cache_name, cache_stats in stats.items():
            logging.info(
                f"Cache '{cache_name}': "
                f"Hit Rate: {cache_stats.hit_rate:.2%}, "
                f"Entries: {cache_stats.entry_count}, "
                f"Memory: {cache_stats.memory_usage / 1024 / 1024:.2f}MB"
            )

class CacheBatch:
    def __init__(self, cache: CacheInterface):
        self.cache = cache
        self.operations: List[tuple] = []

    def get(self, key: str):
        self.operations.append(('get', key))
        return self

    def set(self, key: str, value: Any, ttl: Optional[float] = None):
        self.operations.append(('set', key, value, ttl))
        return self

    def delete(self, key: str):
        self.operations.append(('delete', key))
        return self

    def execute(self) -> List[Any]:
        results = []
        for operation in self.operations:
            op_type = operation[0]

            if op_type == 'get':
                results.append(self.cache.get(operation[1]))
            elif op_type == 'set':
                results.append(self.cache.set(*operation[1:]))
            elif op_type == 'delete':
                results.append(self.cache.delete(operation[1]))

        self.operations.clear()
        return results

class DistributedCache:
    def __init__(self, nodes: List[str]):
        self.nodes = nodes
        self.local_cache = MemoryCache()
        self.hash_ring = self._build_hash_ring()

    def _build_hash_ring(self) -> Dict[int, str]:
        ring = {}
        for node in self.nodes:
            for i in range(100):
                key = hashlib.md5(f"{node}:{i}".encode()).hexdigest()
                ring[int(key, 16)] = node
        return dict(sorted(ring.items()))

    def _get_node(self, key: str) -> str:
        key_hash = int(hashlib.md5(key.encode()).hexdigest(), 16)
        for ring_key in sorted(self.hash_ring.keys()):
            if key_hash <= ring_key:
                return self.hash_ring[ring_key]
        return self.hash_ring[min(self.hash_ring.keys())]

    def get(self, key: str) -> Optional[Any]:
        local_result = self.local_cache.get(key)
        if local_result is not None:
            return local_result

        node = self._get_node(key)
        return None

    def set(self, key: str, value: Any, ttl: Optional[float] = None) -> bool:
        self.local_cache.set(key, value, ttl)
        node = self._get_node(key)
        return True

    def delete(self, key: str) -> bool:
        self.local_cache.delete(key)
        node = self._get_node(key)
        return True
