import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/services/checkout_review_provider.dart';
import 'package:scentify/features/checkout/domain/services/payment_gateway.dart';
import 'package:scentify/features/orders/data/supabase_order_repository.dart';
import 'package:scentify/features/orders/domain/models/order.dart';
import 'package:url_launcher/url_launcher.dart';

Map<String, dynamic> _address(ShippingAddress value) => {'fullName': value.fullName, 'phoneNumber': value.phoneNumber, 'addressLine1': value.addressLine1, 'barangay': value.barangay, 'city': value.city, 'province': value.province, 'postalCode': value.postalCode, 'notes': value.notes};
Map<String, dynamic> _delivery(DeliveryOption value) => {'id': value.id, 'name': value.name, 'feeCentavos': value.fee.centavos, 'estimatedDays': value.estimatedDays};

String _checkoutErrorMessage(String? code) => switch (code) {
  '23514' => 'Some items are no longer available in the requested quantity. Review your cart and try again.',
  '22023' => 'Review your delivery address and option, then try again.',
  '42501' => 'Your session expired. Sign in again before placing the order.',
  'INVALID_PAYMENT_CHANNEL' => 'GCash is temporarily unavailable. Please try again or choose another payment method.',
  'INVALID_AMOUNT' => 'The order total is invalid. Review your cart and try again.',
  _ => 'We could not start checkout. Your cart was not charged; please try again.',
};

class SupabaseXenditPaymentGateway implements PaymentGateway {
  SupabaseXenditPaymentGateway({SupabaseClient? client, Future<bool> Function(Uri)? openUrl}) : _client = client ?? Supabase.instance.client, _openUrl = openUrl ?? _open;
  final SupabaseClient _client;
  final Future<bool> Function(Uri) _openUrl;

  @override
  Future<PaymentSession> createPayment(PaymentRequest request) async {
    try {
      final result = await _client.functions.invoke('create-xendit-session', body: {'idempotencyKey': request.orderId, 'paymentMethod': request.paymentMethod, 'shippingAddress': request.shippingAddress, 'deliveryOption': request.deliveryOption});
      final data = Map<String, dynamic>.from(result.data as Map);
      final reference = data['reference'] as String?;
      final url = data['checkoutUrl'] as String?;
      final uri = url == null ? null : Uri.tryParse(url);
      if (reference == null || uri == null || !uri.hasScheme) throw const PaymentException('GCash checkout could not be opened. Please try again.');
      if (!await _openUrl(uri)) throw const PaymentException('GCash checkout could not be opened.');
      return PaymentSession(provider: 'xendit', reference: reference, checkoutUrl: url, orderCreatedOnServer: true);
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map && details['code'] is String ? details['code'] as String : null;
      throw PaymentException(_checkoutErrorMessage(code));
    } on PaymentException { rethrow; } on Object { throw const PaymentException('GCash checkout is temporarily unavailable. Please try again.'); }
  }

  static Future<bool> _open(Uri uri) => kIsWeb ? launchUrl(uri, webOnlyWindowName: '_self') : launchUrl(uri, mode: LaunchMode.externalApplication);
}

class SupabaseCashOnDeliveryOrderProvider implements CashOnDeliveryOrderProvider {
  SupabaseCashOnDeliveryOrderProvider({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<Order> createCashOnDeliveryOrder({required String orderId, required String userId, required ShippingAddress shippingAddress, required DeliveryOption deliveryOption}) async {
    try {
      await _client.rpc('create_cod_order', params: {'p_idempotency_key': orderId, 'p_shipping_address': _address(shippingAddress), 'p_delivery_option': _delivery(deliveryOption)});
      final order = await SupabaseOrderRepository(client: _client).findById(orderId);
      if (order == null) throw const PaymentException('The order could not be created. Please try again.');
      return order;
    } on PostgrestException catch (error) {
      debugPrint('COD checkout failed: ${error.code}');
      throw PaymentException(_checkoutErrorMessage(error.code));
    }
  }
}
