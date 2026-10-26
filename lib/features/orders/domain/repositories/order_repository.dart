import 'package:scentify/features/orders/domain/models/order.dart';

abstract interface class OrderRepository {
  Future<void> save(Order order);

  Future<Order?> findById(String orderId);

  Future<List<Order>> forUser(String userId);

  Stream<List<Order>> watchForUser(String userId);

  /// Streams every order for the admin order queue.
  ///
  /// Firestore security rules remain the final authority for this operation;
  /// the UI only exposes it after the signed-in profile has the admin role.
  Stream<List<Order>> watchAll();
}
