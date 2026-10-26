class ProductReview {
  ProductReview({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.variantId,
    required this.rating,
    required this.title,
    required this.comment,
    required this.verifiedPurchase,
    required this.createdAt,
  }) {
    if (id.isEmpty || productId.isEmpty || variantId.isEmpty) {
      throw ArgumentError('Review identifiers must not be empty.');
    }
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(rating, 'rating', 'Use a rating from 1 to 5.');
    }
  }

  final String id;
  final String orderId;
  final String productId;
  final String variantId;
  final int rating;
  final String title;
  final String comment;
  final bool verifiedPurchase;
  final DateTime createdAt;
}
