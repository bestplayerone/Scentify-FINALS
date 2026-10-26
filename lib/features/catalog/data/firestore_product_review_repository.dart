import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:scentify/core/ratings/product_rating_api.dart';
import 'package:scentify/features/catalog/domain/models/product_review.dart';
import 'package:scentify/features/catalog/domain/repositories/product_review_repository.dart';
import 'package:scentify/features/orders/domain/models/order.dart';

class FirestoreProductReviewRepository implements ProductReviewRepository {
  FirestoreProductReviewRepository({
    FirebaseFirestore? firestore,
    ProductRatingApi? ratingApi,
    String collectionName = 'perfumes',
  }) : _products = (firestore ?? FirebaseFirestore.instance).collection(
         collectionName,
       ),
       _ratingApi = ratingApi ?? ProductRatingApi();

  final CollectionReference<Map<String, dynamic>> _products;
  final ProductRatingApi _ratingApi;

  CollectionReference<Map<String, dynamic>> _ratings(String productId) =>
      _products.doc(productId).collection('ratings');

  @override
  Stream<List<ProductReview>> watchForProduct(String productId) {
    return _ratings(productId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((document) => _decode(document.id, document.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<ProductReview> submit({
    required Order order,
    required OrderItemSnapshot item,
    required int rating,
    String title = '',
    String comment = '',
  }) async {
    final result = await _ratingApi.submit(
      orderId: order.id,
      productId: item.productId,
      variantId: item.variantId,
      rating: rating,
      title: title,
      comment: comment,
    );
    return ProductReview(
      id: result.reviewId,
      orderId: order.id,
      productId: result.productId,
      variantId: result.variantId,
      rating: result.rating,
      title: result.title,
      comment: result.comment,
      verifiedPurchase: result.verifiedPurchase,
      createdAt: result.createdAt,
    );
  }

  @override
  Future<bool> hasReviewForOrderItem({
    required String orderId,
    required String productId,
    required String variantId,
  }) async {
    final candidate = '${orderId}_${productId}_$variantId';
    final reviewId = candidate.length > 512
        ? candidate.substring(0, 512)
        : candidate;
    final document = await _ratings(productId).doc(reviewId).get();
    return document.exists;
  }

  ProductReview _decode(String id, Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    return ProductReview(
      id: id,
      orderId: _string(data['orderId'], 'orderId'),
      productId: _string(data['productId'], 'productId'),
      variantId: _string(data['variantId'], 'variantId'),
      rating: _integer(data['rating'], 'rating'),
      title: data['title'] is String ? data['title'] as String : '',
      comment: data['comment'] is String ? data['comment'] as String : '',
      verifiedPurchase: data['verifiedPurchase'] == true,
      createdAt: _date(createdAt),
    );
  }

  String _string(Object? value, String field) {
    if (value is String) return value;
    throw FormatException('Expected $field to be a string.');
  }

  int _integer(Object? value, String field) {
    if (value is int) return value;
    throw FormatException('Expected $field to be an integer.');
  }

  DateTime _date(Object? value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    throw const FormatException('The review timestamp is invalid.');
  }
}
