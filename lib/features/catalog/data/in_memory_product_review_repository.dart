import 'dart:async';

import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/features/catalog/domain/models/product_review.dart';
import 'package:scentify/features/catalog/domain/repositories/product_review_repository.dart';
import 'package:scentify/features/orders/domain/models/order.dart';

class InMemoryProductReviewRepository implements ProductReviewRepository {
  final Map<String, List<ProductReview>> _reviewsByProduct = {};
  final _changes = StreamController<String>.broadcast();

  Future<void> dispose() => _changes.close();

  @override
  Stream<List<ProductReview>> watchForProduct(String productId) {
    late final StreamSubscription<String> subscription;
    final controller = StreamController<List<ProductReview>>(sync: true);
    controller.onListen = () {
      subscription = _changes.stream
          .where((changedProductId) => changedProductId == productId)
          .listen((_) => controller.add(_snapshot(productId)));
      controller.add(_snapshot(productId));
    };
    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }

  @override
  Future<ProductReview> submit({
    required Order order,
    required OrderItemSnapshot item,
    required int rating,
    String title = '',
    String comment = '',
  }) async {
    if (order.status != OrderStatus.delivered ||
        !order.items.any(
          (candidate) =>
              candidate.productId == item.productId &&
              candidate.variantId == item.variantId,
        )) {
      throw const ValidationException(
        'Only delivered purchase items can be reviewed.',
      );
    }
    if (rating < 1 || rating > 5) {
      throw const ValidationException('Rating must be between 1 and 5.');
    }
    final normalizedTitle = title.trim();
    final normalizedComment = comment.trim();
    if (normalizedTitle.length > 120 || normalizedComment.length > 1000) {
      throw const ValidationException('Review text is too long.');
    }
    final reviews = _reviewsByProduct.putIfAbsent(item.productId, () => []);
    if (reviews.any(
      (review) =>
          review.orderId == order.id && review.variantId == item.variantId,
    )) {
      throw const ConflictException('This purchase item was already reviewed.');
    }
    final review = ProductReview(
      id: _reviewId(order.id, item.productId, item.variantId),
      orderId: order.id,
      productId: item.productId,
      variantId: item.variantId,
      rating: rating,
      title: normalizedTitle,
      comment: normalizedComment,
      verifiedPurchase: true,
      createdAt: DateTime.now(),
    );
    reviews.insert(0, review);
    _changes.add(item.productId);
    return review;
  }

  @override
  Future<bool> hasReviewForOrderItem({
    required String orderId,
    required String productId,
    required String variantId,
  }) async {
    return (_reviewsByProduct[productId] ?? const <ProductReview>[]).any(
      (review) => review.orderId == orderId && review.variantId == variantId,
    );
  }

  ProductReview? latestForProduct(String productId) {
    final reviews = _reviewsByProduct[productId];
    return reviews == null || reviews.isEmpty ? null : reviews.first;
  }

  List<ProductReview> _snapshot(String productId) =>
      List.unmodifiable(_reviewsByProduct[productId] ?? const []);

  String _reviewId(String orderId, String productId, String variantId) {
    final candidate = [orderId, productId, variantId].join('_');
    return candidate.length > 512 ? candidate.substring(0, 512) : candidate;
  }
}
