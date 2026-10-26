enum ScentifyPaymentMethod { gcash, maya, card }

extension ScentifyPaymentMethodWire on ScentifyPaymentMethod {
  String get wireValue => switch (this) {
    ScentifyPaymentMethod.gcash => 'gcash',
    ScentifyPaymentMethod.maya => 'maya',
    ScentifyPaymentMethod.card => 'card',
  };

  String get label => switch (this) {
    ScentifyPaymentMethod.gcash => 'GCash',
    ScentifyPaymentMethod.maya => 'Maya',
    ScentifyPaymentMethod.card => 'Card',
  };
}

ScentifyPaymentMethod? scentifyPaymentMethodFromWire(String? value) {
  for (final method in ScentifyPaymentMethod.values) {
    if (method.wireValue == value) return method;
  }
  return null;
}

class OrderPaymentSnapshot {
  const OrderPaymentSnapshot({
    required this.method,
    required this.status,
    required this.provider,
    this.reference,
  });

  factory OrderPaymentSnapshot.fromMap(Map<String, dynamic> data) {
    final wireMethod = data['paymentMethod'];
    final method = wireMethod is String
        ? scentifyPaymentMethodFromWire(wireMethod)
        : null;
    final status = data['paymentStatus'];
    final provider = data['paymentProvider'];
    final reference = data['paymentReference'];
    if (method == null ||
        status is! String ||
        provider is! String ||
        (reference != null && reference is! String)) {
      throw const FormatException('The order payment fields are invalid.');
    }
    return OrderPaymentSnapshot(
      method: method,
      status: status,
      provider: provider,
      reference: reference as String?,
    );
  }

  final ScentifyPaymentMethod method;
  final String status;
  final String provider;
  final String? reference;

  Map<String, dynamic> toMap() => {
    'paymentMethod': method.wireValue,
    'paymentStatus': status,
    'paymentProvider': provider,
    'paymentReference': reference,
  };
}
