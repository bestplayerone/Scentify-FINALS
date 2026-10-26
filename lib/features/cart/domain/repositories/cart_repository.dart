import 'package:scentify/features/cart/domain/models/cart.dart';

abstract interface class CartRepository {
  Future<Cart?> findByUserId(String userId);

  Stream<Cart?> watch(String userId);

  Future<void> save(Cart cart);

  Future<void> clear(String userId);
}
