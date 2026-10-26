import 'package:scentify/core/models/money.dart';

class PaymentRequest {
  PaymentRequest({
    required this.orderId,
    required this.amount,
    this.currency = 'PHP',
    this.paymentMethod = 'gcash',
    this.supportedMethods = const ['gcash', 'maya', 'card'],
    this.shippingAddress,
    this.deliveryOption,
  });

  final String orderId;
  final Money amount;
  final String currency;
  final String paymentMethod;
  final List<String> supportedMethods;
  final Map<String, dynamic>? shippingAddress;
  final Map<String, dynamic>? deliveryOption;
}

class PaymentSession {
  PaymentSession({
    required this.provider,
    required this.reference,
    this.checkoutUrl,
    this.orderCreatedOnServer = false,
  });

  final String provider;
  final String reference;
  final String? checkoutUrl;
  final bool orderCreatedOnServer;
}

abstract interface class PaymentGateway {
  Future<PaymentSession> createPayment(PaymentRequest request);
}
