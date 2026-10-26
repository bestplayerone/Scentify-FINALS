import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/cart/domain/repositories/cart_repository.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/catalog/domain/repositories/catalog_repository.dart';

class CartService {
  CartService({
    required this.cartRepository,
    required this.catalogRepository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CartRepository cartRepository;
  final CatalogRepository catalogRepository;
  final DateTime Function() _clock;

  Future<Cart> getCart(String userId) async {
    return await cartRepository.findByUserId(userId) ??
        Cart(userId: userId, items: const [], updatedAt: _clock());
  }

  Future<Cart> addItem({
    required String userId,
    required String productId,
    required String variantId,
    int quantity = 1,
  }) async {
    _validateQuantity(quantity);
    final variantData = await _loadVariant(productId, variantId);
    final cart = await getCart(userId);
    final existing = cart.itemFor(productId, variantId);
    final requestedQuantity = (existing?.quantity ?? 0) + quantity;
    _ensureStock(variantData.variant, requestedQuantity);

    final item = CartItem(
      productId: productId,
      variantId: variantId,
      productName: variantData.product.name,
      variantLabel: variantData.variant.label,
      unitPrice: variantData.variant.price,
      quantity: requestedQuantity,
    );
    final items = [
      for (final current in cart.items)
        if (current.productId != productId || current.variantId != variantId)
          current,
      item,
    ];
    return _save(cart.copyWith(items: items, updatedAt: _clock()));
  }

  Future<Cart> setQuantity({
    required String userId,
    required String productId,
    required String variantId,
    required int quantity,
  }) async {
    _validateQuantity(quantity);
    final variantData = await _loadVariant(productId, variantId);
    _ensureStock(variantData.variant, quantity);
    final cart = await getCart(userId);
    if (cart.itemFor(productId, variantId) == null) {
      throw const NotFoundException('The cart item does not exist.');
    }

    final item = CartItem(
      productId: productId,
      variantId: variantId,
      productName: variantData.product.name,
      variantLabel: variantData.variant.label,
      unitPrice: variantData.variant.price,
      quantity: quantity,
    );
    final items = [
      for (final current in cart.items)
        if (current.productId != productId || current.variantId != variantId)
          current,
      item,
    ];
    return _save(cart.copyWith(items: items, updatedAt: _clock()));
  }

  Future<Cart> removeItem({
    required String userId,
    required String productId,
    required String variantId,
  }) async {
    final cart = await getCart(userId);
    final items = cart.items
        .where(
          (item) => item.productId != productId || item.variantId != variantId,
        )
        .toList();
    return _save(cart.copyWith(items: items, updatedAt: _clock()));
  }

  Future<void> clear(String userId) => cartRepository.clear(userId);

  Future<Cart> _save(Cart cart) async {
    await cartRepository.save(cart);
    return cart;
  }

  Future<({Perfume product, PerfumeVariant variant})> _loadVariant(
    String productId,
    String variantId,
  ) async {
    final product = await catalogRepository.findById(productId);
    if (product == null || !product.isPublished) {
      throw const NotFoundException('The perfume is not available.');
    }
    final variant = product.variantById(variantId);
    if (variant == null) {
      throw const NotFoundException('The perfume variant does not exist.');
    }
    return (product: product, variant: variant);
  }

  void _validateQuantity(int quantity) {
    if (quantity < 1) {
      throw const ValidationException('Quantity must be at least one.');
    }
  }

  void _ensureStock(PerfumeVariant variant, int requestedQuantity) {
    if (requestedQuantity > variant.stock) {
      throw InsufficientStockException(
        'Only ${variant.stock} unit(s) of ${variant.label} are available.',
      );
    }
  }
}
