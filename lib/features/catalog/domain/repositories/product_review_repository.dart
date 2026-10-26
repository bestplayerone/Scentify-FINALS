import 'package:scentify/features/catalog/domain/models/product_review.dart';
import 'package:scentify/features/orders/domain/models/order.dart';

abstract interface class ProductReviewRepository {
  Stream<List<ProductReview>> watchForProduct(String productId);

  Future<ProductReview> submit({
    required Order order,
    required OrderItemSnapshot item,
    required int rating,
    String title = '',
    String comment = '',
  });

  Future<bool> hasReviewForOrderItem({
    required String orderId,
    required String productId,
    required String variantId,
  });
}
