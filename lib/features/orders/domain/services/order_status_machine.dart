import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/features/orders/domain/models/order.dart';

class OrderStatusMachine {
  static const _allowedTransitions = <OrderStatus, Set<OrderStatus>>{
    OrderStatus.pendingPayment: {OrderStatus.confirmed},
    OrderStatus.pendingConfirmation: {OrderStatus.confirmed},
    OrderStatus.confirmed: {OrderStatus.processing},
    OrderStatus.processing: {OrderStatus.packed},
    OrderStatus.packed: {OrderStatus.shipped},
    OrderStatus.shipped: {OrderStatus.delivered},
    OrderStatus.delivered: <OrderStatus>{},
    OrderStatus.cancelled: <OrderStatus>{},
  };

  bool canTransition(OrderStatus from, OrderStatus to) {
    return _allowedTransitions[from]?.contains(to) ?? false;
  }

  void assertTransition(OrderStatus from, OrderStatus to) {
    if (!canTransition(from, to)) {
      throw InvalidOrderTransitionException(
        'Cannot move an order from ${from.wireValue} to ${to.wireValue}.',
      );
    }
  }
}
