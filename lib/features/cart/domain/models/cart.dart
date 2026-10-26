import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/core/models/money.dart';

class CartItem {
  CartItem({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantLabel,
    required this.unitPrice,
    required this.quantity,
  }) {
    if (quantity < 1) {
      throw const ValidationException(
        'Cart item quantity must be at least one.',
      );
    }
  }

  final String productId;
  final String variantId;
  final String productName;
  final String variantLabel;
  final Money unitPrice;
  final int quantity;

  Money get lineTotal => unitPrice * quantity;

  CartItem copyWith({
    String? productId,
    String? variantId,
    String? productName,
    String? variantLabel,
    Money? unitPrice,
    int? quantity,
  }) {
    return CartItem(
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      productName: productName ?? this.productName,
      variantLabel: variantLabel ?? this.variantLabel,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
    );
  }
}

class Cart {
  Cart({
    required this.userId,
    required List<CartItem> items,
    required this.updatedAt,
  }) : items = List.unmodifiable(items);

  final String userId;
  final List<CartItem> items;
  final DateTime updatedAt;

  Money get subtotal =>
      items.fold(Money(0), (total, item) => total + item.lineTotal);

  CartItem? itemFor(String productId, String variantId) {
    for (final item in items) {
      if (item.productId == productId && item.variantId == variantId) {
        return item;
      }
    }
    return null;
  }

  Cart copyWith({String? userId, List<CartItem>? items, DateTime? updatedAt}) {
    return Cart(
      userId: userId ?? this.userId,
      items: items ?? this.items,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
