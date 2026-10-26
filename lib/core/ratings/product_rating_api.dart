import 'package:cloud_functions/cloud_functions.dart';
import 'package:scentify/core/orders/my_purchases_api.dart';

class ProductRatingApi {
  ProductRatingApi({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: scentifyFunctionsRegion);

  final FirebaseFunctions _functions;

  Future<ProductRatingResult> submit({
    required String orderId,
    required String productId,
    required String variantId,
    required int rating,
    String? title,
    String? comment,
  }) async {
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(rating, 'rating', 'Use a rating from 1 to 5.');
    }
    final result = await _functions
        .httpsCallable('submitProductRating')
        .call<Map<String, dynamic>>({
          'orderId': orderId,
          'productId': productId,
          'variantId': variantId,
          'rating': rating,
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
          if (comment != null && comment.trim().isNotEmpty)
            'comment': comment.trim(),
        });
    return ProductRatingResult.fromMap(result.data);
  }
}

class ProductRatingResult {
  const ProductRatingResult({
    required this.reviewId,
    required this.productId,
    required this.variantId,
    required this.rating,
    required this.title,
    required this.comment,
    required this.verifiedPurchase,
    required this.createdAt,
  });

  factory ProductRatingResult.fromMap(Map<String, dynamic> data) {
    final reviewId = data['reviewId'];
    final productId = data['productId'];
    final variantId = data['variantId'];
    final rating = data['rating'];
    final title = data['title'];
    final comment = data['comment'];
    final verifiedPurchase = data['verifiedPurchase'];
    final createdAt = data['createdAt'];
    if (reviewId is! String ||
        productId is! String ||
        variantId is! String ||
        rating is! int ||
        title is! String ||
        comment is! String ||
        verifiedPurchase is! bool ||
        createdAt is! String) {
      throw const FormatException('The product rating response is invalid.');
    }
    final parsedDate = DateTime.tryParse(createdAt);
    if (parsedDate == null) {
      throw const FormatException('The product rating timestamp is invalid.');
    }
    return ProductRatingResult(
      reviewId: reviewId,
      productId: productId,
      variantId: variantId,
      rating: rating,
      title: title,
      comment: comment,
      verifiedPurchase: verifiedPurchase,
      createdAt: parsedDate,
    );
  }

  final String reviewId;
  final String productId;
  final String variantId;
  final int rating;
  final String title;
  final String comment;
  final bool verifiedPurchase;
  final DateTime createdAt;
}
