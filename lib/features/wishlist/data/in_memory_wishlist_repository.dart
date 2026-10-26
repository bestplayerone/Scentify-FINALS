import 'dart:async';

import 'package:scentify/features/wishlist/domain/repositories/wishlist_repository.dart';

class InMemoryWishlistRepository implements WishlistRepository {
  final Map<String, Set<String>> _wishlists = {};
  final _changes = StreamController<String>.broadcast();

  @override
  Future<Set<String>> findByUserId(String userId) async {
    return Set.unmodifiable(_wishlists[userId] ?? const <String>{});
  }

  @override
  Stream<Set<String>> watch(String userId) {
    late final StreamSubscription<String> subscription;
    final controller = StreamController<Set<String>>(sync: true);
    controller.onListen = () {
      subscription = _changes.stream
          .where((changedUserId) => changedUserId == userId)
          .listen((_) async {
            controller.add(await findByUserId(userId));
          });
      controller.add(
        _wishlists[userId] == null
            ? const <String>{}
            : Set.unmodifiable(_wishlists[userId]!),
      );
    };
    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }

  @override
  Future<void> save(String userId, Set<String> productIds) async {
    _wishlists[userId] = productIds.toSet();
    _changes.add(userId);
  }
}
