import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/core/orders/my_purchases_api.dart';
import 'package:scentify/features/checkout/domain/services/payment_gateway.dart';
import 'package:url_launcher/url_launcher.dart';

/// Starts a PayMongo Hosted Checkout session through a trusted backend.
///
/// The PayMongo secret key is intentionally not part of this app. The callable
/// function creates the session and returns only the hosted checkout URL.
class PayMongoPaymentGateway implements PaymentGateway {
  PayMongoPaymentGateway({
    FirebaseFunctions? functions,
    Future<bool> Function(Uri uri)? openUrl,
  }) : _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: scentifyFunctionsRegion),
       _openUrl = openUrl ?? _openExternalUrl;

  final FirebaseFunctions _functions;
  final Future<bool> Function(Uri uri) _openUrl;

  @override
  Future<PaymentSession> createPayment(PaymentRequest request) async {
    try {
      final result = await _functions
          .httpsCallable('createPayMongoCheckoutSession')
          .call<Map<String, dynamic>>({
            'orderId': request.orderId,
            'amountCentavos': request.amount.centavos,
            'currency': request.currency,
            'paymentMethod': request.paymentMethod,
            'supportedMethods': request.supportedMethods,
          });
      final data = result.data;
      final reference = data['reference'] as String?;
      final checkoutUrl = data['checkoutUrl'] as String?;
      if (reference == null || checkoutUrl == null) {
        throw const PaymentException(
          'The payment provider returned an incomplete checkout session.',
        );
      }
      final uri = Uri.tryParse(checkoutUrl);
      if (uri == null || !uri.hasScheme) {
        throw const PaymentException(
          'The payment provider returned an invalid checkout URL.',
        );
      }
      if (!await _openUrl(uri)) {
        throw const PaymentException('Unable to open the payment checkout.');
      }
      return PaymentSession(
        provider: 'paymongo',
        reference: reference,
        checkoutUrl: checkoutUrl,
        orderCreatedOnServer: data['orderCreatedOnServer'] == true,
      );
    } on PaymentException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw PaymentException(
        error.message ?? 'The payment provider is temporarily unavailable.',
      );
    } on Object {
      throw const PaymentException(
        'The payment provider is temporarily unavailable.',
      );
    }
  }

  static Future<bool> _openExternalUrl(Uri uri) {
    if (kIsWeb) {
      return launchUrl(uri, webOnlyWindowName: '_self');
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
