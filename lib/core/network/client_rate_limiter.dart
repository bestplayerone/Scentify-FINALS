class ClientRateLimitException implements Exception {
  const ClientRateLimitException(this.retryAfter);

  final Duration retryAfter;

  @override
  String toString() => 'Too many requests; retry after $retryAfter.';
}

/// A UX guard only. Server callables remain the security boundary.
class ClientRateLimiter {
  ClientRateLimiter({
    this.limit = 4,
    this.window = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (limit < 1 || window <= Duration.zero) {
      throw ArgumentError('A positive limit and window are required.');
    }
  }

  final int limit;
  final Duration window;
  final DateTime Function() _clock;
  final _timestamps = <String, List<DateTime>>{};

  bool allow(String key) {
    final now = _clock();
    final cutoff = now.subtract(window);
    final timestamps = _timestamps.putIfAbsent(key, () => <DateTime>[])
      ..removeWhere((timestamp) => timestamp.isBefore(cutoff));
    if (timestamps.length >= limit) {
      return false;
    }
    timestamps.add(now);
    return true;
  }

  Duration retryAfter(String key) {
    final timestamps = _timestamps[key];
    if (timestamps == null || timestamps.isEmpty) return Duration.zero;
    final remaining = window - _clock().difference(timestamps.first);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void require(String key) {
    if (!allow(key)) {
      throw ClientRateLimitException(retryAfter(key));
    }
  }

  void clear() => _timestamps.clear();
}
