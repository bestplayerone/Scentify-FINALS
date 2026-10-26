import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/cart/domain/repositories/cart_repository.dart';

class SupabaseCartRepository implements CartRepository {
  SupabaseCartRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<Cart?> findByUserId(String userId) async {
    final rows = await _client.from('cart_items').select('quantity, variant_id').eq('user_id', userId);
    if (rows.isEmpty) return Cart(userId: userId, items: const [], updatedAt: DateTime.now());
    final ids = rows.map((row) => row['variant_id'] as String).toList();
    final variants = await _client.from('product_variants').select('id,label,price_centavos,product_id,products(id,name)').inFilter('id', ids);
    final byId = {for (final row in variants) row['id'] as String: row};
    final items = <CartItem>[];
    for (final row in rows) {
      final variant = byId[row['variant_id']];
      final product = variant?['products'];
      if (variant == null || product is! Map) continue;
      items.add(CartItem(productId: product['id'] as String, variantId: variant['id'] as String, productName: product['name'] as String, variantLabel: variant['label'] as String, unitPrice: Money((variant['price_centavos'] as num).toInt()), quantity: (row['quantity'] as num).toInt()));
    }
    return Cart(userId: userId, items: items, updatedAt: DateTime.now());
  }

  @override
  Stream<Cart?> watch(String userId) async* {
    yield await findByUserId(userId);
    yield* Stream.periodic(const Duration(seconds: 5)).asyncMap((_) => findByUserId(userId));
  }

  @override
  Future<void> save(Cart cart) async {
    await _client.from('carts').upsert({'user_id': cart.userId});
    await _client.from('cart_items').delete().eq('user_id', cart.userId);
    if (cart.items.isNotEmpty) {
      await _client.from('cart_items').insert([for (final item in cart.items) {'user_id': cart.userId, 'variant_id': item.variantId, 'quantity': item.quantity}]);
    }
  }

  @override
  Future<void> clear(String userId) async {
    await _client.from('cart_items').delete().eq('user_id', userId);
    await _client.from('carts').delete().eq('user_id', userId);
  }
}
