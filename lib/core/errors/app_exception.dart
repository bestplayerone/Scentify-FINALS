sealed class AppException implements Exception {
  const AppException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class ValidationException extends AppException {
  const ValidationException(String message)
    : super('validation_failed', message);
}

class NotFoundException extends AppException {
  const NotFoundException(String message) : super('not_found', message);
}

class AuthorizationException extends AppException {
  const AuthorizationException(String message)
    : super('not_authorized', message);
}

class ConflictException extends AppException {
  const ConflictException(String message) : super('conflict', message);
}

class InsufficientStockException extends AppException {
  const InsufficientStockException(String message)
    : super('insufficient_stock', message);
}

class InvalidOrderTransitionException extends AppException {
  const InvalidOrderTransitionException(String message)
    : super('invalid_order_transition', message);
}

class PaymentException extends AppException {
  const PaymentException(String message) : super('payment_failed', message);
}
