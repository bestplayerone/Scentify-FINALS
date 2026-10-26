import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scentify/features/wishlist/domain/repositories/wishlist_repository.dart';

class FirestoreWishlistRepository implements WishlistRepository {
  FirestoreWishlistRepository({
    FirebaseFirestore? firestore,
    String collectionName = 'wishlists',
  }) : _collection = (firestore ?? FirebaseFirestore.instance).collection(
         collectionName,
       );

  final CollectionReference<Map<String, dynamic>> _collection;

  @override
  Future<Set<String>> findByUserId(String userId) async {
    final document = await _collection.doc(userId).get();
    return _decode(document.data());
  }

  @override
  Stream<Set<String>> watch(String userId) {
    return _collection.doc(userId).snapshots().map((document) {
      return _decode(document.data());
    });
  }

  static final _productIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$');

  @override
  Future<void> save(String userId, Set<String> productIds) async {
    if (productIds.length > 100 || productIds.any((id) => !_isValidProductId(id))) {
      throw const FormatException(
        'Expected wishlist productIds to contain at most 100 valid product IDs.',
      );
    }
    await _collection.doc(userId).set({'productIds': productIds.toList()});
  }

  Set<String> _decode(Map<String, dynamic>? data) {
    final rawProductIds = data?['productIds'];
    if (rawProductIds == null) {
      return const <String>{};
    }
    if (rawProductIds is! List) {
      throw const FormatException('Expected wishlist productIds to be a list.');
    }
    return Set.unmodifiable(
      rawProductIds.whereType<String>().where(_isValidProductId),
    );
  }

  bool _isValidProductId(String value) =>
      value.length <= 128 && _productIdPattern.hasMatch(value);
}
