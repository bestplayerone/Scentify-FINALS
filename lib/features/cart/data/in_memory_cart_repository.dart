import 'dart:async';

import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/cart/domain/repositories/cart_repository.dart';

class InMemoryCartRepository implements CartRepository {
  final Map<String, Cart> _carts = {};
  final _changes = StreamController<String>.broadcast();

  @override
  Future<Cart?> findByUserId(String userId) async => _carts[userId];

  @override
  Stream<Cart?> watch(String userId) {
    late final StreamSubscription<String> subscription;
    final controller = StreamController<Cart?>(sync: true);
    controller.onListen = () {
      subscription = _changes.stream
          .where((changedUserId) => changedUserId == userId)
          .listen((_) async {
            controller.add(await findByUserId(userId));
          });
      controller.add(_carts[userId]);
    };
    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }

  @override
  Future<void> save(Cart cart) async {
    _carts[cart.userId] = cart;
    _changes.add(cart.userId);
  }

  @override
  Future<void> clear(String userId) async {
    _carts.remove(userId);
    _changes.add(userId);
  }
}
