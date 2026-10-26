import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';

/// A server-calculated checkout snapshot that is used for payment and order
/// creation without recalculating customer-visible prices on the client.
class CheckoutQuote {
  CheckoutQuote({
    required this.orderId,
    required this.userId,
    required List<CheckoutQuoteItem> items,
    required this.shippingAddress,
    required this.deliveryOption,
    required this.subtotal,
    required this.total,
  }) : items = List.unmodifiable(items) {
    if (orderId.isEmpty || userId.isEmpty || this.items.isEmpty) {
      throw const FormatException('The checkout quote is incomplete.');
    }
    final itemSubtotal = this.items.fold(
      Money(0),
      (sum, item) => sum + item.lineTotal,
    );
    if (subtotal != itemSubtotal || total != subtotal + deliveryOption.fee) {
      throw const FormatException(
        'The checkout quote totals are inconsistent.',
      );
    }
  }

  final String orderId;
  final String userId;
  final List<CheckoutQuoteItem> items;
  final ShippingAddress shippingAddress;
  final DeliveryOption deliveryOption;
  final Money subtotal;
  final Money total;
}

class CheckoutQuoteItem {
  CheckoutQuoteItem({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantLabel,
    required this.unitPrice,
    required this.quantity,
  }) {
    if (productId.isEmpty ||
        variantId.isEmpty ||
        productName.isEmpty ||
        variantLabel.isEmpty ||
        quantity < 1) {
      throw const FormatException('The reviewed order item is invalid.');
    }
  }

  final String productId;
  final String variantId;
  final String productName;
  final String variantLabel;
  final Money unitPrice;
  final int quantity;

  Money get lineTotal => unitPrice * quantity;
}
