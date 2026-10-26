import 'dart:async';

import 'package:scentify/features/orders/domain/models/order.dart';
import 'package:scentify/features/orders/domain/repositories/order_repository.dart';

class InMemoryOrderRepository implements OrderRepository {
  final Map<String, Order> _orders = {};
  final _changes = StreamController<String>.broadcast();

  @override
  Future<void> save(Order order) async {
    _orders[order.id] = order;
    _changes.add(order.userId);
  }

  @override
  Future<Order?> findById(String orderId) async => _orders[orderId];

  @override
  Future<List<Order>> forUser(String userId) async {
    final results = _orders.values
        .where((order) => order.userId == userId)
        .toList();
    results.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return results;
  }

  @override
  Stream<List<Order>> watchForUser(String userId) {
    late final StreamSubscription<String> subscription;
    final controller = StreamController<List<Order>>(sync: true);
    controller.onListen = () {
      subscription = _changes.stream
          .where((changedUserId) => changedUserId == userId)
          .listen((_) async {
            controller.add(await forUser(userId));
          });
      forUser(userId).then(controller.add);
    };
    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }

  @override
  Stream<List<Order>> watchAll() {
    late final StreamSubscription<String> subscription;
    final controller = StreamController<List<Order>>(sync: true);
    controller.onListen = () {
      subscription = _changes.stream.listen((_) async {
        controller.add(await _all());
      });
      _all().then(controller.add);
    };
    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }

  Future<List<Order>> _all() async {
    final results = _orders.values.toList();
    results.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return results;
  }
}
