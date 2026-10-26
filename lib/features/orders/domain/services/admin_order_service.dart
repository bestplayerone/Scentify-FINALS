import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';
import 'package:scentify/features/orders/domain/models/order.dart';
import 'package:scentify/features/orders/domain/repositories/order_repository.dart';
import 'package:scentify/features/orders/domain/services/order_service.dart';
import 'package:scentify/features/orders/domain/services/order_status_machine.dart';

/// Role-guarded order operations used by the admin dashboard.
class AdminOrderService {
  AdminOrderService(
    OrderRepository repository, {
    DateTime Function()? clock,
    OrderStatusMachine? statusMachine,
  }) : _orderService = OrderService(
         repository,
         clock: clock,
         statusMachine: statusMachine,
       );

  final OrderService _orderService;

  Future<Order> transitionStatus({
    required UserProfile actor,
    required String orderId,
    required OrderStatus nextStatus,
  }) {
    if (!actor.isAdmin) {
      throw const AuthorizationException('Only admins can update orders.');
    }
    return _orderService.transitionStatus(
      orderId: orderId,
      nextStatus: nextStatus,
      actorId: actor.id,
    );
  }
}
