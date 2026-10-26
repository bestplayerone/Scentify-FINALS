import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/checkout/domain/models/checkout_quote.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/orders/domain/models/order.dart';

abstract interface class CheckoutReviewProvider {
  Future<CheckoutQuote> createQuote({
    required String orderId,
    required String userId,
    required List<CartItem> selectedItems,
    required ShippingAddress shippingAddress,
    required DeliveryOption deliveryOption,
    required String paymentMethod,
    String? addressId,
  });
}

abstract interface class CashOnDeliveryOrderProvider {
  Future<Order> createCashOnDeliveryOrder({
    required String orderId,
    required String userId,
    required ShippingAddress shippingAddress,
    required DeliveryOption deliveryOption,
  });
}
