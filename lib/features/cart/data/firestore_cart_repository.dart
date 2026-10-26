import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scentify/core/firebase/firestore_codecs.dart';
import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/cart/domain/repositories/cart_repository.dart';

class FirestoreCartRepository implements CartRepository {
  FirestoreCartRepository({
    FirebaseFirestore? firestore,
    String collectionName = 'carts',
  }) : _collection = (firestore ?? FirebaseFirestore.instance).collection(
         collectionName,
       );

  final CollectionReference<Map<String, dynamic>> _collection;

  @override
  Future<Cart?> findByUserId(String userId) async {
    final document = await _collection.doc(userId).get();
    if (!document.exists || document.data() == null) {
      return null;
    }
    return FirestoreCodecs.cartFromMap(document.data()!);
  }

  @override
  Stream<Cart?> watch(String userId) {
    return _collection.doc(userId).snapshots().map((document) {
      final data = document.data();
      return !document.exists || data == null
          ? null
          : FirestoreCodecs.cartFromMap(data);
    });
  }

  @override
  Future<void> save(Cart cart) {
    return _collection.doc(cart.userId).set(FirestoreCodecs.cartToMap(cart));
  }

  @override
  Future<void> clear(String userId) => _collection.doc(userId).delete();
}
