import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:scentify/core/firebase/firestore_codecs.dart';
import 'package:scentify/features/orders/domain/models/order.dart';
import 'package:scentify/features/orders/domain/repositories/order_repository.dart';

class FirestoreOrderRepository implements OrderRepository {
  FirestoreOrderRepository({
    FirebaseFirestore? firestore,
    String collectionName = 'orders',
  }) : _collection = (firestore ?? FirebaseFirestore.instance).collection(
         collectionName,
       );

  final CollectionReference<Map<String, dynamic>> _collection;

  @override
  Future<void> save(Order order) {
    return _collection.doc(order.id).set(FirestoreCodecs.orderToMap(order));
  }

  @override
  Future<Order?> findById(String orderId) async {
    final document = await _collection.doc(orderId).get();
    if (!document.exists || document.data() == null) {
      return null;
    }
    return FirestoreCodecs.orderFromMap(document.data()!, id: orderId);
  }

  @override
  Future<List<Order>> forUser(String userId) async {
    final snapshot = await _collection.where('userId', isEqualTo: userId).get();
    final orders = snapshot.docs
        .map(
          (document) =>
              FirestoreCodecs.orderFromMap(document.data(), id: document.id),
        )
        .toList();
    orders.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return orders;
  }

  @override
  Stream<List<Order>> watchForUser(String userId) {
    return _collection.where('userId', isEqualTo: userId).snapshots().map((
      snapshot,
    ) {
      final orders = snapshot.docs
          .map(
            (document) =>
                FirestoreCodecs.orderFromMap(document.data(), id: document.id),
          )
          .toList();
      orders.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return orders;
    });
  }

  @override
  Stream<List<Order>> watchAll() {
    return _collection.snapshots().map((snapshot) {
      final orders = snapshot.docs
          .map(
            (document) =>
                FirestoreCodecs.orderFromMap(document.data(), id: document.id),
          )
          .toList();
      orders.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return orders;
    });
  }
}
