import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/features/wishlist/domain/repositories/wishlist_repository.dart';

class WishlistService {
  WishlistService(this._repository);

  final WishlistRepository _repository;

  Future<Set<String>> toggle({
    required String userId,
    required String productId,
  }) async {
    _requireValue(userId, 'A customer is required to update a wishlist.');
    _requireValue(productId, 'A product is required to update a wishlist.');
    final productIds = (await _repository.findByUserId(userId)).toSet();
    if (!productIds.add(productId)) {
      productIds.remove(productId);
    }
    await _repository.save(userId, productIds);
    return Set.unmodifiable(productIds);
  }

  void _requireValue(String value, String message) {
    if (value.trim().isEmpty) {
      throw ValidationException(message);
    }
  }
}
