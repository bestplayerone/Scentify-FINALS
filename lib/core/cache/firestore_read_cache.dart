import 'dart:async';

typedef CacheClock = DateTime Function();

/// A small app-layer TTL cache for reads where brief staleness is acceptable.
///
/// Firestore's own offline cache has no per-document TTL. This cache avoids
/// repeating the same read while a screen is being rebuilt and coalesces
/// concurrent requests for the same key. Live order/cart state should continue
/// using snapshots rather than this cache.
class FirestoreReadCache<K, V> {
  FirestoreReadCache({
    Duration ttl = const Duration(minutes: 5),
    CacheClock? clock,
    int maxEntries = 128,
  }) : _ttl = ttl,
       _clock = clock ?? DateTime.now,
       _maxEntries = maxEntries {
    if (ttl <= Duration.zero) {
      throw ArgumentError.value(ttl, 'ttl', 'The cache TTL must be positive.');
    }
    if (maxEntries < 1) {
      throw ArgumentError.value(
        maxEntries,
        'maxEntries',
        'The cache must retain at least one entry.',
      );
    }
  }

  final Duration _ttl;
  final CacheClock _clock;
  final int _maxEntries;
  final _entries = <K, _CacheEntry<V>>{};
  final _pending = <K, Future<V>>{};

  int get length => _entries.length;

  Future<V> read(K key, Future<V> Function() loader) {
    final now = _clock();
    final cached = _entries[key];
    if (cached != null && now.difference(cached.fetchedAt) < _ttl) {
      return Future<V>.value(cached.value);
    }

    final pending = _pending[key];
    if (pending != null) {
      return pending;
    }

    final request = loader().then((value) {
      _entries[key] = _CacheEntry(value, _clock());
      _trimToCapacity();
      return value;
    });
    _pending[key] = request;
    return request.whenComplete(() => _pending.remove(key));
  }

  V? peek(K key) {
    final entry = _entries[key];
    if (entry == null || _clock().difference(entry.fetchedAt) >= _ttl) {
      return null;
    }
    return entry.value;
  }

  void put(K key, V value) {
    _entries[key] = _CacheEntry(value, _clock());
    _trimToCapacity();
  }

  void invalidate(K key) {
    _entries.remove(key);
  }

  void clear() {
    _entries.clear();
  }

  void _trimToCapacity() {
    while (_entries.length > _maxEntries) {
      final oldest = _entries.entries.reduce(
        (left, right) =>
            left.value.fetchedAt.isBefore(right.value.fetchedAt) ? left : right,
      );
      _entries.remove(oldest.key);
    }
  }
}

class _CacheEntry<V> {
  const _CacheEntry(this.value, this.fetchedAt);

  final V value;
  final DateTime fetchedAt;
}
