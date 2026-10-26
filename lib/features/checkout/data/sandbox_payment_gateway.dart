import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/features/checkout/domain/services/payment_gateway.dart';

class SandboxPaymentGateway implements PaymentGateway {
  SandboxPaymentGateway({this.shouldFail = false});

  final bool shouldFail;
  int _sequence = 0;

  @override
  Future<PaymentSession> createPayment(PaymentRequest request) async {
    if (shouldFail) {
      throw const PaymentException('The sandbox payment was declined.');
    }
    _sequence++;
    return PaymentSession(
      provider: 'sandbox',
      reference:
          'sandbox-${request.paymentMethod}-${request.orderId}-$_sequence',
    );
  }
}
